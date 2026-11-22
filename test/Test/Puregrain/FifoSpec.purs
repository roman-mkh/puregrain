module Test.Puregrain.FifoSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NEA
import Data.CatQueue (CatQueue)
import Data.Foldable (foldl)
import Data.List as DL
import Data.List.Lazy as LL
import Data.Maybe (isNothing, maybe)
import Data.Tuple (Tuple(..))
import Data.Unfoldable (unfoldr)
import Test.QuickCheck (Result, (===))
import Test.QuickCheck.Gen (Gen, chooseInt, frequency, vectorOf)
import Test.Spec (Spec, describe, it)
import Test.Spec.QuickCheck (quickCheck)
import Type.Proxy (Proxy(..))

import Puregrain.Internal.Fifo (class Fifo, dequeue, enqueue, replace, replicate, reverse)

-- | One operation on a queue.
data Op = Enqueue Int | Dequeue | Replace Int | Reverse

-- | Mostly enqueues, as in a row's work, with the other three mixed in,
-- | so that each happens in every state of a two-list queue (front list
-- | empty or not, back list empty or not).
genOp :: Gen Op
genOp = frequency $ NEA.cons'
  (Tuple 4.0 (Enqueue <$> chooseInt 1 99))
  [ Tuple 2.0 (pure Dequeue)
  , Tuple 1.0 (Replace <$> chooseInt 0 3)
  , Tuple 1.0 (pure Reverse)
  ]

-- | What each operation does to the queue's contents, front first, on a
-- | plain array: the class's contract, written independently.
model :: Op -> Array Int -> Array Int
model op xs = case op of
  Enqueue x -> Array.snoc xs x
  Dequeue -> Array.drop 1 xs
  Replace n -> Array.drop n xs <> Array.replicate n 0
  Reverse -> Array.reverse xs

perform :: forall f. Fifo f => Op -> f Int -> f Int
perform op q = case op of
  Enqueue x -> enqueue q x
  Dequeue -> maybe q _.tail (dequeue q)
  Replace n -> replace n q
  Reverse -> reverse q

-- | Everything in the queue, front first, by dequeueing it.
drain :: forall f. Fifo f => f Int -> Array Int
drain = unfoldr (\q -> (\{ head, tail } -> Tuple head tail) <$> dequeue q)

-- | Any operations, from a queue of 0 to 3 sevens (`replicate`): the
-- | queue's contents follow the model's, and it's empty exactly when the
-- | model's is.
followsTheModel :: forall f. Fifo f => Proxy f -> Gen Result
followsTheModel _ = do
  start <- chooseInt 0 3
  ops <- chooseInt 0 40 >>= \n -> vectorOf n genOp
  let
    queue = foldl (flip perform) (replicate start 7 :: f Int) ops
    expected = foldl (flip model) (Array.replicate start 7) ops
  pure ({ contents: drain queue, empty: isNothing (dequeue queue) } === { contents: expected, empty: Array.null expected })

spec :: Spec Unit
spec = describe "Puregrain.Internal.Fifo" do
  describe "follows a plain array, through any enqueues, dequeues, replaces and reversals" do
    it "CatQueue" do
      quickCheck (followsTheModel (Proxy :: Proxy CatQueue))
    it "List.Lazy" do
      quickCheck (followsTheModel (Proxy :: Proxy LL.List))
    it "List" do
      quickCheck (followsTheModel (Proxy :: Proxy DL.List))
    it "Array" do
      quickCheck (followsTheModel (Proxy :: Proxy Array))
