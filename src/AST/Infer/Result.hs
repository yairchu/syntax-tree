{-# LANGUAGE NoImplicitPrelude, TemplateHaskell, TypeFamilies, DataKinds #-}
{-# LANGUAGE UndecidableInstances, ScopedTypeVariables, StandaloneDeriving #-}
{-# LANGUAGE FlexibleInstances #-}

module AST.Infer.Result
    ( TypeOf, ScopeOf
    , IResult(..), irType, irScope
    ) where

import AST
import Control.Lens (makeLenses)
import Data.Constraint (Dict(..), withDict)
import Data.Kind (Type)
import Data.Proxy (Proxy(..))

import Prelude.Compat

type family TypeOf (t :: Knot -> Type) :: Knot -> Type
type family ScopeOf (t :: Knot -> Type) :: Knot -> Type

data IResult e v = IResult
    { _irType :: Node v (TypeOf e)
    , _irScope :: ScopeOf e v
    }

instance
    KNodes (ScopeOf e) =>
    KNodes (IResult e) where

    type NodeTypesOf (IResult e) = Product (ANode (TypeOf e)) (NodeTypesOf (ScopeOf e))

    kNodes _ = withDict (kNodes (Proxy :: Proxy (ScopeOf e))) Dict

makeLenses ''IResult
makeKApply ''IResult
makeKTraversableAndBases ''IResult

deriving instance (Show (Tree v (TypeOf e)), Show (Tree (ScopeOf e) v)) => Show (Tree (IResult e) v)