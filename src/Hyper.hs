-- | A convinience module which re-exports common basic functionality of `hypertypes`

module Hyper (module X) where

import Hyper.Class.Apply as X (HApply(..), HApplicative, liftH2)
import Hyper.Class.HasPlain as X (HasHPlain(..))
import Hyper.Class.Foldable as X
    ( HFoldable(..), foldMapK, traverseK_, traverseK1_
    )
import Hyper.Class.Functor as X (HFunctor(..), mappedK1)
import Hyper.Class.Nodes as X (HNodes(..), (#>), (#*#))
import Hyper.Class.Pointed as X (HPointed(..))
import Hyper.Class.Traversable as X (HTraversable(..), traverseK, traverseK1)
import Hyper.Type.Combinator.ANode as X
import Hyper.Type as X
import Hyper.Type.Ann as X (Ann(..), ann, annotations)
import Hyper.Type.Pure as X
import Hyper.Class.Recursive as X (Recursively(..), RNodes, RTraversable)
import Hyper.TH.Apply as X (makeHApplicativeBases)
import Hyper.TH.HasPlain as X (makeHasHPlain)
import Hyper.TH.Traversable as X (makeHTraversableApplyAndBases, makeHTraversableAndBases)
import Hyper.TH.ZipMatch as X (makeZipMatch)
import Data.Functor.Product.PolyKinds as X (Product(..))
