(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2013     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

open Names
open Declarations
open Environ
open Mod_subst
open Modops
open Nativecode
open Nativelib

(** This file implements separate compilation for libraries in the native
compiler *)

let rec translate_mod prefix mp env mod_expr acc =
  match mod_expr with
  | NoFunctor struc ->
      let env' = add_structure mp struc empty_delta_resolver env in
      List.fold_left (translate_field prefix mp env') acc struc
  | MoreFunctor _ -> acc

and translate_field prefix mp env acc (l,x) =
  match x with
  | SFBconst cb ->
     let con = make_con mp empty_dirpath l in
     (if !Flags.debug then
	let msg = Printf.sprintf "Compiling constant %s..." (Constant.to_string con) in
	Pp.msg_debug (Pp.str msg));
     compile_constant_field (pre_env env) prefix con acc cb
  | SFBmind mb ->
     (if !Flags.debug then
	let id = mb.mind_packets.(0).mind_typename in
	let msg = Printf.sprintf "Compiling inductive %s..." (Id.to_string id) in
	Pp.msg_debug (Pp.str msg));
     compile_mind_field prefix mp l acc mb
  | SFBmodule md ->
     let mp = md.mod_mp in
     (if !Flags.debug then
	let msg =
	  Printf.sprintf "Compiling module %s..." (ModPath.to_string mp)
	in
	Pp.msg_debug (Pp.str msg));
     translate_mod prefix mp env md.mod_type acc
  | SFBmodtype mdtyp ->
     let mp = mdtyp.typ_mp in
     (if !Flags.debug then
	let msg =
	  Printf.sprintf "Compiling module type %s..." (ModPath.to_string mp)
	in
	Pp.msg_debug (Pp.str msg));
     translate_mod prefix mp env mdtyp.typ_expr acc

let dump_library mp dp env mod_expr =
  if !Flags.debug then Pp.msg_debug (Pp.str "Compiling library...");
  match mod_expr with
  | NoFunctor struc ->
      let env = add_structure mp struc empty_delta_resolver env in
      let prefix = mod_uid_of_dirpath dp ^ "." in
      let t0 = Sys.time () in
      clear_global_tbl ();
      clear_symb_tbl ();
      let mlcode =
        List.fold_left (translate_field prefix mp env) [] struc
      in
      let t1 = Sys.time () in
      let time_info = Format.sprintf "Time spent generating this code: %.5fs" (t1-.t0) in
      let mlcode = add_header_comment (List.rev mlcode) time_info in
      mlcode, get_symbols_tbl ()
  | _ -> assert false


let compile_library dir code load_path f =
  let header = mk_library_header dir in
  let ml_filename = f^".native" in
  write_ml_code ml_filename ~header code;
  fst (call_compiler ml_filename load_path)