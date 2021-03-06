(*  Title:      HOL/Nunchaku/Tools/nunchaku_display.ML
    Author:     Jasmin Blanchette, Inria Nancy, LORIA, MPII
    Copyright   2015, 2016

Pretty printing of Isabelle/HOL models for Nunchaku.
*)

signature NUNCHAKU_DISPLAY =
sig
  type isa_model = Nunchaku_Reconstruct.isa_model

  val pretty_of_isa_model_opt: Proof.context -> isa_model option -> Pretty.T
end;

structure Nunchaku_Display : NUNCHAKU_DISPLAY =
struct

open Nunchaku_Util;
open Nunchaku_Reconstruct;

val indent_size = 2;

val pretty_indent = Pretty.indent indent_size;

fun sorting_str_of_typ (TFree (s, _)) = "a" ^ s
  | sorting_str_of_typ (Type (s, Ts)) = "b" ^ s ^ space_implode " " (map sorting_str_of_typ Ts)
  | sorting_str_of_typ (TVar _) = "X";

fun sorting_str_of_term (Const (s, T)) = "b" ^ s ^ sorting_str_of_typ T
  | sorting_str_of_term (Free (s, _)) = "a" ^ s
  | sorting_str_of_term (t $ u) = sorting_str_of_term t ^ " " ^ sorting_str_of_term u
  | sorting_str_of_term (Abs (_, T, t)) = "c" ^ sorting_str_of_typ T ^ " " ^ sorting_str_of_term t
  | sorting_str_of_term _ = "X";

fun pretty_of_isa_model_opt _ NONE =
    pretty_indent (Pretty.str "Model unavailable (internal error)")
  | pretty_of_isa_model_opt ctxt0
      (SOME {type_model, free_model, pat_complete_model, pat_incomplete_model, skolem_model}) =
    let
      val ctxt = ctxt0 |> Config.put show_question_marks false;

      val pat_incomplete_model' = pat_incomplete_model
        |> filter_out (can (fn Const (@{const_name unreachable}, _) => ()) o fst);

      fun pretty_of_typ_entry (T, atoms) =
        Pretty.block (Pretty.breaks [Syntax.pretty_typ ctxt T, Pretty.str "=",
           Pretty.enum "," "{" "}" (map (Syntax.pretty_term ctxt) atoms)]);

      fun pretty_of_term_entry (t, value) =
        let
          val no_types_ctxt = ctxt |> Config.put show_types false;
          val schematic_ctxt = ctxt |> Proof_Context.set_mode Proof_Context.mode_schematic;

          val show_types = Config.get ctxt show_types;
          val value' = value |> perhaps (try (Syntax.check_term schematic_ctxt));
          val T = fastype_of t;
          val T' = if T = dummyT then try fastype_of value' |> the_default T else T;
          val t' = t |> show_types ? Type.constraint T';
        in
          Pretty.block (Pretty.breaks
            [Syntax.pretty_term ctxt t'
             |> (show_types andalso T' <> dummyT) ? (single #> Pretty.enclose "(" ")"),
             Pretty.str "=", Syntax.pretty_term no_types_ctxt value'])
        end;

      fun chunks_of_entries sorting_str_of pretty_of title entries =
        if not (null entries) then
          (if title = "" then [] else [Pretty.str (title ^ plural_s_for_list entries ^ ":")]) @
          map (pretty_indent o pretty_of) (sort_by (sorting_str_of o fst) entries)
        else
          [];

      val chunks =
        (if null free_model then
           [pretty_indent (Pretty.str "No free variables")]
         else
           chunks_of_entries sorting_str_of_term pretty_of_term_entry "" free_model) @
        chunks_of_entries sorting_str_of_term pretty_of_term_entry "Skolem constant" skolem_model @
        chunks_of_entries sorting_str_of_term pretty_of_term_entry "Underspecified constant"
          pat_incomplete_model' @
        (if Config.get ctxt show_consts then
           chunks_of_entries sorting_str_of_term pretty_of_term_entry "Fully specified constant"
             pat_complete_model
         else
           []) @
        chunks_of_entries sorting_str_of_typ pretty_of_typ_entry "Type" type_model;
    in
      Pretty.chunks chunks
    end;

end;
