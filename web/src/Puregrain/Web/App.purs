-- | The web UI's component. For now (phase 1 of web/ROADMAP.md) it starts
-- | the worker, sends it "ping" and shows the answer: a check that the
-- | page's and the worker's scripts work together.
module Puregrain.Web.App (component) where

import Prelude

import Data.Maybe (Maybe(..), maybe)
import Effect.Class (class MonadEffect, liftEffect)
import Foreign (unsafeFromForeign)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.Subscription as HS
import Puregrain.Web.Text (texts)
import Web.Worker.MessageEvent (data_)
import Web.Worker.Worker as Worker

type State = { answer :: Maybe String }

data Action = Initialize | Answered String

component :: forall q i o m. MonadEffect m => H.Component q i o m
component = H.mkComponent
  { initialState: const { answer: Nothing }
  , render
  , eval: H.mkEval H.defaultEval { handleAction = handleAction, initialize = Just Initialize }
  }

render :: forall m. State -> H.ComponentHTML Action () m
render state =
  HH.main [ HP.class_ (H.ClassName "container") ]
    [ HH.h1_ [ HH.text texts.title ]
    , HH.p_ [ HH.text (maybe texts.workerStarting texts.workerAnswered state.answer) ]
    ]

handleAction :: forall o m. MonadEffect m => Action -> H.HalogenM State Action () o m Unit
handleAction = case _ of
  Initialize -> do
    { emitter, listener } <- liftEffect HS.create
    void (H.subscribe emitter)
    worker <- liftEffect (Worker.new "worker.js" Worker.defaultWorkerOptions)
    -- The worker echoes what it gets, here a string. Messages with real
    -- content (phase 3) will be decoded, not read unchecked like this.
    liftEffect (Worker.onMessage (\event -> HS.notify listener (Answered (unsafeFromForeign (data_ event)))) worker)
    liftEffect (Worker.postMessage "ping" worker)
  Answered answer -> H.modify_ _ { answer = Just answer }
