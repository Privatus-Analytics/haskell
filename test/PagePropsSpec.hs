{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module PagePropsSpec (spec) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import PrivatusAnalytics
import Test.Hspec

decode :: Maybe T.Text -> Maybe Aeson.Value
decode json = json >>= Aeson.decodeStrict . TE.encodeUtf8

spec :: Spec
spec = describe "pagePropsJson" $ do
  it "turns props into a JSON object in the given order" $
    pagePropsJson [("plan", "pro"), ("role", "admin")] `shouldBe` Just "{\"plan\":\"pro\",\"role\":\"admin\"}"

  it "gives Nothing for empty props" $ do
    pagePropsJson [] `shouldBe` Nothing
    pagePropsJson [("gone", PropNull)] `shouldBe` Nothing

  it "keeps numbers, booleans and lists as JSON" $
    pagePropsJson
      [ "seats" =: (5 :: Int),
        "ratio" =: (1.5 :: Double),
        "beta" =: True,
        "old" =: False,
        "flags" =: [PropText "a", PropNull, PropText "b", PropNumber 3]
      ]
      `shouldBe` Just "{\"seats\":5,\"ratio\":1.5,\"beta\":true,\"old\":false,\"flags\":[\"a\",\"b\",3]}"

  it "cleans keys like event props" $
    pagePropsJson [("App Version", "2.1")] `shouldBe` Just "{\"app_version\":\"2.1\"}"

  it "drops NaN and infinity" $
    pagePropsJson ["bad" =: (0 / 0 :: Double), "inf" =: (1 / 0 :: Double)] `shouldBe` Nothing

  it "limits props, list items and value length" $ do
    let count = \case
          Just (Aeson.Object o) -> KM.size o
          _ -> 0
    count (decode (pagePropsJson [("p" <> T.pack (show i)) =: i | i <- [1 .. 40 :: Int]])) `shouldBe` 30
    decode (pagePropsJson ["list" =: map (T.pack . show) [1 .. 50 :: Int]])
      `shouldBe` Just (Aeson.object ["list" Aeson..= map (T.pack . show) [1 .. 30 :: Int]])
    decode (pagePropsJson [("long", PropText (T.replicate 900 "x"))])
      `shouldBe` Just (Aeson.object ["long" Aeson..= T.replicate 500 "x"])

  it "is safe inside a script tag" $ do
    let json = pagePropsJson [("note", "</script><b>&\x2028\x2029")]
    json `shouldBe` Just "{\"note\":\"\\u003c/script\\u003e\\u003cb\\u003e\\u0026\\u2028\\u2029\"}"
    fmap (T.any (`elem` ("<>&\x2028\x2029" :: String))) json `shouldBe` Just False

  it "takes aeson values" $
    pagePropsJson ["v" =: Aeson.toJSON [1 :: Int, 2], "o" =: Aeson.object []]
      `shouldBe` Just "{\"v\":[1,2]}"
