{-# LANGUAGE OverloadedStrings #-}

module FirefoxAddons.JsonLinesSpec (tests) where

import Control.Monad (unless)
import Data.Aeson (Value, eitherDecode, object, (.=))
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Text (Text)
import FirefoxAddons.JsonLines (encodeJSONLines)
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (assertFailure, testCase)

tests :: TestTree
tests = testCase "JsonLines regression scenarios" $ do
  let records =
        [ object ["slug" .= ("example" :: Text)]
        , object ["description" .= ("中文\nsecond line" :: Text)]
        ]
      bytes = encodeJSONLines records
  unless (BL.length (BL.filter (== '\n') bytes) == 2) $
    assertFailure "FAIL: one physical line per record"
  unless (map eitherDecode (BL.lines bytes) == map Right records) $
    assertFailure "FAIL: independent JSON decoding / Unicode / escaped newline"
  unless (BL.isSuffixOf "\n" bytes) $
    assertFailure "FAIL: trailing newline"
  unless (encodeJSONLines ([] :: [Value]) == BL.empty) $
    assertFailure "FAIL: empty catalogue"
  pure ()
