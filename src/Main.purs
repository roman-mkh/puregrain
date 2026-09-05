module Main where

import Prelude

import Data.Array (zipWith)
import Effect (Effect)
import Effect.Console (log)
import Partial.Unsafe (unsafeCrashWith)

type Pixel = Array Number

type PixelRow = Array Pixel

type Error = Pixel

type DitherState =
  { current :: Array Error
  , next    :: Array Error
  }

scale :: Number -> Pixel -> Pixel 
scale k = map (_ * k)

add :: Pixel -> Pixel -> Pixel
add = zipWith (+)

sub :: Pixel -> Pixel -> Pixel
sub = zipWith (-)

processPixelRow
  :: PixelRow
  -> DitherState
  -> { output :: PixelRow
     , state  :: DitherState
     }
processPixelRow _ _ = unsafeCrashWith "not implemented"

quantize :: Pixel -> Pixel     
quantize _ = unsafeCrashWith "not implemented"

main :: Effect Unit
main = do
  log "🍝"

