{-# LANGUAGE OverloadedStrings #-}

module FirefoxAddons.HttpSpec (tests) where

import Control.Exception (bracket)
import Data.Aeson (Value)
import qualified Data.ByteString.Char8 as BS
import FirefoxAddons.Http
import Network.Socket (close)
import Support.Http (address, listener, withResponse)
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (assertBool, testCase)

check :: String -> Bool -> IO ()
check name ok = assertBool name ok

tests :: TestTree
tests = testCase "Http regression scenarios" $ do
  let response status extra body =
        BS.concat
          [ "HTTP/1.1 "
          , status
          , "\r\nConnection: close\r\n"
          , extra
          , "Content-Length: "
          , BS.pack (show (BS.length body))
          , "\r\n\r\n"
          , body
          ]
      fetchValue url = fetchJSON url :: IO (Either FetchError Value)
  good <- withResponse (response "200 OK" "" "{}") fetchValue
  check "valid JSON success" (either (const False) (const True) good)
  missing <- withResponse (response "404 Not Found" "" "not JSON") fetchValue
  check "status checked before JSON decoding" $ case missing of
    Left (HttpError 404 Nothing) -> True
    _ -> False
  limited <- withResponse (response "429 Too Many Requests" "Retry-After: 12\r\n" "") fetchValue
  check "Retry-After retained" $ case limited of
    Left (HttpError 429 (Just "12")) -> True
    _ -> False
  bad <- withResponse (response "200 OK" "" "{broken") fetchValue
  check "malformed JSON" $ case bad of
    Left (DecodeError _) -> True
    _ -> False
  schema <-
    withResponse
      (response "200 OK" "" "{}")
      (\url -> fetchJSON url :: IO (Either FetchError Int))
  check "wrong JSON type" $ case schema of
    Left (DecodeError _) -> True
    _ -> False
  invalid <- fetchValue "not a URL"
  check "invalid URL caught" $ case invalid of
    Left (NetworkError _) -> True
    _ -> False
  deadURL <- bracket listener close address
  refused <- fetchValue deadURL
  check "connection failure caught" $ case refused of
    Left (NetworkError _) -> True
    _ -> False
  pure ()
