{-# LANGUAGE OverloadedStrings #-}

module FirefoxAddons.Properties (tests) where

import Data.Aeson (Value, eitherDecode, toJSON)
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.List (sort)
import qualified Data.Text as T
import Data.Time (UTCTime (..), fromGregorian)
import FirefoxAddons.JsonLines (encodeJSONLines)
import FirefoxAddons.Model
import FirefoxAddons.Retry (retryAfterSeconds)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.QuickCheck

entry :: Int -> Addon
entry n =
  Addon
    { guid = T.pack (show n) <> "@test"
    , slug = "extension-" <> T.pack (show n)
    , version = "1"
    , url = "https://example.org/test.xpi"
    , hash = T.replicate 64 "a"
    , permissions = []
    , license = Nothing
    }

tests :: TestTree
tests =
  testGroup
    "properties"
    [ testProperty "JSONL round trip preserves strings including Unicode/newlines" $
        \texts ->
          let values = map (toJSON . T.pack) (texts :: [String])
           in traverse eitherDecode (BL.lines (encodeJSONLines values)) == Right values
    , testProperty "JSONL has one newline per record" $
        \numbers ->
          let values = map toJSON (numbers :: [Int])
           in BL.count '\n' (encodeJSONLines values) == fromIntegral (length values)
    , testProperty "empty JSONL encodes to empty bytes" $
        encodeJSONLines ([] :: [Value]) === BL.empty
    , testProperty "canonicalization is idempotent" $
        \n -> let initial = canonicalize [entry n] in (initial >>= canonicalize) == initial
    , testProperty "canonicalization ignores input order" $
        \numbers ->
          let entries = map entry (numbers :: [Int])
           in canonicalize entries == canonicalize (reverse entries)
    , testProperty "identical GUID duplicates collapse" $
        \n -> canonicalize [entry n, entry n] == Right [entry n]
    , testProperty "canonicalization sorts slugs" $
        \numbers -> case canonicalize (map entry (numbers :: [Int])) of
          Left _ -> null numbers
          Right entries -> map slug entries == sort (map slug entries)
    , testProperty "Retry-After parses nonnegative integer delays" $
        \number ->
          let n = toInteger (getNonNegative (number :: NonNegative Int))
              now = UTCTime (fromGregorian 2026 1 1) 0
           in retryAfterSeconds now (BS.pack (show n)) == Just n
    ]
