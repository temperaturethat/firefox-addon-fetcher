{-# LANGUAGE OverloadedStrings #-}

module FirefoxAddons.DiscoverSpec (tests) where

import Data.Either (isLeft)
import Data.IORef
import qualified Data.Text as T
import FirefoxAddons.Discover
import FirefoxAddons.Model
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

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
   in SearchPage
        n
        (max 1 (fromInteger ((min 3 n + 1) `div` 2)))
        (take 2 (drop ((page - 1) * 2) (take 3 selected)))

-- Unscripted requests fail rather than accidentally looping or contacting AMO.
scripted :: [SearchPage] -> IO (Int -> IO (Either String SearchPage), IO [Int])
scripted pages = do
  calls <- newIORef []
  let fetch n = do
        modifyIORef' calls (++ [n])
        pure $
          if n > 0 && n <= length pages
            then Right (pages !! (n - 1))
            else Left "unexpected page request"
  pure (fetch, readIORef calls)

tests :: TestTree
tests =
  testGroup
    "discovery"
    [ testCase "count drift within the current page window is tolerated" $ do
        let entries = [item 1 8, item 2 6, item 3 4]
        (fetch, calls) <- scripted [SearchPage 3 2 (take 2 entries), SearchPage 4 2 (drop 2 entries)]
        result <- discoverWith 2 10 (\_ -> fetch) 1
        result @?= canonicalize (map addon entries)
        calls >>= (@?= [1, 2])
    , testCase "growing page hints include newly advertised pages" $ do
        let entries = [item 1 8, item 2 6, item 3 4, item 4 2, item 5 1]
        (fetch, calls) <-
          scripted
            [ SearchPage 3 2 (take 2 entries)
            , SearchPage 5 3 (take 2 (drop 2 entries))
            , SearchPage 5 3 (drop 4 entries)
            ]
        result <- discoverWith 2 10 (\_ -> fetch) 1
        result @?= canonicalize (map addon entries)
        calls >>= (@?= [1, 2, 3])
    , testCase "shrinking page hints and short pages stop without stale requests" $ do
        (fetch, calls) <-
          scripted
            [SearchPage 6 3 [item 1 8, item 2 6], SearchPage 3 2 [item 3 4]]
        result <- discoverWith 2 10 (\_ -> fetch) 1
        result @?= canonicalize (map addon [item 1 8, item 2 6, item 3 4])
        calls >>= (@?= [1, 2])
    , testCase "empty tail after removals is a normal end" $ do
        (fetch, calls) <- scripted [SearchPage 3 2 [item 1 8, item 2 6], SearchPage 0 1 []]
        result <- discoverWith 2 10 (\_ -> fetch) 1
        result @?= canonicalize (map addon [item 1 8, item 2 6])
        calls >>= (@?= [1, 2])
    , testCase "splits capped searches and paginates each leaf" $ do
        let entries = [item 1 8, item 2 6, item 3 4, item 4 2, item 5 1]
        requests <- newIORef []
        let fetch range page = do
              modifyIORef' requests (++ [(range, page)])
              pure (Right (fakePage entries range page))
        result <- discoverWith 2 3 fetch 1
        result @?= canonicalize (map addon entries)
        seen <- readIORef requests
        assertBool "leaf pagination" (any ((== 2) . snd) seen)
        assertBool "parent never paginated past cap" (notElem (Range 1 Nothing, 2) seen)
    , testCase "partition totals may change between parent and child requests" $ do
        let entries = [item 1 8, item 2 6, item 3 4, item 4 2, item 5 1]
            fetch range page = pure $ Right $ case range of
              Range 1 Nothing -> SearchPage 6 2 (take 2 entries)
              _ -> fakePage entries range page
        result <- discoverWith 2 3 fetch 1
        result @?= canonicalize (map addon entries)
    , testCase "open upper range is not frozen to the first observed maximum" $ do
        let entries = [item 1 8, item 2 6, item 3 4, item 4 2, item 5 1]
            fetch range page = pure $ Right $ case range of
              Range 1 Nothing -> SearchPage 5 2 (take 2 entries)
              _ -> fakePage (item 6 10 : entries) range page
        result <- discoverWith 2 3 fetch 1
        result @?= canonicalize (map addon (item 6 10 : entries))
    , testCase "search growing beyond cap is repartitioned" $ do
        requests <- newIORef []
        let entries = [item 1 8, item 2 6, item 3 4, item 4 2]
            fetch range page = do
              modifyIORef' requests (++ [range])
              pure $ Right $ case (range, page) of
                (Range 1 Nothing, 1) -> SearchPage 3 2 (take 2 entries)
                (Range 1 Nothing, _) -> SearchPage 4 2 (drop 2 entries)
                _ -> fakePage entries range page
        result <- discoverWith 2 3 fetch 1
        result @?= canonicalize (map addon entries)
        seen <- readIORef requests
        assertBool "oversized range was split" (any (/= Range 1 Nothing) seen)
    , testCase "invalid page hints beyond search window abort an indivisible range" $ do
        let fetch _ _ = pure (Right (SearchPage 1 100 [item 1 1]))
        result <- discoverWith 2 3 fetch 1
        result @?= Left "single user-count bucket exceeds search cap"
    , testCase "single user-count bucket above cap still aborts" $ do
        let entries = [item 1 1, item 2 1, item 3 1, item 4 1]
        result <- discoverWith 2 3 (\r p -> pure (Right (fakePage entries r p))) 1
        assertBool "known truncation" (isLeft result)
    , testCase "overlapping pages deduplicate by GUID" $ do
        (fetch, _) <- scripted [SearchPage 3 2 [item 1 8, item 2 6], SearchPage 3 2 [item 2 6, item 3 4]]
        result <- discoverWith 2 10 (\_ -> fetch) 1
        result @?= canonicalize (map addon [item 1 8, item 2 6, item 3 4])
    , testCase "latest observation replaces a GUID changed during discovery" $ do
        let old = item 1 8
            newer = old{addon = (addon old){version = "2", url = "https://example.org/new.xpi"}}
        (fetch, _) <- scripted [SearchPage 3 2 [old, item 2 6], SearchPage 3 2 [newer, item 3 4]]
        result <- discoverWith 2 10 (\_ -> fetch) 1
        result @?= canonicalize [addon newer, addon (item 2 6), addon (item 3 4)]
    , testCase "GUID repeated across moving partitions keeps later observation" $ do
        let old = item 1 2
            newer = old{users = 8, addon = (addon old){version = "2"}}
            fetch range _ = pure $ Right $ case range of
              Range 1 Nothing -> SearchPage 4 2 [item 2 8, old]
              Range 1 (Just 4) -> SearchPage 1 1 [old]
              _ -> SearchPage 2 1 [item 2 8, newer]
        result <- discoverWith 2 3 fetch 1
        result @?= canonicalize [addon newer, addon (item 2 8)]
    , testCase "different GUIDs with same final slug still abort" $ do
        let other = (item 2 6){addon = (addon (item 2 6)){slug = "ext-1"}}
        result <- discoverWith 2 3 (\_ _ -> pure (Right (SearchPage 2 1 [item 1 8, other]))) 1
        assertBool "slug collision is ambiguous" (isLeft result)
    , testCase "records observed before splitting are not lost if later removed" $ do
        let fetch range _ = pure $ Right $ case range of
              Range 1 Nothing -> SearchPage 4 2 [item 1 8, item 2 2]
              Range 1 (Just 4) -> SearchPage 1 1 [item 2 2]
              _ -> SearchPage 0 1 []
        result <- discoverWith 2 3 fetch 1
        result @?= canonicalize (map addon [item 1 8, item 2 2])
    , testCase "page fetch errors still abort" $ do
        (fetch, _) <- scripted [SearchPage 3 2 [item 1 8, item 2 6]]
        result <- discoverWith 2 3 (\_ -> fetch) 1
        result @?= Left "unexpected page request"
    , testCase "empty final discovery is refused" $ do
        result <- discoverWith 2 3 (\_ _ -> pure (Right (SearchPage 0 1 []))) 1
        assertBool "no empty publication" (isLeft result)
    , testCase "short nonterminal page still follows the current page hint" $ do
        (fetch, calls) <- scripted [SearchPage 4 2 [item 1 8], SearchPage 3 2 [item 2 6, item 3 4]]
        result <- discoverWith 2 10 (\_ -> fetch) 1
        result @?= canonicalize (map addon [item 1 8, item 2 6, item 3 4])
        calls >>= (@?= [1, 2])
    , testCase "count hint may disagree with nonempty results" $ do
        result <- discoverWith 2 3 (\_ _ -> pure (Right (SearchPage 0 1 [item 1 8]))) 1
        result @?= canonicalize [addon (item 1 8)]
    , testCase "out of range records still abort" $ do
        result <- discoverWith 2 3 (\_ _ -> pure (Right (SearchPage 1 1 [item 1 0]))) 1
        assertBool "filter ignored" (isLeft result)
    , testCase "oversized response still aborts" $ do
        result <- discoverWith 2 3 (\_ _ -> pure (Right (SearchPage 3 2 [item 1 8, item 2 6, item 3 4]))) 1
        assertBool "invalid response length" (isLeft result)
    , testCase "empty nonterminal page still follows the current page hint" $ do
        (fetch, calls) <- scripted [SearchPage 3 3 [item 1 8], SearchPage 3 3 [], SearchPage 1 3 [item 2 6]]
        result <- discoverWith 2 10 (\_ -> fetch) 1
        result @?= canonicalize (map addon [item 1 8, item 2 6])
        calls >>= (@?= [1, 2, 3])
    , testCase "late cap uses current observations for its split bound" $ do
        let fetch range page = pure $ Right $ case (range, page) of
              (Range 1 Nothing, 1) -> SearchPage 3 2 [item 1 1, item 2 1]
              (Range 1 Nothing, _) -> SearchPage 4 2 [item 3 8, item 4 6]
              (Range 1 (Just 4), _) -> SearchPage 2 1 [item 1 1, item 2 1]
              _ -> SearchPage 2 1 [item 3 8, item 4 6]
        result <- discoverWith 2 3 fetch 1
        result @?= canonicalize (map addon [item 1 1, item 2 1, item 3 8, item 4 6])
    , testCase "negative minimum rejected without requests" $ do
        result <- discoverWith 2 3 (\_ _ -> pure (Left "should not fetch")) (-1)
        result @?= Left "invalid page size, cap or minimum user count"
    ]
