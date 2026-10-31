-- | The page's shortcuts (decision 33 in web/ROADMAP.md): Ctrl+O to choose
-- | a picture, Ctrl+S to download, Esc to close the list of formats or to
-- | cancel a run, anywhere on the page; + and − to zoom in the picture
-- | area. Cmd works as Ctrl, on every system. Pure, so specs test it.
module Puregrain.Web.Keys
  ( Pressed
  , Shortcut(..)
  , shortcut
  , zoomStep
  ) where

import Prelude

import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(..))
import Data.Show.Generic (genericShow)
import Data.String.CodeUnits (length, stripPrefix)
import Data.String.Common (toLower)
import Data.String.Pattern (Pattern(..))

-- | A key pressed: its character or name (`KeyboardEvent`'s `key`), its
-- | place on the keyboard (`code`, as on a US keyboard), and the modifier
-- | keys held.
type Pressed =
  { key :: String
  , code :: String
  , ctrl :: Boolean
  , meta :: Boolean
  , alt :: Boolean
  , shift :: Boolean
  }

data Shortcut = ChoosePicture | DownloadNow | Escape

derive instance Eq Shortcut
derive instance Generic Shortcut _
instance Show Shortcut where
  show = genericShow

-- | The page's shortcut a key stands for, if any: Ctrl or Cmd with O or S,
-- | without Shift or Alt (Ctrl+Alt is AltGr on many keyboards), and Esc
-- | without Ctrl, Alt or Cmd.
shortcut :: Pressed -> Maybe Shortcut
shortcut p =
  if p.key == "Escape" then
    if p.ctrl || p.meta || p.alt then Nothing else Just Escape
  else if (p.ctrl || p.meta) && not p.alt && not p.shift then case letter p of
    Just "o" -> Just ChoosePicture
    Just "s" -> Just DownloadNow
    _ -> Nothing
  else Nothing

-- | The letter a key stands for: its character, when that's a Latin
-- | letter, as on most layouts (and on Dvorak, where the letters sit
-- | elsewhere); otherwise the letter of its place, as for a Russian
-- | layout's Ctrl+щ, the key of O. Lower case.
letter :: Pressed -> Maybe String
letter p =
  if latin key then Just key
  else case stripPrefix (Pattern "Key") p.code of
    Just place | latin (toLower place) -> Just (toLower place)
    _ -> Nothing
  where
  key = toLower p.key
  latin s = length s == 1 && s >= "a" && s <= "z"

-- | The zoom step a key asks for in the picture area: one up for + (and
-- | for =, + without Shift on many keyboards), one down for −; none with
-- | Ctrl, Alt or Cmd held, which zoom the browser's page.
zoomStep :: Pressed -> Maybe Int
zoomStep p =
  if p.ctrl || p.meta || p.alt then Nothing
  else case p.key of
    "+" -> Just 1
    "=" -> Just 1
    "-" -> Just (-1)
    _ -> Nothing
