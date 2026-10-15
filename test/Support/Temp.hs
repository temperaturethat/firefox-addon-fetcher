-- | Test directories use TMPDIR when configured by the caller or Nix sandbox.
module Support.Temp (withTestDirectory) where

import System.IO.Temp (withSystemTempDirectory)

withTestDirectory :: (FilePath -> IO a) -> IO a
withTestDirectory = withSystemTempDirectory "firefox-addon-fetcher-test-"
