module Test.Puregrain.DitherSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (foldM)
import Data.Lazy (defer)
import Data.List.Lazy as LL
import Data.List.Lazy.Types (List(..))
import Data.Maybe (Maybe(..))
import Effect.Class (liftEffect)
import Partial.Unsafe (unsafeCrashWith)
import Test.QuickCheck ((===))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Dither (Dithering, defaults, ditherImage, ditherImageBy, ditherRow, ditherRows, ditherRowsBy, initDithering, initDitheringBy, serpentine, withKernel, withScan)
import Puregrain.Kernel (Kernel, floydSteinberg, noDiffusion)
import Puregrain.Ordered (ordered)
import Puregrain.Pixel (class Scalable)
import Puregrain.Quantize (Quantize, evenRamp, threshold)
import Test.Puregrain.Arbitrary (TestImage(..), TestKernel(..))
import Test.Puregrain.Util (bayerMap, errorOf, mentions)

q :: Quantize Number
q = threshold 128.0

-- | The rows dithered one at a time with `ditherRow`, from `initDithering`.
ditherEach :: forall a. Ring a => Scalable a => Kernel -> Quantize a -> Array (Array a) -> Either String (Array (Array a))
ditherEach kernel quantizer = ditherEachFrom (initDithering kernel quantizer)

-- | The rows dithered one at a time with `ditherRow`, from the given state.
ditherEachFrom :: forall a. Ring a => Scalable a => Dithering a -> Array (Array a) -> Either String (Array (Array a))
ditherEachFrom start rows = _.out <$> foldM next { state: start, out: [] } rows
  where
  next acc row = ditherRow acc.state row <#> \r -> { state: r.next, out: Array.snoc acc.out r.row }

-- | All rows of the lazy result, which forces each of them.
allRows :: forall a. LL.List (Array a) -> Array (Array a)
allRows = LL.toUnfoldable

spec :: Spec Unit
spec = describe "Puregrain.Dither" do

  describe "ditherImage, ditherRows and ditherRow" do
    -- A position-dependent quantizer, so they must also give every pixel
    -- the same position.
    it "give the same rows, for any kernel and image" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        let bayer = ordered (bayerMap 4) (evenRamp 3)
        in { rows: allRows (ditherRows kernel bayer (LL.fromFoldable image)), each: ditherEach kernel bayer image }
             === { rows: ditherImage kernel bayer image, each: Right (ditherImage kernel bayer image) }

  describe "ditherRow" do
    let
      first = [ 10.0, 200.0, 90.0 ]
      second = [ 30.0, 140.0, 250.0 ]
      other = [ 250.0, 5.0, 120.0 ]

    it "rejects a row of a different length, leaving the state as it was" do
      case ditherRow (initDithering floydSteinberg q) first of
        Left problem -> fail problem
        Right r1 -> do
          case ditherRow r1.next [ 1.0 ] of
            Left problem -> Just problem `shouldSatisfy` mentions "row 1 has 1 pixels, but the first row has 3"
            Right _ -> fail "expected the short row to be rejected"
          -- Carrying on with a corrected row works as if nothing happened.
          case ditherRow r1.next second of
            Left problem -> fail problem
            Right r2 -> [ r1.row, r2.row ] `shouldEqual` ditherImage floydSteinberg q [ first, second ]

    -- States are immutable values. This also guards that promise for a
    -- future, faster backend that might use mutable arrays inside.
    it "can reuse a state: going back to an older one (an undo) works like dithering that history fresh" do
      case ditherRow (initDithering floydSteinberg q) first of
        Left problem -> fail problem
        Right r1 -> do
          -- Go on with `second`…
          case ditherRow r1.next second of
            Left problem -> fail problem
            Right _ -> pure unit
          -- …then go back to the state after `first` and take `other` instead.
          case ditherRow r1.next other of
            Left problem -> fail problem
            Right r2 -> [ r1.row, r2.row ] `shouldEqual` ditherImage floydSteinberg q [ first, other ]

  describe "ditherRows is lazy" do
    it "works on an endless stream of rows" do
      let row = [ 10.0, 200.0, 90.0, 130.0 ]
      allRows (LL.take 3 (ditherRows floydSteinberg q (LL.repeat row)))
        `shouldEqual` ditherImage floydSteinberg q [ row, row, row ]

    it "reads an input row only when its result row is asked for" do
      let
        first = [ 10.0, 200.0, 90.0 ]
        second = [ 30.0, 140.0, 250.0 ]
        -- An input whose third row stops with an error when it's read.
        input = LL.cons first (LL.cons second (List (defer \_ -> unsafeCrashWith "the third input row was read")))
        out = ditherRows floydSteinberg q input
      -- Two result rows read the first two input rows, not the third. Every
      -- read is inside `errorOf`, so reading too early fails this test
      -- instead of stopping the whole test run.
      firstTwo <- liftEffect (errorOf \_ -> Array.length (allRows (LL.take 2 out)))
      firstTwo `shouldEqual` Nothing
      allRows (LL.take 2 out) `shouldEqual` ditherImage floydSteinberg q [ first, second ]
      -- …and the third result row is what reads the third input row.
      third <- liftEffect (errorOf \_ -> LL.length (LL.take 3 out))
      third `shouldSatisfy` mentions "the third input row was read"

  describe "rows of different lengths (a caller's bug)" do
    let
      tooLong = [ [ 10.0, 200.0, 90.0 ], [ 30.0, 140.0, 250.0 ], [ 60.0, 70.0, 80.0, 90.0 ] ]
      tooShort = [ [ 10.0, 200.0, 90.0 ], [ 30.0, 140.0 ] ]

    it "ditherImage stops with an error naming the row, for a longer and a shorter row" do
      long <- liftEffect (errorOf \_ -> Array.length (ditherImage floydSteinberg q tooLong))
      long `shouldSatisfy` mentions "row 2 has 4 pixels, but the first row has 3"
      short <- liftEffect (errorOf \_ -> Array.length (ditherImage floydSteinberg q tooShort))
      short `shouldSatisfy` mentions "row 1 has 2 pixels, but the first row has 3"

    it "ditherRows stops when it reaches that row; the rows before it come out" do
      let out = ditherRows floydSteinberg q (LL.fromFoldable tooLong)
      -- Inside `errorOf` first, like the laziness test above.
      firstTwo <- liftEffect (errorOf \_ -> Array.length (allRows (LL.take 2 out)))
      firstTwo `shouldEqual` Nothing
      allRows (LL.take 2 out) `shouldEqual` ditherImage floydSteinberg q (Array.take 2 tooLong)
      result <- liftEffect (errorOf \_ -> Array.length (allRows out))
      result `shouldSatisfy` mentions "row 2 has 4 pixels, but the first row has 3"

    it "an image whose rows all have the same length comes through" do
      result <- liftEffect (errorOf \_ -> Array.length (ditherImage floydSteinberg q [ [ 10.0, 200.0 ], [ 30.0, 140.0 ], [ 60.0, 70.0 ] ]))
      result `shouldEqual` Nothing

  describe "serpentine scanning (ditherImageBy, ditherRowsBy, initDitheringBy)" do
    let
      serpentineWith kernel = defaults # withKernel kernel # withScan serpentine
      bayer = ordered (bayerMap 4) (evenRamp 3)

    -- A position-dependent quantizer, as above: the three drivers must
    -- also agree on every pixel's position on the rows scanned right to
    -- left.
    it "gives the same rows in memory, streamed and row by row, for any kernel and image" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        let
          params = serpentineWith kernel
        in
          { rows: allRows (ditherRowsBy params bayer (LL.fromFoldable image)), each: ditherEachFrom (initDitheringBy params bayer) image }
            === { rows: ditherImageBy params bayer image, each: Right (ditherImageBy params bayer image) }

    -- Row 0 runs left to right; a single column is its own mirror image;
    -- without diffusion, the order the pixels are visited in can't matter.
    it "changes nothing for an image of one row, for one of one column, and without diffusion" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        let
          both params picture =
            { serpentine: ditherImageBy (params # withScan serpentine) bayer picture
            , raster: ditherImageBy params bayer picture
            }
          oneRow = both (defaults # withKernel kernel) (Array.take 1 image)
          oneColumn = both (defaults # withKernel kernel) (map (Array.take 1) image)
          none = both (defaults # withKernel noDiffusion) image
        in
          [ oneRow.serpentine, oneColumn.serpentine, none.serpentine ] === [ oneRow.raster, oneColumn.raster, none.raster ]

    it "can reuse a state: going back to an older one (an undo) scans the next row as dithering that history fresh does" do
      let
        params = serpentineWith floydSteinberg
        first = [ 10.0, 200.0, 90.0 ]
        second = [ 30.0, 140.0, 250.0 ]
        other = [ 250.0, 5.0, 120.0 ]
      case ditherRow (initDitheringBy params q) first of
        Left problem -> fail problem
        Right r1 -> do
          case ditherRow r1.next second of
            Left problem -> fail problem
            Right _ -> pure unit
          case ditherRow r1.next other of
            Left problem -> fail problem
            Right r2 -> [ r1.row, r2.row ] `shouldEqual` ditherImageBy params q [ first, other ]
