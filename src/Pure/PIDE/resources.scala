/*  Title:      Pure/PIDE/resources.scala
    Author:     Makarius

Resources for theories and auxiliary files.
*/

package isabelle


import scala.annotation.tailrec
import scala.util.parsing.input.Reader

import java.io.{File => JFile}


class Resources(val base: Sessions.Base, val log: Logger = No_Logger)
{
  val thy_info = new Thy_Info(this)

  def thy_path(path: Path): Path = path.ext("thy")


  /* document node names */

  def node_name(qualifier: String, raw_path: Path): Document.Node.Name =
  {
    val no_qualifier = "" // FIXME
    val path = raw_path.expand
    val node = path.implode
    val theory = Long_Name.qualify(no_qualifier, Thy_Header.thy_name(node).getOrElse(""))
    val master_dir = if (theory == "") "" else path.dir.implode
    Document.Node.Name(node, master_dir, theory)
  }


  /* file-system operations */

  def append(dir: String, source_path: Path): String =
    (Path.explode(dir) + source_path).expand.implode

  def append_file(dir: String, raw_name: String): String =
    if (Path.is_valid(raw_name)) append(dir, Path.explode(raw_name))
    else raw_name



  /* source files of Isabelle/ML bootstrap */

  def source_file(raw_name: String): Option[String] =
  {
    if (Path.is_wellformed(raw_name)) {
      if (Path.is_valid(raw_name)) {
        def check(p: Path): Option[Path] = if (p.is_file) Some(p) else None

        val path = Path.explode(raw_name)
        val path1 =
          if (path.is_absolute || path.is_current) check(path)
          else {
            check(Path.explode("~~/src/Pure") + path) orElse
              (if (Isabelle_System.getenv("ML_SOURCES") == "") None
               else check(Path.explode("$ML_SOURCES") + path))
          }
        Some(File.platform_path(path1 getOrElse path))
      }
      else None
    }
    else Some(raw_name)
  }


  /* theory files */

  def loaded_files(syntax: Outer_Syntax, text: String): List[String] =
    if (syntax.load_commands_in(text)) {
      val spans = syntax.parse_spans(text)
      spans.iterator.map(Command.span_files(syntax, _)._1).flatten.toList
    }
    else Nil

  private def dummy_name(theory: String): Document.Node.Name =
    Document.Node.Name(theory + ".thy", "", theory)

  def import_name(qualifier: String, master: Document.Node.Name, s: String): Document.Node.Name =
  {
    val no_qualifier = "" // FIXME
    val thy1 = Thy_Header.base_name(s)
    val thy2 = if (Long_Name.is_qualified(thy1)) thy1 else Long_Name.qualify(no_qualifier, thy1)
    (base.known_theories.get(thy1) orElse
     base.known_theories.get(thy2) orElse
     base.known_theories.get(Long_Name.base_name(thy1))) match {
      case Some(name) if base.loaded_theories(name.theory) => dummy_name(name.theory)
      case Some(name) => name
      case None =>
        val path = Path.explode(s)
        val theory = path.base.implode
        if (Long_Name.is_qualified(theory)) dummy_name(theory)
        else {
          val node = append(master.master_dir, thy_path(path))
          val master_dir = append(master.master_dir, path.dir)
          Document.Node.Name(node, master_dir, Long_Name.qualify(no_qualifier, theory))
        }
    }
  }

  def with_thy_reader[A](name: Document.Node.Name, f: Reader[Char] => A): A =
  {
    val path = Path.explode(name.node)
    if (!path.is_file) error("No such file: " + path.toString)

    val reader = Scan.byte_reader(path.file)
    try { f(reader) } finally { reader.close }
  }

  def check_thy_reader(qualifier: String, node_name: Document.Node.Name,
      reader: Reader[Char], start: Token.Pos = Token.Pos.command, strict: Boolean = true)
    : Document.Node.Header =
  {
    if (node_name.is_theory && reader.source.length > 0) {
      try {
        val header = Thy_Header.read(reader, start, strict).decode_symbols

        val base_name = Long_Name.base_name(node_name.theory)
        val (name, pos) = header.name
        if (base_name != name)
          error("Bad theory name " + quote(name) +
            " for file " + thy_path(Path.basic(base_name)) + Position.here(pos) +
            Completion.report_names(pos, 1, List((base_name, ("theory", base_name)))))

        val imports =
          header.imports.map({ case (s, pos) => (import_name(qualifier, node_name, s), pos) })
        Document.Node.Header(imports, header.keywords, header.abbrevs)
      }
      catch { case exn: Throwable => Document.Node.bad_header(Exn.message(exn)) }
    }
    else Document.Node.no_header
  }

  def check_thy(qualifier: String, name: Document.Node.Name,
      start: Token.Pos = Token.Pos.command, strict: Boolean = true): Document.Node.Header =
    with_thy_reader(name, check_thy_reader(qualifier, name, _, start, strict))


  /* special header */

  def special_header(name: Document.Node.Name): Option[Document.Node.Header] =
    if (Thy_Header.is_ml_root(name.theory))
      Some(Document.Node.Header(List((import_name("", name, Thy_Header.ML_BOOTSTRAP), Position.none))))
    else if (Thy_Header.is_bootstrap(name.theory))
      Some(Document.Node.Header(List((import_name("", name, Thy_Header.PURE), Position.none))))
    else None


  /* blobs */

  def undefined_blobs(nodes: Document.Nodes): List[Document.Node.Name] =
    (for {
      (node_name, node) <- nodes.iterator
      if !base.loaded_theories(node_name.theory)
      cmd <- node.load_commands.iterator
      name <- cmd.blobs_undefined.iterator
    } yield name).toList


  /* document changes */

  def parse_change(
      reparse_limit: Int,
      previous: Document.Version,
      doc_blobs: Document.Blobs,
      edits: List[Document.Edit_Text]): Session.Change =
    Thy_Syntax.parse_change(this, reparse_limit, previous, doc_blobs, edits)

  def commit(change: Session.Change) { }
}
