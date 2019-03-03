module MinCaml.Beta
  ( f
  ) where

import qualified Data.Map        as Map
import           Data.Maybe      (fromMaybe)

import           MinCaml.Global
import qualified MinCaml.Id      as Id
import qualified MinCaml.KNormal as KNormal

find :: Id.T -> Map.Map Id.T Id.T -> Id.T
find x env = fromMaybe x $ Map.lookup x env

g :: Map.Map Id.T Id.T -> KNormal.T -> KNormal.T
g env KNormal.Unit = KNormal.Unit
g env (KNormal.Int i) = KNormal.Int i
g env (KNormal.Let (x, t) e1 e2) =
  case g env e1 of
    KNormal.Var y -> g (Map.insert x y env) e2
    e1' ->
      let e2' = g env e2
      in KNormal.Let (x, t) e1' e2'
g env (KNormal.Var x) = KNormal.Var $ find x env

f :: KNormal.T -> MinCaml KNormal.T
f e = return $ g Map.empty e
