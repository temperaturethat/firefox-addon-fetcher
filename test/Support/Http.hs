{-# LANGUAGE OverloadedStrings #-}

-- | Loopback HTTP resources used only by the offline test suite.
module Support.Http (listener, address, withResponse) where

import Control.Concurrent (forkIO, killThread)
import Control.Exception (bracket, finally)
import Control.Monad (unless)
import qualified Data.ByteString.Char8 as BS
import Network.Socket
import System.IO

listener :: IO Socket
listener = do
  sock <- socket AF_INET Stream defaultProtocol
  bind sock (SockAddrInet 0 (tupleToHostAddress (127, 0, 0, 1)))
  listen sock 1
  pure sock

address :: Socket -> IO String
address sock = do
  SockAddrInet port _ <- getSocketName sock
  pure ("http://127.0.0.1:" ++ show port ++ "/")

withResponse :: BS.ByteString -> (String -> IO a) -> IO a
withResponse response action = bracket listener close $ \sock -> do
  url <- address sock
  let serve = do
        (conn, _) <- accept sock
        handle <- socketToHandle conn ReadWriteMode
        flip finally (hClose handle) $ do
          hSetBinaryMode handle True
          let headers = do
                line <- BS.hGetLine handle
                unless (line == "\r") headers
          headers
          BS.hPut handle response
          hFlush handle
  bracket (forkIO serve) killThread (const (action url))
