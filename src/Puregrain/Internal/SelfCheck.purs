-- | The engine self-check's machinery: the fingerprint of the light curves
-- | and its stored reference. Internal: may change without notice. What it
-- | checks and why: docs/exact-arithmetic.md, "The engine self-check".
module Puregrain.Internal.SelfCheck
  ( EngineReport(..)
  , Digest
  , fingerprint
  , referenceDigests
  , roundTripProblems
  , reportFor
  ) where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.Int (toNumber)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Number (floor, isFinite, isNaN, (%))

import Puregrain.Internal.Gamma (Gamma, fromLightFormula, fromLightValue, power1p2, power1p5, power1p8, srgb, toLightFormula, toLightValue)

-- | The result of `Puregrain.SelfCheck.checkEngine`: whether the
-- | JavaScript engine computed the light curves exactly as the reference,
-- | and if not, what differed.
-- What failed, one sentence each; nothing when every check passed. (The
-- comment above is what Pursuit shows, through the public module's
-- re-export.)
newtype EngineReport = EngineReport { problems :: Array String }

-- | One curve's results in one direction, folded into a whole number.
type Digest = { name :: String, digest :: Number }

-- | The reference: the fingerprint as Node 22.14 computed it, the same in
-- | Node 26.13, Chromium 156, Firefox 157 and WebKit 27.2 (2026-11-14). It
-- | changes only when a curve changes on purpose, in the same commit and
-- | with a CHANGELOG line, since every picture dithered with that curve
-- | then changes too; never just to make a check pass.
referenceDigests :: Array Digest
referenceDigests =
  [ { name: "gamma1p2, to light", digest: 202998122.0 }
  , { name: "gamma1p2, back", digest: 649587125.0 }
  , { name: "gamma1p5, to light", digest: 1450936529.0 }
  , { name: "gamma1p5, back", digest: 500580780.0 }
  , { name: "gamma1p8, to light", digest: 225166765.0 }
  , { name: "gamma1p8, back", digest: 139725880.0 }
  , { name: "gammaSrgb, to light", digest: 254712697.0 }
  , { name: "gammaSrgb, back", digest: 2072982452.0 }
  ]

curves :: Array { name :: String, gamma :: Gamma }
curves =
  [ { name: "gamma1p2", gamma: power1p2 }
  , { name: "gamma1p5", gamma: power1p5 }
  , { name: "gamma1p8", gamma: power1p8 }
  , { name: "gammaSrgb", gamma: srgb }
  ]

-- | Each computed curve's formulas, both ways, over fixed values and the
-- | generator's, each folded into a digest, in `referenceDigests`' order.
-- | Takes `unit` so that nothing is computed when the module loads.
fingerprint :: Unit -> Array Digest
fingerprint _ = Array.concatMap both curves
  where
  both c =
    [ { name: c.name <> ", to light", digest: digestOf (toLightFormula c.gamma) }
    , { name: c.name <> ", back", digest: digestOf (fromLightFormula c.gamma) }
    ]

-- | A problem for each curve under which a byte doesn't come back exactly
-- | from its light, through the table: a check that needs no reference.
roundTripProblems :: Unit -> Array String
roundTripProblems _ = Array.mapMaybe check curves
  where
  check c = map (\b -> c.name <> ": byte " <> show b <> " doesn't come back exactly from its light")
    (Array.find (\b -> fromLightValue c.gamma (toLightValue c.gamma (toNumber b)) /= toNumber b) (0 .. 255))

-- | The report: the digests that differ from the reference, then the
-- | other problems.
reportFor :: Array Digest -> Array Digest -> Array String -> EngineReport
reportFor reference computed others = EngineReport { problems: Array.catMaybes (Array.zipWith differs reference computed) <> others }
  where
  differs r c =
    if r.digest == c.digest then Nothing
    else Just (c.name <> ": the results differ from the reference (digest " <> whole c.digest <> " instead of " <> whole r.digest <> ")")
  whole x = show (Int.floor x)

-- The generator's count, per curve and direction (linear light's decision
-- 2, in CLAUDE.md: enough for the engines' optimizing compilers
-- to run, and rare faults a fair chance to show).
generated :: Int
generated = 200000

digestOf :: (Number -> Number) -> Number
digestOf f = foldGenerated f (Array.foldl (\h v -> foldNumber h (f v)) 0.0 (fixedInputs unit)) 1.0 generated

-- The bytes and the halves between them, the levels of 2 to 16 with the
-- midpoints between them, and special values: sRGB's two switch points,
-- a fractional threshold, and values just outside 0–255.
fixedInputs :: Unit -> Array Number
fixedInputs _ = bytesAndHalves <> Array.concatMap ramp (2 .. 16) <> specials
  where
  bytesAndHalves = Array.concatMap (\b -> [ toNumber b, toNumber b + 0.5 ]) (0 .. 255)
  ramp n =
    let
      level i = 255.0 * toNumber i / toNumber (n - 1)
    in
      Array.concatMap (\i -> if i == 0 then [ level i ] else [ level i, (level (i - 1) + level i) / 2.0 ]) (0 .. (n - 1))
  specials = [ 0.04045 * 255.0, 0.0031308 * 255.0, 96.5, -0.5, 255.5, 300.0 ]

-- Park and Miller's "minimal standard" generator, next = 48271 × x mod
-- (2^31 − 1), exact in a Number since 48271 × x stays below 2^53; each
-- value scaled to [−20, 300] and its result folded in, one at a time.
foldGenerated :: (Number -> Number) -> Number -> Number -> Int -> Number
foldGenerated f h x n =
  if n <= 0 then h
  else
    let
      x' = (48271.0 * x) % modulus
    in
      foldGenerated f (foldNumber h (f (-20.0 + 320.0 * (x' / modulus)))) x' (n - 1)

modulus :: Number
modulus = 2147483647.0

-- One part folded in: (h × 48271 + part) mod (2^31 − 1). Every value is a
-- whole number below 2^53, so each operation is exact.
mix :: Number -> Number -> Number
mix h part = (h * 48271.0 + part) % modulus

-- A number taken apart exactly, and its parts folded in: a code for 0,
-- NaN and the infinities; else the sign, the power of 2, and the
-- mantissa's 53 bits as two whole numbers. Never its printed digits,
-- which the standard leaves open in the last place.
foldNumber :: Number -> Number -> Number
foldNumber h x =
  if x == 0.0 then mix h 1.0
  else if isNaN x then mix h 2.0
  else if not (isFinite x) then mix h (if x > 0.0 then 3.0 else 4.0)
  else if x < 0.0 then foldMagnitude (mix h 6.0) (negate x)
  else foldMagnitude (mix h 5.0) x

foldMagnitude :: Number -> Number -> Number
foldMagnitude h x =
  let
    n = normalized x 0
    whole = n.m * 4503599627370496.0 -- 2^52: the mantissa as a whole number
    high = floor (whole / 67108864.0) -- 2^26
    low = whole - high * 67108864.0
  in
    mix (mix (mix h (toNumber n.e + 2000.0)) high) low

-- Into [1, 2) by halving or doubling, which is exact, counting the power.
normalized :: Number -> Int -> { m :: Number, e :: Int }
normalized x e =
  if x >= 2.0 then normalized (x / 2.0) (e + 1)
  else if x < 1.0 then normalized (x * 2.0) (e - 1)
  else { m: x, e }
