-- | The settings column (decision 29): the picture's choice, and the
-- | settings for it. Phase 6's step 2 gives it its own controls; until
-- | then it holds the form that v1 and v2's phases 1 to 3 made.
module Puregrain.Web.View.Column (column) where

import Prelude

import Data.Int (toNumber)
import Data.Maybe (Maybe(..))
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Puregrain.Web.Prepare (Background, Placement, backgroundHex, backgroundShows)
import Puregrain.Web.Settings (Colors(..), Settings, Target(..), allKernels, allMachines, allPalettes, bayerAllowed, bayerSides, flatCells, kernelId, machineId, machinePaletteId, machinePalettesOf, paletteId, screenSizeOf)
import Puregrain.Web.State (Action(..), Load(..), State)
import Puregrain.Web.Text (texts)
import Puregrain.Web.View.Parts (option)

column :: forall w. State -> Array (HH.HTML w Action)
column state =
  [ HH.div [ HP.class_ (H.ClassName "choice") ]
      ( [ HH.label_
            [ HH.text texts.picture
            , HH.input [ HP.type_ HP.InputFile, HP.attr (H.AttrName "accept") "image/*", HE.onChange FileChosen ]
            ]
        ]
          <> case state.load of
            Loaded { picture: p } -> [ HH.p [ HP.class_ (H.ClassName "size") ] [ HH.text (texts.loaded { name: p.name, width: p.width, height: p.height }) ] ]
            _ -> []
      )
  , HH.div [ HP.class_ (H.ClassName "settings") ]
      case state.load of
        Loaded { picture: p, prepared } ->
          settingsForm state.settings
            { size: { width: p.width, height: p.height }, transparent: p.transparent, fit: state.fit, fitted: prepared.fitted, background: state.background }
        _ -> []
  ]

-- | The picture's side of the form: its size and transparency, the fit
-- | asked for and where it went, and the background color.
type PictureForm =
  { size :: { width :: Int, height :: Int }
  , transparent :: Boolean
  , fit :: Boolean
  , fitted :: Maybe { screen :: { width :: Int, height :: Int }, placement :: Placement }
  , background :: Background
  }

settingsForm :: forall w. Settings -> PictureForm -> Array (HH.HTML w Action)
settingsForm s pic =
  [ HH.label_
      [ HH.text texts.target
      , HH.select [ HE.onValueChange TargetChosen ]
          ( [ option "any" (texts.targetName AnyScreen) (s.target == AnyScreen) ]
              <> map (\m -> option (machineId m) (texts.targetName (Machine m)) (s.target == Machine m)) allMachines
          )
      ]
  ]
    <> fitting s.target
    <> background
    <>
      [ HH.label_
          [ HH.text texts.colors
          , HH.select [ HE.onValueChange ColorsChosen ]
              ([ option "original" texts.colorsOriginal (s.colors == Original) ] <> colorsOf s.target)
          ]
      ]
    <> amount s.colors
    <>
      [ HH.label_
          [ HH.text texts.kernel
          , HH.select [ HE.onValueChange KernelChosen ]
              (map (\k -> option (kernelId k) (texts.kernelName k) (k == s.kernel)) allKernels)
          ]
      , HH.label_
          [ HH.text texts.bayer
          , HH.select [ HE.onValueChange BayerChosen, HP.disabled (not (bayerAllowed s.colors)) ]
              ( [ option "none" texts.bayerOff (s.bayer == Nothing) ]
                  <> map (\side -> option (show side) (texts.bayerSide side) (s.bayer == Just side)) bayerSides
              )
          ]
      ]
    <> (if bayerAllowed s.colors then [] else [ HH.small_ [ HH.text texts.bayerNeedsLevels ] ])
    <> (if flatCells s then [ HH.small_ [ HH.text texts.flatCells ] ] else [])
    <>
      [ HH.label_
          [ HH.input [ HP.type_ HP.InputCheckbox, HP.checked s.gray, HE.onChecked GrayChosen ]
          , HH.text texts.gray
          ]
      ]
  where
  -- For a machine and a picture of another size: what happens to it, and
  -- the choice to fit it to the screen (decision 22).
  fitting = case _ of
    Machine m | screenSizeOf m /= pic.size ->
      [ HH.p_
          [ HH.small_
              [ HH.text case pic.fitted of
                  Just f -> texts.fitted m { picture: pic.size, placement: f.placement }
                  Nothing -> texts.sizeNote m pic.size
              ]
          ]
      , HH.label_
          [ HH.input [ HP.type_ HP.InputCheckbox, HP.checked pic.fit, HE.onChecked FitChosen ]
          , HH.text texts.fitChoice
          ]
      ]
    _ -> []
  -- Whenever the background shows in the result (decision 27).
  background =
    if backgroundShows pic.transparent pic.fitted then
      [ HH.label_
          [ HH.text texts.background
          , HH.input [ HP.type_ HP.InputColor, HP.value ("#" <> backgroundHex pic.background), HE.onValueChange BackgroundChosen ]
          ]
      ]
        <> (if pic.transparent then [ HH.small_ [ HH.text texts.transparentParts ] ] else [])
    else []
  colorsOf = case _ of
    AnyScreen ->
      [ option "threshold" texts.colorsThreshold (isThreshold s.colors)
      , option "levels" texts.colorsLevels (isLevels s.colors)
      ]
        <> map (\p -> option (paletteId p) (texts.palette p) (s.colors == Palette p)) allPalettes
    Machine m -> map (\p -> option (machinePaletteId p) (texts.machinePalette m p) (s.colors == MachineColors p)) (machinePalettesOf m)
  isThreshold = case _ of
    Threshold _ -> true
    _ -> false
  isLevels = case _ of
    Levels _ -> true
    _ -> false
  amount = case _ of
    Threshold t -> [ number texts.thresholdValue 0 255 t ThresholdTyped ]
    Levels n -> [ number texts.levelsValue 2 256 n LevelsTyped ]
    _ -> []
  number label low high value action =
    HH.label_
      [ HH.text label
      , HH.input
          [ HP.type_ HP.InputNumber
          , HP.min (toNumber low)
          , HP.max (toNumber high)
          , HP.value (show value)
          , HE.onValueInput action
          ]
      ]
