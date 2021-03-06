module MinCaml.Virtual
  ( f
  ) where

import           Control.Applicative  ((<$>))
import           Control.Monad        (foldM)
import           Control.Monad.Except (throwError)
import qualified Data.Map             as Map

import qualified Data.Set             as Set
import qualified MinCaml.Asm          as Asm
import qualified MinCaml.Closure      as Closure
import           MinCaml.Global
import qualified MinCaml.Id           as Id
import qualified MinCaml.Type         as Type
import qualified MinCaml.Util         as Util

classify ::
     [(Id.T, Type.Type)]
  -> (a, b)
  -> ((a, b) -> Id.T -> MinCaml (a, b))
  -> ((a, b) -> Id.T -> Type.Type -> MinCaml (a, b))
  -> MinCaml (a, b)
classify xts ini addf addi =
  foldM
    (\acc (x, t) ->
       case t of
         Type.Unit -> return acc
         _         -> addi acc x t)
    ini
    xts

separate :: [(Id.T, Type.Type)] -> MinCaml ([Id.T], [Id.T])
separate xts =
  classify
    xts
    ([], [])
    (\(int, float) x -> return (int, float ++ [x]))
    (\(int, float) x _ -> return (int ++ [x], float))

expand ::
     [(Id.T, Type.Type)]
  -> (Int, Asm.T)
  -> (Id.T -> Int -> Asm.T -> MinCaml Asm.T)
  -> (Id.T -> Type.Type -> Int -> Asm.T -> MinCaml Asm.T)
  -> MinCaml (Int, Asm.T)
expand xts ini addf addi =
  classify
    xts
    ini
    (\(offset, acc) x -> do
       let offset' = Asm.align offset
       addf x offset' acc >>= \a -> return (offset' + 8, a))
    (\(offset, acc) x t -> addi x t offset acc >>= \a -> return (offset + 8, a))

gIfHelper ::
     (Id.T -> Asm.IdOrImm -> Asm.T -> Asm.T -> Asm.Exp)
  -> Map.Map Id.T Type.Type
  -> Id.T
  -> Id.T
  -> Closure.T
  -> Closure.T
  -> MinCaml Asm.T
gIfHelper c env x y e1 e2 = do
  e1' <- g env e1
  e2' <- g env e2
  return $ Asm.Ans $ c x (Asm.V y) e1' e2'

g :: Map.Map Id.T Type.Type -> Closure.T -> MinCaml Asm.T
g _ Closure.Unit = return $ Asm.Ans Asm.Nop
g _ (Closure.Int i) = return $ Asm.Ans (Asm.Set i)
g _ (Closure.Neg x) = return $ Asm.Ans (Asm.Neg x)
g _ (Closure.Add x y) = return $ Asm.Ans (Asm.Add x $ Asm.V y)
g _ (Closure.Sub x y) = return $ Asm.Ans (Asm.Sub x $ Asm.V y)
g env (Closure.IfEq x y e1 e2) =
  case Map.lookup x env of
    Just Type.Bool -> gIfHelper Asm.IfEq env x y e1 e2
    Just Type.Int -> gIfHelper Asm.IfEq env x y e1 e2
    _ -> throwError "equality supported only for bool, int, and float"
g env (Closure.IfLe x y e1 e2) =
  case Map.lookup x env of
    Just Type.Bool -> gIfHelper Asm.IfLe env x y e1 e2
    Just Type.Int -> gIfHelper Asm.IfLe env x y e1 e2
    _ -> throwError "equality supported only for bool, int, and float"
g env (Closure.Let (x, t) e1 e2) = do
  e1' <- g env e1
  e2' <- g (Map.insert x t env) e2
  return $ Asm.concat e1' (x, t) e2'
g env (Closure.Var x) =
  return $
  case Map.lookup x env of
    Just Type.Unit -> Asm.Ans Asm.Nop
    _              -> Asm.Ans $ Asm.Mov x
g env (Closure.MakeCls (x, t) (Closure.Closure l ys) e2) = do
  e2' <- g (Map.insert x t env) e2
  (offset, storeFv) <-
    expand
      (fmap (\y -> (y, env Map.! y)) ys)
      (8, e2')
      undefined
      (\y _ offset storeFv -> Asm.seq (Asm.St y x (Asm.C offset) 1, storeFv))
  z <- genId "l"
  cont <- Asm.seq (Asm.St z x (Asm.C 0) 1, storeFv)
  return $
    Asm.Let (x, t) (Asm.Mov Asm.regHp) $
    Asm.Let (Asm.regHp, Type.Int) (Asm.Add Asm.regHp (Asm.C $ Asm.align offset)) $
    Asm.Let (z, Type.Int) (Asm.SetL l) cont
g env (Closure.AppCls x ys) = do
  (int, float) <- separate (fmap (\y -> (y, env Map.! y)) ys)
  return $ Asm.Ans $ Asm.CallCls x int float
g env (Closure.AppDir (Id.L x) ys) = do
  (int, float) <- separate (fmap (\y -> (y, env Map.! y)) ys)
  return $ Asm.Ans $ Asm.CallDir (Id.L x) int float
g env (Closure.Tuple xs) = do
  y <- genId "t"
  (offset, store) <-
    expand
      (fmap (\x -> (x, env Map.! x)) xs)
      (0, Asm.Ans $ Asm.Mov y)
      undefined
      (\x _ offset store -> Asm.seq (Asm.St x y (Asm.C offset) 1, store))
  return $
    Asm.Let (y, Type.Tuple $ fmap (\x -> env Map.! x) xs) (Asm.Mov Asm.regHp) $
    Asm.Let (Asm.regHp, Type.Int) (Asm.Add Asm.regHp $ Asm.C $ Asm.align offset) store
g env (Closure.LetTuple xts y e2) = do
  let s = Closure.fv e2
  e2' <- g (Util.addList xts env) e2
  (offset, load) <-
    expand
      xts
      (0, e2')
      undefined
      (\x t offset load ->
         if not (x `Set.member` s)
           then return load
           else return $ Asm.Let (x, t) (Asm.Ld y (Asm.C offset) 1) load)
  return load
g env (Closure.Get x y) =
  return $
  case Map.lookup x env of
    Just (Type.Array Type.Unit) -> Asm.Ans Asm.Nop
    Just (Type.Array _)         -> Asm.Ans $ Asm.Ld x (Asm.V y) 8
    _                           -> error "Virtual: wrong type (Get)"
g env (Closure.Put x y z) =
  return $
  case Map.lookup x env of
    Just (Type.Array Type.Unit) -> Asm.Ans Asm.Nop
    Just (Type.Array _)         -> Asm.Ans $ Asm.St z x (Asm.V y) 8
    _                           -> error "Virtual: wrong type (Get)"

h :: Closure.Fundef -> MinCaml Asm.Fundef
h (Closure.Fundef (Id.L x, t) yts zts e) = do
  (int, float) <- separate yts
  e' <- g (Map.insert x t $ Util.addList yts $ Util.addList zts Map.empty) e
  (offset, load) <-
    expand zts (8, e') undefined (\z t offset load -> return $ Asm.Let (z, t) (Asm.Ld x (Asm.C offset) 1) load)
  case t of
    Type.Fun _ t2 -> return $ Asm.Fundef (Id.L x) int float load t2
    _             -> throwError "Virtual.h never reached"

f :: Closure.Prog -> MinCaml Asm.Prog
f (Closure.Prog fundefs e) = do
  fundefs' <- mapM h fundefs
  Asm.Prog [] fundefs' <$> g Map.empty e
