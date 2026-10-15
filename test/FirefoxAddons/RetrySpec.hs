{-# LANGUAGE OverloadedStrings #-}

module FirefoxAddons.RetrySpec (tests) where

import Control.Exception (AsyncException (ThreadKilled), throwIO, try)
import Data.IORef
import Data.Time
import FirefoxAddons.Http
import FirefoxAddons.Retry
import Network.HTTP.Client
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (assertBool, testCase)

check :: String -> Bool -> IO ()
check label ok = assertBool label ok

now :: UTCTime
now = UTCTime (fromGregorian 2026 1 1) 0

scenario :: [Either FetchError Int] -> IO (Either FetchError Int, Int, [Integer])
scenario replies = do
  queue <- newIORef replies
  count <- newIORef (0 :: Int)
  waits <- newIORef []
  let action = do
        modifyIORef' count (+ 1)
        atomicModifyIORef' queue $ \xs -> case xs of
          [] -> error "unexpected extra attempt"
          x : rest -> (rest, x)
      sleep seconds = modifyIORef' waits (++ [seconds])
  result <- retryWith (pure now) sleep action
  attempts <- readIORef count
  delays <- readIORef waits
  pure (result, attempts, delays)

tests :: TestTree
tests = testCase "Retry regression scenarios" $ do
  let transient = Left (HttpError 503 Nothing)
  (ok, calls, delays) <- scenario [transient, transient, Right 7]
  check
    "eventual success with exponential delays"
    (either (const False) (== 7) ok && calls == 3 && delays == [1, 2])
  (failed, exhausted, backoff) <- scenario (replicate 4 transient)
  check
    "four total attempts and no final sleep"
    (either (const True) (const False) failed && exhausted == 4 && backoff == [1, 2, 4])
  mapM_
    ( \code -> do
        (_, n, ds) <- scenario [Left (HttpError code Nothing)]
        check ("permanent HTTP " ++ show code) (n == 1 && null ds)
    )
    [400, 401, 403, 404, 501]
  (_, badCalls, _) <- scenario [Left (DecodeError "bad JSON")]
  check "no decode retry" (badCalls == 1)
  (_, invalidCalls, _) <- scenario [Left (NetworkError (InvalidUrlException "bad" "invalid"))]
  check "no invalid URL retry" (invalidCalls == 1)
  request <- parseRequest "http://127.0.0.1/"
  (_, timeoutCalls, _) <-
    scenario [Left (NetworkError (HttpExceptionRequest request ResponseTimeout)), Right 1]
  check "retry timeout" (timeoutCalls == 2)
  (_, headerCalls, headerWaits) <- scenario [Left (HttpError 429 (Just "12")), Right 1]
  check "honor numeric Retry-After" (headerCalls == 2 && headerWaits == [12])
  (_, _, dateWaits) <- scenario [Left (HttpError 503 (Just "Thu, 01 Jan 2026 00:00:09 GMT")), Right 1]
  check "honor dated Retry-After" (dateWaits == [9])
  (_, _, invalidWaits) <- scenario [Left (HttpError 503 (Just "nonsense")), Right 1]
  check "invalid header falls back" (invalidWaits == [1])
  check "past date" (retryAfterSeconds now "Wed, 31 Dec 2025 23:59:00 GMT" == Just 0)
  check "reject signed delay" (retryAfterSeconds now "-1" == Nothing)
  check "reject empty header" (retryAfterSeconds now "" == Nothing)
  check
    "unbounded integer parsing"
    (retryAfterSeconds now "999999999999999999999" == Just 999999999999999999999)
  cancelled <-
    try (retryWith (pure now) (const (pure ())) (throwIO ThreadKilled)) ::
      IO (Either AsyncException (Either FetchError Int))
  check "cancellation propagates" (case cancelled of Left ThreadKilled -> True; _ -> False)
  (fourth, fourCalls, _) <- scenario [transient, transient, transient, Right 9]
  check "success on fourth attempt" (either (const False) (== 9) fourth && fourCalls == 4)
  (_, _, minimumWaits) <- scenario [transient, Left (HttpError 429 (Just "0")), Right 1]
  check "header does not shorten local backoff" (minimumWaits == [1, 2])
  mapM_
    ( \code -> do
        (_, n, _) <- scenario [Left (HttpError code Nothing), Right 1]
        check ("retryable HTTP " ++ show code) (n == 2)
    )
    [408, 429, 500, 502, 503, 504]
  check "trim header whitespace" (retryAfterSeconds now " \t12\t " == Just 12)
  check "obsolete RFC850 date" (retryAfterSeconds now "Thursday, 01-Jan-26 00:00:09 GMT" == Just 9)
  check "obsolete asctime date" (retryAfterSeconds now "Thu Jan  1 00:00:09 2026" == Just 9)
  pure ()
