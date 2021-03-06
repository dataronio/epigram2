\section{Parsley}

Here is a bargain basement parser combinator library. It does nothing
fancy. It is hopelessly inefficient, but we can spend more effort when
it becomes a more serious problem. In particular, we can easily
represent extents numerically.

\question{What are \emph{extents} here?}

%if False

> {-# OPTIONS_GHC -F -pgmF she #-}

> module Kit.Parsley where

> import Control.Applicative
> import Control.Monad
> import Control.Monad.Error


%endif

\subsection{Parsley's Semantics}

A parser is represented as a function trying to transform a list of
tokens |t| to:

\begin{itemize}
  \item if it succeeds:
    \begin{itemize}
      \item the tokens successfully consumed so far, 
      \item the lexeme generated by the tokenization, and
      \item the remaining tokens to be read
    \end{itemize}
  \item if it fails:
    \begin{itemize}
      \item the tokens successfully consumed thus far,
      \item the expected token
    \end{itemize}
\end{itemize}

> newtype PFailure t = PFailure ([t], PError t) deriving Show
> data PError t = Abort
>               | EndOfStream
>               | EndOfParser
>               | Expect t
>               | Fail String
>                 deriving Show
> newtype Parsley t x = Parsley {runParsley :: [t] -> Either (PFailure t) ([t], x, [t])}

The informal semantics given above is formalized by the |parse|
function. A successful parse gives a lexeme, with no remaining
tokens. In all other cases, something went wrong.

> parse :: Parsley t x -> [t] -> Either (PFailure t) x
> parse (Parsley p) ts = case p ts of
>   Right (_, x, []) -> Right x
>   Right (ts, _, cts) -> Left (PFailure (ts, EndOfParser))
>   Left e -> Left e

\subsection{Structure}

It's a |Monad| and all that.

> instance Monad (Parsley t) where
>   return x = Parsley $ \ ts -> return ([], x, ts)
>   Parsley s >>= f = Parsley $ \ts -> do
>     (sts, s', ts)  <- s ts
>     (tts, t', ts)  <- runParsley (f s') ts
>     return (sts ++ tts, t', ts)
>   fail s = Parsley $ \ _ -> Left (PFailure ([], Fail s))

< instance Functor (Parsley t) where
<   fmap = ap . return

< instance Applicative (Parsley t) where
<   pure   = return
<   (<*>)  = ap

> instance MonadPlus (Parsley t) where
>   mzero = Parsley $ \ _ -> Left noMsg
>   mplus p q = Parsley $ \ ts -> 
>               either (\_ -> runParsley q ts) Right (runParsley p ts)

> instance Error (PFailure t) where
>   noMsg = PFailure ([], Abort)
>   strMsg s = PFailure ([], Fail s)

\subsection{Low-level combinators}

You can consume the next token. Doing so, we could fail by hitting the
end of the token stream.

> nextToken :: Parsley t t
> nextToken = Parsley $ \ ts -> case ts of
>   []        -> Left (PFailure ([], EndOfStream))
>   (t : ts)  -> Right ([t], t, ts)

You can consume everything! This always succeed.

> pRest :: Parsley t [t]
> pRest = Parsley $ \ ts -> Right (ts, ts, [])

You can peek ahead, that is: we return a lexeme composed by all the
tokens to come, but we do not consider them as consumed (|[]| on the
left, |ts| on the right).

> peekToken :: Parsley t [t]
> peekToken = Parsley $ \ ts -> Right ([], ts, ts)

You can make a parser give you the input extent it consumes as well as
its output.

> pExtent :: Parsley t x -> Parsley t ([t], x)
> pExtent (Parsley p) = Parsley $ \ ts -> do
>   (xts, x', ts) <- p ts
>   return (xts, (xts, x'), ts)

\subsection{High-level combinators}

Based on the combinators defined in the previous section, we implement
the combinators below without breaking the |Parsley(...)| abstraction.

You can test for the end of the token stream with |pEndOfStream|:

> pEndOfStream :: Parsley t ()
> pEndOfStream = guard =<< (|null peekToken|)

Parsing separated sequences goes like this, purely applicative with
She support. Either we can parse a |p| followed by many |sep| and |p|,
or we return the empty list.

> pSep :: Parsley t s -> Parsley t x -> Parsley t [x]
> pSep sep p =  (|p : (many $ sep *> p)
>                |id ~ []
>                |)

We can also allow an optional terminator for a separated sequence.

> pSepTerminate :: Parsley t s -> Parsley t x -> Parsley t [x]
> pSepTerminate sep p = pSep sep p <* optional sep

Similarly, one is often willing to consume some data up to some
delimiter. This is the role of |consumeUntil|. It runs the parser |p|
up to hitting a delimiter recognized by |delim|.

> consumeUntil :: Parsley t a -> Parsley t eol -> Parsley t [a]
> consumeUntil p delim = (|id ~ [] (% delim %)
>                         |p : (consumeUntil p delim)|)
>
> consumeUntil' = consumeUntil nextToken 

Thanks to the monadic nature of our parser, we can implement the
following looping combinator. Hence, we can parse some input |a| with
|p| and bind it. Then, we can try to use the dynamically generated
parser |l a|. Failing that, we simply return |a|.

> pLoop :: Parsley t a -> (a -> Parsley t a) -> Parsley t a
> pLoop p l = do
>   a <- p
>   pLoop (l a) l <|> pure a


Similarly, we can take advantage of the monadic nature of |Parsley| to
do some post-processing on its output. Hence, |pMapFilter| applies a
\emph{predicate} |f| to the result of |p|. The resulting parser is
therefore a parser which recognizes valid |p|-inputs satisfying the
predicate, and returning the result of |f| as tokens.

> pFilter :: (a -> Maybe b) -> Parsley t a -> Parsley t b
> pFilter f p = do
>   a <- p
>   case f a of
>     Just b -> return b
>     Nothing -> empty

Here's a useful static operation:

> pGuard :: Bool -> Parsley t ()
> pGuard True   = (|()|)
> pGuard False  = (|)


\subsection{Token manipulation}

Based on the combinators above, we can already build some interesting
parsers.

Hence, we can make a parser that matches the tokens satisfying a
predicate, |tokenFilter|. Then, we can easily build a parser that
matches a given token.

> tokenFilter :: (t -> Bool) -> Parsley t t
> tokenFilter p = pFilter (ok p) nextToken
>     where ok :: (a -> Bool) -> a -> Maybe a
>           ok p a = (|a (%guard (p a)%)|)
>
> tokenEq :: Eq t => t -> Parsley t ()
> tokenEq t = (|id ~ () (% tokenFilter (== t) %)|)
