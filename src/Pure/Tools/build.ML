(*  Title:      Pure/Tools/build.ML
    Author:     Makarius

Build Isabelle sessions.
*)

signature BUILD =
sig
  val build: string -> unit
end;

structure Build: BUILD =
struct

(* command timings *)

type timings = ((string * Time.time) Inttab.table) Symtab.table;  (*file -> offset -> name, time*)

val empty_timings: timings = Symtab.empty;

fun update_timings props =
  (case Markup.parse_command_timing_properties props of
    SOME ({file, offset, name}, time) =>
      Symtab.map_default (file, Inttab.empty)
        (Inttab.map_default (offset, (name, time)) (fn (_, t) => (name, t + time)))
  | NONE => I);

fun approximative_id name pos =
  (case (Position.file_of pos, Position.offset_of pos) of
    (SOME file, SOME offset) =>
      if name = "" then NONE else SOME {file = file, offset = offset, name = name}
  | _ => NONE);

fun get_timings timings tr =
  (case approximative_id (Toplevel.name_of tr) (Toplevel.pos_of tr) of
    SOME {file, offset, name} =>
      (case Symtab.lookup timings file of
        SOME offsets =>
          (case Inttab.lookup offsets offset of
            SOME (name', time) => if name = name' then SOME time else NONE
          | NONE => NONE)
      | NONE => NONE)
  | NONE => NONE)
  |> the_default Time.zeroTime;


(* session timing *)

fun session_timing name verbose f x =
  let
    val start = Timing.start ();
    val y = f x;
    val timing = Timing.result start;

    val threads = string_of_int (Multithreading.max_threads ());
    val factor = Time.toReal (#cpu timing) / Time.toReal (#elapsed timing)
      |> Real.fmt (StringCvt.FIX (SOME 2));

    val timing_props =
      [("threads", threads)] @ Markup.timing_properties timing @ [("factor", factor)];
    val _ = writeln ("\fTiming = " ^ YXML.string_of_body (XML.Encode.properties timing_props));
    val _ =
      if verbose then
        Output.physical_stderr ("Timing " ^ name ^ " (" ^
          threads ^ " threads, " ^ Timing.message timing ^ ", factor " ^ factor ^ ")\n")
      else ();
  in y end;


(* protocol messages *)

fun inline_message a args =
  writeln ("\f" ^ a ^ " = " ^ YXML.string_of_body (XML.Encode.properties args));

fun protocol_message props output =
  (case props of
    function :: args =>
      if function = Markup.ML_statistics orelse function = Markup.task_statistics then
        inline_message (#2 function) args
      else if function = Markup.command_timing then
        let
          val name = the_default "" (Properties.get args Markup.nameN);
          val pos = Position.of_properties args;
          val {elapsed, ...} = Markup.parse_timing_properties args;
          val is_significant =
            Timing.is_relevant_time elapsed andalso
            elapsed >= Options.default_seconds "command_timing_threshold";
        in
          if is_significant then
            (case approximative_id name pos of
              SOME id => inline_message (#2 function) (Markup.command_timing_properties id elapsed)
            | NONE => ())
          else ()
        end
      else
        (case Markup.dest_loading_theory props of
          SOME name => writeln ("\floading_theory = " ^ name)
        | NONE => raise Output.Protocol_Message props)
  | [] => raise Output.Protocol_Message props);


(* build *)

fun build_theories symbols last_timing master_dir (options, thys) =
  let
    val condition = space_explode "," (Options.string options "condition");
    val conds = filter_out (can getenv_strict) condition;
  in
    if null conds then
      (if Options.bool options "checkpoint" then ML_Heap.share_common_data () else ();
        Options.set_default options;
        Isabelle_Process.init_options ();
        Future.fork I;
        (Thy_Info.use_theories {
          document = Present.document_enabled (Options.string options "document"),
          symbols = symbols,
          last_timing = last_timing,
          master_dir = master_dir}
        |>
          (case Options.string options "profiling" of
            "" => I
          | "time" => profile_time
          | "allocations" => profile_allocations
          | bad => error ("Bad profiling option: " ^ quote bad))
        |> Unsynchronized.setmp print_mode
            (space_explode "," (Options.string options "print_mode") @ print_mode_value ())) thys)
    else
      Output.physical_stderr ("Skipping theories " ^ commas_quote (map #1 thys) ^
        " (undefined " ^ commas conds ^ ")\n")
  end;

fun build args_file =
  let
    val _ = SHA1.test_samples ();

    val (symbol_codes, (command_timings, (do_output, (verbose, (browser_info,
          (document_files, (graph_file, (parent_name, (chapter, (name, theories)))))))))) =
      File.read (Path.explode args_file) |> YXML.parse_body |>
        let open XML.Decode in
          pair (list (pair string int)) (pair (list properties) (pair bool
            (pair bool (pair string (pair (list (pair string string)) (pair string
              (pair string (pair string (pair string
              ((list (pair Options.decode (list (string #> rpair Position.none))))))))))))))
        end;

    val symbols = HTML.make_symbols symbol_codes;
    val _ = Options.load_default ();
    val _ = Isabelle_Process.init_options ();

    val _ = writeln ("\fSession.name = " ^ name);
    val _ =
      Session.init
        symbols
        do_output
        (Options.default_bool "browser_info")
        (Path.explode browser_info)
        (Options.default_string "document")
        (Options.default_string "document_output")
        (Present.document_variants (Options.default_string "document_variants"))
        (map (apply2 Path.explode) document_files)
        (Path.explode graph_file)
        parent_name (chapter, name)
        verbose;

    val last_timing = get_timings (fold update_timings command_timings empty_timings);

    val res1 =
      theories |>
        (List.app (build_theories symbols last_timing Path.current)
          |> session_timing name verbose
          |> Unsynchronized.setmp Private_Output.protocol_message_fn protocol_message
          |> Exn.capture);
    val res2 = Exn.capture Session.finish ();
    val _ = Par_Exn.release_all [res1, res2];

    val _ = Options.reset_default ();
  in () end;


(* PIDE protocol *)

val _ =
  Isabelle_Process.protocol_command "build_theories"
    (fn [id, symbol_codes_yxml, master_dir, theories_yxml] =>
      let
        val symbols =
          YXML.parse_body symbol_codes_yxml
          |> let open XML.Decode in list (pair string int) end
          |> HTML.make_symbols;
        val theories =
          YXML.parse_body theories_yxml |>
            let open XML.Decode
            in list (pair Options.decode (list (string #> rpair Position.none))) end;
        val res1 =
          Exn.capture
            (fn () =>
              theories
              |> List.app (build_theories symbols (K Time.zeroTime) (Path.explode master_dir))) ();
        val res2 = Exn.capture Session.shutdown ();
        val result =
          (Par_Exn.release_all [res1, res2]; "") handle exn =>
            (Runtime.exn_message exn handle _ (*sic!*) =>
              "Exception raised, but failed to print details!");
    in Output.protocol_message (Markup.build_theories_result id) [result] end);

end;
