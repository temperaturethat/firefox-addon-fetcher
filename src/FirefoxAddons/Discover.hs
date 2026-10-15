{- | Sequential discovery using disjoint user-count ranges.
Oversized indivisible buckets abort instead of silently truncating.
-}
module FirefoxAddons.Discover (Range (..), discoverWith) where

import Control.Monad (unless)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.Set as Set
import FirefoxAddons.Model

{- | Inclusive lower bound and optional inclusive upper bound on daily users.
The discovery algorithm constructs nonnegative, noninverted ranges.
-}
data Range = Range Integer (Maybe Integer) deriving (Eq, Show)

{- | Discover using an injected search-page fetcher.
Arguments are page size, result cap, fetcher (range and one-based page),
and minimum daily users. The fetcher must sort by descending daily users.
Count drift, conflicting identities, and capped single-value buckets abort.
AMO is mutable; count checks do not establish a transactional snapshot.
-}
discoverWith ::
  Int ->
  Integer ->
  (Range -> Int -> IO (Either String SearchPage)) ->
  Integer ->
  IO (Either String [Addon])
discoverWith size cap fetch minimumUsers = runExceptT $ do
  unless (size > 0 && cap >= toInteger size && minimumUsers >= 0) $
    throwE "invalid page size, cap or minimum user count"
  entries <- walk (Range minimumUsers Nothing)
  ExceptT (pure (canonicalize entries))
 where
  get range page = ExceptT (fetch range page)
  within (Range lo hi) item = users item >= lo && maybe True (users item <=) hi
  walk range@(Range lo hi) = do
    initial <- get range 1
    let first =
          initial{pageCount = if count initial == 0 && pageCount initial == 1 then 0 else pageCount initial}
    unless (all (within range) (results first)) (throwE "API ignored user range")
    unless (count first /= 0 || null (results first)) (throwE "zero count with nonempty results")
    if count first > cap
      then do
        upper <- case hi of
          Just n -> pure n
          Nothing -> case results first of
            [] -> throwE "capped search returned no upper bound"
            items -> pure (maximum (map users items))
        unless (upper > lo) (throwE "single user-count bucket exceeds search cap")
        let midpoint = lo + (upper - lo) `div` 2
        left <- walk (Range lo (Just midpoint))
        right <- walk (Range (midpoint + 1) (Just upper))
        unless (toInteger (length left + length right) == count first) $
          throwE "partition counts changed; rerun discovery"
        pure (left ++ right)
      else do
        let expectedPages = fromInteger ((count first + toInteger size - 1) `div` toInteger size)
        unless (pageCount first == expectedPages) (throwE "truncated or inconsistent pagination")
        let collect page acc
              | page > expectedPages = pure acc
              | otherwise = do
                  response <- if page == 1 then pure first else get range page
                  unless (count response == count first && pageCount response == expectedPages) $
                    throwE "search counts changed; rerun discovery"
                  let expectedItems =
                        fromInteger
                          ( min
                              (toInteger size)
                              (count first - toInteger ((page - 1) * size))
                          )
                  unless (length (results response) == expectedItems && all (within range) (results response)) $
                    throwE "inconsistent page length or user range"
                  collect (page + 1) (results response : acc)
        chunks <- collect 1 []
        let items = concat (reverse chunks)
            ids = map (guid . addon) items
        unless (Set.size (Set.fromList ids) == length ids) $
          throwE "duplicate GUID across search pages; rerun discovery"
        pure (map addon items)
