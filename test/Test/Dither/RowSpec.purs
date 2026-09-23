module Test.Dither.RowSpec (spec) where

import Prelude

import Data.Array as Array
import Data.List.Lazy as LL
import Data.Tuple (Tuple(..), snd)
import Test.QuickCheck ((===))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.QuickCheck (quickCheck)

import Dither.Kernel (CompiledKernel, Kernel, compileKernel, floydSteinberg)
import Dither.Pixel (Quantize(..))
import Dither.Row (ditherRow)
import Dither.State (DelayLine, DitherState, initState)
import Dither.Util (safeRange)
import Test.Dither.Arbitrary (TestImage(..), TestKernel(..))

quantizeThreshold :: Number -> Number
quantizeThreshold x = if x < 128.0 then 0.0 else 255.0

-- | Folds ditherRow across every row of an image, starting from
-- | initState, calling `check` after every row with (this row's
-- | resulting delayLines, the input row, the output row). True only if
-- | `check` held after every single row, not just the last one.
foldRows
  :: CompiledKernel
  -> (Array (DelayLine LL.List Number) -> Array Number -> Array Number -> Boolean)
  -> Array (Array Number)
  -> Boolean
foldRows compiled check rows =
  snd (Array.foldl go (Tuple (initState compiled).delayLines true) rows)
  where
  go (Tuple delayLines okSoFar) row =
    let Tuple delayLines' outRow = ditherRow compiled (Quantize quantizeThreshold) delayLines row
    in Tuple delayLines' (okSoFar && check delayLines' row outRow)

spec :: Spec Unit
spec = describe "Dither.Row" do

  describe "invariants" do
    it "output row length always equals input row length" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        foldRows (compileKernel kernel) (\_ row outRow -> Array.length outRow == Array.length row) image
          === true

    it "each DelayLine's length is always exactly its dy, from the first row onward" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        let
          compiled = compileKernel kernel
          expectedLengths = safeRange 1 compiled.maxDepth
        in
          foldRows compiled (\delayLines _ _ -> map Array.length delayLines == expectedLengths) image
            === true

  describe "Floyd-Steinberg example (regression, ported from the old Test.Assert version)" do
    it "dithers a 3-pixel row to valid threshold values, preserving length" do
      let
        compiled = compileKernel floydSteinberg
        state0 :: DitherState LL.List Number
        state0 = initState compiled
        row = [ 100.0, 200.0, 50.0 ]
        Tuple _delayLines1 quantizedRow = ditherRow compiled (Quantize quantizeThreshold) state0.delayLines row

      Array.length quantizedRow `shouldEqual` Array.length row
      Array.all (\p -> p == 0.0 || p == 255.0) quantizedRow `shouldEqual` true

  describe "edge cases" do
    it "maxDepth == 0 kernel: DelayLines stay empty across a multi-row image" do
      quickCheck \(TestImage image) ->
        let kernel = [ { dx: 1, dy: 0, weight: 1.0 } ] :: Kernel
        in foldRows (compileKernel kernel) (\delayLines _ _ -> Array.length delayLines == 0) image === true

    it "completely empty kernel: every row is quantized directly, with no diffusion" do
      quickCheck \(TestImage image) ->
        let compiled = compileKernel ([] :: Kernel)
        in foldRows compiled (\_ row outRow -> outRow == map quantizeThreshold row) image === true

    it "width-1 image with Floyd-Steinberg does not crash and preserves invariants" do
      let
        compiled = compileKernel floydSteinberg
        image = [ [ 10.0 ], [ 200.0 ], [ 90.0 ] ] -- height 3, width 1
        expectedLengths = safeRange 1 compiled.maxDepth
      foldRows compiled
        ( \delayLines row outRow ->
            Array.length outRow == Array.length row
              && map Array.length delayLines == expectedLengths
        )
        image
        `shouldEqual` true

    it "height-1 image: DelayLines reach their steady length after the very first row" do
      let
        compiled = compileKernel floydSteinberg
        image = [ [ 10.0, 200.0, 90.0 ] ]
        expectedLengths = safeRange 1 compiled.maxDepth
      foldRows compiled (\delayLines _ _ -> map Array.length delayLines == expectedLengths) image
        `shouldEqual` true
