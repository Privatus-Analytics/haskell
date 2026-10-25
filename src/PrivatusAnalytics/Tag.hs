{-# LANGUAGE OverloadedStrings #-}

-- | Builds the script tag.
--
-- Before the tracker tag it can also print the queue stub
-- ('configQueueStub') and the page props script (props), each with the
-- Content Security Policy nonce when there is one.
--
-- To change a setting for one page, pass a changed config:
--
-- > analyticsTag config { configModules = Just ["engage", "auto"] } defaultTagOptions
module PrivatusAnalytics.Tag
  ( -- * Options for one call
    TagOptions (..),
    defaultTagOptions,

    -- * Rendering
    analyticsTag,
    analyticsTagBS,
    analyticsTagFor,
    shouldRender,

    -- * Building blocks
    tagAttributes,
    queueStub,
    propsFunction,
  )
where

import Data.ByteString (ByteString)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.Wai qualified as Wai
import PrivatusAnalytics.Config
import PrivatusAnalytics.Html (escapeHtml)
import PrivatusAnalytics.PageProps (pagePropsJson)
import PrivatusAnalytics.Prop (Prop, mergeProps)

-- | Things that belong to one page or one request.
data TagOptions = TagOptions
  { -- | The Content Security Policy nonce. Added to every script printed.
    tagNonce :: Maybe Text,
    -- | Page props for this page, merged over the configured ones. A
    -- 'PrivatusAnalytics.Prop.PropNull' value removes a configured prop.
    tagProps :: [Prop]
  }
  deriving stock (Eq, Show)

-- | No nonce and no extra props.
defaultTagOptions :: TagOptions
defaultTagOptions = TagOptions {tagNonce = Nothing, tagProps = []}

-- | The name of the page props function: @privatusPageProps@.
propsFunction :: Text
propsFunction = "privatusPageProps"

-- | The official queue stub. It keeps @privatus.track@ calls made before the
-- tracker loads, and the tracker sends them once it is ready.
queueStub :: Text
queueStub =
  "window.privatus=window.privatus||{q:[]};['track','pageview','props','optOut','optIn','ready']"
    <> ".forEach(function(m){window.privatus[m]=window.privatus[m]||function(){window.privatus.q.push("
    <> "[m,Array.prototype.slice.call(arguments)])}})"

-- | Whether a tag prints at all: there is a site id and the tag is enabled.
shouldRender :: Config -> Bool
shouldRender config = isJust (siteId config) && isEnabled config

-- | The tag as text, or @""@ when no tag should print. Uses 'configProps'
-- and 'tagProps', but not 'configRequestProps' (see 'analyticsTagFor').
--
-- >>> analyticsTag defaultConfig { configSiteId = Just "pa_X", configEnabled = Just True } defaultTagOptions
-- "<script defer src=\"https://privatusstats.com/js/pa.js\" data-site=\"pa_X\"></script>"
analyticsTag :: Config -> TagOptions -> Text
analyticsTag config options = render config options (configProps config)

-- | 'analyticsTag' as UTF-8 bytes.
analyticsTagBS :: Config -> TagOptions -> ByteString
analyticsTagBS config options = TE.encodeUtf8 (analyticsTag config options)

-- | Like 'analyticsTag', and also runs 'configRequestProps' for this
-- request. The props are merged in this order: 'configProps', then the
-- request props, then 'tagProps'. The request props do not run when no tag
-- prints.
analyticsTagFor :: Config -> TagOptions -> Wai.Request -> IO Text
analyticsTagFor config options request
  | not (shouldRender config) = pure ""
  | otherwise = do
      fromRequest <- maybe (pure []) ($ request) (configRequestProps config)
      pure (render config options (mergeProps (configProps config) fromRequest))

render :: Config -> TagOptions -> [Prop] -> Text
render config options baseProps
  | not (shouldRender config) = ""
  | otherwise = T.intercalate "\n" (stub <> propsScript <> [scriptTag attrs])
  where
    json = pagePropsJson (mergeProps baseProps (tagProps options))
    stub = [inline queueStub | configQueueStub config]
    propsScript = maybe [] (\j -> [inline ("window." <> propsFunction <> "=function(){return " <> j <> "}")]) json
    attrs = tagAttributes config options `with` maybe [] (const [("data-props", Just propsFunction)]) json
    inline code = case tagNonce options of
      Just nonce -> "<script nonce=\"" <> escapeHtml nonce <> "\">" <> code <> "</script>"
      Nothing -> "<script>" <> code <> "</script>"

-- | The attributes of the tracker tag, in order. 'Nothing' is a bare
-- attribute like @defer@.
tagAttributes :: Config -> TagOptions -> [(Text, Maybe Text)]
tagAttributes config options =
  base
    `with` lists
    `with` spa
    `with` [("data-manual", Just "true") | configManual config]
    `with` [(name, Just value) | (name, value) <- configExtraAttributes config]
    `with` maybe [] (\n -> [("nonce", Just n)]) (tagNonce options)
  where
    base =
      [ ("defer", Nothing),
        ("src", Just (scriptHost config <> "/js/pa.js")),
        ("data-site", siteId config)
      ]
    lists =
      maybe [] (\ms -> [("data-modules", Just (joined ms))]) (configModules config)
        <> nonEmptyList "data-exclude" (configExcludedPaths config)
        <> nonEmptyList "data-domains" (configDomains config)
    nonEmptyList name values = [(name, Just (joined values)) | not (null (clean values))]
    spa = case configSpa config of
      Just mode | mode /= SpaAuto -> [("data-spa", Just (spaText mode))]
      _ -> []

-- Splits on commas, trims and drops empty items, then joins with commas.
joined :: [Text] -> Text
joined = T.intercalate "," . clean

clean :: [Text] -> [Text]
clean = filter (not . T.null) . map T.strip . concatMap (T.splitOn ",")

-- Adds attributes. A name that is already there keeps its place and gets
-- the new value.
with :: [(Text, a)] -> [(Text, a)] -> [(Text, a)]
with = foldl add
  where
    add acc (name, value)
      | any ((== name) . fst) acc = [(n, if n == name then value else v) | (n, v) <- acc]
      | otherwise = acc <> [(name, value)]

infixl 5 `with`

scriptTag :: [(Text, Maybe Text)] -> Text
scriptTag attrs = "<script " <> T.unwords (map attr attrs) <> "></script>"
  where
    attr (name, Nothing) = name
    attr (name, Just value) = name <> "=\"" <> escapeHtml value <> "\""
