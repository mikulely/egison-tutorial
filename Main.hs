module Main where

import Prelude hiding (catch)
import Control.Exception ( SomeException(..),
                           AsyncException(..),
                           catch, handle, throw)
import System.Posix.Signals
import Control.Concurrent

import Control.Applicative ((<$>), (<*>))
import Control.Monad.Error

import Data.Version
import Data.List
import Data.ByteString.Lazy (ByteString)
import Data.ByteString.Lazy.Char8 ()
import qualified Data.ByteString.Lazy.Char8 as B
import Text.Parsec
import Text.Parsec.ByteString.Lazy
import Text.Regex.Posix

import System.IO
import System.Environment
import System.Directory (getHomeDirectory)
import System.FilePath ((</>))
import System.Console.Haskeline hiding (handle, catch, throwTo)
import System.Console.GetOpt
import System.Exit (ExitCode (..), exitWith, exitFailure)
import Language.Egison
import qualified Paths_egison_tutorial as P

main :: IO ()
main = do args <- getArgs
          let (actions, nonOpts, _) = getOpt Permute options args
          let opts = foldl (flip id) defaultOptions actions
          case opts of
            Options {optShowHelp = True} -> printHelp
            Options {optShowVersion = True} -> printVersionNumber
            Options {optPrompt = prompt} -> do
                env <- primitiveEnv >>= loadLibraries
                case nonOpts of
                    [] -> showBanner >> repl env prompt
                    _ -> printHelp

data Options = Options {
    optShowVersion :: Bool,
    optShowHelp :: Bool,
    optPrompt :: String
    }

defaultOptions :: Options
defaultOptions = Options {
    optShowVersion = False,
    optShowHelp = False,
    optPrompt = "> "
    }

options :: [OptDescr (Options -> Options)]
options = [
  Option ['v', 'V'] ["version"]
    (NoArg (\opts -> opts {optShowVersion = True}))
    "show version number",
  Option ['h', '?'] ["help"]
    (NoArg (\opts -> opts {optShowHelp = True}))
    "show usage information",
  Option ['p'] ["prompt"]
    (ReqArg (\prompt opts -> opts {optPrompt = prompt})
            "String")
    "set prompt string"
  ]

printHelp :: IO ()
printHelp = do
  putStrLn "Usage: egison-tutorial [options]"
  putStrLn ""
  putStrLn "Options:"
  putStrLn "  --help                Display this information"
  putStrLn "  --version             Display egison version information"
  putStrLn "  --prompt string       Set prompt of the interpreter"
  putStrLn ""
  exitWith ExitSuccess

printVersionNumber :: IO ()
printVersionNumber = do
  putStrLn $ showVersion P.version 
  exitWith ExitSuccess

showBanner :: IO ()
showBanner = do
  putStrLn $ "Egison Tutorial for Version " ++ showVersion P.version ++ " (C) 2013-2014 Satoshi Egi"
  putStrLn $ "http://www.egison.org"
  putStrLn $ "Welcome to Egison Tutorial!"

showFinishMessage :: IO ()
showFinishMessage = do
  putStrLn $ "You have finished this section."
  putStrLn $ "Thank you!"

showByebyeMessage :: IO ()
showByebyeMessage = do
  putStrLn $ "Leaving Egison Tutorial.\nByebye."

askUser :: String -> IO Bool
askUser question = do
  putStr $ question
  putStr $ " (Y/n): "
  hFlush stdout
  input <- getLine
  case input of
   [] -> return True
   ('y':_) -> return True
   ('Y':_) -> return True
   ('n':_) -> return False
   _ -> askUser question

selectSection :: Tutorial -> IO [Content]
selectSection tutorial  = selectSectionHelper [] tutorial

selectSectionHelper :: [(Int, String)] -> Tutorial -> IO [Content]
selectSectionHelper hs (Sections secs)  = do
  putStrLn "===================="
  putStrLn "List of tutorials."
  foldM (\x sec -> do
          putStr $ "" ++ show x ++ ": "
          putStrLn (fst sec)
          return (x + 1))
        1 secs
  putStrLn "===================="
  let m = length secs
  n <- readNumber m
  let (title, t) = head $ drop (n - 1) secs
  case t of
    Contents contents -> return contents
    Sections _ -> selectSectionHelper (hs ++ [(n, title)]) t

readNumber :: Int -> IO Int
readNumber m = do
  putStr $ "Please select a section to learn.\n(1-" ++ show m ++ "): "
  hFlush stdout
  input <- getLine
--  let n = (read input :: Int)
  case input of
    ('1':_) -> return 1
    ('2':_) -> return 2
    ('3':_) -> return 3
    ('4':_) -> return 4
    ('5':_) -> return 5
    ('6':_) -> return 6
    ('7':_) -> return 7
    ('8':_) -> return 8
    _ -> do
      putStrLn "Invalid input!"
      readNumber m


printTutorial :: Content -> IO ()
printTutorial (msg, examples) = do
  putStrLn "===================="
  putStrLn msg
  case examples of
    [] -> return ()
    _ -> do
      putStrLn "e.g."
      mapM_ (\example -> do
                putStr "  "
                putStrLn example)
        examples
  putStrLn "===================="

onAbort :: EgisonError -> IO (Either EgisonError a)
onAbort e = do
  let x = show e
  return $ Left e

repl :: Env -> String -> IO ()
repl env prompt = do
  home <- getHomeDirectory
  contents <- selectSection tutorial
  liftIO (runInputT (settings home) $ loop env prompt "" contents True)
  where
    settings :: MonadIO m => FilePath -> Settings m
    settings home = do
      setComplete completeParen $ defaultSettings { historyFile = Just (home </> ".egison_tutorial_history") }
    
    loop :: Env -> String -> String -> [Content] -> Bool -> InputT IO ()
    loop env prompt' _ [] _ = do
      liftIO $ showFinishMessage
      contents <- liftIO $ selectSection tutorial
      loop env prompt' "" contents True
    loop env prompt' rest ts@(t:rs) True = do
      liftIO $ printTutorial t
      loop env prompt' rest ts False
    loop env prompt' rest ts@(t:rs) False = do
      _ <- liftIO $ installHandler keyboardSignal (Catch (do {putStr "^C"; hFlush stdout})) Nothing
      input <- getInputLine prompt'
      tid <- liftIO $ myThreadId
      _ <- liftIO $ installHandler keyboardSignal (Catch (throwTo tid UserInterruption)) Nothing
      case input of
        Nothing -> do
          response1 <- liftIO $ askUser "Do you want to proceed next?"
          case response1 of
            True -> loop env prompt' rest rs True
            False -> do
              response2 <- liftIO $ askUser "Do you want to quit egison-tutorial?"
              case response2 of
                True -> do
                  liftIO $ showByebyeMessage
                  return ()
                False -> loop env prompt' rest ts False
        Just "quit" -> do
          liftIO $ showByebyeMessage
          return () 
        Just "" ->
          case rest of
            "" -> do
              response1 <- liftIO $ askUser "Do you want to proceed next?"
              case response1 of
                True -> loop env prompt' rest rs True
                False -> loop env prompt' rest ts False
            _ -> loop env (take (length prompt) (repeat ' ')) rest ts False
        Just input' -> do
          let newInput = rest ++ input'
          result <- liftIO $ handle onAbort $ runEgisonTopExpr env newInput
          case result of
            Left err | show err =~ "unexpected end of input" -> do
              loop env (take (length prompt) (repeat ' ')) (newInput ++ "\n") ts False
            Left err | show err =~ "expecting (top-level|\"define\")" -> do
              result <- liftIO $ handle onAbort $ fromEgisonM (readExpr newInput) >>= either (return . Left) (evalEgisonExpr env)
              case result of
                Left err | show err =~ "unexpected end of input" -> do
                  loop env (take (length prompt) (repeat ' ')) (newInput ++ "\n") ts False
                Left err -> do
                  liftIO $ putStrLn $ show err
                  loop env prompt "" ts False
                Right val -> do
                  liftIO $ putStrLn $ show val
                  loop env prompt "" ts False
            Left err -> do
              liftIO $ putStrLn $ show err
              loop env prompt "" ts False
            Right env' ->
              loop env' prompt "" ts False

completeParen :: Monad m => CompletionFunc m
completeParen arg@((')':_), _) = completeParen' arg
completeParen arg@(('>':_), _) = completeParen' arg
completeParen arg@((']':_), _) = completeParen' arg
completeParen arg@(('}':_), _) = completeParen' arg
completeParen arg@(('(':_), _) = (completeWord Nothing " \t<>[]{}$," completeAfterOpenParen) arg
completeParen arg@(('<':_), _) = (completeWord Nothing " \t()[]{}$," completeAfterOpenCons) arg
completeParen arg@((' ':_), _) = (completeWord Nothing "" completeNothing) arg
completeParen arg@([], _) = (completeWord Nothing "" completeNothing) arg
completeParen arg@(_, _) = (completeWord Nothing " \t[]{}$," completeEgisonKeyword) arg

completeAfterOpenParen :: Monad m => String -> m [Completion]
completeAfterOpenParen str = return $ map (\kwd -> Completion kwd kwd False) $ filter (isPrefixOf str) egisonKeywordsAfterOpenParen

completeAfterOpenCons :: Monad m => String -> m [Completion]
completeAfterOpenCons str = return $ map (\kwd -> Completion kwd kwd False) $ filter (isPrefixOf str) egisonKeywordsAfterOpenCons

completeNothing :: Monad m => String -> m [Completion]
completeNothing _ = return []

completeEgisonKeyword :: Monad m => String -> m [Completion]
completeEgisonKeyword str = return $ map (\kwd -> Completion kwd kwd False) $ filter (isPrefixOf str) egisonKeywords

egisonKeywordsAfterOpenParen = map ((:) '(') $ ["define", "let", "letrec", "do", "lambda", "match-lambda", "match", "match-all", "pattern-function", "matcher", "algebraic-data-matcher", "if", "loop", "io"]
                            ++ ["id", "or", "and", "not", "char", "eq?/m", "compose", "compose3", "list", "map", "between", "repeat1", "repeat", "filter", "separate", "concat", "foldr", "foldl", "map2", "zip", "empty?", "member?", "member?/m", "include?", "include?/m", "any", "all", "length", "count", "count/m", "car", "cdr", "rac", "rdc", "nth", "take", "drop", "while", "reverse", "multiset", "add", "add/m", "delete-first", "delete-first/m", "delete", "delete/m", "difference", "difference/m", "union", "union/m", "intersect", "intersect/m", "set", "unique", "unique/m", "simple-select", "print", "print-to-port", "each", "pure-rand", "fib", "fact", "divisor?", "gcd", "primes", "find-factor", "prime-factorization", "p-f", "pfs", "pfs-n", "min", "max", "min-and-max", "power", "mod", "float", "ordering", "qsort", "intersperse", "intercalate", "split", "split/m"]
egisonKeywordsAfterOpenCons = map ((:) '<') ["nil", "cons", "join", "snoc", "nioj"]
egisonKeywordsInNeutral = ["something"]
                       ++ ["bool", "string", "integer", "nat", "nats", "nats0"]
egisonKeywords = egisonKeywordsAfterOpenParen ++ egisonKeywordsAfterOpenCons ++ egisonKeywordsInNeutral

completeParen' :: Monad m => CompletionFunc m
completeParen' (lstr, _) = case (closeParen lstr) of
                             Nothing -> return (lstr, [])
                             Just paren -> return (lstr, [(Completion paren paren False)])

closeParen :: String -> Maybe String
closeParen str = closeParen' 0 $ removeCharAndStringLiteral str

removeCharAndStringLiteral :: String -> String
removeCharAndStringLiteral [] = []
removeCharAndStringLiteral ('"':'\\':str) = '"':'\\':(removeCharAndStringLiteral str)
removeCharAndStringLiteral ('"':str) = removeCharAndStringLiteral' str
removeCharAndStringLiteral ('\'':'\\':str) = '\'':'\\':(removeCharAndStringLiteral str)
removeCharAndStringLiteral ('\'':str) = removeCharAndStringLiteral' str
removeCharAndStringLiteral (c:str) = c:(removeCharAndStringLiteral str)

removeCharAndStringLiteral' :: String -> String
removeCharAndStringLiteral' [] = []
removeCharAndStringLiteral' ('"':'\\':str) = removeCharAndStringLiteral' str
removeCharAndStringLiteral' ('"':str) = removeCharAndStringLiteral str
removeCharAndStringLiteral' ('\'':'\\':str) = removeCharAndStringLiteral' str
removeCharAndStringLiteral' ('\'':str) = removeCharAndStringLiteral str
removeCharAndStringLiteral' (_:str) = removeCharAndStringLiteral' str

closeParen' :: Integer -> String -> Maybe String
closeParen' _ [] = Nothing
closeParen' 0 ('(':_) = Just ")"
closeParen' 0 ('<':_) = Just ">"
closeParen' 0 ('[':_) = Just "]"
closeParen' 0 ('{':_) = Just "}"
closeParen' n ('(':str) = closeParen' (n - 1) str
closeParen' n ('<':str) = closeParen' (n - 1) str
closeParen' n ('[':str) = closeParen' (n - 1) str
closeParen' n ('{':str) = closeParen' (n - 1) str
closeParen' n (')':str) = closeParen' (n + 1) str
closeParen' n ('>':str) = closeParen' (n + 1) str
closeParen' n (']':str) = closeParen' (n + 1) str
closeParen' n ('}':str) = closeParen' (n + 1) str
closeParen' n (_:str) = closeParen' n str
              
data Tutorial =
    Sections [(String, Tutorial)]
  | Contents [Content]

type Content = (String, [String]) 

tutorial :: Tutorial
tutorial =
  Sections [
    ("Lv1 - Calculate numbers",
     Contents [
       ("We can do arithmetic operations with `+', '-', '*'.", ["(+ 1 2)", "(* 10 20)"]),
       ("We can write nested expression as follow.", ["(+ (* 10 20) 2)", "(/ (* 10 20) (+ 10 20))"]),
       ("We are supporting rational numbers.", ["(+ 2/3 1/5)", "(/ 42 84)"]),
       ("We are supporting floats, too.", ["(+ 10.2 1.3)", "(* 10.2 1.3)"]),
       ("you can convert a rational number to a float number with 'rtof'.", ["(rtof 1/5)"]),
       ("We can handle collections of numbers.\n We construct then with '{}'.", ["{}", "{10}","{1 2 3 4 5}"]),
       ("With a 'take' function, we can extract a head part of the collection.\nWe can construct a collection with '{}'.", ["(take 0 {1 2 3 4 5})", "(take 3 {1 2 3 4 5})"]),
       ("We can handle infinite lists.\nFor example, 'nats' is an infinite list that contains all natural numbers.\nGet a collection of natural numbers of any length you like.", ["(take 100 nats)"]),
       ("With a 'map' function, we can operate each element of the collection at onece.", ["(map (* $ 2) (take 100 nats))", "(take 100 (map (* $ 2) nats))", "(take 100 (map (modulo $ 3) nats))"]),
       ("We can create a \"partial\" function using '$' as an argument.", ["((+ $ 10) 1)"]),
       ("With a 'foldl' function, we can gather together all elements of the collection using an operator you like.\nWould you try to get a sum of from 1 to 100?", ["(foldl + 0 {1 2 3 4 5})", "(foldl * 1 {1 2 3 4 5})"]),
       ("Try to create a sequce of numbers '{1 1/2 1/3 1/4 ... 1/100}'.", []),
       ("Try to calculate '1 + 1/2 + 1/3 + 1/4 + ... + 1/100'.\nPlease remember that you can convert a rational number to a float number with 'rtof'.", ["(rtof 2/3)"]),
       ("Try to calculate '1 + (1/2)^2 + (1/3)^2 + (1/4)^2 + ... + (1/100)^2'.", [])
       ]),
    ("Lv2 - Basics of functional programming",
     Contents [
       ("We can compare numbers using functions that return '#t' or '#f'.\n'#t' means the true.\n#f means the false.\nFunctions that return '#t' or '#f' are called \"predicates\".", ["(eq? 1 1)", "(gt? 1 1)", "(lt? 1 1)",  "(gte? 1 1)", "(lte? 1 1)"]),
       ("With a 'while' function, we can extract all head elements that satisfy the predicate.\n'primes' is a infinites list that contains all prime numbers.", ["(while (lt? $ 100) primes)", "(while (lt? $ 1000) primes)"]),
       ("With a 'filter' function, we can extract all elements that satisfy the predicate.\n'We extract all prime numbers that are congruent to 1 modulo 4.", ["(take 100 (filter (lambda [$p] (eq? (modulo p 4) 1)) primes))", "(take 200 (filter (lambda [$p] (eq? (modulo p 4) 1)) primes))"]),
       ("We use 'lambda' expressions to create functions.\n Here are simple 'lambda' examples.", ["((lambda [$x] (+ x 1)) 10)", "((lambda [$x] (* x x)) 10)", "((lambda [$x $y] (* x y)) 10 20)"]),
       ("With a 'map2' function, we can combine two lists as follow.", ["(take 100 (map2 * nats nats))", "(take 100 (map2 (lambda [$n $p] [n p]) nats primes))"]),
       ("We combine numbers using '[]'.\nThese things are called 'tuples'.", ["[1 2]", "[1 2 3]"]),
       ("Please not that a tuple that consists of only one elment is equal with that element itself.", ["[1]", "[[[1]]]"]),
       ("Try to create a sequce of tuples '{[1 1] [1 2] [1 3] [1 4] [1 5] [1 6] [1 7] [1 8] [1 9]}'.", []),
       ("Try to create a collections of sequce of tuples as follow.\n{{[1 1] [1 2] ... [1 9]}\n {[2 1] [2 2] ... [2 9]}\n ...\n {[9 1] [9 2] ... [9 9]}}", []),
       ("Try to create the multiplication table.\n{{[[1 1 1] [1 2 2] ... [1 9 9]}\n {[2 1 2] [2 2 4] ... [2 9 18]}\n ...\n {[9 1 9] [9 2 18] ... [9 9 81]}}", [])
       ]),
    ("Lv3 - Define your own functions",
     Contents [
       ("We can bind a value to a variable with a 'define' expression.\nWe can easily get the value we binded to the variable.", ["(define $x 10)", "x"]),
       ("We can define a function. Let's define a function and test it.", ["(define $f (lambda [$x] (+ x 1)))", "(f 10)", "(define $g (lambda [$x $y] (* x y)))", "(g 10 20)"]),
       ("We can write a recursive definition. Let's try that.", ["(define $odds {1 @(map (+ $ 2) odds)})", "(take 10 odds)"]),
       ("Try to define 'evens' referring to 'odds' example above.", []),
       ("We can define local variables with a 'let' expression.", ["(let {[$x 10] [$y 20]} (+ x y))"]),
       ("Let's try 'if' expressions.", ["(if #t 1 2)", "(let {[$x 10]} (if (eq? x 10) 1 2))"]),
       ("Using 'define' and 'if', we can write recursive functions as follow.", ["(define $your-take (lambda [$n $xs] (if (eq? n 0) {} {(car xs) @(your-take (- n 1) (cdr xs))})))", "(your-take 10 nats)"]),
       ("Try to write a 'your-map' function.\nWe may need 'empty?' function inside 'your-map' function.", ["(empty? {})"]),
       ("We can view all library functions on collections at \"http://www.egison.org/libraries/core/collection.html\".", [])
       ]),
    ("Lv4 - Basic of pattern-matching",
     Contents [
       ("We can do pattern-matching against multisets.", ["(match-all {1 2 3} (multiset integer) [<cons $x $xs> [x xs]])"]),
       ("We can do non-linear pattern-matching.\nTry the following expression with various targets.", ["(match-all {1 2 1 3} (multiset integer) [<cons $x <cons ,x _>> x])"]),
       ("We can change the way of pattern-matching by changing \"matcher\".\nTry the following expressions.", ["(match-all {1 2 3} (list integer) [<cons $x $xs> [x xs]])", "(match-all {1 2 3} (multiset integer) [<cons $x $xs> [x xs]])", "(match-all {1 2 3} (set integer) [<cons $x $xs> [x xs]])"]),
       ("We can do pattern-matching against a collection of collections as follow.", ["(match-all {{1 2 3 4 5} {4 5 1} {6 1 7 4}} (list (multiset integer)) [<cons <cons $n _> <cons <cons ,n _> <cons <cons ,n _> _>>> n])"]),
       ("A pattern that has '^' ahead of which is called a not-pattern.\nA not-pattern matches when the target does not match against the pattern.", ["(match-all {1 2 1 3} (multiset integer) [<cons $x ^<cons ,x _>> x])"]),
       ("An and-pattern matches when the all patterns matches the target.\nIt can be used like an as-pattern.", ["(match-all {1 2 1 3} (multiset integer) [<cons $x (& ^<cons ,x _> $xs)> [x xs]])"]),
       ("An or-pattern matches when one of the patterns matches the target.", ["(match-all {1 2 1 3} (multiset integer) [<cons $x (| <cons ,x _> ^<cons ,x _>)> x])"]),
       ("'list' has a special pattern-constructor 'join'.\n'join' divides a collection into two collections.\nTry the following expressions.", ["(match-all {1 2 3 4 5} (list integer) [<join $xs $ys> [xs ys]])"]),
       ("We can enumerate two combination of numbers as follow.\nTry to enumerate three combination of numbers.", ["(match-all {1 2 3 4 5} (list integer) [<join _ <cons $x <join _ <cons $y _>>>> [x y]])"]),
       ("Did we think how about \"n\" comination of the elements of the collection?\nWe already have a solution.\nWe can write a pattern that include '...' as the following demonstrations.", ["(match-all {1 2 3 4 5} (list integer) [(loop $i [1 ,4] <join _ <cons $a_i ...>> _) a])", "(match-all {1 2 3 4 5} (list integer) [(loop $i [1 ,5] <join _ <cons $a_i ...>> _) a])", "(match-all {1 2 3 4 5} (list integer) [(loop $i [1 $n] <join _ <cons $a_i ...>> _) [n a]])"]),
       ("We can view a lot of demonstration of pattern-matching at \"http://www.egison.org/demonstrations/\".", [])
       ]),
    ("Lv5 - Pattern-matching against infinite collections",
     Contents [
       ("We can write a pattern-matching against infinite lists even if that has infinite results.\nPlease note that Egison really enumurate all pairs of two natural numbers in the following example.", ["(take 10 (match-all nats (set integer) [<cons $m <cons $n _>> [m n]]))"]),
       ("We can enumerate all two combinations of natural numbers as follow.", ["(define $two-combs (match-all nats (list integer) [<join _ (& <cons $x _> <join _ <cons $y _>>)> [x y]]))", "(take 100 two-combs)"]),
       ("We can enumerate all pythagoras numbers as follow.", ["(define $pyths (map (lambda [$x $y] (+ (* x x) (* y y))) two-combs))", "(take 100 pyths)"]),
       ("We have an infinite list of prime numers in 'primes'.\nPlease check it with a 'take' function.", ["(take 10 primes)"]),
       ("We can get twin primes or triplet primes using pattern-matching as follow.", ["(take 10 (match-all primes (list integer) [<join _ <cons $n <cons ,(+ n 2) _>>> [n (+ n 2)]]))", "(take 10 (match-all primes (list integer) [<join _ <cons $n <cons ,(+ n 2) <cons ,(+ n 6) _>>>> [n (+ n 2) (+ n 6)]]))", "(take 10 (match-all primes (list integer) [<join _ <cons $n <cons ,(+ n 4) <cons ,(+ n 6) _>>>> [n (+ n 2) (+ n 6)]]))"]),
       ("We can enumurate all common elements between 'primes' and 'pyths' as follow.\nCan we find a pattern in these numbers.", ["(match-all [(take 100 pyths) (take 100 primes)] [(list integer) (list integer)] [[<join _ <cons $c _>> <join _ <cons ,c _>>] c])"]),
       ("Play freely with the sequences of natural numbers.\nWe can view a lot of demonstration of pattern-matching at \"http://www.egison.org/demonstrations/\".", [])
       ]),
    ("Lv6 (preparing) - Pattern-matching against graphs",
     Contents [
       ("Sorry, we are preparing this section now.", [])
       ]),
    ("Lv7 (preparing) - Modularize patterns",
     Contents [
       ("Sorry, we are preparing this section now.", [])
       ]),
    ("Lv8 (preparing) - Define your own matchers",
     Contents [
       ("Sorry, we are preparing this section now.", [])
       ])
  ]


--        ("The collection after '@' in a collection is called a subcollection.", ["{1 @{2 3}}", "{1 @{2 3} @{4 @{5}} 6}"]),
--        ("We can destruct collections with 'car' and 'cdr'.", ["(car {1 2 3})", "(cdr {1 2 3})"]),
        
--        ("We can define an array as follow. We can access the element of the array using '_'.", ["(define $a [| 11 22 33 |])", "a_2"]),
--        ("We can define an hash as follow. We can access the element of the hash using '_' as arrays.", ["(define $h {| [1 11] [2 22] [3 33] |})", "h_2"]),

--       ("We can do boolean operations with 'and', 'or', 'not'.", ["(and #t #f)", "(or #t #f)", "(not #t)"]),
