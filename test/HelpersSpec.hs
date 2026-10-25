{-# LANGUAGE OverloadedStrings #-}

module HelpersSpec (spec) where

import Data.Text.Lazy qualified as TL
import Lucid qualified as L
import PrivatusAnalytics
import PrivatusAnalytics.Blaze
import PrivatusAnalytics.Lucid
import Test.Hspec
import Text.Blaze.Html.Renderer.Text (renderHtml)
import Text.Blaze.Html5 ((!))
import Text.Blaze.Html5 qualified as H
import Text.Blaze.Html5.Attributes qualified as A

on :: Config
on = defaultConfig {configSiteId = Just "pa_TEST123456", configEnabled = Just True}

snippet :: TL.Text
snippet = "<script defer src=\"https://privatusstats.com/js/pa.js\" data-site=\"pa_TEST123456\"></script>"

spec :: Spec
spec = do
  describe "lucid" $ do
    it "prints the tag in the head" $
      L.renderText (L.head_ (analyticsTag_ on defaultTagOptions)) `shouldBe` "<head>" <> snippet <> "</head>"

    it "prints nothing when the tag is off" $
      L.renderText (analyticsTag_ defaultConfig defaultTagOptions) `shouldBe` ""

    it "adds event attributes to a button" $
      L.renderText (L.button_ (L.class_ "btn" : eventAttrs_ "Export CSV" [("format", "csv")]) "Export")
        `shouldBe` "<button class=\"btn\" data-privatus-event=\"Export CSV\" data-privatus-prop-format=\"csv\">Export</button>"

    it "adds event attributes to a form" $
      L.renderText (L.form_ (eventAttrs_ "Newsletter joined" [("list", "weekly")]) "")
        `shouldBe` "<form data-privatus-event=\"Newsletter joined\" data-privatus-prop-list=\"weekly\"></form>"

    it "escapes values" $
      L.renderText (L.button_ (eventAttrs_ "Say \"hi\"" []) "Go")
        `shouldBe` "<button data-privatus-event=\"Say &quot;hi&quot;\">Go</button>"

    it "adds a click map name, and nothing for a bad one" $ do
      L.renderText (L.a_ (L.href_ "/pricing" : clickAttr_ "pricing.cta") "Pricing")
        `shouldBe` "<a href=\"/pricing\" data-privatus-click=\"pricing.cta\">Pricing</a>"
      L.renderText (L.a_ (clickAttr_ "not valid!") "x") `shouldBe` "<a>x</a>"

  describe "blaze-html" $ do
    it "prints the tag in the head" $
      renderHtml (H.head (analyticsTagHtml on defaultTagOptions)) `shouldBe` "<head>" <> snippet <> "</head>"

    it "prints nothing when the tag is off" $
      renderHtml (analyticsTagHtml defaultConfig defaultTagOptions) `shouldBe` ""

    it "adds event attributes to a button" $
      renderHtml (H.button ! A.class_ "btn" ! eventAttribute "Export CSV" [("format", "csv")] $ "Export")
        `shouldBe` "<button class=\"btn\" data-privatus-event=\"Export CSV\" data-privatus-prop-format=\"csv\">Export</button>"

    it "escapes values" $
      renderHtml (H.button ! eventAttribute "<b>" [("note", "a&b")] $ "Go")
        `shouldBe` "<button data-privatus-event=\"&lt;b&gt;\" data-privatus-prop-note=\"a&amp;b\">Go</button>"

    it "combines event and click attributes" $
      renderHtml (H.button ! eventAttribute "Plan chosen" [("plan", "pro")] ! clickAttribute "pricing.buy" $ "Buy")
        `shouldBe` "<button data-privatus-event=\"Plan chosen\" data-privatus-prop-plan=\"pro\" data-privatus-click=\"pricing.buy\">Buy</button>"

    it "adds nothing for a bad click name" $
      renderHtml (H.a ! clickAttribute "not valid!" $ "x") `shouldBe` "<a>x</a>"
