{-# LANGUAGE OverloadedStrings #-}

-- | A single JSON GET with typed network, status and decoding errors.
module FirefoxAddons.Http (FetchError (..), fetchJSON) where

import Control.Exception (try)
import Data.Aeson (FromJSON, eitherDecode)
import qualified Data.ByteString as BS
import Network.HTTP.Client (HttpException, responseTimeoutMicro)
import Network.HTTP.Simple (
  getResponseBody,
  getResponseHeader,
  getResponseStatusCode,
  httpLBS,
  parseRequest,
  setRequestIgnoreStatus,
  setRequestResponseTimeout,
 )

-- | Expected request failures. Cancellation and unrelated exceptions propagate.
data FetchError
  = -- | Request parsing, transport or timeout failure.
    NetworkError HttpException
  | -- | Non-200 status and raw Retry-After.
    HttpError Int (Maybe BS.ByteString)
  | -- | Aeson syntax or schema validation failure.
    DecodeError String
  deriving (Show)

{- | Fetch and decode one response, checking status before its JSON body.
Uses a 30-second response timeout, not a whole-update deadline.
Does not retry or enforce a response-size bound.
-}
fetchJSON :: (FromJSON a) => String -> IO (Either FetchError a)
fetchJSON url = do
  outcome <- try $ do
    request <- parseRequest url
    httpLBS
      ( setRequestIgnoreStatus
          (setRequestResponseTimeout (responseTimeoutMicro 30000000) request)
      )
  pure $ case outcome of
    Left exception -> Left (NetworkError exception)
    Right response
      | getResponseStatusCode response /= 200 ->
          Left
            ( HttpError
                (getResponseStatusCode response)
                ( case getResponseHeader "Retry-After" response of
                    [] -> Nothing
                    value : _ -> Just value
                )
            )
      | otherwise -> case eitherDecode (getResponseBody response) of
          Left message -> Left (DecodeError message)
          Right value -> Right value
