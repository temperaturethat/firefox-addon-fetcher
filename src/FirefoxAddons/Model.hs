{-# LANGUAGE OverloadedStrings #-}

{- | AMO response decoding and normalized catalogue metadata.

The JSON decoder accepts AMO objects; the encoder emits the flat JSONL schema.
These are deliberately different formats, not a serialization round trip.
-}
module FirefoxAddons.Model (Addon (..), SearchItem (..), SearchPage (..), canonicalize) where

import Control.Monad (foldM, unless)
import Data.Aeson
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T

-- | Normalized metadata for one Firefox extension; no XPI bytes are downloaded.
data Addon = Addon
  { guid :: Text
  -- ^ AMO extension identity, used for deduplication.
  , slug :: Text
  -- ^ AMO slug used by downstream package consumers.
  , version :: Text
  -- ^ Current public version string.
  , url :: Text
  -- ^ HTTPS URL of the XPI; this program does not fetch its bytes.
  , hash :: Text
  -- ^ SHA-256 hexadecimal digest without the AMO prefix.
  , permissions :: [Text]
  -- ^ Explicit permissions reported by AMO.
  , license :: Maybe Text
  -- ^ AMO license slug, or unknown/custom/missing.
  }
  deriving (Eq, Show)

instance FromJSON Addon where
  parseJSON = withObject "AMO extension" $ \o -> do
    kind <- o .: "type"
    unless (kind == ("extension" :: Text)) (fail "expected an extension")
    current <- o .: "current_version"
    file <- current .: "file"
    rawHash <- file .: "hash"
    digest <- case T.stripPrefix "sha256:" rawHash of
      Just value
        | T.length value == 64
            && T.all (`elem` ("0123456789abcdefABCDEF" :: String)) value ->
            pure value
      _ -> fail "expected sha256: and 64 hexadecimal digits"
    licenseObject <- current .:? "license"
    licenseSlug <- case licenseObject of
      Nothing -> pure Nothing
      Just licenseValue -> licenseValue .:? "slug"
    a <-
      Addon
        <$> o .: "guid"
        <*> o .: "slug"
        <*> current .: "version"
        <*> file .: "url"
        <*> pure digest
        <*> file .: "permissions"
        <*> pure licenseSlug
    unless (all (not . T.null) [guid a, slug a, version a]) (fail "empty identity/version")
    unless (not (T.any (`elem` ("/\\\r\n" :: String)) (guid a))) (fail "unsafe extension GUID")
    unless ("https://" `T.isPrefixOf` url a) (fail "expected HTTPS XPI URL")
    pure a

instance ToJSON Addon where
  toJSON a =
    object
      [ "guid" .= guid a
      , "slug" .= slug a
      , "version" .= version a
      , "url" .= url a
      , "hash" .= hash a
      , "permissions" .= permissions a
      , "license" .= license a
      ]

-- | An extension together with its average daily user count for partitioning.
data SearchItem = SearchItem
  { addon :: Addon
  -- ^ Normalized metadata from the search object.
  , users :: Integer
  -- ^ Nonnegative average daily users.
  }
  deriving (Eq, Show)

instance FromJSON SearchItem where
  parseJSON value =
    withObject
      "search item"
      ( \o -> do
          n <- o .: "average_daily_users"
          unless (n >= 0) (fail "negative daily users")
          SearchItem <$> parseJSON value <*> pure n
      )
      value

-- | A single AMO search page. Counts can exceed the accessible result window.
data SearchPage = SearchPage
  { count :: Integer
  -- ^ Total query matches, possibly exceeding the search cap.
  , pageCount :: Int
  -- ^ Accessible pages reported by AMO.
  , results :: [SearchItem]
  -- ^ Records on this page.
  }
  deriving (Eq, Show)

instance FromJSON SearchPage where
  parseJSON = withObject "search page" $ \o -> do
    p <- SearchPage <$> o .: "count" <*> o .: "page_count" <*> o .: "results"
    unless (count p >= 0 && pageCount p >= 0) (fail "negative page counts")
    pure p

{- | Reject empty/conflicting catalogues, collapse identical GUID duplicates,
and sort by slug. Does not select a winner between differing versions.
-}
canonicalize :: [Addon] -> Either String [Addon]
canonicalize [] = Left "refusing to publish an empty catalogue"
canonicalize entries = do
  byId <- foldM insert Map.empty entries
  _ <- foldM uniqueSlug Map.empty (Map.elems byId)
  pure (sortOn slug (Map.elems byId))
 where
  insert acc a = case Map.lookup (guid a) acc of
    Just old | old /= a -> Left ("conflicting metadata for " ++ T.unpack (guid a))
    _ -> Right (Map.insert (guid a) a acc)
  uniqueSlug acc a = case Map.lookup (slug a) acc of
    Just identity | identity /= guid a -> Left ("slug collision: " ++ T.unpack (slug a))
    _ -> Right (Map.insert (slug a) (guid a) acc)
