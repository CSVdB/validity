{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE AllowAmbiguousTypes #-}

-- | Monad properties
--
-- You will need @TypeApplications@ to use these.
module Test.Validity.Monad
    ( monadSpecOnValid
    , monadSpec
    , monadSpecOnArbitrary
    , monadSpecOnGens
    ) where

import Data.Data

import Control.Monad (ap)
import Data.GenValidity
import Test.QuickCheck.Gen (unGen)
import Test.QuickCheck.Random (mkQCGen)

import Test.Hspec
import Test.QuickCheck

import Test.Validity.Functions
import Test.Validity.Utils

returnTypeStr
    :: forall (m :: * -> *).
       (Typeable m)
    => String
returnTypeStr = unwords ["return", "::", "a", "->", nameOf @m, "a"]

bindTypeStr
    :: forall (m :: * -> *).
       (Typeable m)
    => String
bindTypeStr =
    unwords
        [ "(>>=)"
        , "::"
        , nameOf @m
        , "a"
        , "->"
        , "(b"
        , "->"
        , nameOf @m
        , "a)"
        , "->"
        , nameOf @m
        , "b"
        ]

-- | Standard test spec for properties of Monad instances for values generated with GenValid instances
--
-- Example usage:
--
-- > monadSpecOnArbitrary @[]
monadSpecOnValid
    :: forall (f :: * -> *).
       (Eq (f Int), Show (f Int), Monad f, Typeable f, GenValid (f Int))
    => Spec
monadSpecOnValid = monadSpecWithInts @f genValid

-- | Standard test spec for properties of Monad instances for values generated with GenUnchecked instances
--
-- Example usage:
--
-- > monadSpecOnArbitrary @[]
monadSpec
    :: forall (f :: * -> *).
       (Eq (f Int), Show (f Int), Monad f, Typeable f, GenUnchecked (f Int))
    => Spec
monadSpec = monadSpecWithInts @f genUnchecked

-- | Standard test spec for properties of Monad instances for values generated with Arbitrary instances
--
-- Example usage:
--
-- > monadSpecOnArbitrary @[]
monadSpecOnArbitrary
    :: forall (f :: * -> *).
       (Eq (f Int), Show (f Int), Monad f, Typeable f, Arbitrary (f Int))
    => Spec
monadSpecOnArbitrary = monadSpecWithInts @f arbitrary

monadSpecWithInts
    :: forall (f :: * -> *).
       (Eq (f Int), Show (f Int), Monad f, Typeable f)
    => Gen (f Int) -> Spec
monadSpecWithInts gen =
    monadSpecOnGens
        @f
        @Int
        genUnchecked
        "int"
        gen
        (unwords [nameOf @f, "of ints"])
        gen
        (unwords [nameOf @f, "of ints"])
        ((+) <$> genUnchecked)
        "increments"
        (do a <- genUnchecked
            let qcgen = mkQCGen a
            let func = unGen gen qcgen
            pure $ \b -> func b)
        "perturbations using the int"
        (do a <- genUnchecked
            let qcgen = mkQCGen a
            let func = unGen gen qcgen
            pure $ \b -> func (2 * b))
        "perturbations using the double the int"
        (pure <$> ((+) <$> genUnchecked))
        (unwords [nameOf @f, "of additions"])

-- | Standard test spec for properties of Monad instances for values generated by given generators (and names for those generator).
--
-- Example usage:
--
-- > monadSpecOnGens
-- >     @[]
-- >     @Int
-- >     (pure 4)
-- >     "four"
-- >     (genListOf $ pure 5)
-- >     "list of fives"
-- >     (genListOf $ pure 6)
-- >     "list of sixes"
-- >     ((*) <$> genValid)
-- >     "factorisations"
-- >     (pure $ \a -> [a])
-- >     "singletonisation"
-- >     (pure $ \a -> [a])
-- >     "singletonisation"
-- >     (pure $ pure (+ 1))
-- >     "increment in list"
monadSpecOnGens
    :: forall (f :: * -> *) (a :: *) (b :: *) (c :: *).
       ( Show a
       , Eq a
       , Show (f a)
       , Show (f b)
       , Show (f c)
       , Eq (f a)
       , Eq (f b)
       , Eq (f c)
       , Monad f
       , Typeable f
       , Typeable a
       , Typeable b
       , Typeable c
       )
    => Gen a
    -> String
    -> Gen (f a)
    -> String
    -> Gen (f b)
    -> String
    -> Gen (a -> b)
    -> String
    -> Gen (a -> f b)
    -> String
    -> Gen (b -> f c)
    -> String
    -> Gen (f (a -> b))
    -> String
    -> Spec
monadSpecOnGens gena genaname gen genname genb genbname geng gengname genbf genbfname gencf gencfname genfab genfabname =
    parallel $
    describe ("Monad " ++ nameOf @f) $ do
        describe (unwords [returnTypeStr @f, "and", bindTypeStr @f]) $ do
            it
                (unwords
                     [ "satisfy the first Monad law: 'return a >>= k = k a' for"
                     , genDescr @a genaname
                     , "and"
                     , genDescr @(a -> f b) genbfname
                     ]) $
                equivalentOnGens2
                    (\a (Anon k) -> return a >>= k)
                    (\a (Anon k) -> k a)
                    ((,) <$> gena <*> (Anon <$> genbf))
            it
                (unwords
                     [ "satisfy the second Monad law: 'm >>= return = m' for"
                     , genDescr @(f a) genname
                     ]) $
                equivalentOnGen (\m -> m >>= return) (\m -> m) gen
        describe (bindTypeStr @f) $
            it
                (unwords
                     [ "satisfies the third Monad law: 'm >>= (x -> k x >>= h) = (m >>= k) >>= h' for"
                     , genDescr @(f a) genname
                     , genDescr @(a -> f b) genbfname
                     , "and"
                     , genDescr @(b -> f c) gencfname
                     ]) $
            equivalentOnGens3
                (\m (Anon k) (Anon h) -> m >>= (\x -> k x >>= h))
                (\m (Anon k) (Anon h) -> (m >>= k) >>= h)
                ((,,) <$> gen <*> (Anon <$> genbf) <*> (Anon <$> gencf))
        describe (unwords ["relation with Applicative", nameOf @f]) $ do
            it
                (unwords
                     ["satisfies 'pure = return' for", genDescr @(f a) genname]) $
                equivalentOnGen (pure @f) (return @f) gena
            it
                (unwords
                     [ "satisfies '(<*>) = ap' for"
                     , genDescr @(f (a -> b)) $ genfabname
                     , "and"
                     , genDescr @(f a) genname
                     ]) $
                equivalentOnGens2
                    (\(Anon a) b -> a <*> b)
                    (\(Anon a) b -> ap a b)
                    ((,) <$> (Anon <$> genfab) <*> gen)
            it
                (unwords
                     [ "satisfies '(>>) = (*>)' for"
                     , genDescr @(f a) genname
                     , "and"
                     , genDescr @(f b) genbname
                     ]) $
                equivalentOnGens2 (>>) (*>) ((,) <$> gen <*> genb)
        describe (unwords ["relation with Functor", nameOf @f]) $ do
            it
                (unwords
                     [ "satisfies 'fmap f xs = xs >>= return . f' for"
                     , genDescr @(a -> b) gengname
                     , "and"
                     , genDescr @(f a) genname
                     ]) $
                equivalentOnGens2
                    (\(Anon f) xs -> fmap f xs)
                    (\(Anon f) xs -> xs >>= (return . f))
                    ((,) <$> (Anon <$> geng) <*> gen)