-- | UTF-8 JSON Lines encoding, without filesystem effects.
module FirefoxAddons.JsonLines (encodeJSONLines) where

import Data.Aeson (ToJSON, encode)
import qualified Data.ByteString.Lazy.Char8 as BL

{- | Encode one compact JSON value per line, including a final newline.
Empty input yields empty bytes. Embedded newlines are escaped by Aeson.
-}
encodeJSONLines :: (ToJSON a) => [a] -> BL.ByteString
encodeJSONLines records = BL.unlines (map encode records)
