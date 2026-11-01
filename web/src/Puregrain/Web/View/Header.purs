-- | The page's header (decisions 29, 30 E and 32): the logo's lockup in
-- | the theme's set, "lab" after it, the tagline, the links, on phones the
-- | button that opens the settings' panel, and the switch between the
-- | light and the dark theme.
module Puregrain.Web.View.Header (header) where

import Prelude

import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Puregrain.Web.State (Action(..), settingsButtonRef)
import Puregrain.Web.Text (texts)
import Puregrain.Web.Theme (Theme(..))
import Puregrain.Web.View.Icon as Icon
import Puregrain.Web.View.Parts (helpUrl, inert, repositoryUrl)

-- | `settings`: whether the settings' button shows, which needs a
-- | picture, and whether its panel is open, which makes the header
-- | `inert`. The stylesheet shows the button on phones only.
header :: forall w. { theme :: Theme, settings :: Boolean, panelOpen :: Boolean } -> HH.HTML w Action
header { theme, settings, panelOpen } =
  HH.header [ HP.class_ (H.ClassName "top"), inert panelOpen ]
    -- The page's heading, "puregrain lab": both sets of the logo, at
    -- their size, the stylesheet showing the theme's, and "lab". Not a
    -- link: a click there would reload the page.
    [ HH.h1 [ HP.class_ (H.ClassName "brand") ]
        [ lockup "zx" "for-dark"
        , lockup "c64" "for-light"
        , HH.span [ HP.class_ (H.ClassName "lab") ] [ HH.text texts.labName ]
        ]
    , HH.p [ HP.class_ (H.ClassName "tagline") ]
        [ HH.span [ HP.class_ (H.ClassName "long") ] [ HH.text texts.tagline ]
        , HH.span [ HP.class_ (H.ClassName "short") ] [ HH.text texts.taglineShort ]
        ]
    , HH.nav [ HP.class_ (H.ClassName "links"), HP.attr (HH.AttrName "aria-label") texts.linksLabel ]
        [ HH.a [ HP.href helpUrl ] [ HH.text texts.help ]
        , HH.a [ HP.href repositoryUrl ] [ HH.text texts.source ]
        -- Hidden rather than left out, so the theme's switch keeps its
        -- place (Halogen matches children by position).
        , HH.button
            [ HP.ref settingsButtonRef
            , HP.type_ HP.ButtonButton
            , HP.class_ (H.ClassName "settings-button")
            , HP.attr (HH.AttrName "aria-expanded") (if panelOpen then "true" else "false")
            , HP.attr (HH.AttrName "aria-controls") "settings"
            , HP.prop (H.PropName "hidden") (not settings)
            , HE.onClick (const PanelOpened)
            ]
            [ Icon.sliders
            , HH.span [ HP.class_ (H.ClassName "sr-only") ] [ HH.text texts.settingsLabel ]
            ]
        -- A toggle: "Dark theme", pressed or not, showing the theme on.
        , HH.button
            [ HP.type_ HP.ButtonButton
            , HP.class_ (H.ClassName "theme")
            , HP.attr (HH.AttrName "aria-pressed") (if theme == Dark then "true" else "false")
            , HP.title texts.darkTheme
            , HE.onClick (const ThemeToggled)
            ]
            [ if theme == Dark then Icon.moon else Icon.sun
            , HH.span [ HP.class_ (H.ClassName "sr-only") ] [ HH.text texts.darkTheme ]
            ]
        ]
    ]
  where
  lockup set shownIn =
    HH.img
      [ HP.src ("logo/" <> set <> "/lockup.png")
      , HP.width 270
      , HP.height 44
      , HP.alt texts.title
      , HP.class_ (H.ClassName shownIn)
      ]
