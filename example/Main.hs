{-# LANGUAGE OverloadedStrings #-}

-- | Conformance example app for privatus-analytics (WAI, Warp and Lucid).
--
-- Built by the conformance suite
-- (https://github.com/Privatus-Analytics/conformance). See its CONTRACT.md
-- for what each route must render. The site id and script host come from
-- PRIVATUS_SITE_ID and PRIVATUS_SCRIPT_HOST.
module Main (main) where

import Data.ByteString.Char8 qualified as B8
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Lucid
import Network.HTTP.Types (hContentType, status200, status404)
import Network.Wai qualified as Wai
import Network.Wai.Handler.Warp qualified as Warp
import PrivatusAnalytics
import PrivatusAnalytics.Lucid
import PrivatusAnalytics.Wai (privatusMiddleware)
import System.Environment (lookupEnv)

nonce :: Text
nonce = "testnonce"

nasty :: Text
nasty = "</script><script>window.__pwned=1</script>\x2028\x2029&<>\"'"

pageProps :: [Prop]
pageProps = [("plan", "pro"), ("role", "admin"), "beta" =: True, "seats" =: (3 :: Int)]

-- The tag with the page props, the queue stub and the nonce.
withProps :: [Prop] -> TagOptions
withProps props = defaultTagOptions {tagNonce = Just nonce, tagProps = props}

layout :: Config -> Text -> [Prop] -> Html () -> Html ()
layout config title props body = do
  doctype_
  html_ [lang_ "en"] $ do
    head_ $ do
      meta_ [charset_ "utf-8"]
      title_ (toHtml title)
      analyticsTag_ config {configQueueStub = True} (withProps props)
    body_ body

home :: Config -> Html ()
home config = layout config "Home" pageProps (h1_ "Home")

event :: Config -> Html ()
event config = layout config "Events" pageProps $ do
  h1_ "Events"
  button_ ([type_ "button"] <> eventAttrs_ "Report exported" [("format", "csv"), ("source", "toolbar")]) "Export report"
  p_ (a_ (href_ "#pricing" : clickAttr_ "pricing.cta") "Pricing")
  form_ ([action_ "/event", method_ "get"] <> eventAttrs_ "Signup form" []) $
    button_ [type_ "submit"] "Sign up"

nastyPage :: Config -> Html ()
nastyPage config = layout config "Nasty" (pageProps <> [("nasty", PropText nasty)]) $ do
  h1_ "Nasty values"
  button_ ([type_ "button"] <> eventAttrs_ "Nasty value" [("nasty", PropText nasty)]) "Nasty"

-- Off with the queue stub on prints only the stub, so privatus.track still
-- works. Off with the stub off prints nothing.
off :: Config -> Bool -> Html ()
off config stub = do
  doctype_
  html_ [lang_ "en"] $ do
    head_ $ do
      meta_ [charset_ "utf-8"]
      title_ "Off"
      meta_ [name_ "privatus-off-start"]
      analyticsTag_ config {configEnabled = Just False, configQueueStub = stub} (withProps pageProps)
      meta_ [name_ "privatus-off-end"]
    body_ (h1_ "Off")

autoPage :: Html ()
autoPage = do
  doctype_
  html_ [lang_ "en"] $ do
    head_ $ do
      meta_ [charset_ "utf-8"]
      title_ "Auto inject"
    body_ $ do
      h1_ "Auto inject"
      p_ "No tag in the template. The middleware adds it."

htmlResponse :: Html () -> Wai.Response
htmlResponse page = Wai.responseLBS status200 [(hContentType, "text/html; charset=utf-8")] (renderBS page)

main :: IO ()
main = do
  -- Forced on, so the tag prints whatever the environment. The site id and
  -- script host come from the environment.
  config <- fromEnvironment defaultConfig {configEnabled = Just True}
  let csp = "script-src 'nonce-" <> TE.encodeUtf8 nonce <> "' " <> TE.encodeUtf8 (scriptHost config)
      withCsp app request respond =
        app request (respond . Wai.mapResponseHeaders (("Content-Security-Policy", csp) :))
      -- Auto inject on this route only, so the other routes test the
      -- template helper alone.
      auto = privatusMiddleware config {configNonceFor = const (Just nonce)} (\_ respond -> respond (htmlResponse autoPage))
      app request respond = case (Wai.requestMethod request, Wai.pathInfo request) of
        ("GET", []) -> respond (htmlResponse (home config))
        ("GET", ["event"]) -> respond (htmlResponse (event config))
        ("GET", ["nasty"]) -> respond (htmlResponse (nastyPage config))
        ("GET", ["off"]) -> respond (htmlResponse (off config True))
        ("GET", ["off-plain"]) -> respond (htmlResponse (off config False))
        ("GET", ["auto"]) -> auto request respond
        _ -> respond (Wai.responseLBS status404 [(hContentType, "text/plain")] "Not found")
  port <- maybe 8080 read <$> lookupEnv "PORT"
  B8.putStrLn ("example app on :" <> B8.pack (show port))
  Warp.runSettings (Warp.setHost "0.0.0.0" (Warp.setPort port Warp.defaultSettings)) (withCsp app)
