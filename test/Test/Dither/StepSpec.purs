module Test.Dither.StepSpec (spec) where

import Prelude

import Data.Array as Array
import Data.List.Lazy as LL
import Data.Tuple (Tuple(..), fst, snd)
import Test.QuickCheck ((===))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)
import Test.Spec.QuickCheck (quickCheck)

import Dither.Kernel (CompiledKernel, Kernel, compileKernel, floydSteinberg)
import Dither.Pixel (quantize)
import Dither.Row (initBuilding)
import Dither.State (RowLayer, RowState, freshLayer)
import Dither.Step (step)
import Test.Dither.Arbitrary (TestKernel(..), TestRow(..))
import Test.Util (approxArrayEqual, takeAsArray)

quantizeThreshold :: Number -> Number
quantizeThreshold x = if x < 128.0 then 0.0 else 255.0

-- | A valid starting RowState for row 1 of any kernel: `current` and
-- | `building` freshly built to match the CompiledKernel's shape
-- | exactly (the only way `Dither.Row.ditherRow` ever builds them),
-- | `matured` seeded with one placeholder ([], 0 fifos) per future
-- | layer — the same placeholder `Dither.State.initState` uses, and
-- | the only `matured` shape that's safe to fold an arbitrary number
-- | of `step` calls over in isolation: a `[]` layer has zero fifos, so
-- | `dequeueAllLayer` makes zero dequeue calls on it, for any row
-- | length. (An "already real" matured layer, as row 2+ would see in
-- | practice, only gets its real depth from having been built by a
-- | full row via `commitBuilding`'s `replace` — faking that safely in
-- | isolation isn't worth it; `Test.Dither.RowSpec`'s multi-row fold
-- | exercises that case naturally, via the real code path.)
freshRowState1 :: CompiledKernel -> RowState LL.List Number
freshRowState1 compiled =
  { current: freshLayer compiled.currentOffsets
  , matured: map (const ([] :: RowLayer LL.List Number)) compiled.futureLayers
  , building: initBuilding compiled
  , x: 0
  , y: 0
  }

-- | current's shape (fifo count) always matches compiled.currentOffsets
-- | exactly — freshLayer builds it that way, and step's zipWith against
-- | compiled.currentOffsets can only preserve that length, never change it.
currentShapeOk :: CompiledKernel -> RowState LL.List Number -> Boolean
currentShapeOk compiled rs = Array.length rs.current == Array.length compiled.currentOffsets

-- | building's nested shape (layer count, and fifo count within each
-- | layer) always matches compiled.futureLayers exactly, for the same
-- | zipWith-preserves-length reason as current.
buildingShapeOk :: CompiledKernel -> RowState LL.List Number -> Boolean
buildingShapeOk compiled rs =
  map Array.length rs.building == map Array.length compiled.futureLayers

-- | Folds `step` across a row, checking current/building's shape after
-- | every pixel (not just at the end) — catches a transient violation
-- | as early as possible, rather than only at the last pixel.
foldStepsCheckingShape :: CompiledKernel -> Array Number -> Boolean
foldStepsCheckingShape compiled row =
  snd (Array.foldl go (Tuple (freshRowState1 compiled) true) row)
  where
  go (Tuple rs okSoFar) px =
    let Tuple rs' _q = step compiled (quantize quantizeThreshold) rs px
    in Tuple rs' (okSoFar && currentShapeOk compiled rs' && buildingShapeOk compiled rs')

spec :: Spec Unit
spec = describe "Dither.Step" do

  describe "shape invariants" do
    it "current/building shapes always match the CompiledKernel, across arbitrary kernels and rows" do
      quickCheck \(TestKernel kernel) (TestRow row) ->
        foldStepsCheckingShape (compileKernel kernel) row === true

    it "advances x by one per pixel and keeps the row's y" do
      quickCheck \(TestKernel kernel) (TestRow row) ->
        let
          compiled = compileKernel kernel
          final = Array.foldl
            (\rs px -> fst (step compiled (quantize quantizeThreshold) rs px))
            ((freshRowState1 compiled) { y = 7 })
            row
        in { x: final.x, y: final.y } === { x: Array.length row, y: 7 }

    it "matured's shape (placeholder seed) is preserved across an arbitrary row" do
      quickCheck \(TestKernel kernel) (TestRow row) ->
        let
          compiled = compileKernel kernel
          expectedShape = map Array.length (freshRowState1 compiled).matured
          finalState = Array.foldl
            (\rs px -> fst (step compiled (quantize quantizeThreshold) rs px))
            (freshRowState1 compiled)
            row
        in map Array.length finalState.matured === expectedShape

  describe "Floyd-Steinberg example (regression, ported from the old Test.Assert version)" do
    it "diffuses one pixel's error into current/building with the correct weights" do
      let
        compiled = compileKernel floydSteinberg
        initial = freshRowState1 compiled
        Tuple rowState1 quantizedPixel = step compiled (quantize quantizeThreshold) initial 100.0
        outErr = 100.0

      quantizedPixel `shouldEqual` 0.0

      case rowState1.current of
        [ f ] -> approxArrayEqual (takeAsArray 1 f) [ outErr * (7.0 / 16.0) ] `shouldEqual` true
        _ -> fail "unexpected current shape"

      case rowState1.building of
        [ [ f1, f2, f3 ] ] -> do
          approxArrayEqual (takeAsArray 1 f1) [ outErr * (3.0 / 16.0) ] `shouldEqual` true
          approxArrayEqual (takeAsArray 1 f2) [ outErr * (5.0 / 16.0) ] `shouldEqual` true
          approxArrayEqual (takeAsArray 2 f3) [ 0.0, outErr * (1.0 / 16.0) ] `shouldEqual` true
        _ -> fail "unexpected building shape"

  describe "edge cases" do
    it "maxDepth == 0 kernel: no future layers, only current-row diffusion" do
      let
        kernel = [ { dx: 1, dy: 0, weight: 1.0 } ] :: Kernel
        compiled = compileKernel kernel
        initial = freshRowState1 compiled

      compiled.futureLayers `shouldEqual` []
      Array.length initial.building `shouldEqual` 0

      let Tuple rowState1 q = step compiled (quantize quantizeThreshold) initial 200.0
      q `shouldEqual` 255.0
      Array.length rowState1.building `shouldEqual` 0
      case rowState1.current of
        [ f ] -> approxArrayEqual (takeAsArray 1 f) [ 200.0 - 255.0 ] `shouldEqual` true
        _ -> fail "unexpected current shape"

    it "completely empty kernel: quantize is applied directly, with no diffusion, for any row" do
      quickCheck \(TestRow row) ->
        let
          compiled = compileKernel ([] :: Kernel)
          outputs = Array.foldl
            ( \(Tuple rs acc) px ->
                let Tuple rs' q = step compiled (quantize quantizeThreshold) rs px
                in Tuple rs' (Array.snoc acc q)
            )
            (Tuple (freshRowState1 compiled) [])
            row
        in snd outputs === map quantizeThreshold row

    it "a zero-weight offset contributes exactly zero error, not NaN/Infinity" do
      let
        kernel = [ { dx: 1, dy: 0, weight: 0.0 } ] :: Kernel
        compiled = compileKernel kernel
        initial = freshRowState1 compiled
        Tuple rowState1 _ = step compiled (quantize quantizeThreshold) initial 200.0
      case rowState1.current of
        [ f ] -> approxArrayEqual (takeAsArray 1 f) [ 0.0 ] `shouldEqual` true
        _ -> fail "unexpected current shape"
