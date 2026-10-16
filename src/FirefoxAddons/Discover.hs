{- | Best-effort discovery over a live catalogue using user-count ranges.
Oversized indivisible buckets abort instead of silently truncating.
-}
module FirefoxAddons.Discover (Range (..), discoverWith) where

import Control.Monad (unless)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.Map.Strict as Map
import FirefoxAddons.Model

-- | Inclusive lower bound and optional inclusive upper bound on daily users.
data Range = Range Integer (Maybe Integer) deriving (Eq, Show)

{- | Discover using an injected search-page fetcher (range, one-based page).
Arguments are page size, search-window cap, fetcher and minimum daily users.
The fetcher must sort by descending users. Counts/page hints may change;
page lengths need not match earlier totals. Known capped ranges are split.
AMO does not provide transactional snapshots: records may be missed as they move.
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
  -- Preserve observation order through traversal; the last record for each GUID
  -- wins as extensions may legitimately update or cross user-count partitions.
  let latest = foldl' (\acc entry -> Map.insert (guid entry) entry acc) Map.empty entries
  ExceptT (pure (canonicalize (Map.elems latest)))
 where
  maxPages = (cap + toInteger size - 1) `div` toInteger size
  overCap response = count response > cap || toInteger (pageCount response) > maxPages
  get range page = do
    response <- ExceptT (fetch range page)
    unless (length (results response) <= size && all (within range) (results response)) $
      throwE ("invalid page length or user range at " ++ show range ++ " page " ++ show page)
    pure response
  within (Range lo hi) entry = users entry >= lo && maybe True (users entry <=) hi
  walk range = do
    first <- get range 1
    collect range 1 first []
  split range@(Range lo hi) observations = do
    upper <- case hi of
      Just n -> pure n
      Nothing -> case observations of
        [] -> throwE ("capped search returned no split bound at " ++ show range)
        items -> pure (maximum (map users items))
    unless (upper > lo) (throwE "single user-count bucket exceeds search cap")
    let midpoint = lo + (upper - lo) `div` 2
    left <- walk (Range lo (Just midpoint))
    -- Retain an open upper bound: later records may exceed the earlier maximum.
    right <- walk (Range (midpoint + 1) hi)
    pure (left ++ right)
  collect range page response acc
    -- Check every response: a formerly uncapped range can grow past the window.
    | overCap response = do
        children <- split range (concat (reverse (results response : acc)))
        pure (map addon (concat (reverse (results response : acc))) ++ children)
    | otherwise = do
        let gathered = results response : acc
        if page >= pageCount response
          then pure (map addon (concat (reverse gathered)))
          else do
            next <- get range (page + 1)
            collect range (page + 1) next gathered
