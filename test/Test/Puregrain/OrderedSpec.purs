module Test.Puregrain.OrderedSpec (spec) where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Either (Either(..))
import Data.Foldable (for_, maximum)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..), fromMaybe, isNothing, maybe)
import Data.String (Pattern(..), contains)
import Data.Tuple (Tuple(..))
import Partial.Unsafe (unsafePartial)
import Test.QuickCheck (arbitrary, (===))
import Test.QuickCheck.Gen (Gen, chooseInt, elements, vectorOf)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Dither (ditherImage)
import Puregrain.Kernel (noDiffusion)
import Puregrain.Ordered (ThresholdMap, bayer, bayerMatrix, compileThresholdMap, ordered, thresholdAt)
import Puregrain.Pixel (RGB(..))
import Puregrain.Quantize (Quantize, evenRamp, nearestLevel, perChannel, runQuantize)
import Test.Puregrain.Arbitrary (TestImage(..), TestKernel(..), TestLevels(..), TestLevelsRGBImage(..), TestRGBImage(..), TestRanks(..), TestSample(..))
import Test.Puregrain.Util (bayerMap, compiledMap, neutral)

-- | Cell (row, column) of a matrix, for indices the test knows are valid.
at :: forall a. Array (Array a) -> Int -> Int -> a
at m row column = unsafePartial (Array.unsafeIndex (Array.unsafeIndex m row) column)

-- | A position anywhere in the first few repeats of a small map.
genPosition :: Gen { x :: Int, y :: Int }
genPosition = { x: _, y: _ } <$> chooseInt 0 40 <*> chooseInt 0 40

-- | The error message of a rejected map, if any (a `ThresholdMap` itself
-- | has no `Show`).
messageOf :: Either String ThresholdMap -> Maybe String
messageOf = case _ of
  Left message -> Just message
  Right _ -> Nothing

mentions :: String -> Maybe String -> Boolean
mentions text = maybe false (contains (Pattern text))

-- | Every pixel quantized on its own, at its position: what dithering
-- | with the empty kernel must give.
pointwise :: forall a. Quantize a -> Array (Array a) -> Array (Array a)
pointwise q = Array.mapWithIndex \y -> Array.mapWithIndex \x -> runQuantize q { x, y }

isNeutralRGB :: RGB -> Boolean
isNeutralRGB (RGB p) = p.r == p.g && p.g == p.b

sides :: Array Int
sides = [ 1, 2, 4, 8, 16, 32 ]

spec :: Spec Unit
spec = describe "Puregrain.Ordered" do

  describe "bayerMatrix" do
    it "is the standard 1×1, 2×2 and 4×4 Bayer matrix" do
      bayerMatrix 1 `shouldEqual` Just [ [ 0 ] ]
      bayerMatrix 2 `shouldEqual` Just [ [ 0, 2 ], [ 3, 1 ] ]
      bayerMatrix 4 `shouldEqual` Just
        [ [ 0, 8, 2, 10 ]
        , [ 12, 4, 14, 6 ]
        , [ 3, 11, 1, 9 ]
        , [ 15, 7, 13, 5 ]
        ]

    it "is n × n and holds every rank from 0 to n² − 1 exactly once (n = 1 … 32)" do
      for_ sides \n -> case bayerMatrix n of
        Nothing -> fail ("no matrix for side " <> show n)
        Just m -> do
          Array.length m `shouldEqual` n
          map Array.length m `shouldEqual` Array.replicate n n
          Array.sort (Array.concat m) `shouldEqual` (0 .. (n * n - 1))

    it "follows the recursion M₂ₙ = [[4Mₙ + 0, 4Mₙ + 2], [4Mₙ + 3, 4Mₙ + 1]]" do
      let quadrantOffset = [ [ 0, 2 ], [ 3, 1 ] ]
      for_ [ 2, 4, 8, 16, 32 ] \n -> case bayerMatrix n, bayerMatrix (n / 2) of
        Just big, Just half -> do
          let
            h = n / 2
            expected = (0 .. (n - 1)) <#> \y -> (0 .. (n - 1)) <#> \x ->
              4 * at half (y `mod` h) (x `mod` h) + at quadrantOffset (y / h) (x / h)
          big `shouldEqual` expected
        _, _ -> fail ("no matrix for side " <> show n <> " or " <> show (n / 2))

    it "is Nothing for a side that isn't a power of 2, and so is bayer" do
      for_ [ 0, -1, -2, -8, 3, 5, 6, 12, 24, 100 ] \n -> do
        bayerMatrix n `shouldSatisfy` isNothing
        isNothing (bayer n) `shouldEqual` true

  describe "compileThresholdMap" do
    it "rejects a map with no rows, an empty row, rows of different lengths, or a negative rank, saying which" do
      messageOf (compileThresholdMap []) `shouldSatisfy` mentions "at least one row"
      messageOf (compileThresholdMap [ [] ]) `shouldSatisfy` mentions "at least one entry"
      messageOf (compileThresholdMap [ [ 0, 1 ], [ 2 ] ]) `shouldSatisfy` mentions "row 0 has 2 entries, row 1 has 1"
      messageOf (compileThresholdMap [ [ 0, 1 ], [ 2, -3 ] ]) `shouldSatisfy` mentions "row 1, column 1 is -3"

    it "accepts any rectangular map of non-negative ranks" do
      quickCheck \(TestRanks ranks) -> isNothing (messageOf (compileThresholdMap ranks))

    it "gives each cell the threshold (rank + 0.5) / (maxRank + 1), repeated across the image" do
      quickCheck do
        TestRanks ranks <- arbitrary
        { x, y } <- genPosition
        let
          height = Array.length ranks
          width = maybe 0 Array.length (Array.head ranks)
          maxRank = fromMaybe 0 (maximum (Array.concat ranks))
          expected = (toNumber (at ranks (y `mod` height) (x `mod` width)) + 0.5) / toNumber (maxRank + 1)
        pure (thresholdAt (compiledMap ranks) { x, y } === expected)

    it "keeps every threshold strictly between 0 and 1" do
      quickCheck do
        TestRanks ranks <- arbitrary
        position <- genPosition
        let t = thresholdAt (compiledMap ranks) position
        pure (t > 0.0 && t < 1.0)

    it "bayer n has the thresholds (rank + 0.5) / n²" do
      for_ sides \n -> case bayerMatrix n of
        Nothing -> fail ("no matrix for side " <> show n)
        Just ranks -> do
          let m = bayerMap n
          for_ (0 .. (n - 1)) \y -> for_ (0 .. (n - 1)) \x ->
            thresholdAt m { x, y } `shouldEqual` ((toNumber (at ranks y x) + 0.5) / toNumber (n * n))

  describe "ordered" do
    it "always returns one of the levels, for any map, levels, value and position" do
      quickCheck do
        TestRanks ranks <- arbitrary
        TestLevels levels <- arbitrary
        TestSample v <- arbitrary
        position <- genPosition
        pure (NEA.elem (runQuantize (ordered (compiledMap ranks) levels) position v) levels)

    it "keeps a value that is exactly a level" do
      quickCheck do
        TestRanks ranks <- arbitrary
        TestLevels levels <- arbitrary
        v <- elements levels
        position <- genPosition
        pure (runQuantize (ordered (compiledMap ranks) levels) position v === v)

    it "snaps values below the lowest level, or above the highest, to that level" do
      quickCheck do
        TestRanks ranks <- arbitrary
        TestLevels levels <- arbitrary
        position <- genPosition
        let
          q = runQuantize (ordered (compiledMap ranks) levels) position
          lowest = NEA.head (NEA.sort levels)
          highest = NEA.last (NEA.sort levels)
        pure ({ below: q (lowest - 1.0), above: q (highest + 1.0) } === { below: lowest, above: highest })

    it "never decreases as the value rises, at a fixed position" do
      quickCheck do
        TestRanks ranks <- arbitrary
        TestLevels levels <- arbitrary
        TestSample a <- arbitrary
        TestSample b <- arbitrary
        position <- genPosition
        let q = runQuantize (ordered (compiledMap ranks) levels) position
        pure (q (min a b) <= q (max a b))

    it "picks the upper level exactly where the fraction is above the threshold (worked example)" do
      -- Bayer 2×2 thresholds: (0 + 0.5)/4, (2 + 0.5)/4 / (3 + 0.5)/4, (1 + 0.5)/4,
      -- i.e. 0.125 0.625 / 0.875 0.375. A value of 128 is 0.502 of the way
      -- from 0 to 255: white where the threshold is below that.
      let q = runQuantize (ordered (bayerMap 2) (evenRamp 2))
      map (\{ x, y } -> q { x, y } 128.0) [ { x: 0, y: 0 }, { x: 1, y: 0 }, { x: 0, y: 1 }, { x: 1, y: 1 } ]
        `shouldEqual` [ 255.0, 0.0, 0.0, 255.0 ]
      -- The map repeats: two columns and two rows on, the same answers.
      map (\{ x, y } -> q { x, y } 128.0) [ { x: 2, y: 2 }, { x: 3, y: 2 }, { x: 2, y: 3 }, { x: 3, y: 3 } ]
        `shouldEqual` [ 255.0, 0.0, 0.0, 255.0 ]

    -- With the trivial map, every threshold is 0.5: the upper level wins
    -- only when strictly nearer, like nearestLevel's earlier-wins rule on
    -- sorted levels. Whole numbers keep the arithmetic exact, so even
    -- exact ties must agree.
    it "with the 1 × 1 map is nearestLevel (whole-number levels and values)" do
      quickCheck do
        levels <- genWholeLevels
        v <- toNumber <$> chooseInt (-50) 300
        position <- genPosition
        pure
          ( runQuantize (ordered (bayerMap 1) levels) position v
              === runQuantize (nearestLevel (NEA.sort levels)) position v
          )

  describe "whole images" do
    it "the empty kernel quantizes each pixel on its own, at its position" do
      quickCheck \(TestRanks ranks) (TestLevels levels) (TestImage image) ->
        let q = ordered (compiledMap ranks) levels
        in ditherImage noDiffusion q image === pointwise q image

    -- Counted exactly in whole numbers: (r + 0.5) / n² < g / 255 is
    -- 255 · (2r + 1) < 2 · g · n².
    it "without diffusion, every n × n tile of a flat gray has one white pixel per threshold below its value" do
      for_ [ 2, 4, 8 ] \n -> for_ (0 .. 255) \g -> do
        let
          image = Array.replicate (2 * n) (Array.replicate (2 * n) (toNumber g))
          out = ditherImage noDiffusion (ordered (bayerMap n) (evenRamp 2)) image
          expected = Array.length (Array.filter (\r -> 255 * (2 * r + 1) < 2 * g * n * n) (0 .. (n * n - 1)))
          whiteIn tileY tileX = Array.length do
            y <- (tileY * n) .. (tileY * n + n - 1)
            x <- (tileX * n) .. (tileX * n + n - 1)
            if at out y x == 255.0 then [ unit ] else []
        [ whiteIn 0 0, whiteIn 0 1, whiteIn 1 0, whiteIn 1 1 ] `shouldEqual` Array.replicate 4 expected

    -- Unlike with error diffusion, where only an isolated neutral area
    -- stays neutral (see PixelSpec), here no error flows between pixels.
    it "without diffusion, every neutral pixel stays neutral, even in a colored image" do
      quickCheck \(TestRanks ranks) (TestLevels levels) (TestRGBImage colored) (TestImage grays) ->
        let
          -- Every other pixel replaced by a neutral one, where the gray image has one.
          image = Array.mapWithIndex
            ( \y -> Array.mapWithIndex \x px ->
                if (x + y) `mod` 2 == 0 then maybeNeutral y x px else px
            )
            colored
          maybeNeutral y x px = case Array.index grays y >>= flip Array.index x of
            Just v -> neutral v
            Nothing -> px
          out = ditherImage noDiffusion (perChannel (ordered (compiledMap ranks) levels)) image
          broken = Array.length do
            Tuple input output <- Array.concat (Array.zipWith (Array.zipWith Tuple) image out)
            if isNeutralRGB input && not (isNeutralRGB output) then [ unit ] else []
        in
          broken === 0

    it "an image made only of levels comes back unchanged, with any kernel" do
      quickCheck \(TestKernel kernel) (TestRanks ranks) (TestLevelsRGBImage { levels, image }) ->
        ditherImage kernel (perChannel (ordered (compiledMap ranks) levels)) image === image

-- | 1-8 whole-number levels in [-20, 275], unsorted, repeats allowed.
genWholeLevels :: Gen (NonEmptyArray Number)
genWholeLevels = do
  n <- chooseInt 0 7
  h <- chooseInt (-20) 275
  t <- vectorOf n (chooseInt (-20) 275)
  pure (map toNumber (NEA.cons' h t))
