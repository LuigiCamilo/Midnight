module Tablon where
import Tipos
import Lexer (AlexPosn, AlexPosn(AlexPn))
import Control.Monad.RWS
import Data.List (intercalate)
import Data.Foldable
import Data.Maybe (isNothing)
import qualified Data.Map as Map

vacio :: Tablon
vacio = Map.empty

buscar :: String -> Tablon -> [Entry]
buscar s t = lis $ Map.lookup s t
    where
      lis Nothing = []
      lis (Just lista) = lista

clash :: Entry -> Entry -> Bool
clash (Entry _ _ a) (Entry _ _ b) = a == b || b == 0

insertar' :: String -> Entry -> Tablon -> Tablon
insertar' s e t
    | any (clash e) vaina = error $ "(ñame) Redeclaración de \""++s++"\""
    | otherwise = Map.insert s (e : vaina) t
    where vaina = (buscar s t)

insertar :: (String, AlexPosn) -> Entry -> Tablon -> MonadTablon Tablon
insertar (s, pos) e t = do
  let vaina = buscar s t
      AlexPn _ m n = pos
  if any (clash e) vaina then do 
    lift $ putStrLn $ "Redeclaración de \""++s++"\" en la línea "++(show m)++" columna "++(show n)
    return t
  else return $ Map.insert s (e : (buscar s t)) t
        

insertarV :: [String] -> [Entry] -> Tablon -> Tablon
insertarV xs ys t = foldr (uncurry insertar') t (zip xs ys)

insertarV' :: [(String,Entry)] -> Tablon -> Tablon
insertarV' xs t = foldr (uncurry insertar') t xs

type MonadTablon a = RWST () () (Tablon, [Integer], Integer) IO a

initTablon :: (Tablon,[Integer], Integer)
initTablon = (t,[0],0)
    where
        t = insertarV claves valores vacio
        --t = insertarV [] [] vacio
        claves = ["new", "full", "blackhole", "moon", "planet", "cloud", "star", "BlackHole", "cosmos",
                  "Cluster", "Quasar", "Nebula", "~", "Galaxy", "UFO",
                  "read", "print", "push", "pop", "terraform", "vaporize", "astral", "scale", "bigbang"]
        valores = [(Entry (Simple "moon") Literal 0),
                   (Entry (Simple "moon") Literal 0),
                   (Entry (Simple "BlackHole") Literal 0),
                   (Entry (Simple "cosmos") Tipo 0),
                   (Entry (Simple "cosmos") Tipo 0),
                   (Entry (Simple "cosmos") Tipo 0),
                   (Entry (Simple "cosmos") Tipo 0),
                   (Entry (Simple "cosmos") Tipo 0),
                   (Entry (Simple "cosmos") Tipo 0),
                   (Entry NA Constructor 0),
                   (Entry NA Constructor 0),
                   (Entry NA Constructor 0),
                   (Entry NA Constructor 0),
                   (Entry NA Constructor 0),
                   (Entry NA Constructor 0),
                   (Entry (Subroutine "Comet" [IDK] (Composite "Cluster" (Simple "star"))) (Subrutina []) 0),
                   (Entry (Subroutine "Comet" [IDK] (Simple "blackhole") ) (Subrutina []) 0),
                   (Entry (Subroutine "Comet" [IDK] (Simple "blackhole") ) (Subrutina []) 0),
                   (Entry (Subroutine "Comet" [IDK] (Simple "blackhole") ) (Subrutina []) 0),
                   (Entry (Subroutine "Comet" [IDK] (Simple "planet") ) (Subrutina []) 0),
                   (Entry (Subroutine "Comet" [IDK] (Simple "cloud") ) (Subrutina []) 0),
                   (Entry (Subroutine "Comet" [IDK] (Composite "Cluster" (Simple "star")) ) (Subrutina []) 0),
                   (Entry (Subroutine "Comet" [IDK] (Simple "planet") ) (Subrutina []) 0),
                   (Entry (Subroutine "Comet" [IDK] (Composite "~" NA)) (Subrutina []) 0)
                   ]

lookupTablon :: String -> MonadTablon (Maybe Entry)
lookupTablon s = do
    (_, pila, _) <- get
    e <- lookupScope s pila
    return e

lookupScope :: String -> [Integer] -> MonadTablon (Maybe Entry)
lookupScope s pila = do
    (tablonActual, _, _) <- get
    let match n (Entry _ _ m) = n == m
        pervasive entry = match 0 entry
        entries = buscar s tablonActual
        candidatos = [entry | n <- pila, entry <- entries, match n entry]
        e | null entries = Nothing
          | pervasive $ head entries = Just $ head entries
          | null candidatos = Nothing
          | otherwise = Just $ head candidatos
    return e

lookupExists :: (String, AlexPosn) -> MonadTablon (Maybe Entry)
lookupExists (s, pos) = do
    entry <- lookupTablon s
    let AlexPn _ m n = pos
    if isNothing entry then do
      lift $ putStrLn $ "Variable no declarada \""++s++"\" en la línea "++(show m)++" columna "++(show n)
      return Nothing
    else return entry

getTipo :: Maybe Entry -> Type
getTipo Nothing = Err
getTipo (Just (Entry t _ _)) = t

checkNum :: (String, AlexPosn) -> Exp -> Exp -> MonadTablon (Exp, Exp)
checkNum (op, AlexPn _ m n) a@(e1, t1) b@(e2, t2) = do
  if t1 == t2 && elem t1 [Err, Simple "planet", Simple "cloud"] then return (a,b)
  else do
    let cast e = (Funcall (Var "vaporize", NA) [e], Simple "cloud")
    if      (t1, t2) == (Simple "planet", Simple "cloud") then return (cast a, b)
    else if (t2, t1) == (Simple "planet", Simple "cloud") then return (a, cast b)
    else do
      if not $ elem t1 [Err, Simple "planet", Simple "cloud"]
        then lift $ putStrLn ("Error de tipo: El operador " ++ op ++ " solo admite los tipos planet y cloud, se encontró "++(show t1)
                              ++" en la línea "++(show m)++" columna "++(show n))
      else return ()
      if not $ elem t2 [Err, Simple "planet", Simple "cloud"]
        then lift $ putStrLn ("Error de tipo: El operador " ++ op ++ " solo admite los tipos planet y cloud, se encontró "++(show t2)
                              ++" en la línea "++(show m)++" columna "++(show n))
      else return ()
      return ((e1, Err), (e2, Err))

checkSame :: AlexPosn -> Exp -> Exp -> MonadTablon (Exp, Exp)
checkSame (AlexPn _ m n) a@(e1, t1) b@(e2, t2) = do
  let isComp (Composite _ _) = True
      isComp (Record _ _) = True
      isComp (Subroutine _ _ _) = True
      isComp _ = False
  if t1 == t2 || (isComp t1 && t2 == Simple "BlackHole")|| (isComp t2 && t1 == Simple "BlackHole") then return (a,b)
  else do
    if t1 /= Err && t2 /= Err then return ()
    else lift $ putStrLn ("Error de tipo: Los tipos  "++(show t1)++" y "++(show t2)++" no son comparables"
                      ++" en la línea "++(show m)++" columna "++(show n))
    return ((e1, Err), (e2, Err))

checkT :: Type -> (String, AlexPosn) -> Exp -> Exp -> MonadTablon (Exp, Exp)
checkT t (op, AlexPn _ m n) a@(e1, t1) b@(e2, t2) = do
  if t1 == t2 && elem t1 [Err, t] then return (a,b)
  else do
    if t1 /= t || t1 == Err
      then lift $ putStrLn ("Error de tipo: El operador " ++ op ++ " solo admite el tipo "++(show t)++", se encontró "++(show t1)
                              ++" en la línea "++(show m)++" columna "++(show n))
      else return ()
    if t2 /= t || t2 == Err
      then lift $ putStrLn ("Error de tipo: El operador " ++ op ++ " solo admite el tipo "++(show t)++", se encontró "++(show t2)
                              ++" en la línea "++(show m)++" columna "++(show n))
      else return ()
    return ((e1, Err), (e2, Err))

checkInt :: (String, AlexPosn) -> Exp -> Exp -> MonadTablon (Exp, Exp)
checkInt = checkT (Simple "planet")

checkBool :: (String, AlexPosn) -> Exp -> Exp -> MonadTablon (Exp, Exp)
checkBool = checkT (Simple "moon")

checkBool' :: AlexPosn -> Type -> MonadTablon ()
checkBool' (AlexPn _ m n) t = do
  if t /= Err && t /= Simple "moon" 
    then lift $ putStrLn ("Error de tipo: Se esperaba moon, se encontró "++(show t)
                              ++" en la línea "++(show m)++" columna "++(show n))
  else return ()

pushPila :: MonadTablon ()
pushPila = do
    (tablonActual, pila, n) <- get
    let m = n + 1
    put (tablonActual, m:pila, m)

popPila :: MonadTablon ()
popPila = do
    (tablonActual, pila, n) <- get
    put (tablonActual, tail pila, n)

insertarCampos :: [(Type, (String, AlexPosn))] -> MonadTablon ()
insertarCampos xs = do
    (tablonActual, pila@(tope:_), n) <- get
    let tuplas = [ (snd x, (Entry (fst x) Campo tope)) | x <- xs ]
    tab <- foldlM (flip $ uncurry insertar) tablonActual tuplas
    put (tab, pila, n)

insertarVar :: (String, AlexPosn) -> Type -> MonadTablon ()
insertarVar s t = do
    (tablonActual, pila@(tope:_), n) <- get
    tab <- insertar s (Entry t Variable tope) tablonActual
    put (tab, pila, n)

insertarSubrutina :: (Def, AlexPosn) -> MonadTablon ()
insertarSubrutina ((Func s params tret sequ), pos) = do
    (tablonActual, pila@(tope:_), n) <- get
    let tparams = [ t | (t, _, _) <- params ]
        ti = Subroutine "Comet" tparams tret
    tab <- insertar (s, pos) (Entry ti (Subrutina sequ) tope) tablonActual
    put (tab, pila, n)
insertarSubrutina ((Iter s params tret sequ), pos) = do
    (tablonActual, pila@(tope:_), n) <- get
    let tparams = [ t | (t, _, _) <- params ]
        ti = Subroutine "Satellite" tparams tret
    tab <- insertar (s, pos) (Entry ti (Subrutina sequ) tope) tablonActual
    put (tab, pila, n)
insertarSubrutina _ = error "No es una Subrutina"

actualizarSubrutina :: String -> [Instr] -> MonadTablon ()
actualizarSubrutina s sequ = do
    (tablonActual, pila, n) <- get
    let f (Entry _ _ k) = k == 1 
        entries = buscar s tablonActual
        g (l,x:xs) = if f x then (x, l++xs)
                     else g (x:l, xs)
        g (_,_) = error "error raro"
        gg = g ([],entries)
        Entry t _ _ = fst gg
        e = Entry t (Subrutina sequ) 1
        updated = e : (snd gg)
        tab = Map.insert s updated tablonActual
    put (tab, pila, n)


insertarParams :: [(Type, (String, AlexPosn), Bool)] -> MonadTablon ()
insertarParams params = do
    (tablonActual, pila@(tope:_), n) <- get
    let tuplas = [ (s, (Entry t (Parametro b) tope)) | (t, s, b) <- params ]
    tab <- foldlM (flip $ uncurry insertar) tablonActual tuplas
    put (tab, pila, n)

insertarReg :: (String, AlexPosn) -> String -> MonadTablon ()
insertarReg (s, pos) tr = do
    (tablonActual, pila@(tope:_), n) <- get
    tab <- insertar (s, pos) (Entry (Simple "cosmos") (Registro (Record tr s)  (n+1)) tope) tablonActual
    put (tab, pila, n)

showTablon :: Tablon -> String
showTablon t = fst (Map.mapAccumWithKey f "" t) where
  f a k v =  (a ++ '\n' : k ++ '\n' : intercalate "\n" (map (show) v) ++ "\n" , ())

showTablon' :: Tablon -> String
showTablon' t = showTablon $ ñame
  where ñame = Map.filter (not.apio) t
        papa (Entry _ _ 0) = True
        papa _ = False
        apio a = all papa a