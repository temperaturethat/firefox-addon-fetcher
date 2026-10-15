{-# LANGUAGE OverloadedStrings #-}

-- | Bounded retries for GET requests, with injectable clock and sleep actions.
module FirefoxAddons.Retry (retryWith, retryAfterSeconds, fetchJSONWithRetry) where

import Control.Applicative ((<|>))
import Control.Concurrent (threadDelay)
import Data.Aeson (FromJSON)
import qualified Data.ByteString.Char8 as BS
import Data.Time (
  UTCTime,
  defaultTimeLocale,
  diffUTCTime,
  getCurrentTime,
  parseTimeM,
 )
import FirefoxAddons.Http (FetchError (..), fetchJSON)
import Network.HTTP.Client (HttpException (..), HttpExceptionContent (..))

retryable :: FetchError -> Bool
retryable (HttpError status _) = status `elem` [408, 429, 500, 502, 503, 504]
retryable (NetworkError (HttpExceptionRequest _ reason)) = case reason of
  ResponseTimeout -> True
  ConnectionTimeout -> True
  ConnectionFailure _ -> True
  ConnectionClosed -> True
  NoResponseDataReceived -> True
  ResponseBodyTooShort _ _ -> True
  _ -> False
retryable _ = False

{- | Parse delay-seconds or HTTP dates; past dates become zero.
Invalid/missing content yields Nothing; integer delays do not overflow Int.
-}
retryAfterSeconds :: UTCTime -> BS.ByteString -> Maybe Integer
retryAfterSeconds now raw
  | not (BS.null value) && BS.all (\c -> c >= '0' && c <= '9') value =
      Just (BS.foldl' (\n c -> n * 10 + toInteger (fromEnum c - fromEnum '0')) 0 value)
  | otherwise = do
      date <-
        parseDate "%a, %d %b %Y %H:%M:%S GMT"
          <|> parseDate "%A, %d-%b-%y %H:%M:%S GMT"
          <|> parseDate "%a %b %e %H:%M:%S %Y"
      pure (max 0 (ceiling (diffUTCTime date now)))
 where
  parseDate format =
    parseTimeM True defaultTimeLocale format (BS.unpack value) ::
      Maybe UTCTime
  value = BS.dropWhileEnd isSpace (BS.dropWhile isSpace raw)
  isSpace c = c == ' ' || c == '\t'

{- | Run at most four attempts, waiting at least 1, 2 and 4 seconds.
A longer Retry-After is honored. The clock and seconds-based sleep action
are injectable for deterministic tests. No wait follows the last failure;
this wrapper does not catch asynchronous exceptions or impose a deadline.
-}
retryWith ::
  IO UTCTime ->
  (Integer -> IO ()) ->
  IO (Either FetchError a) ->
  IO (Either FetchError a)
retryWith clock sleep action = go [1, 2, 4]
 where
  go delays = do
    result <- action
    case (result, delays) of
      (Left err, fallback : remaining) | retryable err -> do
        now <- clock
        let header = case err of
              HttpError _ raw -> raw >>= retryAfterSeconds now
              _ -> Nothing
            delay = maybe fallback (max fallback) header
        sleep delay
        go remaining
      _ -> pure result

-- Sleep in bounded chunks to avoid converting a huge server delay to Int.
sleepSeconds :: Integer -> IO ()
sleepSeconds seconds
  | seconds <= 0 = pure ()
  | otherwise = do
      let chunk = min 60 seconds
      threadDelay (fromInteger (chunk * 1000000))
      sleepSeconds (seconds - chunk)

-- | Apply the retry policy to a JSON GET using the real clock and sleep.
fetchJSONWithRetry :: (FromJSON a) => String -> IO (Either FetchError a)
fetchJSONWithRetry url = retryWith getCurrentTime sleepSeconds (fetchJSON url)
