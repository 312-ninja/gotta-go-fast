module GottaGoFast where

import Data.List (isPrefixOf)
import Data.Maybe (isJust, fromJust)
import Data.Time (UTCTime, diffUTCTime)

-- It is often useful to know whether the line / character etc we are
-- considering is "BeforeCursor" or "AfterCursor". More granularity turns out
-- to be unnecessary.
data Position = BeforeCursor | AfterCursor

data State = State
  { target  :: String
  , input   :: String
  , start   :: Maybe UTCTime
  , end     :: Maybe UTCTime
  , strokes :: Integer
  , hits    :: Integer
  }

-- For ease of rendering a character in the UI, we tag it as a Hit, Miss, or
-- Empty. Corresponding to the cases of being correctly typed, incorrectly
-- typed (or skipped), or not yet typed.
data Character = Hit Char | Miss Char | Empty Char
type Line = [Character]
type Page = [Line]

startClock :: UTCTime -> State -> State
startClock now s = s { start = Just now }

stopClock :: UTCTime -> State -> State
stopClock now s = s { end = Just now }

hasStarted :: State -> Bool
hasStarted = isJust . start

hasEnded :: State -> Bool
hasEnded = isJust . end

cursorCol :: State -> Int
cursorCol = length . takeWhile (/= '\n') . reverse . input

cursorRow :: State -> Int
cursorRow = length . filter (== '\n') . input

cursor :: State -> (Int, Int)
cursor s = (cursorCol s, cursorRow s)

onLastLine :: State -> Bool
onLastLine s = cursorRow s + 1 == length (lines $ target s)

isHit :: State -> Char -> Bool
isHit s c = (input s ++ [c]) `isPrefixOf` target s

applyChar :: Char -> State -> State
applyChar c s = s
  { input = input s ++ [c]
  , strokes = strokes s + 1
  , hits = hits s + if isHit s c then 1 else 0
  }

applyEnter :: State -> State
applyEnter s = s' { input = input s' ++ leadingSpaces }
  where
    s' = applyChar '\n' s
    leadingSpaces = replicate n ' '
    n = length $ takeWhile (== ' ') $ lines (target s') !! cursorRow s'

backspace :: String -> String
backspace "" = ""
backspace xs = init xs

applyBackspace :: State -> State
applyBackspace s = s {input = backspace $ input s}

backspaceWord :: String -> String
backspaceWord xs = reverse $ dropWhile (/= ' ') $ reverse $ backspace xs

applyBackspaceWord :: State -> State
applyBackspaceWord s = s { input = backspaceWord $ input s }

initialState :: String -> State
initialState t = State
  { target = t
  , input = ""
  , start = Nothing
  , end = Nothing
  , strokes = 0
  , hits = 0
  }

character :: Position -> (Maybe Char, Maybe Char) -> Character
character _ (Just t, Just i)
  | t == i = Hit t
  | t /= i = Miss t
character _ (Nothing, Just i) = Miss i
character BeforeCursor (Just t, Nothing) = Miss t
character AfterCursor (Just t, Nothing) = Empty t

line :: Position -> (String, String) -> Line
line _ ("", "") = []
line p (ts, is) = map (character p) charPairs
  where
    charPairs = take maxLen $ zip (nothingsForever ts) (nothingsForever is)
    nothingsForever x = map Just x ++ repeat Nothing
    maxLen = max (length ts) (length is)

page :: State -> Page
page s = linesBeforeCursor ++ linesAfterCursor
  where
    linesBeforeCursor = map (line BeforeCursor) $ take (cursorRow s) linePairs
    linesAfterCursor = map (line AfterCursor) $ drop (cursorRow s) linePairs
    linePairs = zip (lines $ target s) (lines (input s) ++ repeat "")

-- The following functions are only safe to use when both hasStarted and
-- hasEnded hold.

seconds :: State -> Rational
seconds s = toRational $ diffUTCTime (fromJust $ end s) (fromJust $ start s)

wpm :: State -> Rational
wpm s = fromIntegral (length $ target s) / (5 * seconds s / 60)

accuracy :: State -> Rational
accuracy s = fromIntegral (hits s) / fromIntegral (strokes s)
