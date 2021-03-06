/*  Title:      Pure/System/isabelle_process.scala
    Author:     Makarius

Isabelle process wrapper.
*/

package isabelle


object Isabelle_Process
{
  def start(session: Session,
    options: Options,
    logic: String = "",
    args: List[String] = Nil,
    dirs: List[Path] = Nil,
    modes: List[String] = Nil,
    store: Sessions.Store = Sessions.store(),
    phase_changed: Session.Phase => Unit = null)
  {
    if (phase_changed != null)
      session.phase_changed += Session.Consumer("Isabelle_Process")(phase_changed)

    session.start(receiver =>
      Isabelle_Process(options, logic = logic, args = args, dirs = dirs, modes = modes,
        receiver = receiver, xml_cache = session.xml_cache, store = store))
  }

  def apply(
    options: Options,
    logic: String = "",
    args: List[String] = Nil,
    dirs: List[Path] = Nil,
    modes: List[String] = Nil,
    receiver: Prover.Receiver = Console.println(_),
    xml_cache: XML.Cache = new XML.Cache(),
    store: Sessions.Store = Sessions.store()): Isabelle_Process =
  {
    val channel = System_Channel()
    val process =
      try {
        ML_Process(options, logic = logic, args = args, dirs = dirs,
          modes = modes, store = store, channel = Some(channel))
      }
      catch { case exn @ ERROR(_) => channel.accepted(); throw exn }
    process.stdin.close

    new Isabelle_Process(receiver, xml_cache, channel, process)
  }
}

class Isabelle_Process private(
    receiver: Prover.Receiver,
    xml_cache: XML.Cache,
    channel: System_Channel,
    process: Prover.System_Process)
  extends Prover(receiver, xml_cache, channel, process)
{
  def encode(s: String): String = Symbol.encode(s)
  def decode(s: String): String = Symbol.decode(s)
}
