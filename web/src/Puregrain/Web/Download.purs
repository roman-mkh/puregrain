-- | The download's formats (decision 31 in web/ROADMAP.md): a PNG of the
-- | result for every target, and for a machine its own files, possible
-- | only when the picture is the machine's screen. The download button
-- | names one format: the one chosen last while it's possible, else PNG.
-- | Pure, so specs test it.
module Puregrain.Web.Download
  ( Format(..)
  , extension
  , Choice
  , formatsFor
  , buttonFormat
  ) where

import Prelude

import Data.Array as Array
import Data.Generic.Rep (class Generic)
import Data.Show.Generic (genericShow)
import Puregrain.Web.Settings (MachineName(..), Target(..), screenSizeOf)

-- | A file the result can be saved as: a PNG, the ZX Spectrum's screen
-- | file and tape, the C64's program with a viewer and Art Studio picture.
data Format = Png | Scr | Tap | Prg | Art

derive instance Eq Format
derive instance Generic Format _
instance Show Format where
  show = genericShow

-- | The file's extension, as the CLI names the format, and as the worker
-- | marks a machine's files.
extension :: Format -> String
extension = case _ of
  Png -> "png"
  Scr -> "scr"
  Tap -> "tap"
  Prg -> "prg"
  Art -> "art"

-- | A format offered, and whether it's possible for the picture.
type Choice = { format :: Format, possible :: Boolean }

-- | The formats offered for a target and the picture's size as it's
-- | dithered: PNG, always possible; then a machine's own files, possible
-- | only at its screen's size, where the worker makes them.
formatsFor :: Target -> { width :: Int, height :: Int } -> Array Choice
formatsFor target size =
  [ { format: Png, possible: true } ] <> case target of
    AnyScreen -> []
    Machine machine -> machineFormats machine <#> \format -> { format, possible: size == screenSizeOf machine }
  where
  machineFormats = case _ of
    ZxSpectrumScreen -> [ Scr, Tap ]
    C64HiresScreen -> [ Prg, Art ]

-- | The format the download button names: the one chosen last
-- | (`Format`), while it's one of the choices and possible, else PNG. The
-- | choice itself is kept, so the button comes back to it when it's
-- | possible again.
buttonFormat :: Format -> Array Choice -> Format
buttonFormat chosen choices =
  if Array.any (\c -> c.format == chosen && c.possible) choices then chosen else Png
