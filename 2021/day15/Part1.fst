module Part1

open FStar.List.Tot
open FStar.String
open FStar.IO
open FStar.All
open FStar.Printf

let vector (a:Type) (len:nat) = (l:(list a){List.Tot.length l = len})

let matrix (a:Type) (width:nat{0<width}) (height:nat{0<height}) =
  (vector (vector a width) height)

let value_at #a #w #h (m:matrix a w h) (i:nat{0 <= i && i < h}) (j:nat{0 <= j && j < w}) : Tot a =
  List.Tot.index (List.Tot.index m i) j  

let rec parse_row_aux (s:list char) (expected_len:nat) : Tot
 (option (vector nat expected_len)) 
 (decreases expected_len) =
    if expected_len = 0 then
       match s with
         | [] -> Some []
         | _ -> None
    else
    let add_cell (c:nat) (tl:list char) : (option (vector nat expected_len)) =
       match (parse_row_aux tl (expected_len - 1)) with
       | None -> None
       | Some l -> Some (c :: l)
    in match s with 
    | [] -> None
    | '0' :: tl -> (add_cell 0 tl)
    | '1' :: tl -> (add_cell 1 tl)
    | '2' :: tl -> (add_cell 2 tl)
    | '3' :: tl -> (add_cell 3 tl)
    | '4' :: tl -> (add_cell 4 tl)
    | '5' :: tl -> (add_cell 5 tl)
    | '6' :: tl -> (add_cell 6 tl)
    | '7' :: tl -> (add_cell 7 tl)
    | '8' :: tl -> (add_cell 8 tl)
    | '9' :: tl -> (add_cell 9 tl)
    | _ -> None
    
let parse_row (s:string) (expected_len:nat) : (option (vector nat expected_len)) =
  parse_row_aux (list_of_string s) expected_len

let rec parse_matrix_aux (fd:fd_read) (width:nat) : ML (list (vector nat width)) =
  try 
   let line = read_line fd in
     match (parse_row line width) with
       | None -> failwith "Can't parse row"
       | Some row -> row :: (parse_matrix_aux fd width)
   with
     | EOF -> []
     | _ -> failwith "Unexpected error" 

type sized_matrix =
 | Matrix : (w:nat{w>0}) -> (h:nat{h>0}) -> (m:matrix nat w h) -> sized_matrix

let parse_matrix (fd:fd_read) : ML sized_matrix =
  let first_line = read_line fd in
    let width = strlen first_line in
      match parse_row first_line width with
        | None -> failwith "Can't parse first row"
        | Some first_line ->
      let rest = parse_matrix_aux fd width in
        if width = 0 then
           failwith "Width can't be zero"
        else 
          Matrix width (1 + List.Tot.length rest) (first_line :: rest )

// Leftist heap, following
// https://courses.cs.washington.edu/courses/cse326/08sp/lectures/05-leftist-heaps.pdf

type int_1 = (z:int{z >= -1})

noeq type heapnode : v:Type -> (npl:int_1) -> Type =
  | Null : #v:Type -> heapnode v (-1)
  | Node: #v:Type -> 
          npl_left:int_1 -> left:heapnode v npl_left -> 
          key:nat -> value:v -> 
          (npl_right:int_1{npl_right <= npl_left}) -> right:(heapnode v npl_right) -> 
          heapnode v (1 + (min npl_left npl_right))

let empty_heap (#v:Type) = Null

let singleton_heap (#v:Type) (key:nat) (value:v) : (heapnode v 0) =
  Node (-1) Null key value (-1) Null

// We don't have any way to decrease_key for this heap implementation.
// So, we will have to allow the same value to be inserted multiple times,
// and just check in our matrix whether we've already found the minimum value for it.

// Merge two leftist heaps
let rec merge_heaps (#v:Type) (#npl_a:int_1) (a:heapnode v npl_a) (#npl_b:int_1) (b:heapnode v npl_b) 
  : Tot (npl_result:int_1 & (heapnode v npl_result)) 
    (decreases %[a;b]) =
  if Null? a then
     (| npl_a, a |)
  else if Null? b then
     (| npl_b, b |)
  else if Node?.key a <= Node?.key b then (
     // a has the minimum key
     let new_left = Node?.left a in
     let npl_left = Node?.npl_left a in
     let new_tree = merge_heaps (Node?.right a) b in
     let npl_right = dfst new_tree in
     let new_right = dsnd new_tree in
        if npl_right <= npl_left then
           // Order is OK
           (| 1 + (min npl_left npl_right),
              Node npl_left new_left 
                   (Node?.key a) (Node?.value a)
                   npl_right new_right |)
        else
           // Invariant not OK, swap the trees to preserve it
           (| 1 + (min npl_left npl_right),
              Node npl_right new_right 
                   (Node?.key a) (Node?.value a)
                   npl_left new_left |)                      
  ) else 
     // b has the minimum key
     let new_left = Node?.left b in
     let npl_left = Node?.npl_left b in
     let new_tree = merge_heaps a (Node?.right b) in
     let npl_right = dfst new_tree in
     let new_right = dsnd new_tree in
        if npl_right <= npl_left then
           // Order is OK
           (| 1 + (min npl_left npl_right),
              Node npl_left new_left 
                   (Node?.key b) (Node?.value b)
                   npl_right new_right |)
        else
           // Invariant not OK, swap the trees to preserve it
           (| 1 + (min npl_left npl_right),
              Node npl_right new_right 
                   (Node?.key b) (Node?.value b)
                   npl_left new_left |)                      

let insert (#v:Type) (#npl_root:int_1) (root:heapnode v npl_root) (key:nat) (value:v) 
  : Tot (npl_result:int_1 & (heapnode v npl_result)) =
  merge_heaps root (singleton_heap key value)

noeq type pop_result : v:Type -> Type =
  | MinValue : (#v:Type) -> (key:nat) -> (value:v) -> (npl:int_1) -> (new_root:heapnode v npl) -> pop_result v
  
let pop_min (#v:Type) (#npl_root:int_1{npl_root >= 0}) (root:heapnode v npl_root)
 : Tot (pop_result v) =
 match root with 
 | Node npl_left left key value npl_right right ->
   let new_tree = merge_heaps left right in
     MinValue key value (dfst new_tree) (dsnd new_tree)

type distance =
  | Infinity
  | Finite : n:nat -> distance
  | Finished : n:nat -> distance

// Copied from day 9 -- create a range of integres
let rec nat_range_helper (start:nat) (nd:nat{start<nd}) 
    (curr:nat{start <= curr && curr < nd}) 
    (l:list (z:nat{start <= z && z < nd}))
: Tot (list (z:nat{start <= z && z < nd})) (decreases (curr-start)) =
  if curr = start then curr :: l
  else nat_range_helper start nd (curr-1) (curr :: l)

let nat_range_lemma_0 (start:nat) (nd:nat{start<nd}) (l:list (z:nat{start <= z && z < nd}))
  : Lemma( nat_range_helper start nd start l = start :: l ) =
  ()

let nat_range_lemma_1 (start:nat) (nd:nat{start<nd}) 
  (c:nat{start < c && c < nd}) (l:list (z:nat{start <= z && z < nd})) 
  : Lemma( nat_range_helper start nd c l = nat_range_helper start nd (c-1) ( c :: l ) ) =
  ()

let rec nat_range_helper_len (start:nat) (nd:nat{start<nd}) 
   (curr:nat{start <= curr && curr < nd}) 
   (l:list (z:nat{start <= z && z < nd}))
  : Lemma (ensures (List.Tot.length (nat_range_helper start nd curr l) = (List.Tot.length l) + (1 + (curr - start))))
          (decreases (curr - start))
   = if curr = start then 
       nat_range_lemma_0 start nd l
     else (
       nat_range_helper_len start nd (curr-1) (curr::l);
       nat_range_lemma_1 start nd curr l
     )
     
let nat_range (start:nat) (nd:nat) : Tot (list (z:nat{start <= z && z < nd})) =
  if start >= nd then []
  else nat_range_helper start nd (nd-1) []
  
let nat_range_length (start:nat) (nd:nat) 
  : Lemma (requires start < nd)
          (ensures (List.Tot.length (nat_range start nd) = (nd - start)))
          [SMTPat (nat_range start nd)]
  =  nat_range_helper_len start nd (nd-1) []

let map_vec #a #b #n (f:a -> Tot b) (l:(list a){List.Tot.length l = n}) : Tot (vector b n) =
  List.Tot.map f l

let nat_range_no_really (w:nat{0 < w}) :  (l:list (z:nat{0 <= z && z < w}){List.Tot.length l = w}) =
  let ret = (nat_range 0 w) in 
    nat_range_length 0 w;
    ret

let start_matrix (w:nat{w>0}) (h:nat{h>0}) : Tot (matrix distance w h) =
  let map_row (y:nat{y<h}): (vector distance w) = 
    let row : (l:list(j:nat{0 <= j && j < w}){List.Tot.length l = w}) = (nat_range_no_really w) in
      map_vec (fun (x:nat{0 <= x && x < w}) -> 
         if x = 0 && y = 0 then
            Finite 0
         else
            Infinity)
      row
  in 
    nat_range_length 0 h;
    map_vec map_row (nat_range 0 h)

let finish_node #w #h (distances:matrix distance w h)
   (y:nat{y<h}) (x:nat{x<w}) (d_xy:nat) 
   : Tot (matrix distance w h) = 
   admit()
   
let update_neighbors #w #h (weights:matrix nat w h) (distances:matrix distance w h)
   (y:nat{y<h}) (x:nat{x<w}) (d_xy:nat) 
   : Tot (matrix distance w h) = 
   admit()

let insert_neighbors #w #h (distances:matrix distance w h) 
    (y:nat{y<h}) (x:nat{x<w})    
    (npl:int_1) (pri_queue:heapnode (x:nat{x<w}*y:nat{y<h}) npl) 
  : Tot (npl_result:int_1 & (heapnode (x:nat{x<w}*y:nat{y<h})  npl_result)) =
  admit()

let rec dijkstras #w #h (weights:matrix nat w h) (distances:matrix distance w h) 
   (pq_npl:int_1) (pri_queue:heapnode (x:nat{x<w}*y:nat{y<h}) pq_npl) 
   : Dv (matrix distance w h) =
   if pq_npl = -1 then
     distances
   else
     match pop_min pri_queue with
     | MinValue key value npl new_root -> 
       let y = (snd #(x:nat{x<w}) #(y:nat{y<h}) value) in
       let x = (fst #(x:nat{x<w}) #(y:nat{y<h}) value) in
       let v = value_at distances y x in (
         assume( ~ (Infinity? v) );
         match v with 
         | Finished _ ->
              dijkstras weights distances npl new_root
         | Finite n ->
            let new_distances_1 = finish_node distances y x n in
            let new_distances_2 = update_neighbors weights new_distances_1 y x n in
            let new_q = insert_neighbors new_distances_2 y x npl new_root in
              dijkstras weights new_distances_2 (dfst new_q) (dsnd new_q)
       )
     
let find_minimum_path #w #h (m:matrix nat w h) : Dv distance =
   let dmatrix = dijkstras m (start_matrix w h) 0 (singleton_heap 0 (0,0)) in
     value_at dmatrix (h-1) (w-1)     

let calc_part_1 (fn:string): ML unit =
  let fd = open_read_file fn in
    let m = parse_matrix fd in
      match m with
      | Matrix w h board ->
         let soln = find_minimum_path board in
           admit()

let _ = calc_part_1 "example.txt"
let _ = calc_part_1 "input.txt"

