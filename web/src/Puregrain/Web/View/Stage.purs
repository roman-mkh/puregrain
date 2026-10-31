-- | The picture area and the bar under it (decision 29): the original
-- | and the result stacked in one box, at whole-number zoom, split
-- | between them; under them the zoom and the split, the run's state, and
-- | the downloads. Phase 6's steps 3 and 4 give them their own controls.
module Puregrain.Web.View.Stage (stage) where

import Prelude

import Data.Int (toNumber)
import Data.Maybe (maybe)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Puregrain.Web.Estimate (rounded)
import Puregrain.Web.State (Action(..), Load(..), Run(..), State, originalRef, resultRef)
import Puregrain.Web.Text (texts)
import Puregrain.Web.View.Parts (option)
import Puregrain.Web.Zoom (cssSize, zooms)

stage :: forall w. State -> Array (HH.HTML w Action)
stage state = case state.load of
  Loaded { prepared } ->
    let
      size = cssSize state.pixelRatio state.zoom { width: prepared.width, height: prepared.height }
      sizeStyle = "width: " <> show size.width <> "px; height: " <> show size.height <> "px"
      -- The result's left edge is cut at the split, so the original shows
      -- on its left: at whole picture columns, so at whole screen pixels.
      cut = "clip-path: inset(0 0 0 " <> show (toNumber state.split * 100.0 / toNumber prepared.width) <> "%)"
      finished = isFinished state.run
    in
      -- The view and the bar are separate boxes, so the canvases keep
      -- their places whatever the bar shows: Halogen matches unkeyed
      -- children by position, and would otherwise rebuild a canvas,
      -- blank, whenever the progress bar appears or goes.
      [ HH.div [ HP.class_ (H.ClassName "view") ]
          [ HH.div [ HP.class_ (H.ClassName "layers") ]
              [ HH.canvas
                  [ HP.ref originalRef
                  , HP.class_ (H.ClassName "picture")
                  , HP.width prepared.width
                  , HP.height prepared.height
                  , HP.style sizeStyle
                  ]
              , HH.canvas
                  [ HP.ref resultRef
                  , HP.classes [ H.ClassName "picture", H.ClassName "result" ]
                  , HP.width prepared.width
                  , HP.height prepared.height
                  , HP.style (sizeStyle <> "; " <> cut)
                  , HP.prop (H.PropName "hidden") (not finished)
                  ]
              ]
          ]
      , HH.div [ HP.class_ (H.ClassName "bar") ]
          [ HH.div [ HP.class_ (H.ClassName "bar-view") ]
              [ HH.label_
                  [ HH.text texts.zoom
                  , HH.select [ HE.onValueChange ZoomChosen ]
                      (map (\z -> option (show z) (texts.zoomLevel z) (z == state.zoom)) zooms)
                  ]
              , HH.input
                  [ HP.type_ HP.InputRange
                  , HP.attr (H.AttrName "aria-label") texts.split
                  , HP.title texts.split
                  , HP.min 0.0
                  , HP.max (toNumber prepared.width)
                  , HP.value (show state.split)
                  , HP.disabled (not finished)
                  , HE.onValueInput SplitMoved
                  ]
              ]
          , HH.div [ HP.class_ (H.ClassName "bar-state") ] (runState state.run)
          , HH.div [ HP.class_ (H.ClassName "bar-actions") ] (downloads state.run)
          ]
      ]
  other ->
    [ HH.div [ HP.classes [ H.ClassName "view", H.ClassName "empty" ] ]
        [ HH.p_
            [ HH.text case other of
                Loading name -> texts.loading name
                Failed failure -> texts.failed failure
                _ -> texts.choose
            ]
        ]
    ]

-- | The run's state, in the bar's middle.
runState :: forall w. Run -> Array (HH.HTML w Action)
runState = case _ of
  Idle -> []
  Running r ->
    [ HH.p_ [ HH.text (texts.dithering { done: r.done, total: r.total } <> maybe "" (\ms -> ", " <> texts.timeLeft (rounded ms)) r.left) ]
    , HH.progress [ HP.max (toNumber r.total), HP.value (toNumber r.done) ] []
    , HH.button [ HP.type_ HP.ButtonButton, HE.onClick (const Cancel) ] [ HH.text texts.cancel ]
    ]
  Finished r -> if r.saveFailed then [ HH.p_ [ HH.text texts.saveFailed ] ] else []
  Cancelled -> [ HH.p_ [ HH.text texts.cancelled ] ]
  RunFailed reason -> [ HH.p_ [ HH.text (texts.ditherFailed reason) ] ]

-- | The downloads, at the bar's right: the PNG, and a machine's files.
downloads :: forall w. Run -> Array (HH.HTML w Action)
downloads = case _ of
  Finished r ->
    [ HH.button [ HP.type_ HP.ButtonButton, HE.onClick (const Save) ] [ HH.text texts.save ] ]
      <> map (\f -> HH.button [ HP.type_ HP.ButtonButton, HE.onClick (const (SaveFile f.format)) ] [ HH.text (texts.saveFile f.format) ]) r.files
  _ -> []

isFinished :: Run -> Boolean
isFinished = case _ of
  Finished _ -> true
  _ -> false
