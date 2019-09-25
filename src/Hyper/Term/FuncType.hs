{-# LANGUAGE UndecidableInstances, TemplateHaskell, FlexibleInstances #-}

module Hyper.Term.FuncType
    ( FuncType(..), funcIn, funcOut, KWitness(..)
    , HasFuncType(..)
    ) where

import           Hyper
import           Control.DeepSeq (NFData)
import           Control.Lens (Prism', makeLenses)
import           Control.Lens.Operators
import           Data.Binary (Binary)
import           Generics.Constraints (makeDerivings, makeInstances)
import           GHC.Generics (Generic)
import           Text.PrettyPrint ((<+>))
import qualified Text.PrettyPrint as Pretty
import           Text.PrettyPrint.HughesPJClass (Pretty(..), maybeParens)
import           Text.Show.Combinators ((@|), showCon)

import           Prelude.Compat

-- | A term for the types of functions. Analogues to @(->)@ in Haskell.
--
-- @FuncType typ@s express types of functions of @typ@.
--
-- The data type comes along with the 'HasFuncType' class
-- for code to be able to work for any type AST supporting the types of functions.
data FuncType typ k = FuncType
    { _funcIn  :: k # typ
    , _funcOut :: k # typ
    } deriving Generic

makeLenses ''FuncType
makeZipMatch ''FuncType
makeKTraversableApplyAndBases ''FuncType
makeDerivings [''Eq, ''Ord] [''FuncType]
makeInstances [''Binary, ''NFData] [''FuncType]

instance Pretty (k # typ) => Pretty (FuncType typ k) where
    pPrintPrec lvl p (FuncType i o) =
        pPrintPrec lvl 11 i <+> Pretty.text "->" <+> pPrintPrec lvl 10 o
        & maybeParens (p > 10)

instance Show (k # typ) => Show (FuncType typ k) where
    showsPrec p (FuncType i o) = (showCon "FuncType" @| i @| o) p

-- | HasFuncType is a class of 'AHyperType's representing types that support the types of functions.
--
-- It is used by the 'Hyper.Class.Infer.Infer' instances of 'Hyper.Term.App.App' and 'Hyper.Term.Lam.Lam'
-- to work for any AST which provides 'HasFuncType'.
class HasFuncType typ where
    funcType :: Prism' (Tree typ k) (Tree (FuncType typ) k)
