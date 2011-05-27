theory HOL_Specific
imports Base Main
begin

chapter {* Isabelle/HOL \label{ch:hol} *}

section {* Typedef axiomatization \label{sec:hol-typedef} *}

text {*
  \begin{matharray}{rcl}
    @{command_def (HOL) "typedef"} & : & @{text "local_theory \<rightarrow> proof(prove)"} \\
  \end{matharray}

  @{rail "
    @@{command (HOL) typedef} altname? abstype '=' repset
    ;

    altname: '(' (@{syntax name} | @'open' | @'open' @{syntax name}) ')'
    ;
    abstype: @{syntax typespec_sorts} @{syntax mixfix}?
    ;
    repset: @{syntax term} (@'morphisms' @{syntax name} @{syntax name})?
  "}

  \begin{description}

  \item @{command (HOL) "typedef"}~@{text "(\<alpha>\<^sub>1, \<dots>, \<alpha>\<^sub>n) t = A"}
  axiomatizes a Gordon/HOL-style type definition in the background
  theory of the current context, depending on a non-emptiness result
  of the set @{text A} (which needs to be proven interactively).

  The raw type may not depend on parameters or assumptions of the
  context --- this is logically impossible in Isabelle/HOL --- but the
  non-emptiness property can be local, potentially resulting in
  multiple interpretations in target contexts.  Thus the established
  bijection between the representing set @{text A} and the new type
  @{text t} may semantically depend on local assumptions.

  By default, @{command (HOL) "typedef"} defines both a type @{text t}
  and a set (term constant) of the same name, unless an alternative
  base name is given in parentheses, or the ``@{text "(open)"}''
  declaration is used to suppress a separate constant definition
  altogether.  The injection from type to set is called @{text Rep_t},
  its inverse @{text Abs_t} --- this may be changed via an explicit
  @{keyword (HOL) "morphisms"} declaration.

  Theorems @{text Rep_t}, @{text Rep_t_inverse}, and @{text
  Abs_t_inverse} provide the most basic characterization as a
  corresponding injection/surjection pair (in both directions).  Rules
  @{text Rep_t_inject} and @{text Abs_t_inject} provide a slightly
  more convenient view on the injectivity part, suitable for automated
  proof tools (e.g.\ in @{attribute simp} or @{attribute iff}
  declarations).  Rules @{text Rep_t_cases}/@{text Rep_t_induct}, and
  @{text Abs_t_cases}/@{text Abs_t_induct} provide alternative views
  on surjectivity; these are already declared as set or type rules for
  the generic @{method cases} and @{method induct} methods.

  An alternative name for the set definition (and other derived
  entities) may be specified in parentheses; the default is to use
  @{text t} as indicated before.

  \end{description}
*}


section {* Adhoc tuples *}

text {*
  \begin{matharray}{rcl}
    @{attribute_def (HOL) split_format}@{text "\<^sup>*"} & : & @{text attribute} \\
  \end{matharray}

  @{rail "
    @@{attribute (HOL) split_format} ('(' 'complete' ')')?
  "}

  \begin{description}

  \item @{attribute (HOL) split_format}\ @{text "(complete)"} causes
  arguments in function applications to be represented canonically
  according to their tuple type structure.

  Note that this operation tends to invent funny names for new local
  parameters introduced.

  \end{description}
*}


section {* Records \label{sec:hol-record} *}

text {*
  In principle, records merely generalize the concept of tuples, where
  components may be addressed by labels instead of just position.  The
  logical infrastructure of records in Isabelle/HOL is slightly more
  advanced, though, supporting truly extensible record schemes.  This
  admits operations that are polymorphic with respect to record
  extension, yielding ``object-oriented'' effects like (single)
  inheritance.  See also \cite{NaraschewskiW-TPHOLs98} for more
  details on object-oriented verification and record subtyping in HOL.
*}


subsection {* Basic concepts *}

text {*
  Isabelle/HOL supports both \emph{fixed} and \emph{schematic} records
  at the level of terms and types.  The notation is as follows:

  \begin{center}
  \begin{tabular}{l|l|l}
    & record terms & record types \\ \hline
    fixed & @{text "\<lparr>x = a, y = b\<rparr>"} & @{text "\<lparr>x :: A, y :: B\<rparr>"} \\
    schematic & @{text "\<lparr>x = a, y = b, \<dots> = m\<rparr>"} &
      @{text "\<lparr>x :: A, y :: B, \<dots> :: M\<rparr>"} \\
  \end{tabular}
  \end{center}

  \noindent The ASCII representation of @{text "\<lparr>x = a\<rparr>"} is @{text
  "(| x = a |)"}.

  A fixed record @{text "\<lparr>x = a, y = b\<rparr>"} has field @{text x} of value
  @{text a} and field @{text y} of value @{text b}.  The corresponding
  type is @{text "\<lparr>x :: A, y :: B\<rparr>"}, assuming that @{text "a :: A"}
  and @{text "b :: B"}.

  A record scheme like @{text "\<lparr>x = a, y = b, \<dots> = m\<rparr>"} contains fields
  @{text x} and @{text y} as before, but also possibly further fields
  as indicated by the ``@{text "\<dots>"}'' notation (which is actually part
  of the syntax).  The improper field ``@{text "\<dots>"}'' of a record
  scheme is called the \emph{more part}.  Logically it is just a free
  variable, which is occasionally referred to as ``row variable'' in
  the literature.  The more part of a record scheme may be
  instantiated by zero or more further components.  For example, the
  previous scheme may get instantiated to @{text "\<lparr>x = a, y = b, z =
  c, \<dots> = m'\<rparr>"}, where @{text m'} refers to a different more part.
  Fixed records are special instances of record schemes, where
  ``@{text "\<dots>"}'' is properly terminated by the @{text "() :: unit"}
  element.  In fact, @{text "\<lparr>x = a, y = b\<rparr>"} is just an abbreviation
  for @{text "\<lparr>x = a, y = b, \<dots> = ()\<rparr>"}.

  \medskip Two key observations make extensible records in a simply
  typed language like HOL work out:

  \begin{enumerate}

  \item the more part is internalized, as a free term or type
  variable,

  \item field names are externalized, they cannot be accessed within
  the logic as first-class values.

  \end{enumerate}

  \medskip In Isabelle/HOL record types have to be defined explicitly,
  fixing their field names and types, and their (optional) parent
  record.  Afterwards, records may be formed using above syntax, while
  obeying the canonical order of fields as given by their declaration.
  The record package provides several standard operations like
  selectors and updates.  The common setup for various generic proof
  tools enable succinct reasoning patterns.  See also the Isabelle/HOL
  tutorial \cite{isabelle-hol-book} for further instructions on using
  records in practice.
*}


subsection {* Record specifications *}

text {*
  \begin{matharray}{rcl}
    @{command_def (HOL) "record"} & : & @{text "theory \<rightarrow> theory"} \\
  \end{matharray}

  @{rail "
    @@{command (HOL) record} @{syntax typespec_sorts} '=' \\
      (@{syntax type} '+')? (@{syntax constdecl} +)
  "}

  \begin{description}

  \item @{command (HOL) "record"}~@{text "(\<alpha>\<^sub>1, \<dots>, \<alpha>\<^sub>m) t = \<tau> + c\<^sub>1 :: \<sigma>\<^sub>1
  \<dots> c\<^sub>n :: \<sigma>\<^sub>n"} defines extensible record type @{text "(\<alpha>\<^sub>1, \<dots>, \<alpha>\<^sub>m) t"},
  derived from the optional parent record @{text "\<tau>"} by adding new
  field components @{text "c\<^sub>i :: \<sigma>\<^sub>i"} etc.

  The type variables of @{text "\<tau>"} and @{text "\<sigma>\<^sub>i"} need to be
  covered by the (distinct) parameters @{text "\<alpha>\<^sub>1, \<dots>,
  \<alpha>\<^sub>m"}.  Type constructor @{text t} has to be new, while @{text
  \<tau>} needs to specify an instance of an existing record type.  At
  least one new field @{text "c\<^sub>i"} has to be specified.
  Basically, field names need to belong to a unique record.  This is
  not a real restriction in practice, since fields are qualified by
  the record name internally.

  The parent record specification @{text \<tau>} is optional; if omitted
  @{text t} becomes a root record.  The hierarchy of all records
  declared within a theory context forms a forest structure, i.e.\ a
  set of trees starting with a root record each.  There is no way to
  merge multiple parent records!

  For convenience, @{text "(\<alpha>\<^sub>1, \<dots>, \<alpha>\<^sub>m) t"} is made a
  type abbreviation for the fixed record type @{text "\<lparr>c\<^sub>1 ::
  \<sigma>\<^sub>1, \<dots>, c\<^sub>n :: \<sigma>\<^sub>n\<rparr>"}, likewise is @{text
  "(\<alpha>\<^sub>1, \<dots>, \<alpha>\<^sub>m, \<zeta>) t_scheme"} made an abbreviation for
  @{text "\<lparr>c\<^sub>1 :: \<sigma>\<^sub>1, \<dots>, c\<^sub>n :: \<sigma>\<^sub>n, \<dots> ::
  \<zeta>\<rparr>"}.

  \end{description}
*}


subsection {* Record operations *}

text {*
  Any record definition of the form presented above produces certain
  standard operations.  Selectors and updates are provided for any
  field, including the improper one ``@{text more}''.  There are also
  cumulative record constructor functions.  To simplify the
  presentation below, we assume for now that @{text "(\<alpha>\<^sub>1, \<dots>,
  \<alpha>\<^sub>m) t"} is a root record with fields @{text "c\<^sub>1 ::
  \<sigma>\<^sub>1, \<dots>, c\<^sub>n :: \<sigma>\<^sub>n"}.

  \medskip \textbf{Selectors} and \textbf{updates} are available for
  any field (including ``@{text more}''):

  \begin{matharray}{lll}
    @{text "c\<^sub>i"} & @{text "::"} & @{text "\<lparr>\<^vec>c :: \<^vec>\<sigma>, \<dots> :: \<zeta>\<rparr> \<Rightarrow> \<sigma>\<^sub>i"} \\
    @{text "c\<^sub>i_update"} & @{text "::"} & @{text "\<sigma>\<^sub>i \<Rightarrow> \<lparr>\<^vec>c :: \<^vec>\<sigma>, \<dots> :: \<zeta>\<rparr> \<Rightarrow> \<lparr>\<^vec>c :: \<^vec>\<sigma>, \<dots> :: \<zeta>\<rparr>"} \\
  \end{matharray}

  There is special syntax for application of updates: @{text "r\<lparr>x :=
  a\<rparr>"} abbreviates term @{text "x_update a r"}.  Further notation for
  repeated updates is also available: @{text "r\<lparr>x := a\<rparr>\<lparr>y := b\<rparr>\<lparr>z :=
  c\<rparr>"} may be written @{text "r\<lparr>x := a, y := b, z := c\<rparr>"}.  Note that
  because of postfix notation the order of fields shown here is
  reverse than in the actual term.  Since repeated updates are just
  function applications, fields may be freely permuted in @{text "\<lparr>x
  := a, y := b, z := c\<rparr>"}, as far as logical equality is concerned.
  Thus commutativity of independent updates can be proven within the
  logic for any two fields, but not as a general theorem.

  \medskip The \textbf{make} operation provides a cumulative record
  constructor function:

  \begin{matharray}{lll}
    @{text "t.make"} & @{text "::"} & @{text "\<sigma>\<^sub>1 \<Rightarrow> \<dots> \<sigma>\<^sub>n \<Rightarrow> \<lparr>\<^vec>c :: \<^vec>\<sigma>\<rparr>"} \\
  \end{matharray}

  \medskip We now reconsider the case of non-root records, which are
  derived of some parent.  In general, the latter may depend on
  another parent as well, resulting in a list of \emph{ancestor
  records}.  Appending the lists of fields of all ancestors results in
  a certain field prefix.  The record package automatically takes care
  of this by lifting operations over this context of ancestor fields.
  Assuming that @{text "(\<alpha>\<^sub>1, \<dots>, \<alpha>\<^sub>m) t"} has ancestor
  fields @{text "b\<^sub>1 :: \<rho>\<^sub>1, \<dots>, b\<^sub>k :: \<rho>\<^sub>k"},
  the above record operations will get the following types:

  \medskip
  \begin{tabular}{lll}
    @{text "c\<^sub>i"} & @{text "::"} & @{text "\<lparr>\<^vec>b :: \<^vec>\<rho>, \<^vec>c :: \<^vec>\<sigma>, \<dots> :: \<zeta>\<rparr> \<Rightarrow> \<sigma>\<^sub>i"} \\
    @{text "c\<^sub>i_update"} & @{text "::"} & @{text "\<sigma>\<^sub>i \<Rightarrow>
      \<lparr>\<^vec>b :: \<^vec>\<rho>, \<^vec>c :: \<^vec>\<sigma>, \<dots> :: \<zeta>\<rparr> \<Rightarrow>
      \<lparr>\<^vec>b :: \<^vec>\<rho>, \<^vec>c :: \<^vec>\<sigma>, \<dots> :: \<zeta>\<rparr>"} \\
    @{text "t.make"} & @{text "::"} & @{text "\<rho>\<^sub>1 \<Rightarrow> \<dots> \<rho>\<^sub>k \<Rightarrow> \<sigma>\<^sub>1 \<Rightarrow> \<dots> \<sigma>\<^sub>n \<Rightarrow>
      \<lparr>\<^vec>b :: \<^vec>\<rho>, \<^vec>c :: \<^vec>\<sigma>\<rparr>"} \\
  \end{tabular}
  \medskip

  \noindent Some further operations address the extension aspect of a
  derived record scheme specifically: @{text "t.fields"} produces a
  record fragment consisting of exactly the new fields introduced here
  (the result may serve as a more part elsewhere); @{text "t.extend"}
  takes a fixed record and adds a given more part; @{text
  "t.truncate"} restricts a record scheme to a fixed record.

  \medskip
  \begin{tabular}{lll}
    @{text "t.fields"} & @{text "::"} & @{text "\<sigma>\<^sub>1 \<Rightarrow> \<dots> \<sigma>\<^sub>n \<Rightarrow> \<lparr>\<^vec>c :: \<^vec>\<sigma>\<rparr>"} \\
    @{text "t.extend"} & @{text "::"} & @{text "\<lparr>\<^vec>b :: \<^vec>\<rho>, \<^vec>c :: \<^vec>\<sigma>\<rparr> \<Rightarrow>
      \<zeta> \<Rightarrow> \<lparr>\<^vec>b :: \<^vec>\<rho>, \<^vec>c :: \<^vec>\<sigma>, \<dots> :: \<zeta>\<rparr>"} \\
    @{text "t.truncate"} & @{text "::"} & @{text "\<lparr>\<^vec>b :: \<^vec>\<rho>, \<^vec>c :: \<^vec>\<sigma>, \<dots> :: \<zeta>\<rparr> \<Rightarrow> \<lparr>\<^vec>b :: \<^vec>\<rho>, \<^vec>c :: \<^vec>\<sigma>\<rparr>"} \\
  \end{tabular}
  \medskip

  \noindent Note that @{text "t.make"} and @{text "t.fields"} coincide
  for root records.
*}


subsection {* Derived rules and proof tools *}

text {*
  The record package proves several results internally, declaring
  these facts to appropriate proof tools.  This enables users to
  reason about record structures quite conveniently.  Assume that
  @{text t} is a record type as specified above.

  \begin{enumerate}

  \item Standard conversions for selectors or updates applied to
  record constructor terms are made part of the default Simplifier
  context; thus proofs by reduction of basic operations merely require
  the @{method simp} method without further arguments.  These rules
  are available as @{text "t.simps"}, too.

  \item Selectors applied to updated records are automatically reduced
  by an internal simplification procedure, which is also part of the
  standard Simplifier setup.

  \item Inject equations of a form analogous to @{prop "(x, y) = (x',
  y') \<equiv> x = x' \<and> y = y'"} are declared to the Simplifier and Classical
  Reasoner as @{attribute iff} rules.  These rules are available as
  @{text "t.iffs"}.

  \item The introduction rule for record equality analogous to @{text
  "x r = x r' \<Longrightarrow> y r = y r' \<dots> \<Longrightarrow> r = r'"} is declared to the Simplifier,
  and as the basic rule context as ``@{attribute intro}@{text "?"}''.
  The rule is called @{text "t.equality"}.

  \item Representations of arbitrary record expressions as canonical
  constructor terms are provided both in @{method cases} and @{method
  induct} format (cf.\ the generic proof methods of the same name,
  \secref{sec:cases-induct}).  Several variations are available, for
  fixed records, record schemes, more parts etc.

  The generic proof methods are sufficiently smart to pick the most
  sensible rule according to the type of the indicated record
  expression: users just need to apply something like ``@{text "(cases
  r)"}'' to a certain proof problem.

  \item The derived record operations @{text "t.make"}, @{text
  "t.fields"}, @{text "t.extend"}, @{text "t.truncate"} are \emph{not}
  treated automatically, but usually need to be expanded by hand,
  using the collective fact @{text "t.defs"}.

  \end{enumerate}
*}


section {* Datatypes \label{sec:hol-datatype} *}

text {*
  \begin{matharray}{rcl}
    @{command_def (HOL) "datatype"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def (HOL) "rep_datatype"} & : & @{text "theory \<rightarrow> proof(prove)"} \\
  \end{matharray}

  @{rail "
    @@{command (HOL) datatype} (spec + @'and')
    ;
    @@{command (HOL) rep_datatype} ('(' (@{syntax name} +) ')')? (@{syntax term} +)
    ;

    spec: @{syntax parname}? @{syntax typespec} @{syntax mixfix}? '=' (cons + '|')
    ;
    cons: @{syntax name} (@{syntax type} * ) @{syntax mixfix}?
  "}

  \begin{description}

  \item @{command (HOL) "datatype"} defines inductive datatypes in
  HOL.

  \item @{command (HOL) "rep_datatype"} represents existing types as
  inductive ones, generating the standard infrastructure of derived
  concepts (primitive recursion etc.).

  \end{description}

  The induction and exhaustion theorems generated provide case names
  according to the constructors involved, while parameters are named
  after the types (see also \secref{sec:cases-induct}).

  See \cite{isabelle-HOL} for more details on datatypes, but beware of
  the old-style theory syntax being used there!  Apart from proper
  proof methods for case-analysis and induction, there are also
  emulations of ML tactics @{method (HOL) case_tac} and @{method (HOL)
  induct_tac} available, see \secref{sec:hol-induct-tac}; these admit
  to refer directly to the internal structure of subgoals (including
  internally bound parameters).
*}


section {* Functorial structure of types *}

text {*
  \begin{matharray}{rcl}
    @{command_def (HOL) "enriched_type"} & : & @{text "local_theory \<rightarrow> proof(prove)"}
  \end{matharray}

  @{rail "
    @@{command (HOL) enriched_type} (@{syntax name} ':')? @{syntax term}
    ;
  "}

  \begin{description}

  \item @{command (HOL) "enriched_type"}~@{text "prefix: m"} allows to
  prove and register properties about the functorial structure of type
  constructors.  These properties then can be used by other packages
  to deal with those type constructors in certain type constructions.
  Characteristic theorems are noted in the current local theory.  By
  default, they are prefixed with the base name of the type
  constructor, an explicit prefix can be given alternatively.

  The given term @{text "m"} is considered as \emph{mapper} for the
  corresponding type constructor and must conform to the following
  type pattern:

  \begin{matharray}{lll}
    @{text "m"} & @{text "::"} &
      @{text "\<sigma>\<^isub>1 \<Rightarrow> \<dots> \<sigma>\<^isub>k \<Rightarrow> (\<^vec>\<alpha>\<^isub>n) t \<Rightarrow> (\<^vec>\<beta>\<^isub>n) t"} \\
  \end{matharray}

  \noindent where @{text t} is the type constructor, @{text
  "\<^vec>\<alpha>\<^isub>n"} and @{text "\<^vec>\<beta>\<^isub>n"} are distinct
  type variables free in the local theory and @{text "\<sigma>\<^isub>1"},
  \ldots, @{text "\<sigma>\<^isub>k"} is a subsequence of @{text "\<alpha>\<^isub>1 \<Rightarrow>
  \<beta>\<^isub>1"}, @{text "\<beta>\<^isub>1 \<Rightarrow> \<alpha>\<^isub>1"}, \ldots,
  @{text "\<alpha>\<^isub>n \<Rightarrow> \<beta>\<^isub>n"}, @{text "\<beta>\<^isub>n \<Rightarrow>
  \<alpha>\<^isub>n"}.

  \end{description}
*}


section {* Recursive functions \label{sec:recursion} *}

text {*
  \begin{matharray}{rcl}
    @{command_def (HOL) "primrec"} & : & @{text "local_theory \<rightarrow> local_theory"} \\
    @{command_def (HOL) "fun"} & : & @{text "local_theory \<rightarrow> local_theory"} \\
    @{command_def (HOL) "function"} & : & @{text "local_theory \<rightarrow> proof(prove)"} \\
    @{command_def (HOL) "termination"} & : & @{text "local_theory \<rightarrow> proof(prove)"} \\
  \end{matharray}

  @{rail "
    @@{command (HOL) primrec} @{syntax target}? @{syntax \"fixes\"} @'where' equations
    ;
    (@@{command (HOL) fun} | @@{command (HOL) function}) @{syntax target}? functionopts?
      @{syntax \"fixes\"} \\ @'where' equations
    ;

    equations: (@{syntax thmdecl}? @{syntax prop} + '|')
    ;
    functionopts: '(' (('sequential' | 'domintros') + ',') ')'
    ;
    @@{command (HOL) termination} @{syntax term}?
  "}

  \begin{description}

  \item @{command (HOL) "primrec"} defines primitive recursive
  functions over datatypes, see also \cite{isabelle-HOL}.

  \item @{command (HOL) "function"} defines functions by general
  wellfounded recursion. A detailed description with examples can be
  found in \cite{isabelle-function}. The function is specified by a
  set of (possibly conditional) recursive equations with arbitrary
  pattern matching. The command generates proof obligations for the
  completeness and the compatibility of patterns.

  The defined function is considered partial, and the resulting
  simplification rules (named @{text "f.psimps"}) and induction rule
  (named @{text "f.pinduct"}) are guarded by a generated domain
  predicate @{text "f_dom"}. The @{command (HOL) "termination"}
  command can then be used to establish that the function is total.

  \item @{command (HOL) "fun"} is a shorthand notation for ``@{command
  (HOL) "function"}~@{text "(sequential)"}, followed by automated
  proof attempts regarding pattern matching and termination.  See
  \cite{isabelle-function} for further details.

  \item @{command (HOL) "termination"}~@{text f} commences a
  termination proof for the previously defined function @{text f}.  If
  this is omitted, the command refers to the most recent function
  definition.  After the proof is closed, the recursive equations and
  the induction principle is established.

  \end{description}

  Recursive definitions introduced by the @{command (HOL) "function"}
  command accommodate
  reasoning by induction (cf.\ \secref{sec:cases-induct}): rule @{text
  "c.induct"} (where @{text c} is the name of the function definition)
  refers to a specific induction rule, with parameters named according
  to the user-specified equations. Cases are numbered (starting from 1).

  For @{command (HOL) "primrec"}, the induction principle coincides
  with structural recursion on the datatype the recursion is carried
  out.

  The equations provided by these packages may be referred later as
  theorem list @{text "f.simps"}, where @{text f} is the (collective)
  name of the functions defined.  Individual equations may be named
  explicitly as well.

  The @{command (HOL) "function"} command accepts the following
  options.

  \begin{description}

  \item @{text sequential} enables a preprocessor which disambiguates
  overlapping patterns by making them mutually disjoint.  Earlier
  equations take precedence over later ones.  This allows to give the
  specification in a format very similar to functional programming.
  Note that the resulting simplification and induction rules
  correspond to the transformed specification, not the one given
  originally. This usually means that each equation given by the user
  may result in several theorems.  Also note that this automatic
  transformation only works for ML-style datatype patterns.

  \item @{text domintros} enables the automated generation of
  introduction rules for the domain predicate. While mostly not
  needed, they can be helpful in some proofs about partial functions.

  \end{description}
*}


subsection {* Proof methods related to recursive definitions *}

text {*
  \begin{matharray}{rcl}
    @{method_def (HOL) pat_completeness} & : & @{text method} \\
    @{method_def (HOL) relation} & : & @{text method} \\
    @{method_def (HOL) lexicographic_order} & : & @{text method} \\
    @{method_def (HOL) size_change} & : & @{text method} \\
  \end{matharray}

  @{rail "
    @@{method (HOL) relation} @{syntax term}
    ;
    @@{method (HOL) lexicographic_order} (@{syntax clasimpmod} * )
    ;
    @@{method (HOL) size_change} ( orders (@{syntax clasimpmod} * ) )
    ;
    orders: ( 'max' | 'min' | 'ms' ) *
  "}

  \begin{description}

  \item @{method (HOL) pat_completeness} is a specialized method to
  solve goals regarding the completeness of pattern matching, as
  required by the @{command (HOL) "function"} package (cf.\
  \cite{isabelle-function}).

  \item @{method (HOL) relation}~@{text R} introduces a termination
  proof using the relation @{text R}.  The resulting proof state will
  contain goals expressing that @{text R} is wellfounded, and that the
  arguments of recursive calls decrease with respect to @{text R}.
  Usually, this method is used as the initial proof step of manual
  termination proofs.

  \item @{method (HOL) "lexicographic_order"} attempts a fully
  automated termination proof by searching for a lexicographic
  combination of size measures on the arguments of the function. The
  method accepts the same arguments as the @{method auto} method,
  which it uses internally to prove local descents.  The same context
  modifiers as for @{method auto} are accepted, see
  \secref{sec:clasimp}.

  In case of failure, extensive information is printed, which can help
  to analyse the situation (cf.\ \cite{isabelle-function}).

  \item @{method (HOL) "size_change"} also works on termination goals,
  using a variation of the size-change principle, together with a
  graph decomposition technique (see \cite{krauss_phd} for details).
  Three kinds of orders are used internally: @{text max}, @{text min},
  and @{text ms} (multiset), which is only available when the theory
  @{text Multiset} is loaded. When no order kinds are given, they are
  tried in order. The search for a termination proof uses SAT solving
  internally.

 For local descent proofs, the same context modifiers as for @{method
  auto} are accepted, see \secref{sec:clasimp}.

  \end{description}
*}

subsection {* Functions with explicit partiality *}

text {*
  \begin{matharray}{rcl}
    @{command_def (HOL) "partial_function"} & : & @{text "local_theory \<rightarrow> local_theory"} \\
    @{attribute_def (HOL) "partial_function_mono"} & : & @{text attribute} \\
  \end{matharray}

  @{rail "
    @@{command (HOL) partial_function} @{syntax target}?
      '(' @{syntax nameref} ')' @{syntax \"fixes\"} \\
      @'where' @{syntax thmdecl}? @{syntax prop}
  "}

  \begin{description}

  \item @{command (HOL) "partial_function"}~@{text "(mode)"} defines
  recursive functions based on fixpoints in complete partial
  orders. No termination proof is required from the user or
  constructed internally. Instead, the possibility of non-termination
  is modelled explicitly in the result type, which contains an
  explicit bottom element.

  Pattern matching and mutual recursion are currently not supported.
  Thus, the specification consists of a single function described by a
  single recursive equation.

  There are no fixed syntactic restrictions on the body of the
  function, but the induced functional must be provably monotonic
  wrt.\ the underlying order.  The monotonicitity proof is performed
  internally, and the definition is rejected when it fails. The proof
  can be influenced by declaring hints using the
  @{attribute (HOL) partial_function_mono} attribute.

  The mandatory @{text mode} argument specifies the mode of operation
  of the command, which directly corresponds to a complete partial
  order on the result type. By default, the following modes are
  defined:

  \begin{description}
  \item @{text option} defines functions that map into the @{type
  option} type. Here, the value @{term None} is used to model a
  non-terminating computation. Monotonicity requires that if @{term
  None} is returned by a recursive call, then the overall result
  must also be @{term None}. This is best achieved through the use of
  the monadic operator @{const "Option.bind"}.

  \item @{text tailrec} defines functions with an arbitrary result
  type and uses the slightly degenerated partial order where @{term
  "undefined"} is the bottom element.  Now, monotonicity requires that
  if @{term undefined} is returned by a recursive call, then the
  overall result must also be @{term undefined}. In practice, this is
  only satisfied when each recursive call is a tail call, whose result
  is directly returned. Thus, this mode of operation allows the
  definition of arbitrary tail-recursive functions.
  \end{description}

  Experienced users may define new modes by instantiating the locale
  @{const "partial_function_definitions"} appropriately.

  \item @{attribute (HOL) partial_function_mono} declares rules for
  use in the internal monononicity proofs of partial function
  definitions.

  \end{description}

*}

subsection {* Old-style recursive function definitions (TFL) *}

text {*
  The old TFL commands @{command (HOL) "recdef"} and @{command (HOL)
  "recdef_tc"} for defining recursive are mostly obsolete; @{command
  (HOL) "function"} or @{command (HOL) "fun"} should be used instead.

  \begin{matharray}{rcl}
    @{command_def (HOL) "recdef"} & : & @{text "theory \<rightarrow> theory)"} \\
    @{command_def (HOL) "recdef_tc"}@{text "\<^sup>*"} & : & @{text "theory \<rightarrow> proof(prove)"} \\
  \end{matharray}

  @{rail "
    @@{command (HOL) recdef} ('(' @'permissive' ')')? \\
      @{syntax name} @{syntax term} (@{syntax prop} +) hints?
    ;
    recdeftc @{syntax thmdecl}? tc
    ;
    hints: '(' @'hints' ( recdefmod * ) ')'
    ;
    recdefmod: (('recdef_simp' | 'recdef_cong' | 'recdef_wf')
      (() | 'add' | 'del') ':' @{syntax thmrefs}) | @{syntax clasimpmod}
    ;
    tc: @{syntax nameref} ('(' @{syntax nat} ')')?
  "}

  \begin{description}

  \item @{command (HOL) "recdef"} defines general well-founded
  recursive functions (using the TFL package), see also
  \cite{isabelle-HOL}.  The ``@{text "(permissive)"}'' option tells
  TFL to recover from failed proof attempts, returning unfinished
  results.  The @{text recdef_simp}, @{text recdef_cong}, and @{text
  recdef_wf} hints refer to auxiliary rules to be used in the internal
  automated proof process of TFL.  Additional @{syntax clasimpmod}
  declarations (cf.\ \secref{sec:clasimp}) may be given to tune the
  context of the Simplifier (cf.\ \secref{sec:simplifier}) and
  Classical reasoner (cf.\ \secref{sec:classical}).

  \item @{command (HOL) "recdef_tc"}~@{text "c (i)"} recommences the
  proof for leftover termination condition number @{text i} (default
  1) as generated by a @{command (HOL) "recdef"} definition of
  constant @{text c}.

  Note that in most cases, @{command (HOL) "recdef"} is able to finish
  its internal proofs without manual intervention.

  \end{description}

  \medskip Hints for @{command (HOL) "recdef"} may be also declared
  globally, using the following attributes.

  \begin{matharray}{rcl}
    @{attribute_def (HOL) recdef_simp} & : & @{text attribute} \\
    @{attribute_def (HOL) recdef_cong} & : & @{text attribute} \\
    @{attribute_def (HOL) recdef_wf} & : & @{text attribute} \\
  \end{matharray}

  @{rail "
    (@@{attribute (HOL) recdef_simp} | @@{attribute (HOL) recdef_cong} |
      @@{attribute (HOL) recdef_wf}) (() | 'add' | 'del')
  "}
*}


section {* Inductive and coinductive definitions \label{sec:hol-inductive} *}

text {*
  An \textbf{inductive definition} specifies the least predicate (or
  set) @{text R} closed under given rules: applying a rule to elements
  of @{text R} yields a result within @{text R}.  For example, a
  structural operational semantics is an inductive definition of an
  evaluation relation.

  Dually, a \textbf{coinductive definition} specifies the greatest
  predicate~/ set @{text R} that is consistent with given rules: every
  element of @{text R} can be seen as arising by applying a rule to
  elements of @{text R}.  An important example is using bisimulation
  relations to formalise equivalence of processes and infinite data
  structures.

  \medskip The HOL package is related to the ZF one, which is
  described in a separate paper,\footnote{It appeared in CADE
  \cite{paulson-CADE}; a longer version is distributed with Isabelle.}
  which you should refer to in case of difficulties.  The package is
  simpler than that of ZF thanks to implicit type-checking in HOL.
  The types of the (co)inductive predicates (or sets) determine the
  domain of the fixedpoint definition, and the package does not have
  to use inference rules for type-checking.

  \begin{matharray}{rcl}
    @{command_def (HOL) "inductive"} & : & @{text "local_theory \<rightarrow> local_theory"} \\
    @{command_def (HOL) "inductive_set"} & : & @{text "local_theory \<rightarrow> local_theory"} \\
    @{command_def (HOL) "coinductive"} & : & @{text "local_theory \<rightarrow> local_theory"} \\
    @{command_def (HOL) "coinductive_set"} & : & @{text "local_theory \<rightarrow> local_theory"} \\
    @{attribute_def (HOL) mono} & : & @{text attribute} \\
  \end{matharray}

  @{rail "
    (@@{command (HOL) inductive} | @@{command (HOL) inductive_set} |
      @@{command (HOL) coinductive} | @@{command (HOL) coinductive_set})
    @{syntax target}? @{syntax \"fixes\"} (@'for' @{syntax \"fixes\"})? \\
    (@'where' clauses)? (@'monos' @{syntax thmrefs})?
    ;
    clauses: (@{syntax thmdecl}? @{syntax prop} + '|')
    ;
    @@{attribute (HOL) mono} (() | 'add' | 'del')
  "}

  \begin{description}

  \item @{command (HOL) "inductive"} and @{command (HOL)
  "coinductive"} define (co)inductive predicates from the
  introduction rules given in the @{keyword "where"} part.  The
  optional @{keyword "for"} part contains a list of parameters of the
  (co)inductive predicates that remain fixed throughout the
  definition.  The optional @{keyword "monos"} section contains
  \emph{monotonicity theorems}, which are required for each operator
  applied to a recursive set in the introduction rules.  There
  \emph{must} be a theorem of the form @{text "A \<le> B \<Longrightarrow> M A \<le> M B"},
  for each premise @{text "M R\<^sub>i t"} in an introduction rule!

  \item @{command (HOL) "inductive_set"} and @{command (HOL)
  "coinductive_set"} are wrappers for to the previous commands,
  allowing the definition of (co)inductive sets.

  \item @{attribute (HOL) mono} declares monotonicity rules.  These
  rule are involved in the automated monotonicity proof of @{command
  (HOL) "inductive"}.

  \end{description}
*}


subsection {* Derived rules *}

text {*
  Each (co)inductive definition @{text R} adds definitions to the
  theory and also proves some theorems:

  \begin{description}

  \item @{text R.intros} is the list of introduction rules as proven
  theorems, for the recursive predicates (or sets).  The rules are
  also available individually, using the names given them in the
  theory file;

  \item @{text R.cases} is the case analysis (or elimination) rule;

  \item @{text R.induct} or @{text R.coinduct} is the (co)induction
  rule.

  \end{description}

  When several predicates @{text "R\<^sub>1, \<dots>, R\<^sub>n"} are
  defined simultaneously, the list of introduction rules is called
  @{text "R\<^sub>1_\<dots>_R\<^sub>n.intros"}, the case analysis rules are
  called @{text "R\<^sub>1.cases, \<dots>, R\<^sub>n.cases"}, and the list
  of mutual induction rules is called @{text
  "R\<^sub>1_\<dots>_R\<^sub>n.inducts"}.
*}


subsection {* Monotonicity theorems *}

text {*
  Each theory contains a default set of theorems that are used in
  monotonicity proofs.  New rules can be added to this set via the
  @{attribute (HOL) mono} attribute.  The HOL theory @{text Inductive}
  shows how this is done.  In general, the following monotonicity
  theorems may be added:

  \begin{itemize}

  \item Theorems of the form @{text "A \<le> B \<Longrightarrow> M A \<le> M B"}, for proving
  monotonicity of inductive definitions whose introduction rules have
  premises involving terms such as @{text "M R\<^sub>i t"}.

  \item Monotonicity theorems for logical operators, which are of the
  general form @{text "(\<dots> \<longrightarrow> \<dots>) \<Longrightarrow> \<dots> (\<dots> \<longrightarrow> \<dots>) \<Longrightarrow> \<dots> \<longrightarrow> \<dots>"}.  For example, in
  the case of the operator @{text "\<or>"}, the corresponding theorem is
  \[
  \infer{@{text "P\<^sub>1 \<or> P\<^sub>2 \<longrightarrow> Q\<^sub>1 \<or> Q\<^sub>2"}}{@{text "P\<^sub>1 \<longrightarrow> Q\<^sub>1"} & @{text "P\<^sub>2 \<longrightarrow> Q\<^sub>2"}}
  \]

  \item De Morgan style equations for reasoning about the ``polarity''
  of expressions, e.g.
  \[
  @{prop "\<not> \<not> P \<longleftrightarrow> P"} \qquad\qquad
  @{prop "\<not> (P \<and> Q) \<longleftrightarrow> \<not> P \<or> \<not> Q"}
  \]

  \item Equations for reducing complex operators to more primitive
  ones whose monotonicity can easily be proved, e.g.
  \[
  @{prop "(P \<longrightarrow> Q) \<longleftrightarrow> \<not> P \<or> Q"} \qquad\qquad
  @{prop "Ball A P \<equiv> \<forall>x. x \<in> A \<longrightarrow> P x"}
  \]

  \end{itemize}

  %FIXME: Example of an inductive definition
*}


section {* Arithmetic proof support *}

text {*
  \begin{matharray}{rcl}
    @{method_def (HOL) arith} & : & @{text method} \\
    @{attribute_def (HOL) arith} & : & @{text attribute} \\
    @{attribute_def (HOL) arith_split} & : & @{text attribute} \\
  \end{matharray}

  The @{method (HOL) arith} method decides linear arithmetic problems
  (on types @{text nat}, @{text int}, @{text real}).  Any current
  facts are inserted into the goal before running the procedure.

  The @{attribute (HOL) arith} attribute declares facts that are
  always supplied to the arithmetic provers implicitly.

  The @{attribute (HOL) arith_split} attribute declares case split
  rules to be expanded before @{method (HOL) arith} is invoked.

  Note that a simpler (but faster) arithmetic prover is
  already invoked by the Simplifier.
*}


section {* Intuitionistic proof search *}

text {*
  \begin{matharray}{rcl}
    @{method_def (HOL) iprover} & : & @{text method} \\
  \end{matharray}

  @{rail "
    @@{method (HOL) iprover} ( @{syntax rulemod} * )
  "}

  The @{method (HOL) iprover} method performs intuitionistic proof
  search, depending on specifically declared rules from the context,
  or given as explicit arguments.  Chained facts are inserted into the
  goal before commencing proof search.

  Rules need to be classified as @{attribute (Pure) intro},
  @{attribute (Pure) elim}, or @{attribute (Pure) dest}; here the
  ``@{text "!"}'' indicator refers to ``safe'' rules, which may be
  applied aggressively (without considering back-tracking later).
  Rules declared with ``@{text "?"}'' are ignored in proof search (the
  single-step @{method (Pure) rule} method still observes these).  An
  explicit weight annotation may be given as well; otherwise the
  number of rule premises will be taken into account here.
*}


section {* Coherent Logic *}

text {*
  \begin{matharray}{rcl}
    @{method_def (HOL) "coherent"} & : & @{text method} \\
  \end{matharray}

  @{rail "
    @@{method (HOL) coherent} @{syntax thmrefs}?
  "}

  The @{method (HOL) coherent} method solves problems of
  \emph{Coherent Logic} \cite{Bezem-Coquand:2005}, which covers
  applications in confluence theory, lattice theory and projective
  geometry.  See @{file "~~/src/HOL/ex/Coherent.thy"} for some
  examples.
*}


section {* Proving propositions *}

text {*
  In addition to the standard proof methods, a number of diagnosis
  tools search for proofs and provide an Isar proof snippet on success.
  These tools are available via the following commands.

  \begin{matharray}{rcl}
    @{command_def (HOL) "solve_direct"}@{text "\<^sup>*"} & : & @{text "proof \<rightarrow>"} \\
    @{command_def (HOL) "try_methods"}@{text "\<^sup>*"} & : & @{text "proof \<rightarrow>"} \\
    @{command_def (HOL) "sledgehammer"}@{text "\<^sup>*"} & : & @{text "proof \<rightarrow>"} \\
    @{command_def (HOL) "sledgehammer_params"} & : & @{text "theory \<rightarrow> theory"}
  \end{matharray}

  @{rail "
    @@{command (HOL) try_methods} ( ( ( 'simp' | 'intro' | 'elim' | 'dest' ) ':' @{syntax thmrefs} ) + ) ?
      @{syntax nat}?
    ;
    @@{command (HOL) sledgehammer} ( '[' args ']' )? facts? @{syntax nat}?
    ;

    @@{command (HOL) sledgehammer_params} ( ( '[' args ']' ) ? )
    ;

    args: ( @{syntax name} '=' value + ',' )
    ;

    facts: '(' ( ( ( ( 'add' | 'del' ) ':' ) ? @{syntax thmrefs} ) + ) ? ')'
    ;
  "} % FIXME try_methods: proper clasimpmod!?
  % FIXME check args "value"

  \begin{description}

  \item @{command (HOL) "solve_direct"} checks whether the current subgoals can
    be solved directly by an existing theorem. Duplicate lemmas can be detected
    in this way.

  \item @{command (HOL) "try_methods"} attempts to prove a subgoal using a combination
    of standard proof methods (@{text auto}, @{text simp}, @{text blast}, etc.).
    Additional facts supplied via @{text "simp:"}, @{text "intro:"},
    @{text "elim:"}, and @{text "dest:"} are passed to the appropriate proof
    methods.

  \item @{command (HOL) "sledgehammer"} attempts to prove a subgoal using external
    automatic provers (resolution provers and SMT solvers). See the Sledgehammer
    manual \cite{isabelle-sledgehammer} for details.

  \item @{command (HOL) "sledgehammer_params"} changes
    @{command (HOL) "sledgehammer"} configuration options persistently.

  \end{description}
*}


section {* Checking and refuting propositions *}

text {*
  Identifying incorrect propositions usually involves evaluation of
  particular assignments and systematic counterexample search.  This
  is supported by the following commands.

  \begin{matharray}{rcl}
    @{command_def (HOL) "value"}@{text "\<^sup>*"} & : & @{text "context \<rightarrow>"} \\
    @{command_def (HOL) "quickcheck"}@{text "\<^sup>*"} & : & @{text "proof \<rightarrow>"} \\
    @{command_def (HOL) "refute"}@{text "\<^sup>*"} & : & @{text "proof \<rightarrow>"} \\
    @{command_def (HOL) "nitpick"}@{text "\<^sup>*"} & : & @{text "proof \<rightarrow>"} \\
    @{command_def (HOL) "quickcheck_params"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def (HOL) "refute_params"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def (HOL) "nitpick_params"} & : & @{text "theory \<rightarrow> theory"}
  \end{matharray}

  @{rail "
    @@{command (HOL) value} ( '[' name ']' )? modes? @{syntax term}
    ;

    (@@{command (HOL) quickcheck} | @@{command (HOL) refute} | @@{command (HOL) nitpick})
      ( '[' args ']' )? @{syntax nat}?
    ;

    (@@{command (HOL) quickcheck_params} | @@{command (HOL) refute_params} |
      @@{command (HOL) nitpick_params}) ( '[' args ']' )?
    ;

    modes: '(' (@{syntax name} +) ')'
    ;

    args: ( @{syntax name} '=' value + ',' )
    ;
  "} % FIXME check "value"

  \begin{description}

  \item @{command (HOL) "value"}~@{text t} evaluates and prints a
    term; optionally @{text modes} can be specified, which are
    appended to the current print mode (see also \cite{isabelle-ref}).
    Internally, the evaluation is performed by registered evaluators,
    which are invoked sequentially until a result is returned.
    Alternatively a specific evaluator can be selected using square
    brackets; typical evaluators use the current set of code equations
    to normalize and include @{text simp} for fully symbolic evaluation
    using the simplifier, @{text nbe} for \emph{normalization by evaluation}
    and \emph{code} for code generation in SML.

  \item @{command (HOL) "quickcheck"} tests the current goal for
    counterexamples using a series of assignments for its
    free variables; by default the first subgoal is tested, an other
    can be selected explicitly using an optional goal index.
    Assignments can be chosen exhausting the search space upto a given
    size or using a fixed number of random assignments in the search space.
    By default, quickcheck uses exhaustive testing.
    A number of configuration options are supported for
    @{command (HOL) "quickcheck"}, notably:

    \begin{description}

    \item[@{text tester}] specifies how to explore the search space
      (e.g. exhaustive or random).
      An unknown configuration option is treated as an argument to tester,
      making @{text "tester ="} optional.
    \item[@{text size}] specifies the maximum size of the search space
    for assignment values.

    \item[@{text eval}] takes a term or a list of terms and evaluates
      these terms under the variable assignment found by quickcheck.

    \item[@{text iterations}] sets how many sets of assignments are
    generated for each particular size.

    \item[@{text no_assms}] specifies whether assumptions in
    structured proofs should be ignored.

    \item[@{text timeout}] sets the time limit in seconds.

    \item[@{text default_type}] sets the type(s) generally used to
    instantiate type variables.

    \item[@{text report}] if set quickcheck reports how many tests
    fulfilled the preconditions.

    \item[@{text quiet}] if not set quickcheck informs about the
    current size for assignment values.

    \item[@{text expect}] can be used to check if the user's
    expectation was met (@{text no_expectation}, @{text
    no_counterexample}, or @{text counterexample}).

    \end{description}

    These option can be given within square brackets.

  \item @{command (HOL) "quickcheck_params"} changes
    @{command (HOL) "quickcheck"} configuration options persistently.

  \item @{command (HOL) "refute"} tests the current goal for
    counterexamples using a reduction to SAT. The following configuration
    options are supported:

    \begin{description}

    \item[@{text minsize}] specifies the minimum size (cardinality) of the
      models to search for.

    \item[@{text maxsize}] specifies the maximum size (cardinality) of the
      models to search for. Nonpositive values mean $\infty$.

    \item[@{text maxvars}] specifies the maximum number of Boolean variables
    to use when transforming the term into a propositional formula.
    Nonpositive values mean $\infty$.

    \item[@{text satsolver}] specifies the SAT solver to use.

    \item[@{text no_assms}] specifies whether assumptions in
    structured proofs should be ignored.

    \item[@{text maxtime}] sets the time limit in seconds.

    \item[@{text expect}] can be used to check if the user's
    expectation was met (@{text genuine}, @{text potential},
    @{text none}, or @{text unknown}).

    \end{description}

    These option can be given within square brackets.

  \item @{command (HOL) "refute_params"} changes
    @{command (HOL) "refute"} configuration options persistently.

  \item @{command (HOL) "nitpick"} tests the current goal for counterexamples
    using a reduction to first-order relational logic. See the Nitpick manual
    \cite{isabelle-nitpick} for details.

  \item @{command (HOL) "nitpick_params"} changes
    @{command (HOL) "nitpick"} configuration options persistently.

  \end{description}
*}


section {* Unstructured case analysis and induction \label{sec:hol-induct-tac} *}

text {*
  The following tools of Isabelle/HOL support cases analysis and
  induction in unstructured tactic scripts; see also
  \secref{sec:cases-induct} for proper Isar versions of similar ideas.

  \begin{matharray}{rcl}
    @{method_def (HOL) case_tac}@{text "\<^sup>*"} & : & @{text method} \\
    @{method_def (HOL) induct_tac}@{text "\<^sup>*"} & : & @{text method} \\
    @{method_def (HOL) ind_cases}@{text "\<^sup>*"} & : & @{text method} \\
    @{command_def (HOL) "inductive_cases"}@{text "\<^sup>*"} & : & @{text "local_theory \<rightarrow> local_theory"} \\
  \end{matharray}

  @{rail "
    @@{method (HOL) case_tac} @{syntax goal_spec}? @{syntax term} rule?
    ;
    @@{method (HOL) induct_tac} @{syntax goal_spec}? (@{syntax insts} * @'and') rule?
    ;
    @@{method (HOL) ind_cases} (@{syntax prop}+) (@'for' (@{syntax name}+))?
    ;
    @@{command (HOL) inductive_cases} (@{syntax thmdecl}? (@{syntax prop}+) + @'and')
    ;

    rule: 'rule' ':' @{syntax thmref}
  "}

  \begin{description}

  \item @{method (HOL) case_tac} and @{method (HOL) induct_tac} admit
  to reason about inductive types.  Rules are selected according to
  the declarations by the @{attribute cases} and @{attribute induct}
  attributes, cf.\ \secref{sec:cases-induct}.  The @{command (HOL)
  datatype} package already takes care of this.

  These unstructured tactics feature both goal addressing and dynamic
  instantiation.  Note that named rule cases are \emph{not} provided
  as would be by the proper @{method cases} and @{method induct} proof
  methods (see \secref{sec:cases-induct}).  Unlike the @{method
  induct} method, @{method induct_tac} does not handle structured rule
  statements, only the compact object-logic conclusion of the subgoal
  being addressed.

  \item @{method (HOL) ind_cases} and @{command (HOL)
  "inductive_cases"} provide an interface to the internal @{ML_text
  mk_cases} operation.  Rules are simplified in an unrestricted
  forward manner.

  While @{method (HOL) ind_cases} is a proof method to apply the
  result immediately as elimination rules, @{command (HOL)
  "inductive_cases"} provides case split theorems at the theory level
  for later use.  The @{keyword "for"} argument of the @{method (HOL)
  ind_cases} method allows to specify a list of variables that should
  be generalized before applying the resulting rule.

  \end{description}
*}


section {* Executable code *}

text {* For validation purposes, it is often useful to \emph{execute}
  specifications.  In principle, execution could be simulated by
  Isabelle's inference kernel, i.e. by a combination of resolution and
  simplification.  Unfortunately, this approach is rather inefficient.
  A more efficient way of executing specifications is to translate
  them into a functional programming language such as ML.

  Isabelle provides two generic frameworks to support code generation
  from executable specifications.  Isabelle/HOL instantiates these
  mechanisms in a way that is amenable to end-user applications.
*}


subsection {* The new code generator (F. Haftmann) *}

text {* This framework generates code from functional programs
  (including overloading using type classes) to SML \cite{SML}, OCaml
  \cite{OCaml}, Haskell \cite{haskell-revised-report} and Scala
  \cite{scala-overview-tech-report}.  Conceptually, code generation is
  split up in three steps: \emph{selection} of code theorems,
  \emph{translation} into an abstract executable view and
  \emph{serialization} to a specific \emph{target language}.
  Inductive specifications can be executed using the predicate
  compiler which operates within HOL.  See \cite{isabelle-codegen} for
  an introduction.

  \begin{matharray}{rcl}
    @{command_def (HOL) "export_code"}@{text "\<^sup>*"} & : & @{text "context \<rightarrow>"} \\
    @{attribute_def (HOL) code} & : & @{text attribute} \\
    @{command_def (HOL) "code_abort"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def (HOL) "code_datatype"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def (HOL) "print_codesetup"}@{text "\<^sup>*"} & : & @{text "context \<rightarrow>"} \\
    @{attribute_def (HOL) code_inline} & : & @{text attribute} \\
    @{attribute_def (HOL) code_post} & : & @{text attribute} \\
    @{command_def (HOL) "print_codeproc"}@{text "\<^sup>*"} & : & @{text "context \<rightarrow>"} \\
    @{command_def (HOL) "code_thms"}@{text "\<^sup>*"} & : & @{text "context \<rightarrow>"} \\
    @{command_def (HOL) "code_deps"}@{text "\<^sup>*"} & : & @{text "context \<rightarrow>"} \\
    @{command_def (HOL) "code_const"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def (HOL) "code_type"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def (HOL) "code_class"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def (HOL) "code_instance"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def (HOL) "code_reserved"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def (HOL) "code_monad"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def (HOL) "code_include"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def (HOL) "code_modulename"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def (HOL) "code_reflect"} & : & @{text "theory \<rightarrow> theory"}
  \end{matharray}

  @{rail "
    @@{command (HOL) export_code} ( constexpr + ) \\
       ( ( @'in' target ( @'module_name' @{syntax string} ) ? \\
        ( @'file' ( @{syntax string} | '-' ) ) ? ( '(' args ')' ) ?) + ) ?
    ;

    const: @{syntax term}
    ;

    constexpr: ( const | 'name._' | '_' )
    ;

    typeconstructor: @{syntax nameref}
    ;

    class: @{syntax nameref}
    ;

    target: 'SML' | 'OCaml' | 'Haskell' | 'Scala'
    ;

    @@{attribute (HOL) code} ( 'del' | 'abstype' | 'abstract' )?
    ;

    @@{command (HOL) code_abort} ( const + )
    ;

    @@{command (HOL) code_datatype} ( const + )
    ;

    @@{attribute (HOL) code_inline} ( 'del' ) ?
    ;

    @@{attribute (HOL) code_post} ( 'del' ) ?
    ;

    @@{command (HOL) code_thms} ( constexpr + ) ?
    ;

    @@{command (HOL) code_deps} ( constexpr + ) ?
    ;

    @@{command (HOL) code_const} (const + @'and') \\
      ( ( '(' target ( syntax ? + @'and' ) ')' ) + )
    ;

    @@{command (HOL) code_type} (typeconstructor + @'and') \\
      ( ( '(' target ( syntax ? + @'and' ) ')' ) + )
    ;

    @@{command (HOL) code_class} (class + @'and') \\
      ( ( '(' target \\ ( @{syntax string} ? + @'and' ) ')' ) + )
    ;

    @@{command (HOL) code_instance} (( typeconstructor '::' class ) + @'and') \\
      ( ( '(' target ( '-' ? + @'and' ) ')' ) + )
    ;

    @@{command (HOL) code_reserved} target ( @{syntax string} + )
    ;

    @@{command (HOL) code_monad} const const target
    ;

    @@{command (HOL) code_include} target ( @{syntax string} ( @{syntax string} | '-') )
    ;

    @@{command (HOL) code_modulename} target ( ( @{syntax string} @{syntax string} ) + )
    ;

    @@{command (HOL) code_reflect} @{syntax string} \\
      ( @'datatypes' ( @{syntax string} '=' ( '_' | ( @{syntax string} + '|' ) + @'and' ) ) ) ? \\
      ( @'functions' ( @{syntax string} + ) ) ? ( @'file' @{syntax string} ) ?
    ;

    syntax: @{syntax string} | ( @'infix' | @'infixl' | @'infixr' ) @{syntax nat} @{syntax string}
  "}

  \begin{description}

  \item @{command (HOL) "export_code"} generates code for a given list
  of constants in the specified target language(s).  If no
  serialization instruction is given, only abstract code is generated
  internally.

  Constants may be specified by giving them literally, referring to
  all executable contants within a certain theory by giving @{text
  "name.*"}, or referring to \emph{all} executable constants currently
  available by giving @{text "*"}.

  By default, for each involved theory one corresponding name space
  module is generated.  Alternativly, a module name may be specified
  after the @{keyword "module_name"} keyword; then \emph{all} code is
  placed in this module.

  For \emph{SML}, \emph{OCaml} and \emph{Scala} the file specification
  refers to a single file; for \emph{Haskell}, it refers to a whole
  directory, where code is generated in multiple files reflecting the
  module hierarchy.  Omitting the file specification denotes standard
  output.

  Serializers take an optional list of arguments in parentheses.  For
  \emph{SML} and \emph{OCaml}, ``@{text no_signatures}`` omits
  explicit module signatures.

  For \emph{Haskell} a module name prefix may be given using the
  ``@{text "root:"}'' argument; ``@{text string_classes}'' adds a
  ``@{verbatim "deriving (Read, Show)"}'' clause to each appropriate
  datatype declaration.

  \item @{attribute (HOL) code} explicitly selects (or with option
  ``@{text "del"}'' deselects) a code equation for code generation.
  Usually packages introducing code equations provide a reasonable
  default setup for selection.  Variants @{text "code abstype"} and
  @{text "code abstract"} declare abstract datatype certificates or
  code equations on abstract datatype representations respectively.

  \item @{command (HOL) "code_abort"} declares constants which are not
  required to have a definition by means of code equations; if needed
  these are implemented by program abort instead.

  \item @{command (HOL) "code_datatype"} specifies a constructor set
  for a logical type.

  \item @{command (HOL) "print_codesetup"} gives an overview on
  selected code equations and code generator datatypes.

  \item @{attribute (HOL) code_inline} declares (or with option
  ``@{text "del"}'' removes) inlining theorems which are applied as
  rewrite rules to any code equation during preprocessing.

  \item @{attribute (HOL) code_post} declares (or with option ``@{text
  "del"}'' removes) theorems which are applied as rewrite rules to any
  result of an evaluation.

  \item @{command (HOL) "print_codeproc"} prints the setup of the code
  generator preprocessor.

  \item @{command (HOL) "code_thms"} prints a list of theorems
  representing the corresponding program containing all given
  constants after preprocessing.

  \item @{command (HOL) "code_deps"} visualizes dependencies of
  theorems representing the corresponding program containing all given
  constants after preprocessing.

  \item @{command (HOL) "code_const"} associates a list of constants
  with target-specific serializations; omitting a serialization
  deletes an existing serialization.

  \item @{command (HOL) "code_type"} associates a list of type
  constructors with target-specific serializations; omitting a
  serialization deletes an existing serialization.

  \item @{command (HOL) "code_class"} associates a list of classes
  with target-specific class names; omitting a serialization deletes
  an existing serialization.  This applies only to \emph{Haskell}.

  \item @{command (HOL) "code_instance"} declares a list of type
  constructor / class instance relations as ``already present'' for a
  given target.  Omitting a ``@{text "-"}'' deletes an existing
  ``already present'' declaration.  This applies only to
  \emph{Haskell}.

  \item @{command (HOL) "code_reserved"} declares a list of names as
  reserved for a given target, preventing it to be shadowed by any
  generated code.

  \item @{command (HOL) "code_monad"} provides an auxiliary mechanism
  to generate monadic code for Haskell.

  \item @{command (HOL) "code_include"} adds arbitrary named content
  (``include'') to generated code.  A ``@{text "-"}'' as last argument
  will remove an already added ``include''.

  \item @{command (HOL) "code_modulename"} declares aliasings from one
  module name onto another.

  \item @{command (HOL) "code_reflect"} without a ``@{text "file"}''
  argument compiles code into the system runtime environment and
  modifies the code generator setup that future invocations of system
  runtime code generation referring to one of the ``@{text
  "datatypes"}'' or ``@{text "functions"}'' entities use these precompiled
  entities.  With a ``@{text "file"}'' argument, the corresponding code
  is generated into that specified file without modifying the code
  generator setup.

  \end{description}
*}


subsection {* The old code generator (S. Berghofer) *}

text {* This framework generates code from both functional and
  relational programs to SML, as explained below.

  \begin{matharray}{rcl}
    @{command_def "code_module"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def "code_library"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def "consts_code"} & : & @{text "theory \<rightarrow> theory"} \\
    @{command_def "types_code"} & : & @{text "theory \<rightarrow> theory"} \\
    @{attribute_def code} & : & @{text attribute} \\
  \end{matharray}

  @{rail "
  ( @@{command code_module} | @@{command code_library} ) modespec? @{syntax name}? \\
    ( @'file' name ) ? ( @'imports' ( @{syntax name} + ) ) ? \\
    @'contains' ( ( @{syntax name} '=' @{syntax term} ) + | @{syntax term} + )
  ;

  modespec: '(' ( @{syntax name} * ) ')'
  ;

  @@{command (HOL) consts_code} (codespec +)
  ;

  codespec: const template attachment ?
  ;

  @@{command (HOL) types_code} (tycodespec +)
  ;

  tycodespec: @{syntax name} template attachment ?
  ;

  const: @{syntax term}
  ;

  template: '(' @{syntax string} ')'
  ;

  attachment: 'attach' modespec? '{' @{syntax text} '}'
  ;

  @@{attribute code} name?
  "}
*}


subsubsection {* Invoking the code generator *}

text {* The code generator is invoked via the @{command code_module}
  and @{command code_library} commands, which correspond to
  \emph{incremental} and \emph{modular} code generation, respectively.

  \begin{description}

  \item [Modular] For each theory, an ML structure is generated,
  containing the code generated from the constants defined in this
  theory.

  \item [Incremental] All the generated code is emitted into the same
  structure.  This structure may import code from previously generated
  structures, which can be specified via @{keyword "imports"}.
  Moreover, the generated structure may also be referred to in later
  invocations of the code generator.

  \end{description}

  After the @{command code_module} and @{command code_library}
  keywords, the user may specify an optional list of ``modes'' in
  parentheses. These can be used to instruct the code generator to
  emit additional code for special purposes, e.g.\ functions for
  converting elements of generated datatypes to Isabelle terms, or
  test data generators. The list of modes is followed by a module
  name.  The module name is optional for modular code generation, but
  must be specified for incremental code generation.

  The code can either be written to a file, in which case a file name
  has to be specified after the @{keyword "file"} keyword, or be loaded
  directly into Isabelle's ML environment. In the latter case, the
  @{command ML} theory command can be used to inspect the results
  interactively, for example.

  The terms from which to generate code can be specified after the
  @{keyword "contains"} keyword, either as a list of bindings, or just
  as a list of terms. In the latter case, the code generator just
  produces code for all constants and types occuring in the term, but
  does not bind the compiled terms to ML identifiers.

  Here is an example:
*}

code_module Test
contains test = "foldl op + (0 :: int) [1, 2, 3, 4, 5]"

text {* \noindent This binds the result of compiling the given term to
  the ML identifier @{ML Test.test}.  *}

ML {* @{assert} (Test.test = 15) *}


subsubsection {* Configuring the code generator *}

text {* When generating code for a complex term, the code generator
  recursively calls itself for all subterms.  When it arrives at a
  constant, the default strategy of the code generator is to look up
  its definition and try to generate code for it.  Constants which
  have no definitions that are immediately executable, may be
  associated with a piece of ML code manually using the @{command_ref
  consts_code} command.  It takes a list whose elements consist of a
  constant (given in usual term syntax -- an explicit type constraint
  accounts for overloading), and a mixfix template describing the ML
  code. The latter is very much the same as the mixfix templates used
  when declaring new constants.  The most notable difference is that
  terms may be included in the ML template using antiquotation
  brackets @{verbatim "{"}@{verbatim "*"}~@{text "..."}~@{verbatim
  "*"}@{verbatim "}"}.

  A similar mechanism is available for types: @{command_ref
  types_code} associates type constructors with specific ML code.

  For example, the following declarations copied from @{file
  "~~/src/HOL/Product_Type.thy"} describe how the product type of
  Isabelle/HOL should be compiled to ML.  *}

typedecl ('a, 'b) prod
consts Pair :: "'a \<Rightarrow> 'b \<Rightarrow> ('a, 'b) prod"

types_code prod  ("(_ */ _)")
consts_code Pair  ("(_,/ _)")

text {* Sometimes, the code associated with a constant or type may
  need to refer to auxiliary functions, which have to be emitted when
  the constant is used. Code for such auxiliary functions can be
  declared using @{keyword "attach"}. For example, the @{const wfrec}
  function can be implemented as follows:
*}

consts_code wfrec  ("\<module>wfrec?")  (* FIXME !? *)
attach {* fun wfrec f x = f (wfrec f) x *}

text {* If the code containing a call to @{const wfrec} resides in an
  ML structure different from the one containing the function
  definition attached to @{const wfrec}, the name of the ML structure
  (followed by a ``@{text "."}'')  is inserted in place of ``@{text
  "\<module>"}'' in the above template.  The ``@{text "?"}''  means that
  the code generator should ignore the first argument of @{const
  wfrec}, i.e.\ the termination relation, which is usually not
  executable.

  \medskip Another possibility of configuring the code generator is to
  register theorems to be used for code generation. Theorems can be
  registered via the @{attribute code} attribute. It takes an optional
  name as an argument, which indicates the format of the
  theorem. Currently supported formats are equations (this is the
  default when no name is specified) and horn clauses (this is
  indicated by the name \texttt{ind}). The left-hand sides of
  equations may only contain constructors and distinct variables,
  whereas horn clauses must have the same format as introduction rules
  of inductive definitions.

  The following example specifies three equations from which to
  generate code for @{term "op <"} on natural numbers (see also
  @{"file" "~~/src/HOL/Nat.thy"}).  *}

lemma [code]: "(Suc m < Suc n) = (m < n)"
  and [code]: "((n::nat) < 0) = False"
  and [code]: "(0 < Suc n) = True" by simp_all


subsubsection {* Specific HOL code generators *}

text {* The basic code generator framework offered by Isabelle/Pure
  has already been extended with additional code generators for
  specific HOL constructs. These include datatypes, recursive
  functions and inductive relations. The code generator for inductive
  relations can handle expressions of the form @{text "(t\<^sub>1, \<dots>, t\<^sub>n) \<in>
  r"}, where @{text "r"} is an inductively defined relation. If at
  least one of the @{text "t\<^sub>i"} is a dummy pattern ``@{text "_"}'',
  the above expression evaluates to a sequence of possible answers. If
  all of the @{text "t\<^sub>i"} are proper terms, the expression evaluates
  to a boolean value.

  The following example demonstrates this for beta-reduction on lambda
  terms (see also @{"file" "~~/src/HOL/Proofs/Lambda/Lambda.thy"}).
*}

datatype dB =
    Var nat
  | App dB dB  (infixl "\<degree>" 200)
  | Abs dB

primrec lift :: "dB \<Rightarrow> nat \<Rightarrow> dB"
where
    "lift (Var i) k = (if i < k then Var i else Var (i + 1))"
  | "lift (s \<degree> t) k = lift s k \<degree> lift t k"
  | "lift (Abs s) k = Abs (lift s (k + 1))"

primrec subst :: "dB \<Rightarrow> dB \<Rightarrow> nat \<Rightarrow> dB"  ("_[_'/_]" [300, 0, 0] 300)
where
    "(Var i)[s/k] =
      (if k < i then Var (i - 1) else if i = k then s else Var i)"
  | "(t \<degree> u)[s/k] = t[s/k] \<degree> u[s/k]"
  | "(Abs t)[s/k] = Abs (t[lift s 0 / k+1])"

inductive beta :: "dB \<Rightarrow> dB \<Rightarrow> bool"  (infixl "\<rightarrow>\<^sub>\<beta>" 50)
where
    beta: "Abs s \<degree> t \<rightarrow>\<^sub>\<beta> s[t/0]"
  | appL: "s \<rightarrow>\<^sub>\<beta> t \<Longrightarrow> s \<degree> u \<rightarrow>\<^sub>\<beta> t \<degree> u"
  | appR: "s \<rightarrow>\<^sub>\<beta> t \<Longrightarrow> u \<degree> s \<rightarrow>\<^sub>\<beta> u \<degree> t"
  | abs: "s \<rightarrow>\<^sub>\<beta> t \<Longrightarrow> Abs s \<rightarrow>\<^sub>\<beta> Abs t"

code_module Test
contains
  test1 = "Abs (Var 0) \<degree> Var 0 \<rightarrow>\<^sub>\<beta> Var 0"
  test2 = "Abs (Abs (Var 0 \<degree> Var 0) \<degree> (Abs (Var 0) \<degree> Var 0)) \<rightarrow>\<^sub>\<beta> _"

text {*
  In the above example, @{ML Test.test1} evaluates to a boolean,
  whereas @{ML Test.test2} is a lazy sequence whose elements can be
  inspected separately.
*}

ML {* @{assert} Test.test1 *}
ML {* val results = DSeq.list_of Test.test2 *}
ML {* @{assert} (length results = 2) *}

text {*
  \medskip The theory underlying the HOL code generator is described
  more detailed in \cite{Berghofer-Nipkow:2002}. More examples that
  illustrate the usage of the code generator can be found e.g.\ in
  @{"file" "~~/src/HOL/MicroJava/J/JListExample.thy"} and @{"file"
  "~~/src/HOL/MicroJava/JVM/JVMListExample.thy"}.
*}


section {* Definition by specification \label{sec:hol-specification} *}

text {*
  \begin{matharray}{rcl}
    @{command_def (HOL) "specification"} & : & @{text "theory \<rightarrow> proof(prove)"} \\
    @{command_def (HOL) "ax_specification"} & : & @{text "theory \<rightarrow> proof(prove)"} \\
  \end{matharray}

  @{rail "
  (@@{command (HOL) specification} | @@{command (HOL) ax_specification})
    '(' (decl +) ')' \\ (@{syntax thmdecl}? @{syntax prop} +)
  ;
  decl: ((@{syntax name} ':')? @{syntax term} '(' @'overloaded' ')'?)
  "}

  \begin{description}

  \item @{command (HOL) "specification"}~@{text "decls \<phi>"} sets up a
  goal stating the existence of terms with the properties specified to
  hold for the constants given in @{text decls}.  After finishing the
  proof, the theory will be augmented with definitions for the given
  constants, as well as with theorems stating the properties for these
  constants.

  \item @{command (HOL) "ax_specification"}~@{text "decls \<phi>"} sets up
  a goal stating the existence of terms with the properties specified
  to hold for the constants given in @{text decls}.  After finishing
  the proof, the theory will be augmented with axioms expressing the
  properties given in the first place.

  \item @{text decl} declares a constant to be defined by the
  specification given.  The definition for the constant @{text c} is
  bound to the name @{text c_def} unless a theorem name is given in
  the declaration.  Overloaded constants should be declared as such.

  \end{description}

  Whether to use @{command (HOL) "specification"} or @{command (HOL)
  "ax_specification"} is to some extent a matter of style.  @{command
  (HOL) "specification"} introduces no new axioms, and so by
  construction cannot introduce inconsistencies, whereas @{command
  (HOL) "ax_specification"} does introduce axioms, but only after the
  user has explicitly proven it to be safe.  A practical issue must be
  considered, though: After introducing two constants with the same
  properties using @{command (HOL) "specification"}, one can prove
  that the two constants are, in fact, equal.  If this might be a
  problem, one should use @{command (HOL) "ax_specification"}.
*}

end
