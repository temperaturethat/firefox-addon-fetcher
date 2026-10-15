{-# LANGUAGE OverloadedStrings #-}

module FirefoxAddons.ModelSpec (tests) where

import Control.Monad (forM_)
import Data.Aeson
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import Data.Either (isLeft)
import Data.Text (Text)
import qualified Data.Text as T
import FirefoxAddons.Model
import Paths_firefox_addon_fetcher (getDataFileName)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

fixture :: Value -> Bool -> Maybe Value -> Value
fixture hashValue withPermissions licenseValue =
  object
    [ "guid" .= ("sample@test" :: Text)
    , "slug" .= ("sample" :: Text)
    , "type" .= ("extension" :: Text)
    , "current_version"
        .= object
          ( [ "version" .= ("1" :: Text)
            , "file"
                .= object
                  ( ["url" .= ("https://example.org/sample.xpi" :: Text), "hash" .= hashValue]
                      ++ ["permissions" .= (["tabs"] :: [Text]) | withPermissions]
                  )
            ]
              ++ maybe [] (\value -> ["license" .= value]) licenseValue
          )
    ]

digest :: Value
digest = String ("sha256:" <> T.replicate 64 "a")

example :: Addon
example =
  Addon
    "sample@test"
    "sample"
    "1"
    "https://example.org/sample.xpi"
    (T.replicate 64 "a")
    ["tabs"]
    (Just "MIT")

tests :: TestTree
tests =
  testGroup
    "model"
    [ testCase "saved AMO search page parses permissions and license" $ do
        bytes <- getDataFileName "test/fixtures/amo-page.json" >>= BL.readFile
        page <- either assertFailure pure (eitherDecode bytes :: Either String SearchPage)
        length (results page) @?= 50
        assertBool "positive count" (count page > 0)
        case results page of
          item : _ -> do
            assertBool "permissions retained" (not (null (permissions (addon item))))
            license (addon item) @?= Just "GPL-3.0-only"
          [] -> assertFailure "empty fixture"
    , testCase "normalized JSON contains exactly the seven schema fields" $
        case toJSON example of
          Object o -> do
            KM.size o @?= 7
            forM_ ["guid", "slug", "version", "url", "hash", "permissions", "license"] $ \key ->
              assertBool (show key) (KM.member key o)
          _ -> assertFailure "expected JSON object"
    , testCase "malformed SHA-256 rejected"
        $ forM_
          [ String "sha256:abcd"
          , String ("sha256:" <> T.replicate 64 "g")
          , String ("sha512:" <> T.replicate 64 "a")
          ]
        $ \badHash ->
          case fromJSON (fixture badHash True Nothing) :: Result Addon of
            Error _ -> pure ()
            Success _ -> assertFailure "accepted invalid hash"
    , testCase "missing permissions is not silently an empty permission list" $
        case fromJSON (fixture digest False Nothing) :: Result Addon of
          Error _ -> pure ()
          Success _ -> assertFailure "accepted missing permissions"
    , testCase "missing and null/custom license slugs remain unknown" $
        forM_ [Nothing, Just Null, Just (object ["slug" .= Null])] $ \value ->
          case fromJSON (fixture digest True value) of
            Success a -> license a @?= Nothing
            Error err -> assertFailure err
    , testCase "known license slug retained" $
        case fromJSON (fixture digest True (Just (object ["slug" .= ("MIT" :: Text)]))) of
          Success a -> a @?= example
          Error err -> assertFailure err
    , testCase "identical GUID duplicates collapse and records sort by slug" $ do
        let second = example{guid = "another@test", slug = "aaaa"}
        canonicalize [example, second, example] @?= Right [second, example]
    , testCase "conflicting records for one GUID abort" $
        assertBool "conflict" (isLeft (canonicalize [example, example{version = "different"}]))
    , testCase "different GUIDs sharing a slug abort" $
        assertBool "slug collision" (isLeft (canonicalize [example, example{guid = "other@test"}]))
    , testCase "empty catalogue refused" $
        assertBool "empty snapshot" (isLeft (canonicalize []))
    ]
