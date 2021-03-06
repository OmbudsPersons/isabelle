/*  Title:      Pure/Tools/build.scala
    Author:     Makarius
    Options:    :folding=explicit:

Build and manage Isabelle sessions.
*/

package isabelle


import java.io.{BufferedInputStream, FileInputStream,
  BufferedReader, InputStreamReader, IOException}
import java.util.zip.GZIPInputStream

import scala.collection.SortedSet
import scala.collection.mutable
import scala.annotation.tailrec


object Build
{
  /** auxiliary **/

  /* persistent build info */

  sealed case class Session_Info(
    sources: List[String],
    input_heaps: List[String],
    output_heap: Option[String],
    return_code: Int)


  /* queue with scheduling information */

  private object Queue
  {
    def load_timings(store: Sessions.Store, name: String): (List[Properties.T], Double) =
    {
      val no_timings: (List[Properties.T], Double) = (Nil, 0.0)

      store.find_database(name) match {
        case None => no_timings
        case Some(database) =>
          def ignore_error(msg: String) =
          {
            Output.warning("Ignoring bad database: " + database + (if (msg == "") "" else "\n" + msg))
            no_timings
          }
          try {
            using(SQLite.open_database(database))(db =>
            {
              val build_log = store.read_build_log(db, name, command_timings = true)
              val session_timing = Markup.Elapsed.unapply(build_log.session_timing) getOrElse 0.0
              (build_log.command_timings, session_timing)
            })
          }
          catch {
            case ERROR(msg) => ignore_error(msg)
            case exn: java.lang.Error => ignore_error(Exn.message(exn))
            case _: XML.Error => ignore_error("")
          }
      }
    }

    def apply(tree: Sessions.Tree, store: Sessions.Store): Queue =
    {
      val graph = tree.graph
      val sessions = graph.keys

      val timings = sessions.map(name => (name, load_timings(store, name)))
      val command_timings =
        Map(timings.map({ case (name, (ts, _)) => (name, ts) }): _*).withDefaultValue(Nil)
      val session_timing =
        Map(timings.map({ case (name, (_, t)) => (name, t) }): _*).withDefaultValue(0.0)

      def outdegree(name: String): Int = graph.imm_succs(name).size

      object Ordering extends scala.math.Ordering[String]
      {
        def compare_timing(name1: String, name2: String): Int =
        {
          val t1 = session_timing(name1)
          val t2 = session_timing(name2)
          if (t1 == 0.0 || t2 == 0.0) 0
          else t1 compare t2
        }

        def compare(name1: String, name2: String): Int =
          outdegree(name2) compare outdegree(name1) match {
            case 0 =>
              compare_timing(name2, name1) match {
                case 0 =>
                  tree(name2).timeout compare tree(name1).timeout match {
                    case 0 => name1 compare name2
                    case ord => ord
                  }
                case ord => ord
              }
            case ord => ord
          }
      }

      new Queue(graph, SortedSet(sessions: _*)(Ordering), command_timings)
    }
  }

  private final class Queue private(
    graph: Graph[String, Sessions.Info],
    order: SortedSet[String],
    val command_timings: String => List[Properties.T])
  {
    def is_inner(name: String): Boolean = !graph.is_maximal(name)

    def is_empty: Boolean = graph.is_empty

    def - (name: String): Queue =
      new Queue(graph.del_node(name),
        order - name,  // FIXME scala-2.10.0 TreeSet problem!?
        command_timings)

    def dequeue(skip: String => Boolean): Option[(String, Sessions.Info)] =
    {
      val it = order.iterator.dropWhile(name =>
        skip(name)
          || !graph.defined(name)  // FIXME scala-2.10.0 TreeSet problem!?
          || !graph.is_minimal(name))
      if (it.hasNext) { val name = it.next; Some((name, graph.get_node(name))) }
      else None
    }
  }


  /* jobs */

  private class Job(progress: Progress, name: String, val info: Sessions.Info, tree: Sessions.Tree,
    store: Sessions.Store, do_output: Boolean, verbose: Boolean, val numa_node: Option[Int],
    session_graph: Graph_Display.Graph, command_timings: List[Properties.T])
  {
    val output = store.output_dir + Path.basic(name)
    def output_path: Option[Path] = if (do_output) Some(output) else None
    def output_save_state: String =
      if (do_output) "ML_Heap.save_child " + ML_Syntax.print_string0(File.platform_path(output))
      else ""
    output.file.delete

    private val parent = info.parent.getOrElse("")

    private val graph_file = Isabelle_System.tmp_file("session_graph", "pdf")
    try { isabelle.graphview.Graph_File.write(info.options, graph_file, session_graph) }
    catch { case ERROR(_) => /*error should be exposed in ML*/ }

    private val env =
      Isabelle_System.settings() +
        ("ISABELLE_ML_DEBUGGER" -> info.options.bool("ML_debugger").toString)

    private val future_result: Future[Process_Result] =
      Future.thread("build") {
        val args_file = Isabelle_System.tmp_file("build")
        File.write(args_file, YXML.string_of_body(
            {
              val theories = info.theories.map(x => (x._2, x._3))
              import XML.Encode._
              pair(list(pair(string, int)), pair(list(properties), pair(bool, pair(bool,
                pair(Path.encode, pair(list(pair(Path.encode, Path.encode)), pair(string,
                pair(string, pair(string, pair(string,
                list(pair(Options.encode, list(Path.encode)))))))))))))(
              (Symbol.codes, (command_timings, (do_output, (verbose,
                (store.browser_info, (info.document_files, (File.standard_path(graph_file),
                (parent, (info.chapter, (name,
                theories)))))))))))
            }))

        val eval =
          "Command_Line.tool0 (fn () => (" +
          "Build.build " + ML_Syntax.print_string0(File.standard_path(args_file)) +
          (if (do_output) "; ML_Heap.share_common_data (); " + output_save_state
           else "") + "));"

        val process_options =
          numa_node match {
            case None => info.options
            case Some(n) => info.options.string("ML_process_policy") = NUMA.policy(n)
          }
        val process =
          if (Sessions.pure_name(name)) {
            ML_Process(process_options, raw_ml_system = true, cwd = info.dir.file,
              args =
                (for ((root, _) <- Thy_Header.ml_roots) yield List("--use", root)).flatten :::
                List("--eval", eval),
              env = env, tree = Some(tree), store = store, cleanup = () => args_file.delete)
          }
          else {
            ML_Process(process_options, parent, List("--eval", eval), cwd = info.dir.file,
              env = env, tree = Some(tree), store = store, cleanup = () => args_file.delete)
          }

        process.result(
          progress_stdout = (line: String) =>
            Library.try_unprefix("\floading_theory = ", line) match {
              case Some(theory) => progress.theory(name, theory)
              case None =>
            },
          progress_limit =
            info.options.int("process_output_limit") match {
              case 0 => None
              case m => Some(m * 1000000L)
            },
          strict = false)
      }

    def terminate: Unit = future_result.cancel
    def is_finished: Boolean = future_result.is_finished

    @volatile private var was_timeout = false
    private val timeout_request: Option[Event_Timer.Request] =
    {
      if (info.timeout > Time.zero)
        Some(Event_Timer.request(Time.now() + info.timeout) { terminate; was_timeout = true })
      else None
    }

    def join: Process_Result =
    {
      val result = future_result.join

      if (result.ok)
        Present.finish(progress, store.browser_info, graph_file, info, name)

      graph_file.delete
      timeout_request.foreach(_.cancel)

      if (result.interrupted) {
        if (was_timeout) result.error(Output.error_text("Timeout")).was_timeout
        else result.error(Output.error_text("Interrupt"))
      }
      else result
    }
  }



  /** build with results **/

  class Results private[Build](results: Map[String, (Option[Process_Result], Sessions.Info)])
  {
    def sessions: Set[String] = results.keySet
    def cancelled(name: String): Boolean = results(name)._1.isEmpty
    def apply(name: String): Process_Result = results(name)._1.getOrElse(Process_Result(1))
    def info(name: String): Sessions.Info = results(name)._2
    val rc =
      (0 /: results.iterator.map(
        { case (_, (Some(r), _)) => r.rc case (_, (None, _)) => 1 }))(_ max _)
    def ok: Boolean = rc == 0

    override def toString: String = rc.toString
  }

  def build(
    options: Options,
    progress: Progress = No_Progress,
    build_heap: Boolean = false,
    clean_build: Boolean = false,
    dirs: List[Path] = Nil,
    select_dirs: List[Path] = Nil,
    numa_shuffling: Boolean = false,
    max_jobs: Int = 1,
    list_files: Boolean = false,
    check_keywords: Set[String] = Set.empty,
    no_build: Boolean = false,
    system_mode: Boolean = false,
    verbose: Boolean = false,
    requirements: Boolean = false,
    all_sessions: Boolean = false,
    exclude_session_groups: List[String] = Nil,
    exclude_sessions: List[String] = Nil,
    session_groups: List[String] = Nil,
    sessions: List[String] = Nil): Results =
  {
    build_selection(
      options = options,
      progress = progress,
      build_heap = build_heap,
      clean_build = clean_build,
      dirs = dirs,
      select_dirs = select_dirs,
      numa_shuffling = numa_shuffling,
      max_jobs = max_jobs,
      list_files = list_files,
      check_keywords = check_keywords,
      no_build = no_build,
      system_mode = system_mode,
      verbose = verbose,
      selection = { full_tree =>
        full_tree.selection(requirements, all_sessions,
          exclude_session_groups, exclude_sessions, session_groups, sessions) })
  }

  def build_selection(
    options: Options,
    progress: Progress = No_Progress,
    build_heap: Boolean = false,
    clean_build: Boolean = false,
    dirs: List[Path] = Nil,
    select_dirs: List[Path] = Nil,
    numa_shuffling: Boolean = false,
    max_jobs: Int = 1,
    list_files: Boolean = false,
    check_keywords: Set[String] = Set.empty,
    no_build: Boolean = false,
    system_mode: Boolean = false,
    verbose: Boolean = false,
    selection: Sessions.Tree => (List[String], Sessions.Tree) =
      (_.selection(all_sessions = true))): Results =
  {
    /* session selection and dependencies */

    val build_options = options.int.update("completion_limit", 0).bool.update("ML_statistics", true)
    val full_tree = Sessions.load(build_options, dirs, select_dirs)
    val (selected, selected_tree) = selection(full_tree)
    val deps =
      Sessions.dependencies(progress, true, verbose, list_files, check_keywords, selected_tree)

    def sources_stamp(name: String): List[String] =
      (selected_tree(name).meta_digest :: deps.sources(name)).map(_.toString).sorted


    /* main build process */

    val store = Sessions.store(system_mode)
    val queue = Queue(selected_tree, store)

    store.prepare_output()

    // optional cleanup
    if (clean_build) {
      for (name <- full_tree.graph.all_succs(selected)) {
        val files =
          List(Path.basic(name), store.database(name), store.log(name), store.log_gz(name)).
            map(store.output_dir + _).filter(_.is_file)
        if (files.nonEmpty) progress.echo("Cleaning " + name + " ...")
        if (!files.forall(p => p.file.delete)) progress.echo(name + " FAILED to delete")
      }
    }

    // scheduler loop
    case class Result(
      current: Boolean, heap_stamp: Option[String],
      process: Option[Process_Result], info: Sessions.Info)
    {
      def ok: Boolean =
        process match {
          case None => false
          case Some(res) => res.rc == 0
        }
    }

    def sleep()
    {
      try { Thread.sleep(500) }
      catch { case Exn.Interrupt() => Exn.Interrupt.impose() }
    }

    val numa_nodes = new NUMA.Nodes(numa_shuffling)

    @tailrec def loop(
      pending: Queue,
      running: Map[String, (List[String], Job)],
      results: Map[String, Result]): Map[String, Result] =
    {
      def used_node(i: Int): Boolean =
        running.iterator.exists(
          { case (_, (_, job)) => job.numa_node.isDefined && job.numa_node.get == i })

      if (pending.is_empty) results
      else {
        if (progress.stopped)
          for ((_, (_, job)) <- running) job.terminate

        running.find({ case (_, (_, job)) => job.is_finished }) match {
          case Some((name, (input_heaps, job))) =>
            //{{{ finish job

            val process_result = job.join
            process_result.err_lines.foreach(progress.echo(_))
            if (process_result.ok)
              progress.echo("Finished " + name + " (" + process_result.timing.message_resources + ")")

            val log_lines = process_result.out_lines.filterNot(_.startsWith("\f"))
            val process_result_tail =
            {
              val tail = job.info.options.int("process_output_tail")
              process_result.copy(
                out_lines =
                  "(see also " + (store.output_dir + store.log(name)).file.toString + ")" ::
                  (if (tail == 0) log_lines else log_lines.drop(log_lines.length - tail max 0)))
            }

            val heap_stamp =
              if (process_result.ok) {
                (store.output_dir + store.log(name)).file.delete
                val heap_stamp =
                  for (path <- job.output_path if path.is_file)
                    yield Sessions.write_heap_digest(path)

                File.write_gzip(store.output_dir + store.log_gz(name), terminate_lines(log_lines))

                heap_stamp
              }
              else {
                (store.output_dir + Path.basic(name)).file.delete
                (store.output_dir + store.log_gz(name)).file.delete

                File.write(store.output_dir + store.log(name), terminate_lines(log_lines))
                progress.echo(name + " FAILED")
                if (!process_result.interrupted) progress.echo(process_result_tail.out)

                None
              }

            // write database
            {
              val database = store.output_dir + store.database(name)
              database.file.delete

              using(SQLite.open_database(database))(db =>
                store.write_session_info(db,
                  build_log =
                    Build_Log.Log_File(name, process_result.out_lines).
                      parse_session_info(name,
                        command_timings = true, ml_statistics = true, task_statistics = true),
                  build =
                    Session_Info(sources_stamp(name), input_heaps, heap_stamp, process_result.rc)))
            }

            loop(pending - name, running - name,
              results + (name -> Result(false, heap_stamp, Some(process_result_tail), job.info)))
            //}}}
          case None if running.size < (max_jobs max 1) =>
            //{{{ check/start next job
            pending.dequeue(running.isDefinedAt(_)) match {
              case Some((name, info)) =>
                val ancestor_results = selected_tree.ancestors(name).map(results(_))
                val ancestor_heaps = ancestor_results.flatMap(_.heap_stamp)

                val do_output = build_heap || Sessions.pure_name(name) || queue.is_inner(name)

                val (current, heap_stamp) =
                {
                  store.find_database_heap(name) match {
                    case Some((database, heap_stamp)) =>
                      using(SQLite.open_database(database))(store.read_build(_)) match {
                        case Some(build) =>
                          val current =
                            build.sources == sources_stamp(name) &&
                            build.input_heaps == ancestor_heaps &&
                            build.output_heap == heap_stamp &&
                            !(do_output && heap_stamp.isEmpty) &&
                            build.return_code == 0
                          (current, heap_stamp)
                        case None => (false, None)
                      }
                    case None => (false, None)
                  }
                }
                val all_current = current && ancestor_results.forall(_.current)

                if (all_current)
                  loop(pending - name, running,
                    results + (name -> Result(true, heap_stamp, Some(Process_Result(0)), info)))
                else if (no_build) {
                  if (verbose) progress.echo("Skipping " + name + " ...")
                  loop(pending - name, running,
                    results + (name -> Result(false, heap_stamp, Some(Process_Result(1)), info)))
                }
                else if (ancestor_results.forall(_.ok) && !progress.stopped) {
                  val numa_node = numa_nodes.next(used_node(_))
                  progress.echo((if (do_output) "Building " else "Running ") + name + " ...")
                  val job =
                    new Job(progress, name, info, selected_tree, store, do_output, verbose,
                      numa_node, deps(name).session_graph, queue.command_timings(name))
                  loop(pending, running + (name -> (ancestor_heaps, job)), results)
                }
                else {
                  progress.echo(name + " CANCELLED")
                  loop(pending - name, running,
                    results + (name -> Result(false, heap_stamp, None, info)))
                }
              case None => sleep(); loop(pending, running, results)
            }
            ///}}}
          case None => sleep(); loop(pending, running, results)
        }
      }
    }


    /* build results */

    val results0 =
      if (deps.is_empty) {
        progress.echo(Output.warning_text("Nothing to build"))
        Map.empty[String, Result]
      }
      else loop(queue, Map.empty, Map.empty)

    val results =
      new Results(
        (for ((name, result) <- results0.iterator)
          yield (name, (result.process, result.info))).toMap)

    if (results.rc != 0 && (verbose || !no_build)) {
      val unfinished =
        (for {
          name <- results.sessions.iterator
          if !results(name).ok
         } yield name).toList.sorted
      progress.echo("Unfinished session(s): " + commas(unfinished))
    }


    /* global browser info */

    if (!no_build) {
      val browser_chapters =
        (for {
          (name, result) <- results0.iterator
          if result.ok
          info = full_tree(name)
          if info.options.bool("browser_info")
        } yield (info.chapter, (name, info.description))).toList.groupBy(_._1).
            map({ case (chapter, es) => (chapter, es.map(_._2)) }).filterNot(_._2.isEmpty)

      for ((chapter, entries) <- browser_chapters)
        Present.update_chapter_index(store.browser_info, chapter, entries)

      if (browser_chapters.nonEmpty) Present.make_global_index(store.browser_info)
    }

    results
  }


  /* Isabelle tool wrapper */

  val isabelle_tool = Isabelle_Tool("build", "build and manage Isabelle sessions", args =>
  {
    val build_options = Word.explode(Isabelle_System.getenv("ISABELLE_BUILD_OPTIONS"))

    var select_dirs: List[Path] = Nil
    var numa_shuffling = false
    var requirements = false
    var exclude_session_groups: List[String] = Nil
    var all_sessions = false
    var build_heap = false
    var clean_build = false
    var dirs: List[Path] = Nil
    var session_groups: List[String] = Nil
    var max_jobs = 1
    var check_keywords: Set[String] = Set.empty
    var list_files = false
    var no_build = false
    var options = (Options.init() /: build_options)(_ + _)
    var system_mode = false
    var verbose = false
    var exclude_sessions: List[String] = Nil

    val getopts = Getopts("""
Usage: isabelle build [OPTIONS] [SESSIONS ...]

  Options are:
    -D DIR       include session directory and select its sessions
    -N           cyclic shuffling of NUMA CPU nodes (performance tuning)
    -R           operate on requirements of selected sessions
    -X NAME      exclude sessions from group NAME and all descendants
    -a           select all sessions
    -b           build heap images
    -c           clean build
    -d DIR       include session directory
    -g NAME      select session group NAME
    -j INT       maximum number of parallel jobs (default 1)
    -k KEYWORD   check theory sources for conflicts with proposed keywords
    -l           list session source files
    -n           no build -- test dependencies only
    -o OPTION    override Isabelle system OPTION (via NAME=VAL or NAME)
    -s           system build mode: produce output in ISABELLE_HOME
    -v           verbose
    -x NAME      exclude session NAME and all descendants

  Build and manage Isabelle sessions, depending on implicit settings:

""" + Library.prefix_lines("  ", Build_Log.Settings.show()) + "\n",
      "D:" -> (arg => select_dirs = select_dirs ::: List(Path.explode(arg))),
      "N" -> (_ => numa_shuffling = true),
      "R" -> (_ => requirements = true),
      "X:" -> (arg => exclude_session_groups = exclude_session_groups ::: List(arg)),
      "a" -> (_ => all_sessions = true),
      "b" -> (_ => build_heap = true),
      "c" -> (_ => clean_build = true),
      "d:" -> (arg => dirs = dirs ::: List(Path.explode(arg))),
      "g:" -> (arg => session_groups = session_groups ::: List(arg)),
      "j:" -> (arg => max_jobs = Value.Int.parse(arg)),
      "k:" -> (arg => check_keywords = check_keywords + arg),
      "l" -> (_ => list_files = true),
      "n" -> (_ => no_build = true),
      "o:" -> (arg => options = options + arg),
      "s" -> (_ => system_mode = true),
      "v" -> (_ => verbose = true),
      "x:" -> (arg => exclude_sessions = exclude_sessions ::: List(arg)))

    val sessions = getopts(args)

    val progress = new Console_Progress(verbose = verbose)

    val start_date = Date.now()

    if (verbose) {
      progress.echo(
        "Started at " + Build_Log.print_date(start_date) +
          " (" + Isabelle_System.getenv("ML_IDENTIFIER") + " on " + Isabelle_System.hostname() +")")
      progress.echo(Build_Log.Settings.show() + "\n")
    }

    val results =
      progress.interrupt_handler {
        build(options, progress,
          build_heap = build_heap,
          clean_build = clean_build,
          dirs = dirs,
          select_dirs = select_dirs,
          numa_shuffling = NUMA.enabled_warning(numa_shuffling),
          max_jobs = max_jobs,
          list_files = list_files,
          check_keywords = check_keywords,
          no_build = no_build,
          system_mode = system_mode,
          verbose = verbose,
          requirements = requirements,
          all_sessions = all_sessions,
          exclude_session_groups = exclude_session_groups,
          exclude_sessions = exclude_sessions,
          session_groups = session_groups,
          sessions = sessions)
      }
    val end_date = Date.now()
    val elapsed_time = end_date.time - start_date.time

    if (verbose) {
      progress.echo("\nFinished at " + Build_Log.print_date(end_date))
    }

    val total_timing =
      (Timing.zero /: results.sessions.iterator.map(a => results(a).timing))(_ + _).
        copy(elapsed = elapsed_time)
    progress.echo(total_timing.message_resources)

    sys.exit(results.rc)
  })


  /* PIDE protocol */

  def build_theories(
    session: Session, master_dir: Path, theories: List[(Options, List[Path])]): Promise[XML.Body] =
      session.get_protocol_handler(classOf[Handler].getName) match {
        case Some(handler: Handler) => handler.build_theories(session, master_dir, theories)
        case _ => error("Cannot invoke build_theories: bad protocol handler")
      }

  class Handler(progress: Progress, session_name: String) extends Session.Protocol_Handler
  {
    private val pending = Synchronized(Map.empty[String, Promise[XML.Body]])

    override def exit(): Unit =
      pending.change(promises => { for ((_, promise) <- promises) promise.cancel; Map.empty })

    def build_theories(
      session: Session, master_dir: Path, theories: List[(Options, List[Path])]): Promise[XML.Body] =
    {
      val promise = Future.promise[XML.Body]
      val id = Document_ID.make().toString
      pending.change(promises => promises + (id -> promise))
      session.build_theories(id, master_dir, theories)
      promise
    }

    private def loading_theory(msg: Prover.Protocol_Output): Boolean =
      msg.properties match {
        case Markup.Loading_Theory(name) => progress.theory(session_name, name); true
        case _ => false
      }

    private def build_theories_result(msg: Prover.Protocol_Output): Boolean =
      msg.properties match {
        case Markup.Build_Theories_Result(id) =>
          pending.change_result(promises =>
            promises.get(id) match {
              case Some(promise) =>
                val error_message =
                  try { YXML.parse_body(Symbol.decode(msg.text)) }
                  catch { case exn: Throwable => List(XML.Text(Exn.message(exn))) }
                promise.fulfill(error_message)
                (true, promises - id)
              case None =>
                (false, promises)
            })
        case _ => false
      }

    val functions =
      List(
        Markup.BUILD_THEORIES_RESULT -> build_theories_result _,
        Markup.LOADING_THEORY -> loading_theory _)
  }
}
