-- | The page's footer (decision 29): the versions of the page and of the
-- | library, the licenses, and the repository.
module Puregrain.Web.View.Footer (footer) where

import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Puregrain.Web.Text (texts)
import Puregrain.Web.View.Parts (helpUrl, licenseUrl, logoTermsUrl, repositoryUrl)

-- | On a phone the header has no room for its links, so Help is here
-- | too, and the repository.
footer :: forall w i. String -> HH.HTML w i
footer libraryVersion =
  HH.footer [ HP.class_ (H.ClassName "foot") ]
    [ HH.span_ [ HH.text (texts.versions libraryVersion) ]
    , HH.a [ HP.href helpUrl ] [ HH.text texts.help ]
    , HH.a [ HP.href licenseUrl ] [ HH.text texts.codeLicense ]
    , HH.a [ HP.href logoTermsUrl ] [ HH.text texts.logoLicense ]
    , HH.a [ HP.href repositoryUrl ] [ HH.text texts.onGitHub ]
    ]
