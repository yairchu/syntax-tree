{-# LANGUAGE TemplateHaskell, MultiParamTypeClasses, TypeFamilies, LambdaCase #-}
{-# LANGUAGE FlexibleInstances, UndecidableInstances, TupleSections, DataKinds #-}
{-# LANGUAGE ScopedTypeVariables, GeneralizedNewtypeDeriving, ConstraintKinds #-}

module LangB where

import           TypeLang

import           AST
import           AST.Class.Infer
import           AST.Class.Infer.Inferred
import           AST.Class.Infer.ScopeLevel
import           AST.Class.Instantiate
import           AST.Term.Apply
import           AST.Term.Lam
import           AST.Term.Let
import           AST.Term.Row
import           AST.Term.Var
import           AST.Unify
import           AST.Unify.Constraints
import           AST.Unify.Generalize
import           AST.Unify.PureBinding
import           AST.Unify.STBinding
import           Control.Applicative
import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Control.Lens.Tuple
import           Control.Monad.Except
import           Control.Monad.RWS
import           Control.Monad.Reader
import           Control.Monad.ST
import           Control.Monad.ST.Class (MonadST(..))
import           Data.Constraint
import           Data.Map (Map)
import           Data.Proxy
import           Text.PrettyPrint ((<+>))
import qualified Text.PrettyPrint as Pretty
import           Text.PrettyPrint.HughesPJClass (Pretty(..), maybeParens)

data LangB k
    = BLit Int
    | BApp (Apply LangB k)
    | BVar (Var Name LangB k)
    | BLam (Lam Name LangB k)
    | BLet (Let Name LangB k)
    | BRecEmpty
    | BRecExtend (RowExtend Name LangB LangB k)
    | BGetField (Tie k LangB) Name

makeChildren ''LangB
instance Recursive Children LangB

type instance TypeOf LangB = Typ
type instance ScopeOf LangB = ScopeTypes

instance Pretty (Tree LangB Pure) where
    pPrintPrec _ _ (BLit i) = pPrint i
    pPrintPrec _ _ BRecEmpty = Pretty.text "{}"
    pPrintPrec lvl p (BRecExtend (RowExtend k v r)) =
        pPrintPrec lvl 20 k <+>
        Pretty.text "=" <+>
        (pPrintPrec lvl 2 v <> Pretty.text ",") <+>
        pPrintPrec lvl 1 r
        & maybeParens (p > 1)
    pPrintPrec lvl p (BApp x) = pPrintPrec lvl p x
    pPrintPrec lvl p (BVar x) = pPrintPrec lvl p x
    pPrintPrec lvl p (BLam x) = pPrintPrec lvl p x
    pPrintPrec lvl p (BLet x) = pPrintPrec lvl p x
    pPrintPrec lvl p (BGetField w k) = pPrintPrec lvl p w <> Pretty.text "." <> pPrint k

instance ScopeLookup Name LangB where
    scopeType _ k (ScopeTypes t) = t ^?! Lens.ix k & instantiate

instance
    ( MonadScopeLevel m
    , LocalScopeType Name (Tree (UVar m) Typ) m
    , LocalScopeType Name (Tree (Generalized Typ) (UVar m)) m
    , Unify m Typ, Unify m Row
    , HasScope m ScopeTypes
    ) =>
    Infer m LangB where

    infer (BApp x) = infer x <&> _2 %~ BApp
    infer (BVar x) = infer x <&> _2 %~ BVar
    infer (BLam x) = infer x <&> _2 %~ BLam
    infer (BLet x) = infer x <&> _2 %~ BLet
    infer (BLit x) = newTerm TInt <&> (, BLit x)
    infer (BRecExtend x) =
        withDict (recursive :: RecursiveDict (Unify m) Typ) $
        do
            (xT, xI) <- inferRowExtend TRec RExtend x
            TRec xT & newTerm <&> (, BRecExtend xI)
    infer BRecEmpty =
        withDict (recursive :: RecursiveDict (Unify m) Typ) $
        newTerm REmpty >>= newTerm . TRec <&> (, BRecEmpty)
    infer (BGetField w k) =
        do
            (rT, wR) <- rowElementInfer RExtend k
            wI <- inferNode w
            _ <- TRec wR & newTerm >>= unify (wI ^. iType)
            pure (rT, BGetField wI k)

instance (c Typ, c Row) => Recursive (InferredChildConstraints (Recursive c)) LangB

-- Monads for inferring `LangB`:

newtype ScopeTypes v = ScopeTypes (Map Name (Generalized Typ v))
    deriving (Semigroup, Monoid)
Lens.makePrisms ''ScopeTypes

-- TODO: `AST.Class.Children.TH.makeChildren` should be able to generate this.
-- (whereas it currently generate empty `ChildrenConstraint`).
-- The problem is that simply referring to the `ChildrenConstraint`s
-- of embedded types can explode in case of mutually recursive types,
-- and this requires some thoughtful solution..
instance Children ScopeTypes where
    type ChildrenConstraint ScopeTypes c = Recursive c Typ
    children p f (ScopeTypes x) = traverse (children p f) x <&> ScopeTypes

newtype PureInferB a =
    PureInferB
    ( RWST (Tree ScopeTypes (Const Int), ScopeLevel) () PureInferState
        (Either (Tree TypeError Pure)) a
    )
    deriving
    ( Functor, Applicative, Monad
    , MonadError (Tree TypeError Pure)
    , MonadReader (Tree ScopeTypes (Const Int), ScopeLevel)
    , MonadState PureInferState
    )

type instance UVar PureInferB = Const Int

instance HasScope PureInferB ScopeTypes where
    getScope = Lens.view Lens._1

instance LocalScopeType Name (Tree (Const Int) Typ) PureInferB where
    localScopeType k v = local (Lens._1 . _ScopeTypes . Lens.at k ?~ monomorphic v)

instance LocalScopeType Name (Tree (Generalized Typ) (Const Int)) PureInferB where
    localScopeType k v = local (Lens._1 . _ScopeTypes . Lens.at k ?~ v)

instance MonadScopeLevel PureInferB where
    localLevel = local (Lens._2 . _ScopeLevel +~ 1)

instance ScopeConstraintsMonad ScopeLevel PureInferB where
    scopeConstraints = Lens.view Lens._2

instance ScopeConstraintsMonad RConstraints PureInferB where
    scopeConstraints = Lens.view Lens._2 <&> RowConstraints mempty

instance Unify PureInferB Typ where
    binding = pureBinding (Lens._1 . tTyp)
    newQuantifiedVariable _ _ = increase (Lens._2 . tTyp . Lens._Wrapped) <&> Name . ('t':) . show
    unifyError e =
        children (Proxy :: Proxy (Recursive (Unify PureInferB))) applyBindings e
        >>= throwError . TypError

instance Unify PureInferB Row where
    binding = pureBinding (Lens._1 . tRow)
    newQuantifiedVariable _ _ = increase (Lens._2 . tRow . Lens._Wrapped) <&> Name . ('r':) . show
    structureMismatch = rStructureMismatch
    unifyError e =
        children (Proxy :: Proxy (Recursive (Unify PureInferB))) applyBindings e
        >>= throwError . RowError

newtype STInferB s a =
    STInferB
    (ReaderT (Tree ScopeTypes (STVar s), ScopeLevel, STInferState s)
        (ExceptT (Tree TypeError Pure) (ST s)) a
    )
    deriving
    ( Functor, Applicative, Monad, MonadST
    , MonadError (Tree TypeError Pure)
    , MonadReader (Tree ScopeTypes (STVar s), ScopeLevel, STInferState s)
    )

type instance UVar (STInferB s) = STVar s

instance HasScope (STInferB s) ScopeTypes where
    getScope = Lens.view Lens._1

instance LocalScopeType Name (Tree (STVar s) Typ) (STInferB s) where
    localScopeType k v = local (Lens._1 . _ScopeTypes . Lens.at k ?~ monomorphic v)

instance LocalScopeType Name (Tree (Generalized Typ) (STVar s)) (STInferB s) where
    localScopeType k v = local (Lens._1 . _ScopeTypes . Lens.at k ?~ v)

instance MonadScopeLevel (STInferB s) where
    localLevel = local (Lens._2 . _ScopeLevel +~ 1)

instance ScopeConstraintsMonad ScopeLevel (STInferB s) where
    scopeConstraints = Lens.view Lens._2

instance ScopeConstraintsMonad RConstraints (STInferB s) where
    scopeConstraints = Lens.view Lens._2 <&> RowConstraints mempty

instance Unify (STInferB s) Typ where
    binding = stBindingState
    newQuantifiedVariable _ _ = newStQuantified (Lens._3 . tTyp) <&> Name . ('t':) . show
    unifyError e =
        children (Proxy :: Proxy (Recursive (Unify (STInferB s)))) applyBindings e
        >>= throwError . TypError

instance Unify (STInferB s) Row where
    binding = stBindingState
    newQuantifiedVariable _ _ = newStQuantified (Lens._3 . tRow) <&> Name . ('r':) . show
    structureMismatch = rStructureMismatch
    unifyError e =
        children (Proxy :: Proxy (Recursive (Unify (STInferB s)))) applyBindings e
        >>= throwError . RowError
