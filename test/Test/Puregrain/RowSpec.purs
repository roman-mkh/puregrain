module Test.Puregrain.RowSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Either (Either, either)
import Data.Foldable (and, for_)
import Data.Int (odd)
import Data.List.Lazy as LL
import Data.Maybe (Maybe(..), maybe)
import Data.Tuple (Tuple(..), snd)
import Partial.Unsafe (unsafeCrashWith)
import Test.QuickCheck ((===))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Internal.Params (CompiledParams, Scan, compileParams, defaults, raster, serpentine, withKernel, withScan)
import Puregrain.Kernel (Kernel, floydSteinberg, noDiffusion)
import Puregrain.Quantize (quantize, runQuantize)
import Puregrain.Internal.Row (stepRow)
import Puregrain.Internal.State (DitherState, initState)
import Puregrain.Internal.Util (safeRange)
import Test.Puregrain.Arbitrary (TestImage(..), TestKernel(..))
import Test.Puregrain.Util (validKernel)

quantizeThreshold :: Number -> Number
quantizeThreshold x = if x < 128.0 then 0.0 else 255.0

-- | The row's result, for rows the test knows are valid (its images are
-- | rectangular, so `stepRow` never rejects one).
rowOk :: forall a. Either String a -> a
rowOk = either unsafeCrashWith identity

-- | The settings compiled, for a kernel and a scan.
compiledFor :: Scan -> Kernel -> CompiledParams
compiledFor scan kernel = compileParams (defaults # withKernel kernel # withScan scan)

-- | Both scans; `alternates` says, independently of the library, that
-- | every other row runs the other way.
scans :: Array { name :: String, scan :: Scan, alternates :: Boolean }
scans =
  [ { name: "every row left to right", scan: raster, alternates: false }
  , { name: "serpentine", scan: serpentine, alternates: true }
  ]

-- | Folds stepRow across every row of an image, starting from
-- | initState, calling `check` after every row with (this row's
-- | resulting state, the input row, the output row). True only if
-- | `check` held after every single row, not just the last one.
foldRows
  :: CompiledParams
  -> (DitherState LL.List Number -> Array Number -> Array Number -> Boolean)
  -> Array (Array Number)
  -> Boolean
foldRows compiled check rows =
  snd (Array.foldl go (Tuple (initState compiled.kernel) true) rows)
  where
  go (Tuple state okSoFar) row =
    let Tuple state' outRow = rowOk (stepRow compiled (runQuantize (quantize quantizeThreshold)) state row)
    in Tuple state' (okSoFar && check state' row outRow)

spec :: Spec Unit
spec = describe "Puregrain.Internal.Row" do

  for_ scans \s -> describe ("invariants, " <> s.name) do
    it "output row length always equals input row length" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        foldRows (compiledFor s.scan kernel) (\_ row outRow -> Array.length outRow == Array.length row) image
          === true

    it "counts rows: after k rows, nextRow (the next row's y) is k" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        let
          compiled = compiledFor s.scan kernel
          counts = Array.foldl
            ( \(Tuple state acc) row ->
                let Tuple state' _ = rowOk (stepRow compiled (runQuantize (quantize quantizeThreshold)) state row)
                in Tuple state' (Array.snoc acc state'.nextRow)
            )
            (Tuple (initState compiled.kernel :: DitherState LL.List Number) [])
            image
        in snd counts === Array.range 1 (Array.length image)

    it "remembers the image's width: none before the first row, then the first row's length" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        let
          compiled = compiledFor s.scan kernel
          start = initState compiled.kernel :: DitherState LL.List Number
          widths = Array.foldl
            ( \(Tuple state acc) row ->
                let Tuple state' _ = rowOk (stepRow compiled (runQuantize (quantize quantizeThreshold)) state row)
                in Tuple state' (Array.snoc acc state'.width)
            )
            (Tuple start [])
            image
          firstWidth = Array.length <$> Array.head image
        in { before: start.width, after: snd widths } === { before: Nothing, after: map (const firstWidth) image }

    it "each DelayLine's length is always exactly its dy, from the first row onward" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        let
          compiled = compiledFor s.scan kernel
          expectedLengths = safeRange 1 compiled.kernel.maxDepth
        in
          foldRows compiled (\state _ _ -> map Array.length state.delayLines == expectedLengths) image
            === true

    -- A queue holds one entry per column for the row it's for. Built for
    -- a row running the same way, the dx > 0 entries past the row's end
    -- stay at the back, where they're never read; for a row running the
    -- other way, they'd come out first after the reversal, so they must
    -- be gone. (A row narrower than -dx gets -dx zeros, all its error
    -- having gone past its left edge: `replace` drops everything.)
    it "hands each later row a queue of one entry per column, plus dx unread ones only for a row running the same way" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        let
          compiled = compiledFor s.scan kernel
          width = maybe 0 Array.length (Array.head image)
          -- the newest layer of each delay line is the one just handed over
          handedOver state = Array.mapWithIndex (\i dl -> { dy: i + 1, layer: Array.last dl }) state.delayLines
          expected dy o
            | o.dx < 0 = max width (negate o.dx)
            | s.alternates && odd dy = width
            | otherwise = width + o.dx
          layerOk { dy, layer } = case layer, Array.index compiled.kernel.futureLayers (dy - 1) of
            Just fifos, Just offsets ->
              Array.length fifos == Array.length offsets
                && and (Array.zipWith (\o fifo -> LL.length fifo == expected dy o) offsets fifos)
            _, _ -> false
        in
          foldRows compiled (\state _ _ -> and (map layerOk (handedOver state))) image === true

  describe "Floyd-Steinberg example (regression, ported from the old Test.Assert version)" do
    it "dithers a 3-pixel row to valid threshold values, preserving length" do
      let
        compiled = compiledFor raster floydSteinberg
        state0 :: DitherState LL.List Number
        state0 = initState compiled.kernel
        row = [ 100.0, 200.0, 50.0 ]
        Tuple _state1 quantizedRow = rowOk (stepRow compiled (runQuantize (quantize quantizeThreshold)) state0 row)

      Array.length quantizedRow `shouldEqual` Array.length row
      Array.all (\p -> p == 0.0 || p == 255.0) quantizedRow `shouldEqual` true

  describe "edge cases" do
    it "maxDepth == 0 kernel: DelayLines stay empty across a multi-row image" do
      quickCheck \(TestImage image) ->
        let kernel = validKernel [ { dx: 1, dy: 0, weight: 1.0 } ]
        in foldRows (compiledFor raster kernel) (\state _ _ -> Array.length state.delayLines == 0) image === true

    it "completely empty kernel: every row is quantized directly, with no diffusion" do
      quickCheck \(TestImage image) ->
        let compiled = compiledFor raster noDiffusion
        in foldRows compiled (\_ row outRow -> outRow == map quantizeThreshold row) image === true

    it "width-1 image with Floyd-Steinberg does not crash and preserves invariants" do
      let
        compiled = compiledFor raster floydSteinberg
        image = [ [ 10.0 ], [ 200.0 ], [ 90.0 ] ] -- height 3, width 1
        expectedLengths = safeRange 1 compiled.kernel.maxDepth
      foldRows compiled
        ( \state row outRow ->
            Array.length outRow == Array.length row
              && map Array.length state.delayLines == expectedLengths
        )
        image
        `shouldEqual` true

    it "height-1 image: DelayLines reach their steady length after the very first row" do
      let
        compiled = compiledFor raster floydSteinberg
        image = [ [ 10.0, 200.0, 90.0 ] ]
        expectedLengths = safeRange 1 compiled.kernel.maxDepth
      foldRows compiled (\state _ _ -> map Array.length state.delayLines == expectedLengths) image
        `shouldEqual` true
