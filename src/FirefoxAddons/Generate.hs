{-# LANGUAGE OverloadedStrings #-}

-- | Request construction and fresh, abort-safe JSONL generation.
module FirefoxAddons.Generate (generateSelected, generateFile, detailURL, searchURL) where

import Control.Exception (IOException, try)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.ByteString.Lazy as BL
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import FirefoxAddons.Discover (Range (..))
import FirefoxAddons.JsonLines (encodeJSONLines)
import FirefoxAddons.Model (Addon, canonicalize)
import FirefoxAddons.Publish (writeAtomically)

{- | Validate a selected slug and construct its AMO detail URL.
Accepts ASCII letters, digits, hyphens and underscores only.
-}
detailURL :: Text -> Either String String
detailURL name
  | T.null name || not (T.all safe name) = Left "invalid extension slug"
  | otherwise =
      Right
        ("https://addons.mozilla.org/api/v5/addons/addon/" ++ T.unpack name ++ "/?app=firefox&lang=en-US")
 where
  safe c = c `elem` (['a' .. 'z'] ++ ['A' .. 'Z'] ++ ['0' .. '9'] ++ "-_")

{- | Construct a Firefox-extension search URL (50 results per page).
Callers supply a valid range and positive, one-based page number.
-}
searchURL :: Range -> Int -> String
searchURL (Range low high) page =
  "https://addons.mozilla.org/api/v5/addons/search/?app=firefox&type=extension&lang=en-US&sort=users,created&page_size=50&page="
    ++ show page
    ++ "&users__gte="
    ++ show low
    ++ maybe "" (\n -> "&users__lte=" ++ show n) high

{- | Validate all inputs before requesting; fetch distinct slugs in input order.
The first returned error aborts without requesting later slugs.
-}
generateSelected :: (Text -> IO (Either String Addon)) -> [Text] -> IO (Either String [Addon])
generateSelected fetch names = runExceptT $ do
  if null names then throwE "provide at least one extension slug" else pure ()
  _ <- ExceptT (pure (traverse detailURL names))
  entries <- traverse (ExceptT . fetch) (unique Set.empty names)
  ExceptT (pure (canonicalize entries))
 where
  unique _ [] = []
  unique seen (name : rest)
    | Set.member name seen = unique seen rest
    | otherwise = name : unique (Set.insert name seen) rest

{- | Collect a complete snapshot, canonicalize it, then replace the output.
Never reads or merges an existing catalogue. IO exceptions become errors;
asynchronous cancellation is not swallowed. See atomic-write limitations
in "FirefoxAddons.Publish".
-}
generateFile :: FilePath -> IO (Either String [Addon]) -> IO (Either String Int)
generateFile path collect = do
  outcome <- try run :: IO (Either IOException (Either String Int))
  pure (either (Left . show) id outcome)
 where
  run = runExceptT $ do
    entries <- ExceptT collect
    sorted <- ExceptT (pure (canonicalize entries))
    ExceptT $ do
      writeAtomically path (\handle -> BL.hPut handle (encodeJSONLines sorted))
      pure (Right (length sorted))
