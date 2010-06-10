\section{The Scheduler}

%if False

> {-# OPTIONS_GHC -F -pgmF she #-}
> {-# LANGUAGE GADTs, TypeOperators, TupleSections #-}

> module UI.Cochon.Elaboration.Scheduler where

> import NameSupply.NameSupply

> import Evidences.Tm
> import Evidences.Rules

> import Features.Features ()

> import ProofState.Developments
> import ProofState.Lifting
> import ProofState.ProofState
> import ProofState.ProofKit

> import DisplayLang.Name

> import UI.Cochon.Elaboration.ElabMonad
> import UI.Cochon.Elaboration.MakeElab
> import UI.Cochon.Elaboration.RunElab
> import UI.Cochon.Elaboration.Unification

> import Kit.BwdFwd
> import Kit.MissingLibrary

%endif

Handling elaboration essentially requires writing an operating system. Having
defined how to execute processes in section~\ref{sec:elaborator}, we now turn
our attention to process scheduling. The scheduler is called when an
elaboration process yields (either halting after solving its goal, halting
with an error, or suspending work until later). It searches downwards in the
proof state for unstable elaboration problems and executes any it finds.

When the scheduler is started, all problems before the working location should
be stable, but there may be unstable problems in the current location and below
it. The |startScheduler| command runs the scheduler from the top of the current
location, so it will stabilise the children and return to where it started.

> startScheduler :: ProofState ()
> startScheduler = cursorTop >> getMotherName >>= scheduler

In general, the scheduler might have to move non-locally (e.g. in order to solve
goals elsewhere in the proof state), so it keeps track of a target location to
return to.

> scheduler :: Name -> ProofState ()
> scheduler n = do
>     cs <- getDevCadets
>     case cs of

If we have no cadets to search, we check whether this is the target location:
if so, we stop, otherwise we resume the mother and continue searching.

>         F0 -> do
>             mn <- getMotherName
>             case mn of
>                 _ | mn == n  -> return ()
>                 []           -> error "scheduler: got lost!"
>                 _            -> do
>                     b <- resumeMother
>                     if b then cursorTop else goOutProperly
>                     scheduler n

Boys are simply ignored by the scheduler.

>         E _ _ (Boy _) _ :> _  -> cursorDown >> scheduler n

If we find a module or a girl, we enter it, try to resume its mother, then
search its children from the top.

>         _ :> _ -> do
>             cursorDown
>             goIn
>             resumeMother
>             cursorTop
>             scheduler n


The |resumeMother| command checks for an unstable elaboration problem on the
mother of the current location, and resumes elaboration if it finds one. If
elaboration succeeds, it gives the resulting term. It returns whether an
elaboration process was resumed (not whether the process succeeded).

> resumeMother :: ProofState Bool
> resumeMother = do
>   tip <- getDevTip
>   case tip of
>     Suspended (ty :=>: tyv) prob | isUnstable prob -> do
>         putDevTip (Unknown (ty :=>: tyv))
>         mn <- getMotherName
>         schedTrace $ "scheduler: resuming elaboration on " ++ showName mn
>                           ++ ":  \n" ++ show prob
>         mtt <- resume (ty :=>: tyv) prob
>         case mtt of
>             Just tt  ->  give' (termOf tt)
>                      >>  schedTrace "scheduler: elaboration done."
>             Nothing  ->  schedTrace "scheduler: elaboration suspended."
>         return True
>     _ -> return False


Given a (potentially, but not necessarily, unstable) elaboration problem for the
current location, we can |resume| it to try to produce a term. If this suceeds,
the cursor will be in the same location, but if it fails (i.e.\ the problem has
been suspended) then the cursor could be anywhere earlier in the proof state.

> resume :: (INTM :=>: VAL) -> EProb -> ProofState (Maybe (INTM :=>: VAL))
> resume _ (ElabDone tt) = return . Just . maybeEval $ tt
> resume (ty :=>: tyv) ElabHope = 
>     return . ifSnd =<< runElabHope True tyv
> resume (ty :=>: tyv) (ElabProb tm) = 
>     return . ifSnd =<< runElab True (tyv :>: makeElab (Loc 0) tm)
> resume (ty :=>: tyv) (ElabInferProb tm) =
>     return . ifSnd =<< runElab True (tyv :>: makeElabInfer (Loc 0) tm)
> resume (ty :=>: tyv) (WaitCan (tm :=>: Just (C v)) prob) =
>     resume (ty :=>: tyv) prob
> resume (ty :=>: tyv) (WaitCan (tm :=>: Nothing) prob) =
>     resume (ty :=>: tyv) (WaitCan (tm :=>: Just (evTm tm)) prob)
> resume _ prob@(WaitCan (tm :=>: _) _) = do
>     schedTrace $ "Suspended waiting for " ++ show tm ++ " to become canonical."
>     suspendMe prob
>     return Nothing
> resume _ (WaitSolve ref@(_ := HOLE _ :<: _) stt prob) = do
>     suspendMe prob
>     mn <- getMotherName
>     tm <- bquoteHere (valueOf . maybeEval $ stt) -- force definitional expansion
>     solveHole' ref [] tm -- takes us to who knows where
>     return Nothing

If we have a |WaitSolve| problem where the hole has already been solved with
something else, we need to check the solution is compatible. \question{How
can we reorganise things to use propositional rather than definitional
equality here?}

> resume tt (WaitSolve ref@(_ := DEFN tmv' :<: ty) stt prob) = do
>     aus   <- getGreatAuncles
>     sibs  <- getDevEntries
>     let  stt'  = maybeEval stt
>          stm   = parBind aus sibs (termOf stt')
>     eq <- withNSupply $ equal (ty :>: (evTm stm, tmv'))
>     if eq
>         then  resume tt prob
>         else  throwError' $ err "resume: hole" ++ errRef ref ++
>                    err "has been solved with" ++ errTyVal (tmv' :<: ty) ++
>                    err "but I wanted to solve it with" ++
>                            errTyVal (valueOf stt' :<: ty)

> resume tt (ElabSchedule prob) = resume tt prob


> ifSnd :: (a, Bool) -> Maybe a
> ifSnd (a,  True)   = Just a
> ifSnd (_,  False)  = Nothing


Trace messages from the scheduler are essential for debugging but annoying
otherwise, so we can enable or disable them at compile time.

> schedTrace :: String -> ProofState ()
> schedTrace s = if schedTracing then proofTrace s else return ()

> schedTracing = False