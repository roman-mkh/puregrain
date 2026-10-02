-- | Command-line options, parsed with optparse (a port of Haskell's
-- | optparse-applicative).
module Puregrain.Cli.Options
  ( KernelName(..)
  , PaletteName(..)
  , QuantizerChoice(..)
  , Options
  , allKernels
  , allPalettes
  , kernelName
  , paletteName
  , describeQuantizer
  , parserInfo
  ) where

import Prelude

import Control.Alt ((<|>))
import Data.Array as Array
import Data.Either (Either(..))
import Data.Generic.Rep (class Generic)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Show.Generic (genericShow)
import Data.String (joinWith)
import Data.Tuple (Tuple(..), fst)
import Options.Applicative (Parser, ParserInfo, ReadM, eitherReader, fullDesc, header, help, helper, info, long, metavar, number, option, progDesc, short, showDefaultWith, strArgument, switch, value, (<**>))

data KernelName = FloydSteinberg | Atkinson | JarvisJudiceNinke

derive instance Eq KernelName
derive instance Generic KernelName _
instance Show KernelName where
  show = genericShow

data PaletteName = BlackWhite | Websafe216 | Cga16 | Ansi16 | Ansi256 | C64 | ZxSpectrum

derive instance Eq PaletteName
derive instance Generic PaletteName _
instance Show PaletteName where
  show = genericShow

-- | Which quantizer to build — and so, which kind of error diffusion
-- | runs: a threshold always works on gray; levels work per channel
-- | (scalarED) on color input; a palette picks the nearest palette color
-- | for the whole pixel (vectorED). See "scalarED / vectorED" in CLAUDE.md.
data QuantizerChoice = Threshold Number | Levels Int | Palette PaletteName

derive instance Eq QuantizerChoice
derive instance Generic QuantizerChoice _
instance Show QuantizerChoice where
  show = genericShow

type Options =
  { input :: String
  , output :: String
  , kernel :: KernelName
  , quantizer :: QuantizerChoice
  , gray :: Boolean
  }

-- | Every kernel and palette the CLI offers. Each command-line name lives
-- | only in `kernelName`/`paletteName`: the parse tables and the help
-- | texts are all derived from these lists, so they can't drift apart.
-- | (The compiler checks that the name functions cover every constructor;
-- | it can't check these lists, so a new constructor must be added here.)
allKernels :: Array KernelName
allKernels = [ FloydSteinberg, Atkinson, JarvisJudiceNinke ]

allPalettes :: Array PaletteName
allPalettes = [ BlackWhite, Websafe216, Cga16, Ansi16, Ansi256, C64, ZxSpectrum ]

kernels :: Array (Tuple String KernelName)
kernels = map (\k -> Tuple (kernelName k) k) allKernels

palettes :: Array (Tuple String PaletteName)
palettes = map (\p -> Tuple (paletteName p) p) allPalettes

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

paletteName :: PaletteName -> String
paletteName = case _ of
  BlackWhite -> "bw"
  Websafe216 -> "websafe216"
  Cga16 -> "cga16"
  Ansi16 -> "ansi16"
  Ansi256 -> "ansi256"
  C64 -> "c64"
  ZxSpectrum -> "zx-spectrum"

describeQuantizer :: QuantizerChoice -> String
describeQuantizer = case _ of
  Threshold t -> "threshold " <> show t
  Levels n -> show n <> " levels"
  Palette p -> "palette " <> paletteName p

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

quantizer :: Parser QuantizerChoice
quantizer =
  (Threshold <$> option number
      (long "threshold" <> metavar "T" <> help "1-bit gray: below T black, else white (the default, with T = 128)"))
    <|> (Levels <$> option levelCount
      (long "levels" <> metavar "N" <> help "N evenly spaced levels per channel (scalarED on color input)"))
    <|> (Palette <$> option (oneOf "palette" palettes)
      ( long "palette" <> metavar "NAME"
          <> help ("nearest palette color, whole pixel (vectorED): " <> orList (map fst palettes))
      ))
    <|> pure (Threshold 128.0)

options :: Parser Options
options = ado
  input <- strArgument (metavar "INPUT.png" <> help "image to dither (any PNG; alpha is ignored)")
  output <- strArgument (metavar "OUTPUT.png" <> help "where to write the result")
  kernel <- option (oneOf "kernel" kernels)
    ( long "kernel" <> short 'k' <> metavar "NAME" <> value FloydSteinberg <> showDefaultWith kernelName
        <> help ("error-diffusion kernel: " <> orList (map fst kernels))
    )
  q <- quantizer
  gray <- switch (long "gray" <> help "convert a color input to gray (luma) first")
  in { input, output, kernel, quantizer: q, gray }

parserInfo :: ParserInfo Options
parserInfo = info (options <**> helper)
  ( fullDesc
      <> header "puregrain-cli — error-diffusion dithering of PNG images"
      <> progDesc
        ( "Dithers INPUT.png into OUTPUT.png. Use at most one of --threshold, --levels, --palette. "
            <> "Gray input (or --gray) gives a grayscale PNG; color input with --levels or --palette "
            <> "gives an RGB PNG."
        )
  )
