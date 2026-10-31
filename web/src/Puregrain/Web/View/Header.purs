-- | The page's header (decisions 29 and 32): the logo's lockup in the
-- | theme's set, "lab" after it, the tagline, the links, and the switch
-- | between the light and the dark theme.
module Puregrain.Web.View.Header (header) where

import Prelude

import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Puregrain.Web.State (Action(..))
import Puregrain.Web.Text (texts)
import Puregrain.Web.Theme (Theme(..))
import Puregrain.Web.View.Icon as Icon
import Puregrain.Web.View.Parts (helpUrl, repositoryUrl)

header :: forall w. Theme -> HH.HTML w Action
header theme =
  HH.header [ HP.class_ (H.ClassName "top") ]
    [ HH.div [ HP.class_ (H.ClassName "brand") ]
        -- Both sets of the logo, at their size; the stylesheet shows the
        -- theme's. Not a link: a click there would reload the page.
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
