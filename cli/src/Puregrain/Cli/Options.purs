-- | Command-line options, parsed with optparse (a port of Haskell's
-- | optparse-applicative).
module Puregrain.Cli.Options
  ( KernelName(..)
  , PaletteName(..)
  , MachineName(..)
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
  , formatName
  , describeQuantizer
  , parseOptions
  ) where

import Prelude

import Control.Alt ((<|>))
import Data.Array as Array
import Data.Either (Either(..))
import Data.Generic.Rep (class Generic)
import Data.Int as Int
import Data.Maybe (Maybe(..), optional)
import Data.Show.Generic (genericShow)
import Data.String (joinWith)
import Data.Tuple (Tuple(..), fst)
import Options.Applicative (ParseError(..), Parser, ParserInfo, ParserResult(..), ReadM, defaultPrefs, eitherReader, execParserPure, fullDesc, header, help, helper, info, long, metavar, number, option, parserFailure, progDesc, short, showDefaultWith, strArgument, switch, value, (<**>))

-- | `NoDiffusion` is the empty kernel: each pixel is quantized on its
-- | own, so `--bayer` with it gives pure ordered dithering.
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

-- | A machine whose screen the image is dithered to, cell by cell. (The
-- | constructor is named for the screen, since `ZxSpectrum` is the
-- | palette's, whose command-line name is "zx15".)
data MachineName = ZxSpectrumScreen

derive instance Eq MachineName
derive instance Generic MachineName _
instance Show MachineName where
  show = genericShow

-- | The output file's format: a PNG, or a machine's own screen file (the
-- | ZX Spectrum's, for `--machine zx-spectrum`).
data FormatName = Png | Scr

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
-- | a few colors; the machine defines them all.
data QuantizerChoice
  = Threshold Number
  | Levels Int
  | Palette PaletteName
  | Bayer { side :: Int, levels :: Int }
  | Machine MachineName

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
allMachines = [ ZxSpectrumScreen ]

allFormats :: Array FormatName
allFormats = [ Png, Scr ]

kernels :: Array (Tuple String KernelName)
kernels = map (\k -> Tuple (kernelName k) k) allKernels

palettes :: Array (Tuple String PaletteName)
palettes = map (\p -> Tuple (paletteName p) p) allPalettes

machines :: Array (Tuple String MachineName)
machines = map (\m -> Tuple (machineName m) m) allMachines

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

formatName :: FormatName -> String
formatName = case _ of
  Png -> "png"
  Scr -> "scr"

describeQuantizer :: QuantizerChoice -> String
describeQuantizer = case _ of
  Threshold t -> "threshold " <> show t
  Levels n -> show n <> " levels"
  Palette p -> "palette " <> paletteName p
  Bayer { side, levels } -> "Bayer " <> show side <> "x" <> show side <> ", " <> show levels <> " levels"
  Machine m -> machineName m

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
  , kernel :: KernelName
  , quantizer :: Maybe QuantizerChoice
  , bayer :: Maybe Int
  , machine :: Maybe MachineName
  , format :: FormatName
  , gray :: Boolean
  }

rawOptions :: Parser RawOptions
rawOptions = ado
  input <- strArgument (metavar "INPUT.png" <> help "image to dither (any PNG; alpha is ignored)")
  output <- strArgument (metavar "OUTPUT" <> help "where to write the result (a PNG unless --format says otherwise)")
  kernel <- option (oneOf "kernel" kernels)
    ( long "kernel" <> short 'k' <> metavar "NAME" <> value FloydSteinberg <> showDefaultWith kernelName
        <> help ("error-diffusion kernel (none: no diffusion): " <> orList (map fst kernels))
    )
  q <- quantizer
  bayer <- optional $ option bayerSide
    ( long "bayer" <> metavar "N"
        <> help "ordered dithering with the N x N Bayer map (N = 2, 4, 8 or 16), over --levels (default 2)"
    )
  machine <- optional $ option (oneOf "machine" machines)
    ( long "machine" <> metavar "NAME"
        <> help ("dither to a machine's screen, a few colors per cell: " <> orList (map fst machines))
    )
  format <- option (oneOf "format" formats)
    ( long "format" <> metavar "NAME" <> value Png <> showDefaultWith formatName
        <> help
          ( "output file format: " <> orList (map fst formats) <> "; " <> formatName Scr
              <> " is the ZX Spectrum's screen file, for --machine " <> machineName ZxSpectrumScreen
              <> " on a 256x192 image"
          )
    )
  gray <- switch (long "gray" <> help "convert a color input to gray (luma) first")
  in { input, output, kernel, quantizer: q, bayer, machine, format, gray }

parserInfo :: ParserInfo RawOptions
parserInfo = info (rawOptions <**> helper)
  ( fullDesc
      <> header "puregrain-cli - error-diffusion and ordered dithering of PNG images"
      <> progDesc
        ( "Dithers INPUT.png into OUTPUT. Use at most one of --threshold, --levels, --palette; "
            <> "--bayer N adds ordered dithering to --levels, or to black and white on its own. "
            <> "Gray input (or --gray) gives a grayscale PNG; color input with --levels, --bayer "
            <> "or --palette gives an RGB PNG. --machine zx-spectrum dithers to the ZX Spectrum's "
            <> "screen, two colors per 8x8 cell, and gives an RGB PNG, or with --format scr the "
            <> "Spectrum's own screen file."
        )
  )

-- | The checks across options that optparse can't express: `--bayer`
-- | works over levels, so it combines with `--levels` and nothing else;
-- | `--machine` defines all the colors, so it combines with none of the
-- | quantizer options (`--kernel` and `--gray` work with everything); a
-- | screen file holds a machine's screen, so `--format scr` needs
-- | `--machine zx-spectrum`.
resolve :: RawOptions -> Either String Options
resolve raw = ado
  quantizer <- case raw.machine of
    Just m -> machineChoice m
    Nothing -> quantizerChoice
  format <- formatChoice
  in { input: raw.input, output: raw.output, kernel: raw.kernel, quantizer, format, gray: raw.gray }
  where
  machineChoice m = case raw.quantizer, raw.bayer of
    Nothing, Nothing -> Right (Machine m)
    Just _, _ -> Left "--machine can't be combined with --threshold, --levels or --palette: the machine defines the colors"
    Nothing, Just _ -> Left "--machine can't be combined with --bayer: ordered dithering within a machine's cells isn't supported"
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
  -- No wildcard for the machine: a new machine must decide its formats.
  formatChoice = case raw.format, raw.machine of
    Png, _ -> Right Png
    Scr, Just ZxSpectrumScreen -> Right Scr
    Scr, Nothing ->
      Left ("--format " <> formatName Scr <> " needs --machine " <> machineName ZxSpectrumScreen <> ": the file holds a ZX Spectrum screen")

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
