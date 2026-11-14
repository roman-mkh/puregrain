module Test.Puregrain.Web.DitherSpec (spec) where

import Prelude

import Data.Array ((..))
import Data.Foldable (for_)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Puregrain (Gamma, Quantize, RGB(..), gamma1p2, gamma1p5, gamma1p8, gammaOff, gammaSrgb, atkinson, bayer, burkes, evenRamp, fan, floydSteinberg, jarvisJudiceNinke, nearestColor, nearestLevel, noDiffusion, ordered, perChannel, runQuantize, shiauFan, shiauFan2, sierra2, sierra3, sierraLite, stucki, threshold, websafe216)
import Puregrain.Cells (CellQuantizer, ditherCells, nearestInCell, orderedInCell)
import Puregrain.Machine.C64 as C64
import Puregrain.Machine.ZxSpectrum as Zx
import Puregrain.Gamma (toLight)
import Puregrain.Web.Dither (Pipeline(..), gammaOf, kernelOf, pipelineFor, toNeutral, zxModeOf)
import Puregrain.Web.Settings (Colors(..), GammaName(..), KernelName(..), MachineName(..), MachinePaletteName(..), PaletteName(..), Target(..), chooseBayer, chooseColors, chooseTarget, initial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

-- Quantizers can't be compared directly; they're compared by what they
-- make of probe values at probe positions.
grays :: Array Number
grays = map (\i -> toNumber (i * 15)) (0 .. 17)

colors :: Array RGB
colors = do
  r <- [ 0.0, 70.0, 140.0, 210.0, 255.0 ]
  g <- [ 0.0, 128.0, 255.0 ]
  b <- [ 30.0, 200.0 ]
  pure (RGB { r, g, b })

positions :: Array { x :: Int, y :: Int }
positions = do
  x <- 0 .. 7
  y <- 0 .. 7
  pure { x, y }

probe :: forall a. Quantize a -> Array a -> Array a
probe q values = do
  p <- positions
  v <- values
  pure (runQuantize q p v)

shouldBeGray :: Maybe Pipeline -> Quantize Number -> Aff Unit
shouldBeGray pipeline expected = case pipeline of
  Just (Gray q) -> probe q grays `shouldEqual` probe expected grays
  Just (Color _) -> fail "expected gray processing, got RGB"
  Just (Screen _) -> fail "expected gray processing, got a machine's screen"
  Nothing -> fail "expected gray processing, got nothing"

shouldBeColor :: Maybe Pipeline -> Quantize RGB -> Aff Unit
shouldBeColor pipeline expected = case pipeline of
  Just (Color q) -> probe q colors `shouldEqual` probe expected colors
  Just (Gray _) -> fail "expected RGB processing, got gray"
  Just (Screen _) -> fail "expected RGB processing, got a machine's screen"
  Nothing -> fail "expected RGB processing, got nothing"

-- | Two cells by two of varied colors: rules inside the cells are compared
-- | by what they make of it, without diffusion, so the rule alone
-- | decides, as in the CLI's spec.
screenProbe :: Array (Array RGB)
screenProbe = map (\y -> map (\x -> RGB { r: toNumber ((x * 37 + y * 11) `mod` 256), g: toNumber ((x * 13 + y * 29) `mod` 256), b: toNumber ((x * y * 7) `mod` 256) }) (0 .. 15)) (0 .. 15)

shouldBeScreen :: Maybe Pipeline -> MachineName -> MachinePaletteName -> CellQuantizer -> Aff Unit
shouldBeScreen pipeline machine palette expected = case pipeline of
  Just (Screen s) -> do
    { machine: s.machine, palette: s.palette } `shouldEqual` { machine, palette }
    case machine of
      ZxSpectrumScreen ->
        ditherCells noDiffusion s.rule (zxModeOf palette) screenProbe `shouldEqual` ditherCells noDiffusion expected (zxModeOf palette) screenProbe
      C64HiresScreen ->
        ditherCells noDiffusion s.rule C64.hiresScreen screenProbe `shouldEqual` ditherCells noDiffusion expected C64.hiresScreen screenProbe
  Just _ -> fail "expected a machine's screen"
  Nothing -> fail "expected a machine's screen, got nothing"

spec :: Spec Unit
spec = describe "Puregrain.Web.Dither" do
  describe "pipelineFor, as the CLI chooses" do
    it "has nothing to dither for the original" do
      case pipelineFor initial false of
        Nothing -> pure unit
        Just _ -> fail "expected nothing"

    it "always dithers a threshold on gray" do
      for_ [ false, true ] \grayPicture ->
        shouldBeGray (pipelineFor (chooseColors (Threshold 100) initial) grayPicture) (threshold 100.0)

    it "dithers levels on gray for a gray picture, per channel otherwise" do
      let s = chooseColors (Levels 4) initial
      shouldBeGray (pipelineFor s true) (nearestLevel (evenRamp 4))
      shouldBeColor (pipelineFor s false) (perChannel (nearestLevel (evenRamp 4)))

    it "dithers a Bayer map over the levels, on gray or per channel alike" do
      let s = chooseBayer (Just 8) (chooseColors (Levels 3) initial)
      case bayer 8 of
        Just m -> do
          shouldBeGray (pipelineFor s true) (ordered m (evenRamp 3))
          shouldBeColor (pipelineFor s false) (perChannel (ordered m (evenRamp 3)))
        Nothing -> fail "no 8x8 Bayer map"

    it "always dithers a palette on RGB, even for a gray picture" do
      for_ [ false, true ] \grayPicture ->
        shouldBeColor (pipelineFor (chooseColors (Palette Websafe216) initial) grayPicture) (nearestColor websafe216)

    it "dithers a machine's colors cell by cell: the nearer color, or with a Bayer map ordered inside the cells" do
      let zx = chooseTarget (Machine ZxSpectrumScreen) initial
      for_ [ false, true ] \grayPicture ->
        shouldBeScreen (pipelineFor zx grayPicture) ZxSpectrumScreen FullPalette nearestInCell
      for_ [ NormalPalette, BrightPalette ] \palette ->
        shouldBeScreen (pipelineFor (chooseColors (MachineColors palette) zx) false) ZxSpectrumScreen palette nearestInCell
      case bayer 8, bayer 4 of
        Just m8, Just m4 -> do
          shouldBeScreen (pipelineFor (chooseBayer (Just 8) zx) false) ZxSpectrumScreen FullPalette (orderedInCell m8)
          shouldBeScreen (pipelineFor (chooseBayer (Just 4) (chooseTarget (Machine C64HiresScreen) initial)) false) C64HiresScreen FullPalette (orderedInCell m4)
        _, _ -> fail "no Bayer maps"

    it "has nothing to dither for a machine's colors without the machine, which the rules rule out" do
      case pipelineFor (initial { colors = MachineColors FullPalette }) false of
        Nothing -> pure unit
        Just _ -> fail "expected nothing"

  describe "names -> library values" do
    it "maps each kernel to the library's" do
      kernelOf NoDiffusion `shouldEqual` noDiffusion
      kernelOf FloydSteinberg `shouldEqual` floydSteinberg
      kernelOf Atkinson `shouldEqual` atkinson
      kernelOf JarvisJudiceNinke `shouldEqual` jarvisJudiceNinke
      kernelOf Stucki `shouldEqual` stucki
      kernelOf Burkes `shouldEqual` burkes
      kernelOf Sierra3 `shouldEqual` sierra3
      kernelOf Sierra2 `shouldEqual` sierra2
      kernelOf SierraLite `shouldEqual` sierraLite
      kernelOf Fan `shouldEqual` fan
      kernelOf ShiauFan `shouldEqual` shiauFan
      kernelOf ShiauFan2 `shouldEqual` shiauFan2

    it "maps each of the Spectrum's palettes to the library's screen mode" do
      -- A mode holds a function, so it's compared by its cell size and candidates.
      let same mode expected = { size: mode.size, candidates: mode.candidates } `shouldEqual` { size: expected.size, candidates: expected.candidates }
      same (zxModeOf FullPalette) Zx.screen
      same (zxModeOf NormalPalette) Zx.normalScreen
      same (zxModeOf BrightPalette) Zx.brightScreen

  describe "gammaOf" do
    -- A Gamma can't be compared directly; its light on a few values can.
    it "gives the library's preset for each name" do
      let
        lightOf :: Gamma -> Array Number
        lightOf g = map (toLight g) [ 0.0, 37.5, 100.0, 128.0, 255.0 ]
        presets = [ { name: GammaOff, gamma: gammaOff }, { name: Gamma1p2, gamma: gamma1p2 }, { name: Gamma1p5, gamma: gamma1p5 }, { name: Gamma1p8, gamma: gamma1p8 }, { name: GammaSrgb, gamma: gammaSrgb } ]
      for_ presets \p -> lightOf (gammaOf p.name) `shouldEqual` lightOf p.gamma

  describe "toNeutral, as the CLI's" do
    it "keeps every neutral pixel exactly, under every gamma" do
      for_ [ gammaOff, gamma1p2, gamma1p5, gamma1p8, gammaSrgb ] \g -> for_ (0 .. 255) \i -> do
        let v = toNumber i
        toNeutral g (RGB { r: v, g: v, b: v }) `shouldEqual` RGB { r: v, g: v, b: v }

    it "gives Rec. 601 luma's gray with gammaOff, as before" do
      toNeutral gammaOff (RGB { r: 0.0, g: 255.0, b: 0.0 }) `shouldEqual` RGB { r: 0.587 * 255.0, g: 0.587 * 255.0, b: 0.587 * 255.0 }
      toNeutral gammaOff (RGB { r: 100.0, g: 150.0, b: 200.0 }) `shouldEqual`
        let v = 0.299 * 100.0 + 0.587 * 150.0 + 0.114 * 200.0 in RGB { r: v, g: v, b: v }

    it "gives the gray with the color's light with gammaSrgb: pure blue 75.96, not 29.07" do
      toNeutral gammaSrgb (RGB { r: 0.0, g: 0.0, b: 255.0 }) `shouldEqual` RGB { r: 75.96269735836901, g: 75.96269735836901, b: 75.96269735836901 }
