{-# LANGUAGE OverloadedStrings #-}

module FirefoxAddons.PublishSpec (tests) where

import Control.Exception (IOException, throwIO, try)
import qualified Data.ByteString as BS
import FirefoxAddons.Publish (writeAtomically)
import Support.Temp (withTestDirectory)
import System.Directory
import System.FilePath ((</>))
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (assertBool, testCase)

check :: String -> Bool -> IO ()
check name ok = assertBool name ok

tests :: TestTree
tests = testCase "Publish regression scenarios" $ withTestDirectory $ \root -> do
  let target = root </> "addons.jsonl"
  BS.writeFile target "old\n"
  failure <-
    try
      ( writeAtomically target $ \handle -> do
          BS.hPut handle "partial"
          throwIO (userError "simulated write failure")
      ) ::
      IO (Either IOException ())
  check "write failure propagated" (either (const True) (const False) failure)
  old <- BS.readFile target
  check "old catalogue preserved" (old == "old\n")
  afterFailure <- listDirectory root
  check "failed temp file removed" (afterFailure == ["addons.jsonl"])
  writeAtomically target $ \handle -> do
    during <- BS.readFile target
    check "old catalogue visible until commit" (during == "old\n")
    BS.hPut handle "new\n"
  new <- BS.readFile target
  check "successful replacement" (new == "new\n")
  let fresh = root </> "fresh.jsonl"
  writeAtomically fresh (\handle -> BS.hPut handle "first\n")
  first <- BS.readFile fresh
  check "create missing catalogue" (first == "first\n")
  let blocked = root </> "blocked"
  createDirectory blocked
  BS.writeFile (blocked </> "keep") "keep"
  renameFailure <-
    try (writeAtomically blocked (\handle -> BS.hPut handle "new")) ::
      IO (Either IOException ())
  check "rename failure propagated" (either (const True) (const False) renameFailure)
  remaining <- listDirectory root
  check "no temporary files remain" (length remaining == 3)
  pure ()
