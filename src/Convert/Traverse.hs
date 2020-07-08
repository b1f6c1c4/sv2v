{- sv2v
 - Author: Zachary Snow <zach@zachjs.com>
 -
 - Utilities for traversing AST transformations.
 -}

module Convert.Traverse
( MapperM
, Mapper
, CollectorM
, TFStrategy (..)
, TypeStrategy (..)
, unmonad
, collectify
, traverseDescriptionsM
, traverseDescriptions
, collectDescriptionsM
, traverseModuleItemsM
, traverseModuleItems
, collectModuleItemsM
, traverseStmtsM
, traverseStmts
, collectStmtsM
, traverseStmtsM'
, traverseStmts'
, collectStmtsM'
, traverseStmtLHSsM
, traverseStmtLHSs
, collectStmtLHSsM
, traverseExprsM
, traverseExprs
, collectExprsM
, traverseExprsM'
, traverseExprs'
, collectExprsM'
, traverseStmtExprsM
, traverseStmtExprs
, collectStmtExprsM
, traverseLHSsM
, traverseLHSs
, collectLHSsM
, traverseLHSsM'
, traverseLHSs'
, collectLHSsM'
, traverseDeclsM
, traverseDecls
, collectDeclsM
, traverseDeclsM'
, traverseDecls'
, collectDeclsM'
, traverseNestedTypesM
, traverseNestedTypes
, collectNestedTypesM
, traverseExprTypesM
, traverseExprTypes
, collectExprTypesM
, traverseTypeExprsM
, traverseTypeExprs
, collectTypeExprsM
, traverseGenItemExprsM
, traverseGenItemExprs
, collectGenItemExprsM
, traverseDeclExprsM
, traverseDeclExprs
, collectDeclExprsM
, traverseDeclTypesM
, traverseDeclTypes
, collectDeclTypesM
, traverseTypesM'
, traverseTypes'
, collectTypesM'
, traverseTypesM
, traverseTypes
, collectTypesM
, traverseGenItemsM
, traverseGenItems
, collectGenItemsM
, traverseNestedGenItemsM
, traverseNestedGenItems
, traverseAsgnsM
, traverseAsgns
, collectAsgnsM
, traverseAsgnsM'
, traverseAsgns'
, collectAsgnsM'
, traverseStmtAsgnsM
, traverseStmtAsgns
, collectStmtAsgnsM
, traverseNestedModuleItemsM
, traverseNestedModuleItems
, collectNestedModuleItemsM
, traverseNestedStmts
, collectNestedStmtsM
, traverseNestedExprsM
, traverseNestedExprs
, collectNestedExprsM
, traverseNestedLHSsM
, traverseNestedLHSs
, collectNestedLHSsM
, traverseScopesM
, scopedConversion
, scopedConversionM
, stately
, traverseFilesM
, traverseFiles
, traverseSinglyNestedGenItemsM
, traverseSinglyNestedStmtsM
) where

import Data.Functor.Identity (Identity, runIdentity)
import Control.Monad.State
import Control.Monad.Writer
import Language.SystemVerilog.AST

type MapperM m t = t -> m t
type Mapper t = t -> t
type CollectorM m t = t -> m ()

data TFStrategy
    = IncludeTFs
    | ExcludeTFs
    deriving Eq

data TypeStrategy
    = IncludeParamTypes
    | ExcludeParamTypes
    deriving Eq

unmonad :: (MapperM Identity a -> MapperM Identity b) -> Mapper a -> Mapper b
unmonad traverser mapper = runIdentity . traverser (return . mapper)

collectify :: Monad m => (MapperM m a -> MapperM m b) -> CollectorM m a -> CollectorM m b
collectify traverser collector =
    traverser mapper >=> \_ -> return ()
    where mapper x = collector x >> return x

traverseDescriptionsM :: Monad m => MapperM m Description -> MapperM m AST
traverseDescriptionsM = mapM
traverseDescriptions :: Mapper Description -> Mapper AST
traverseDescriptions = map
collectDescriptionsM :: Monad m => CollectorM m Description -> CollectorM m AST
collectDescriptionsM = collectify traverseDescriptionsM

breakGenerate :: ModuleItem -> [ModuleItem]
breakGenerate (Generate genItems) =
    if all isGenModuleItem genItems
        then map (\(GenModuleItem item) -> item) genItems
        else [Generate genItems]
    where
        isGenModuleItem :: GenItem -> Bool
        isGenModuleItem (GenModuleItem _) = True
        isGenModuleItem _ = False
breakGenerate other = [other]

traverseModuleItemsM :: Monad m => MapperM m ModuleItem -> MapperM m Description
traverseModuleItemsM mapper (Part attrs extern kw lifetime name ports items) = do
    items' <- mapM (traverseNestedModuleItemsM mapper) items
    let items'' = concatMap breakGenerate items'
    return $ Part attrs extern kw lifetime name ports items''
    where
traverseModuleItemsM mapper (PackageItem packageItem) = do
    let item = MIPackageItem packageItem
    item' <- traverseNestedModuleItemsM mapper item
    return $ case item' of
        MIPackageItem packageItem' -> PackageItem packageItem'
        other -> error $ "encountered bad package module item: " ++ show other
traverseModuleItemsM mapper (Package lifetime name packageItems) = do
    let items = map MIPackageItem packageItems
    items' <- mapM (traverseNestedModuleItemsM mapper) items
    let items'' = concatMap breakGenerate items'
    return $ Package lifetime name $ map (\(MIPackageItem item) -> item) items''

traverseModuleItems :: Mapper ModuleItem -> Mapper Description
traverseModuleItems = unmonad traverseModuleItemsM
collectModuleItemsM :: Monad m => CollectorM m ModuleItem -> CollectorM m Description
collectModuleItemsM = collectify traverseModuleItemsM

traverseStmtsM' :: Monad m => TFStrategy -> MapperM m Stmt -> MapperM m ModuleItem
traverseStmtsM' strat mapper = moduleItemMapper
    where
        moduleItemMapper (AlwaysC kw stmt) =
            fullMapper stmt >>= return . AlwaysC kw
        moduleItemMapper (MIPackageItem (Function lifetime ret name decls stmts)) = do
            stmts' <-
                if strat == IncludeTFs
                    then mapM fullMapper stmts
                    else return stmts
            return $ MIPackageItem $ Function lifetime ret name decls stmts'
        moduleItemMapper (MIPackageItem (Task lifetime name decls stmts)) = do
            stmts' <-
                if strat == IncludeTFs
                    then mapM fullMapper stmts
                    else return stmts
            return $ MIPackageItem $ Task lifetime name decls stmts'
        moduleItemMapper (Initial stmt) =
            fullMapper stmt >>= return . Initial
        moduleItemMapper (Final stmt) =
            fullMapper stmt >>= return . Final
        moduleItemMapper other = return $ other
        fullMapper = traverseNestedStmtsM mapper

traverseStmts' :: TFStrategy -> Mapper Stmt -> Mapper ModuleItem
traverseStmts' strat = unmonad $ traverseStmtsM' strat
collectStmtsM' :: Monad m => TFStrategy -> CollectorM m Stmt -> CollectorM m ModuleItem
collectStmtsM' strat = collectify $ traverseStmtsM' strat

traverseStmtsM :: Monad m => MapperM m Stmt -> MapperM m ModuleItem
traverseStmtsM = traverseStmtsM' IncludeTFs
traverseStmts :: Mapper Stmt -> Mapper ModuleItem
traverseStmts = traverseStmts' IncludeTFs
collectStmtsM :: Monad m => CollectorM m Stmt -> CollectorM m ModuleItem
collectStmtsM = collectStmtsM' IncludeTFs

-- private utility for turning a thing which maps over a single lever of
-- statements into one that maps over the nested statements first, then the
-- higher levels up
traverseNestedStmtsM :: Monad m => MapperM m Stmt -> MapperM m Stmt
traverseNestedStmtsM mapper = fullMapper
    where fullMapper = mapper >=> traverseSinglyNestedStmtsM fullMapper

-- variant of the above which only traverses one level down
traverseSinglyNestedStmtsM :: Monad m => MapperM m Stmt -> MapperM m Stmt
traverseSinglyNestedStmtsM fullMapper = cs
    where
        cs (StmtAttr a stmt) = fullMapper stmt >>= return . StmtAttr a
        cs (Block _ "" [] []) = return Null
        cs (Block _ "" [] [stmt]) = fullMapper stmt
        cs (Block Seq name decls stmts) = do
            stmts' <- mapM fullMapper stmts
            return $ Block Seq name decls $ concatMap explode stmts'
            where
                explode :: Stmt -> [Stmt]
                explode (Block Seq "" [] ss) = ss
                explode other = [other]
        cs (Block kw name decls stmts) =
            mapM fullMapper stmts >>= return . Block kw name decls
        cs (Case u kw expr cases) = do
            caseStmts <- mapM fullMapper $ map snd cases
            let cases' = zip (map fst cases) caseStmts
            return $ Case u kw expr cases'
        cs (Asgn op mt lhs expr) = return $ Asgn op mt lhs expr
        cs (For a b c stmt) = fullMapper stmt >>= return . For a b c
        cs (While   e stmt) = fullMapper stmt >>= return . While   e
        cs (RepeatL e stmt) = fullMapper stmt >>= return . RepeatL e
        cs (DoWhile e stmt) = fullMapper stmt >>= return . DoWhile e
        cs (Forever   stmt) = fullMapper stmt >>= return . Forever
        cs (Foreach x vars stmt) = fullMapper stmt >>= return . Foreach x vars
        cs (If NoCheck (Number "1") s _) = fullMapper s
        cs (If NoCheck (Number "0") _ s) = fullMapper s
        cs (If u e s1 s2) = do
            s1' <- fullMapper s1
            s2' <- fullMapper s2
            return $ If u e s1' s2'
        cs (Timing event stmt) = fullMapper stmt >>= return . Timing event
        cs (Return expr) = return $ Return expr
        cs (Subroutine expr exprs) = return $ Subroutine expr exprs
        cs (Trigger blocks x) = return $ Trigger blocks x
        cs (Assertion a) =
            traverseAssertionStmtsM fullMapper a >>= return . Assertion
        cs (Continue) = return Continue
        cs (Break) = return Break
        cs (Null) = return Null
        cs (CommentStmt c) = return $ CommentStmt c

traverseAssertionStmtsM :: Monad m => MapperM m Stmt -> MapperM m Assertion
traverseAssertionStmtsM mapper = assertionMapper
    where
        actionBlockMapper (ActionBlock s1 s2) = do
            s1' <- mapper s1
            s2' <- mapper s2
            return $ ActionBlock s1' s2'
        assertionMapper (Assert e ab) =
            actionBlockMapper ab >>= return . Assert e
        assertionMapper (Assume e ab) =
            actionBlockMapper ab >>= return . Assume e
        assertionMapper (Cover e stmt) =
            mapper stmt >>= return . Cover e

-- Note that this does not include the expressions without the statements of the
-- actions associated with the assertions.
traverseAssertionExprsM :: Monad m => MapperM m Expr -> MapperM m Assertion
traverseAssertionExprsM mapper = assertionMapper
    where
        seqExprMapper (SeqExpr e) =
            mapper e >>= return . SeqExpr
        seqExprMapper (SeqExprAnd        s1 s2) =
            ssMapper   SeqExprAnd        s1 s2
        seqExprMapper (SeqExprOr         s1 s2) =
            ssMapper   SeqExprOr         s1 s2
        seqExprMapper (SeqExprIntersect  s1 s2) =
            ssMapper   SeqExprIntersect  s1 s2
        seqExprMapper (SeqExprWithin     s1 s2) =
            ssMapper   SeqExprWithin     s1 s2
        seqExprMapper (SeqExprThroughout e s) = do
            e' <- mapper e
            s' <- seqExprMapper s
            return $ SeqExprThroughout e' s'
        seqExprMapper (SeqExprDelay ms e s) = do
            ms' <- case ms of
                Nothing -> return Nothing
                Just x -> seqExprMapper x >>= return . Just
            e' <- mapper e
            s' <- seqExprMapper s
            return $ SeqExprDelay ms' e' s'
        seqExprMapper (SeqExprFirstMatch s items) = do
            s' <- seqExprMapper s
            items' <- mapM seqMatchItemMapper items
            return $ SeqExprFirstMatch s' items'
        seqMatchItemMapper (Left (a, b, c)) = do
            c' <- mapper c
            return $ Left (a, b, c')
        seqMatchItemMapper (Right (x, (Args l p))) = do
            l' <- mapM mapper l
            pes <- mapM mapper $ map snd p
            let p' = zip (map fst p) pes
            return $ Right (x, Args l' p')
        ppMapper constructor p1 p2 = do
            p1' <- propExprMapper p1
            p2' <- propExprMapper p2
            return $ constructor p1' p2'
        ssMapper constructor s1 s2 = do
            s1' <- seqExprMapper s1
            s2' <- seqExprMapper s2
            return $ constructor s1' s2'
        spMapper constructor se pe = do
            se' <- seqExprMapper se
            pe' <- propExprMapper pe
            return $ constructor se' pe'
        propExprMapper (PropExpr se) =
            seqExprMapper se >>= return . PropExpr
        propExprMapper (PropExprImpliesO se pe) =
            spMapper PropExprImpliesO se pe
        propExprMapper (PropExprImpliesNO se pe) =
            spMapper PropExprImpliesNO se pe
        propExprMapper (PropExprFollowsO se pe) =
            spMapper PropExprFollowsO se pe
        propExprMapper (PropExprFollowsNO se pe) =
            spMapper PropExprFollowsNO se pe
        propExprMapper (PropExprIff p1 p2) =
            ppMapper PropExprIff p1 p2
        propSpecMapper (PropertySpec ms e pe) = do
            e' <- mapper e
            pe' <- propExprMapper pe
            return $ PropertySpec ms e' pe'
        assertionExprMapper (Left e) =
            propSpecMapper e >>= return . Left
        assertionExprMapper (Right e) =
            mapper e >>= return . Right
        assertionMapper (Assert e ab) = do
            e' <- assertionExprMapper e
            return $ Assert e' ab
        assertionMapper (Assume e ab) = do
            e' <- assertionExprMapper e
            return $ Assume e' ab
        assertionMapper (Cover e stmt) = do
            e' <- assertionExprMapper e
            return $ Cover e' stmt

traverseStmtLHSsM :: Monad m => MapperM m LHS -> MapperM m Stmt
traverseStmtLHSsM mapper = stmtMapper
    where
        fullMapper = mapper
        stmtMapper (Timing (Event sense) stmt) = do
            sense' <- senseMapper sense
            return $ Timing (Event sense') stmt
        stmtMapper (Asgn op (Just (Event sense)) lhs expr) = do
            lhs' <- fullMapper lhs
            sense' <- senseMapper sense
            return $ Asgn op (Just $ Event sense') lhs' expr
        stmtMapper (Asgn op mt lhs expr) =
            fullMapper lhs >>= \lhs' -> return $ Asgn op mt lhs' expr
        stmtMapper (For inits me incrs stmt) = do
            inits' <- mapInits inits
            let (lhss, asgnOps, exprs) = unzip3 incrs
            lhss' <- mapM fullMapper lhss
            let incrs' = zip3 lhss' asgnOps exprs
            return $ For inits' me incrs' stmt
            where
                mapInits (Left decls) = return $ Left decls
                mapInits (Right asgns) = do
                    let (lhss, exprs) = unzip asgns
                    lhss' <- mapM fullMapper lhss
                    return $ Right $ zip lhss' exprs
        stmtMapper (Assertion a) =
            assertionMapper a >>= return . Assertion
        stmtMapper other = return other
        senseMapper (Sense        lhs) = fullMapper lhs >>= return . Sense
        senseMapper (SensePosedge lhs) = fullMapper lhs >>= return . SensePosedge
        senseMapper (SenseNegedge lhs) = fullMapper lhs >>= return . SenseNegedge
        senseMapper (SenseOr    s1 s2) = do
            s1' <- senseMapper s1
            s2' <- senseMapper s2
            return $ SenseOr s1' s2'
        senseMapper (SenseStar       ) = return SenseStar
        assertionExprMapper (Left (PropertySpec (Just sense) me pe)) = do
            sense' <- senseMapper sense
            return $ Left $ PropertySpec (Just sense') me pe
        assertionExprMapper other = return $ other
        assertionMapper (Assert e ab) = do
            e' <- assertionExprMapper e
            return $ Assert e' ab
        assertionMapper (Assume e ab) = do
            e' <- assertionExprMapper e
            return $ Assume e' ab
        assertionMapper (Cover e stmt) = do
            e' <- assertionExprMapper e
            return $ Cover e' stmt

traverseStmtLHSs :: Mapper LHS -> Mapper Stmt
traverseStmtLHSs = unmonad traverseStmtLHSsM
collectStmtLHSsM :: Monad m => CollectorM m LHS -> CollectorM m Stmt
collectStmtLHSsM = collectify traverseStmtLHSsM

traverseNestedExprsM :: Monad m => MapperM m Expr -> MapperM m Expr
traverseNestedExprsM mapper = exprMapper
    where
        exprMapper = mapper >=> em
        (_, _, _, typeMapper, _) = exprMapperHelpers exprMapper
        typeOrExprMapper (Left t) =
            typeMapper t >>= return . Left
        typeOrExprMapper (Right e) =
            exprMapper e >>= return . Right
        exprOrRangeMapper (Left e) =
            exprMapper e >>= return . Left
        exprOrRangeMapper (Right (e1, e2)) = do
            e1' <- exprMapper e1
            e2' <- exprMapper e2
            return $ Right (e1', e2')
        em (String s) = return $ String s
        em (Number s) = return $ Number s
        em (Time   s) = return $ Time   s
        em (Ident  i) = return $ Ident  i
        em (PSIdent x y) = return $ PSIdent x y
        em (CSIdent x ps y) = do
            tes' <- mapM typeOrExprMapper $ map snd ps
            let ps' = zip (map fst ps) tes'
            return $ CSIdent x ps' y
        em (Range e m (e1, e2)) = do
            e' <- exprMapper e
            e1' <- exprMapper e1
            e2' <- exprMapper e2
            return $ Range e' m (e1', e2')
        em (Bit   e1 e2) = do
            e1' <- exprMapper e1
            e2' <- exprMapper e2
            return $ Bit e1' e2'
        em (Repeat     e l) = do
            e' <- exprMapper e
            l' <- mapM exprMapper l
            return $ Repeat e' l'
        em (Concat     l) =
            mapM exprMapper l >>= return . Concat
        em (Stream o e l) = do
            e' <- exprMapper e
            l' <- mapM exprMapper l
            return $ Stream o e' l'
        em (Call  e (Args l p)) = do
            e' <- exprMapper e
            l' <- mapM exprMapper l
            pes <- mapM exprMapper $ map snd p
            let p' = zip (map fst p) pes
            return $ Call e' (Args l' p')
        em (UniOp      o e) =
            exprMapper e >>= return . UniOp o
        em (BinOp      o e1 e2) = do
            e1' <- exprMapper e1
            e2' <- exprMapper e2
            return $ BinOp o e1' e2'
        em (Mux        e1 e2 e3) = do
            e1' <- exprMapper e1
            e2' <- exprMapper e2
            e3' <- exprMapper e3
            return $ Mux e1' e2' e3'
        em (Cast (Left t) e) =
            exprMapper e >>= return . Cast (Left t)
        em (Cast (Right e1) e2) = do
            e1' <- exprMapper e1
            e2' <- exprMapper e2
            return $ Cast (Right e1') e2'
        em (DimsFn f tore) =
            typeOrExprMapper tore >>= return . DimsFn f
        em (DimFn f tore e) = do
            tore' <- typeOrExprMapper tore
            e' <- exprMapper e
            return $ DimFn f tore' e'
        em (Dot e x) =
            exprMapper e >>= \e' -> return $ Dot e' x
        em (Pattern l) = do
            let names = map fst l
            exprs <- mapM exprMapper $ map snd l
            return $ Pattern $ zip names exprs
        em (Inside e l) = do
            e' <- exprMapper e
            l' <- mapM exprOrRangeMapper l
            return $ Inside e' l'
        em (MinTypMax e1 e2 e3) = do
            e1' <- exprMapper e1
            e2' <- exprMapper e2
            e3' <- exprMapper e3
            return $ MinTypMax e1' e2' e3'
        em (Nil) = return Nil

exprMapperHelpers :: Monad m => MapperM m Expr ->
    ( MapperM m Range
    , MapperM m Decl
    , MapperM m LHS
    , MapperM m Type
    , MapperM m GenItem
    )
exprMapperHelpers exprMapper =
    ( rangeMapper
    , declMapper
    , traverseNestedLHSsM lhsMapper
    , typeMapper
    , genItemMapper
    )
    where

    rangeMapper (a, b) = do
        a' <- exprMapper a
        b' <- exprMapper b
        return (a', b')

    typeOrExprMapper (Left t) =
        typeMapper t >>= return . Left
    typeOrExprMapper (Right e) =
        exprMapper e >>= return . Right

    typeMapper' (TypeOf expr) =
        exprMapper expr >>= return . TypeOf
    typeMapper' (CSAlias x pm y rs) = do
        vals' <- mapM typeOrExprMapper $ map snd pm
        let pm' = zip (map fst pm) vals'
        rs' <- mapM rangeMapper rs
        return $ CSAlias x pm' y rs'
    typeMapper' t = do
        let (tf, rs) = typeRanges t
        rs' <- mapM rangeMapper rs
        return $ tf rs'
    typeMapper = traverseNestedTypesM typeMapper'

    maybeTypeMapper Nothing = return Nothing
    maybeTypeMapper (Just t) =
        typeMapper t >>= return . Just

    declMapper (Param s t x e) = do
        t' <- typeMapper t
        e' <- exprMapper e
        return $ Param s t' x e'
    declMapper (ParamType s x mt) = do
        mt' <- maybeTypeMapper mt
        return $ ParamType s x mt'
    declMapper (Variable d t x a e) = do
        t' <- typeMapper t
        a' <- mapM rangeMapper a
        e' <- exprMapper e
        return $ Variable d t' x a' e'
    declMapper (CommentDecl c) =
        return $ CommentDecl c

    lhsMapper (LHSRange l m r) =
        rangeMapper r >>= return . LHSRange l m
    lhsMapper (LHSBit l e) =
        exprMapper e >>= return . LHSBit l
    lhsMapper (LHSStream o e ls) = do
        e' <- exprMapper e
        return $ LHSStream o e' ls
    lhsMapper other = return other

    genItemMapper (GenFor (x1, e1) cc (x2, op2, e2) subItem) = do
        e1' <- exprMapper e1
        e2' <- exprMapper e2
        cc' <- exprMapper cc
        return $ GenFor (x1, e1') cc' (x2, op2, e2') subItem
    genItemMapper (GenIf e i1 i2) = do
        e' <- exprMapper e
        return $ GenIf e' i1 i2
    genItemMapper (GenCase e cases) = do
        e' <- exprMapper e
        caseExprs <- mapM (mapM exprMapper . fst) cases
        let cases' = zip caseExprs (map snd cases)
        return $ GenCase e' cases'
    genItemMapper other = return other

traverseExprsM' :: Monad m => TFStrategy -> MapperM m Expr -> MapperM m ModuleItem
traverseExprsM' strat exprMapper = moduleItemMapper
    where

    (rangeMapper, declMapper, lhsMapper, typeMapper, genItemMapper)
        = exprMapperHelpers exprMapper

    stmtMapper = traverseNestedStmtsM (traverseStmtExprsM exprMapper)

    portBindingMapper (p, e) =
        exprMapper e >>= \e' -> return (p, e')

    paramBindingMapper (p, Left t) =
        typeMapper t >>= \t' -> return (p, Left t')
    paramBindingMapper (p, Right e) =
        exprMapper e >>= \e' -> return (p, Right e')

    moduleItemMapper (MIAttr attr mi) =
        -- note: we exclude expressions in attributes from conversion
        return $ MIAttr attr mi
    moduleItemMapper (MIPackageItem (Typedef t x)) = do
        t' <- typeMapper t
        return $ MIPackageItem $ Typedef t' x
    moduleItemMapper (MIPackageItem (Decl decl)) =
        declMapper decl >>= return . MIPackageItem . Decl
    moduleItemMapper (Defparam lhs expr) = do
        lhs' <- lhsMapper lhs
        expr' <- exprMapper expr
        return $ Defparam lhs' expr'
    moduleItemMapper (AlwaysC kw stmt) =
        stmtMapper stmt >>= return . AlwaysC kw
    moduleItemMapper (Initial stmt) =
        stmtMapper stmt >>= return . Initial
    moduleItemMapper (Final stmt) =
        stmtMapper stmt >>= return . Final
    moduleItemMapper (Assign opt lhs expr) = do
        opt' <- case opt of
            AssignOptionNone -> return $ AssignOptionNone
            AssignOptionDrive ds -> return $ AssignOptionDrive ds
            AssignOptionDelay delay ->
                exprMapper delay >>= return . AssignOptionDelay
        lhs' <- lhsMapper lhs
        expr' <- exprMapper expr
        return $ Assign opt' lhs' expr'
    moduleItemMapper (MIPackageItem (Function lifetime ret f decls stmts)) = do
        ret' <- typeMapper ret
        decls' <-
            if strat == IncludeTFs
                then mapM declMapper decls
                else return decls
        stmts' <-
            if strat == IncludeTFs
                then mapM stmtMapper stmts
                else return stmts
        return $ MIPackageItem $ Function lifetime ret' f decls' stmts'
    moduleItemMapper (MIPackageItem (Task lifetime f decls stmts)) = do
        decls' <-
            if strat == IncludeTFs
                then mapM declMapper decls
                else return decls
        stmts' <-
            if strat == IncludeTFs
                then mapM stmtMapper stmts
                else return stmts
        return $ MIPackageItem $ Task lifetime f decls' stmts'
    moduleItemMapper (Instance m p x rs l) = do
        p' <- mapM paramBindingMapper p
        l' <- mapM portBindingMapper l
        rs' <- mapM rangeMapper rs
        return $ Instance m p' x rs' l'
    moduleItemMapper (Modport x l) =
        mapM modportDeclMapper l >>= return . Modport x
    moduleItemMapper (NInputGate  kw d x lhs exprs) = do
        d' <- exprMapper d
        exprs' <- mapM exprMapper exprs
        lhs' <- lhsMapper lhs
        return $ NInputGate kw d' x lhs' exprs'
    moduleItemMapper (NOutputGate kw d x lhss expr) = do
        d' <- exprMapper d
        lhss' <- mapM lhsMapper lhss
        expr' <- exprMapper expr
        return $ NOutputGate kw d' x lhss' expr'
    moduleItemMapper (Genvar   x) = return $ Genvar   x
    moduleItemMapper (Generate items) = do
        items' <- mapM (traverseNestedGenItemsM genItemMapper) items
        return $ Generate items'
    moduleItemMapper (MIPackageItem (Directive c)) =
        return $ MIPackageItem $ Directive c
    moduleItemMapper (MIPackageItem (Import x y)) =
        return $ MIPackageItem $ Import x y
    moduleItemMapper (MIPackageItem (Export x)) =
        return $ MIPackageItem $ Export x
    moduleItemMapper (AssertionItem (mx, a)) = do
        a' <- traverseAssertionStmtsM stmtMapper a
        a'' <- traverseAssertionExprsM exprMapper a'
        return $ AssertionItem (mx, a'')

    modportDeclMapper (dir, ident, t, e) = do
        t' <- typeMapper t
        e' <- exprMapper e
        return (dir, ident, t', e')

traverseExprs' :: TFStrategy -> Mapper Expr -> Mapper ModuleItem
traverseExprs' strat = unmonad $ traverseExprsM' strat
collectExprsM' :: Monad m => TFStrategy -> CollectorM m Expr -> CollectorM m ModuleItem
collectExprsM' strat = collectify $ traverseExprsM' strat

traverseExprsM :: Monad m => MapperM m Expr -> MapperM m ModuleItem
traverseExprsM = traverseExprsM' IncludeTFs
traverseExprs :: Mapper Expr -> Mapper ModuleItem
traverseExprs = traverseExprs' IncludeTFs
collectExprsM :: Monad m => CollectorM m Expr -> CollectorM m ModuleItem
collectExprsM = collectExprsM' IncludeTFs

traverseStmtExprsM :: Monad m => MapperM m Expr -> MapperM m Stmt
traverseStmtExprsM exprMapper = flatStmtMapper
    where

    (_, declMapper, lhsMapper, _, _) = exprMapperHelpers exprMapper

    caseMapper (exprs, stmt) = do
        exprs' <- mapM exprMapper exprs
        return (exprs', stmt)
    stmtMapper = traverseNestedStmtsM flatStmtMapper
    flatStmtMapper (StmtAttr attr stmt) =
        -- note: we exclude expressions in attributes from conversion
        return $ StmtAttr attr stmt
    flatStmtMapper (Block kw name decls stmts) = do
        decls' <- mapM declMapper decls
        return $ Block kw name decls' stmts
    flatStmtMapper (Case u kw e cases) = do
        e' <- exprMapper e
        cases' <- mapM caseMapper cases
        return $ Case u kw e' cases'
    flatStmtMapper (Asgn op mt lhs expr) = do
        lhs' <- lhsMapper lhs
        expr' <- exprMapper expr
        return $ Asgn op mt lhs' expr'
    flatStmtMapper (For inits cc asgns stmt) = do
        inits' <- initsMapper inits
        cc' <- exprMapper cc
        asgns' <- mapM asgnMapper asgns
        return $ For inits' cc' asgns' stmt
    flatStmtMapper (While   e stmt) =
        exprMapper e >>= \e' -> return $ While   e' stmt
    flatStmtMapper (RepeatL e stmt) =
        exprMapper e >>= \e' -> return $ RepeatL e' stmt
    flatStmtMapper (DoWhile e stmt) =
        exprMapper e >>= \e' -> return $ DoWhile e' stmt
    flatStmtMapper (Forever   stmt) = return $ Forever stmt
    flatStmtMapper (Foreach x vars stmt) = return $ Foreach x vars stmt
    flatStmtMapper (If u cc s1 s2) =
        exprMapper cc >>= \cc' -> return $ If u cc' s1 s2
    flatStmtMapper (Timing event stmt) = return $ Timing event stmt
    flatStmtMapper (Subroutine e (Args l p)) = do
        e' <- exprMapper e
        l' <- mapM exprMapper l
        pes <- mapM exprMapper $ map snd p
        let p' = zip (map fst p) pes
        return $ Subroutine e' (Args l' p')
    flatStmtMapper (Return expr) =
        exprMapper expr >>= return . Return
    flatStmtMapper (Trigger blocks x) = return $ Trigger blocks x
    flatStmtMapper (Assertion a) = do
        a' <- traverseAssertionStmtsM stmtMapper a
        a'' <- traverseAssertionExprsM exprMapper a'
        return $ Assertion a''
    flatStmtMapper (Continue) = return Continue
    flatStmtMapper (Break) = return Break
    flatStmtMapper (Null) = return Null
    flatStmtMapper (CommentStmt c) = return $ CommentStmt c

    initsMapper (Left decls) = mapM declMapper decls >>= return . Left
    initsMapper (Right asgns) = mapM mapper asgns >>= return . Right
        where mapper (l, e) = exprMapper e >>= return . (,) l

    asgnMapper (l, op, e) = exprMapper e >>= \e' -> return $ (l, op, e')

traverseStmtExprs :: Mapper Expr -> Mapper Stmt
traverseStmtExprs = unmonad traverseStmtExprsM
collectStmtExprsM :: Monad m => CollectorM m Expr -> CollectorM m Stmt
collectStmtExprsM = collectify traverseStmtExprsM

traverseLHSsM' :: Monad m => TFStrategy -> MapperM m LHS -> MapperM m ModuleItem
traverseLHSsM' strat mapper =
    traverseStmtsM' strat (traverseStmtLHSsM mapper) >=> traverseModuleItemLHSsM
    where
        traverseModuleItemLHSsM (Assign delay lhs expr) = do
            lhs' <- mapper lhs
            return $ Assign delay lhs' expr
        traverseModuleItemLHSsM (Defparam lhs expr) = do
            lhs' <- mapper lhs
            return $ Defparam lhs' expr
        traverseModuleItemLHSsM (NOutputGate kw d x lhss expr) = do
            lhss' <- mapM mapper lhss
            return $ NOutputGate kw d x lhss' expr
        traverseModuleItemLHSsM (NInputGate  kw d x lhs exprs) = do
            lhs' <- mapper lhs
            return $ NInputGate kw d x lhs' exprs
        traverseModuleItemLHSsM (AssertionItem (mx, a)) = do
            converted <-
                traverseNestedStmtsM (traverseStmtLHSsM mapper) (Assertion a)
            return $ case converted of
                Assertion a' -> AssertionItem (mx, a')
                _ -> error $ "redirected AssertionItem traverse failed: "
                        ++ show converted
        traverseModuleItemLHSsM (Generate items) = do
            items' <- mapM (traverseNestedGenItemsM traverGenItemLHSsM) items
            return $ Generate items'
        traverseModuleItemLHSsM other = return other
        traverGenItemLHSsM (GenFor (x1, e1) cc (x2, op2, e2) subItem) = do
            wrapped_x1' <- mapper $ LHSIdent x1
            wrapped_x2' <- mapper $ LHSIdent x2
            let LHSIdent x1' = wrapped_x1'
            let LHSIdent x2' = wrapped_x2'
            return $ GenFor (x1', e1) cc (x2', op2, e2) subItem
        traverGenItemLHSsM other = return other

traverseLHSs' :: TFStrategy -> Mapper LHS -> Mapper ModuleItem
traverseLHSs' strat = unmonad $ traverseLHSsM' strat
collectLHSsM' :: Monad m => TFStrategy -> CollectorM m LHS -> CollectorM m ModuleItem
collectLHSsM' strat = collectify $ traverseLHSsM' strat

traverseLHSsM :: Monad m => MapperM m LHS -> MapperM m ModuleItem
traverseLHSsM = traverseLHSsM' IncludeTFs
traverseLHSs :: Mapper LHS -> Mapper ModuleItem
traverseLHSs = traverseLHSs' IncludeTFs
collectLHSsM :: Monad m => CollectorM m LHS -> CollectorM m ModuleItem
collectLHSsM = collectLHSsM' IncludeTFs

traverseNestedLHSsM :: Monad m => MapperM m LHS -> MapperM m LHS
traverseNestedLHSsM mapper = fullMapper
    where
        fullMapper = mapper >=> tl
        tl (LHSIdent  x       ) = return $ LHSIdent x
        tl (LHSBit    l e     ) = fullMapper l >>= \l' -> return $ LHSBit    l' e
        tl (LHSRange  l m r   ) = fullMapper l >>= \l' -> return $ LHSRange  l' m r
        tl (LHSDot    l x     ) = fullMapper l >>= \l' -> return $ LHSDot    l' x
        tl (LHSConcat     lhss) = mapM fullMapper lhss >>= return . LHSConcat
        tl (LHSStream o e lhss) = mapM fullMapper lhss >>= return . LHSStream o e

traverseNestedLHSs :: Mapper LHS -> Mapper LHS
traverseNestedLHSs = unmonad traverseNestedLHSsM
collectNestedLHSsM :: Monad m => CollectorM m LHS -> CollectorM m LHS
collectNestedLHSsM = collectify traverseNestedLHSsM

traverseDeclsM' :: Monad m => TFStrategy -> MapperM m Decl -> MapperM m ModuleItem
traverseDeclsM' strat mapper item = do
    item' <- miMapper item
    traverseStmtsM' strat stmtMapper item'
    where
        miMapper (MIPackageItem (Decl decl)) =
            mapper decl >>= return . MIPackageItem . Decl
        miMapper (MIPackageItem (Function l t x decls stmts)) = do
            decls' <-
                if strat == IncludeTFs
                    then mapM mapper decls
                    else return decls
            return $ MIPackageItem $ Function l t x decls' stmts
        miMapper (MIPackageItem (Task l x decls stmts)) = do
            decls' <-
                if strat == IncludeTFs
                    then mapM mapper decls
                    else return decls
            return $ MIPackageItem $ Task l x decls' stmts
        miMapper other = return other
        stmtMapper (Block kw name decls stmts) = do
            decls' <- mapM mapper decls
            return $ Block kw name decls' stmts
        stmtMapper other = return other

traverseDecls' :: TFStrategy -> Mapper Decl -> Mapper ModuleItem
traverseDecls' strat = unmonad $ traverseDeclsM' strat
collectDeclsM' :: Monad m => TFStrategy -> CollectorM m Decl -> CollectorM m ModuleItem
collectDeclsM' strat = collectify $ traverseDeclsM' strat

traverseDeclsM :: Monad m => MapperM m Decl -> MapperM m ModuleItem
traverseDeclsM = traverseDeclsM' IncludeTFs
traverseDecls :: Mapper Decl -> Mapper ModuleItem
traverseDecls = traverseDecls' IncludeTFs
collectDeclsM :: Monad m => CollectorM m Decl -> CollectorM m ModuleItem
collectDeclsM = collectDeclsM' IncludeTFs

traverseNestedTypesM :: Monad m => MapperM m Type -> MapperM m Type
traverseNestedTypesM mapper = fullMapper
    where
        fullMapper = mapper >=> tm
        tm (CSAlias ps pm xx    rs) = return $ CSAlias ps pm xx    rs
        tm (Net           kw sg rs) = return $ Net           kw sg rs
        tm (Implicit         sg rs) = return $ Implicit         sg rs
        tm (IntegerVector kw sg rs) = return $ IntegerVector kw sg rs
        tm (IntegerAtom   kw sg   ) = return $ IntegerAtom   kw sg
        tm (NonInteger    kw      ) = return $ NonInteger    kw
        tm (TypeOf        expr    ) = return $ TypeOf        expr
        tm (InterfaceT x my r) = return $ InterfaceT x my r
        tm (Enum t vals r) = do
            t' <- fullMapper t
            return $ Enum t' vals r
        tm (Struct p fields r) = do
            types <- mapM fullMapper $ map fst fields
            let idents = map snd fields
            return $ Struct p (zip types idents) r
        tm (Union p fields r) = do
            types <- mapM fullMapper $ map fst fields
            let idents = map snd fields
            return $ Union p (zip types idents) r
        tm (UnpackedType t r) = do
            t' <- fullMapper t
            return $ UnpackedType t' r

traverseNestedTypes :: Mapper Type -> Mapper Type
traverseNestedTypes = unmonad traverseNestedTypesM
collectNestedTypesM :: Monad m => CollectorM m Type -> CollectorM m Type
collectNestedTypesM = collectify traverseNestedTypesM

traverseExprTypesM :: Monad m => MapperM m Type -> MapperM m Expr
traverseExprTypesM mapper = exprMapper
    where
        typeOrExprMapper (Right e) = return $ Right e
        typeOrExprMapper (Left t) =
            mapper t >>= return . Left
        exprMapper (Cast (Left t) e) =
            mapper t >>= \t' -> return $ Cast (Left t') e
        exprMapper (DimsFn f tore) =
            typeOrExprMapper tore >>= return . DimsFn f
        exprMapper (DimFn f tore e) = do
            tore' <- typeOrExprMapper tore
            return $ DimFn f tore' e
        exprMapper other = return other

traverseExprTypes :: Mapper Type -> Mapper Expr
traverseExprTypes = unmonad traverseExprTypesM
collectExprTypesM :: Monad m => CollectorM m Type -> CollectorM m Expr
collectExprTypesM = collectify traverseExprTypesM

traverseTypeExprsM :: Monad m => MapperM m Expr -> MapperM m Type
traverseTypeExprsM mapper =
    typeMapper
    where (_, _, _, typeMapper, _) = exprMapperHelpers mapper

traverseTypeExprs :: Mapper Expr -> Mapper Type
traverseTypeExprs = unmonad traverseTypeExprsM
collectTypeExprsM :: Monad m => CollectorM m Expr -> CollectorM m Type
collectTypeExprsM = collectify traverseTypeExprsM

traverseGenItemExprsM :: Monad m => MapperM m Expr -> MapperM m GenItem
traverseGenItemExprsM mapper =
    genItemMapper
    where (_, _, _, _, genItemMapper) = exprMapperHelpers mapper

traverseGenItemExprs :: Mapper Expr -> Mapper GenItem
traverseGenItemExprs = unmonad traverseGenItemExprsM
collectGenItemExprsM :: Monad m => CollectorM m Expr -> CollectorM m GenItem
collectGenItemExprsM = collectify traverseGenItemExprsM

traverseDeclExprsM :: Monad m => MapperM m Expr -> MapperM m Decl
traverseDeclExprsM mapper =
    declMapper
    where (_, declMapper, _, _, _) = exprMapperHelpers mapper

traverseDeclExprs :: Mapper Expr -> Mapper Decl
traverseDeclExprs = unmonad traverseDeclExprsM
collectDeclExprsM :: Monad m => CollectorM m Expr -> CollectorM m Decl
collectDeclExprsM = collectify traverseDeclExprsM

traverseDeclTypesM :: Monad m => MapperM m Type -> MapperM m Decl
traverseDeclTypesM mapper (Param s t x e) =
    mapper t >>= \t' -> return $ Param s t' x e
traverseDeclTypesM mapper (ParamType s x mt) =
    mapM mapper mt >>= \mt' -> return $ ParamType s x mt'
traverseDeclTypesM mapper (Variable d t x a e) =
    mapper t >>= \t' -> return $ Variable d t' x a e
traverseDeclTypesM _ (CommentDecl c) = return $ CommentDecl c

traverseDeclTypes :: Mapper Type -> Mapper Decl
traverseDeclTypes = unmonad traverseDeclTypesM
collectDeclTypesM :: Monad m => CollectorM m Type -> CollectorM m Decl
collectDeclTypesM = collectify traverseDeclTypesM

traverseTypesM' :: Monad m => TypeStrategy -> MapperM m Type -> MapperM m ModuleItem
traverseTypesM' strategy mapper =
    miMapper >=>
    traverseDeclsM declMapper >=>
    traverseExprsM (traverseNestedExprsM exprMapper)
    where
        fullMapper = traverseNestedTypesM mapper
        exprMapper = traverseExprTypesM fullMapper
        declMapper = traverseDeclTypesM fullMapper
        miMapper (MIPackageItem (Typedef t x)) =
            fullMapper t >>= \t' -> return $ MIPackageItem $ Typedef t' x
        miMapper (MIPackageItem (Function l t x d s)) =
            fullMapper t >>= \t' -> return $ MIPackageItem $ Function l t' x d s
        miMapper (MIPackageItem (other @ (Task _ _ _ _))) =
            return $ MIPackageItem other
        miMapper (Instance m params x rs p) = do
            params' <- mapM mapParam params
            return $ Instance m params' x rs p
            where
                mapParam (i, Left t) =
                    if strategy == IncludeParamTypes
                        then fullMapper t >>= \t' -> return (i, Left t')
                        else return (i, Left t)
                mapParam (i, Right e) = return $ (i, Right e)
        miMapper (Modport name decls) =
            mapM mapModportDecl decls >>= return . Modport name
            where
                mapModportDecl (d, x, t, e) =
                    fullMapper t >>= \t' -> return (d, x, t', e)
        miMapper other = return other

traverseTypes' :: TypeStrategy -> Mapper Type -> Mapper ModuleItem
traverseTypes' strategy = unmonad $ traverseTypesM' strategy
collectTypesM' :: Monad m => TypeStrategy -> CollectorM m Type -> CollectorM m ModuleItem
collectTypesM' strategy = collectify $ traverseTypesM' strategy

traverseTypesM :: Monad m => MapperM m Type -> MapperM m ModuleItem
traverseTypesM = traverseTypesM' IncludeParamTypes
traverseTypes :: Mapper Type -> Mapper ModuleItem
traverseTypes = traverseTypes' IncludeParamTypes
collectTypesM :: Monad m => CollectorM m Type -> CollectorM m ModuleItem
collectTypesM = collectTypesM' IncludeParamTypes

traverseGenItemsM :: Monad m => MapperM m GenItem -> MapperM m ModuleItem
traverseGenItemsM mapper = moduleItemMapper
    where
        fullMapper = traverseNestedGenItemsM mapper
        moduleItemMapper (Generate genItems) =
            mapM fullMapper genItems >>= return . Generate
        moduleItemMapper other = return other

traverseGenItems :: Mapper GenItem -> Mapper ModuleItem
traverseGenItems = unmonad traverseGenItemsM
collectGenItemsM :: Monad m => CollectorM m GenItem -> CollectorM m ModuleItem
collectGenItemsM = collectify traverseGenItemsM

-- traverses all GenItems within a given GenItem, but doesn't inspect within
-- GenModuleItems
traverseNestedGenItemsM :: Monad m => MapperM m GenItem -> MapperM m GenItem
traverseNestedGenItemsM mapper = fullMapper
    where fullMapper = mapper >=> traverseSinglyNestedGenItemsM fullMapper

traverseNestedGenItems :: Mapper GenItem -> Mapper GenItem
traverseNestedGenItems = unmonad traverseNestedGenItemsM

flattenGenBlocks :: GenItem -> [GenItem]
flattenGenBlocks (GenBlock "" items) = items
flattenGenBlocks (GenFor _ _ _ GenNull) = []
flattenGenBlocks GenNull = []
flattenGenBlocks other = [other]

traverseSinglyNestedGenItemsM :: Monad m => MapperM m GenItem -> MapperM m GenItem
traverseSinglyNestedGenItemsM fullMapper = gim
    where
        gim (GenBlock x subItems) = do
            subItems' <- mapM fullMapper subItems
            return $ GenBlock x (concatMap flattenGenBlocks subItems')
        gim (GenFor a b c subItem) = do
            subItem' <- fullMapper subItem
            return $ GenFor a b c subItem'
        gim (GenIf e i1 i2) = do
            i1' <- fullMapper i1
            i2' <- fullMapper i2
            return $ GenIf e i1' i2'
        gim (GenCase e cases) = do
            caseItems <- mapM (fullMapper . snd) cases
            let cases' = zip (map fst cases) caseItems
            return $ GenCase e cases'
        gim (GenModuleItem moduleItem) =
            return $ GenModuleItem moduleItem
        gim (GenNull) = return GenNull

traverseAsgnsM' :: Monad m => TFStrategy -> MapperM m (LHS, Expr) -> MapperM m ModuleItem
traverseAsgnsM' strat mapper = moduleItemMapper
    where
        moduleItemMapper = miMapperA >=> miMapperB

        miMapperA (Assign delay lhs expr) = do
            (lhs', expr') <- mapper (lhs, expr)
            return $ Assign delay lhs' expr'
        miMapperA (Defparam lhs expr) = do
            (lhs', expr') <- mapper (lhs, expr)
            return $ Defparam lhs' expr'
        miMapperA other = return other

        miMapperB = traverseStmtsM' strat stmtMapper
        stmtMapper = traverseStmtAsgnsM mapper

traverseAsgns' :: TFStrategy -> Mapper (LHS, Expr) -> Mapper ModuleItem
traverseAsgns' strat = unmonad $ traverseAsgnsM' strat
collectAsgnsM' :: Monad m => TFStrategy -> CollectorM m (LHS, Expr) -> CollectorM m ModuleItem
collectAsgnsM' strat = collectify $ traverseAsgnsM' strat

traverseAsgnsM :: Monad m => MapperM m (LHS, Expr) -> MapperM m ModuleItem
traverseAsgnsM = traverseAsgnsM' IncludeTFs
traverseAsgns :: Mapper (LHS, Expr) -> Mapper ModuleItem
traverseAsgns = traverseAsgns' IncludeTFs
collectAsgnsM :: Monad m => CollectorM m (LHS, Expr) -> CollectorM m ModuleItem
collectAsgnsM = collectAsgnsM' IncludeTFs

traverseStmtAsgnsM :: Monad m => MapperM m (LHS, Expr) -> MapperM m Stmt
traverseStmtAsgnsM mapper = stmtMapper
    where
        stmtMapper (Asgn op mt lhs expr) = do
            (lhs', expr') <- mapper (lhs, expr)
            return $ Asgn op mt lhs' expr'
        stmtMapper other = return other

traverseStmtAsgns :: Mapper (LHS, Expr) -> Mapper Stmt
traverseStmtAsgns = unmonad traverseStmtAsgnsM
collectStmtAsgnsM :: Monad m => CollectorM m (LHS, Expr) -> CollectorM m Stmt
collectStmtAsgnsM = collectify traverseStmtAsgnsM

traverseNestedModuleItemsM :: Monad m => MapperM m ModuleItem -> MapperM m ModuleItem
traverseNestedModuleItemsM mapper = fullMapper
    where
        fullMapper (Generate genItems) = do
            let genItems' = concatMap flattenGenBlocks genItems
            mapM fullGenItemMapper genItems' >>= mapper . Generate
        fullMapper (MIAttr attr mi) =
            fullMapper mi >>= mapper . MIAttr attr
        fullMapper (Initial Null) = return $ Generate []
        fullMapper other = mapper other
        fullGenItemMapper = traverseNestedGenItemsM genItemMapper
        genItemMapper (GenModuleItem moduleItem) = do
            moduleItem' <- fullMapper moduleItem
            return $ case moduleItem' of
                Generate subItems -> GenBlock "" subItems
                _ -> GenModuleItem moduleItem'
        genItemMapper (GenIf _ GenNull GenNull) = return GenNull
        genItemMapper (GenIf (Number "1") s _) = return s
        genItemMapper (GenIf (Number "0") _ s) = return s
        genItemMapper (GenBlock "" [item]) = return item
        genItemMapper (GenBlock _ []) = return GenNull
        genItemMapper other = return other

traverseNestedModuleItems :: Mapper ModuleItem -> Mapper ModuleItem
traverseNestedModuleItems = unmonad traverseNestedModuleItemsM
collectNestedModuleItemsM :: Monad m => CollectorM m ModuleItem -> CollectorM m ModuleItem
collectNestedModuleItemsM = collectify traverseNestedModuleItemsM

traverseNestedStmts :: Mapper Stmt -> Mapper Stmt
traverseNestedStmts = unmonad traverseNestedStmtsM
collectNestedStmtsM :: Monad m => CollectorM m Stmt -> CollectorM m Stmt
collectNestedStmtsM = collectify traverseNestedStmtsM

traverseNestedExprs :: Mapper Expr -> Mapper Expr
traverseNestedExprs = unmonad traverseNestedExprsM
collectNestedExprsM :: Monad m => CollectorM m Expr -> CollectorM m Expr
collectNestedExprsM = collectify traverseNestedExprsM

-- Traverse all the declaration scopes within a ModuleItem. Note that Functions,
-- Tasks, Always/Initial/Final blocks are all NOT passed through ModuleItem
-- mapper, and Decl ModuleItems are NOT passed through the Decl mapper. The
-- state is restored to its previous value after each scope is exited. Only the
-- Decl mapper may modify the state, as we maintain the invariant that all other
-- functions restore the state on exit. The Stmt mapper must not traverse
-- statements recursively, as we add a recursive wrapper here.
traverseScopesM
    :: (Eq s, Show s)
    => Monad m
    => MapperM (StateT s m) Decl
    -> MapperM (StateT s m) ModuleItem
    -> MapperM (StateT s m) Stmt
    -> MapperM (StateT s m) ModuleItem
traverseScopesM declMapper moduleItemMapper stmtMapper =
    fullModuleItemMapper
    where

        nestedStmtMapper =
            stmtMapper >=> traverseSinglyNestedStmtsM fullStmtMapper
        fullStmtMapper (Block kw name decls stmts) = do
            prevState <- get
            decls' <- mapM declMapper decls
            block <- nestedStmtMapper $ Block kw name decls' stmts
            put prevState
            return block
        fullStmtMapper other = nestedStmtMapper other

        redirectModuleItem (MIPackageItem (Function ml t x decls stmts)) = do
            prevState <- get
            t' <- do
                res <- declMapper $ Variable Local t x [] Nil
                case res of
                    Variable Local newType _ [] Nil -> return newType
                    _ -> error $ "redirected func ret traverse failed: " ++ show res
            decls' <- mapM declMapper decls
            stmts' <- mapM fullStmtMapper stmts
            put prevState
            return $ MIPackageItem $ Function ml t' x decls' stmts'
        redirectModuleItem (MIPackageItem (Task     ml   x decls stmts)) = do
            prevState <- get
            decls' <- mapM declMapper decls
            stmts' <- mapM fullStmtMapper stmts
            put prevState
            return $ MIPackageItem $ Task     ml    x decls' stmts'
        redirectModuleItem (AlwaysC kw stmt) =
            fullStmtMapper stmt >>= return . AlwaysC kw
        redirectModuleItem (Initial stmt) =
            fullStmtMapper stmt >>= return . Initial
        redirectModuleItem (Final stmt) =
            fullStmtMapper stmt >>= return . Final
        redirectModuleItem item =
            moduleItemMapper item

        -- This previously checked the invariant that the module item mappers
        -- should not modify the state. Now we simply "enforce" it but resetting
        -- the state to its previous value. Comparing the state, as we did
        -- previously, incurs a noticeable performance hit.
        fullModuleItemMapper item = do
            prevState <- get
            item' <- redirectModuleItem item
            put prevState
            return item'

-- applies the given decl conversion across the description, and then performs a
-- scoped traversal for each ModuleItem in the description
scopedConversion
    :: (Eq s, Show s)
    => MapperM (State s) Decl
    -> MapperM (State s) ModuleItem
    -> MapperM (State s) Stmt
    -> s
    -> Description
    -> Description
scopedConversion traverseDeclM traverseModuleItemM traverseStmtM s description =
    runIdentity $ scopedConversionM traverseDeclM traverseModuleItemM traverseStmtM s description

scopedConversionM
    :: (Eq s, Show s)
    => Monad m
    => MapperM (StateT s m) Decl
    -> MapperM (StateT s m) ModuleItem
    -> MapperM (StateT s m) Stmt
    -> s
    -> Description
    -> m Description
scopedConversionM traverseDeclM traverseModuleItemM traverseStmtM s description =
    evalStateT (initialTraverse description >>= scopedTraverse) s
    where
        initialTraverse = traverseModuleItemsM traverseMIPackageItemDecl
        scopedTraverse = traverseModuleItemsM $
            traverseScopesM traverseDeclM traverseModuleItemM traverseStmtM
        traverseMIPackageItemDecl (MIPackageItem (Decl decl)) =
            traverseDeclM decl >>= return . MIPackageItem . Decl
        traverseMIPackageItemDecl other = return other

-- convert a basic mapper with an initial argument to a stateful mapper
stately :: (Eq s, Show s) => (s -> Mapper a) -> MapperM (State s) a
stately mapper thing = do
    s <- get
    return $ mapper s thing

-- In many conversions, we want to resolve items locally first, and then fall
-- back to looking at other source files, if necessary. This helper captures
-- this behavior, allowing a conversion to fall back to arbitrary global
-- collected item, if one exists. While this isn't foolproof (we could
-- inadvertently resolve a name that doesn't exist in the given file), many
-- projects rely on their toolchain to locate their modules, interfaces,
-- packages, or typenames in other files. Global resolution of modules and
-- interfaces is more commonly expected than global resolution of typenames and
-- packages.
traverseFilesM
    :: (Monoid w, Monad m)
    => CollectorM (Writer w) AST
    -> (w -> MapperM m AST)
    -> MapperM m [AST]
traverseFilesM fileCollectorM fileMapperM files =
    mapM traverseFileM files
    where
        globalNotes = execWriter $ mapM fileCollectorM files
        traverseFileM file =
            fileMapperM notes file
            where
                localNotes = execWriter $ fileCollectorM file
                notes = localNotes <> globalNotes
traverseFiles
    :: Monoid w
    => CollectorM (Writer w) AST
    -> (w -> Mapper AST)
    -> Mapper [AST]
traverseFiles fileCollectorM fileMapper files =
    evalState (traverseFilesM fileCollectorM fileMapperM  files) ()
    where fileMapperM = (\w -> return . fileMapper w)
