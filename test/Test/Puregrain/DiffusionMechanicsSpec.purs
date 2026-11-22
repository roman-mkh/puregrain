module Test.Puregrain.DiffusionMechanicsSpec
  ( spec
  ) where

import Prelude

import Data.Array (mapWithIndex)
import Data.CatQueue (CatQueue)
import Data.Foldable (for_)
import Data.Int (toNumber)
import Data.List.Lazy as LL
import Data.List as DL
import Data.Tuple (Tuple(..))
import Test.QuickCheck (Result, (===))
import Test.Spec (Spec, describe, it)
import Test.Spec.QuickCheck (quickCheck)
import Type.Proxy (Proxy(..))

import Puregrain.Internal.Fifo (class Fifo)
import Puregrain.Internal.Gamma (noConversion)
import Puregrain.Internal.Image (ditherImageVia)
import Puregrain.Internal.Params (Scan, compileParams, defaults, raster, serpentine, withKernel, withScan)
import Puregrain.Kernel (Kernel)
import Puregrain.Ordered (ordered)
import Puregrain.Quantize (Quantize, evenRamp, quantize, quantizeWith, runQuantize)
import Test.Puregrain.Arbitrary (TestKernel(..), TestImage(..))
import Test.Puregrain.Reference (RowOrder(..), referenceDitherIn)
import Test.Puregrain.Util (bayerMap)

-- | A fixed, simple, position-blind quantizer. These properties check the
-- | DIFFUSION MECHANICS (padding, Fifo backend, DelayLine growth) against
-- | an independent reference — not the quantizer — so a simple one is
-- | enough.
testQuantize :: Quantize Number
testQuantize = quantize \x -> if x < 128.0 then 0.0 else 255.0

-- | A threshold that varies with the pixel's position. If a backend gave
-- | any pixel a wrong position, its output would differ from the
-- | reference's, so agreement proves the positions match pixel for pixel.
positionalThreshold :: Quantize Number
positionalThreshold = quantizeWith \c v -> if v < toNumber (32 + (37 * c.x + 61 * c.y) `mod` 192) then 0.0 else 255.0

-- | Ordered dithering over three levels with the 4×4 Bayer map: the
-- | position-dependent quantizer the library actually ships, run through
-- | diffusion (the hybrid).
bayerHybrid :: Quantize Number
bayerHybrid = ordered (bayerMap 4) (evenRamp 3)

-- | Ignores the value and returns the pixel's position as x + 1000·y, so
-- | the dithered image shows exactly which position each pixel was given.
revealPosition :: Quantize Number
revealPosition = quantizeWith \c _ -> toNumber (c.x + 1000 * c.y)

runWith
  :: forall f
   . Fifo f
  => Proxy f
  -> Scan
  -> Kernel
  -> Quantize Number
  -> Array (Array Number)
  -> Array (Array Number)
runWith proxy scan kernel q image =
  ditherImageVia proxy noConversion (compileParams (defaults # withKernel kernel # withScan scan)) q image

-- | The library's scans, each with the reference's own row order for it.
scans :: Array { name :: String, scan :: Scan, order :: RowOrder }
scans =
  [ { name: "every row left to right", scan: raster, order: AllLeftToRight }
  , { name: "serpentine", scan: serpentine, order: Alternating }
  ]

agreesWithReference :: forall f. Fifo f => Proxy f -> Scan -> RowOrder -> Quantize Number -> TestKernel -> TestImage -> Result
agreesWithReference proxy scan order q (TestKernel kernel) (TestImage image) =
  runWith proxy scan kernel q image === referenceDitherIn order kernel (runQuantize q) image

spec :: Spec Unit
spec = describe "Puregrain.Internal.Image properties" do

  for_ scans \s -> describe s.name do
    for_
      [ Tuple "a position-blind threshold" testQuantize
      , Tuple "a position-dependent threshold" positionalThreshold
      , Tuple "ordered (Bayer 4×4) dithering" bayerHybrid
      ]
      \(Tuple label q) ->
        describe ("agrees with the independent reference implementation, with " <> label) do
          it "CatQueue backend" do
            quickCheck (agreesWithReference (Proxy :: Proxy CatQueue) s.scan s.order q)
          it "List.Lazy backend" do
            quickCheck (agreesWithReference (Proxy :: Proxy LL.List) s.scan s.order q)
          it "List backend" do
            quickCheck (agreesWithReference (Proxy :: Proxy DL.List) s.scan s.order q)
          it "Array backend" do
            quickCheck (agreesWithReference (Proxy :: Proxy Array) s.scan s.order q)

    describe "pixel positions" do
      -- Under serpentine too: a row scanned right to left still gives each
      -- pixel its column counted from the left edge.
      it "each pixel's quantizer gets its own position: x from 0 in every row, y from 0 for the image" do
        quickCheck \(TestKernel kernel) (TestImage image) ->
          runWith (Proxy :: Proxy CatQueue) s.scan kernel revealPosition image
            === mapWithIndex (\y row -> mapWithIndex (\x _ -> toNumber (x + 1000 * y)) row) image
