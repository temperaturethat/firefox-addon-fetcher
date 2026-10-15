{-# LANGUAGE OverloadedStrings #-}

module FirefoxAddons.DiscoverSpec (tests) where

import Data.Either (isLeft)
import Data.IORef
import qualified Data.Text as T
import FirefoxAddons.Discover
import FirefoxAddons.Model
import Test.Tasty (TestTree)
import Test.Tasty.HUnit (assertBool, testCase)

check :: String -> Bool -> IO ()
check label ok = assertBool label ok

item :: Integer -> Integer -> SearchItem
item n userCount =
  SearchItem
    ( Addon
        (T.pack (show n) <> "@test")
        ("ext-" <> T.pack (show n))
        "1"
        "https://example.org/a.xpi"
        (T.replicate 64 "a")
        []
        (Just "MIT")
    )
    userCount

fakePage :: [SearchItem] -> Range -> Int -> SearchPage
fakePage items (Range lo hi) page =
  let selected = filter (\i -> users i >= lo && maybe True (users i <=) hi) items
      n = toInteger (length selected)
      limited = take 3 selected
   in SearchPage
        n
        (fromInteger ((min 3 n + 1) `div` 2))
        (take 2 (drop ((page - 1) * 2) limited))

tests :: TestTree
tests = testCase "Discover regression scenarios" $ do
  let items = [item 1 8, item 2 6, item 3 4, item 4 2, item 5 1]
  requests <- newIORef []
  let fetch range page = do
        modifyIORef' requests (++ [(range, page)])
        pure (Right (fakePage items range page))
  found <- discoverWith 2 3 fetch 1
  check
    "split capped searches and paginate"
    ((found >>= canonicalize) == canonicalize (map addon items))
  seen <- readIORef requests
  check "leaf pagination exercised" (any ((== 2) . snd) seen)
  check "no pages beyond cap fetched" (notElem (Range 1 Nothing, 2) seen)
  let tooMany = [item 1 1, item 2 1, item 3 1, item 4 1]
  capped <- discoverWith 2 3 (\range page -> pure (Right (fakePage tooMany range page))) 1
  check "unsplittable bucket aborts" (isLeft capped)
  let failLater range page
        | page == 2 = pure (Left "HTTP failure")
        | otherwise = pure (Right (fakePage (take 3 items) range page))
  failed <- discoverWith 2 3 failLater 1
  check "page failure propagates" (failed == Left "HTTP failure")
  let duplicate range page =
        pure
          ( Right
              ( (fakePage (take 3 items) range page)
                  { results = if page == 2 then take 1 items else take 2 items
                  }
              )
          )
  repeated <- discoverWith 2 3 duplicate 1
  check "duplicate page records rejected" (isLeft repeated)
  changed <-
    discoverWith
      2
      3
      ( \range page ->
          pure
            ( Right
                ( (fakePage (take 3 items) range page)
                    { count = if page == 2 then 2 else 3
                    }
                )
            )
      )
      1
  check "changing count aborts" (isLeft changed)
  empty <- discoverWith 2 3 (\_ _ -> pure (Right (SearchPage 0 1 []))) 1
  check "empty discovery fails" (isLeft empty)
  impossible <- discoverWith 2 3 (\_ _ -> pure (Right (SearchPage 0 1 (take 1 items)))) 1
  check "nonempty zero-count page rejected" (isLeft impossible)
  invalid <- discoverWith 2 3 fetch (-1)
  check "negative minimum rejected" (isLeft invalid)
  let withGap = [item 1 8, item 2 8, item 3 8, item 4 8]
  gap <- discoverWith 2 3 (\range page -> pure (Right (fakePage withGap range page))) 1
  check
    "empty child bucket reaches actual cap error"
    ( case gap of
        Left err -> err == "single user-count bucket exceeds search cap"
        _ -> False
    )
  pure ()
