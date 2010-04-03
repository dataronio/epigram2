\section{Enum}
\label{sec:enum}

%if False

> {-# OPTIONS_GHC -F -pgmF she #-}

> module Features.Enum where

%endif

\question{Do the Formation/Introduction/\ldots names make sense?}

Formation rule:

\begin{prooftree}
\AxiomC{}
\RightLabel{EnumU-formation}
\UnaryInfC{|Set :>: EnumU|}
\end{prooftree}

\begin{prooftree}
\AxiomC{|EnumU :>: e|}
\RightLabel{EnumT-formation}
\UnaryInfC{|Set :>: EnumT e|}
\end{prooftree}

Introduction rules:

\begin{prooftree}
\AxiomC{}
\RightLabel{NilE-intro-1}
\UnaryInfC{|EnumU :>: NilE|}
\end{prooftree}

\begin{prooftree}
\AxiomC{|UId :>: t|}
\AxiomC{|EnumU :>: e|}
\RightLabel{ConsE-Intro-1}
\BinaryInfC{|EnumU :>: ConsE t e|}
\end{prooftree}

\begin{prooftree}
\AxiomC{}
\RightLabel{Ze-intro-1}
\UnaryInfC{|EnumT (ConsE t e) :>: Ze|}
\end{prooftree}

\begin{prooftree}
\AxiomC{|EnumT e :>: n|}
\RightLabel{Su-intro-1}
\UnaryInfC{|EnumT (ConsE t e) :>: Su n|}
\end{prooftree}

Elimination rules:

\begin{prooftree}
\AxiomC{|EnumU :>: e|}
\AxiomC{|EnumT e -> Set :>: P|}
\RightLabel{branches-elim}
\BinaryInfC{|Set :>: branches(e,P)|}
\end{prooftree}

With the following computational behavior:

< branches NilE _ :-> Unit
< branches (ConsE t e') P :-> (P Ze , branches (e', \x -> P (Su x)))

\begin{prooftree}
\AxiomC{|EnumU :>: e|}
\noLine
\UnaryInfC{|EnumT e -> Set :>: P|}
\AxiomC{|branches(e,P) :>: b|}
\noLine
\UnaryInfC{|EnumT e :>: x|}
\RightLabel{switch-elim}
\BinaryInfC{|P x :>: switch(e,P,b,x)|}
\end{prooftree}

With the following computational behavior:

< switch (ConsE t e') P ps Ze :-> fst ps
< switch (ConsE t e') P ps (Su n) :-> switch(e', \x -> P (Su x), snd ps, n)

Equality rules:

< eqGreen(EnumU, NilE, EnumU, NilE) :-> Trivial
< eqGreen(EnumU, ConsE t1 e1, EnumU, ConsE t2 e2) :->
<     And (eqGreen(UId, t1, UId, t2))
<         (eqGreen(EnumU, e1, EnumU, e2))
< eqGreen(EnumT (ConsE _ e1), Ze, EnumT (ConsE _ e2), Ze) :-> Trivial
< eqGreen(EnumT (ConsE _ e1), Su n1, EnumT (ConsE _ e2), Su n2) :->
<     eqGreen(EnumT e1, n1, EnumT e2, n2)


> import -> BootstrapDesc where
>   inEnumU :: VAL
>   inEnumU = SIGMAD  (ENUMT constructors)
>                     (L $ HF "c" $ \c -> 
>                      switchDOp @@ [ constructors , cases , c])
>       where constructors = CONSE (TAG "nil")
>                            (CONSE (TAG "cons")
>                             NILE)
>             cases = PAIR (CONSTD UNIT)
>                     (PAIR (SIGMAD UID (L $ K (PRODD IDD (CONSTD UNIT))))
>                      VOID)
>   enumFakeREF :: REF
>   enumFakeREF = [("Primitive", 0), ("EnumU", 0)] := (FAKE :<: SET) 
>   enumU :: VAL
>   enumU = MU (Just (N (P enumFakeREF))) inEnumU
>   enumREF :: REF
>   enumREF = [("Primitive", 0), ("EnumU", 0)] := (DEFN enumU :<: SET) 

> import -> Primitives where
>   ("EnumU", enumREF) :

> import -> CanConstructors where
>   EnumT  :: t -> Can t
>   Ze     :: Can t
>   Su     :: t -> Can t 

> import -> CanPats where
>   pattern ENUMT e    = C (EnumT e) 
>   pattern NILE       = CON (PAIR ZE VOID)
>   pattern CONSE t e  = CON (PAIR (SU ZE) (PAIR t (PAIR e VOID)))
>   pattern ZE         = C Ze
>   pattern SU n       = C (Su n)

> import -> CanDisplayPats where
>   pattern DENUMT e    = DC (EnumT e) 
>   pattern DNILE       = DCON (DPAIR {-(DTAG "nil")-} DZE DVOID)
>   pattern DCONSE t e  = DCON (DPAIR {- (DTAG "cons") -} (DSU DZE) (DPAIR t (DPAIR e DVOID)))
>   pattern DZE         = DC Ze
>   pattern DSU n       = DC (Su n)

> import -> CanCompile where
>   makeBody Ze = CTag 0
>   makeBody (Su x) = STag (makeBody x)

> import -> CanTraverse where
>   traverse f (EnumT e)    = (|EnumT (f e)|)
>   traverse f Ze           = (|Ze|)
>   traverse f (Su n)       = (|Su (f n)|) 

> import -> CanHalfZip where
>   halfZip (EnumT t0) (EnumT t1) = Just (EnumT (t0,t1))
>   halfZip Ze Ze = Just Ze
>   halfZip (Su t0) (Su t1) = Just (Su (t0,t1))

> import -> CanPretty where
>   pretty (EnumT t)  = wrapDoc (kword KwEnum <+> pretty t ArgSize) AppSize
>   pretty Ze         = const (int 0)
>   pretty (Su t)     = prettyEnumIndex 1 t

> import -> Pretty where
>   prettyEnumIndex :: Int -> InDTmRN -> Size -> Doc
>   prettyEnumIndex n DZE      = const (int n)
>   prettyEnumIndex n (DSU t)  = prettyEnumIndex (succ n) t
>   prettyEnumIndex n tm       = wrapDoc
>       (int n <+> kword KwPlus <+> pretty tm ArgSize)
>       ArgSize

> import -> CanTyRules where
>   canTy chev (Set :>: EnumT e)  = do
>     eev@(e :=>: ev) <- chev (enumU :>: e)
>     return $ EnumT eev
>   canTy _ (EnumT (CONSE t e) :>: Ze)    = return Ze 
>   canTy chev (EnumT (CONSE t e) :>: Su n)  = do
>     nnv@(n :=>: nv) <- chev (ENUMT e :>: n)
>     return $ Su nnv

> import -> OpCode where

>   type EnumDispatchTable = (VAL, VAL -> VAL -> VAL) 
>
>   mkLazyEnumDef :: VAL -> EnumDispatchTable -> Either NEU VAL
>   mkLazyEnumDef arg cases =
>     let const = arg $$ Fst
>         args  = arg $$ Snd
>     in Right $ dispatch const cases args
>        where dispatch :: VAL -> EnumDispatchTable -> VAL -> VAL
>              dispatch ZE (nilECase, consECase) args = nilECase
>              dispatch (SU ZE) (nilECase, consECase) args =
>                  consECase (args $$ Fst) (args $$ Snd $$ Fst)

>   branchesOp = Op 
>     { opName   = "branches"
>     , opArity  = 2 
>     , opTyTel  = bOpTy
>     , opRun    = bOpRun
>     , opSimp   = \_ _ -> empty
>     } where
>         bOpTy = "e" :<: enumU :-: \e ->
>                 "p" :<: ARR (ENUMT e) SET :-: \p ->
>                 Target SET

>         bOpRun :: [VAL] -> Either NEU VAL
>         bOpRun [CON arg, p] = mkLazyEnumDef arg (nilECase p, 
>                                                  consECase p)
>         bOpRun [N e , _] = Left e 

%if False

>         bOpRun vs = error ("Enum.branches.bOpRun: couldn't handle " ++ show vs)

%endif

>         nilECase p = UNIT
>         consECase p t e' = 
>             TIMES (p $$ A ZE) 
>                   (branchesOp @@ [e' , L (HF "x" $ \x -> p $$ A (SU x))])

>   switchOp = Op
>     { opName  = "switch"
>     , opArity = 4
>     , opTyTel = sOpTy
>     , opRun   = sOpRun
>     , opSimp  = \_ _ -> empty
>     } where
>         sOpTy = 
>           "e" :<: enumU :-: \e ->
>           "x" :<: ENUMT e :-: \x ->
>           "p" :<: ARR (ENUMT e) SET :-: \p ->
>           "b" :<: branchesOp @@ [e , p] :-: \b -> 
>           Target (p $$ A x)
>         sOpRun :: [VAL] -> Either NEU VAL
>         sOpRun [_      , N n , _ , _] = Left n
>         sOpRun [CON arg, n, p, ps] = mkLazyEnumDef arg (error "switchOp: NilE barfs me.", 
>                                                         consECase n p ps)
>
>         consECase :: VAL -> VAL -> VAL -> VAL -> VAL -> VAL
>         consECase ZE     p ps t e' = ps $$ Fst
>         consECase (SU n) p ps t e' =
>             switchOp @@ [ e'
>                         , n
>                         , L . HF "x" $ \x -> p $$ A (SU x)
>                         , ps $$ Snd ]

> import -> Coerce where
>   coerce (EnumT (CONSE _ _,   CONSE _ _))      _  (N x) = Left x
>   coerce (EnumT (CONSE _ _,   CONSE _ _))      _  ZE = Right ZE
>   coerce (EnumT (CONSE _ e1,  CONSE _ e2))     q  (SU x) = Right . SU $
>     coe @@ [ENUMT e1, ENUMT e2, CON $ q $$ Snd $$ Snd $$ Fst, x]  -- |CONSE| tails
>   coerce (EnumT (NILE,        NILE))           q  x = Right x
>   coerce (EnumT (NILE,        t@(CONSE _ _)))  q  x = Right $
>     nEOp @@ [q, ENUMT t]
>   coerce (EnumT (CONSE _ _,   NILE))           q  x = Right $
>     nEOp @@ [q, ENUMT NILE]

> import -> Operators where
>   branchesOp :
>   switchOp :

> import -> OpCompile where
>     ("branches", _) -> Ignore
>     ("switch", [e, x, p, b]) -> App (Var "__switch") [x, b]


A function from an enumeration is equivalent to a list, so the elaborator can
turn lists into functions like this:

> import -> MakeElabRules where
>   makeElab' loc (PI (ENUMT e) t :>: m) | isTuply m = do
>       t' :=>: _ <- eQuote t
>       e' :=>: _ <- eQuote e
>       tm :=>: tmv <- subElab loc (branchesOp @@ [e, t] :>: m)
>       x <- eLambda (fortran t)
>       return $ N (switchOp :@ [e', NP x, t', tm])
>                      :=>: switchOp @@ [e, NP x, t, tmv]
>     where
>       isTuply :: InDTmRN -> Bool
>       isTuply DVOID        = True
>       isTuply (DPAIR _ _)  = True
>       isTuply _            = False


To elaborate a tag with an enumeration as its type, we search for the
tag in the enumeration to determine the appropriate index.

>   makeElab' loc (ENUMT t :>: DTAG a) = findTag a t 0
>     where
>       findTag :: String -> TY -> Int -> Elab (INTM :=>: VAL)
>       findTag a (CONSE (TAG b) t) n
>         | a == b        = return (toNum n :=>: toNum n)
>         | otherwise     = findTag a t (succ n)
>       findTag a _ n  = throwError' . err $ "elaborate: tag `" 
>                                             ++ a 
>                                             ++ " not found in enumeration."
>                         
>       toNum :: Int -> Tm {In, p} x
>       toNum 0  = ZE
>       toNum n  = SU (toNum (n-1))

Conversely, we can distill an index to a tag as follows. Note that if the
index contains a stuck term, we simply give up and let the normal distillation
rules take over; the pretty-printer will then do the right thing.

> import -> DistillRules where
>   distill _ (ENUMT t :>: tm) | Just r <- findIndex (t :>: tm) = return r
>     where
>       findIndex :: (VAL :>: INTM) -> Maybe (InDTmRN :=>: VAL)
>       findIndex (CONSE (TAG s)  _ :>: ZE)    = Just (DTAG s :=>: evTm tm)
>       findIndex (CONSE _        a :>: SU b)  = findIndex (a :>: b)
>       findIndex _                            = Nothing

Since elaboration turns lists into functions from enumerated types, we can
do the reverse when distilling. This is slightly dubious.

>   distill es (PI (ENUMT e) t :>: L (x :. N (op :@ [e', NV 0, t', b]))) 
>     | op == switchOp = distill es (branchesOp @@ [e, t] :>: b)