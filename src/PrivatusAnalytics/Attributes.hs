{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Data attributes the tracker reads for custom events and click maps.
--
-- These print in every environment, even when the tag is off. They do nothing
-- without the tracker, so your pages look the same in development and
-- production.
module PrivatusAnalytics.Attributes
  ( -- * Custom events
    eventData,
    eventAttrs,

    -- * Click maps
    clickData,
    clickAttr,
    validClickName,

    -- * Limits
    maxName,
  )
where

import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Maybe (mapMaybe)
import Data.Scientific (FPFormat (..), Scientific, base10Exponent, formatScientific, isInteger, toBoundedInteger)
import Data.Text (Text)
import Data.Text qualified as T
import PrivatusAnalytics.Html (renderAttrs)
import PrivatusAnalytics.Prop

-- | Event names are cut to this many characters.
maxName :: Int
maxName = 120

-- | The attributes for a custom event, as name and value pairs (not escaped
-- yet). Use this with template engines that take an attribute list, like
-- hamlet's @*{...}@.
--
-- >>> eventData "Export CSV" [("format", "csv")]
-- [("data-privatus-event","Export CSV"),("data-privatus-prop-format","csv")]
--
-- The name is trimmed and cut to 120 characters. An empty name gives @[]@.
-- Prop keys are cleaned with 'normalizeKey', at most 30 props are kept, null
-- values are dropped and values are cut to 500 characters.
eventData :: Text -> [Prop] -> [(Text, Text)]
eventData rawName props
  | T.null name = []
  | otherwise =
      ("data-privatus-event", name)
        : [("data-privatus-prop-" <> key, textValue value) | (key, value) <- normalizeProps props]
  where
    name = T.strip (T.take maxName (T.strip rawName))

-- | The attributes for a custom event as escaped HTML, to put inside a tag:
--
-- > <button data-privatus-event="Export CSV" data-privatus-prop-format="csv">
--
-- On a @\<form\>@ the event is sent when the form is submitted.
eventAttrs :: Text -> [Prop] -> Text
eventAttrs name props = renderAttrs (eventData name props)

-- | @[("data-privatus-click", name)]@, or @[]@ when the name is not valid.
clickData :: Text -> [(Text, Text)]
clickData name
  | validClickName name = [("data-privatus-click", name)]
  | otherwise = []

-- | The click map name as escaped HTML: @data-privatus-click="pricing.cta"@.
-- Gives @""@ when the name is not valid.
clickAttr :: Text -> Text
clickAttr = renderAttrs . clickData

-- | Whether a click map name is valid: letters, digits and @_ . : -@ only,
-- 1 to 100 characters.
validClickName :: Text -> Bool
validClickName name = len >= 1 && len <= 100 && T.all ok name
  where
    len = T.length name
    ok c =
      isAsciiLower c
        || isAsciiUpper c
        || isDigit c
        || c `elem` ("_.:-" :: String)

-- Values become text: booleans as true and false, numbers as written, lists
-- joined with commas.
textValue :: PropValue -> Text
textValue = T.take maxValue . go
  where
    go = \case
      PropText t -> t
      PropBool True -> "true"
      PropBool False -> "false"
      PropNumber n -> numberText n
      PropList xs -> T.intercalate "," (mapMaybe item xs)
      PropNull -> ""
    item PropNull = Nothing
    item v = Just (go v)

numberText :: Scientific -> Text
numberText n
  | isInteger n, Just i <- toBoundedInteger n :: Maybe Int = T.pack (show i)
  | abs (base10Exponent n) < 50 = T.pack (formatScientific Fixed Nothing n)
  | otherwise = T.pack (formatScientific Generic Nothing n)
