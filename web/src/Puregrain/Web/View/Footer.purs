-- | The page's footer (decision 29): the versions of the page and of the
-- | library, the licenses, and the repository.
module Puregrain.Web.View.Footer (footer) where

import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Puregrain.Web.State (Action)
import Puregrain.Web.Status (EngineCheck)
import Puregrain.Web.Text (texts)
import Puregrain.Web.View.Engine (engineCheck)
import Puregrain.Web.View.Icon as Icon
import Puregrain.Web.View.Parts (helpUrl, inert, licenseUrl, logoTermsUrl, repositoryUrl)

-- | On a phone the header has no room for its links, so Help is here
-- | too, and the repository, and the engine check's icon, which the
-- | stylesheet shows here on a phone only. The versions on the left, with
-- | the repository after them, as GitHub's mark, named "puregrain on
-- | GitHub" for screen readers and in its tooltip: next to the name it
-- | points to, and off the links' line, which then fits one row on most
-- | phones. The links on the right. `inert` while the phone's panel is
-- | open.
footer :: forall w. { libraryVersion :: String, panelOpen :: Boolean, engine :: EngineCheck, engineOpen :: Boolean } -> HH.HTML w Action
footer { libraryVersion, panelOpen, engine, engineOpen } =
  HH.footer [ HP.class_ (H.ClassName "foot"), inert panelOpen ]
    [ HH.span [ HP.class_ (H.ClassName "foot-about") ]
        [ HH.span_ [ HH.text (texts.versions libraryVersion) ]
        , HH.a [ HP.href repositoryUrl, HP.class_ (H.ClassName "foot-github"), HP.title texts.onGitHub ]
            [ Icon.github
            , HH.span [ HP.class_ (H.ClassName "sr-only") ] [ HH.text texts.onGitHub ]
            ]
        ]
    , HH.span [ HP.class_ (H.ClassName "foot-links") ]
        [ engineCheck { check: engine, open: engineOpen, place: "foot" }
        , HH.a [ HP.href helpUrl ] [ HH.text texts.help ]
        , HH.a [ HP.href licenseUrl ] [ HH.text texts.codeLicense ]
        , HH.a [ HP.href logoTermsUrl ] [ HH.text texts.logoLicense ]
        ]
    ]
