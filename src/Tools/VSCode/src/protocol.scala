/*  Title:      Tools/VSCode/src/protocol.scala
    Author:     Makarius

Message formats for Language Server Protocol 3.0, see
https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md
*/

package isabelle.vscode


import isabelle._

import java.io.{File => JFile}


object Protocol
{
  /* abstract message */

  object Message
  {
    val empty: Map[String, JSON.T] = Map("jsonrpc" -> "2.0")
  }


  /* notification */

  object Notification
  {
    def apply(method: String, params: JSON.T): JSON.T =
      Message.empty + ("method" -> method) + ("params" -> params)

    def unapply(json: JSON.T): Option[(String, Option[JSON.T])] =
      for {
        method <- JSON.string(json, "method")
        params = JSON.value(json, "params")
      } yield (method, params)
  }

  class Notification0(name: String)
  {
    def unapply(json: JSON.T): Option[Unit] =
      json match {
        case Notification(method, _) if method == name => Some(())
        case _ => None
      }
  }


  /* request message */

  sealed case class Id(id: Any)
  {
    require(
      id.isInstanceOf[Int] ||
      id.isInstanceOf[Long] ||
      id.isInstanceOf[Double] ||
      id.isInstanceOf[String])

    override def toString: String = id.toString
  }

  object RequestMessage
  {
    def apply(id: Id, method: String, params: JSON.T): JSON.T =
      Message.empty + ("id" -> id.id) + ("method" -> method) + ("params" -> params)

    def unapply(json: JSON.T): Option[(Id, String, Option[JSON.T])] =
      for {
        id <- JSON.long(json, "id") orElse JSON.double(json, "id") orElse JSON.string(json, "id")
        method <- JSON.string(json, "method")
        params = JSON.value(json, "params")
      } yield (Id(id), method, params)
  }

  class Request0(name: String)
  {
    def unapply(json: JSON.T): Option[Id] =
      json match {
        case RequestMessage(id, method, _) if method == name => Some(id)
        case _ => None
      }
  }

  class RequestTextDocumentPosition(name: String)
  {
    def unapply(json: JSON.T): Option[(Id, Line.Node_Position)] =
      json match {
        case RequestMessage(id, method, Some(TextDocumentPosition(node_pos))) if method == name =>
          Some((id, node_pos))
        case _ => None
      }
  }


  /* response message */

  object ResponseMessage
  {
    def apply(id: Id, result: Option[JSON.T] = None, error: Option[ResponseError] = None): JSON.T =
      Message.empty + ("id" -> id.id) ++
        JSON.optional("result" -> result) ++
        JSON.optional("error" -> error.map(_.json))

    def strict(id: Id, result: Option[JSON.T] = None, error: String = ""): JSON.T =
      if (error == "") apply(id, result = result)
      else apply(id, error = Some(ResponseError(code = ErrorCodes.serverErrorEnd, message = error)))
  }

  sealed case class ResponseError(code: Int, message: String, data: Option[JSON.T] = None)
  {
    def json: JSON.T =
      Map("code" -> code, "message" -> message) ++ JSON.optional("data" -> data)
  }

  object ErrorCodes
  {
    val ParseError = -32700
    val InvalidRequest = -32600
    val MethodNotFound = -32601
    val InvalidParams = -32602
    val InternalError = -32603
    val serverErrorStart = -32099
    val serverErrorEnd = -32000
  }


  /* init and exit */

  object Initialize extends Request0("initialize")
  {
    def reply(id: Id, error: String): JSON.T =
      ResponseMessage.strict(id, Some(Map("capabilities" -> ServerCapabilities.json)), error)
  }

  object ServerCapabilities
  {
    val json: JSON.T =
      Map(
        "textDocumentSync" -> 2,
        "completionProvider" -> Map("resolveProvider" -> false, "triggerCharacters" -> Nil),
        "hoverProvider" -> true,
        "definitionProvider" -> true,
        "documentHighlightProvider" -> true)
  }

  object Initialized extends Notification0("initialized")

  object Shutdown extends Request0("shutdown")
  {
    def reply(id: Id, error: String): JSON.T =
      ResponseMessage.strict(id, Some("OK"), error)
  }

  object Exit extends Notification0("exit")


  /* document positions */

  object Position
  {
    def apply(pos: Line.Position): JSON.T =
      Map("line" -> pos.line, "character" -> pos.column)

    def unapply(json: JSON.T): Option[Line.Position] =
      for {
        line <- JSON.int(json, "line")
        column <- JSON.int(json, "character")
      } yield Line.Position(line, column)
  }

  object Range
  {
    def compact(range: Line.Range): List[Int] =
      List(range.start.line, range.start.column, range.stop.line, range.stop.column)

    def apply(range: Line.Range): JSON.T =
      Map("start" -> Position(range.start), "end" -> Position(range.stop))

    def unapply(json: JSON.T): Option[Line.Range] =
      (JSON.value(json, "start"), JSON.value(json, "end")) match {
        case (Some(Position(start)), Some(Position(stop))) => Some(Line.Range(start, stop))
        case _ => None
      }
  }

  object Location
  {
    def apply(loc: Line.Node_Range): JSON.T =
      Map("uri" -> Url.print_file_name(loc.name), "range" -> Range(loc.range))

    def unapply(json: JSON.T): Option[Line.Node_Range] =
      for {
        uri <- JSON.string(json, "uri")
        range_json <- JSON.value(json, "range")
        range <- Range.unapply(range_json)
      } yield Line.Node_Range(Url.canonical_file_name(uri), range)
  }

  object TextDocumentPosition
  {
    def unapply(json: JSON.T): Option[Line.Node_Position] =
      for {
        doc <- JSON.value(json, "textDocument")
        uri <- JSON.string(doc, "uri")
        pos_json <- JSON.value(json, "position")
        pos <- Position.unapply(pos_json)
      } yield Line.Node_Position(Url.canonical_file_name(uri), pos)
  }


  /* marked strings */

  sealed case class MarkedString(text: String, language: String = "plaintext")
  {
    def json: JSON.T = Map("language" -> language, "value" -> text)
  }

  object MarkedStrings
  {
    def json(msgs: List[MarkedString]): Option[JSON.T] =
      msgs match {
        case Nil => None
        case List(msg) => Some(msg.json)
        case _ => Some(msgs.map(_.json))
      }
  }


  /* diagnostic messages */

  object MessageType
  {
    val Error = 1
    val Warning = 2
    val Info = 3
    val Log = 4
  }

  object DisplayMessage
  {
    def apply(message_type: Int, message: String, show: Boolean = true): JSON.T =
      Notification(if (show) "window/showMessage" else "window/logMessage",
        Map("type" -> message_type, "message" -> message))
  }


  /* document edits */

  object DidOpenTextDocument
  {
    def unapply(json: JSON.T): Option[(JFile, String, Long, String)] =
      json match {
        case Notification("textDocument/didOpen", Some(params)) =>
          for {
            doc <- JSON.value(params, "textDocument")
            uri <- JSON.string(doc, "uri")
            lang <- JSON.string(doc, "languageId")
            version <- JSON.long(doc, "version")
            text <- JSON.string(doc, "text")
          } yield (Url.canonical_file(uri), lang, version, text)
        case _ => None
      }
  }


  sealed case class TextDocumentChange(range: Option[Line.Range], text: String)

  object DidChangeTextDocument
  {
    def unapply_change(json: JSON.T): Option[TextDocumentChange] =
      for { text <- JSON.string(json, "text") }
      yield TextDocumentChange(JSON.value(json, "range", Range.unapply _), text)

    def unapply(json: JSON.T): Option[(JFile, Long, List[TextDocumentChange])] =
      json match {
        case Notification("textDocument/didChange", Some(params)) =>
          for {
            doc <- JSON.value(params, "textDocument")
            uri <- JSON.string(doc, "uri")
            version <- JSON.long(doc, "version")
            changes <- JSON.array(params, "contentChanges", unapply_change _)
          } yield (Url.canonical_file(uri), version, changes)
        case _ => None
      }
  }

  class TextDocumentNotification(name: String)
  {
    def unapply(json: JSON.T): Option[JFile] =
      json match {
        case Notification(method, Some(params)) if method == name =>
          for {
            doc <- JSON.value(params, "textDocument")
            uri <- JSON.string(doc, "uri")
          } yield Url.canonical_file(uri)
        case _ => None
      }
  }

  object DidCloseTextDocument extends TextDocumentNotification("textDocument/didClose")
  object DidSaveTextDocument extends TextDocumentNotification("textDocument/didSave")


  /* completion */

  sealed case class CompletionItem(
    label: String,
    kind: Option[Int] = None,
    detail: Option[String] = None,
    documentation: Option[String] = None,
    insertText: Option[String] = None,
    range: Option[Line.Range] = None)
  {
    def json: JSON.T =
      Message.empty + ("label" -> label) ++
        JSON.optional("kind" -> kind) ++
        JSON.optional("detail" -> detail) ++
        JSON.optional("documentation" -> documentation) ++
        JSON.optional("insertText" -> insertText) ++
        JSON.optional("range" -> range.map(Range(_)))
  }

  object Completion extends RequestTextDocumentPosition("textDocument/completion")
  {
    def reply(id: Id, result: List[CompletionItem]): JSON.T =
      ResponseMessage(id, Some(result.map(_.json)))
  }


  /* hover request */

  object Hover extends RequestTextDocumentPosition("textDocument/hover")
  {
    def reply(id: Id, result: Option[(Line.Range, List[MarkedString])]): JSON.T =
    {
      val res =
        result match {
          case Some((range, contents)) =>
            Map("contents" -> MarkedStrings.json(contents).getOrElse(Nil), "range" -> Range(range))
          case None => Map("contents" -> Nil)
        }
      ResponseMessage(id, Some(res))
    }
  }


  /* goto definition request */

  object GotoDefinition extends RequestTextDocumentPosition("textDocument/definition")
  {
    def reply(id: Id, result: List[Line.Node_Range]): JSON.T =
      ResponseMessage(id, Some(result.map(Location.apply(_))))
  }


  /* document highlights request */

  object DocumentHighlight
  {
    def text(range: Line.Range): DocumentHighlight = DocumentHighlight(range, Some(1))
    def read(range: Line.Range): DocumentHighlight = DocumentHighlight(range, Some(2))
    def write(range: Line.Range): DocumentHighlight = DocumentHighlight(range, Some(3))
  }

  sealed case class DocumentHighlight(range: Line.Range, kind: Option[Int] = None)
  {
    def json: JSON.T =
      kind match {
        case None => Map("range" -> Range(range))
        case Some(k) => Map("range" -> Range(range), "kind" -> k)
      }
  }

  object DocumentHighlights extends RequestTextDocumentPosition("textDocument/documentHighlight")
  {
    def reply(id: Id, result: List[DocumentHighlight]): JSON.T =
      ResponseMessage(id, Some(result.map(_.json)))
  }


  /* diagnostics */

  sealed case class Diagnostic(range: Line.Range, message: String,
    severity: Option[Int] = None, code: Option[Int] = None, source: Option[String] = None)
  {
    def json: JSON.T =
      Message.empty + ("range" -> Range(range)) + ("message" -> message) ++
      JSON.optional("severity" -> severity) ++
      JSON.optional("code" -> code) ++
      JSON.optional("source" -> source)
  }

  object DiagnosticSeverity
  {
    val Error = 1
    val Warning = 2
    val Information = 3
    val Hint = 4
  }

  object PublishDiagnostics
  {
    def apply(file: JFile, diagnostics: List[Diagnostic]): JSON.T =
      Notification("textDocument/publishDiagnostics",
        Map("uri" -> Url.print_file(file), "diagnostics" -> diagnostics.map(_.json)))
  }


  /* decorations */

  sealed case class DecorationOpts(range: Line.Range, hover_message: List[MarkedString])
  {
    def json: JSON.T =
      Map("range" -> Range.compact(range)) ++
      JSON.optional("hover_message" -> MarkedStrings.json(hover_message))
  }

  sealed case class Decoration(typ: String, content: List[DecorationOpts])
  {
    def json(file: JFile): JSON.T =
      Notification("PIDE/decoration",
        Map("uri" -> Url.print_file(file), "type" -> typ, "content" -> content.map(_.json)))
  }


  /* caret handling */

  object Caret_Update
  {
    def unapply(json: JSON.T): Option[Option[(JFile, Line.Position)]] =
      json match {
        case Notification("PIDE/caret_update", Some(params)) =>
          val caret =
            for {
              uri <- JSON.string(params, "uri")
              if Url.is_wellformed_file(uri)
              pos <- Position.unapply(params)
            } yield (Url.canonical_file(uri), pos)
          Some(caret)
        case _ => None
      }
  }


  /* dynamic output */

  object Dynamic_Output
  {
    def apply(body: String): JSON.T =
      Notification("PIDE/dynamic_output", Map("body" -> body))
  }
}
