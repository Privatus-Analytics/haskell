{-# LANGUAGE LambdaCase #-}

-- | Prop values for events and page props.
--
-- A prop is a key and a value, like @("plan", "pro")@. With
-- @OverloadedStrings@ a text value can be written as a plain string literal.
-- For other types use 'prop' or '(=:)':
--
-- > [("format", "csv"), "seats" =: (5 :: Int), "beta" =: True]
module PrivatusAnalytics.Prop
  ( Prop,
    PropValue (..),
    ToPropValue (..),
    prop,
    (=:),
    normalizeKey,
    normalizeProps,
    mergeProps,
    maxProps,
    maxKey,
    maxValue,
  )
where

import Data.Aeson qualified as Aeson
import Data.Bifunctor (first)
import Data.Char (isAsciiLower, isDigit)
import Data.Int (Int16, Int32, Int64, Int8)
import Data.List (foldl')
import Data.Scientific (Scientific, fromFloatDigits)
import Data.String (IsString (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Lazy qualified as TL
import Data.Vector qualified as V
import Data.Word (Word16, Word32, Word64, Word8)
import Numeric.Natural (Natural)

-- | One prop: a key and a value.
type Prop = (Text, PropValue)

-- | A prop value. 'PropNull' values are dropped, so @Nothing@ leaves a prop out.
data PropValue
  = PropText Text
  | PropNumber Scientific
  | PropBool Bool
  | PropList [PropValue]
  | PropNull
  deriving stock (Eq, Show)

instance IsString PropValue where
  fromString = PropText . T.pack

-- | Types that can be a prop value.
class ToPropValue a where
  toPropValue :: a -> PropValue

  -- | How a list of this type becomes a value. Only 'Char' overrides it, so
  -- a 'String' is text and not a list.
  listToPropValue :: [a] -> PropValue
  listToPropValue = PropList . map toPropValue

instance ToPropValue PropValue where
  toPropValue = id

instance ToPropValue Text where
  toPropValue = PropText

instance ToPropValue TL.Text where
  toPropValue = PropText . TL.toStrict

instance ToPropValue Char where
  toPropValue c = PropText (T.singleton c)
  listToPropValue = PropText . T.pack

instance ToPropValue Bool where
  toPropValue = PropBool

instance ToPropValue Scientific where
  toPropValue = PropNumber

integral :: (Integral a) => a -> PropValue
integral = PropNumber . fromIntegral

instance ToPropValue Int where toPropValue = integral

instance ToPropValue Int8 where toPropValue = integral

instance ToPropValue Int16 where toPropValue = integral

instance ToPropValue Int32 where toPropValue = integral

instance ToPropValue Int64 where toPropValue = integral

instance ToPropValue Integer where toPropValue = integral

instance ToPropValue Natural where toPropValue = integral

instance ToPropValue Word where toPropValue = integral

instance ToPropValue Word8 where toPropValue = integral

instance ToPropValue Word16 where toPropValue = integral

instance ToPropValue Word32 where toPropValue = integral

instance ToPropValue Word64 where toPropValue = integral

-- | NaN and infinity are dropped.
instance ToPropValue Double where
  toPropValue d
    | isNaN d || isInfinite d = PropNull
    | otherwise = PropNumber (fromFloatDigits d)

-- | NaN and infinity are dropped.
instance ToPropValue Float where
  toPropValue f
    | isNaN f || isInfinite f = PropNull
    | otherwise = PropNumber (fromFloatDigits f)

instance (ToPropValue a) => ToPropValue (Maybe a) where
  toPropValue = maybe PropNull toPropValue

instance (ToPropValue a) => ToPropValue [a] where
  toPropValue = listToPropValue

-- | JSON null is dropped. Objects are dropped too, because props are flat.
instance ToPropValue Aeson.Value where
  toPropValue = \case
    Aeson.String t -> PropText t
    Aeson.Number n -> PropNumber n
    Aeson.Bool b -> PropBool b
    Aeson.Array xs -> PropList (map toPropValue (V.toList xs))
    Aeson.Null -> PropNull
    Aeson.Object _ -> PropNull

-- | Builds a prop from any supported value.
prop :: (ToPropValue a) => Text -> a -> Prop
prop key value = (key, toPropValue value)

-- | Operator form of 'prop': @"seats" =: (5 :: Int)@.
(=:) :: (ToPropValue a) => Text -> a -> Prop
(=:) = prop

infixr 8 =:

-- | At most this many props are kept.
maxProps :: Int
maxProps = 30

-- | Keys are cut to this many characters.
maxKey :: Int
maxKey = 64

-- | Values are cut to this many characters.
maxValue :: Int
maxValue = 500

-- | Lowercases a key, turns anything outside @a-z 0-9 _@ into @_@ and cuts it
-- to 64 characters. @"Report Type"@ becomes @"report_type"@.
normalizeKey :: Text -> Text
normalizeKey = T.take maxKey . T.map clean . T.toLower
  where
    clean c
      | isAsciiLower c || isDigit c || c == '_' = c
      | otherwise = '_'

-- | Cleans every key, drops empty keys and null values, keeps one entry per
-- key (a later value replaces an earlier one in its place) and keeps the
-- first 30.
normalizeProps :: [Prop] -> [Prop]
normalizeProps =
  take maxProps . foldl' add [] . map (first normalizeKey)
  where
    add acc (key, value)
      | T.null key || value == PropNull = acc
      | otherwise = upsert key value acc

-- | Merges props over others, with keys cleaned first. A key in the second
-- list replaces the same key in the first; 'PropNull' then removes it.
mergeProps :: [Prop] -> [Prop] -> [Prop]
mergeProps base over = foldl' (\acc (k, v) -> upsert k v acc) (keyed base) (keyed over)
  where
    keyed = map (first normalizeKey)

upsert :: Text -> PropValue -> [Prop] -> [Prop]
upsert key value props
  | any ((== key) . fst) props = map (\(k, v) -> if k == key then (k, value) else (k, v)) props
  | otherwise = props ++ [(key, value)]
