module Test.Puregrain.Web.MessageSpec (spec) where

import Prelude

import Control.Monad.Except (runExcept)
import Data.Either (Either(..), isLeft)
import Data.Maybe (Maybe(..))
import Effect.Class (liftEffect)
import Foreign (unsafeToForeign)
import Puregrain (RGB(..))
import Puregrain.Web.Message (Reply(..), doneMessage, errorMessage, jobMessage, progressMessage, readJob, readReply)
import Puregrain.Web.Pixels (newPixels, readRow, writeRgbRow)
import Puregrain.Web.Settings (Colors(..), chooseBayer, chooseColors, initial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)
import Web.Worker.Types (unwrap)

spec :: Spec Unit
spec = describe "Puregrain.Web.Message" do
  it "reads back a job as the page sends it" do
    pixels <- liftEffect (newPixels (3 * 1 * 4))
    liftEffect (writeRgbRow pixels 3 0 [ RGB { r: 1.0, g: 2.0, b: 3.0 }, RGB { r: 4.0, g: 5.0, b: 6.0 }, RGB { r: 7.0, g: 8.0, b: 9.0 } ])
    let settings = chooseBayer (Just 4) (chooseColors (Levels 6) initial)
    case runExcept (readJob (unsafeToForeign (unwrap (jobMessage { settings, width: 3, height: 1, pixels })))) of
      Left errors -> fail (show errors)
      Right job -> do
        job.settings `shouldEqual` settings
        { width: job.width, height: job.height } `shouldEqual` { width: 3, height: 1 }
        row <- liftEffect (readRow job.pixels 3 0)
        row `shouldEqual` [ RGB { r: 1.0, g: 2.0, b: 3.0 }, RGB { r: 4.0, g: 5.0, b: 6.0 }, RGB { r: 7.0, g: 8.0, b: 9.0 } ]

  it "rejects a job with a missing field, settings the page wouldn't send, or pixels that aren't bytes" do
    pixels <- liftEffect (newPixels 4)
    let good = unwrap (jobMessage { settings: chooseColors (Levels 6) initial, width: 1, height: 1, pixels })
    -- (A job has no Show instance: its pixels are a typed array.)
    isLeft (runExcept (readJob (unsafeToForeign { settings: good.settings, width: 1, pixels }))) `shouldEqual` true
    isLeft (runExcept (readJob (unsafeToForeign (good { settings = good.settings { bayer = 3 } })))) `shouldEqual` true
    isLeft (runExcept (readJob (unsafeToForeign { settings: good.settings, width: 1, height: 1, pixels: [ 1, 2, 3, 4 ] }))) `shouldEqual` true

  it "reads back the worker's progress, result and errors, and rejects an unknown reply" do
    pixels <- liftEffect (newPixels 4)
    case runExcept (readReply (unsafeToForeign (unwrap (progressMessage { done: 3, total: 10 })))) of
      Right (Progress p) -> p `shouldEqual` { done: 3, total: 10 }
      _ -> fail "expected progress"
    case runExcept (readReply (unsafeToForeign (unwrap (doneMessage pixels)))) of
      Right (Done _) -> pure unit
      _ -> fail "expected the result"
    case runExcept (readReply (unsafeToForeign (unwrap (errorMessage "it broke")))) of
      Right (Failure reason) -> reason `shouldEqual` "it broke"
      _ -> fail "expected an error"
    case runExcept (readReply (unsafeToForeign { kind: "chat" })) of
      Left _ -> pure unit
      Right _ -> fail "expected an unknown reply to be rejected"
