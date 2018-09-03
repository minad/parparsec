module Text.ParParsec.Combinators (
  -- * Basics
  Text
  , F.void
  , (A.<|>)
  , A.empty
  , A.optional
  , A.many

  -- * Control.Monad.Combinators.NonEmpty
  , NonEmpty(..)
  , ON.some
  , ON.endBy1
  , ON.someTill
  , ON.sepBy1
  , ON.sepEndBy1

  -- * Control.Monad.Combinators
  , O.between
  , O.choice
  , O.count
  , O.count'
  , O.eitherP
  , O.endBy
  , O.manyTill
  , O.option
  , O.sepBy
  , O.sepEndBy
  , O.skipMany
  , O.skipSome
  , O.skipCount
  , O.skipManyTill
  , O.skipSomeTill

  -- * ParParsec
  , (<?>)
  , getRefColumn
  , getRefLine
  , setRefColumn
  , setRefLine
  , saveRef
  , align
  , indented
  , line
  , linefold
  , notByte
  , anyByte
  , digitByte
  , integer
  , signed
  , fractionHex
  , fractionDec
  , char'
  , notChar
  , anyChar
  , alphaNumChar
  , digitChar
  , letterChar
  , string
  , asString
) where

import Control.Applicative ((<|>))
import Control.Monad (when, unless)
import Control.Monad.Combinators (option)
import Data.List.NonEmpty (NonEmpty(..))
import Text.ParParsec.Ascii
import Text.ParParsec.Class
import Data.Text (Text)
import GHC.Base (unsafeChr)
import Prelude hiding (getLine)
import qualified Control.Applicative as A
import qualified Control.Monad.Combinators as O
import qualified Control.Monad.Combinators.NonEmpty as ON
import qualified Data.Char as C
import qualified Data.Functor as F
import qualified Data.Text.Encoding as T

(<?>) :: Parser p => p a -> String -> p a
(<?>) = flip label
{-# INLINE (<?>) #-}

getRefLine :: Parser p => p Int
getRefLine = _posLine <$> getRefPos
{-# INLINE getRefLine #-}

getRefColumn :: Parser p => p Int
getRefColumn = _posColumn <$> getRefPos
{-# INLINE getRefColumn #-}

setRefLine :: Parser p => Int -> p ()
setRefLine l = do
  c <- getRefColumn
  setRefPos $ Pos l c
{-# INLINE setRefLine #-}

setRefColumn :: Parser p => Int -> p ()
setRefColumn c = do
  l <- getRefLine
  setRefPos $ Pos l c
{-# INLINE setRefColumn #-}

getLine :: Parser p => p Int
getLine = _posLine <$> getPos
{-# INLINE getLine #-}

getColumn :: Parser p => p Int
getColumn = _posColumn <$> getPos
{-# INLINE getColumn #-}

line :: Parser p => p ()
line = do
  l <- getLine
  rl <- getRefLine
  when (l /= rl) $ fail "Over one line"
{-# INLINE line #-}

saveRef :: Parser p => p a -> p a
saveRef p = do
  r <- getRefPos
  getPos >>= setRefPos
  x <- p
  setRefPos r
  pure x
{-# INLINE saveRef #-}

align :: Parser p => p ()
align = do
  c <- getColumn
  rc <- getRefColumn
  when (c /= rc) $ fail "Indentation not aligned"
{-# INLINE align #-}

indented :: Parser p => p ()
indented = do
  c <- getColumn
  rc <- getRefColumn
  if c <= rc then
    fail "Not enough indentation"
  else
    getLine >>= setRefLine
{-# INLINE indented #-}

linefold :: Parser p => p ()
linefold = line <|> indented
{-# INLINE linefold #-}

notByte :: Parser p => Word8 -> p Word8
notByte b = byteSatisfy (/= b)
{-# INLINE notByte #-}

anyByte :: Parser p => p Word8
anyByte = byteSatisfy (const True)
{-# INLINE anyByte #-}

digitByte :: Parser p => p Word8
digitByte = byteSatisfy (\b -> b >= asc_0 && b <= asc_9) <?> "digit"
{-# INLINE digitByte #-}

integer :: (Num a, Parser p) => p sep -> Int -> p (a, Int)
integer sep base = do
  unless (base >= 2 && base <= 36) $ fail "Only base 2 to 36 are supported"
  d <- digit base
  accum 1 $ fromIntegral d
  where accum !i !n = next i n <|> pure (n, i)
        next !i !n = do
          d <- sep *> digit base
          accum (i + 1) $ n * fromIntegral base + fromIntegral d
{-# INLINE integer #-}

digitToInt :: Int -> Word8 -> Word
digitToInt base b
  | n <- (fromIntegral b :: Word) - fromIntegral asc_0, base <= 10 || n <= 9  = n
  | n <- (fromIntegral b :: Word) - fromIntegral asc_A, n               <= 26 = n + 10
  | n <- (fromIntegral b :: Word) - fromIntegral asc_a                        = n + 10
{-# INLINE digitToInt #-}

digit :: Parser p => Int -> p Word
digit base = digitToInt base <$> byteSatisfy (isDigit base)
{-# INLINE digit #-}

isDigit :: Int -> Word8 -> Bool
isDigit base b
  | base <= 10 = b >= asc_0 && b <= asc_0 + fromIntegral base - 1
  | otherwise = (b >= asc_0 && b <= asc_9)
                || ((fromIntegral b :: Word) - fromIntegral asc_A) < fromIntegral (base - 10)
                || ((fromIntegral b :: Word) - fromIntegral asc_a) < fromIntegral (base - 10)
{-# INLINE isDigit #-}

signed :: (Num a, Parser p) => p a -> p a
signed p = ($) <$> ((id <$ byte asc_plus) <|> (negate <$ byte asc_minus) <|> pure id) <*> p
{-# INLINE signed #-}

fraction :: (Num a, Parser p) => p expSep -> Int -> Int -> p digitSep -> p (a, Int, a)
fraction expSep expBase coeffBasePow digitSep = do
  let coeffBase = expBase ^ coeffBasePow
  coeff <- fst <$> integer digitSep coeffBase
  (frac, fracLen) <- option (0, 0) $ byte asc_point *> integer digitSep coeffBase
  expVal <- option 0 $ expSep *> signed (fst <$> integer digitSep 10)
  pure (coeff * fromIntegral coeffBase ^ fracLen + frac,
        expBase,
        expVal - fromIntegral (fracLen * coeffBasePow))
{-# INLINE fraction #-}

fractionDec :: (Num a, Parser p) => p digitSep -> p (a, Int, a)
fractionDec = fraction (byteSatisfy (\b -> b == asc_E || b == asc_e)) 10 1
{-# INLINE fractionDec #-}

fractionHex :: (Num a, Parser p) => p digitSep -> p (a, Int, a)
fractionHex = fraction (byteSatisfy (\b -> b == asc_P || b == asc_p)) 2 4
{-# INLINE fractionHex #-}

char' :: Parser p => Char -> p Char
char' x =
  let l = C.toLower x
      u = C.toUpper x
  in satisfy (\c -> c == l || c == u)
{-# INLINE char' #-}

notChar :: Parser p => Char -> p Char
notChar c = satisfy (/= c)
{-# INLINE notChar #-}

anyChar :: Parser p => p Char
anyChar = satisfy (const True)
{-# INLINE anyChar #-}

alphaNumChar :: Parser p => p Char
alphaNumChar = satisfy C.isAlphaNum <?> "alphanumeric"
{-# INLINE alphaNumChar #-}

letterChar :: Parser p => p Char
letterChar = satisfy C.isLetter <?> "letter"
{-# INLINE letterChar #-}

digitChar :: Parser p => p Char
digitChar = unsafeChr . fromIntegral <$> digitByte
{-# INLINE digitChar #-}

string :: Parser p => Text -> p Text
string t = t <$ bytes (T.encodeUtf8 t)
{-# INLINE string #-}

asString :: Parser p => p () -> p Text
asString p = T.decodeUtf8 <$> asBytes p
{-# INLINE asString #-}
