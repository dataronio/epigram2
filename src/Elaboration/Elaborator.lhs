\section{The Elaborator}
\label{sec:elaborator}

%if False

> {-# OPTIONS_GHC -F -pgmF she #-}
> {-# LANGUAGE GADTs, TypeOperators, TupleSections #-}

> module Elaboration.Elaborator where

> import Control.Applicative
> import Control.Monad.Error
> import Control.Monad.Identity
> import Data.Traversable
> import Data.Monoid hiding (All)

> import NameSupply.NameSupplier

> import Evidences.Tm
> import Evidences.Rules
> import Evidences.Mangler

> import Features.Features ()

> import ProofState.Developments
> import ProofState.Lifting
> import ProofState.ProofContext
> import ProofState.ProofState
> import ProofState.ProofKit

> import DisplayLang.DisplayTm
> import DisplayLang.Naming

> import Tactics.PropSimp

> import Elaboration.ElabMonad
> import Elaboration.MakeElab

> import Cochon.Error

> import Kit.BwdFwd
> import Kit.MissingLibrary

%endif

\subsection{Implementing the |Elab| monad}

The |runElab| proof state command actually interprets an |Elab x| in
the proof state. That is, it defines the semantics of the |Elab| syntax.
It returns |True| in the second component if elaboration was successful,
and |False| if the problem was suspended.

> runElab :: Bool -> (TY :>: Elab (INTM :=>: VAL))
>                       -> ProofState (INTM :=>: VAL, Bool)
> runElab _ (_ :>: Bale x) = return (x, True)

> runElab True (ty :>: ELambda x f) = case lambdable ty of
>     Just (_, s, tyf) -> do
>         ref <- lambdaBoy x
>         runElab True (tyf (NP ref) :>: f ref)
>     Nothing -> throwError' $ err "runElab: type" ++ errTyVal (ty :<: SET)
>                                  ++ err "is not lambdable!"

> runElab False (ty :>: ELambda s f) = runElabTop (ty :>: ELambda s f)

> runElab top (ty :>: EGoal f) = runElab top (ty :>: f ty)

> runElab top (ty :>: EWait s tyWait f) = do
>     tyWait' <- bquoteHere tyWait
>     tt <- make' Waiting (s :<: tyWait' :=>: tyWait)
>     runElab top (ty :>: f tt)

> runElab top (ty :>: EElab l p)  = runElabProb top l (ty :>: p)

> runElab top (ty :>: ECompute (tyComp :>: elab) f) = runElab False (tyComp :>: elab)
>     >>= runElab top . (ty :>:) . f . fst

> runElab True (ty :>: ECry e) = do
>     e' <- distillErrors e
>     let msg = show (prettyStackError e')
>     mn <- getMotherName
>     proofTrace ("Hole " ++ showName mn ++ " started crying:\n" ++ msg)
>     putHoleKind (Crying msg)
>     t :=>: tv <- getMotherDefinition
>     return (N t :=>: tv, False)

> runElab False (ty :>: ECry e) = runElabTop (ty :>: ECry e)

> runElab True (ty :>: EFake b f)           = do
>     GirlMother (nom := HOLE _ :<: ty) _ _ _ <- getMother
>     let fr = nom := FAKE :<: ty
>     xs <- if b  then  (| boySpine getAuncles |)
>                 else  (| (init . boySpine) getAuncles |)
>     let tm = P fr $:$ xs
>     runElab True . (ty :>:) . f $ tm :=>: evTm tm

> runElab False (ty :>: EFake b f) = runElabTop (ty :>: EFake b f)


> runElab top (ty :>: EResolve rn f) = do
>     (ref, as, ms) <- resolveHere rn
>     let tm = P ref $:$ as
>     (tmv :<: tyv) <- inferHere tm
>     tyv'  <- bquoteHere tyv
>     runElab top (ty :>: f (PAIR tyv' (N tm) :=>: PAIR tyv tmv, ms))
>   

> runElab top (ty :>: EAskNSupply f) = do
>     nsupply <- askNSupply
>     runElab top (ty :>: f nsupply)


The |runElabTop| command interprets the |Elab| monad at the top level, by
creating a new subgoal corresponding to the solution. This is necessary
when commands that need to modify the proof state (such as |ELambda|)
are encountered below the top level.

> runElabTop :: (TY :>: Elab (INTM :=>: VAL)) -> ProofState (INTM :=>: VAL, Bool)
> runElabTop (ty :>: elab) = do
>     ty' <- bquoteHere ty
>     x <- pickName "h" ""
>     make' Waiting (x :<: ty' :=>: ty)
>     goIn
>     (tm :=>: tmv, okay) <- runElab True (ty :>: elab)
>     if okay
>         then  return . (, True)  =<< neutralise =<< give tm
>         else  return . (, False) =<< neutralise =<< getMotherDefinition <* goOut


\subsubsection{Interpreting elaboration problems}

The |runElabProb| command interprets the |EElab| instruction, which holds a syntactic
representation of an elaboration problem. 

> runElabProb :: Bool -> Loc -> (TY :>: EProb) -> ProofState (INTM :=>: VAL, Bool)
> runElabProb top loc (ty :>: ElabDone tt)  = return (maybeEval tt, True)
> runElabProb top loc (ty :>: ElabHope)     = runElabHope top ty
> runElabProb top loc (ty :>: ElabProb tm)  = runElab top (ty :>: makeElab loc tm)
> runElabProb top loc (ty :>: ElabInferProb tm) =
>     runElab top (ty :>: makeElabInfer loc tm)
> runElabProb top loc (ty :>: WaitCan (_ :=>: Just (C _)) prob) =
>     runElabProb top loc (ty :>: prob)
> runElabProb top loc (ty :>: WaitCan (tm :=>: Nothing) prob) =
>     runElabProb top loc (ty :>: WaitCan (tm :=>: Just (evTm tm)) prob)
> runElabProb True loc (ty :>: prob) =
>     return . (, False) =<< neutralise =<< suspendMe prob
> runElabProb False loc (ty :>: prob) = do
>     ty' <- bquoteHere ty
>     return . (, True) =<< neutralise =<< suspend (name prob :<: ty' :=>: ty) prob
>   where
>     name :: EProb -> String
>     name (WaitCan _ _)      = "can"
>     name (WaitSolve _ _ _)  = "solve"
>     name _                  = "suspend"


\subsubsection{Hoping, hoping, hoping}

The |runElabHope| command interprets the |EHope| instruction, which hopes for
an element of a given type. If it is asking for a proof, we might be able to
find one, but otherwise we just create a hole.

> runElabHope :: Bool -> TY -> ProofState (INTM :=>: VAL, Bool)
> runElabHope top (PRF p)  = simplifyProof top p
> runElabHope top ty       = lastHope top ty

If we are hoping for a proof of a proposition, we first try simplifying it using
the propositional simplification machinery.

> simplifyProof :: Bool -> VAL -> ProofState (INTM :=>: VAL, Bool)
> simplifyProof top p = do
>     pSimp <- runPropSimplify p
>     case pSimp of
>         Just (SimplyTrivial prf) -> do
>             prf' <- bquoteHere prf
>             return (prf' :=>: prf, True)
>         Just (SimplyAbsurd _) -> runElab top (PRF p :>:
>             ECry [err "lastHope: proposition is absurd!"])
>         Just (Simply qs _ h) -> do
>             qrs <- Data.Traversable.mapM partProof qs
>             h' <- dischargeLots qs h
>             let prf = h' $$$ qrs
>             prf' <- bquoteHere prf
>             return (prf' :=>: prf, True)
>         Nothing -> subProof top (PRF p)
>   where
>     partProof :: REF -> ProofState (Elim VAL)
>     partProof ref = return . A . valueOf . fst =<< subProof False (pty ref)

>     subProof :: Bool -> VAL -> ProofState (INTM :=>: VAL, Bool)
>     subProof top (PRF p) = flexiProof top p <|> lastHope top (PRF p)

After simplification has dealt with the easy stuff, it calls |flexiProof| to
solve any flex-rigid equations (by suspending a solution process on a subgoal
and returning the subgoal). \question{Can we hope for a proof of equality and
insert a coercion rather than demanding definitional equality of the sets?}

> flexiProof :: Bool -> VAL -> ProofState (INTM :=>: VAL, Bool)
> flexiProof top p@(EQBLUE (_S :>: s) (_T :>: (NP ref@(_ := HOLE Hoping :<: _)))) = do
>     guard =<< withNSupply (equal (SET :>: (_S, _T)))
>     s' <- bquoteHere s
>     _S' <- bquoteHere _S
>     _T' <- bquoteHere _T
>     let p' = EQBLUE (_S' :>: s') (_T' :>: NP ref)
>     return . (, False) =<< neutralise =<< suspend ("eq" :<: PRF p' :=>: PRF p)
>         (WaitSolve ref (s' :=>: Just s)
>             (ElabDone (N (P refl :$ A _S' :$ A s')
>                           :=>: Just (pval refl $$ A _S $$ A s))))

> flexiProof top p@(EQBLUE (_T :>: (NP ref@(_ := HOLE Hoping :<: _))) (_S :>: s)) = do
>     guard =<< withNSupply (equal (SET :>: (_S, _T)))
>     s' <- bquoteHere s
>     _S' <- bquoteHere _S
>     _T' <- bquoteHere _T
>     let p' = EQBLUE (_T' :>: NP ref) (_S' :>: s')
>     return . (, False) =<< neutralise =<< suspend ("eq" :<: PRF p' :=>: PRF p)
>         (WaitSolve ref (s' :=>: Just s)
>             (ElabDone (N (P refl :$ A _S' :$ A s')
>                           :=>: Just (pval refl $$ A _S $$ A s))))

> flexiProof _ _ = (|)

If all else fails, we can hope for anything we like by creating a subgoal, though
ideally we should cry rather than hoping for something patently absurd.

> lastHope :: Bool -> TY -> ProofState (INTM :=>: VAL, Bool)
> lastHope True ty = do
>     putHoleKind Hoping
>     return . (, False) =<< neutralise =<< getMotherDefinition
> lastHope False ty = do
>     ty' <- bquoteHere ty
>     return . (, True) =<< neutralise =<< make' Hoping ("hope" :<: ty' :=>: ty)


\subsubsection{Suspending computation}

The |suspend| command can be used to delay elaboration, by creating a subgoal
of the given type and attaching a suspended elaboration problem to its tip.
When the scheduler hits the goal, the elaboration problem will restart if it
is unstable.

> suspend :: (String :<: INTM :=>: TY) -> EProb
>                -> ProofState (EXTM :=>: VAL)
> suspend (x :<: tt) prob = do
>     r <- make' Waiting (x :<: tt)
>     Just (E ref xn (Girl LETG (es, Unknown utt, nsupply) ms) tm) <- removeDevEntry
>     putDevEntry (E ref xn (Girl LETG (es, Suspended utt prob, nsupply) ms) tm)
>     return r


The |suspendMe| command attaches a suspended elaboration problem to the current
location.

> suspendMe :: EProb -> ProofState (EXTM :=>: VAL)
> suspendMe prob = do
>     Unknown tt <- getDevTip
>     putDevTip (Suspended tt prob)
>     getMotherDefinition



\subsection{Elaborating terms}

The |elaborate| command elaborates a term in display syntax, given its type,
to produce an elaborated term and its value representation. It behaves
similarly to |check| from subsection~\ref{subsec:type-checking}, except that
it operates in the |Elab| monad, so it can create subgoals and
$\lambda$-lift terms.

> elaborate :: Loc -> (TY :>: InDTmRN) -> ProofState (INTM :=>: VAL)
> elaborate loc (ty :>: tm) = runElab False (ty :>: makeElab loc tm)
>     >>= return . fst

> elaborate' = elaborate (Loc 0)


> elaborateHere :: Loc -> InDTmRN -> ProofState (INTM :=>: VAL, Bool)
> elaborateHere loc tm = do
>     _ :=>: ty <- getHoleGoal
>     runElab True (ty :>: makeElab loc tm)

> elaborateHere' = elaborateHere (Loc 0)


> elabInfer :: Loc -> ExDTmRN -> ProofState (INTM :=>: VAL :<: TY)
> elabInfer loc tm = do
>     (tt, _) <- runElab False (sigSetVAL :>: makeElabInfer loc tm)
>     let (tt' :<: _ :=>: ty) = extractNeutral tt
>     return (tt' :<: ty)

> elabInfer' = elabInfer (Loc 0)



\subsection{Elaborated Construction Commands}


The |elabGive| command elaborates the given display term in the appropriate type for
the current goal, and calls the |give| command on the resulting term. If its argument
is a nameless question mark, it avoids creating a pointless subgoal by simply returning
a reference to the current goal (applied to the appropriate shared parameters).

> elabGive :: InDTmRN -> ProofState (EXTM :=>: VAL)
> elabGive tm = elabGive' tm <* goOut

> elabGiveNext :: InDTmRN -> ProofState (EXTM :=>: VAL)
> elabGiveNext tm = elabGive' tm <* (nextGoal <|> goOut)

> elabGive' :: InDTmRN -> ProofState (EXTM :=>: VAL)
> elabGive' tm = do
>     tip <- getDevTip
>     case (tip, tm) of         
>         (Unknown _, DQ "")  -> getDefn
>         (Unknown _, _)      -> do
>             (tm' :=>: _, done) <- elaborateHere' tm
>             if done then give' tm' else getDefn
>         _  -> throwError' $ err "elabGive: only possible for incomplete goals."
>   where
>     getDefn :: ProofState (EXTM :=>: VAL)
>     getDefn = do
>         GirlMother ref _ _ _ <- getMother
>         aus <- getGreatAuncles
>         return (applyAuncles ref aus)


The |elabMake| command elaborates the given display term in a module to
produce a type, then converts the module to a goal with that type. Thus any
subgoals produced by elaboration will be children of the resulting goal.

> elabMake :: (String :<: InDTmRN) -> ProofState (EXTM :=>: VAL)
> elabMake (s :<: ty) = do
>     makeModule s
>     goIn
>     ty' :=>: _ <- elaborate' (SET :>: ty)
>     tm <- moduleToGoal ty'
>     goOutProperly
>     return tm


The |elabProgram| command adds a label to a type, given a list of arguments.
e.g. with a goal |plus : Nat -> Nat -> Nat|, |program x,y| will give a proof
state of:

\begin{verbatim}
plus [
  plus := ? : (x : Nat) -> (y : Nat) -> <plus x y : Nat>
  \ x : Nat
  \ y : Nat
] plus x y call : Nat
\end{verbatim}

> elabProgram :: [String] -> ProofState (EXTM :=>: VAL)
> elabProgram args = do
>     n <- getMotherName
>     (_ :=>: g) <- getHoleGoal
>     let pn = P (n := FAKE :<: g)
>     let newty = pity (mkTel pn g [] args)
>     newty' <- bquoteHere newty
>     g :=>: _ <- make (fst (last n) :<: newty') 
>     argrefs <- traverse lambdaBoy args
>     let fcall = pn $## (map NP argrefs) 
>     let call = g $## (map NP argrefs) :$ Call (N fcall)
>     r <- give' (N call)
>     goIn
>     return r
>   where mkTel :: NEU -> TY -> [VAL] -> [String] -> TEL TY
>         mkTel n (PI s t) args (x:xs)
>            = (x :<: s) :-: (\val -> mkTel n (t $$ A val) (val:args) xs)
>         mkTel n r args _ = Target (LABEL (mkL n (reverse args)) r)
>         
>         mkL :: NEU -> [VAL] -> VAL
>         mkL n [] = N n
>         mkL n (x:xs) = mkL (n :$ (A x)) xs


The |elabPiBoy| command elaborates the given display term to produce a type, and
creates a $\Pi$-boy with that type.

> elabPiBoy :: (String :<: InDTmRN) -> ProofState REF
> elabPiBoy (s :<: ty) = do
>     tt <- elaborate' (SET :>: ty)
>     piBoy' (s :<: tt)

> elabLamBoy :: (String :<: InDTmRN) -> ProofState REF
> elabLamBoy (s :<: ty) = do
>     tt <- elaborate' (SET :>: ty)
>     lambdaBoy' (s :<: tt)


\subsection{Elaborating Schemes}

> elabLet :: (String :<: Scheme InDTmRN) -> ProofState (EXTM :=>: VAL)
> elabLet (x :<: sch) = do
>     makeModule x
>     goIn
>     make ("tau" :<: SET)
>     goIn
>     (sch', ty :=>: _) <- elabScheme B0 sch
>     moduleToGoal (N ty)     
>     putMotherScheme sch'
>     r <- elabProgram (schemeNames sch')
>     putMotherScheme sch' -- this is wrong but does it matter?
>     return r


> elabScheme :: Entries -> Scheme InDTmRN -> ProofState (Scheme INTM, EXTM :=>: VAL)

> elabScheme es (SchType ty) = do
>     ty' :=>: _ <- elaborate' (SET :>: ty)
>     tt <- give ty'
>     return (SchType (es -| ty'), tt)

> elabScheme es (SchExplicitPi (x :<: s) t) = do
>     make ("tau" :<: SET)
>     goIn
>     (s', ty :=>: _) <- elabScheme es s
>     piBoy (x :<: N ty)
>     e <- getDevEntry
>     (t', tt) <- elabScheme (es :< e) t
>     return (SchExplicitPi (x :<: s') t', tt)

> elabScheme es (SchImplicitPi (x :<: s) t) = do
>     ss <- elaborate' (SET :>: s)
>     piBoy (x :<: termOf ss)
>     e <- getDevEntry
>     (t', tt) <- elabScheme (es :< e) t
>     return (SchImplicitPi (x :<: (es -| termOf ss)) t', tt)


> import <- ElabCode