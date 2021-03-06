/*  Title:      Pure/PIDE/batch_session.scala
    Author:     Makarius

PIDE session in batch mode.
*/

package isabelle


import isabelle._


object Batch_Session
{
  def batch_session(
    options: Options,
    verbose: Boolean = false,
    dirs: List[Path] = Nil,
    session: String): Batch_Session =
  {
    val (_, session_tree) = Sessions.load(options, dirs).selection(sessions = List(session))
    val session_info = session_tree(session)
    val parent_session =
      session_info.parent getOrElse error("No parent session for " + quote(session))

    if (!Build.build(options, new Console_Progress(verbose = verbose),
        verbose = verbose, build_heap = true,
        dirs = dirs, sessions = List(parent_session)).ok)
      new RuntimeException

    val deps = Sessions.dependencies(verbose = verbose, tree = session_tree)
    val resources = new Resources(deps(parent_session))

    val progress = new Console_Progress(verbose = verbose)

    val prover_session = new Session(options, resources)
    val batch_session = new Batch_Session(prover_session)

    val handler = new Build.Handler(progress, session)

    Isabelle_Process.start(prover_session, options, logic = parent_session,
      phase_changed =
      {
        case Session.Ready =>
          prover_session.add_protocol_handler(handler)
          val master_dir = session_info.dir
          val theories = session_info.theories.map({ case (_, opts, thys) => (opts, thys) })
          batch_session.build_theories_result =
            Some(Build.build_theories(prover_session, master_dir, theories))
        case Session.Terminated(_) =>
          batch_session.session_result.fulfill_result(Exn.Exn(ERROR("Prover process terminated")))
        case Session.Shutdown =>
          batch_session.session_result.fulfill(())
        case _ =>
      })

    batch_session
  }
}

class Batch_Session private(val session: Session)
{
  val session_result = Future.promise[Unit]
  @volatile var build_theories_result: Option[Promise[XML.Body]] = None
}

