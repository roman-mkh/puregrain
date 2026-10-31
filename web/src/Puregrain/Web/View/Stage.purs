-- | The picture area and the bar under it (decisions 29 to 31). Empty, a
-- | drop zone with how to start and the promises. With a picture, the
-- | original and the result stacked in one box, at whole-number zoom,
-- | split between them by a handle, and an overlay while files are
-- | dragged over the page; under them the zoom, the notes on the file
-- | and the run, and the download.
-- |
-- | Parts that come and go are hidden rather than removed, or sit in
-- | fixed boxes: Halogen matches unkeyed children by position, and would
-- | otherwise rebuild a canvas, blank, or a control that has the focus.
-- | And an element removed while a drag is over it never passes on its
-- | `dragleave`, which the drag's count needs (`Puregrain.Web.Drag`).
module Puregrain.Web.View.Stage (stage) where

import Prelude

import Data.Array as Array
import Data.Int (toNumber)
import Data.Maybe (Maybe(..), fromMaybe, isJust, isNothing, maybe)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Puregrain.Web.Download (buttonFormat, extension, formatsFor)
import Puregrain.Web.Estimate (rounded)
import Puregrain.Web.Picture (Picture)
import Puregrain.Web.Settings (Target(..), screenSizeOf)
import Puregrain.Web.State (Action(..), Load(..), Prepared, State, downloadName, downloadsRef, formatsRef, handleRef, layersRef, originalRef, resultRef)
import Puregrain.Web.Status (Run(..), RunNote(..), resultShows, runNote)
import Puregrain.Web.Text (texts)
import Puregrain.Web.View.Controls (fileButton, segments)
import Puregrain.Web.View.Icon as Icon
import Puregrain.Web.Zoom (cssSize, zooms)
import Web.Event.Event (EventType(..))

stage :: forall w. State -> Array (HH.HTML w Action)
stage state = case state.load of
  Loaded loaded@{ prepared } ->
    let
      size = cssSize state.pixelRatio state.zoom { width: prepared.width, height: prepared.height }
      sizeStyle = "width: " <> show size.width <> "px; height: " <> show size.height <> "px"
      -- The split as a share of the width: the result's left edge is cut
      -- there, at whole picture columns, so at whole screen pixels, and
      -- the handle's line sits on it.
      percent = show (toNumber state.split * 100.0 / toNumber prepared.width)
      shows = resultShows state.run
    in
      [ HH.div [ HP.class_ (H.ClassName "area") ]
          -- The picture area takes the focus, for + and − (decision 33).
          [ HH.div [ HP.class_ (H.ClassName "view"), HP.tabIndex 0, HE.onKeyDown ViewKey ]
              [ HH.div [ HP.ref layersRef, HP.class_ (H.ClassName "layers") ]
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
                      , HP.style (sizeStyle <> "; clip-path: inset(0 0 0 " <> percent <> "%)")
                      , hidden (not shows)
                      ]
                  , handle state.split prepared.width percent shows
                  , HH.div [ HP.class_ (H.ClassName "sides"), hidden (not shows) ]
                      [ HH.span_ [ HH.text texts.original ]
                      , HH.span_ [ HH.text texts.result ]
                      ]
                  ]
              ]
          -- Over the picture area while files are dragged over the page
          -- (decision 30 D); the drag's events go through it.
          , HH.div [ HP.class_ (H.ClassName "drop-overlay"), hidden (state.dragged == 0) ]
              [ HH.p_ [ HH.text texts.dropToLoad ] ]
          ]
      , HH.div [ HP.class_ (H.ClassName "bar") ]
          [ HH.div [ HP.class_ (H.ClassName "bar-view") ]
              [ HH.span [ HP.id "zoom-label", HP.class_ (H.ClassName "bar-label") ] [ HH.text texts.zoom ]
              , segments
                  { name: "zoom", labelledBy: "zoom-label", selected: show state.zoom, disabled: false, pick: ZoomChosen }
                  (zooms <#> \z -> { value: show z, text: texts.zoomLevel z })
              ]
          , HH.div [ HP.class_ (H.ClassName "bar-state") ]
              [ fileNote state
              , runNotes state.run
              ]
          , HH.div [ HP.class_ (H.ClassName "bar-actions") ] [ downloadBox state loaded ]
          ]
      ]
  NoPicture ->
    [ HH.div [ HP.class_ (H.ClassName "area") ]
        [ HH.div [ HP.classes [ H.ClassName "view", H.ClassName "empty" ] ]
            [ HH.div [ HP.class_ (H.ClassName "start") ]
                [ HH.div [ HP.class_ (H.ClassName "start-note") ]
                    (maybe [] (\name -> [ HH.p [ HP.class_ (H.ClassName "warning") ] [ HH.text (texts.notAPicture name) ] ]) state.notAPicture)
                , dropZone state
                ]
            ]
        ]
    ]

-- | The handle on the split (decision 31): dragged by the pointer, moved
-- | by the keys while it has the focus, a slider for screen readers. Its
-- | knob stays in sight when the picture is taller than its area.
handle :: forall w. Int -> Int -> String -> Boolean -> HH.HTML w Action
handle split width percent shows =
  HH.div
    [ HP.ref handleRef
    , HP.class_ (H.ClassName "handle")
    , HP.tabIndex 0
    , HP.attr (H.AttrName "role") "slider"
    , HP.attr (H.AttrName "aria-label") texts.split
    , HP.attr (H.AttrName "aria-valuemin") "0"
    , HP.attr (H.AttrName "aria-valuemax") (show width)
    , HP.attr (H.AttrName "aria-valuenow") (show split)
    , HP.attr (H.AttrName "aria-valuetext") (texts.splitValue split width)
    , HP.style ("left: " <> percent <> "%")
    , hidden (not shows)
    , HE.handler (EventType "pointerdown") SplitPressed
    , HE.handler (EventType "pointermove") SplitDragged
    , HE.handler (EventType "pointerup") SplitReleased
    , HE.handler (EventType "pointercancel") SplitReleased
    , HE.onKeyDown SplitKey
    ]
    [ HH.span [ HP.class_ (H.ClassName "knob") ] [ Icon.leftRight ] ]

-- | The empty picture area (decisions 29 and 30): the drop zone, lit while
-- | files are dragged over the page, with the logo's mark in the theme's
-- | set; how to start, and the promises. While the first picture loads,
-- | it says so.
dropZone :: forall w. State -> HH.HTML w Action
dropZone state =
  HH.div [ HP.classes ([ H.ClassName "drop" ] <> (if state.dragged > 0 then [ H.ClassName "lit" ] else [])) ]
    [ HH.div [ HP.class_ (H.ClassName "drop-inner") ]
        [ mark "zx" "for-dark"
        , mark "c64" "for-light"
        , HH.p [ HP.class_ (H.ClassName "drop-title") ] [ HH.text (maybe texts.dropTitle texts.loading state.loading) ]
        , HH.p [ HP.class_ (H.ClassName "drop-choose") ]
            [ HH.text texts.dropOr
            , fileButton { label: texts.chooseFirst, title: texts.withKeys texts.chooseFirst texts.chooseKeys, primary: true, ref: Nothing, chosen: FileChosen }
            ]
        , HH.p [ HP.class_ (H.ClassName "hint") ] [ HH.text texts.formats ]
        , HH.p [ HP.class_ (H.ClassName "about") ] [ HH.text texts.description ]
        , HH.p [ HP.class_ (H.ClassName "about") ] [ HH.text texts.promises ]
        ]
    ]
  where
  -- Decorative: the header's logo names the page.
  mark set shownIn =
    HH.img
      [ HP.src ("logo/" <> set <> "/mark.png")
      , HP.width 88
      , HP.height 88
      , HP.alt ""
      , HP.class_ (H.ClassName shownIn)
      ]

-- | The note on the file last chosen, in the bar's middle: being loaded,
-- | or not a picture, while the current one stays (decision 30 C).
fileNote :: forall w i. State -> HH.HTML w i
fileNote state =
  HH.div [ HP.class_ (H.ClassName "bar-file"), hidden (isNothing note) ]
    [ HH.p [ HP.classes (if failed then [ H.ClassName "warning" ] else []) ] [ HH.text (fromMaybe "" note) ] ]
  where
  note = case state.loading, state.notAPicture of
    Just name, _ -> Just (texts.loading name)
    _, Just name -> Just (texts.notAPictureKept name)
    _, _ -> Nothing
  failed = isNothing state.loading && isJust state.notAPicture

-- | The run's note in the bar's middle (`Puregrain.Web.Status.runNote`),
-- | after the file's: the progress has its bar, the time left and Cancel.
runNotes :: forall w. Run -> HH.HTML w Action
runNotes run =
  HH.div [ HP.class_ (H.ClassName "bar-run"), hidden (isNothing note) ]
    [ HH.p [ HP.classes (if failure then [ H.ClassName "warning" ] else []) ] [ HH.text text ]
    , HH.div
        [ HP.class_ (H.ClassName "progress")
        , HP.attr (H.AttrName "role") "progressbar"
        , HP.attr (H.AttrName "aria-label") texts.ditheringLabel
        , HP.attr (H.AttrName "aria-valuemin") "0"
        , HP.attr (H.AttrName "aria-valuemax") (show progress.total)
        , HP.attr (H.AttrName "aria-valuenow") (show progress.done)
        , hidden (not running)
        ]
        [ HH.div
            [ HP.class_ (H.ClassName "fill")
            , HP.style ("width: " <> show (if progress.total > 0 then toNumber progress.done * 100.0 / toNumber progress.total else 0.0) <> "%")
            ]
            []
        ]
    , HH.button
        [ HP.type_ HP.ButtonButton
        , HP.title (texts.withKeys texts.cancel texts.cancelKeys)
        , HE.onClick (const Cancel)
        , hidden (not running)
        ]
        [ HH.text texts.cancel ]
    ]
  where
  note = runNote run
  progress = case note of
    Just (Progress p) -> p
    _ -> { done: 0, total: 0, left: Nothing }
  running = case note of
    Just (Progress _) -> true
    _ -> false
  failure = case note of
    Just (DitherFailed _) -> true
    Just SaveFailed -> true
    _ -> false
  text = case note of
    Nothing -> ""
    Just OriginalShown -> texts.originalShown
    Just (Progress p) -> texts.dithering { done: p.done, total: p.total } <> maybe "" (\ms -> ", " <> texts.timeLeft (rounded ms)) p.left
    Just RunCancelled -> texts.cancelled
    Just (DitherFailed reason) -> texts.ditherFailed reason
    Just SaveFailed -> texts.saveFailed

-- | The download, at the bar's right (decision 31): a button naming its
-- | format, the one chosen last while it's possible, else PNG
-- | (`Puregrain.Web.Download`). For a machine, ▾ beside it shows the
-- | list of formats, each with the name it's saved under, or why it isn't
-- | possible: a disclosure, a button showing a list of buttons (decision
-- | 34). The impossible ones are only marked so (`aria-disabled`), so
-- | that Tab still reaches them and their reason. Unavailable until
-- | there's a result.
downloadBox :: forall w. State -> { picture :: Picture, prepared :: Prepared } -> HH.HTML w Action
downloadBox state loaded =
  HH.div [ HP.ref downloadsRef, HP.class_ (H.ClassName "downloads") ]
    ( [ HH.button
          [ HP.type_ HP.ButtonButton
          , HP.class_ (H.ClassName "primary")
          , HP.disabled (not ready)
          , HP.title (texts.withKeys (texts.downloadAs current) texts.downloadKeys)
          , HE.onClick (const DownloadClicked)
          ]
          [ HH.text (texts.downloadAs current) ]
      ]
        <>
          if Array.length choices < 2 then []
          else
            [ HH.button
                [ HP.ref formatsRef
                , HP.type_ HP.ButtonButton
                , HP.classes [ H.ClassName "primary", H.ClassName "more" ]
                , HP.disabled (not ready)
                , HP.attr (H.AttrName "aria-expanded") (if open then "true" else "false")
                , HP.attr (H.AttrName "aria-controls") "formats"
                , HP.attr (H.AttrName "aria-label") texts.moreFormats
                , HP.title texts.moreFormats
                , HE.onClick (const FormatsToggled)
                ]
                [ Icon.caretDown ]
            , HH.ul [ HP.id "formats", HP.class_ (H.ClassName "formats"), hidden (not open) ]
                ( choices <#> \c ->
                    HH.li_
                      [ HH.button
                          ( [ HP.type_ HP.ButtonButton, HE.onClick (const (FormatChosen c.format)) ]
                              <> (if c.possible then [] else [ HP.attr (H.AttrName "aria-disabled") "true" ])
                          )
                          [ HH.span [ HP.class_ (H.ClassName "ext") ] [ HH.text ("." <> extension c.format) ]
                          , HH.span_ [ HH.text (texts.formatName c.format) ]
                          , HH.small_ [ HH.text (if c.possible then downloadName state loaded c.format else reason) ]
                          ]
                      ]
                )
            ]
    )
  where
  choices = formatsFor state.settings.target { width: loaded.prepared.width, height: loaded.prepared.height }
  current = buttonFormat state.format choices
  ready = case state.run of
    Finished _ -> true
    _ -> false
  open = state.formatsOpen && ready
  reason = case state.settings.target of
    Machine machine -> texts.needsScreen (screenSizeOf machine)
    AnyScreen -> ""

-- | The `hidden` property: the element stays in place, unseen.
hidden :: forall r i. Boolean -> HP.IProp r i
hidden = HP.prop (H.PropName "hidden")
