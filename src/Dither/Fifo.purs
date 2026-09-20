module Dither.Fifo where

import Prelude

import Data.Array as Array
import Data.List.Lazy as LL
import Data.List as DL
import Data.Maybe (Maybe)
import Data.Sequence as Seq
import Data.Tuple (Tuple(..))

-- | A FIFO-like container of `Number`s, used to hold error-diffusion
-- | fractions for a single kernel offset as they travel from the pixel
-- | that produced them to the pixel that consumes them.
-- |
-- | Every method below is called exactly once per pixel (or once per
-- | row, where noted) in the dithering hot path, so the real-world
-- | performance of the whole algorithm is dominated by how cheaply an
-- | instance can implement these four operations. Each instance should
-- | document its own actual complexity per method, and should aim for
-- | the target given here wherever its underlying representation
-- | allows it — falling short of the target is not a correctness bug,
-- | but it will show up directly in `docs/benchmarks.md`.
class Fifo (f :: Type -> Type) where

  -- | `replicate n x` builds a `Fifo` containing exactly `n` copies of
  -- | `x`, in order — so `dequeue` on the result yields `x` exactly `n`
  -- | times before the `Fifo` becomes empty.
  -- |
  -- | Called once per row, to build the leading zero-padding for an
  -- | offset with a positive `dx` (see `Dither.Kernel.paddingFor`), and
  -- | to build the leading zero-padding for the `current`/`building`
  -- | layers at the start of every row. `n` is always small — bounded
  -- | by the kernel's horizontal reach (`maxForward`), never by image
  -- | width or height.
  -- |
  -- | Target complexity: O(n). Since `n` is always small, this is never
  -- | the bottleneck regardless of the instance's constant factors.
  replicate :: forall a. Int -> a -> f a

  -- | `enqueue fifo x` appends `x` to the tail of `fifo`, returning the
  -- | extended `Fifo`. `fifo` itself is left unchanged — anyone still
  -- | holding a reference to it must keep seeing the original,
  -- | unextended contents (this is a pure, persistent operation, not a
  -- | mutation).
  -- |
  -- | Called exactly once per pixel, for every offset with `dy == 0`
  -- | (`current`) and every offset with `dy > 0` (`building`). This is
  -- | the single hottest operation in the whole algorithm: its `O(n)`
  -- | cost on `Data.List.Lazy` — where `n` grows up to the image width
  -- | over the course of a row — is exactly what produced the
  -- | `O(width²)`-per-row, `O(width³)`-per-square-image blowup recorded
  -- | in `docs/benchmarks.md`.
  -- |
  -- | Target complexity: O(1) amortized. An instance that can only
  -- | offer O(n) here reintroduces precisely the bug this class exists
  -- | to fix.
  enqueue :: forall a. f a -> a -> f a

  -- | `dequeue fifo` removes and returns the value at the head of
  -- | `fifo`, together with the remaining `Fifo` — or `Nothing` if
  -- | `fifo` is empty.
  -- |
  -- | Called exactly once per pixel, for every offset being read this
  -- | row (`current` and `matured`). Together with `enqueue`, this
  -- | bounds the per-pixel cost of the whole algorithm.
  -- |
  -- | `Nothing` is a real, expected outcome only when padding runs out
  -- | at the very edge of the image. `Dither.Step` treats any other
  -- | `Nothing` as a violated invariant and crashes loudly rather than
  -- | silently substituting a value — instances must not paper over
  -- | emptiness themselves (e.g. by returning a fabricated zero).
  -- |
  -- | Target complexity: O(1) amortized.
  dequeue :: forall a. f a -> Maybe { head :: a, tail :: f a }

  -- | `replace skip fifo` drops the first `skip` elements from the
  -- | front of `fifo` and appends `skip` zeros to the tail, returning a
  -- | `Fifo` of the SAME LENGTH as the input. `skip` is always small
  -- | (bounded by the kernel's horizontal reach — see
  -- | `Dither.Kernel.skipFor`), but `fifo` itself may be as long as the
  -- | image width by the time this is called.
  -- |
  -- | Called once per row, per offset with a negative `dx`, in
  -- | `Dither.Row.commitBuilding` — this re-aligns a fully-built row's
  -- | worth of error fractions with the next row's pixel positions
  -- | before it's handed off to its `DelayLine` slot.
  -- |
  -- | This is its own method — rather than being left for callers to
  -- | express as "drop, then append a small replicated tail" — because
  -- | that composition is O(n) on a plain singly-linked list even
  -- | though `skip` is small (the append has to walk and rebuild the
  -- | entire dropped-and-kept prefix). An instance backed by a
  -- | structure with cheap concatenation (e.g. a finger tree, where
  -- | append is O(log(min(n1, n2)))) should implement `replace` using
  -- | that capability directly, to actually realize the better
  -- | complexity — not by delegating to `drop` + `<>`.
  -- |
  -- | Target complexity: better than O(n) where the underlying
  -- | structure allows it. O(n) is acceptable only if the instance
  -- | genuinely cannot do better, and should be called out as a known
  -- | limitation in that instance's own documentation.
  replace :: forall a. Ring a => Int -> f a -> f a -- нужен zero для заполнения хвоста

-- | Sanity-check baseline instance: this is the representation the
-- | project used before `class Fifo` existed. `enqueue` and `replace`
-- | are both O(n) here (a plain singly-linked list has no cheap way to
-- | append at the tail) — an instance of `Fifo` using this should
-- | reproduce the `O(N³)` scaling recorded for square images in
-- | `docs/benchmarks.md`, not improve on it. Kept around specifically
-- | to verify that the abstraction itself introduces no regression
-- | relative to the pre-`class Fifo` code, and as a point of comparison
-- | for `Seq Number` below.
instance Fifo LL.List where
  replicate = LL.replicate
  enqueue = LL.snoc
  dequeue = LL.uncons
  replace skip fifo = LL.drop skip fifo <> LL.replicate skip zero

instance Fifo DL.List where
  replicate n x = DL.fromFoldable (Array.replicate n x)
  enqueue = DL.snoc
  dequeue = DL.uncons
  replace skip fifo = DL.drop skip fifo <> replicate skip zero

-- | The actual fix. `Data.Sequence.Seq` is a 2-3 finger tree: `enqueue`
-- | (`snoc`) and `dequeue` (`uncons`) are O(1) amortized on either end,
-- | and — just as importantly for `replace` — `<>` is
-- | O(log(min(n1, n2))), so appending a small tail to a long sequence
-- | is cheap regardless of how long that sequence already is. That
-- | second property is what makes `replace` genuinely sub-linear here,
-- | not just `enqueue`/`dequeue`.
instance Fifo Seq.Seq where
  replicate n x = Seq.fromFoldable (Array.replicate n x)
  enqueue = Seq.snoc
  dequeue fifo = (\(Tuple h t) -> { head: h, tail: t }) <$> Seq.uncons fifo
  replace skip fifo = Seq.drop skip fifo <> Seq.fromFoldable (Array.replicate skip zero)

instance Fifo Array where
  replicate = Array.replicate
  enqueue = Array.snoc
  dequeue = Array.uncons
  replace skip fifo = Array.drop skip fifo <> Array.replicate skip zero
