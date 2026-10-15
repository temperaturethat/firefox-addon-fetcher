-- | Same-directory temporary-file publication for atomic visibility on Linux.
module FirefoxAddons.Publish (writeAtomically) where

import Control.Exception (bracketOnError, finally)
import System.Directory (removeFile, renameFile)
import System.FilePath (takeDirectory, takeFileName)
import System.IO (Handle, hClose, openBinaryTempFile)

{- | Write through a callback, close the temporary file, then rename it.
The callback must leave its handle open. On failure, cleanup is attempted
and the exception propagates. Parent directories must already exist.
Does not provide fsync durability, concurrent-writer locking, or preserve
existing permissions. A forced kill can leave a temporary file behind.
-}
writeAtomically :: FilePath -> (Handle -> IO ()) -> IO ()
writeAtomically target writeContents =
  bracketOnError
    (openBinaryTempFile (takeDirectory target) (takeFileName target ++ ".tmp"))
    (\(temporary, handle) -> hClose handle `finally` removeFile temporary)
    ( \(temporary, handle) -> do
        writeContents handle
        hClose handle
        renameFile temporary target
    )
