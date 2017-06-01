module ParsePNG where

import qualified Data.ByteString as B
import Data.Char (ord, chr)
import Data.Word (Word8, Word32)
import Data.Bits
import System.Environment (getArgs)

main :: IO ()
main =
     do args <- getArgs
        let path = head args
        raw <- B.readFile path
        print $ runParser ((parseError :: String -> Parser ()) "I'm an error!") raw
        print $ runParser lookahead raw
        print $ runParser consumeByte raw
        print $ runParser getByte raw
        print $ runParser (byte 109) raw
        print $ runParser ((byte 109) >> (byte 122)) raw
        print $ runParser (char 'm') raw
        print $ runParser (string "module") raw
        case runParser pngParser raw of
            Left  err -> putStrLn err
            Right (png, bytesConsumed) -> do
                print png
                print $ size png
                print $ colorType png
                print bytesConsumed

----------------------------------------------------------------------
-- PNG Data Structure

data PNG = PNG
    { size :: (Word32, Word32)
    , colorType :: ColorType
    }
    deriving Show

data ColorType = Grayscale | RGB | Palette | GrayscaleAlpha | RGBAlpha
    deriving Show

data Chunk = Chunk
    { cType :: String
    , cData :: [Word8]
    }
    deriving Show

----------------------------------------------------------------------
-- Parser Infrastructure 

-- On failure, return an error message and the old state
newtype Parser a = Parser
    (ParseState -> Either (String, ParseState) (a, ParseState))

instance Functor Parser where
    fmap f (Parser p) = Parser $ \state ->
        case p state of
             Left  x           -> Left x
             Right (x, state') -> Right (f x, state')

instance Applicative Parser where
    pure x = Parser $ \state -> Right (x, state)
    (Parser p) <*> (Parser q) = Parser $ \state ->
        case p state of
            Left  x           -> Left x
            Right (f, state') ->
                case q state' of
                    Left  x            -> Left  x
                    Right (x, state'') -> Right (f x, state'')

instance Monad Parser where
    (Parser p) >>= f = Parser $ \state ->
        case p state of Left x -> Left x
                        Right (x, state') -> let (Parser q) = f x in q state'

runParser :: Parser a -> B.ByteString -> Either String (a, Int)
runParser (Parser parser) bytes =
    case parser init of
        Left  (err, state) -> Left $ errMsg err state
        Right (x, state)   -> Right (x, B.length (remainder state))
    where
        init = ParseState bytes 0
        errMsg err state = err ++ " at byte " ++ show (bytesConsumed state)

data ParseState = ParseState
    {  remainder                :: B.ByteString
    ,  bytesConsumed            :: Word
    }

----------------------------------------------------------------------
-- Parsers

pngParser :: Parser PNG
pngParser = do header
               readWord32
               string "IHDR"
               width <- readWord32
               height <- readWord32
               _bitDepth <- readWord8
               tempColorType <- colorTypeP
               return $ PNG (width, height) tempColorType

header :: Parser ()
header  = do byte 0x89; string "PNG"; cr; lf; ctrlZ; lf

colorTypeP :: Parser ColorType
colorTypeP = do byte <- lookahead
                case byte of
                    0 -> return Grayscale
                    2 -> return RGB
                    3 -> return Palette
                    4 -> return GrayscaleAlpha
                    6 -> return RGBAlpha
                    _ -> parseError $ "Bad colorType byte " ++ show byte


chunk :: Parser Chunk
chunk   = do length <- readWord32
             chunkType <- readASCIIString 4
             chunkData <- readWord8String $ word32ToInt length
             readWord8String 4
             return (Chunk chunkType chunkData)

parseError :: String -> Parser a
parseError message = Parser $ \state -> Left (message, state)

lookahead :: Parser Word8
lookahead = Parser $ \state ->
    if B.null (remainder state)
        then Left  ("No bytes left to parse", state)
        else Right (B.head (remainder state), state)

consumeByte :: Parser ()
consumeByte = Parser $ \state ->
    if B.null (remainder state)
        then Left  ("No bytes left to parse", state)
        else Right ((),
                ParseState (B.tail$ remainder state) (bytesConsumed state + 1))

getByte = do b <- lookahead
             consumeByte
             return b

byte :: Word8 -> Parser ()
byte b = do b' <- lookahead
            if b == b' then consumeByte
                       else parseError $
                           "expected " ++ show b ++ " got " ++ show b'

readWord8 :: Parser Word8
readWord8 = do b <- lookahead
               consumeByte
               return b

word8sToWord32 :: [Word8] -> Word32
word8sToWord32 = foldl accum 0
  where
    accum a o = (a `shiftL` 8) .|. fromIntegral o

readWord32 :: Parser Word32
readWord32 = fmap word8sToWord32 parserOfList
    where listOfParser = take 4 (repeat readWord8)
          parserOfList = sequence listOfParser

readWord8String :: Int -> Parser [Word8]
readWord8String len = sequence (take len (repeat readWord8))

word8ToChar :: Word8 -> Char
word8ToChar = chr.fromIntegral.toInteger

word32ToInt :: Word32 -> Int
word32ToInt = fromIntegral.toInteger

readASCIIString :: Int -> Parser String
readASCIIString len = fmap (map word8ToChar) (readWord8String len)

char    :: Char -> Parser ()
char    = byte.fromIntegral.ord

string :: String -> Parser ()
string  = mapM_ char

cr      = byte 0x0d
lf      = byte 0x0a
ctrlZ   = byte 0x1a
