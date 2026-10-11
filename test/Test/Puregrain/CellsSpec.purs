module Test.Puregrain.CellsSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Foldable (sum)
import Data.Lazy (defer)
import Data.List.Lazy as LL
import Data.List.Lazy.Types (List(..))
import Data.Maybe (Maybe(..), maybe)
import Data.Tuple (Tuple(..), fst, snd)
import Effect.Class (liftEffect)
import Partial.Unsafe (unsafeCrashWith)
import Test.QuickCheck (class Arbitrary, arbitrary, (===))
import Test.QuickCheck.Gen (chooseInt, elements, vectorOf)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Cells (CellPalette, CellSize, cellColors, colorPair, ditherBands, ditherCells, singleColor)
import Puregrain.Internal.Util (safeRange)
import Puregrain.Kernel (floydSteinberg)
import Puregrain.Pixel (RGB(..))
import Test.Puregrain.Arbitrary (TestKernel(..), genRGB)
import Test.Puregrain.Util (errorOf, mentions)

black :: RGB
black = RGB { r: 0.0, g: 0.0, b: 0.0 }

white :: RGB
white = RGB { r: 216.0, g: 216.0, b: 216.0 }

blue :: RGB
blue = RGB { r: 0.0, g: 0.0, b: 216.0 }

gray :: RGB
gray = RGB { r: 128.0, g: 128.0, b: 128.0 }

uniform :: Int -> Int -> RGB -> Array (Array RGB)
uniform width height c = Array.replicate height (Array.replicate width c)

-- | The cells `ditherCells` chooses. They don't depend on the kernel.
cellsOf :: forall c. CellSize -> (c -> CellPalette) -> NonEmptyArray c -> Array (Array RGB) -> Array (Array c)
cellsOf size toPalette candidates image = (ditherCells floydSteinberg size toPalette candidates image).cells

-- | Collects the lazy bands into what `ditherCells` returns.
collect :: forall c. LL.List { cells :: Array c, rows :: Array (Array RGB) } -> { cells :: Array (Array c), image :: Array (Array RGB) }
collect bands = { cells: map _.cells all, image: Array.concatMap _.rows all }
  where
  all = LL.toUnfoldable bands :: Array { cells :: Array c, rows :: Array (Array RGB) }

-- | Random cells: a cell size, candidates (each a pair of colors, the same
-- | color twice for a single color) and an image. The last candidate is a
-- | copy of the first, an exact tie the first must win. Half the images
-- | use only the candidates' own colors, so zero scores, and the early
-- | stop at 0, happen often.
type Cells =
  { size :: CellSize
  , candidates :: Array (Tuple RGB RGB)
  , image :: Array (Array RGB)
  }

newtype TestCells = TestCells Cells

instance Arbitrary TestCells where
  arbitrary = do
    width <- chooseInt 1 3
    height <- chooseInt 1 3
    first <- genCandidate
    others <- chooseInt 0 5 >>= \n -> vectorOf n genCandidate
    let
      candidates = Array.snoc (Array.cons first others) first
      colors = NEA.cons' (fst first) (Array.concatMap (\(Tuple a b) -> [ a, b ]) (Array.cons first others))
    ownColors <- arbitrary
    imageWidth <- chooseInt 1 7
    imageHeight <- chooseInt 1 7
    image <- vectorOf imageHeight (vectorOf imageWidth (if ownColors then elements colors else genRGB))
    pure (TestCells { size: { width, height }, candidates, image })
    where
    genCandidate = do
      single <- arbitrary
      a <- genRGB
      b <- if single then pure a else genRGB
      pure (Tuple a b)

-- | Candidates are passed as their indices.
indices :: Cells -> NonEmptyArray Int
indices t = NEA.range 0 (Array.length t.candidates - 1)

paletteOf :: Cells -> Int -> CellPalette
paletteOf t i = case Array.index t.candidates i of
  Just (Tuple a b) -> colorPair a b
  Nothing -> singleColor black

-- | An independent, plain version of the choice: each pixel's squared
-- | distance to the segment between the two colors, summed over the cell,
-- | for every candidate, without stopping early; the lowest wins, the
-- | earlier on a tie. Sums run in the same order as in the library, so
-- | equal scores are exactly equal in both.
naiveCells :: Cells -> Array (Array Int)
naiveCells t = map row (safeRange 0 (rows - 1))
  where
  w = maybe 0 Array.length (Array.head t.image)
  h = Array.length t.image
  rows = (h + t.size.height - 1) / t.size.height
  columns = (w + t.size.width - 1) / t.size.width
  row cy = map (cell cy) (safeRange 0 (columns - 1))
  cell cy cx =
    let
      pixels = do
        y <- safeRange (cy * t.size.height) (min h (cy * t.size.height + t.size.height) - 1)
        x <- safeRange (cx * t.size.width) (min w (cx * t.size.width + t.size.width) - 1)
        maybe [] pure (Array.index t.image y >>= \r -> Array.index r x)
      scores = Array.mapWithIndex (\i c -> Tuple i (sum (map (naiveError c) pixels))) t.candidates
      lower best current = if snd current < snd best then current else best
    in
      case Array.uncons scores of
        Just { head, tail } -> fst (Array.foldl lower head tail)
        Nothing -> 0

naiveError :: Tuple RGB RGB -> RGB -> Number
naiveError (Tuple (RGB a) (RGB b)) (RGB p) =
  let
    d = [ b.r - a.r, b.g - a.g, b.b - a.b ]
    v = [ p.r - a.r, p.g - a.g, p.b - a.b ]
    dot xs ys = sum (Array.zipWith (*) xs ys)
    length2 = dot d d
    t = if length2 == 0.0 then 0.0 else max 0.0 (min 1.0 (dot v d / length2))
  in
    sum (map (\e -> e * e) (Array.zipWith (\vi di -> vi - t * di) v d))

spec :: Spec Unit
spec = describe "Puregrain.Cells" do

  describe "CellPalette" do
    it "holds one color, or two in the order given; the same color twice is one color" do
      cellColors (colorPair black white) `shouldEqual` NEA.cons' black [ white ]
      cellColors (colorPair white white) `shouldEqual` NEA.singleton white
      cellColors (singleColor gray) `shouldEqual` NEA.singleton gray

  describe "the choice of cells" do
    it "prefers the pair a gray can be mixed from: black and white, not blue and white" do
      let
        candidates = NEA.cons' { name: "blue-white", palette: colorPair blue white }
          [ { name: "black-white", palette: colorPair black white } ]
      map (map _.name) (cellsOf { width: 8, height: 8 } _.palette candidates (uniform 8 8 gray))
        `shouldEqual` [ [ "black-white" ] ]

    it "lets the earlier candidate win a tie: a white cell fits white alone and black-white" do
      let
        alone = { name: "white", palette: singleColor white }
        pair = { name: "black-white", palette: colorPair black white }
        choose candidates = map (map _.name) (cellsOf { width: 8, height: 8 } _.palette candidates (uniform 8 8 white))
      choose (NEA.cons' alone [ pair ]) `shouldEqual` [ [ "white" ] ]
      choose (NEA.cons' pair [ alone ]) `shouldEqual` [ [ "black-white" ] ]

    it "agrees with a plain search over full scores, for any cells (the early stops change nothing)" do
      quickCheck \(TestCells t) ->
        cellsOf t.size (paletteOf t) (indices t) t.image === naiveCells t

    it "covers the whole image, with partial cells at the right and bottom edges" do
      let cells = cellsOf { width: 4, height: 4 } identity (NEA.singleton (singleColor gray)) (uniform 10 5 gray)
      map Array.length cells `shouldEqual` [ 3, 3 ]

  describe "ditherCells" do
    it "gives every pixel one of its own cell's colors, with any kernel" do
      quickCheck \(TestKernel kernel) (TestCells t) ->
        let
          result = ditherCells kernel t.size (paletteOf t) (indices t) t.image
          ownColor y x pixel =
            case Array.index result.cells (y / t.size.height) >>= \r -> Array.index r (x / t.size.width) of
              Just c -> NEA.elem pixel (cellColors (paletteOf t c))
              Nothing -> false
          wrong = Array.filter not (Array.concat (Array.mapWithIndex (\y r -> Array.mapWithIndex (ownColor y) r) result.image))
        in
          Array.length wrong === 0

    it "has no cells and no rows for an empty image" do
      let result = ditherCells floydSteinberg { width: 8, height: 8 } identity (NEA.singleton (singleColor gray)) []
      { cells: Array.length result.cells, rows: Array.length result.image } `shouldEqual` { cells: 0, rows: 0 }

    it "stops with an error naming a row of a different length" do
      let image = [ [ gray, gray, gray ], [ gray, gray ] ]
      result <- liftEffect (errorOf \_ -> Array.length (ditherCells floydSteinberg { width: 2, height: 2 } identity (NEA.singleton (singleColor gray)) image).image)
      result `shouldSatisfy` mentions "row 1 has 2 pixels, but the first row has 3"

  describe "ditherBands" do
    it "gives the same cells and rows as ditherCells, for any kernel and cells" do
      quickCheck \(TestKernel kernel) (TestCells t) ->
        collect (ditherBands kernel t.size (paletteOf t) (indices t) (LL.fromFoldable t.image))
          === ditherCells kernel t.size (paletteOf t) (indices t) t.image

    it "works on an endless stream of rows" do
      let
        row = [ black, gray, white, blue, gray ]
        candidates = NEA.cons' (colorPair black white) [ colorPair blue white ]
        bands = ditherBands floydSteinberg { width: 2, height: 2 } identity candidates (LL.repeat row)
      (collect (LL.take 3 bands)).image `shouldEqual`
        (ditherCells floydSteinberg { width: 2, height: 2 } identity candidates (Array.replicate 6 row)).image

    it "reads a band's rows only when that band is asked for" do
      let
        row = [ gray, gray ]
        -- Two rows per band; the third row, the second band's first, stops
        -- with an error when it's read.
        input = LL.cons row (LL.cons row (List (defer \_ -> unsafeCrashWith "the third input row was read")))
        bands = ditherBands floydSteinberg { width: 2, height: 2 } identity (NEA.singleton (singleColor gray)) input
      -- Both inside `errorOf`, so reading too early fails this test
      -- instead of stopping the whole test run.
      firstBand <- liftEffect (errorOf \_ -> Array.length (collect (LL.take 1 bands)).image)
      firstBand `shouldEqual` Nothing
      secondBand <- liftEffect (errorOf \_ -> LL.length (LL.take 2 bands))
      secondBand `shouldSatisfy` mentions "the third input row was read"

    it "stops with an error naming a row of a different length, when its band is reached" do
      let
        rows = [ [ gray, gray ], [ gray, gray ], [ gray, gray, gray ] ]
        bands = ditherBands floydSteinberg { width: 2, height: 2 } identity (NEA.singleton (singleColor gray)) (LL.fromFoldable rows)
      firstBand <- liftEffect (errorOf \_ -> Array.length (collect (LL.take 1 bands)).image)
      firstBand `shouldEqual` Nothing
      secondBand <- liftEffect (errorOf \_ -> LL.length (LL.take 2 bands))
      secondBand `shouldSatisfy` mentions "row 2 has 3 pixels, but the first row has 2"
