module Main where

import Control.Concurrent (threadDelay)
import Data.Aeson (FromJSON)
import qualified Data.Text as T
import FirefoxAddons.Discover
import FirefoxAddons.Generate
import FirefoxAddons.Model
import FirefoxAddons.Retry (fetchJSONWithRetry)
import System.Environment (getArgs)
import System.Exit (die)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

requestJSON :: (FromJSON a) => String -> IO (Either String a)
requestJSON address = do
  hPutStrLn stderr ("GET " ++ address)
  threadDelay 250000
  result <- fetchJSONWithRetry address
  pure (either (Left . ((address ++ ": ") ++) . show) Right result)

main :: IO ()
main = do
  args <- getArgs
  result <- case args of
    "selected" : output : names@(_ : _) ->
      generateFile output (generateSelected fetchOne (map T.pack names))
    ["discover", output] -> discover output 1
    ["discover", output, minimumText] -> case readMaybe minimumText of
      Just n | n >= 0 -> discover output n
      _ -> die "Minimum daily users must be a nonnegative integer"
    _ ->
      die
        "Usage: addon-fetcher selected OUTPUT.jsonl SLUG [SLUG ...]\n       addon-fetcher discover OUTPUT.jsonl [MIN_DAILY_USERS=1]"
  case result of
    Left err -> die ("Generation aborted: " ++ err)
    Right n -> hPutStrLn stderr ("Wrote " ++ show n ++ " extension records")
 where
  fetchOne name = case detailURL name of
    Left err -> pure (Left err)
    Right address -> requestJSON address :: IO (Either String Addon)
  discover output minimumUsers =
    generateFile output $
      discoverWith 50 30000 (\range page -> requestJSON (searchURL range page)) minimumUsers
