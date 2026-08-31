import gleam/int
import gleam/io
import gleam/option.{None}
import gleam/string
import gleeunit
import gleeunit/should
import spaceship_toml
import spaceship_toml/internal/types.{
  TomlBoolean, TomlFloat, TomlInteger, TomlString,
}

pub fn main() {
  gleeunit.main()
}

// ── Parse Tests ───────────────────────────────────────────────

pub fn parse_simple_kv_test() {
  let input = "name = \"hello\"\nversion = 42\n"
  let result = spaceship_toml.parse(input)
  result |> should.be_ok

  let doc = result |> should.be_ok
  let result = spaceship_toml.get(doc, ["name"])
  result |> should.be_ok

  let get_result = result |> should.be_ok
  get_result.line_number |> should.equal(1)
}

pub fn parse_integer_test() {
  let input = "count = 100\n"
  let result = spaceship_toml.parse(input)
  result |> should.be_ok

  let doc = result |> should.be_ok
  let result = spaceship_toml.get(doc, ["count"])
  result |> should.be_ok

  let get_result = result |> should.be_ok
  case get_result.value {
    TomlInteger(v) -> v |> should.equal(100)
    _ -> panic as "expected integer"
  }
}

pub fn parse_float_test() {
  let input = "pi = 3.14\n"
  let result = spaceship_toml.parse(input)
  result |> should.be_ok

  let doc = result |> should.be_ok
  let result = spaceship_toml.get(doc, ["pi"])
  result |> should.be_ok

  let get_result = result |> should.be_ok
  case get_result.value {
    TomlFloat(v) -> v |> should.equal(3.14)
    _ -> panic as "expected float"
  }
}

pub fn parse_boolean_test() {
  let input = "debug = true\nproduction = false\n"
  let result = spaceship_toml.parse(input)
  result |> should.be_ok

  let doc = result |> should.be_ok
  let result = spaceship_toml.get(doc, ["debug"])
  result |> should.be_ok

  let get_result = result |> should.be_ok
  case get_result.value {
    TomlBoolean(v) -> v |> should.equal(True)
    _ -> panic as "expected boolean"
  }
}

pub fn parse_string_test() {
  let input = "greeting = \"hello world\"\n"
  let result = spaceship_toml.parse(input)
  result |> should.be_ok

  let doc = result |> should.be_ok
  let result = spaceship_toml.get(doc, ["greeting"])
  result |> should.be_ok

  let get_result = result |> should.be_ok
  case get_result.value {
    TomlString(v) -> v |> should.equal("hello world")
    _ -> panic as "expected string"
  }
}

pub fn parse_table_test() {
  let input = "[server]\nhost = \"localhost\"\nport = 8080\n"
  let result = spaceship_toml.parse(input)
  result |> should.be_ok

  let doc = result |> should.be_ok
  let result = spaceship_toml.get(doc, ["server", "host"])
  result |> should.be_ok

  let get_result = result |> should.be_ok
  case get_result.value {
    TomlString(v) -> v |> should.equal("localhost")
    _ -> panic as "expected string"
  }
}

// ── Comment Preservation Tests ────────────────────────────────

pub fn preserve_comments_test() {
  let input = "# This is a comment\nname = \"hello\"\n"
  let result = spaceship_toml.parse(input)
  result |> should.be_ok

  let doc = result |> should.be_ok
  let output = spaceship_toml.to_string(doc)
  output |> should.equal("# This is a comment\nname = \"hello\"\n")
}

// ── Edit Tests ────────────────────────────────────────────────

pub fn set_value_test() {
  let input = "name = \"hello\"\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok

  let result =
    spaceship_toml.set(doc, ["name"], spaceship_toml.string("world"), None)
  result |> should.be_ok

  let new_doc = result |> should.be_ok
  let result = spaceship_toml.get(new_doc, ["name"])
  result |> should.be_ok

  let get_result = result |> should.be_ok
  case get_result.value {
    TomlString(v) -> v |> should.equal("world")
    _ -> panic as "expected string"
  }
}

pub fn delete_value_test() {
  let input = "name = \"hello\"\nversion = 1\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok

  let result = spaceship_toml.delete(doc, ["name"])
  result |> should.be_ok

  let new_doc = result |> should.be_ok
  let result = spaceship_toml.get(new_doc, ["name"])
  result |> should.be_error
}

pub fn rename_key_test() {
  let input = "old_name = \"hello\"\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok

  let result = spaceship_toml.rename_key(doc, ["old_name"], ["new_name"])
  result |> should.be_ok

  let new_doc = result |> should.be_ok
  let result = spaceship_toml.get(new_doc, ["new_name"])
  result |> should.be_ok

  let get_result = result |> should.be_ok
  case get_result.value {
    TomlString(v) -> v |> should.equal("hello")
    _ -> panic as "expected string"
  }
}

// ── Serialization Tests ───────────────────────────────────────

pub fn serialize_roundtrip_test() {
  let input = "name = \"hello\"\nversion = 42\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok
  let output = spaceship_toml.to_string(doc)
  output |> should.equal(input)
}

pub fn serialize_with_table_test() {
  let input = "[server]\nhost = \"localhost\"\nport = 8080\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok
  let output = spaceship_toml.to_string(doc)
  output |> should.equal(input)
}

// ── Line Number Tests ─────────────────────────────────────────

pub fn get_line_number_test() {
  let input = "a = 1\nb = 2\nc = 3\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok

  let result = spaceship_toml.get(doc, ["a"])
  result |> should.be_ok
  let get_result = result |> should.be_ok
  get_result.line_number |> should.equal(1)

  let result = spaceship_toml.get(doc, ["b"])
  result |> should.be_ok
  let get_result = result |> should.be_ok
  get_result.line_number |> should.equal(2)

  let result = spaceship_toml.get(doc, ["c"])
  result |> should.be_ok
  let get_result = result |> should.be_ok
  get_result.line_number |> should.equal(3)
}

// ── Integration Test ──────────────────────────────────────────

pub fn full_workflow_test() {
  let input =
    "# Config file\ndebug = true\n\n[server]\nhost = \"localhost\"\nport = 8080\n"

  // Parse
  let doc = spaceship_toml.parse(input) |> should.be_ok

  // Get
  let result = spaceship_toml.get(doc, ["debug"])
  result |> should.be_ok
  let get_result = result |> should.be_ok
  get_result.line_number |> should.equal(2)

  // Edit
  let doc =
    spaceship_toml.set(
      doc,
      ["server", "port"],
      spaceship_toml.integer(9090),
      None,
    )
    |> should.be_ok

  // Verify edit
  let result = spaceship_toml.get(doc, ["server", "port"])
  result |> should.be_ok
  let get_result = result |> should.be_ok
  case get_result.value {
    TomlInteger(v) -> v |> should.equal(9090)
    _ -> panic as "expected integer"
  }

  // Serialize (preserves comments)
  let output = spaceship_toml.to_string(doc)
  // Verify comments preserved and value updated
  case string.contains(output, "# Config file") {
    True -> Nil
    False -> panic as "expected comment to be preserved"
  }
  case string.contains(output, "port = 9090") {
    True -> Nil
    False -> panic as "expected port to be updated"
  }
}

pub fn debug_line_numbers_test() {
  let input =
    "# Config file\ndebug = true\n\n[server]\nhost = \"localhost\"\nport = 8080\n"
  case spaceship_toml.parse(input) {
    Ok(doc) -> {
      // Print all lines with their line numbers
      let _ = do_print_lines(doc.lines)

      let result = spaceship_toml.get(doc, ["debug"])
      case result {
        Ok(gr) -> io.println("debug line: " <> int.to_string(gr.line_number))
        Error(_) -> io.println("Error getting debug")
      }

      let result = spaceship_toml.get(doc, ["server", "host"])
      case result {
        Ok(gr) ->
          io.println("server.host line: " <> int.to_string(gr.line_number))
        Error(_) -> io.println("Error getting server.host")
      }

      let result = spaceship_toml.get(doc, ["server", "port"])
      case result {
        Ok(gr) ->
          io.println("server.port line: " <> int.to_string(gr.line_number))
        Error(_) -> io.println("Error getting server.port")
      }
    }
    Error(_) -> io.println("Parse error")
  }
}

fn do_print_lines(lines) {
  case lines {
    [] -> Nil
    [line, ..rest] -> {
      io.println("---")
      io.println(string.inspect(line))
      do_print_lines(rest)
    }
  }
}

// ── Typed Getter Tests ───────────────────────────────────────

pub fn get_string_test() {
  let input = "name = \"hello\"\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok

  let result = spaceship_toml.get_string(doc, ["name"])
  result |> should.be_ok

  let #(value, line) = result |> should.be_ok
  value |> should.equal("hello")
  line |> should.equal(1)
}

pub fn get_int_test() {
  let input = "count = 42\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok

  let result = spaceship_toml.get_int(doc, ["count"])
  result |> should.be_ok

  let #(value, line) = result |> should.be_ok
  value |> should.equal(42)
  line |> should.equal(1)
}

pub fn get_float_test() {
  let input = "pi = 3.14\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok

  let result = spaceship_toml.get_float(doc, ["pi"])
  result |> should.be_ok

  let #(value, _line) = result |> should.be_ok
  value |> should.equal(3.14)
}

pub fn get_bool_test() {
  let input = "debug = true\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok

  let result = spaceship_toml.get_bool(doc, ["debug"])
  result |> should.be_ok

  let #(value, line) = result |> should.be_ok
  value |> should.equal(True)
  line |> should.equal(1)
}

pub fn get_string_wrong_type_test() {
  let input = "count = 42\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok

  // Try to get a string from an integer value
  let result = spaceship_toml.get_string(doc, ["count"])
  result |> should.be_error
}

pub fn get_int_not_found_test() {
  let input = "name = \"hello\"\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok

  // Try to get a non-existent key
  let result = spaceship_toml.get_int(doc, ["missing"])
  result |> should.be_error
}

pub fn get_string_in_table_test() {
  let input = "[server]\nhost = \"localhost\"\nport = 8080\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok

  let result = spaceship_toml.get_string(doc, ["server", "host"])
  result |> should.be_ok

  let #(value, line) = result |> should.be_ok
  value |> should.equal("localhost")
  line |> should.equal(2)
}

pub fn get_int_in_table_test() {
  let input = "[server]\nhost = \"localhost\"\nport = 8080\n"
  let doc = spaceship_toml.parse(input) |> should.be_ok

  let result = spaceship_toml.get_int(doc, ["server", "port"])
  result |> should.be_ok

  let #(value, line) = result |> should.be_ok
  value |> should.equal(8080)
  line |> should.equal(3)
}
