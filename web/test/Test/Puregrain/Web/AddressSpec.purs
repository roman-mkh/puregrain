module Test.Puregrain.Web.AddressSpec (spec) where

import Prelude

import Data.Maybe (Maybe(..))
import Puregrain.Web.Address (addressIn, nameOf, siteOf)
import Puregrain.Web.Status (LoadFailure(..))
import Puregrain.Web.Text (texts)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

nothingBut :: { uriList :: String, html :: String, text :: String }
nothingBut = { uriList: "", html: "", text: "" }

spec :: Spec Unit
spec = describe "Puregrain.Web.Address" do
  it "takes a picture's own address from the HTML before the link around it" do
    addressIn
      { uriList: "https://example.org/page"
      , html: "<a href=\"https://example.org/page\"><img alt=\"a bird\" src=\"https://img.example.org/bird.jpg?w=400&amp;h=300\"></a>"
      , text: "https://example.org/page"
      }
      `shouldEqual` Just "https://img.example.org/bird.jpg?w=400&h=300"
    addressIn nothingBut { html = "<IMG SRC='https://a.example/x.png'>" } `shouldEqual` Just "https://a.example/x.png"
    addressIn nothingBut { html = "<img src=https://a.example/x.png width=10>" } `shouldEqual` Just "https://a.example/x.png"

  it "passes over a picture's address it can't fetch, for the list's" do
    addressIn { uriList: "https://a.example/x.png", html: "<img src=\"images/x.png\">", text: "" }
      `shouldEqual` Just "https://a.example/x.png"

  it "takes the list's first address, past comments and line ends" do
    addressIn nothingBut { uriList = "# from a page\r\nhttps://a.example/x.png\r\nhttps://a.example/y.png\r\n" }
      `shouldEqual` Just "https://a.example/x.png"

  it "takes the text when it's an address, and not when it's a sentence" do
    addressIn nothingBut { text = "  https://a.example/x.png \n" } `shouldEqual` Just "https://a.example/x.png"
    addressIn nothingBut { text = "look at https://a.example/x.png" } `shouldEqual` Nothing
    addressIn nothingBut { text = "HTTPS://A.EXAMPLE/X.PNG" } `shouldEqual` Just "HTTPS://A.EXAMPLE/X.PNG"

  it "takes only the addresses a page can fetch: http, https and a picture in the address" do
    map (\text -> addressIn nothingBut { text = text })
      [ "file:///home/me/x.png", "javascript:alert(1)", "data:text/html,<b>x</b>", "data:image/png;base64,iVBORw0KGgo=", "ftp://a.example/x.png" ]
      `shouldEqual` [ Nothing, Nothing, Nothing, Just "data:image/png;base64,iVBORw0KGgo=", Nothing ]
    addressIn nothingBut `shouldEqual` Nothing

  it "names a picture after its address's last part, decoded, without query or fragment" do
    map nameOf
      [ "https://upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg"
      , "https://images.example.org/photo.jpg?w=400#top"
      , "https://a.example/My%20photo.png"
      , "https://a.example/100%.png"
      , "https://a.example/pictures/"
      , "https://a.example"
      , "https://a.example?x=1"
      , "data:image/png;base64,iVBORw0KGgo="
      ]
      `shouldEqual` [ "Example.jpg", "photo.jpg", "My photo.png", "100%.png", "picture", "picture", "picture", "picture" ]

  it "names the site, with its port, and none for a picture in the address" do
    map siteOf
      [ "https://upload.wikimedia.org/wikipedia/x.jpg", "http://127.0.0.1:8080/p.png", "https://a.example?x=1", "data:image/png;base64,AA==" ]
      `shouldEqual` [ "upload.wikimedia.org", "127.0.0.1:8080", "a.example", "" ]

  it "says the picture couldn't be fetched, from which site, and what works instead" do
    texts.loadFailure (AddressFailed "img.example.org") false
      `shouldEqual` "The picture couldn't be fetched from img.example.org: the site doesn't let other pages read its pictures, or can't be reached. Copy the picture itself and paste it instead."
    texts.loadFailure (AddressFailed "") true
      `shouldEqual` "The picture couldn't be read from its address: the site doesn't let other pages read its pictures, or can't be reached. Copy the picture itself and paste it instead."
