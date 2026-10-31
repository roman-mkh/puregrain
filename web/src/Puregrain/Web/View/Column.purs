-- | The settings' column (decisions 29 and 31): the numbered steps, 1
-- | Picture, 2 Target, 3 Colors, 4 Method, and 5 Background when the
-- | background shows. On the empty page the steps after the first are
-- | there, disabled (decision 30), so nothing jumps when a picture comes.
-- | On phones the column is a panel over the page, with Apply at its
-- | bottom; the stylesheet shows Apply there only.
-- |
-- | Each step's parts keep their places when notes come and go after
-- | them: Halogen matches unkeyed children by position, so a control with
-- | the focus must not move.
module Puregrain.Web.View.Column (column) where

import Prelude

import Data.Maybe (Maybe(..), isNothing, maybe)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Puregrain.Web.Picture (Picture)
import Puregrain.Web.Prepare (backgroundHex, backgroundShows)
import Puregrain.Web.Settings (Colors(..), Settings, Target(..), allKernels, allMachines, allPalettes, bayerAllowed, bayerSides, flatCells, kernelId, machineId, machinePaletteId, machinePalettesOf, paletteId, screenSizeOf)
import Puregrain.Web.State (Action(..), Load(..), Prepared, State, chooserRef)
import Puregrain.Web.Text (texts)
import Puregrain.Web.View.Controls (cards, fileButton, note, segments, step, stepper, toggleSwitch)
import Puregrain.Web.View.Parts (option)

type Loaded = { picture :: Picture, prepared :: Prepared }

column :: forall w. State -> Array (HH.HTML w Action)
column state =
  -- The steps in a box of their own, so Apply keeps its place when the
  -- fifth comes and goes.
  [ HH.div [ HP.class_ (H.ClassName "steps") ]
      ( [ step 1 texts.picture false (pictureStep loaded)
        , step 2 texts.target off (targetStep s loaded state.fit)
        , step 3 texts.colors off (colorsStep s state.typed.threshold)
        , step 4 texts.method off (methodStep s)
        ]
          <> backgroundStep
      )
  , HH.div [ HP.class_ (H.ClassName "apply") ]
      [ HH.button [ HP.type_ HP.ButtonButton, HP.class_ (H.ClassName "primary"), HE.onClick (const PanelClosed) ] [ HH.text texts.apply ] ]
  ]
  where
  s = state.settings
  loaded = case state.load of
    Loaded l -> Just l
    _ -> Nothing
  off = isNothing loaded
  -- Whenever the background shows in the result (decision 27).
  backgroundStep = case loaded of
    Just l | backgroundShows l.picture.transparent l.prepared.fitted ->
      let
        hex = "#" <> backgroundHex state.background
      in
        [ step 5 texts.background false
            ( [ HH.label [ HP.class_ (H.ClassName "color") ]
                  [ HH.input
                      [ HP.type_ HP.InputColor
                      , HP.value hex
                      , HP.attr (H.AttrName "aria-label") texts.background
                      , HE.onValueChange BackgroundChosen
                      ]
                  , HH.span [ HP.class_ (H.ClassName "hex") ] [ HH.text hex ]
                  ]
              ]
                <> (if l.picture.transparent then [ note [ HH.text texts.transparentParts ] ] else [])
            )
        ]
    _ -> []

-- | The picture's name and size, and the file chooser, which Ctrl+O opens.
pictureStep :: forall w. Maybe Loaded -> Array (HH.HTML w Action)
pictureStep = case _ of
  Just { picture: p } ->
    [ HH.p [ HP.class_ (H.ClassName "picture-name") ] [ HH.text p.name ]
    , HH.p [ HP.class_ (H.ClassName "picture-size") ] [ HH.text (texts.pictureSize { width: p.width, height: p.height }) ]
    , fileButton { label: texts.chooseAnother, title: texts.withKeys texts.chooseAnother texts.chooseKeys, primary: false, ref: Just chooserRef, chosen: FileChosen }
    ]
  Nothing ->
    [ fileButton { label: texts.chooseFirst, title: texts.withKeys texts.chooseFirst texts.chooseKeys, primary: true, ref: Just chooserRef, chosen: FileChosen }
    , HH.p [ HP.class_ (H.ClassName "hint") ] [ HH.text texts.dropHint ]
    ]

-- | The target's cards; for a machine and a picture of another size, what
-- | happens to it, and the choice to fit it to the screen (decision 22).
targetStep :: forall w. Settings -> Maybe Loaded -> Boolean -> Array (HH.HTML w Action)
targetStep s loaded fit =
  [ cards { name: "target", label: texts.target, selected: targetValue s.target, pick: TargetChosen }
      ( [ item AnyScreen "any" ]
          <> map (\m -> item (Machine m) (machineId m)) allMachines
      )
  ]
    <> fitting
  where
  item target value = { value, title: texts.targetName target, line: texts.targetLine target }
  targetValue = case _ of
    AnyScreen -> "any"
    Machine m -> machineId m
  fitting = case s.target, loaded of
    Machine m, Just l | screenSizeOf m /= size l.picture ->
      [ note
          [ HH.text case l.prepared.fitted of
              Just f -> texts.fitted m { picture: size l.picture, placement: f.placement }
              Nothing -> texts.sizeNote m (size l.picture)
          ]
      , HH.label [ HP.class_ (H.ClassName "check") ]
          [ HH.input [ HP.type_ HP.InputCheckbox, HP.checked fit, HE.onChecked FitChosen ]
          , HH.text texts.fitChoice
          ]
      ]
    _, _ -> []
  size p = { width: p.width, height: p.height }

-- | The colors' menu, the palettes grouped, then its value: the levels
-- | between − and +, or the threshold as a slider and a number. The slider
-- | shows its value while dragged and starts the run when released
-- | (`ThresholdDragged`, then `ThresholdTyped`).
colorsStep :: forall w. Settings -> Int -> Array (HH.HTML w Action)
colorsStep s shownThreshold =
  [ HH.select [ HP.attr (H.AttrName "aria-label") texts.colors, HE.onValueChange ColorsChosen ]
      ([ option "original" texts.colorsOriginal (s.colors == Original) ] <> options s.target)
  ]
    <> amount
  where
  options = case _ of
    AnyScreen ->
      [ option "threshold" texts.colorsThreshold (isThreshold s.colors)
      , option "levels" texts.colorsLevels (isLevels s.colors)
      , HH.optgroup [ HP.attr (H.AttrName "label") texts.palettesGroup ]
          (map (\p -> option (paletteId p) (texts.palette p) (s.colors == Palette p)) allPalettes)
      ]
    Machine m -> map (\p -> option (machinePaletteId p) (texts.machinePalette m p) (s.colors == MachineColors p)) (machinePalettesOf m)
  isThreshold = case _ of
    Threshold _ -> true
    _ -> false
  isLevels = case _ of
    Levels _ -> true
    _ -> false
  labelledBy id = HP.attr (H.AttrName "aria-labelledby") id
  amount = case s.colors of
    Threshold _ ->
      [ HH.div [ HP.class_ (H.ClassName "field") ]
          [ HH.span [ HP.id "threshold-label", HP.class_ (H.ClassName "label") ] [ HH.text texts.thresholdValue ]
          , HH.div [ HP.class_ (H.ClassName "row") ]
              [ HH.input
                  [ HP.type_ HP.InputRange
                  , HP.min 0.0
                  , HP.max 255.0
                  , HP.value (show shownThreshold)
                  , labelledBy "threshold-label"
                  , HE.onValueInput ThresholdDragged
                  , HE.onValueChange ThresholdTyped
                  ]
              , HH.input
                  [ HP.type_ HP.InputNumber
                  , HP.min 0.0
                  , HP.max 255.0
                  , HP.value (show shownThreshold)
                  , labelledBy "threshold-label"
                  , HE.onValueInput ThresholdTyped
                  ]
              ]
          ]
      ]
    Levels n ->
      [ HH.div [ HP.class_ (H.ClassName "field") ]
          [ HH.span [ HP.id "levels-label", HP.class_ (H.ClassName "label") ] [ HH.text texts.levelsValue ]
          , stepper { labelledBy: "levels-label", value: n, low: 2, high: 256, fewer: texts.fewerLevels, more: texts.moreLevels, set: LevelsTyped }
          ]
      ]
    _ -> []

-- | The error diffusion's menu, the Bayer map's segments with the notes
-- | on them, and "gray first" as a toggle switch.
methodStep :: forall w. Settings -> Array (HH.HTML w Action)
methodStep s =
  [ HH.label [ HP.class_ (H.ClassName "field") ]
      [ HH.span [ HP.class_ (H.ClassName "label") ] [ HH.text texts.kernel ]
      , HH.select [ HE.onValueChange KernelChosen ]
          (map (\k -> option (kernelId k) (texts.kernelName k) (k == s.kernel)) allKernels)
      ]
  , HH.div [ HP.class_ (H.ClassName "field") ]
      [ HH.span [ HP.id "bayer-label", HP.class_ (H.ClassName "label") ] [ HH.text texts.bayer ]
      , segments
          { name: "bayer", labelledBy: "bayer-label", selected: maybe "none" show s.bayer, disabled: not (bayerAllowed s.colors), pick: BayerChosen }
          ([ { value: "none", text: texts.bayerOff } ] <> map (\side -> { value: show side, text: texts.bayerSide side }) bayerSides)
      ]
  ]
    <> (if bayerAllowed s.colors then [] else [ note [ HH.text texts.bayerNeedsLevels ] ])
    <>
      ( if flatCells s then
          [ note
              [ HH.text (texts.flatCells <> " ")
              , HH.button [ HP.type_ HP.ButtonButton, HP.class_ (H.ClassName "link"), HE.onClick (const (BayerChosen "8")) ] [ HH.text texts.useBayer8 ]
              ]
          ]
        else []
      )
    <> [ toggleSwitch { label: texts.gray, checked: s.gray, toggle: GrayChosen } ]
