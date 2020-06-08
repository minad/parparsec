{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FunctionalDependencies #-}
module Text.PariPari.Internal.Class (
  ChunkParser(..)
  , CharParser(..)
  , Alternative(..)
  , MonadPlus
  , Pos(..)
  , Error(..)
  , showError
  , expectedEnd
  , unexpectedEnd
  , string
) where

import Control.Applicative (Alternative(empty, (<|>)))
import Control.Monad (MonadPlus(..))
import Control.Monad.Fail (MonadFail(..))
import Data.List (intercalate)
import Data.Semigroup ((<>))
import Data.String (IsString)
import Data.Word (Word8)
import GHC.Generics (Generic)
import Text.PariPari.Internal.Chunk

-- | Parsing errors
data Error
  = EInvalidUtf8
  | EExpected         [String]
  | EUnexpected       String
  | EFail             String
  | EIndentNotAligned !Int !Int
  | EIndentOverLine   !Int !Int
  | ENotEnoughIndent  !Int !Int
  deriving (Eq, Ord, Show, Generic)

-- | Parser class, which specifies the necessary
-- primitives for parsing. All other parser combinators
-- rely on these primitives.
class (MonadFail p, MonadPlus p, Chunk k) => ChunkParser k p | p -> k where
  -- | Get file name associated with current parser
  getFile :: p FilePath

  -- | Get current position of the parser
  getPos :: p Pos

  -- | Get reference position used for indentation-sensitive parsing
  getRefPos :: p Pos

  -- | Update reference position with current position
  withRefPos :: p a -> p a

  -- | Parser which succeeds when the given parser fails
  notFollowedBy :: Show a => p a -> p ()

  -- | Look ahead and return result of the given parser
  -- The current position stays the same.
  lookAhead :: p a -> p a

  -- | Parser failure with detailled 'Error'
  failWith :: Error -> p a

  -- | Parser which succeeds at the end of file
  eof :: p ()

  -- | Annotate the given parser with a label used for error reporting.
  --
  -- __Note__: This function has zero cost in the 'Acceptor'. You can
  -- use it to improve the error reports without slowing
  -- down the fast path of your parser.
  label :: String -> p a -> p a

  -- | Hide errors occurring within the given parser
  -- from the error report. Based on the given
  -- labels an 'Error' is constructed instead.
  --
  -- __Note__: This function has zero cost in the 'Acceptor'. You can
  -- use it to improve the error reports without slowing
  -- down the fast path of your parser.
  hidden :: p a -> p a

  -- | Commit to the given branch, increasing
  -- the priority of the errors within this branch
  -- in contrast to other branches.
  --
  -- This is basically the opposite of the `try`
  -- combinator provided by other parser combinator
  -- libraries, which decreases the error priority
  -- within the given branch (and usually also influences backtracking).
  --
  -- `commit` only applies to the reported
  -- errors, it has no effect on the backtracking behavior
  -- of the parser.
  --
  -- __Note__: This function has zero cost in the 'Acceptor'. You can
  -- use it to improve the error reports without slowing
  -- down the fast path of your parser.
  commit :: p a -> p a

  -- | Parse with error recovery.
  -- If the parser p fails in `recover p r`
  -- the parser r continues at the position where p failed.
  -- If the recovering parser r fails too, the whole
  -- parser fails. The errors reported by the recovering
  -- parser are ignored in any case.
  -- Error recovery support is only available
  -- in the 'Reporter' instance.
  --
  -- __Note__: This function has zero cost in the 'Acceptor'. You can
  -- use it to improve the error reports without slowing
  -- down the fast path of your parser.
  recover :: p a -> p a -> p a

  -- | Parse a single element
  element :: Element k -> p (Element k)

  -- | Scan a single element
  elementScan :: (Element k -> Maybe a) -> p a

  -- | Parse a chunk of elements. The chunk must not
  -- contain multiple lines, otherwise the position information
  -- will be invalid.
  chunk :: k -> p k

  -- | Run the given parser and return the
  -- result as buffer
  asChunk :: p () -> p k

class (ChunkParser k p, IsString (p k), CharChunk k) => CharParser k p | p -> k where
  -- | Parse a single character
  --
  -- __Note__: The character '\0' cannot be parsed using this combinator
  -- since it is used as decoding sentinel. Use 'element' instead.
  char :: Char -> p Char

  -- | Scan a single character
  --
  -- __Note__: The character '\0' cannot be parsed using this combinator
  -- since it is used as decoding sentinel. Use 'elementScan' instead.
  scan :: (Char -> Maybe a) -> p a

  -- | Parse a single character within the ASCII charset
  --
  -- __Note__: The character '\0' cannot be parsed using this combinator
  -- since it is used as decoding sentinel. Use 'element' instead.
  asciiByte :: Word8 -> p Word8

  -- | Scan a single character within the ASCII charset
  --
  -- __Note__: The character '\0' cannot be parsed using this combinator
  -- since it is used as decoding sentinel. Use 'elementScan' instead.
  asciiScan :: (Word8 -> Maybe a) -> p a

-- | Pretty string representation of 'Error'
showError :: Error -> String
showError EInvalidUtf8             = "Invalid UTF-8 character found"
showError (EExpected tokens)       = "Expected " <> intercalate ", " tokens
showError (EUnexpected token)      = "Unexpected " <> token
showError (EFail msg)              = msg
showError (EIndentNotAligned rc c) = "Invalid alignment, expected column " <> show rc <> " expected, got " <> show c
showError (EIndentOverLine   rl l) = "Indentation over line, expected line " <> show rl <> ", got " <> show l
showError (ENotEnoughIndent  rc c) = "Must be indented deeper than column " <> show rc <> ", got column " <> show c

expectedEnd :: Error
expectedEnd = EExpected ["end of file"]

unexpectedEnd :: Error
unexpectedEnd = EUnexpected "end of file"

-- | Parse a string
string :: CharParser k p => String -> p k
string t = chunk (stringToChunk t)
{-# INLINE string #-}
