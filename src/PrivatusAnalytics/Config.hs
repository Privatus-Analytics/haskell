{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Settings for the tracking script.
--
-- Start from 'defaultConfig' (pure) or 'loadConfig' (reads the environment
-- variables), then change what you need with record update syntax:
--
-- > config <- loadConfig
-- > let config' = config { configModules = Just ["engage", "auto"] }
module PrivatusAnalytics.Config
  ( -- * Settings
    Config (..),
    Spa (..),
    spaText,
    parseSpa,
    defaultConfig,
    defaultScriptHost,

    -- * The environment
    loadConfig,
    fromEnvironment,

    -- * Resolved values
    siteId,
    scriptHost,
    isEnabled,
  )
where

import Control.Applicative ((<|>))
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Network.Wai qualified as Wai
import PrivatusAnalytics.Prop (Prop)
import System.Environment (lookupEnv)

-- | Single-page app mode, the @data-spa@ attribute. 'SpaAuto' is the tracker
-- default and is not printed.
data Spa = SpaAuto | SpaHistory | SpaHash | SpaOff
  deriving stock (Eq, Show, Enum, Bounded)

-- | @auto@, @history@, @hash@ or @off@.
spaText :: Spa -> Text
spaText = \case
  SpaAuto -> "auto"
  SpaHistory -> "history"
  SpaHash -> "hash"
  SpaOff -> "off"

-- | Reads @auto@, @history@, @hash@ or @off@. Anything else gives 'Nothing'.
parseSpa :: Text -> Maybe Spa
parseSpa text = lookup (T.toLower (T.strip text)) [(spaText s, s) | s <- [minBound .. maxBound]]

-- | Every setting. Only the site id is needed.
data Config = Config
  { -- | The site id (starts with @pa_@), the @data-site@ attribute. Nothing
    -- prints without it. 'fromEnvironment' fills it from @PRIVATUS_SITE_ID@.
    configSiteId :: Maybe Text,
    -- | Origin that serves @\/js\/pa.js@. Default @https:\/\/privatusstats.com@.
    -- 'fromEnvironment' fills it from @PRIVATUS_SCRIPT_HOST@.
    configScriptHost :: Maybe Text,
    -- | Tracker modules, the @data-modules@ attribute. 'Nothing' keeps the
    -- tracker default. @Just []@ loads none.
    configModules :: Maybe [Text],
    -- | Path globs the tracker never counts, the @data-exclude@ attribute.
    configExcludedPaths :: [Text],
    -- | Hostnames to count, the @data-domains@ attribute. @[]@ counts every host.
    configDomains :: [Text],
    -- | The @data-spa@ attribute. 'Nothing' keeps the tracker default.
    configSpa :: Maybe Spa,
    -- | 'True' turns off the automatic pageview (@data-manual="true"@).
    configManual :: Bool,
    -- | The name of the environment the app runs in, like @production@.
    -- 'fromEnvironment' fills it from @PRIVATUS_ENV@, then @APP_ENV@.
    configEnvironment :: Maybe Text,
    -- | Environments that get the tag. Used when 'configEnabled' is 'Nothing'.
    configEnabledEnvironments :: [Text],
    -- | @Just True@ or @Just False@ forces the tag on or off in every
    -- environment. 'Nothing' uses 'configEnabledEnvironments'.
    configEnabled :: Maybe Bool,
    -- | Any other @data-*@ attribute, like @[("data-mask", "\/orders\/*->\/orders\/:id")]@.
    configExtraAttributes :: [(Text, Text)],
    -- | Page props sent with every pageview and event, like
    -- @[("plan", "pro")]@. Never put names, emails, user ids or anything
    -- else that points to one person here.
    configProps :: [Prop],
    -- | Page props worked out for each request, merged over 'configProps'.
    -- Used by the middleware and by 'PrivatusAnalytics.Tag.analyticsTagFor'.
    -- It runs only when the tag prints.
    configRequestProps :: Maybe (Wai.Request -> IO [Prop]),
    -- | 'True' prints the tracker's queue stub first, so @privatus.track@
    -- calls made before the tracker loads are kept.
    configQueueStub :: Bool,
    -- | The Content Security Policy nonce for a request, used by the
    -- middleware. When this gives 'Nothing', the middleware reads the nonce
    -- from the response's @Content-Security-Policy@ header.
    configNonceFor :: Wai.Request -> Maybe Text
  }

-- | @https:\/\/privatusstats.com@
defaultScriptHost :: Text
defaultScriptHost = "https://privatusstats.com"

-- | Every setting at its default. Reads no environment variables.
defaultConfig :: Config
defaultConfig =
  Config
    { configSiteId = Nothing,
      configScriptHost = Nothing,
      configModules = Nothing,
      configExcludedPaths = [],
      configDomains = [],
      configSpa = Nothing,
      configManual = False,
      configEnvironment = Nothing,
      configEnabledEnvironments = ["production"],
      configEnabled = Nothing,
      configExtraAttributes = [],
      configProps = [],
      configRequestProps = Nothing,
      configQueueStub = False,
      configNonceFor = const Nothing
    }

-- | 'defaultConfig' with the environment variables read in.
loadConfig :: IO Config
loadConfig = fromEnvironment defaultConfig

-- | Fills the settings you did not set from the environment:
--
-- * 'configSiteId' from @PRIVATUS_SITE_ID@
-- * 'configScriptHost' from @PRIVATUS_SCRIPT_HOST@
-- * 'configEnvironment' from @PRIVATUS_ENV@, or else @APP_ENV@
--
-- A value you set yourself always wins.
fromEnvironment :: Config -> IO Config
fromEnvironment config = do
  envSite <- env "PRIVATUS_SITE_ID"
  envHost <- env "PRIVATUS_SCRIPT_HOST"
  envName <- env "PRIVATUS_ENV"
  appEnv <- env "APP_ENV"
  pure
    config
      { configSiteId = orElse (configSiteId config) envSite,
        configScriptHost = orElse (configScriptHost config) envHost,
        configEnvironment = orElse (configEnvironment config) (orElse envName appEnv)
      }
  where
    env name = (>>= nonEmpty . T.pack) <$> lookupEnv name
    orElse own fallback = (own >>= nonEmpty) <|> fallback

nonEmpty :: Text -> Maybe Text
nonEmpty text = let t = T.strip text in if T.null t then Nothing else Just t

-- | The site id, trimmed. 'Nothing' when it is missing or blank.
siteId :: Config -> Maybe Text
siteId config = configSiteId config >>= nonEmpty

-- | The script host without a trailing slash.
scriptHost :: Config -> Text
scriptHost config = dropSlash (fromMaybe defaultScriptHost (configScriptHost config >>= nonEmpty))
  where
    dropSlash t = fromMaybe t (T.stripSuffix "/" t)

-- | Whether the tag should print in this environment. 'configEnabled' wins
-- when set. Otherwise only the environments in 'configEnabledEnvironments'
-- (by default only @production@) get the tag.
isEnabled :: Config -> Bool
isEnabled config = case configEnabled config of
  Just forced -> forced
  Nothing -> maybe False (`elem` configEnabledEnvironments config) (configEnvironment config)
