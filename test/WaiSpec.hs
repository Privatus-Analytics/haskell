{-# LANGUAGE OverloadedStrings #-}

module WaiSpec (spec) where

import Data.ByteString qualified as B
import Data.ByteString.Builder (byteString)
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Lazy qualified as BL
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Network.HTTP.Types (RequestHeaders, status200, status404)
import Network.Wai
import Network.Wai.Test
import PrivatusAnalytics
import PrivatusAnalytics.Wai
import Test.Hspec

on :: Config
on = defaultConfig {configSiteId = Just "pa_TEST123456", configEnabled = Just True}

snippet :: BL.ByteString
snippet = "<script defer src=\"https://privatusstats.com/js/pa.js\" data-site=\"pa_TEST123456\"></script>"

plain :: BL.ByteString
plain = "<html><head><title>Plain</title></head><body>Hi</body></html>"

app :: Application
app req respond = respond $ case rawPathInfo req of
  "/layout" -> responseLBS status200 htmlType ("<html><head>" <> snippet <> "</head><body></body></html>")
  "/plain" -> responseLBS status200 (("Content-Length", "61") : htmlType) plain
  "/upper" -> responseLBS status200 [("Content-Type", "TEXT/HTML")] "<HTML><HEAD></HEAD></HTML>"
  "/data" -> responseLBS status200 [("Content-Type", "application/json")] "{\"ok\":true,\"head\":\"</head>\"}"
  "/bare" -> responseLBS status200 htmlType "<p>No head here</p>"
  "/gzip" -> responseLBS status200 (("Content-Encoding", "gzip") : htmlType) plain
  "/missing" -> responseLBS status404 htmlType plain
  "/csp" -> responseLBS status200 (("Content-Security-Policy", "script-src 'self' 'nonce-n0nce'") : htmlType) plain
  "/stream" -> responseStream status200 htmlType $ \write flush ->
    mapM_ (write . byteString) ["<html><he", "ad></he", "ad><body>Z\195\188rich</body></html>"] >> flush
  _ -> responseLBS status404 [] ""
  where
    htmlType = [("Content-Type", "text/html; charset=utf-8")]

get :: Config -> B.ByteString -> RequestHeaders -> IO SResponse
get config path headers =
  runSession
    (request (setPath defaultRequest {requestHeaders = headers} path))
    (privatusMiddleware config app)

contains :: BL.ByteString -> SResponse -> Bool
contains needle response = BL.toStrict needle `B.isInfixOf` BL.toStrict (simpleBody response)

count :: B.ByteString -> SResponse -> Int
count needle response = go (BL.toStrict (simpleBody response))
  where
    go body = case B.breakSubstring needle body of
      (_, rest)
        | B.null rest -> 0
        | otherwise -> 1 + go (B.drop (B.length needle) rest)

lengthMatches :: SResponse -> Bool
lengthMatches response =
  lookup "Content-Length" (simpleHeaders response) == Just (B8.pack (show (BL.length (simpleBody response))))

spec :: Spec
spec = do
  it "adds the tag before </head>" $ do
    response <- get on "/plain" []
    response `shouldSatisfy` contains (snippet <> "\n</head>")
    response `shouldSatisfy` lengthMatches

  it "finds </HEAD> in any letter case" $ do
    response <- get on "/upper" []
    simpleBody response `shouldBe` "<HTML><HEAD>" <> snippet <> "\n</HEAD></HTML>"

  it "reads streamed responses and sets the length in bytes" $ do
    response <- get on "/stream" []
    response `shouldSatisfy` contains (snippet <> "\n</head><body>Z\195\188rich")
    response `shouldSatisfy` lengthMatches

  it "does not add a second tag" $ do
    response <- get on "/layout" []
    count "/js/pa.js" response `shouldBe` 1

  it "leaves JSON alone" $ do
    response <- get on "/data" []
    response `shouldNotSatisfy` contains "pa.js"

  it "leaves HTML without a head alone" $ do
    response <- get on "/bare" []
    simpleBody response `shouldBe` "<p>No head here</p>"

  it "leaves compressed responses alone" $ do
    response <- get on "/gzip" []
    response `shouldNotSatisfy` contains "pa.js"

  it "leaves other status codes alone" $ do
    response <- get on "/missing" []
    response `shouldNotSatisfy` contains "pa.js"

  it "leaves Ajax requests alone" $ do
    response <- get on "/plain" [("X-Requested-With", "XMLHttpRequest")]
    response `shouldNotSatisfy` contains "pa.js"

  it "adds nothing outside the enabled environments" $ do
    response <- get on {configEnabled = Nothing} "/plain" []
    simpleBody response `shouldBe` plain

  it "adds nothing without a site id" $ do
    response <- get on {configSiteId = Nothing} "/plain" []
    simpleBody response `shouldBe` plain

  it "gives the props function the request" $ do
    let config = on {configRequestProps = Just (\req -> pure [("section", PropText (T.drop 1 (TE.decodeUtf8 (rawPathInfo req))))])}
    response <- get config "/plain" []
    response `shouldSatisfy` contains "{\"section\":\"plain\"}"
    response `shouldSatisfy` contains "data-props=\"privatusPageProps\""

  it "uses the nonce from the CSP header, with the queue stub" $ do
    response <- get on {configQueueStub = True, configProps = [("plan", "pro")]} "/csp" []
    count "nonce=\"n0nce\"" response `shouldBe` 3
    response `shouldSatisfy` contains "q:[]"
    response `shouldSatisfy` lengthMatches

  it "prefers the configured nonce" $ do
    response <- get on {configNonceFor = const (Just "mine")} "/csp" []
    response `shouldSatisfy` contains "nonce=\"mine\""

  it "reads nonces from CSP headers" $ do
    nonceFromCsp "default-src 'self'; script-src 'nonce-abc123' 'strict-dynamic'" `shouldBe` Just "abc123"
    nonceFromCsp "script-src 'self'" `shouldBe` Nothing
