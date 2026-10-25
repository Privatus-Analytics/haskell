{-# LANGUAGE OverloadedStrings #-}

module AttributesSpec (spec) where

import Data.Text qualified as T
import PrivatusAnalytics
import Test.Hspec

spec :: Spec
spec = do
  describe "eventData" $ do
    it "turns an event into data attributes" $
      eventData "Export CSV" [("format", "csv"), ("source", "toolbar")]
        `shouldBe` [ ("data-privatus-event", "Export CSV"),
                     ("data-privatus-prop-format", "csv"),
                     ("data-privatus-prop-source", "toolbar")
                   ]

    it "trims the name and cuts it to 120 characters" $ do
      lookup "data-privatus-event" (eventData "  Export CSV  " []) `shouldBe` Just "Export CSV"
      lookup "data-privatus-event" (eventData (T.replicate 200 "a") []) `shouldBe` Just (T.replicate 120 "a")

    it "gives nothing for an empty name" $ do
      eventData "   " [("format", "csv")] `shouldBe` []
      eventData "" [] `shouldBe` []

    it "lowercases, cleans and cuts prop keys" $ do
      let attrs = eventData "Saved" [("Report Type", "a"), ("x-y", "b"), (T.replicate 80 "K", "c")]
      lookup "data-privatus-prop-report_type" attrs `shouldBe` Just "a"
      lookup "data-privatus-prop-x_y" attrs `shouldBe` Just "b"
      lookup ("data-privatus-prop-" <> T.replicate 64 "k") attrs `shouldBe` Just "c"

    it "turns values into text and drops nulls" $ do
      let attrs =
            eventData
              "Saved"
              [ "on" =: True,
                "off" =: False,
                "count" =: (3 :: Int),
                "ratio" =: (1.5 :: Double),
                "tags" =: (["a", "b"] :: [T.Text]),
                "gone" =: (Nothing :: Maybe T.Text),
                "name" =: ("str" :: String)
              ]
      map (\k -> lookup ("data-privatus-prop-" <> k) attrs) ["on", "off", "count", "ratio", "tags", "name"]
        `shouldBe` map Just ["true", "false", "3", "1.5", "a,b", "str"]
      lookup "data-privatus-prop-gone" attrs `shouldBe` Nothing

    it "keeps at most 30 props and cuts values to 500 characters" $ do
      length (eventData "Saved" [("p" <> T.pack (show i), "v") | i <- [1 .. 40 :: Int]]) `shouldBe` 31
      fmap T.length (lookup "data-privatus-prop-long" (eventData "Saved" [("long", PropText (T.replicate 900 "x"))]))
        `shouldBe` Just 500

    it "keeps one value per key, the last one, in the first place" $
      eventData "Saved" [("Plan", "a"), ("role", "r"), ("plan", "b")]
        `shouldBe` [ ("data-privatus-event", "Saved"),
                     ("data-privatus-prop-plan", "b"),
                     ("data-privatus-prop-role", "r")
                   ]

  describe "eventAttrs" $ do
    it "prints escaped HTML" $
      eventAttrs "Say \"hi\" <now>" [("note", "a&b")]
        `shouldBe` "data-privatus-event=\"Say &quot;hi&quot; &lt;now&gt;\" data-privatus-prop-note=\"a&amp;b\""

    it "prints the spec example" $
      eventAttrs "Export CSV" [("format", "csv"), ("source", "toolbar")]
        `shouldBe` "data-privatus-event=\"Export CSV\" data-privatus-prop-format=\"csv\" data-privatus-prop-source=\"toolbar\""

    it "prints nothing for an empty name" $
      eventAttrs " " [] `shouldBe` ""

    it "prints even when the tag is off" $ do
      isEnabled defaultConfig `shouldBe` False
      eventAttrs "Export CSV" [] `shouldBe` "data-privatus-event=\"Export CSV\""

  describe "click maps" $ do
    it "turns a valid name into a data attribute" $ do
      clickData "pricing.cta" `shouldBe` [("data-privatus-click", "pricing.cta")]
      clickData "a-b_c:d.1" `shouldBe` [("data-privatus-click", "a-b_c:d.1")]
      clickAttr "pricing.cta" `shouldBe` "data-privatus-click=\"pricing.cta\""

    it "gives nothing for an invalid name" $ do
      mapM_ (\name -> clickData name `shouldBe` []) ["", "has space", T.replicate 101 "x", "<b>", "caf\233"]
      clickAttr "not valid!" `shouldBe` ""
      validClickName (T.replicate 100 "x") `shouldBe` True
