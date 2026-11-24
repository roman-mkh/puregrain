-- | Pictures from other web pages by their address (v2.6 in
-- | web/ROADMAP.md): a picture dragged from a page brings only its
-- | address, and so does "Copy image address"; the page then fetches it.
-- | Here: finding the address in what a drop or a paste carries, and the
-- | name and the site of the picture fetched. Pure, so specs test it.
module Puregrain.Web.Address
  ( Carried
  , addressIn
  , nameOf
  , siteOf
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmptyArray
import Data.Either (hush)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String (Pattern(..), Replacement(..), contains, drop, indexOf, lastIndexOf, length, replaceAll, split, stripPrefix, take, toLower, trim)
import Data.String.Regex (match, regex)
import Data.String.Regex.Flags (ignoreCase)
import JSURI (decodeURIComponent)

-- | What a drop or a paste carries besides files: its data as a list of
-- | addresses (`text/uri-list`), as HTML and as plain text, each empty
-- | when it has none.
type Carried = { uriList :: String, html :: String, text :: String }

-- | The address of the picture a drop or a paste carries, if any: a
-- | picture's own in its HTML first, since a picture inside a link brings
-- | the link as its address; then the first address of its list; then its
-- | text, when that's an address. Only addresses a page can fetch:
-- | `http:`, `https:` and `data:image/`.
addressIn :: Carried -> Maybe String
addressIn carried = Array.head (Array.catMaybes [ imageIn carried.html, listed carried.uriList, whole carried.text ])
  where
  whole text = if fetchable (trim text) then Just (trim text) else Nothing
  listed list =
    Array.find (\line -> line /= "" && take 1 line /= "#" && fetchable line)
      (map trim (split (Pattern "\n") (replaceAll (Pattern "\r") (Replacement "") list)))

-- | The `src` of the first `<img>` in some HTML whose address a page can
-- | fetch, with `&amp;` decoded, as HTML writes it in addresses.
imageIn :: String -> Maybe String
imageIn html = do
  pattern <- hush (regex "<img\\b[^>]*?\\ssrc\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))" ignoreCase)
  groups <- match pattern html
  src <- Array.head (Array.catMaybes (NonEmptyArray.drop 1 groups))
  let
    address = trim (replaceAll (Pattern "&amp;") (Replacement "&") src)
  if fetchable address then Just address else Nothing

-- | Whether a page can fetch an address: `http:` or `https:`, or a
-- | picture written in the address itself (`data:image/`); with no
-- | spaces, which a sentence would have.
fetchable :: String -> Boolean
fetchable address =
  not (contains (Pattern " ") address) && Array.any (\scheme -> take (length scheme) lower == scheme) [ "http://", "https://", "data:image/" ]
  where
  lower = toLower address

-- | A fetched picture's name, for the page and the downloads: the last
-- | part of its address's path, decoded (`%20` a space), without its query
-- | or fragment; `picture` when the address has none, as a `data:` one.
nameOf :: String -> String
nameOf address = case pathOf address of
  Nothing -> "picture"
  Just path ->
    let
      last = case lastIndexOf (Pattern "/") path of
        Just i -> drop (i + 1) path
        Nothing -> path
      decoded = fromMaybe last (decodeURIComponent last)
    in
      if trim decoded == "" then "picture" else decoded

-- | The site an address is on, as the message names it
-- | (`upload.wikimedia.org`, with its port if it has one); empty for an
-- | address that holds the picture itself (`data:`).
siteOf :: String -> String
siteOf address = case afterScheme address of
  Nothing -> ""
  Just rest -> take (endOfHost rest) rest

-- | The path of an `http:` or `https:` address, without its query and
-- | fragment.
pathOf :: String -> Maybe String
pathOf address = do
  rest <- afterScheme address
  let
    beyond = drop (endOfHost rest) rest
  pure (take (firstOf [ "?", "#" ] beyond) beyond)

-- | What follows `http://` or `https://`, if the address starts so.
afterScheme :: String -> Maybe String
afterScheme address = case stripPrefix (Pattern "http://") lower, stripPrefix (Pattern "https://") lower of
  Just _, _ -> Just (drop 7 address)
  _, Just _ -> Just (drop 8 address)
  _, _ -> Nothing
  where
  lower = toLower address

-- | Where the host ends: at the path, the query or the fragment.
endOfHost :: String -> Int
endOfHost rest = firstOf [ "/", "?", "#" ] rest

-- | The index of the first of some patterns in a string, or its length.
firstOf :: Array String -> String -> Int
firstOf patterns s =
  fromMaybe (length s)
    (Array.head (Array.sort (Array.catMaybes (map (\p -> indexOf (Pattern p) s) patterns))))
