{-# LANGUAGE OverloadedStrings #-}

module TagSpec (spec) where

import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.Wai (defaultRequest, rawPathInfo)
import PrivatusAnalytics
import Test.Hspec

on :: Config
on = defaultConfig {configSiteId = Just "pa_TEST123456", configEnabled = Just True}

tag :: Config -> T.Text
tag config = analyticsTag config defaultTagOptions

snippet :: T.Text
snippet = "<script defer src=\"https://privatusstats.com/js/pa.js\" data-site=\"pa_TEST123456\"></script>"

spec :: Spec
spec = do
  it "prints the basic snippet" $
    tag on `shouldBe` snippet

  it "prints the same as UTF-8 bytes" $
    analyticsTagBS on defaultTagOptions `shouldBe` TE.encodeUtf8 snippet

  it "prints nothing without a site id" $
    tag on {configSiteId = Nothing} `shouldBe` ""

  it "prints nothing outside the enabled environments" $ do
    tag on {configEnabled = Nothing} `shouldBe` ""
    tag on {configEnabled = Nothing, configEnvironment = Just "production"} `shouldBe` snippet

  it "adds modules and exclusions" $ do
    let html = tag on {configModules = Just ["engage", "auto"], configExcludedPaths = ["/admin/*", "/preview/*"]}
    html `shouldSatisfy` T.isInfixOf "data-modules=\"engage,auto\""
    html `shouldSatisfy` T.isInfixOf "data-exclude=\"/admin/*,/preview/*\""

  it "loads no modules for an empty list" $
    tag on {configModules = Just []} `shouldSatisfy` T.isInfixOf "data-modules=\"\""

  it "adds domains, spa mode and manual mode" $ do
    let html = tag on {configDomains = ["example.com, www.example.com"], configSpa = Just SpaHash, configManual = True}
    html `shouldSatisfy` T.isInfixOf "data-domains=\"example.com,www.example.com\""
    html `shouldSatisfy` T.isInfixOf "data-spa=\"hash\""
    html `shouldSatisfy` T.isInfixOf "data-manual=\"true\""

  it "does not print the auto spa default" $
    tag on {configSpa = Just SpaAuto} `shouldBe` snippet

  it "escapes attribute values" $
    tag on {configExcludedPaths = ["/a\"b"]} `shouldSatisfy` T.isInfixOf "data-exclude=\"/a&quot;b\""

  it "adds extra attributes and a nonce" $ do
    let html = analyticsTag on {configExtraAttributes = [("data-mask", "/orders/*->/orders/:id")]} defaultTagOptions {tagNonce = Just "abc123"}
    html `shouldSatisfy` T.isInfixOf "data-mask=\"/orders/*-&gt;/orders/:id\""
    html `shouldSatisfy` T.isInfixOf "nonce=\"abc123\""

  it "prints a page props script before the tag and data-props on it" $
    analyticsTag on defaultTagOptions {tagProps = [("plan", "pro"), ("role", "admin")]}
      `shouldBe` "<script>window.privatusPageProps=function(){return {\"plan\":\"pro\",\"role\":\"admin\"}}</script>\n"
        <> "<script defer src=\"https://privatusstats.com/js/pa.js\" data-site=\"pa_TEST123456\" data-props=\"privatusPageProps\"></script>"

  it "gives the props script the nonce" $
    analyticsTag on defaultTagOptions {tagProps = [("plan", "pro")], tagNonce = Just "abc"}
      `shouldSatisfy` T.isPrefixOf "<script nonce=\"abc\">window.privatusPageProps="

  it "prints no script and no data-props for empty props" $
    analyticsTag on defaultTagOptions {tagProps = [("plan", PropNull)]} `shouldBe` snippet

  it "uses configured props" $
    tag on {configProps = [("plan", "pro")]} `shouldSatisfy` T.isInfixOf "{\"plan\":\"pro\"}"

  it "merges call props over configured props, and null removes one" $
    analyticsTag on {configProps = [("plan", "pro"), ("role", "admin")]} defaultTagOptions {tagProps = [("role", PropNull), ("tier", "gold")]}
      `shouldSatisfy` T.isInfixOf "{\"plan\":\"pro\",\"tier\":\"gold\"}"

  it "runs request props with the request" $ do
    let config = on {configProps = [("plan", "pro")], configRequestProps = Just (\req -> pure [("path", PropText (TE.decodeUtf8 (rawPathInfo req)))])}
    html <- analyticsTagFor config defaultTagOptions {tagProps = [("plan", "team")]} defaultRequest {rawPathInfo = "/reports"}
    html `shouldSatisfy` T.isInfixOf "{\"plan\":\"team\",\"path\":\"/reports\"}"

  it "does not run request props when the tag is off" $ do
    called <- newIORef False
    let config = on {configEnabled = Just False, configRequestProps = Just (\_ -> writeIORef called True >> pure [])}
    html <- analyticsTagFor config defaultTagOptions defaultRequest
    html `shouldBe` ""
    readIORef called `shouldReturn` False

  it "prints the queue stub first" $ do
    let parts = T.lines (analyticsTag on {configQueueStub = True} defaultTagOptions {tagNonce = Just "abc", tagProps = [("plan", "pro")]})
    take 1 parts `shouldBe` ["<script nonce=\"abc\">" <> queueStub <> "</script>"]
    (parts !! 1) `shouldSatisfy` T.isInfixOf "privatusPageProps"
    (parts !! 2) `shouldSatisfy` T.isInfixOf "/js/pa.js"

  it "has the official queue stub" $
    queueStub
      `shouldBe` "window.privatus=window.privatus||{q:[]};['track','pageview','props','optOut','optIn','ready']"
        <> ".forEach(function(m){window.privatus[m]=window.privatus[m]||function(){window.privatus.q.push("
        <> "[m,Array.prototype.slice.call(arguments)])}})"

  it "has no queue stub by default" $
    tag on `shouldNotSatisfy` T.isInfixOf "q:[]"

  describe "when the tag is off" $ do
    let stubOnly nonce = "<script nonce=\"" <> nonce <> "\">" <> queueStub <> "</script>"
        props = defaultTagOptions {tagNonce = Just "abc", tagProps = [("plan", "pro")]}

    it "prints exactly the queue stub, with the nonce, when the stub is on" $
      analyticsTag on {configEnabled = Just False, configQueueStub = True, configProps = [("role", "admin")]} props
        `shouldBe` stubOnly "abc"

    it "prints the stub without a nonce when there is none" $
      analyticsTag on {configEnabled = Just False, configQueueStub = True} defaultTagOptions
        `shouldBe` "<script>" <> queueStub <> "</script>"

    it "prints nothing when the stub is off" $
      analyticsTag on {configEnabled = Just False} props `shouldBe` ""

    it "prints only the stub without a site id" $
      analyticsTag on {configSiteId = Nothing, configQueueStub = True} props `shouldBe` stubOnly "abc"

    it "prints only the stub outside the enabled environments" $
      analyticsTag on {configEnabled = Nothing, configEnvironment = Just "development", configQueueStub = True} props
        `shouldBe` stubOnly "abc"

    it "prints only the stub from analyticsTagFor and does not run request props" $ do
      called <- newIORef False
      let config = on {configEnabled = Just False, configQueueStub = True, configRequestProps = Just (\_ -> writeIORef called True >> pure [])}
      html <- analyticsTagFor config props defaultRequest
      html `shouldBe` stubOnly "abc"
      readIORef called `shouldReturn` False
