{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE Rank2Types #-}
module Text.PariPari.Internal.Combinators (
  -- * Basic combinators
  void
  , (<|>)
  , empty

  -- * Control.Monad.Combinators.NonEmpty
  , ON.some
  , ON.endBy1
  , ON.someTill
  , ON.sepBy1
  , ON.sepEndBy1

  -- * Control.Monad.Combinators
  , O.optional -- dont use Applicative version for efficiency
  , O.many -- dont use Applicative version for efficiency
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

  -- * Labels
  , (<?>)

  -- * Position
  , getLine
  , getCol
  , withPos
  , withSpan

  -- * Indentation
  , getRefCol
  , getRefLine
  , withRefPos
  , align
  , indented
  , line
  , linefold

  -- * Char combinators
  , digitByte
  , integer
  , integer'
  , decimal
  , octal
  , hexadecimal
  , digit
  , sign
  , signed
  , fractionHex
  , fractionDec
  , char'
  , notChar
  , anyChar
  , anyAsciiByte
  , alphaNumChar
  , digitChar
  , letterChar
  , lowerChar
  , upperChar
  , symbolChar
  , categoryChar
  , punctuationChar
  , spaceChar
  , asciiChar
  , satisfy
  , asciiSatisfy
  , skipChars
  , takeChars
  , skipCharsWhile
  , takeCharsWhile
  , skipCharsWhile1
  , takeCharsWhile1
  , scanChars
  , scanChars1
  , string
) where

import Control.Applicative (optional)
import Control.Monad (when)
import Control.Monad.Combinators (option, skipCount, skipMany)
import Data.Functor (void)
import Data.Maybe (fromMaybe)
import Data.Word (Word8)
import Prelude hiding (getLine)
import Text.PariPari.Internal.Chunk
import Text.PariPari.Internal.Class
import qualified Control.Monad.Combinators as O
import qualified Control.Monad.Combinators.NonEmpty as ON
import qualified Data.Char as C

type P k a  = (forall p. Parser k p => p a)

-- | Infix alias for 'label'
(<?>) :: Parser k p => p a -> String -> p a
(<?>) = flip label
{-# INLINE (<?>) #-}
infix 0 <?>

-- | Get line number of the reference position
getRefLine :: P k Int
getRefLine = _posLine <$> getRefPos
{-# INLINE getRefLine #-}

-- | Get column number of the reference position
getRefCol :: P k Int
getRefCol = _posCol <$> getRefPos
{-# INLINE getRefCol #-}

-- | Get current line number
getLine :: P k Int
getLine = _posLine <$> getPos
{-# INLINE getLine #-}

-- | Get current column
getCol :: P k Int
getCol = _posCol <$> getPos
{-# INLINE getCol #-}

-- | Decorate the parser result with the current position
withPos :: Parser k p => p a -> p (Pos, a)
withPos p = do
  pos <- getPos
  ret <- p
  pure (pos, ret)
{-# INLINE withPos #-}

-- | Decorate the parser result with the position span
withSpan :: Parser k p => p a -> p (Pos, Pos, a)
withSpan p = do
  begin <- getPos
  ret <- p
  end <- getPos
  pure (begin, end, ret)
{-# INLINE withSpan #-}

-- | Parser succeeds on the same line as the reference line
line :: P k ()
line = do
  l <- getLine
  rl <- getRefLine
  when (l /= rl) $ failWith $ EIndentOverLine rl l
{-# INLINE line #-}

-- | Parser succeeds on the same column as the reference column
align :: P k ()
align = do
  c <- getCol
  rc <- getRefCol
  when (c /= rc) $ failWith $ EIndentNotAligned rc c
{-# INLINE align #-}

-- | Parser succeeds for columns greater than the current reference column
indented :: P k ()
indented = do
  c <- getCol
  rc <- getRefCol
  when (c <= rc) $ failWith $ ENotEnoughIndent rc c
{-# INLINE indented #-}

-- | Parser succeeds either on the reference line or
-- for columns greater than the current reference column
linefold :: P k ()
linefold = line <|> indented
{-# INLINE linefold #-}

-- | Parse a digit byte for the given base.
-- Bases 2 to 36 are supported.
digitByte :: Parser k p => Int -> p Word8
digitByte base = asciiSatisfy (isDigit base)
{-# INLINE digitByte #-}

isDigit :: Int -> Word8 -> Bool
isDigit base b
  | base >= 2 && base <= 10 = b >= asc_0 && b <= asc_0 + fromIntegral base - 1
  | base <= 36 = (b >= asc_0 && b <= asc_9)
                 || ((fromIntegral b :: Word) - fromIntegral asc_A) < fromIntegral (base - 10)
                 || ((fromIntegral b :: Word) - fromIntegral asc_a) < fromIntegral (base - 10)
  |otherwise = error "Text.PariPari.Internal.Combinators.isDigit: Bases 2 to 36 are supported"
{-# INLINE isDigit #-}

digitToInt :: Int -> Word8 -> Word
digitToInt base b
  | n <- (fromIntegral b :: Word) - fromIntegral asc_0, base <= 10 || n <= 9  = n
  | n <- (fromIntegral b :: Word) - fromIntegral asc_A, n               <= 26 = n + 10
  | n <- (fromIntegral b :: Word) - fromIntegral asc_a                        = n + 10
{-# INLINE digitToInt #-}

-- | Parse a single digit of the given base and return its value.
-- Bases 2 to 36 are supported.
digit :: Parser k p => Int -> p Word
digit base = digitToInt base <$> asciiSatisfy (isDigit base)
{-# INLINE digit #-}

-- | Parse an integer of the given base.
-- Returns the integer and the number of digits.
-- Bases 2 to 36 are supported.
-- Digits can be separated by separator, e.g. `optional (char '_')`.
-- Signs are not parsed by this combinator.
integer' :: (Num a, Parser k p) => p sep -> Int -> p (a, Int)
integer' sep base = label (integerLabel base) $ do
  d <- digit base
  accum 1 $ fromIntegral d
  where accum !i !n = next i n <|> pure (n, i)
        next !i !n = do
          void $ sep
          d <- digit base
          accum (i + 1) $ n * fromIntegral base + fromIntegral d
{-# INLINE integer' #-}

-- | Parse an integer of the given base.
-- Bases 2 to 36 are supported.
-- Digits can be separated by separator, e.g. `optional (char '_')`.
-- Signs are not parsed by this combinator.
integer :: (Num a, Parser k p) => p sep -> Int -> p a
integer sep base = label (integerLabel base) $ do
  d <- digit base
  accum $ fromIntegral d
  where accum !n = next n <|> pure n
        next !n = do
          void $ sep
          d <- digit base
          accum $ n * fromIntegral base + fromIntegral d
{-# INLINE integer #-}

integerLabel :: Int -> String
integerLabel 2  = "binary integer"
integerLabel 8  = "octal integer"
integerLabel 10 = "decimal integer"
integerLabel 16 = "hexadecimal integer"
integerLabel b  = "integer of base " <> show b

-- | Parses a decimal integer.
-- Signs are not parsed by this combinator.
decimal :: Num a => P k a
decimal = integer (pure ()) 10
{-# INLINE decimal #-}

-- | Parses an octal integer.
-- Signs are not parsed by this combinator.
octal :: Num a => P k a
octal = integer (pure ()) 8
{-# INLINE octal #-}

-- | Parses a hexadecimal integer.
-- Signs are not parsed by this combinator.
hexadecimal :: Num a => P k a
hexadecimal = integer (pure ()) 16
{-# INLINE hexadecimal #-}

-- | Parse plus or minus sign
sign :: (Parser k f, Num a) => f (a -> a)
sign = (negate <$ asciiByte asc_minus) <|> (id <$ optional (asciiByte asc_plus))
{-# INLINE sign #-}

-- | Parse a number with a plus or minus sign.
signed :: (Num a, Parser k p) => p a -> p a
signed p = ($) <$> sign <*> p
{-# INLINE signed #-}

fractionExp :: (Num a, Parser k p) => p expSep -> p digitSep -> p (Maybe a)
fractionExp expSep digitSep = do
  e <- optional expSep
  case e of
    Nothing{} -> pure Nothing
    Just{} -> Just <$> signed (integer digitSep 10)
{-# INLINE fractionExp #-}

-- | Parse a fraction of arbitrary exponent base and mantissa base.
-- 'fractionDec' and 'fractionHex' should be used instead probably.
-- Returns either an integer in 'Left' or a fraction in 'Right'.
-- Signs are not parsed by this combinator.
fraction :: (Num a, Parser k p) => p expSep -> Int -> Int -> p digitSep -> p (Either a (a, Int, a))
fraction expSep expBase mantBasePow digitSep = do
  let mantBase = expBase ^ mantBasePow
  mant <- integer digitSep mantBase
  frac <- optional $ asciiByte asc_point *> option (0, 0) (integer' digitSep mantBase)
  expn <- fractionExp expSep digitSep
  let (fracVal, fracLen) = fromMaybe (0, 0) frac
      expVal = fromMaybe 0 expn
  pure $ case (frac, expn) of
           (Nothing, Nothing) -> Left mant
           _ -> Right ( mant * fromIntegral mantBase ^ fracLen + fracVal
                      , expBase
                      , expVal - fromIntegral (fracLen * mantBasePow))
{-# INLINE fraction #-}

-- | Parse a decimal fraction, e.g., 123.456e-78, returning (mantissa, 10, exponent),
-- corresponding to mantissa * 10^exponent.
-- Digits can be separated by separator, e.g. `optional (char '_')`.
-- Signs are not parsed by this combinator.
fractionDec :: (Num a, Parser k p) => p digitSep -> p (Either a (a, Int, a))
fractionDec sep = fraction (asciiSatisfy (\b -> b == asc_E || b == asc_e)) 10 1 sep <?> "fraction"
{-# INLINE fractionDec #-}

-- | Parse a hexadecimal fraction, e.g., co.ffeep123, returning (mantissa, 2, exponent),
-- corresponding to mantissa * 2^exponent.
-- Digits can be separated by separator, e.g. `optional (char '_')`.
-- Signs are not parsed by this combinator.
fractionHex :: (Num a, Parser k p) => p digitSep -> p (Either a (a, Int, a))
fractionHex sep = fraction (asciiSatisfy (\b -> b == asc_P || b == asc_p)) 2 4 sep <?> "hexadecimal fraction"
{-# INLINE fractionHex #-}

-- | Parse a case-insensitive character
char' :: Parser k p => Char -> p Char
char' x =
  let l = C.toLower x
      u = C.toUpper x
  in satisfy (\c -> c == l || c == u)
{-# INLINE char' #-}

-- | Parse a character different from the given one.
notChar :: Parser k p => Char -> p Char
notChar c = satisfy (/= c)
{-# INLINE notChar #-}

-- | Parse an arbitrary character.
anyChar :: P k Char
anyChar = satisfy (const True)
{-# INLINE anyChar #-}

-- | Parse an arbitrary ASCII byte.
anyAsciiByte :: P k Word8
anyAsciiByte = asciiSatisfy (const True)
{-# INLINE anyAsciiByte #-}

-- | Parse an alphanumeric character, including Unicode.
alphaNumChar :: P k Char
alphaNumChar = satisfy C.isAlphaNum <?> "alphanumeric character"
{-# INLINE alphaNumChar #-}

-- | Parse a letter character, including Unicode.
letterChar :: P k Char
letterChar = satisfy C.isLetter <?> "letter"
{-# INLINE letterChar #-}

-- | Parse a lowercase letter, including Unicode.
lowerChar :: P k Char
lowerChar = satisfy C.isLower <?> "lowercase letter"
{-# INLINE lowerChar #-}

-- | Parse a uppercase letter, including Unicode.
upperChar :: P k Char
upperChar = satisfy C.isUpper <?> "uppercase letter"
{-# INLINE upperChar #-}

-- | Parse a space character, including Unicode.
spaceChar :: P k Char
spaceChar = satisfy C.isSpace <?> "space"
{-# INLINE spaceChar #-}

-- | Parse a symbol character, including Unicode.
symbolChar :: P k Char
symbolChar = satisfy C.isSymbol <?> "symbol"
{-# INLINE symbolChar #-}

-- | Parse a punctuation character, including Unicode.
punctuationChar :: P k Char
punctuationChar = satisfy C.isPunctuation <?> "punctuation"
{-# INLINE punctuationChar #-}

-- | Parse a digit character of the given base.
-- Bases 2 to 36 are supported.
digitChar :: Parser k p => Int -> p Char
digitChar base = unsafeAsciiToChar <$> digitByte base
{-# INLINE digitChar #-}

-- | Parse a character beloning to the ASCII charset (< 128)
asciiChar :: P k Char
asciiChar = unsafeAsciiToChar <$> anyAsciiByte
{-# INLINE asciiChar #-}

-- | Parse a character belonging to the given Unicode category
categoryChar :: Parser k p => C.GeneralCategory -> p Char
categoryChar cat = satisfy ((== cat) . C.generalCategory) <?> untitle (show cat)
{-# INLINE categoryChar #-}

untitle :: String -> String
untitle []     = []
untitle (x:xs) = C.toLower x : go xs
  where go [] = ""
        go (y:ys) | C.isUpper y = ' ' : C.toLower y : untitle ys
                  | otherwise   = y : ys

-- | Skip the next n characters
skipChars :: Parser k p => Int -> p ()
skipChars n = skipCount n anyChar
{-# INLINE skipChars #-}

-- | Skip char while predicate is true
skipCharsWhile :: Parser k p => (Char -> Bool) -> p ()
skipCharsWhile f = skipMany (satisfy f)
{-# INLINE skipCharsWhile #-}

-- | Skip at least one char while predicate is true
skipCharsWhile1 :: Parser k p => (Char -> Bool) -> p ()
skipCharsWhile1 f = satisfy f *> skipCharsWhile f
{-# INLINE skipCharsWhile1 #-}

-- | Take the next n characters and advance the position by n characters
takeChars :: Parser k p => Int -> p k
takeChars n = asChunk (skipChars n) <?> "string of length " <> show n
{-# INLINE takeChars #-}

-- | Take chars while predicate is true
takeCharsWhile :: Parser k p => (Char -> Bool) -> p k
takeCharsWhile f = asChunk (skipCharsWhile f)
{-# INLINE takeCharsWhile #-}

-- | Take at least one byte while predicate is true
takeCharsWhile1 :: Parser k p => (Char -> Bool) -> p k
takeCharsWhile1 f = asChunk (skipCharsWhile1 f)
{-# INLINE takeCharsWhile1 #-}

-- | Parse a single character with the given predicate
satisfy :: Parser k p => (Char -> Bool) -> p Char
satisfy f = scan $ \c -> if f c then Just c else Nothing
{-# INLINE satisfy #-}

-- | Parse a single character within the ASCII charset with the given predicate
asciiSatisfy :: Parser k p => (Word8 -> Bool) -> p Word8
asciiSatisfy f = asciiScan $ \b -> if f b then Just b else Nothing
{-# INLINE asciiSatisfy #-}

scanChars :: Parser k p => (s -> Char -> Maybe s) -> s -> p s
scanChars f = go
  where go s = (scan (f s) >>= go) <|> pure s
{-# INLINE scanChars #-}

scanChars1 :: Parser k p => (s -> Char -> Maybe s) -> s -> p s
scanChars1 f s = scan (f s) >>= scanChars f
{-# INLINE scanChars1 #-}
