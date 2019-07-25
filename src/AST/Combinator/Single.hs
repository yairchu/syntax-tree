{-# LANGUAGE NoImplicitPrelude, DerivingStrategies, DeriveGeneric, StandaloneDeriving #-}
{-# LANGUAGE UndecidableInstances, TypeFamilies, TemplateHaskell, DataKinds #-}

module AST.Combinator.Single
    ( Single(..), _Single
    ) where

import AST.Class (HasNodes(..))
import AST.Class.Apply.TH (makeKApplicativeBases)
import AST.Constraint
import AST.Knot (Tree, Node)
import Control.DeepSeq (NFData)
import Control.Lens (Iso, iso)
import Data.Binary (Binary)
import GHC.Generics (Generic)

import Prelude.Compat

newtype Single c k = MkSingle { getSingle :: Node k c }
    deriving stock Generic

{-# INLINE _Single #-}
_Single :: Iso (Tree (Single c0) k0) (Tree (Single c1) k1) (Tree k0 c0) (Tree k1 c1)
_Single = iso getSingle MkSingle

instance HasNodes (Single c) where
    type NodeTypesOf (Single c) = Single c
    type NodesConstraint (Single c) = KnotsConstraint '[c]

makeKApplicativeBases ''Single

deriving instance Eq   (Node k c) => Eq   (Single c k)
deriving instance Ord  (Node k c) => Ord  (Single c k)
deriving instance Show (Node k c) => Show (Single c k)
instance Binary (Node k c) => Binary (Single c k)
instance NFData (Node k c) => NFData (Single c k)
