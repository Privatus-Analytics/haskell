-- | Helpers for <https://hackage.haskell.org/package/lucid lucid>.
--
-- > import PrivatusAnalytics
-- > import PrivatusAnalytics.Lucid
-- >
-- > page :: Config -> Html ()
-- > page config = html_ $ do
-- >   head_ $ do
-- >     title_ "My app"
-- >     analyticsTag_ config defaultTagOptions
-- >   body_ $ do
-- >     button_ ([class_ "btn"] <> eventAttrs_ "Report exported" [("format", "csv")]) "Export"
-- >     a_ (href_ "/pricing" : clickAttr_ "pricing.cta") "See plans"
module PrivatusAnalytics.Lucid
  ( analyticsTag_,
    eventAttrs_,
    clickAttr_,
  )
where

import Data.Text (Text)
import Lucid.Base (Attribute, HtmlT, makeAttribute, toHtmlRaw)
import PrivatusAnalytics.Attributes (clickData, eventData)
import PrivatusAnalytics.Config (Config)
import PrivatusAnalytics.Prop (Prop)
import PrivatusAnalytics.Tag (TagOptions, analyticsTag)

-- | The script tag. Without a site id, or outside the enabled environments,
-- it prints only the queue stub (when 'PrivatusAnalytics.Config.configQueueStub'
-- is on) or nothing.
analyticsTag_ :: (Monad m) => Config -> TagOptions -> HtmlT m ()
analyticsTag_ config options = toHtmlRaw (analyticsTag config options)

-- | Custom event attributes for any element. Lucid escapes the values. On a
-- @form_@ the event is sent when the form is submitted.
eventAttrs_ :: Text -> [Prop] -> [Attribute]
eventAttrs_ name props = map (uncurry makeAttribute) (eventData name props)

-- | The click map name attribute, or @[]@ when the name is not valid.
clickAttr_ :: Text -> [Attribute]
clickAttr_ name = map (uncurry makeAttribute) (clickData name)
