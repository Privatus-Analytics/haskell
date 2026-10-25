{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Turns page props (plan, role and so on) into JSON that is safe inside a
-- @\<script\>@.
--
-- Keys follow the same rules as event props. Numbers, booleans and lists keep
-- their JSON types.
module PrivatusAnalytics.PageProps
  ( pagePropsJson,
    maxItems,
  )
where

import Data.Aeson qualified as Aeson
import Data.Aeson.Encoding qualified as E
import Data.Aeson.Key qualified as Key
import Data.ByteString.Lazy qualified as BL
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import PrivatusAnalytics.Prop

-- | Lists keep at most this many items.
maxItems :: Int
maxItems = 30

-- | A JSON object, or 'Nothing' when there are no props to send. Keys keep
-- the order you gave them. @<@, @>@, @&@, U+2028 and U+2029 are written as
-- @\\u003c@ and so on, so the JSON is safe inside a script tag.
--
-- >>> pagePropsJson [("plan", "pro"), ("role", "admin")]
-- Just "{\"plan\":\"pro\",\"role\":\"admin\"}"
pagePropsJson :: [Prop] -> Maybe Text
pagePropsJson props =
  case mapMaybe pair (normalizeProps props) of
    [] -> Nothing
    pairs -> Just (scriptSafe (encode (E.pairs (mconcat pairs))))
  where
    pair (key, value) = E.pair (Key.fromText key) <$> json value
    encode = TE.decodeUtf8 . BL.toStrict . E.encodingToLazyByteString

json :: PropValue -> Maybe Aeson.Encoding
json = \case
  PropList xs -> Just (E.list id (mapMaybe scalar (take maxItems (filter (/= PropNull) xs))))
  other -> scalar other

scalar :: PropValue -> Maybe Aeson.Encoding
scalar = \case
  PropText t -> Just (E.text (T.take maxValue t))
  PropNumber n -> Just (E.scientific n)
  PropBool b -> Just (E.bool b)
  PropList _ -> Nothing
  PropNull -> Nothing

scriptSafe :: Text -> Text
scriptSafe = T.concatMap $ \case
  '<' -> "\\u003c"
  '>' -> "\\u003e"
  '&' -> "\\u0026"
  '\x2028' -> "\\u2028"
  '\x2029' -> "\\u2029"
  c -> T.singleton c
