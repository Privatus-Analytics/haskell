{-# LANGUAGE OverloadedStrings #-}

module ConfigSpec (spec) where

import PrivatusAnalytics
import System.Environment (setEnv, unsetEnv)
import Test.Hspec

clearEnv :: IO ()
clearEnv = mapM_ unsetEnv ["PRIVATUS_SITE_ID", "PRIVATUS_SCRIPT_HOST", "PRIVATUS_ENV", "APP_ENV"]

spec :: Spec
spec = around_ (\run -> clearEnv >> run >> clearEnv) $ do
  it "has no site id by default" $ do
    siteId defaultConfig `shouldBe` Nothing
    config <- loadConfig
    siteId config `shouldBe` Nothing

  it "reads the site id from PRIVATUS_SITE_ID" $ do
    setEnv "PRIVATUS_SITE_ID" "pa_FROMENV123"
    config <- loadConfig
    siteId config `shouldBe` Just "pa_FROMENV123"

  it "keeps an explicit site id over the environment variable" $ do
    setEnv "PRIVATUS_SITE_ID" "pa_FROMENV123"
    config <- fromEnvironment defaultConfig {configSiteId = Just "pa_EXPLICIT01"}
    siteId config `shouldBe` Just "pa_EXPLICIT01"

  it "treats a blank site id as missing" $
    siteId defaultConfig {configSiteId = Just "  "} `shouldBe` Nothing

  it "defaults the script host and drops a trailing slash" $ do
    scriptHost defaultConfig `shouldBe` "https://privatusstats.com"
    scriptHost defaultConfig {configScriptHost = Just "https://stats.example.com/"} `shouldBe` "https://stats.example.com"
    setEnv "PRIVATUS_SCRIPT_HOST" "https://env.example.com/"
    config <- loadConfig
    scriptHost config `shouldBe` "https://env.example.com"

  it "is enabled only in production by default" $ do
    let env name = defaultConfig {configEnvironment = name}
    isEnabled (env (Just "production")) `shouldBe` True
    isEnabled (env (Just "development")) `shouldBe` False
    isEnabled (env (Just "test")) `shouldBe` False
    isEnabled (env Nothing) `shouldBe` False

  it "reads the environment from PRIVATUS_ENV, then APP_ENV" $ do
    setEnv "APP_ENV" "production"
    appConfig <- loadConfig
    isEnabled appConfig `shouldBe` True
    setEnv "PRIVATUS_ENV" "staging"
    config <- loadConfig
    configEnvironment config `shouldBe` Just "staging"
    isEnabled config `shouldBe` False

  it "lets enabled force the tag on or off" $ do
    isEnabled defaultConfig {configEnabled = Just True, configEnvironment = Just "development"} `shouldBe` True
    isEnabled defaultConfig {configEnabled = Just False, configEnvironment = Just "production"} `shouldBe` False

  it "takes other enabled environments" $
    isEnabled defaultConfig {configEnvironment = Just "staging", configEnabledEnvironments = ["staging"]} `shouldBe` True

  it "has props and the queue stub off by default" $ do
    configProps defaultConfig `shouldBe` []
    configQueueStub defaultConfig `shouldBe` False

  it "reads spa modes" $ do
    parseSpa "Hash" `shouldBe` Just SpaHash
    parseSpa "bogus" `shouldBe` Nothing
