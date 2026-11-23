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

import Data.Maybe (Maybe(..), isJust, isNothing, maybe)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Puregrain.Web.Picture (Picture)
import Puregrain.Web.Prepare (backgroundHex, backgroundShows)
import Puregrain.Web.Settings (Colors(..), KernelName, Settings, Target(..), allGammas, allMachines, allPalettes, bayerAllowed, bayerSides, flatCells, gammaActs, gammaId, kernelId, kernelMenu, machineId, machinePaletteId, machinePalettesOf, paletteId, screenSizeOf, serpentineAllowed)
import Puregrain.Web.State (Action(..), Load(..), Prepared, State, chooserRef, targetRef)
import Puregrain.Web.Text (texts)
import Puregrain.Web.View.Controls (cardMenu, fileButton, note, segments, step, stepper, toggleSwitch, withLink)
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
        , step 4 texts.method off (methodStep s gammaIdle)
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
  -- With a picture, whether the gamma can't change it now (`gammaActs`).
  gammaIdle = maybe false (\l -> not (gammaActs (l.picture.transparent || isJust l.prepared.fitted) s)) loaded
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

-- | The picture's name and size, and the file chooser, which Ctrl+O opens;
-- | before the first picture, a hint to drop one or to try the sample.
pictureStep :: forall w. Maybe Loaded -> Array (HH.HTML w Action)
pictureStep = case _ of
  Just { picture: p } ->
    [ HH.p [ HP.class_ (H.ClassName "picture-name") ] [ HH.text p.name ]
    , HH.p [ HP.class_ (H.ClassName "picture-size") ] [ HH.text (texts.pictureSize { width: p.width, height: p.height }) ]
    , fileButton { label: texts.chooseAnother, title: texts.withKeys texts.chooseAnother texts.chooseKeys, primary: false, ref: Just chooserRef, chosen: FileChosen }
    ]
  Nothing ->
    [ fileButton { label: texts.chooseFirst, title: texts.withKeys texts.chooseFirst texts.chooseKeys, primary: true, ref: Just chooserRef, chosen: FileChosen }
    , HH.p [ HP.class_ (H.ClassName "hint") ] (withLink texts.dropHint SampleChosen)
    ]

-- | The target's menu, which looks like its card (decision 37); for a
-- | machine and a picture of another size, what happens to it, and the
-- | choice to fit it to the screen (decision 22).
targetStep :: forall w. Settings -> Maybe Loaded -> Boolean -> Array (HH.HTML w Action)
targetStep s loaded fit =
  [ cardMenu { name: "target", label: texts.target, selected: targetValue s.target, pick: TargetChosen, ref: Just targetRef }
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

-- | The error diffusion's menu (`kernelMenu`: the originals, then two
-- | groups, as the colors' menu has "Palettes") with serpentine scanning's
-- | switch under it, disabled where it wouldn't act (`serpentineAllowed`;
-- | decision 36), the Bayer map's segments with the notes
-- | on them, the gamma's segments with a note when it can't change the
-- | picture (`gammaIdle`), and "gray first" as a toggle switch.
methodStep :: forall w. Settings -> Boolean -> Array (HH.HTML w Action)
methodStep s gammaIdle =
  [ HH.label [ HP.class_ (H.ClassName "field") ]
      [ HH.span [ HP.class_ (H.ClassName "label") ] [ HH.text texts.kernel ]
      , HH.select [ HE.onValueChange KernelChosen ]
          ( map kernelOption kernelMenu.main
              <> [ kernelGroup texts.kernelsLikeFloydSteinberg kernelMenu.likeFloydSteinberg
                 , kernelGroup texts.kernelsLikeJarvisJudiceNinke kernelMenu.likeJarvisJudiceNinke
                 ]
          )
      ]
  , toggleSwitch { label: texts.serpentine, checked: s.serpentine, disabled: not (serpentineAllowed s), toggle: SerpentineChosen }
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
              , HH.button [ HP.type_ HP.ButtonButton, HP.class_ (H.ClassName "link"), HE.onClick (const (BayerChosen "2")) ] [ HH.text texts.useBayer2 ]
              ]
          ]
        else []
      )
    <>
      [ HH.div [ HP.class_ (H.ClassName "field") ]
          [ HH.span [ HP.id "gamma-label", HP.class_ (H.ClassName "label") ] [ HH.text texts.gamma ]
          , segments
              { name: "gamma", labelledBy: "gamma-label", selected: gammaId s.gamma, disabled: false, pick: GammaChosen }
              (map (\g -> { value: gammaId g, text: texts.gammaName g }) allGammas)
          ]
      ]
    <> (if gammaIdle then [ note [ HH.text texts.gammaNoEffect ] ] else [])
    <> [ toggleSwitch { label: texts.gray, checked: s.gray, disabled: false, toggle: GrayChosen } ]
  where
  kernelOption :: KernelName -> HH.HTML w Action
  kernelOption k = option (kernelId k) (texts.kernelName k) (k == s.kernel)
  kernelGroup label kernels = HH.optgroup [ HP.attr (H.AttrName "label") label ] (map kernelOption kernels)
