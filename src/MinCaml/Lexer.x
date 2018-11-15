{
module MinCaml.Lexer (Token(..), runLexer) where
}

%wrapper "basic"

$space = $white
$digit = 0-9
$lower = [a-z]
$upper = [A-Z]

tokens :-
  $space+               ;
  \(                    { tokenize LPAREN }
  \)                    { tokenize RPAREN }
  true                  { tokenize $ BOOL True }
  false                 { tokenize $ BOOL False }
  not                   { tokenize NOT }
  $digit+               { tokenizeInt }
  $digit+ (\. $digit*)? { tokenizeFloat }
  \+                    { tokenize PLUS }
  \-                    { tokenize MINUS }
  \=                    { tokenize EQUAL }
  \<>                   { tokenize LESS_GREATER }
  \<=                   { tokenize LESS_EQUAL }
  \>=                   { tokenize GREATER_EQUAL }
  \<                    { tokenize LESS }
  \>                    { tokenize GREATER }
  if                    { tokenize IF }
  then                  { tokenize THEN }
  else                  { tokenize ELSE }

{
data Token
  = LPAREN
  | RPAREN
  | BOOL Bool
  | NOT
  | INT Int
  | FLOAT Float
  | PLUS
  | MINUS
  | EQUAL
  | LESS_GREATER
  | LESS_EQUAL
  | GREATER_EQUAL
  | LESS
  | GREATER
  | IF
  | THEN
  | ELSE
  deriving (Show, Eq)

tokenize :: Token -> String -> Token
tokenize t _ = t

tokenizeInt :: String -> Token
tokenizeInt = INT . read

tokenizeFloat :: String -> Token
tokenizeFloat = FLOAT . read

runLexer :: String -> [Token]
runLexer = alexScanTokens
}
