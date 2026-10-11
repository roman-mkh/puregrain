module Test.Puregrain.CellsSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Foldable (sum)
import Data.Maybe (Maybe(..), maybe)
import Data.Tuple (Tuple(..), fst, snd)
import Effect.Class (liftEffect)
import Test.QuickCheck (class Arbitrary, arbitrary, (===))
import Test.QuickCheck.Gen (chooseInt, elements, vectorOf)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Cells (CellPalette, CellSize, cellColors, cellQuantize, chooseCells, colorPair, singleColor)
import Puregrain.Dither (ditherImage)
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

-- | Candidates are passed to `chooseCells` as their indices.
indices :: Cells -> NonEmptyArray Int
indices t = NEA.range 0 (Array.length t.candidates - 1)

paletteOf :: Cells -> Int -> CellPalette
paletteOf t i = case Array.index t.candidates i of
  Just (Tuple a b) -> colorPair a b
  Nothing -> singleColor black

-- | An independent, plain version of the score: each pixel's squared
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

  describe "chooseCells" do
    it "prefers the pair a gray can be mixed from: black and white, not blue and white" do
      let
        candidates = NEA.cons' { name: "blue-white", palette: colorPair blue white }
          [ { name: "black-white", palette: colorPair black white } ]
      map (map _.name) (chooseCells { width: 8, height: 8 } _.palette candidates (uniform 8 8 gray))
        `shouldEqual` [ [ "black-white" ] ]

    it "lets the earlier candidate win a tie: a white cell fits white alone and black-white" do
      let
        alone = { name: "white", palette: singleColor white }
        pair = { name: "black-white", palette: colorPair black white }
        choose candidates = map (map _.name) (chooseCells { width: 8, height: 8 } _.palette candidates (uniform 8 8 white))
      choose (NEA.cons' alone [ pair ]) `shouldEqual` [ [ "white" ] ]
      choose (NEA.cons' pair [ alone ]) `shouldEqual` [ [ "black-white" ] ]

    it "agrees with a plain search over full scores, for any cells (the early stops change nothing)" do
      quickCheck \(TestCells t) ->
        chooseCells t.size (paletteOf t) (indices t) t.image === naiveCells t

    it "covers the whole image, with partial cells at the right and bottom edges" do
      let cells = chooseCells { width: 4, height: 4 } identity (NEA.singleton (singleColor gray)) (uniform 10 5 gray)
      map Array.length cells `shouldEqual` [ 3, 3 ]

    it "has no cells for an empty image" do
      Array.length (chooseCells { width: 8, height: 8 } identity (NEA.singleton (singleColor gray)) [])
        `shouldEqual` 0

  describe "cellQuantize" do
    it "gives every pixel one of its own cell's colors, with any kernel" do
      quickCheck \(TestKernel kernel) (TestCells t) ->
        let
          cells = chooseCells t.size (paletteOf t) (indices t) t.image
          out = ditherImage kernel (cellQuantize t.size (paletteOf t) cells) t.image
          ownColor y x pixel =
            case Array.index cells (y / t.size.height) >>= \r -> Array.index r (x / t.size.width) of
              Just c -> NEA.elem pixel (cellColors (paletteOf t c))
              Nothing -> false
          wrong = Array.filter not (Array.concat (Array.mapWithIndex (\y r -> Array.mapWithIndex (ownColor y) r) out))
        in
          Array.length wrong === 0

    it "stops with an error naming a pixel outside its cells" do
      let
        cells = chooseCells { width: 2, height: 2 } identity (NEA.singleton (singleColor gray)) (uniform 2 2 gray)
        quantizer = cellQuantize { width: 2, height: 2 } identity cells
      result <- liftEffect (errorOf \_ -> Array.length (ditherImage floydSteinberg quantizer (uniform 4 4 gray)))
      result `shouldSatisfy` mentions "pixel (2, 0) is outside the cells cellQuantize was given"
