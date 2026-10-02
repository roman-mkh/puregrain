-- | The command-line contract promised in cli/README.md (defaults, which
-- | options exist, what's rejected, exit codes), tested on the real parser.
-- | Not tested: help-text layout (optparse's job, and brittle).
module Test.Puregrain.Cli.OptionsSpec (spec) where

import Prelude

import Data.Either (Either(..), isLeft)
import Data.Foldable (for_)
import Data.String (Pattern(..), contains)
import Data.Tuple (Tuple(..), fst)
import ExitCodes (ExitCode)
import ExitCodes as ExitCode
import Options.Applicative (ParserResult(..), defaultPrefs, execParserPure, renderFailure)
import Puregrain.Cli.Options (KernelName(..), Options, QuantizerChoice(..), allKernels, allPalettes, kernelName, paletteName, parserInfo)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual, shouldSatisfy)

-- | Runs the real parser on an argument list, purely: no process argv and
-- | no exit. `Left` carries the text optparse would print for a failure.
parse :: Array String -> Either String Options
parse args = case execParserPure defaultPrefs parserInfo args of
  Success opts -> Right opts
  Failure failure -> Left (fst (renderFailure failure "puregrain-cli"))
  CompletionInvoked _ -> Left "unexpected shell-completion request"

-- | The exit code optparse exits with for a command line it rejects, or
-- | answers itself (like --help). A command line that parses successfully
-- | has no such code, and is reported as a `Left`.
exitCodeOf :: Array String -> Either String ExitCode
exitCodeOf args = case execParserPure defaultPrefs parserInfo args of
  Failure failure -> let Tuple _ code = renderFailure failure "puregrain-cli" in Right code
  _ -> Left "the command line parsed successfully"

failsWith :: String -> Either String Options -> Boolean
failsWith text = case _ of
  Left message -> contains (Pattern text) message
  Right _ -> false

defaults :: Options
defaults = { input: "in.png", output: "out.png", kernel: FloydSteinberg, quantizer: Threshold 128.0, gray: false }

files :: Array String
files = [ "in.png", "out.png" ]

spec :: Spec Unit
spec = describe "Puregrain.Cli.Options (the command-line contract in cli/README.md)" do

  describe "defaults" do
    it "INPUT and OUTPUT alone: Floyd–Steinberg, --threshold 128, no --gray" do
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

    it "the documented kernel and palette names are exactly the ones in the README" do
      map kernelName allKernels `shouldEqual` [ "floyd-steinberg", "atkinson", "jjn" ]
      map paletteName allPalettes `shouldEqual` [ "bw", "websafe216", "cga16", "ansi16", "ansi256", "c64", "zx-spectrum" ]

    it "--threshold takes a number, --levels a whole number" do
      parse (files <> [ "--threshold", "96.5" ]) `shouldEqual` Right (defaults { quantizer = Threshold 96.5 })
      parse (files <> [ "--levels", "4" ]) `shouldEqual` Right (defaults { quantizer = Levels 4 })

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
        failsWith "use one of: bw, websafe216, cga16, ansi16, ansi256, c64, zx-spectrum"

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
      for_ [ [], files <> [ "--levels", "1" ], files <> [ "--bogus" ] ] \args ->
        case exitCodeOf args of
          Right code -> code `shouldEqual` ExitCode.Error
          Left why -> fail why
