(*  Title:      HOL/Tools/code_evaluation.ML
    Author:     Florian Haftmann, TU Muenchen

Evaluation and reconstruction of terms in ML.
*)

signature CODE_EVALUATION =
sig
  val dynamic_value: Proof.context -> term -> term option
  val dynamic_value_strict: Proof.context -> term -> term
  val dynamic_value_exn: Proof.context -> term -> term Exn.result
  val put_term: (unit -> term) -> Proof.context -> Proof.context
  val tracing: string -> 'a -> 'a
end;

structure Code_Evaluation : CODE_EVALUATION =
struct

(** term_of instances **)

(* formal definition *)

fun add_term_of tyco raw_vs thy =
  let
    val vs = map (fn (v, _) => (v, @{sort typerep})) raw_vs;
    val ty = Type (tyco, map TFree vs);
    val lhs = Const (@{const_name term_of}, ty --> @{typ term})
      $ Free ("x", ty);
    val rhs = @{term "undefined :: term"};
    val eq = HOLogic.mk_Trueprop (HOLogic.mk_eq (lhs, rhs));
    fun triv_name_of t = (fst o dest_Free o fst o strip_comb o fst
      o HOLogic.dest_eq o HOLogic.dest_Trueprop) t ^ "_triv";
  in
    thy
    |> Class.instantiation ([tyco], vs, @{sort term_of})
    |> `(fn lthy => Syntax.check_term lthy eq)
    |-> (fn eq => Specification.definition NONE [] [] ((Binding.name (triv_name_of eq), []), eq))
    |> snd
    |> Class.prove_instantiation_exit (fn ctxt => Class.intro_classes_tac ctxt [])
  end;

fun ensure_term_of (tyco, (vs, _)) thy =
  let
    val need_inst = not (Sorts.has_instance (Sign.classes_of thy) tyco @{sort term_of})
      andalso Sorts.has_instance (Sign.classes_of thy) tyco @{sort typerep};
  in if need_inst then add_term_of tyco vs thy else thy end;

fun for_term_of_instance tyco vs f thy =
  let
    val algebra = Sign.classes_of thy;
  in
    case try (Sorts.mg_domain algebra tyco) @{sort term_of} of
      NONE => thy
    | SOME sorts => f tyco (map2 (fn (v, sort) => fn sort' =>
        (v, Sorts.inter_sort algebra (sort, sort'))) vs sorts) thy
  end;


(* code equations for datatypes *)

fun mk_term_of_eq thy ty (c, (_, tys)) =
  let
    val t = list_comb (Const (c, tys ---> ty),
      map Free (Name.invent_names Name.context "a" tys));
    val (arg, rhs) =
      apply2 (Thm.global_cterm_of thy o Logic.unvarify_types_global o Logic.varify_global)
        (t,
          map_aterms (fn t as Free (_, ty) => HOLogic.mk_term_of ty t | t => t)
            (HOLogic.reflect_term t));
    val cty = Thm.global_ctyp_of thy ty;
  in
    @{thm term_of_anything}
    |> Thm.instantiate' [SOME cty] [SOME arg, SOME rhs]
    |> Thm.varifyT_global
  end;

fun add_term_of_code tyco vs raw_cs thy =
  let
    val ty = Type (tyco, map TFree vs);
    val cs = (map o apsnd o apsnd o map o map_atyps)
      (fn TFree (v, _) => TFree (v, (the o AList.lookup (op =) vs) v)) raw_cs;
    val const = Axclass.param_of_inst thy (@{const_name term_of}, tyco);
    val eqs = map (mk_term_of_eq thy ty) cs;
 in
    thy
    |> Code.del_eqns const
    |> fold (Code.add_eqn (Code.Equation, false)) eqs
  end;

fun ensure_term_of_code (tyco, (vs, cs)) =
  for_term_of_instance tyco vs (fn tyco => fn vs => add_term_of_code tyco vs cs);


(* code equations for abstypes *)

fun mk_abs_term_of_eq thy ty abs ty_rep proj =
  let
    val arg = Var (("x", 0), ty);
    val rhs = Abs ("y", @{typ term}, HOLogic.reflect_term (Const (abs, ty_rep --> ty) $ Bound 0)) $
      (HOLogic.mk_term_of ty_rep (Const (proj, ty --> ty_rep) $ arg))
      |> Thm.global_cterm_of thy;
    val cty = Thm.global_ctyp_of thy ty;
  in
    @{thm term_of_anything}
    |> Thm.instantiate' [SOME cty] [SOME (Thm.global_cterm_of thy arg), SOME rhs]
    |> Thm.varifyT_global
  end;

fun add_abs_term_of_code tyco vs abs raw_ty_rep proj thy =
  let
    val ty = Type (tyco, map TFree vs);
    val ty_rep = map_atyps
      (fn TFree (v, _) => TFree (v, (the o AList.lookup (op =) vs) v)) raw_ty_rep;
    val const = Axclass.param_of_inst thy (@{const_name term_of}, tyco);
    val eq = mk_abs_term_of_eq thy ty abs ty_rep proj;
 in
    thy
    |> Code.del_eqns const
    |> Code.add_eqn (Code.Equation, false) eq
  end;

fun ensure_abs_term_of_code (tyco, (vs, ((abs, (_, ty)), (proj, _)))) =
  for_term_of_instance tyco vs
    (fn tyco => fn vs => add_abs_term_of_code tyco vs abs ty proj);


(* setup *)

val _ = Theory.setup
  (Code.datatype_interpretation ensure_term_of
  #> Code.abstype_interpretation ensure_term_of
  #> Code.datatype_interpretation ensure_term_of_code
  #> Code.abstype_interpretation ensure_abs_term_of_code);


(** termifying syntax **)

fun map_default f xs =
  let val ys = map f xs
  in if exists is_some ys
    then SOME (map2 the_default xs ys)
    else NONE
  end;

fun subst_termify_app (Const (@{const_name termify}, _), [t]) =
      if not (Term.exists_subterm (fn Abs _ => true | _ => false) t)
      then if fold_aterms (fn Const _ => I | _ => K false) t true
        then SOME (HOLogic.reflect_term t)
        else error "Cannot termify expression containing variable"
      else error "Cannot termify expression containing abstraction"
  | subst_termify_app (t, ts) = case map_default subst_termify ts
     of SOME ts' => SOME (list_comb (t, ts'))
      | NONE => NONE
and subst_termify (Abs (v, T, t)) = (case subst_termify t
     of SOME t' => SOME (Abs (v, T, t'))
      | NONE => NONE)
  | subst_termify t = subst_termify_app (strip_comb t) 

fun check_termify ts = the_default ts (map_default subst_termify ts);

val _ = Context.>> (Syntax_Phases.term_check 0 "termify" (K check_termify));


(** evaluation **)

structure Evaluation = Proof_Data
(
  type T = unit -> term
  val empty: T = fn () => raise Fail "Evaluation"
  fun init _ = empty
);
val put_term = Evaluation.put;
val cookie = (Evaluation.get, put_term, "Code_Evaluation.put_term");

fun mk_term_of t = HOLogic.mk_term_of (fastype_of t) t;

fun gen_dynamic_value computation ctxt t =
  computation cookie ctxt NONE I (mk_term_of t) [];

val dynamic_value = gen_dynamic_value Code_Runtime.dynamic_value;
val dynamic_value_strict = gen_dynamic_value Code_Runtime.dynamic_value_strict;
val dynamic_value_exn = gen_dynamic_value Code_Runtime.dynamic_value_exn;


(** diagnostic **)

fun tracing s x = (Output.tracing s; x);

end;
