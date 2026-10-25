{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Small HTML helpers shared by the other modules.
module PrivatusAnalytics.Html
  ( escapeHtml,
    renderAttrs,
  )
where

import Data.Text (Text)
import Data.Text qualified as T

-- | Escapes @& < > \" '@, like Ruby's @CGI.escapeHTML@.
escapeHtml :: Text -> Text
escapeHtml = T.concatMap escape
  where
    escape = \case
      '&' -> "&amp;"
      '<' -> "&lt;"
      '>' -> "&gt;"
      '"' -> "&quot;"
      '\'' -> "&#39;"
      c -> T.singleton c

-- | @name="value"@ pairs joined by spaces, with every value escaped.
renderAttrs :: [(Text, Text)] -> Text
renderAttrs = T.intercalate " " . map (\(name, value) -> name <> "=\"" <> escapeHtml value <> "\"")
