{-# LANGUAGE OverloadedStrings #-}

-- | A WAI middleware that adds the script tag just before @\<\/head\>@.
--
-- > import PrivatusAnalytics
-- > import PrivatusAnalytics.Wai (privatusMiddleware)
-- >
-- > main = do
-- >   config <- loadConfig
-- >   run 3000 (privatusMiddleware config app)
--
-- It works with any WAI app: Yesod, Servant, Scotty, Spock, IHP and plain WAI.
module PrivatusAnalytics.Wai
  ( privatusMiddleware,
    nonceFromCsp,
  )
where

import Control.Applicative ((<|>))
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as B
import Data.ByteString.Builder qualified as BB
import Data.ByteString.Char8 qualified as B8
import Data.ByteString.Lazy qualified as BL
import Data.CaseInsensitive qualified as CI
import Data.Char (isAsciiUpper)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Data.Text.Encoding.Error qualified as TE
import Network.HTTP.Types (ResponseHeaders, hContentEncoding, hContentLength, hContentType, statusCode)
import Network.Wai qualified as Wai
import Network.Wai.Internal qualified as WaiI
import PrivatusAnalytics.Config
import PrivatusAnalytics.Tag

-- | Adds the tag to the head of HTML responses.
--
-- It only touches responses with status 200, a @text\/html@ content type and
-- no @Content-Encoding@ header. It skips Ajax requests
-- (@X-Requested-With: XMLHttpRequest@), pages without a @\<\/head\>@ and
-- pages that already have the tag (they contain @\/js\/pa.js@). It fixes the
-- @Content-Length@ header.
--
-- It prints nothing without a site id, or outside the enabled environments.
-- The nonce comes from 'configNonceFor', or else from the response's
-- @Content-Security-Policy@ header. 'configRequestProps' gets the request.
--
-- To read the body, it holds the whole HTML response in memory. Streamed
-- HTML responses are read to the end first.
privatusMiddleware :: Config -> Wai.Middleware
privatusMiddleware config app request respond =
  app request $ \response ->
    if inject response
      then rewrite response >>= respond
      else respond response
  where
    inject response =
      not (isRaw response)
        && statusCode (Wai.responseStatus response) == 200
        && isHtml (Wai.responseHeaders response)
        && not (hasHeader hContentEncoding (Wai.responseHeaders response))
        && not (isAjax request)
        && shouldRender config

    rewrite response = do
      body <- readBody response
      let headers = Wai.responseHeaders response
      html <-
        if marker `B.isInfixOf` body
          then pure body
          else case splitHead body of
            Nothing -> pure body
            Just (before, after) -> do
              let nonce = configNonceFor config request <|> (lookup "content-security-policy" (lowerHeaders headers) >>= nonceFromCsp)
              tag <- analyticsTagFor config defaultTagOptions {tagNonce = nonce} request
              pure (before <> TE.encodeUtf8 tag <> "\n" <> after)
      let headers' = (hContentLength, B8.pack (show (B.length html))) : filter ((/= hContentLength) . fst) headers
      pure (Wai.responseLBS (Wai.responseStatus response) headers' (BL.fromStrict html))

marker :: ByteString
marker = "/js/pa.js"

isRaw :: Wai.Response -> Bool
isRaw WaiI.ResponseRaw {} = True
isRaw _ = False

isHtml :: ResponseHeaders -> Bool
isHtml headers = case lookup hContentType headers of
  Just value -> "text/html" `B.isPrefixOf` lowerAscii (B8.dropWhile (== ' ') value)
  Nothing -> False

hasHeader :: CI.CI ByteString -> ResponseHeaders -> Bool
hasHeader name = any ((== name) . fst)

isAjax :: Wai.Request -> Bool
isAjax request = case lookup "X-Requested-With" (Wai.requestHeaders request) of
  Just value -> lowerAscii value == "xmlhttprequest"
  Nothing -> False

lowerHeaders :: ResponseHeaders -> [(ByteString, ByteString)]
lowerHeaders = map (first CI.foldedCase)

lowerAscii :: ByteString -> ByteString
lowerAscii = B8.map (\c -> if isAsciiUpper c then toEnum (fromEnum c + 32) else c)

-- Splits the body at the first </head>, in any letter case.
splitHead :: ByteString -> Maybe (ByteString, ByteString)
splitHead body =
  let (before, _) = B.breakSubstring "</head>" (lowerAscii body)
      at = B.length before
   in if at == B.length body then Nothing else Just (B.splitAt at body)

readBody :: Wai.Response -> IO ByteString
readBody response = do
  let (_, _, withBody) = Wai.responseToStream response
  ref <- newIORef mempty
  withBody $ \streaming -> streaming (\chunk -> modifyIORef' ref (<> chunk)) (pure ())
  BL.toStrict . BB.toLazyByteString <$> readIORef ref

-- | Finds the nonce in a @Content-Security-Policy@ header value, so
-- @"script-src 'nonce-abc123'"@ gives @Just "abc123"@.
nonceFromCsp :: ByteString -> Maybe Text
nonceFromCsp value =
  case B.breakSubstring "'nonce-" value of
    (_, rest)
      | B.null rest -> Nothing
      | otherwise ->
          let nonce = B8.takeWhile (/= '\'') (B.drop 7 rest)
           in if B.null nonce then Nothing else Just (TE.decodeUtf8With TE.lenientDecode nonce)
