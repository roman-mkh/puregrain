module Test.Puregrain.ParamsSpec (spec) where

import Prelude

import Data.Array.NonEmpty as NEA
import Data.Foldable (for_)
import Test.QuickCheck ((===))
import Test.QuickCheck.Gen (elements)
import Test.Spec (Spec, describe, it)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Cells (ditherCells, ditherCellsBy, nearestInCell, orderedInCell)
import Puregrain.Dither (defaults, ditherImage, ditherImageBy, withGamma, withKernel)
import Puregrain.Gamma (gammaOff)
import Puregrain.Kernel (noDiffusion)
import Puregrain.Machine.ZxSpectrum (screen)
import Puregrain.Ordered (ordered)
import Puregrain.Quantize (nearestLevel, threshold)
import Test.Puregrain.Arbitrary (genImage, genKernel, genLevels, genRGBImage)
import Test.Puregrain.Util (bayerMap, curves)

spec :: Spec Unit
spec = describe "Puregrain.Internal.Params (DitherParams)" do

  it "starts from no diffusion and gammaOff" do
    quickCheck do
      image <- genImage
      levels <- genLevels
      q <- elements (NEA.cons' (threshold 128.0) [ nearestLevel levels, ordered (bayerMap 4) levels ])
      pure (ditherImageBy defaults q image === ditherImage noDiffusion q image)
    quickCheck do
      image <- genRGBImage
      rule <- elements (NEA.cons' nearestInCell [ orderedInCell (bayerMap 2) ])
      pure (ditherCellsBy defaults rule screen image === ditherCells noDiffusion rule screen image)

  it "takes the last of two settings of the same kind" do
    quickCheck do
      first <- genKernel
      second <- genKernel
      image <- genImage
      pure
        ( ditherImageBy (defaults # withKernel first # withKernel second) (threshold 128.0) image
            === ditherImageBy (defaults # withKernel second) (threshold 128.0) image
        )

  for_ curves \c -> describe c.name do

    it "gives the same result whatever the order of the settings" do
      quickCheck do
        kernel <- genKernel
        image <- genImage
        pure
          ( ditherImageBy (defaults # withKernel kernel # withGamma c.gamma) (threshold 128.0) image
              === ditherImageBy (defaults # withGamma c.gamma # withKernel kernel) (threshold 128.0) image
          )

    it "replaces an earlier gamma" do
      quickCheck do
        kernel <- genKernel
        image <- genImage
        other <- elements (NEA.cons' gammaOff (map _.gamma curves))
        pure
          ( ditherImageBy (defaults # withGamma other # withKernel kernel # withGamma c.gamma) (threshold 128.0) image
              === ditherImageBy (defaults # withKernel kernel # withGamma c.gamma) (threshold 128.0) image
          )
