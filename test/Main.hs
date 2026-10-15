module Main (main) where

import qualified FirefoxAddons.DiscoverSpec as Discover
import qualified FirefoxAddons.GenerateSpec as Generate
import qualified FirefoxAddons.HttpSpec as Http
import qualified FirefoxAddons.IntegrationSpec as Integration
import qualified FirefoxAddons.JsonLinesSpec as JsonLines
import qualified FirefoxAddons.ModelSpec as Model
import qualified FirefoxAddons.Properties as Properties
import qualified FirefoxAddons.PublishSpec as Publish
import qualified FirefoxAddons.RetrySpec as Retry
import Test.Tasty (defaultMain, localOption, mkTimeout, testGroup)

main :: IO ()
main =
  defaultMain $
    localOption (mkTimeout 10000000) $
      testGroup
        "firefox-addon-fetcher"
        [ Model.tests
        , Discover.tests
        , Generate.tests
        , Http.tests
        , Retry.tests
        , JsonLines.tests
        , Publish.tests
        , Integration.tests
        , Properties.tests
        ]
