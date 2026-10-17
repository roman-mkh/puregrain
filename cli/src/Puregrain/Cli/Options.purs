-- | Command-line options, parsed with optparse (a port of Haskell's
-- | optparse-applicative).
module Puregrain.Cli.Options
  ( KernelName(..)
  , PaletteName(..)
  , MachineName(..)
  , MachinePaletteName(..)
  , FormatName(..)
  , QuantizerChoice(..)
  , Options
  , allKernels
  , allPalettes
  , allMachines
  , allFormats
  , kernelName
  , paletteName
  , machineName
  , machinePaletteName
  , allMachinePalettes
  , formatName
  , splitFileName
  , describeQuantizer
  , parseOptions
  ) where

import Prelude

import Control.Alt ((<|>))
import Data.Array as Array
import Data.Either (Either(..))
import Data.Generic.Rep (class Generic)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe, isJust, maybe, optional)
import Data.Show.Generic (genericShow)
import Data.String (Pattern(..), Replacement(..), joinWith, replaceAll, split, toLower)
import Data.String.CodeUnits as CodeUnits
import Data.Tuple (Tuple(..), fst)
import Options.Applicative (ParseError(..), Parser, ParserInfo, ParserResult(..), ReadM, defaultPrefs, eitherReader, execParserPure, fullDesc, header, help, helper, info, long, metavar, number, option, parserFailure, progDesc, short, strArgument, switch, (<**>))

-- | `NoDiffusion` is the empty kernel: each pixel is quantized on its
-- | own, so `--bayer` with it gives pure ordered dithering (the default
-- | with `--bayer`, see `resolve`).
data KernelName = FloydSteinberg | Atkinson | JarvisJudiceNinke | NoDiffusion

derive instance Eq KernelName
derive instance Generic KernelName _
instance Show KernelName where
  show = genericShow

data PaletteName = BlackWhite | Websafe216 | Cga16 | Ansi16 | Ansi256 | C64 | ZxSpectrum

derive instance Eq PaletteName
derive instance Generic PaletteName _
instance Show PaletteName where
  show = genericShow

-- | A machine's screen the image is dithered to, cell by cell: the ZX
-- | Spectrum's, or the Commodore 64's hires mode. (The constructors are
-- | named for the screens: `ZxSpectrum` and `C64` are the palettes', whose
-- | command-line names are "zx15" and "c64".)
data MachineName = ZxSpectrumScreen | C64HiresScreen

derive instance Eq MachineName
derive instance Generic MachineName _
instance Show MachineName where
  show = genericShow

-- | Which of a machine's colors its cells may use, by the machine's own
-- | terms: on the ZX Spectrum, all of them, or normal brightness only, or
-- | BRIGHT only (with black).
data MachinePaletteName = FullPalette | NormalPalette | BrightPalette

derive instance Eq MachinePaletteName
derive instance Generic MachinePaletteName _
instance Show MachinePaletteName where
  show = genericShow

-- | The output file's format: a PNG, or for `--machine zx-spectrum` the
-- | Spectrum's own screen file or a tape image that loads and shows it.
data FormatName = Png | Scr | Tap

derive instance Eq FormatName
derive instance Generic FormatName _
instance Show FormatName where
  show = genericShow

-- | Which quantizer to build — and so, which kind of error diffusion
-- | runs: a threshold always works on gray; levels work per channel
-- | (scalarED) on color input; a palette picks the nearest palette color
-- | for the whole pixel (vectorED). See "scalarED / vectorED" in CLAUDE.md.
-- | `Bayer` is levels with ordered dithering: the side of the Bayer map,
-- | and the number of levels (2 unless `--levels` says otherwise).
-- | `Machine` dithers to a machine's screen, whose cells each allow only
-- | a few colors; the machine defines them all. With `bayer`, the side of
-- | a Bayer map, it's ordered dithering inside the cells.
data QuantizerChoice
  = Threshold Number
  | Levels Int
  | Palette PaletteName
  | Bayer { side :: Int, levels :: Int }
  | Machine { name :: MachineName, palette :: MachinePaletteName, bayer :: Maybe Int }

derive instance Eq QuantizerChoice
derive instance Generic QuantizerChoice _
instance Show QuantizerChoice where
  show = genericShow

type Options =
  { input :: String
  , output :: String
  , kernel :: KernelName
  , quantizer :: QuantizerChoice
  , format :: FormatName
  , gray :: Boolean
  }

-- | Every kernel and palette the CLI offers. Each command-line name lives
-- | only in `kernelName`/`paletteName`: the parse tables and the help
-- | texts are all derived from these lists, so they can't drift apart.
-- | (The compiler checks that the name functions cover every constructor;
-- | it can't check these lists, so a new constructor must be added here.)
allKernels :: Array KernelName
allKernels = [ FloydSteinberg, Atkinson, JarvisJudiceNinke, NoDiffusion ]

allPalettes :: Array PaletteName
allPalettes = [ BlackWhite, Websafe216, Cga16, Ansi16, Ansi256, C64, ZxSpectrum ]

allMachines :: Array MachineName
allMachines = [ ZxSpectrumScreen, C64HiresScreen ]

allMachinePalettes :: Array MachinePaletteName
allMachinePalettes = [ FullPalette, NormalPalette, BrightPalette ]

allFormats :: Array FormatName
allFormats = [ Png, Scr, Tap ]

kernels :: Array (Tuple String KernelName)
kernels = map (\k -> Tuple (kernelName k) k) allKernels

palettes :: Array (Tuple String PaletteName)
palettes = map (\p -> Tuple (paletteName p) p) allPalettes

machines :: Array (Tuple String MachineName)
machines = map (\m -> Tuple (machineName m) m) allMachines

machinePalettes :: Array (Tuple String MachinePaletteName)
machinePalettes = map (\p -> Tuple (machinePaletteName p) p) allMachinePalettes

formats :: Array (Tuple String FormatName)
formats = map (\f -> Tuple (formatName f) f) allFormats

-- | "a, b or c"
orList :: Array String -> String
orList names = case Array.unsnoc names of
  Just { init, last } | not (Array.null init) -> joinWith ", " init <> " or " <> last
  _ -> joinWith "" names

kernelName :: KernelName -> String
kernelName = case _ of
  FloydSteinberg -> "floyd-steinberg"
  Atkinson -> "atkinson"
  JarvisJudiceNinke -> "jjn"
  NoDiffusion -> "none"

paletteName :: PaletteName -> String
paletteName = case _ of
  BlackWhite -> "bw"
  Websafe216 -> "websafe216"
  Cga16 -> "cga16"
  Ansi16 -> "ansi16"
  Ansi256 -> "ansi256"
  C64 -> "c64"
  -- Named by its color count, like cga16 and ansi16, so "zx-spectrum"
  -- means only the machine's screen (`--machine zx-spectrum`).
  ZxSpectrum -> "zx15"

machineName :: MachineName -> String
machineName = case _ of
  ZxSpectrumScreen -> "zx-spectrum"
  C64HiresScreen -> "c64-hires"

-- | The palettes a machine offers, by its own terms; the first is the
-- | default. No wildcard: a new machine must list its own.
machinePalettesOf :: MachineName -> Array MachinePaletteName
machinePalettesOf = case _ of
  ZxSpectrumScreen -> [ FullPalette, NormalPalette, BrightPalette ]
  C64HiresScreen -> [ FullPalette ]

-- | The Spectrum's own terms: normal and BRIGHT.
machinePaletteName :: MachinePaletteName -> String
machinePaletteName = case _ of
  FullPalette -> "full"
  NormalPalette -> "normal"
  BrightPalette -> "bright"

formatName :: FormatName -> String
formatName = case _ of
  Png -> "png"
  Scr -> "scr"
  Tap -> "tap"

describeQuantizer :: QuantizerChoice -> String
describeQuantizer = case _ of
  Threshold t -> "threshold " <> show t
  Levels n -> show n <> " levels"
  Palette p -> "palette " <> paletteName p
  Bayer { side, levels } -> "Bayer " <> show side <> "x" <> show side <> ", " <> show levels <> " levels"
  Machine { name, palette, bayer } ->
    machineName name
      <> (if palette == FullPalette then "" else " (" <> machinePaletteName palette <> ")")
      <> maybe "" (\side -> ", Bayer " <> show side <> "x" <> show side) bayer

-- | A reader for one of a fixed set of names, listing them on a mistake.
oneOf :: forall a. String -> Array (Tuple String a) -> ReadM a
oneOf what choices = eitherReader \s ->
  case Array.find (\(Tuple name _) -> name == s) choices of
    Just (Tuple _ a) -> Right a
    Nothing -> Left ("unknown " <> what <> " \"" <> s <> "\"; use one of: " <> joinWith ", " (map fst choices))

levelCount :: ReadM Int
levelCount = eitherReader \s ->
  case Int.fromString s of
    Just n | n >= 2 -> Right n
    _ -> Left ("levels must be a whole number >= 2, got \"" <> s <> "\"")

-- | The side of a Bayer map: a power of 2 from 2 to 16. (With 8-bit
-- | input, 16 × 16 already gives 256 thresholds, one per input level; the
-- | library itself takes any power of 2.)
bayerSide :: ReadM Int
bayerSide = eitherReader \s ->
  case Int.fromString s of
    Just n | Array.elem n [ 2, 4, 8, 16 ] -> Right n
    _ -> Left ("bayer must be a power of 2 from 2 to 16 (the matrix side), got \"" <> s <> "\"")

-- | At most one of --threshold, --levels and --palette; none means the
-- | default, which depends on --bayer (see `resolve`).
quantizer :: Parser (Maybe QuantizerChoice)
quantizer = optional $
  (Threshold <$> option number
      (long "threshold" <> metavar "T" <> help "1-bit gray: below T black, else white (the default, with T = 128)"))
    <|> (Levels <$> option levelCount
      (long "levels" <> metavar "N" <> help "N evenly spaced levels per channel (scalarED on color input)"))
    <|> (Palette <$> option (oneOf "palette" palettes)
      ( long "palette" <> metavar "NAME"
          <> help ("nearest palette color, whole pixel (vectorED): " <> orList (map fst palettes))
      ))

-- | What optparse can check on its own. `--bayer` and `--machine` are
-- | separate options, and `resolve` checks how they combine with the
-- | others.
type RawOptions =
  { input :: String
  , output :: String
  , kernel :: Maybe KernelName
  , quantizer :: Maybe QuantizerChoice
  , bayer :: Maybe Int
  , machine :: Maybe MachineName
  , machinePalette :: Maybe MachinePaletteName
  , format :: Maybe FormatName
  , gray :: Boolean
  }

rawOptions :: Parser RawOptions
rawOptions = ado
  input <- strArgument (metavar "INPUT.png" <> help "image to dither (any PNG; alpha is ignored)")
  output <- strArgument
    ( metavar "OUTPUT"
        <> help ("where to write the result; its extension, " <> orList (map ("." <> _) (map fst formats)) <> ", picks the format unless --format is given")
    )
  -- No `value` here: the default depends on --bayer (see `resolve`).
  kernel <- optional $ option (oneOf "kernel" kernels)
    ( long "kernel" <> short 'k' <> metavar "NAME"
        <> help
          ( "error-diffusion kernel (none: no diffusion): " <> orList (map fst kernels) <> " (default: "
              <> kernelName FloydSteinberg <> "; " <> kernelName NoDiffusion <> " with --bayer)"
          )
    )
  q <- quantizer
  bayer <- optional $ option bayerSide
    ( long "bayer" <> metavar "N"
        <> help "ordered dithering with the N x N Bayer map (N = 2, 4, 8 or 16), over --levels (default 2) or inside --machine's cells; no error diffusion unless --kernel is given"
    )
  machine <- optional $ option (oneOf "machine" machines)
    ( long "machine" <> metavar "NAME"
        <> help ("dither to a machine's screen, a few colors per cell: " <> orList (map fst machines))
    )
  machinePalette <- optional $ option (oneOf "machine palette" machinePalettes)
    ( long "machine-palette" <> metavar "NAME"
        <> help
          ( "which of the machine's colors the cells may use: " <> orList (map fst machinePalettes)
              <> " (default: " <> machinePaletteName FullPalette <> "); for " <> machineName ZxSpectrumScreen <> ", "
              <> machinePaletteName NormalPalette <> " is without BRIGHT, " <> machinePaletteName BrightPalette
              <> " BRIGHT only; " <> machineName C64HiresScreen <> " offers only " <> machinePaletteName FullPalette
          )
    )
  -- No `value` here: without --format, the output's extension decides (see `resolve`).
  format <- optional $ option (oneOf "format" formats)
    ( long "format" <> metavar "NAME"
        <> help
          ( "output file format: " <> orList (map fst formats) <> " (default: from OUTPUT's extension); " <> formatName Scr
              <> " is the ZX Spectrum's screen file, " <> formatName Tap
              <> " a tape image that loads and shows it, for --machine " <> machineName ZxSpectrumScreen
              <> " on a 256x192 image"
          )
    )
  gray <- switch (long "gray" <> help "convert a color input to gray (luma) first")
  in { input, output, kernel, quantizer: q, bayer, machine, machinePalette, format, gray }

parserInfo :: ParserInfo RawOptions
parserInfo = info (rawOptions <**> helper)
  ( fullDesc
      <> header "puregrain-cli - error-diffusion and ordered dithering of PNG images"
      <> progDesc
        ( "Dithers INPUT.png into OUTPUT, whose extension picks the format unless --format is given. "
            <> "Use at most one of --threshold, --levels, --palette; "
            <> "--bayer N gives ordered dithering, over --levels, black and white, or inside --machine's cells; without --kernel it passes no error on. "
            <> "Gray input (or --gray) gives a grayscale PNG; color input with --levels, --bayer "
            <> "or --palette gives an RGB PNG. --machine zx-spectrum dithers to the ZX Spectrum's "
            <> "screen, two colors per 8x8 cell; as .scr or .tap it writes the Spectrum's own screen file "
            <> "or a tape image. --machine c64-hires dithers to the Commodore 64's hires screen, also "
            <> "two colors per 8x8 cell."
        )
  )

-- | The checks across options that optparse can't express: `--bayer`
-- | works over levels or inside a machine's cells, so it combines with
-- | `--levels` or `--machine` and nothing else; `--machine` defines all
-- | the colors, so it combines with none of the quantizer options
-- | (`--kernel` and `--gray` work with everything); `--machine-palette`
-- | picks among the machine's colors, so it needs `--machine`; a
-- | screen file or tape holds a machine's screen, so `scr` and `tap`
-- | output need `--machine zx-spectrum`. Without `--format`, the output's
-- | extension picks the format, and an extension that names none is
-- | rejected with advice; an explicit `--format` always wins, so
-- | `--format png` writes a PNG under any name. Without `--kernel`, the kernel is
-- | Floyd–Steinberg, except with `--bayer`: there it's none, so `--bayer`
-- | alone is pure ordered dithering. With `--bayer` the kernel decides
-- | which method runs, pure or the hybrid, so that's the one mode with a
-- | default of its own.
resolve :: RawOptions -> Either String Options
resolve raw = ado
  quantizer <- case raw.machine of
    Just m -> machineChoice m
    Nothing ->
      if isJust raw.machinePalette then Left "--machine-palette needs --machine: it picks among a machine's colors"
      else quantizerChoice
  format <- formatOf raw.format raw.output >>= formatChoice
  in { input: raw.input, output: raw.output, kernel: fromMaybe defaultKernel raw.kernel, quantizer, format, gray: raw.gray }
  where
  defaultKernel = if isJust raw.bayer then NoDiffusion else FloydSteinberg
  machineChoice m = case raw.quantizer of
    Nothing -> (\palette -> Machine { name: m, palette, bayer: raw.bayer }) <$> paletteChoice m (fromMaybe FullPalette raw.machinePalette)
    Just _ -> Left "--machine can't be combined with --threshold, --levels or --palette: the machine defines the colors"
  quantizerChoice = case raw.quantizer, raw.bayer of
    Nothing, Nothing -> Right (Threshold 128.0)
    Nothing, Just side -> Right (Bayer { side, levels: 2 })
    Just (Levels levels), Just side -> Right (Bayer { side, levels })
    Just (Palette _), Just _ ->
      Left "--bayer can't be combined with --palette: ordered dithering against a palette isn't supported (see docs/ordered-dithering.md)"
    -- --threshold, or anything else that isn't levels.
    Just _, Just _ ->
      Left "--bayer works over levels: use it alone (2 levels) or with --levels N, not with --threshold"
    Just q, Nothing -> Right q
  paletteChoice m p =
    if Array.elem p (machinePalettesOf m) then Right p
    else Left
      ( "--machine-palette " <> machinePaletteName p <> " isn't one of " <> machineName m
          <> "'s palettes; use one of: " <> joinWith ", " (map machinePaletteName (machinePalettesOf m))
      )
  -- No wildcard for the machine: a new machine must decide its formats.
  formatChoice format = case format, raw.machine of
    Png, _ -> Right Png
    Scr, Just ZxSpectrumScreen -> Right Scr
    Scr, Just C64HiresScreen -> Left (zxOnly Scr)
    Scr, Nothing -> Left (zxOnly Scr)
    Tap, Just ZxSpectrumScreen -> Right Tap
    Tap, Just C64HiresScreen -> Left (zxOnly Tap)
    Tap, Nothing -> Left (zxOnly Tap)
  zxOnly f = formatName f <> " output needs --machine " <> machineName ZxSpectrumScreen <> ": the file holds a ZX Spectrum screen"

-- | The output format: `--format` if given, else the one the output
-- | file's extension names, in any case. `Left` with advice when the
-- | extension names none.
formatOf :: Maybe FormatName -> String -> Either String FormatName
formatOf given output = case given of
  Just f -> Right f
  Nothing -> case Array.find (\f -> formatName f == toLower (splitFileName output).extension) allFormats of
    Just f -> Right f
    Nothing -> Left
      ( "can't tell the output format from \"" <> output <> "\": name it "
          <> orList (map (\f -> "." <> formatName f) allFormats) <> ", or give --format "
          <> orList (map formatName allFormats)
      )

-- | A path's file name, without its directory, split into the stem and
-- | the extension: what follows the last dot, without it, or "" for none.
-- | A leading dot starts a hidden file's name, not an extension. Both `/`
-- | and `\` separate directories.
splitFileName :: String -> { stem :: String, extension :: String }
splitFileName path = case CodeUnits.lastIndexOf (Pattern ".") file of
  Just i | i > 0 -> { stem: CodeUnits.take i file, extension: CodeUnits.drop (i + 1) file }
  _ -> { stem: file, extension: "" }
  where
  file = fromMaybe path (Array.last (split (Pattern "/") (replaceAll (Pattern "\\") (Replacement "/") path)))

-- | Parses a command line (without the program name): optparse's own
-- | checks, then `resolve`. A rejection by `resolve` becomes an ordinary
-- | optparse failure, so it's reported, and exits, like any other.
parseOptions :: Array String -> ParserResult Options
parseOptions args = case execParserPure defaultPrefs parserInfo args of
  Success raw -> case resolve raw of
    Right opts -> Success opts
    Left message -> Failure (parserFailure defaultPrefs parserInfo (ErrorMsg message) [])
  Failure failure -> Failure failure
  CompletionInvoked completion -> CompletionInvoked completion
