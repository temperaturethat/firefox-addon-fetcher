{-# LANGUAGE OverloadedStrings #-}

module FirefoxAddons.GenerateSpec (tests) where

import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Either (isLeft)
import Data.IORef
import FirefoxAddons.Discover
import FirefoxAddons.Generate
import FirefoxAddons.Model
import Support.Temp (withTestDirectory)
import System.FilePath ((</>))
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (assertBool, testCase)

check :: String -> Bool -> IO ()
check label ok = assertBool label ok

tests :: TestTree
tests = testCase "Generate regression scenarios" $ withTestDirectory $ \root -> do
  let path = root </> "catalogue.jsonl"
      original = "original file is not even JSON\n"
      a =
        Addon
          "a@test"
          "a"
          "1"
          "https://example.org/a.xpi"
          "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
          []
          Nothing
  BL.writeFile path original
  calls <- newIORef []
  let fetch name = do
        modifyIORef' calls (++ [name])
        pure (if name == "bad" then Left "failed" else Right a)
  failed <- generateFile path (generateSelected fetch ["a", "bad", "later"])
  check "failure propagates" (isLeft failed)
  afterFailure <- BL.readFile path
  seen <- readIORef calls
  check
    "preserve file on failure and stop requests"
    (afterFailure == original && seen == ["a", "bad"])
  writeIORef calls []
  success <- generateFile path (generateSelected fetch ["a", "a"])
  check "success writes new snapshot" (success == Right 1)
  seenOnce <- readIORef calls
  check "dedup CLI inputs" (seenOnce == ["a"])
  new <- BL.readFile path
  check "replaces rather than merges" (new /= original && length (BL.lines new) == 1)
  empty <- generateFile path (pure (Right []))
  check "empty snapshot refused" (isLeft empty)
  unchanged <- BL.readFile path
  check "empty snapshot leaves file" (unchanged == new)
  invalid <- generateSelected fetch ["../escape"]
  check "unsafe slug rejected" (isLeft invalid)
  check
    "detail URL"
    ( detailURL "ublock-origin"
        == Right "https://addons.mozilla.org/api/v5/addons/addon/ublock-origin/?app=firefox&lang=en-US"
    )
  check
    "range URL filters"
    ( searchURL (Range 1 (Just 4)) 2
        == "https://addons.mozilla.org/api/v5/addons/search/?app=firefox&type=extension&lang=en-US&sort=users,created&page_size=50&page=2&users__gte=1&users__lte=4"
    )
  pure ()
