{- sv2v
 - Author: Zachary Snow <zach@zachjs.com>
 -
 - Conversion for the `type` operator
 -}

module Convert.TypeOf (convert) where

import Data.Tuple (swap)
import qualified Data.Map.Strict as Map

import Convert.Scoper
import Convert.Traverse
import Language.SystemVerilog.AST

convert :: [AST] -> [AST]
convert = map $ traverseDescriptions $ partScoper
    traverseDeclM traverseModuleItemM traverseGenItemM traverseStmtM

traverseDeclM :: Decl -> Scoper Type Decl
traverseDeclM decl = do
    item <- traverseModuleItemM (MIPackageItem $ Decl decl)
    let MIPackageItem (Decl decl') = item
    case decl' of
        Variable d t ident a e -> do
            let t' = injectRanges t a
            insertElem ident t'
            return $ case t' of
                UnpackedType t'' a' -> Variable d t'' ident a' e
                _ ->                   Variable d t'  ident [] e
        Param    _ t ident   _ -> do
            let t' = if t == Implicit Unspecified []
                        then IntegerAtom TInteger Unspecified
                        else t
            insertElem ident t'
            return decl'
        ParamType{} -> return decl'
        CommentDecl{} -> return decl'

traverseModuleItemM :: ModuleItem -> Scoper Type ModuleItem
traverseModuleItemM = traverseTypesM traverseTypeM

traverseGenItemM :: GenItem -> Scoper Type GenItem
traverseGenItemM = traverseGenItemExprsM traverseExprM

traverseStmtM :: Stmt -> Scoper Type Stmt
traverseStmtM = traverseStmtExprsM traverseExprM

traverseExprM :: Expr -> Scoper Type Expr
traverseExprM = traverseNestedExprsM $ traverseExprTypesM traverseTypeM

traverseTypeM :: Type -> Scoper Type Type
traverseTypeM (TypeOf expr) = typeof expr
traverseTypeM other = return other

lookupTypeOf :: Expr -> Scoper Type Type
lookupTypeOf expr = do
    details <- lookupElemM expr
    case details of
        Nothing -> return $ TypeOf expr
        -- functions with no return type implicitly return a single bit
        Just (_, _, Implicit Unspecified []) ->
            return $ IntegerVector TLogic Unspecified []
        Just (_, replacements, typ) ->
            return $ rewriteType typ
            where
                rewriteType = traverseNestedTypes $ traverseTypeExprs $
                    traverseNestedExprs replace
                replace :: Expr -> Expr
                replace (Ident x) =
                    Map.findWithDefault (Ident x) x replacements
                replace other = other

typeof :: Expr -> Scoper Type Type
typeof (Number n) =
    return $ IntegerVector TLogic sg [r]
    where
        r = (RawNum $ size - 1, RawNum 0)
        size = numberBitLength n
        sg = if numberIsSigned n then Signed else Unspecified
typeof (Call (Ident x) _) =
    typeof $ Ident x
typeof (orig @ (Bit e _)) = do
    t <- typeof e
    case t of
        TypeOf _ -> lookupTypeOf orig
        _ -> return $ popRange t
typeof (orig @ (Range e mode r)) = do
    t <- typeof e
    return $ case t of
        TypeOf _ -> TypeOf orig
        _ -> replaceRange (lo, hi) t
    where
        lo = fst r
        hi = case mode of
            NonIndexed   -> snd r
            IndexedPlus  -> BinOp Sub (uncurry (BinOp Add) r) (RawNum 1)
            IndexedMinus -> BinOp Add (uncurry (BinOp Sub) r) (RawNum 1)
typeof (orig @ (Dot e x)) = do
    t <- typeof e
    case t of
        Struct _ fields [] ->
            return $ fieldsType fields
        Union _ fields [] ->
            return $ fieldsType fields
        _ -> lookupTypeOf orig
    where
        fieldsType :: [Field] -> Type
        fieldsType fields =
            case lookup x $ map swap fields of
                Just typ -> typ
                Nothing -> TypeOf orig
typeof (Cast (Right s) _) = return $ typeOfSize s
typeof (UniOp UniSub  e  ) = typeof e
typeof (UniOp BitNot  e  ) = typeof e
typeof (BinOp Pow     e _) = typeof e
typeof (BinOp ShiftL  e _) = typeof e
typeof (BinOp ShiftR  e _) = typeof e
typeof (BinOp ShiftAL e _) = typeof e
typeof (BinOp ShiftAR e _) = typeof e
typeof (BinOp Add     a b) = return $ largerSizeType a b
typeof (BinOp Sub     a b) = return $ largerSizeType a b
typeof (BinOp Mul     a b) = return $ largerSizeType a b
typeof (BinOp Div     a b) = return $ largerSizeType a b
typeof (BinOp Mod     a b) = return $ largerSizeType a b
typeof (BinOp BitAnd  a b) = return $ largerSizeType a b
typeof (BinOp BitXor  a b) = return $ largerSizeType a b
typeof (BinOp BitXnor a b) = return $ largerSizeType a b
typeof (BinOp BitOr   a b) = return $ largerSizeType a b
typeof (Mux   _       a b) = return $ largerSizeType a b
typeof (Concat      exprs) = return $ typeOfSize $ concatSize exprs
typeof (Repeat reps exprs) = return $ typeOfSize size
    where size = BinOp Mul reps (concatSize exprs)
typeof other = lookupTypeOf other

-- produces a type large enough to hold either expression
largerSizeType :: Expr -> Expr -> Type
largerSizeType a b =
    typeOfSize larger
    where
        sizeof = DimsFn FnBits . Right
        cond = BinOp Ge (sizeof a) (sizeof b)
        larger = Mux cond (sizeof a) (sizeof b)

-- returns the total size of concatenated list of expressions
concatSize :: [Expr] -> Expr
concatSize exprs =
    foldl (BinOp Add) (RawNum 0) $
    map sizeof exprs
    where
        sizeof = DimsFn FnBits . Right

-- produces a generic type of the given size
typeOfSize :: Expr -> Type
typeOfSize size =
    IntegerVector TLogic sg [(hi, RawNum 0)]
    where
        sg = Unspecified -- suitable for now
        hi = BinOp Sub size (RawNum 1)

-- combines a type with unpacked ranges
injectRanges :: Type -> [Range] -> Type
injectRanges t [] = t
injectRanges (UnpackedType t rs) unpacked = UnpackedType t $ unpacked ++ rs
injectRanges t unpacked = UnpackedType t unpacked

-- removes the most significant range of the given type
popRange :: Type -> Type
popRange (UnpackedType t [_]) = t
popRange (IntegerAtom TInteger sg) =
    IntegerVector TLogic sg []
popRange t =
    tf rs
    where (tf, _ : rs) = typeRanges t

-- replaces the most significant range of the given type
replaceRange :: Range -> Type -> Type
replaceRange r (UnpackedType t (_ : rs)) =
    UnpackedType t (r : rs)
replaceRange r (IntegerAtom TInteger sg) =
    IntegerVector TLogic sg [r]
replaceRange r t =
    tf (r : rs)
    where (tf, _ : rs) = typeRanges t
