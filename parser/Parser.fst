module Parser

(*
A very simple parser combinator library.

Parsers are functions that take a string and return a parse_result which
contains either a user-specified value and the remaining portion of the string,
or the parse_error type.
*)

open FStar.String
open FStar.Printf
open FStar.Tactics
open StringLemmas

// The type returned by a parser
type parse_result 'a =
  | ParseError : expecting:string -> at:string -> parse_result 'a
  | Success : v:'a -> rest:string -> parse_result 'a

// The type of a parser 
type parser 'a = (x:string) -> Tot (r:(parse_result 'a){ParseError? r ||
  is_substring (Success?.rest r) x})

// Transform the result of a single parser
let parse_apply #a #b (f:a->b) (x:(parser a)) : (parser b) =
  fun (input:string) -> 
  match (x input) with
  | ParseError e1 a1 -> ParseError e1 a1
  | Success t1 rest -> Success (f t1) rest

// Parse one type, then a second, and return a pair
let parse_seq #a #b (x:(parser a)) (y:(parser b)) : Tot (parser (a*b)) =
  fun (input:string) -> 
  match (x input) with
  | ParseError e1 a1 -> ParseError e1 a1
  | Success t1 rest ->
    match (y rest) with
      | ParseError e2 a2 -> ParseError e2 a2
      | Success t2 r2 -> 
        ( substring_transitivity r2 rest input;
          Success (t1, t2) r2 )

//  <,> to create pairs
let op_Less_Comma_Greater (#a:Type) (#b:Type) (x:parser a) (y:parser b) = 
  parse_seq #a #b x y

// Parse a list of one type, then a second list of the same type, and append them
let parse_list #a (x:(parser (list a))) (y:(parser (list a))) : Tot (parser (list a)) =
  fun (input:string) -> 
  match (x input) with
  | ParseError e1 a1 -> ParseError e1 a1
  | Success t1 rest -> match (y rest) with
      | ParseError e2 a2 -> ParseError e2 a2 
      | Success t2 r2 -> 
        (substring_transitivity r2 rest input;
         Success (FStar.List.Tot.append t1 t2) r2)

// TODO: how to combine this with the above?
let parse_nonempty_list #a (x:(parser (z:(list a){Cons? z}))) (y:(parser (list a))) 
 : Tot (parser (z:(list a){Cons? z})) =
  fun (input:string) -> 
  match (x input) with
  | ParseError e1 a1 -> ParseError e1 a1
  | Success t1 rest -> match (y rest) with
      | ParseError e2 a2 -> ParseError e2 a2 
      | Success t2 r2 -> 
        (substring_transitivity r2 rest input;
         Success (FStar.List.Tot.append t1 t2) r2)
 
// <::> to create lists
let op_Less_Colon_Colon_Greater (#a:Type) (x:parser (list a)) (y:parser (list a)) =
  parse_list #a x y

// Explicitly combine the parse results from two types into a third
let parse_comb #a #b #c (x:(parser a)) (f: a -> b -> Tot c) (y:(parser b)) : Tot (parser (c)) =
  fun (input:string) -> 
  match (x input) with
  | ParseError e1 a1 -> ParseError e1 a1
  | Success t1 rest -> match (y rest) with
      | ParseError e2 a2 -> ParseError e2 a2
      | Success t2 r2 -> 
        (substring_transitivity r2 rest input;
        Success (f t1 t2) r2)

// Don't think we can create a ternary operator, but somebody could define their own
// based on a specific method of combining the parsed types

// A utility function for replacing parser failure positions
val bound_string_length : (s:string) -> (l:nat{l>=3}) -> Tot (t:string{strlen t <= l})
let bound_string_length s l = 
  if (strlen s) <= l then  s
  else 
    ( concat_length (sub s 0 (l-3)) "...";  // lemma from String module
      assert_norm( (strlen "...") == 3 );   // let F* know how long the string is?
     (sub s 0 (l-3)) ^ "..." )

let or_of_reasons #a (r1:string) (r2:string) (at:string) 
  :  (r:(parse_result a){ParseError? r}) =
  ParseError (concat " or " [r1; r2]) at
    
// Parse one of two options of the same type. Does not indicate which was chosen,
// you'll have to have the value indicate that.
let parse_either #a (x:(parser a)) (y:(parser a)) : Tot (parser a) =
  fun (input:string) -> 
  match (x input) with
  | Success t1 rest -> Success t1 rest
  | ParseError e1 a1 -> match (y input) with
     | Success t2 r2 -> Success t2 r2 
     | ParseError e2 a2 -> or_of_reasons e1 e2 input

// <|> to create alternatives
let op_Less_Bar_Greater (#a:Type) (x:(parser a)) (y:(parser a)) =
  parse_either x y

type left_right 'a 'b =
 | Left : left:'a -> left_right 'a 'b
 | Right :  right:'b -> left_right 'a 'b
 
// Parse one of the options of differing types.  Indicate which was chosen with the
// left_right type.
let parse_lr #a #b (x:(parser a)) (y:(parser b)) : Tot (parser (left_right a b)) =
  fun (input:string) -> 
  match (x input) with
  | Success t1 rest -> Success (Left t1) rest
  | ParseError e1 a1 -> match (y input) with
     | Success t2 r2 -> Success (Right t2) r2 
     | ParseError e2 a2 -> or_of_reasons e1 e2 input

// The Kleene star won't terminate if the parser doesn't consume input.  So, we'll
// enforce totality by exiting as soon as it doesn't. 
// (Previous approach: define proper and improper parsers, but then we'd have to have
// make multiple version of the above combinators, probably?)
let rec parse_star_aux #a (input:string) (x:parser a) (prev_a:list a) 
: Tot ((list a)*(remaining:string{is_substring remaining input})) 
  (decreases (strlen input)) =
  match (x input) with
  | ParseError _ at -> 
     substring_is_reflexive input;
     ((List.Tot.rev prev_a),input)
  | Success v rest -> 
     if rest = input then ((List.Tot.rev prev_a),input)
       else ( substring_is_shorter rest input;
              proper_substring rest input;
              let next_match = parse_star_aux rest x (v :: prev_a) in
                ( substring_transitivity (snd next_match) rest input;
                  assert( is_substring (snd next_match) input );
                  // OK, this is dumb, F* knows about (snd next_match) but it
                  // can't apply that to intrinsic type of the pair without
                  // me spelling it out for it.
                  ((fst next_match), (snd next_match)) ) )

// Parse zero or more of the given parser, returned as a list
let parse_star #a (x:(parser a)) : Tot (parser (list a)) =
  fun (input:string) -> 
     let r = parse_star_aux input x [] in
       Success (fst r) (snd r)

let listify #a (x:a) : y:(list a){Cons? y} = [x]

// Parse one or more of the given parser, returned as a list
let parse_plus #a (x:(parser a)) : Tot (parser (z:(list a){Cons? z})) =
  parse_nonempty_list (parse_apply listify x) (parse_star x)

(*
  Parsers for basic types
*)

// Return the string when the string is matched.
let literal (a:string) : Tot (parser (m:string{m=a})) = 
  fun (input:string) ->
  if strlen a > strlen input then
     ParseError (sprintf "literal '%s'" a) input
  else let m = sub input 0 (strlen a) in
     if m = a then
        Success m (sub input (strlen a) ((strlen input) - (strlen a)))
     else
        ParseError (sprintf "literal '%s'" a) input

// Return a specific value when the string is matched
let literal_of #b (a:string) (v:b) (input:string) : Tot (parse_result (m:b{m==v})) =
  match literal a input with
  | ParseError expected at -> ParseError expected at
  | Success _ rest -> Success v rest

type digit_string = (x:string{x = "0" || x = "1" || x = "2" || x = "3" || x = "4" || x = "5" || x = "6" || x = "7" || x = "8" || x = "9"})

let digit : (parser digit_string) =
    literal "0" <|> literal "1" <|> literal "2" <|> literal "3"
  

let integer (input:string) : Tot (parse_result int) = 
  


  




