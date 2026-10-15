{-# LANGUAGE OverloadedStrings #-}

module FirefoxAddons.IntegrationSpec (tests) where

import Data.Aeson (Value, eitherDecode)
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.IORef
import Data.Time (getCurrentTime)
import FirefoxAddons.Discover
import FirefoxAddons.Generate
import FirefoxAddons.Http
import FirefoxAddons.Model
import FirefoxAddons.Retry
import Paths_firefox_addon_fetcher (getDataFileName)
import qualified Support.Http as TestHttp
import Support.Temp (withTestDirectory)
import System.FilePath ((</>))
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (assertBool, testCase)

check :: String -> Bool -> IO ()
check label ok = assertBool label ok

response :: BS.ByteString -> BS.ByteString -> BS.ByteString
response status body =
  BS.concat
    [ "HTTP/1.1 "
    , status
    , "\r\nConnection: close\r\nContent-Length: "
    , BS.pack (show (BS.length body))
    , "\r\n\r\n"
    , body
    ]

tests :: TestTree
tests = testCase "Integration regression scenarios" $ withTestDirectory $ \root -> do
  let output = root </> "extensions.jsonl"
      before = "previous snapshot\n"
  BL.writeFile output before
  body <- getDataFileName "test/fixtures/amo-page.json" >>= BS.readFile
  success <- TestHttp.withResponse (response "200 OK" body) $ \address ->
    generateFile
      output
      ( discoverWith
          50
          30000
          ( \_ _ -> do
              result <- fetchJSON address :: IO (Either FetchError SearchPage)
              -- Treat the saved page as a complete 50-result search for this fixture.
              pure (either (Left . show) (Right . (\p -> p{count = 50, pageCount = 1})) result)
          )
          1
      )
  check "HTTP discovery -> JSONL" (success == Right 50)
  bytes <- BL.readFile output
  check
    "JSONL independently decodable"
    ( all
        ( either (const False) (const True)
            . (eitherDecode :: BL.ByteString -> Either String Value)
        )
        (BL.lines bytes)
    )
  attempts <- newIORef (0 :: Int)
  waits <- newIORef []
  failed <-
    generateFile output $
      discoverWith
        50
        30000
        ( \_ _ -> do
            result <- retryWith getCurrentTime (\s -> modifyIORef' waits (++ [s])) $ do
              modifyIORef' attempts (+ 1)
              TestHttp.withResponse (response "503 Service Unavailable" "") $ \address ->
                fetchJSON address :: IO (Either FetchError SearchPage)
            pure (either (Left . show) Right result)
        )
        1
  check "failure returned" (either (const True) (const False) failed)
  n <- readIORef attempts
  ds <- readIORef waits
  check "HTTP retry budget" (n == 4 && ds == [1, 2, 4])
  after <- BL.readFile output
  check "retry failure preserves JSONL bytes" (after == bytes)
  malformed <- TestHttp.withResponse (response "200 OK" "{broken") $ \address ->
    generateFile output $ do
      result <- fetchJSON address :: IO (Either FetchError Addon)
      pure (either (Left . show) (Right . (: [])) result)
  check "invalid metadata fails" (either (const True) (const False) malformed)
  final <- BL.readFile output
  check "decode failure preserves JSONL bytes" (final == bytes)
  pure ()
