-- | The command-line contract promised in cli/README.md (defaults, which
-- | options exist, what's rejected, exit codes), tested on the real parser.
-- | Not tested: help-text layout (optparse's job, and brittle).
module Test.Puregrain.Cli.OptionsSpec (spec) where

import Prelude

import Data.Either (Either(..), isLeft)
import Data.Foldable (for_)
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), contains)
import Data.Tuple (Tuple(..), fst)
import ExitCodes (ExitCode)
import ExitCodes as ExitCode
import Options.Applicative (ParserResult(..), renderFailure)
import Puregrain.Cli.Options (FormatName(..), KernelName(..), MachineName(..), MachinePaletteName(..), Options, QuantizerChoice(..), allFormats, allKernels, allMachinePalettes, allMachines, allPalettes, formatName, kernelName, machineName, machinePaletteName, paletteName, parseOptions)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual, shouldSatisfy)

-- | Runs the real parser on an argument list, purely: no process argv and
-- | no exit. `Left` carries the text optparse would print for a failure.
parse :: Array String -> Either String Options
parse args = case parseOptions args of
  Success opts -> Right opts
  Failure failure -> Left (fst (renderFailure failure "puregrain-cli"))
  CompletionInvoked _ -> Left "unexpected shell-completion request"

-- | The exit code optparse exits with for a command line it rejects, or
-- | answers itself (like --help). A command line that parses successfully
-- | has no such code, and is reported as a `Left`.
exitCodeOf :: Array String -> Either String ExitCode
exitCodeOf args = case parseOptions args of
  Failure failure -> let Tuple _ code = renderFailure failure "puregrain-cli" in Right code
  _ -> Left "the command line parsed successfully"

failsWith :: String -> Either String Options -> Boolean
failsWith text = case _ of
  Left message -> contains (Pattern text) message
  Right _ -> false

defaults :: Options
defaults = { input: "in.png", output: "out.png", kernel: FloydSteinberg, quantizer: Threshold 128.0, format: Png, gray: false }

files :: Array String
files = [ "in.png", "out.png" ]

-- | The ZX Spectrum's screen, with or without a Bayer map's side.
zx :: Maybe Int -> QuantizerChoice
zx bayer = Machine { name: ZxSpectrumScreen, palette: FullPalette, bayer }

spec :: Spec Unit
spec = describe "Puregrain.Cli.Options (the command-line contract in cli/README.md)" do

  describe "defaults" do
    it "INPUT and OUTPUT alone: Floyd-Steinberg, --threshold 128, a PNG, no --gray" do
      parse files `shouldEqual` Right defaults

  describe "every option" do
    -- Also the round trip between names and constructors: each name the
    -- CLI prints (kernelName) parses back to the same kernel.
    it "--kernel and -k accept every kernel's name" do
      for_ allKernels \k -> do
        parse (files <> [ "--kernel", kernelName k ]) `shouldEqual` Right (defaults { kernel = k })
        parse (files <> [ "-k", kernelName k ]) `shouldEqual` Right (defaults { kernel = k })

    it "--palette accepts every palette's name" do
      for_ allPalettes \p ->
        parse (files <> [ "--palette", paletteName p ]) `shouldEqual` Right (defaults { quantizer = Palette p })

    it "--machine accepts every machine's name" do
      for_ allMachines \m ->
        parse (files <> [ "--machine", machineName m ]) `shouldEqual` Right (defaults { quantizer = Machine { name: m, palette: FullPalette, bayer: Nothing } })

    it "--format accepts every format's name (with --machine zx-spectrum, which scr needs)" do
      for_ allFormats \f ->
        parse (files <> [ "--machine", "zx-spectrum", "--format", formatName f ])
          `shouldEqual` Right (defaults { quantizer = zx Nothing, format = f })

    it "the documented kernel, palette, machine and format names are exactly the ones in the README" do
      map kernelName allKernels `shouldEqual` [ "floyd-steinberg", "atkinson", "jjn", "none" ]
      map paletteName allPalettes `shouldEqual` [ "bw", "websafe216", "cga16", "ansi16", "ansi256", "c64", "zx15" ]
      map machineName allMachines `shouldEqual` [ "zx-spectrum", "c64-hires" ]
      map formatName allFormats `shouldEqual` [ "png", "scr", "tap" ]
      map machinePaletteName allMachinePalettes `shouldEqual` [ "full", "normal", "bright" ]

    it "without --format, the output's extension picks the format, in any case" do
      parse [ "in.png", "out.PNG" ] `shouldEqual` Right (defaults { output = "out.PNG" })
      for_ [ Tuple "pic.scr" Scr, Tuple "pic.tap" Tap, Tuple "v1.2/PIC.TAP" Tap, Tuple "C:\\pics\\pic.Scr" Scr ] \(Tuple output format) ->
        parse [ "in.png", output, "--machine", "zx-spectrum" ]
          `shouldEqual` Right (defaults { output = output, quantizer = zx Nothing, format = format })

    it "--format wins over the extension: --format png writes a PNG under any name" do
      parse [ "in.png", "out.jpg", "--format", "png" ] `shouldEqual` Right (defaults { output = "out.jpg" })
      parse [ "in.png", "screen.bin", "--machine", "zx-spectrum", "--format", "scr" ]
        `shouldEqual` Right (defaults { output = "screen.bin", quantizer = zx Nothing, format = Scr })
      parse [ "in.png", "pic.tap", "--format", "png" ] `shouldEqual` Right (defaults { output = "pic.tap" })

    it "--format png works with every mode" do
      parse (files <> [ "--format", "png" ]) `shouldEqual` Right defaults
      parse (files <> [ "--levels", "4", "--format", "png" ]) `shouldEqual` Right (defaults { quantizer = Levels 4 })

    it "--machine-palette full, normal or bright, with --machine, and with --bayer" do
      for_ allMachinePalettes \p -> do
        parse (files <> [ "--machine", "zx-spectrum", "--machine-palette", machinePaletteName p ])
          `shouldEqual` Right (defaults { quantizer = Machine { name: ZxSpectrumScreen, palette: p, bayer: Nothing } })
        parse (files <> [ "--machine-palette", machinePaletteName p, "--machine", "zx-spectrum", "--bayer", "8" ])
          `shouldEqual` Right (defaults { kernel = NoDiffusion, quantizer = Machine { name: ZxSpectrumScreen, palette: p, bayer: Just 8 } })

    it "--machine c64-hires offers only --machine-palette full" do
      parse (files <> [ "--machine", "c64-hires", "--machine-palette", "full" ])
        `shouldEqual` Right (defaults { quantizer = Machine { name: C64HiresScreen, palette: FullPalette, bayer: Nothing } })

    it "--machine works with any kernel and with --gray" do
      for_ allMachines \m ->
        parse (files <> [ "--machine", machineName m, "-k", "atkinson", "--gray" ])
          `shouldEqual` Right (defaults { kernel = Atkinson, quantizer = Machine { name: m, palette: FullPalette, bayer: Nothing }, gray = true })

    it "--machine with --bayer N: ordered dithering inside the cells, pure unless --kernel is given" do
      parse (files <> [ "--machine", "zx-spectrum", "--bayer", "8" ])
        `shouldEqual` Right (defaults { kernel = NoDiffusion, quantizer = zx (Just 8) })
      parse (files <> [ "--bayer", "4", "--machine", "zx-spectrum", "-k", "atkinson", "--format", "scr" ])
        `shouldEqual` Right (defaults { kernel = Atkinson, quantizer = zx (Just 4), format = Scr })
      parse (files <> [ "--machine", "c64-hires", "--bayer", "8" ])
        `shouldEqual` Right (defaults { kernel = NoDiffusion, quantizer = Machine { name: C64HiresScreen, palette: FullPalette, bayer: Just 8 } })

    it "--threshold takes a number, --levels a whole number" do
      parse (files <> [ "--threshold", "96.5" ]) `shouldEqual` Right (defaults { quantizer = Threshold 96.5 })
      parse (files <> [ "--levels", "4" ]) `shouldEqual` Right (defaults { quantizer = Levels 4 })

    it "--bayer N alone: pure ordered dithering (no kernel) over 2 levels; with --levels L, over L levels" do
      let pure' quantizer = Right (defaults { kernel = NoDiffusion, quantizer = quantizer })
      parse (files <> [ "--bayer", "8", "--levels", "6" ]) `shouldEqual` pure' (Bayer { side: 8, levels: 6 })
      parse (files <> [ "--levels", "6", "--bayer", "8" ]) `shouldEqual` pure' (Bayer { side: 8, levels: 6 })
      for_ [ 2, 4, 8, 16 ] \n ->
        parse (files <> [ "--bayer", show n ]) `shouldEqual` pure' (Bayer { side: n, levels: 2 })

    it "--bayer N with --kernel: combined with that kernel (the hybrid)" do
      for_ [ FloydSteinberg, Atkinson, JarvisJudiceNinke ] \k ->
        parse (files <> [ "--bayer", "4", "-k", kernelName k ])
          `shouldEqual` Right (defaults { kernel = k, quantizer = Bayer { side: 4, levels: 2 } })
      parse (files <> [ "--kernel", "floyd-steinberg", "--levels", "6", "--bayer", "8" ])
        `shouldEqual` Right (defaults { kernel = FloydSteinberg, quantizer = Bayer { side: 8, levels: 6 } })

    it "without --bayer, every mode defaults to Floyd-Steinberg" do
      for_ [ [], [ "--threshold", "100" ], [ "--levels", "4" ], [ "--palette", "bw" ], [ "--machine", "zx-spectrum" ], [ "--machine", "c64-hires" ] ] \extra ->
        map _.kernel (parse (files <> extra)) `shouldEqual` Right FloydSteinberg

    it "--gray turns gray conversion on" do
      parse (files <> [ "--gray" ]) `shouldEqual` Right (defaults { gray = true })

    it "options can come before, between or after the two files" do
      let expected = Right (defaults { kernel = Atkinson, quantizer = Levels 4, gray = true })
      parse [ "--gray", "-k", "atkinson", "in.png", "--levels", "4", "out.png" ] `shouldEqual` expected
      parse [ "in.png", "out.png", "--levels", "4", "--gray", "--kernel", "atkinson" ] `shouldEqual` expected

  describe "rejected command lines" do
    it "more than one of --threshold, --levels, --palette" do
      for_
        [ [ "--threshold", "100", "--levels", "4" ]
        , [ "--levels", "4", "--palette", "bw" ]
        , [ "--palette", "bw", "--threshold", "100" ]
        ]
        \extra -> parse (files <> extra) `shouldSatisfy` isLeft

    it "--levels below 2 or not a whole number, naming the rule" do
      for_ [ "1", "0", "2.5", "many" ] \n ->
        parse (files <> [ "--levels", n ]) `shouldSatisfy` failsWith "levels must be a whole number >= 2"

    it "an unknown kernel or palette, listing the valid names" do
      parse (files <> [ "--kernel", "sierra" ]) `shouldSatisfy` failsWith "use one of: floyd-steinberg, atkinson, jjn"
      parse (files <> [ "--palette", "nes" ]) `shouldSatisfy`
        failsWith "use one of: bw, websafe216, cga16, ansi16, ansi256, c64, zx15"

    it "--bayer that isn't a power of 2 from 2 to 16, naming the rule" do
      for_ [ "1", "3", "6", "32", "0", "-4", "four" ] \n ->
        parse (files <> [ "--bayer", n ]) `shouldSatisfy` failsWith "bayer must be a power of 2 from 2 to 16"

    it "--bayer with --threshold or --palette, saying why" do
      parse (files <> [ "--bayer", "4", "--threshold", "100" ]) `shouldSatisfy` failsWith "--bayer works over levels"
      parse (files <> [ "--palette", "bw", "--bayer", "4" ]) `shouldSatisfy`
        failsWith "ordered dithering against a palette isn't supported"

    it "--machine with --threshold, --levels or --palette, saying why" do
      for_ allMachines \m -> for_ [ [ "--threshold", "100" ], [ "--levels", "4" ], [ "--palette", "bw" ] ] \extra ->
        parse (files <> [ "--machine", machineName m ] <> extra) `shouldSatisfy` failsWith "the machine defines the colors"

    it "an unknown machine, listing the valid names" do
      parse (files <> [ "--machine", "c64" ]) `shouldSatisfy` failsWith "use one of: zx-spectrum, c64-hires"

    it "--machine-palette without --machine, saying why, and an unknown one, listing the valid names" do
      parse (files <> [ "--machine-palette", "normal" ]) `shouldSatisfy`
        failsWith "--machine-palette needs --machine: it picks among a machine's colors"
      parse (files <> [ "--machine", "zx-spectrum", "--machine-palette", "pastel" ]) `shouldSatisfy`
        failsWith "use one of: full, normal, bright"

    it "--machine-palette normal or bright with c64-hires, listing the machine's palettes" do
      for_ [ "normal", "bright" ] \p ->
        parse (files <> [ "--machine", "c64-hires", "--machine-palette", p ]) `shouldSatisfy`
          failsWith ("--machine-palette " <> p <> " isn't one of c64-hires's palettes; use one of: full")

    it "scr or tap output without --machine zx-spectrum, from --format or the extension, saying why" do
      for_ [ "scr", "tap" ] \format -> for_ [ [], [ "--levels", "4" ], [ "--palette", "zx15" ], [ "--machine", "c64-hires" ] ] \extra -> do
        parse (files <> [ "--format", format ] <> extra) `shouldSatisfy`
          failsWith (format <> " output needs --machine zx-spectrum: the file holds a ZX Spectrum screen")
        parse ([ "in.png", "out." <> format ] <> extra) `shouldSatisfy`
          failsWith (format <> " output needs --machine zx-spectrum: the file holds a ZX Spectrum screen")

    it "an output whose extension names no format, without --format, with advice" do
      for_ [ "out.jpg", "out.pgn", "out", "out.", ".png", "v1.2/out" ] \output ->
        parse [ "in.png", output ] `shouldSatisfy`
          failsWith ("can't tell the output format from \"" <> output <> "\": name it .png, .scr or .tap, or give --format png, scr or tap")

    it "an unknown format, listing the valid names" do
      parse (files <> [ "--format", "gif" ]) `shouldSatisfy` failsWith "use one of: png, scr, tap"

    it "a threshold that isn't a number" do
      parse (files <> [ "--threshold", "half" ]) `shouldSatisfy` isLeft

    it "missing files, an extra file, an unknown option" do
      parse [] `shouldSatisfy` failsWith "Missing"
      parse [ "in.png" ] `shouldSatisfy` failsWith "Missing"
      parse [ "in.png", "out.png", "extra.png" ] `shouldSatisfy` isLeft
      parse (files <> [ "--bogus" ]) `shouldSatisfy` isLeft

  describe "exit codes (the README's table)" do
    it "--help exits with 0" do
      case exitCodeOf [ "--help" ] of
        Right code -> code `shouldEqual` ExitCode.Success
        Left why -> fail why

    it "a rejected command line exits with 1" do
      for_ [ [], files <> [ "--levels", "1" ], files <> [ "--bogus" ], files <> [ "--bayer", "4", "--palette", "bw" ], files <> [ "--machine", "zx-spectrum", "--levels", "4" ], files <> [ "--format", "scr" ], [ "in.png", "out.jpg" ], files <> [ "--machine-palette", "normal" ] ] \args ->
        case exitCodeOf args of
          Right code -> code `shouldEqual` ExitCode.Error
          Left why -> fail why
