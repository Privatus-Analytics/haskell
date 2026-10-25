{-# LANGUAGE OverloadedStrings #-}

-- | Adds the cookieless Privatus Analytics tracking script to Haskell web apps.
--
-- The package only prints HTML: the browser script tag and data attributes.
-- It never sends HTTP requests or events from the server, sets no cookies and
-- reads no IP addresses, user agents or visitor ids.
--
-- > import PrivatusAnalytics
-- >
-- > main :: IO ()
-- > main = do
-- >   config <- loadConfig  -- reads PRIVATUS_SITE_ID and PRIVATUS_ENV
-- >   print (analyticsTag config defaultTagOptions)
--
-- See "PrivatusAnalytics.Wai" for the middleware, and
-- "PrivatusAnalytics.Lucid" and "PrivatusAnalytics.Blaze" for template helpers.
-- Docs: <https://privatusanalytics.com/docs>.
module PrivatusAnalytics
  ( -- * Settings
    module PrivatusAnalytics.Config,

    -- * The script tag
    module PrivatusAnalytics.Tag,

    -- * Events and click maps
    module PrivatusAnalytics.Attributes,

    -- * Page props
    module PrivatusAnalytics.PageProps,

    -- * Props
    module PrivatusAnalytics.Prop,

    -- * Version
    version,
  )
where

import Data.Text (Text)
import PrivatusAnalytics.Attributes
import PrivatusAnalytics.Config
import PrivatusAnalytics.PageProps
import PrivatusAnalytics.Prop
import PrivatusAnalytics.Tag

-- | The package version.
version :: Text
version = "1.0.0"
