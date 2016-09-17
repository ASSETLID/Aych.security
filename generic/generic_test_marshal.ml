open Generic_core
open Generic_util

open Ty.T
open Desc.T
open Product.Build

module M = Generic_fun_marshal

type _ ty += Var : int -> 'a ty
let print_exn e =
  print_endline (Printexc.to_string e)
  (* ; Printexc.print_backtrace stdout *)

let print_obj = Obj_inspect.print_obj
(* let address = Obj_inspect.address
let print_address x = print_string (address x); print_newline ()
*)

let guard = Exn.guard
let get_some = Option.get_some
let unopt = Option.unopt
let some_if = Option.some_if
let opt_try = Option.opt_try
let (-<) = Fun.(-<)

let debug = true

let test_to msg x t =
  try let y = M.to_repr t x in
      print_endline ("Success        " ^ msg); y
  with e -> print_endline (  "Failure (To)   " ^ msg);
            print_exn e;
            (Obj.repr x)

let test_from msg x t =
  try let _ = M.from_repr t x in
    print_endline ("Success        " ^ msg);
  with e -> print_endline (  "Failure (From) " ^ msg);
            print_exn e

let cast msg x t =
  try let y = M.to_repr t x in
      try let z = M.from_repr t y in
          print_endline ("Success        " ^ msg);
          z
      with e -> print_endline (  "Failure (From) " ^ msg);
                print_exn e;
                x
  with e -> print_endline        ("Failure (To)   " ^ msg);
            print_exn e;
            x

let test_cast m x t = let _ = cast m x t in ()
let expect_fail () = print_endline "Expecting failure..."
let test_cast_fail m x t =
  expect_fail ();
  let _ = cast m x t in ()

(* let test_cast' msg x t = *)
(*   begin *)
(*     print_endline "*** To_repr ARG"; *)
(*     print_obj x; *)
(*     match M.to_repr t x with *)
(*     | Some y -> *)
(*        begin *)
(*          print_endline "*** To_repr RESULT"; *)
(*          print_obj y; *)
(*          match M.from_repr t y with *)
(*          | Some z -> print_endline ("*** Success        " ^ msg); *)
(*                      if debug then *)
(*                        print_obj z; *)
(*          | None -> print_endline   ("*** Failure (From) " ^ msg) *)
(*        end *)
(*     | None ->  print_endline       ("*** Failure (To)   " ^ msg) *)
(*   end *)

let _ =
  begin
    test_cast "\"hello\" : String" "hello" String;
    test_cast "3 : Int" 3 Int;
  end

(**************************************************)
(* Types abstraits *)

(* Naturals *)
type nat = int
type _ ty += Nat : nat ty
let () =
  begin
    Desc_fun.ext Nat { f = fun (type a) (ty : a ty) -> match ty with
        | Nat -> (Abstract : a Desc.t)
        | _ -> assert false };
    Repr.ext Nat
      { f = fun (type a) (ty : a ty) -> match ty with
           | Nat -> (Repr.Repr { repr_ty = Int
                            ; to_repr = (fun x -> x)
                            ; from_repr = some_if (fun x -> x >= 0)
                            ; default = 0
                            ; update = (fun _ _ -> ())}
                     : a Repr.t)
           | _ -> assert false
    };

    test_cast "5 : nat" 5 Nat;
    test_cast_fail "-1 : nat" (-1) Nat;
  end
(* cycle *)
type u = {s : string; mutable x : v option}
and v = {i : int; mutable y : u option}


type _ ty += U : u ty | V : v ty

let () =
  begin
    Desc_fun.ext U { f = fun (type a) (ty : a ty) -> match ty with
        | U -> (Abstract : a desc)
        | _ -> assert false };
    Desc_fun.ext V { f = fun (type a) (ty : a ty) -> match ty with
        | V -> (Abstract : a desc)
        | _ -> assert false };
    Repr.ext U
      { f = fun (type a) (ty : a ty) -> match ty with
           | U -> (Repr.Repr { repr_ty = Pair (String, Option V)
                          ; to_repr = (fun u -> (u.s, u.x))
                          ; from_repr = (fun (s, x) -> Some {s=s; x=x})
                          ; default = {s=""; x = None}
                          ; update = (fun u (s,x) -> u.x <- x)}
                   : a Repr.t)
           | _ -> assert false };
    Repr.ext V
      { f = fun (type a) (ty : a ty) -> match ty with
           | V -> (Repr.Repr { repr_ty = Pair (Int, Option U)
                          ; to_repr = (fun v -> (v.i, v.y))
                          ; from_repr = (fun (i,y) -> Some {i=i; y=y})
                          ; default = {i=0; y = None}
                          ; update = (fun v (i,y) -> v.y <- y)}
                   : a Repr.t)
           | _ -> assert false };

    let rec u_v_cycle = {x = Some v; s = "U"}
    and v = {y = Some u_v_cycle; i = 111}
    in
    test_cast "u_v_cycle : u" u_v_cycle U;
  end

(*************************************************
 * Cycle with lazy *)

module Stream =
  (struct
    type t = C of int * t Lazy.t
    let cons h t = C (h,t)

    type _ ty += T : t ty

    (* cyclic stream *)
    let to_cycle =
      function
      | [] -> assert false (*raise (Invalid_argument "to_cycle []")*)
      | x :: xs ->
         let rec go = function
           | h :: t -> C (h, lazy (go t))
           | [] -> top
         and top = C (x, lazy (go xs))
         in top

    let from_cycle x =
      let rec go = function
          C (h, t) as y
          -> if x == y then []
             else h :: go (Lazy.force t)
      in match x with C (x0,x') ->
                      x0 :: go (Lazy.force x')

    let () =
      Desc_fun.ext T { f = fun (type a) (ty : a ty) -> match ty with
          | T -> (Abstract : a desc)
          | _ -> assert false };
      Repr.ext T
        { f = fun (type a) (ty : a ty) -> match ty with
             | T -> (Repr.Repr { repr_ty = List Int
                            ; to_repr = from_cycle
                            ; from_repr = (fun x -> Some (to_cycle x))
                            ; default = to_cycle [1]
                            ; update = (fun _ _ -> ())
                            }
                     : a Repr.t)
             | _ -> assert false };
  end
  :
    sig
      type t
      val cons : int -> t Lazy.t -> t
      val from_cycle : t -> int list
      type _ ty += T : t ty
    end);;

let cycle_123 =
  let c = Stream.cons in
  let rec x = lazy (c 1 (lazy (c 2 (lazy (c 3 x)))))
  in Lazy.force x

let () =
  print_obj (Stream.from_cycle cycle_123);
  test_cast "cycle_123" cycle_123 Stream.T (* TODO investigate failure *)

(**************************************************)
(* Objets *)

let p =
    object
      val mutable x = 0
      method get_x = x
      method move d = x <- x + d
      method len : 'a . 'a list -> int = List.length
    end;;

let get_x =
  { Desc.Method.name = "get_x"
  ; send = (fun c -> c#get_x)
  ; bound = 0
  ; ty = Int
  }

let move =
  { Desc.Method.name = "move"
  ; send = (fun c -> c#move)
  ; bound = 0
  ; ty = Fun (Int, Unit)
  }

let len =
  { Desc.Method.name = "len"
  ; send = (fun (c  : <len : 'a . 'a list -> int; ..>) -> c#len)
  ; bound = 1
  ; ty = Fun (List (Var 0), Int)
  }

let len0 =
  { Desc.Method.name = "len"
  ; send = (fun c -> c#len)
  ; bound = 0
  ; ty = Fun (List (Var 0), Int)
  }


let p_ty = Desc.Object.T
  [ Method get_x
  ; Method move
  ; Method len
  ]

let has_type : 'a . 'a -> 'a ty -> unit = fun _ _ -> ()

let () = has_type p p_ty

(* Desc.Method polymorphism *)
exception Undefined
let f = object method m = raise Undefined end (* 'a . <m : 'a> = *)
let g = object method m : 'a . 'a = raise Undefined end


(**************************************************)
class point init =
  object
    val mutable x = init
    method get_x = x
    method move d = x <- x + d
    method len : 'a . 'a list -> int = List.length
  end

type _ ty += Point : point ty

let () =
  begin
    Desc_fun.ext Point { f = fun (type a) (ty : a ty) -> (match ty with
        | Point -> Class { name = "Point"
                         ; methods =
                             [ Method get_x
                             ; Method move
                             ; Method len ]
                         }
        | _ -> assert false : a desc) };

    Repr.ext Point
      { f = fun (type a) (ty : a ty) -> match ty with
           | Point -> (Repr.Repr { repr_ty = Int
                              ; to_repr = (fun p -> p#get_x)
                              ; from_repr = (fun x -> Some (new point x))
                              ; default = new point 0
                              ; update = (fun p x -> ())}
                       : a Repr.t)
           | _ -> assert false };

    let p = cast "(new point 3) : point" (new point 3) Point in
    print_endline ("*** p#get_x = " ^ string_of_int p#get_x);
    let pp = M.to_repr (Pair (Point, Point)) (p,p) in
    print_endline "*** pp = to_repr (p,p)";
    print_obj pp;
    let p' = M.from_repr (Pair (Point, Point)) pp in
    print_endline "*** from_repr pp";
    print_obj p';
  end

class a init =
  object
    val mutable b = (init : b)
    method get_b = b
  end
and b init =
  object
    val mutable a = (init : a option)
    method set_a a' = a <- Some a'
    method get_a = a
  end

type _ ty += A : a ty | B : b ty

let a_b_cycle = new a (new b None)
let () = a_b_cycle # get_b # set_a a_b_cycle

let () =
  begin
    Desc_fun.ext A { f = fun (type a) (ty : a ty) -> match ty with
        | A -> (Abstract : a desc)
        | _ -> assert false };
    Desc_fun.ext B { f = fun (type a) (ty : a ty) -> match ty with
        | B -> (Abstract : a desc)
        | _ -> assert false };
    Repr.ext A
      { f = fun (type a) (ty : a ty) -> match ty with
           | A -> (Repr.Repr { repr_ty = B
                          ; to_repr = (fun a -> a#get_b)
                          ; from_repr = (fun b -> Some (new a b))
                          ; default = new a (new b None)
                          ; update = (fun a b -> guard (b == a#get_b))}
                   : a Repr.t)
           | _ -> assert false };
    Repr.ext B
      { f = fun (type a) (ty : a ty) -> match ty with
           | B -> (Repr.Repr { repr_ty = Option A
                          ; to_repr = (fun b -> b#get_a)
                          ; from_repr = (fun a -> Some (new b a))
                          ; default = new b None
                          ; update = (fun b -> unopt () (b#set_a))}
                   : a Repr.t)
           | _ -> assert false };
    test_cast "a_b_cycle : a" a_b_cycle A;
  end

(**************************************************)
(* Synonyms *)

type c = int list
type d = c
type _ ty += C : c ty
type _ ty += D : d ty
let () =
  begin
    Desc_fun.ext_add_con (Ty C)
    { con = fun (type a) (Ty C : a ty)
          -> (Desc.Con.make "C" p0
                     (fun () -> C)
                     (function | C -> Some ()
                               | _ -> None)
              : a Desc.Con.t)
    };

    Desc_fun.ext C { f = fun (type a) (ty : a ty) -> match ty with
        | C -> (Synonym (List Int, Refl) : a desc)
        | _ -> assert false };
    Desc_fun.ext D { f = fun (type a) (ty : a ty) -> match ty with
        | D -> (Synonym (C, Refl) : a desc)
        | _ -> assert false };
    test_cast "[3] : d" [3] D;
  end

(**************************************************)
(* champs mutables *)

let () =
  begin
    let x = ref [] in
    test_cast "(ref []) : int list ref " x (Ref (List Int));
    test_cast_fail "(ref []) : ('a . 'a list) ref " x (Ref (List Any)); (* should fail *)
    test_cast "[] : 'a . 'a list" [] (List Any);
    let y = Some [] in
    let yt t = Option (List t) in
    let yr = M.to_repr (yt Int) y in
    test_from "(Some []) : int list ref " yr (Ref (List Int));
    let z = (y,y) in
    let zr = M.to_repr (Pair (yt Int, yt Bool)) z in
    let zt' = Pair (Ref (List Int), Ref (List String)) in
    print_endline "*** let y = Some [] in (y,y) : (int list ref, string list ref)";
    expect_fail ();
    test_from "let y = Some [] in (y,y) : (int list ref, string list ref)" zr zt';
    print_endline "*** zr";
    print_obj zr;
    try let z' =  M.from_repr zt' zr in
        print_endline "*** assigning values of different types";
        match z' with
        | (r1,r2) ->
           print_obj z';
           r2 := [""];
           print_obj z';
           r1 := [5];
           print_obj z'
    with _ -> ()
  end

(* polymorphic mutable field *)
(*type pmf = {mutable pmf : 'a . 'a list}
type _ ty += Pmf : pmf ty
let () =
  begin
    Desc_fun.ext_add_con (Ty Pmf)
    { con = fun (type a) (Ty Pmf : a ty)
          -> (Desc.Con.make "Pmf" p0
                     (fun () -> Pmf)
                     (function | Pmf -> Some ()
                               | _ -> None)
              : a Desc.Con.t)
    };

    Desc_fun.ext Pmf {
      f = fun (type a) (Pmf : a ty) ->
          ( Record
              { name = "pmf"
              ; fields =
                  Cons ( { name = "pmf"
                          ; ty = List (Var 0)
                          ; bound = 1
                          ; set = None
                          }
                        , Nil)
              ; iso = { fwd = (fun (pmf,()) -> {pmf})
                      ; bck = (fun {pmf} -> (pmf,()))
                      }
              }
            : a desc)
    };

    test_cast "polymorphic mutable field" {pmf = []} Pmf;
  end
  *)
