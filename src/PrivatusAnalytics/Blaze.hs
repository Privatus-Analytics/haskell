-- | Helpers for <https://hackage.haskell.org/package/blaze-html blaze-html>
-- (and so for Yesod's hamlet, which builds blaze-html).
--
-- > import PrivatusAnalytics
-- > import PrivatusAnalytics.Blaze
-- > import Text.Blaze.Html5 ((!))
-- > import Text.Blaze.Html5 qualified as H
-- > import Text.Blaze.Html5.Attributes qualified as A
-- >
-- > page :: Config -> H.Html
-- > page config = H.docTypeHtml $ do
-- >   H.head $ do
-- >     H.title "My app"
-- >     analyticsTagHtml config defaultTagOptions
-- >   H.body $ do
-- >     H.button ! eventAttribute "Report exported" [("format", "csv")] $ "Export"
-- >     H.a ! A.href "/pricing" ! clickAttribute "pricing.cta" $ "See plans"
module PrivatusAnalytics.Blaze
  ( analyticsTagHtml,
    eventAttribute,
    clickAttribute,
  )
where

import Data.Text (Text)
import PrivatusAnalytics.Attributes (clickData, eventData)
import PrivatusAnalytics.Config (Config)
import PrivatusAnalytics.Prop (Prop)
import PrivatusAnalytics.Tag (TagOptions, analyticsTag)
import Text.Blaze (Attribute, customAttribute, preEscapedToMarkup, textTag, toValue)
import Text.Blaze.Html (Html)

-- | The script tag. Prints nothing without a site id, or outside the enabled
-- environments.
analyticsTagHtml :: Config -> TagOptions -> Html
analyticsTagHtml config options = preEscapedToMarkup (analyticsTag config options)

-- | Custom event attributes, to add with @!@. Blaze escapes the values. On
-- a @form@ the event is sent when the form is submitted.
eventAttribute :: Text -> [Prop] -> Attribute
eventAttribute name props = attributes (eventData name props)

-- | The click map name attribute, or nothing when the name is not valid.
clickAttribute :: Text -> Attribute
clickAttribute = attributes . clickData

attributes :: [(Text, Text)] -> Attribute
attributes = foldMap (\(name, value) -> customAttribute (textTag name) (toValue value))
