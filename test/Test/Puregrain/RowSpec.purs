module Test.Puregrain.RowSpec (spec) where

import Prelude

import Data.Array as Array
import Data.List.Lazy as LL
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), snd)
import Test.QuickCheck ((===))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Internal.Kernel (CompiledKernel, compileKernel)
import Puregrain.Kernel (floydSteinberg, noDiffusion)
import Puregrain.Quantize (quantize)
import Puregrain.Internal.Row (ditherRow)
import Puregrain.Internal.State (DitherState, initState)
import Puregrain.Internal.Util (safeRange)
import Test.Puregrain.Arbitrary (TestImage(..), TestKernel(..))
import Test.Puregrain.Util (validKernel)

quantizeThreshold :: Number -> Number
quantizeThreshold x = if x < 128.0 then 0.0 else 255.0

-- | Folds ditherRow across every row of an image, starting from
-- | initState, calling `check` after every row with (this row's
-- | resulting state, the input row, the output row). True only if
-- | `check` held after every single row, not just the last one.
foldRows
  :: CompiledKernel
  -> (DitherState LL.List Number -> Array Number -> Array Number -> Boolean)
  -> Array (Array Number)
  -> Boolean
foldRows compiled check rows =
  snd (Array.foldl go (Tuple (initState compiled) true) rows)
  where
  go (Tuple state okSoFar) row =
    let Tuple state' outRow = ditherRow compiled (quantize quantizeThreshold) state row
    in Tuple state' (okSoFar && check state' row outRow)

spec :: Spec Unit
spec = describe "Puregrain.Internal.Row" do

  describe "invariants" do
    it "output row length always equals input row length" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        foldRows (compileKernel kernel) (\_ row outRow -> Array.length outRow == Array.length row) image
          === true

    it "counts rows: after k rows, nextRow (the next row's y) is k" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        let
          compiled = compileKernel kernel
          counts = Array.foldl
            ( \(Tuple state acc) row ->
                let Tuple state' _ = ditherRow compiled (quantize quantizeThreshold) state row
                in Tuple state' (Array.snoc acc state'.nextRow)
            )
            (Tuple (initState compiled :: DitherState LL.List Number) [])
            image
        in snd counts === Array.range 1 (Array.length image)

    it "remembers the image's width: none before the first row, then the first row's length" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        let
          compiled = compileKernel kernel
          start = initState compiled :: DitherState LL.List Number
          widths = Array.foldl
            ( \(Tuple state acc) row ->
                let Tuple state' _ = ditherRow compiled (quantize quantizeThreshold) state row
                in Tuple state' (Array.snoc acc state'.width)
            )
            (Tuple start [])
            image
          firstWidth = Array.length <$> Array.head image
        in { before: start.width, after: snd widths } === { before: Nothing, after: map (const firstWidth) image }

    it "each DelayLine's length is always exactly its dy, from the first row onward" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        let
          compiled = compileKernel kernel
          expectedLengths = safeRange 1 compiled.maxDepth
        in
          foldRows compiled (\state _ _ -> map Array.length state.delayLines == expectedLengths) image
            === true

  describe "Floyd-Steinberg example (regression, ported from the old Test.Assert version)" do
    it "dithers a 3-pixel row to valid threshold values, preserving length" do
      let
        compiled = compileKernel floydSteinberg
        state0 :: DitherState LL.List Number
        state0 = initState compiled
        row = [ 100.0, 200.0, 50.0 ]
        Tuple _state1 quantizedRow = ditherRow compiled (quantize quantizeThreshold) state0 row

      Array.length quantizedRow `shouldEqual` Array.length row
      Array.all (\p -> p == 0.0 || p == 255.0) quantizedRow `shouldEqual` true

  describe "edge cases" do
    it "maxDepth == 0 kernel: DelayLines stay empty across a multi-row image" do
      quickCheck \(TestImage image) ->
        let kernel = validKernel [ { dx: 1, dy: 0, weight: 1.0 } ]
        in foldRows (compileKernel kernel) (\state _ _ -> Array.length state.delayLines == 0) image === true

    it "completely empty kernel: every row is quantized directly, with no diffusion" do
      quickCheck \(TestImage image) ->
        let compiled = compileKernel noDiffusion
        in foldRows compiled (\_ row outRow -> outRow == map quantizeThreshold row) image === true

    it "width-1 image with Floyd-Steinberg does not crash and preserves invariants" do
      let
        compiled = compileKernel floydSteinberg
        image = [ [ 10.0 ], [ 200.0 ], [ 90.0 ] ] -- height 3, width 1
        expectedLengths = safeRange 1 compiled.maxDepth
      foldRows compiled
        ( \state row outRow ->
            Array.length outRow == Array.length row
              && map Array.length state.delayLines == expectedLengths
        )
        image
        `shouldEqual` true

    it "height-1 image: DelayLines reach their steady length after the very first row" do
      let
        compiled = compileKernel floydSteinberg
        image = [ [ 10.0, 200.0, 90.0 ] ]
        expectedLengths = safeRange 1 compiled.maxDepth
      foldRows compiled (\state _ _ -> map Array.length state.delayLines == expectedLengths) image
        `shouldEqual` true
