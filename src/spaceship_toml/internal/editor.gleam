import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import spaceship_toml/internal/types.{
  type Document, type EditError, type GetResult, type Line, type TomlValue,
  ArrayOfTablesHeader, Blank, Comment, Document as DocumentConstructor, Entry,
  GetResult as GetResultConstructor, KeyNotFound, TableHeader, TableNotFound,
  TomlArray, TomlBoolean, TomlDate, TomlDateTime, TomlFloat, TomlInteger,
  TomlString, TomlTime,
}

// ── Public API ────────────────────────────────────────────────

/// Get a value by key, returning the key, value, and line number.
pub fn get(doc: Document, key: List(String)) -> Result(GetResult, EditError) {
  let lines = list.reverse(doc.lines)
  do_get(lines, key)
}

fn do_get(
  lines: List(Line),
  key: List(String),
) -> Result(GetResult, EditError) {
  case lines {
    [] -> Error(KeyNotFound(key: string.join(key, ".")))

    [Entry(line_number, entry_key, value), ..rest] -> {
      case entry_key == key {
        True ->
          Ok(GetResultConstructor(
            key: string.join(key, "."),
            value: value,
            line_number: line_number,
          ))
        False -> do_get(rest, key)
      }
    }

    [_, ..rest] -> do_get(rest, key)
  }
}

/// Set a value at the given key. If line_number is provided, insert at that position.
/// If line_number is None, update existing entry or append to the current table.
pub fn set(
  doc: Document,
  key: List(String),
  value: TomlValue,
  line_number: Option(Int),
) -> Result(Document, EditError) {
  let lines = list.reverse(doc.lines)

  case line_number {
    Some(ln) -> {
      // Insert at specific line
      let lines = insert_at_line(lines, key, value, ln)
      Ok(DocumentConstructor(lines: list.reverse(lines)))
    }

    None -> {
      // Update existing or append
      let lines = update_or_append(lines, key, value)
      Ok(DocumentConstructor(lines: list.reverse(lines)))
    }
  }
}

/// Delete a key from the document.
pub fn delete(doc: Document, key: List(String)) -> Result(Document, EditError) {
  let lines = list.reverse(doc.lines)
  let lines = do_delete(lines, key, [])
  Ok(DocumentConstructor(lines: list.reverse(lines)))
}

fn do_delete(
  lines: List(Line),
  key: List(String),
  acc: List(Line),
) -> List(Line) {
  case lines {
    [] -> list.reverse(acc)

    [Entry(_, entry_key, _), ..rest] if entry_key == key -> {
      do_delete(rest, key, acc)
    }

    [line, ..rest] -> do_delete(rest, key, [line, ..acc])
  }
}

/// Rename a key throughout the document.
pub fn rename_key(
  doc: Document,
  old_key: List(String),
  new_key: List(String),
) -> Result(Document, EditError) {
  let lines = list.reverse(doc.lines)
  let lines = do_rename_key(lines, old_key, new_key, [])
  Ok(DocumentConstructor(lines: list.reverse(lines)))
}

fn do_rename_key(
  lines: List(Line),
  old_key: List(String),
  new_key: List(String),
  acc: List(Line),
) -> List(Line) {
  case lines {
    [] -> list.reverse(acc)

    [Entry(line_number, entry_key, value), ..rest] if entry_key == old_key -> {
      let line = Entry(line_number: line_number, key: new_key, value: value)
      do_rename_key(rest, old_key, new_key, [line, ..acc])
    }

    [TableHeader(line_number, path), ..rest] if path == old_key -> {
      let line = TableHeader(line_number: line_number, path: new_key)
      do_rename_key(rest, old_key, new_key, [line, ..acc])
    }

    [ArrayOfTablesHeader(line_number, path), ..rest] if path == old_key -> {
      let line = ArrayOfTablesHeader(line_number: line_number, path: new_key)
      do_rename_key(rest, old_key, new_key, [line, ..acc])
    }

    [line, ..rest] -> do_rename_key(rest, old_key, new_key, [line, ..acc])
  }
}

/// Add a table header at the given line number (or append if None).
pub fn add_table(
  doc: Document,
  path: List(String),
  line_number: Option(Int),
) -> Result(Document, EditError) {
  let lines = list.reverse(doc.lines)

  case line_number {
    Some(ln) -> {
      let line = TableHeader(line_number: ln, path: path)
      let lines = insert_line_at(lines, ln, line)
      Ok(DocumentConstructor(lines: list.reverse(lines)))
    }

    None -> {
      let max_line = find_max_line_number(lines, 0)
      let line = TableHeader(line_number: max_line + 1, path: path)
      Ok(DocumentConstructor(lines: list.reverse([line, ..lines])))
    }
  }
}

/// Add an array of tables header at the given line number (or append if None).
pub fn add_array_of_tables(
  doc: Document,
  path: List(String),
  line_number: Option(Int),
) -> Result(Document, EditError) {
  let lines = list.reverse(doc.lines)

  case line_number {
    Some(ln) -> {
      let line = ArrayOfTablesHeader(line_number: ln, path: path)
      let lines = insert_line_at(lines, ln, line)
      Ok(DocumentConstructor(lines: list.reverse(lines)))
    }

    None -> {
      let max_line = find_max_line_number(lines, 0)
      let line = ArrayOfTablesHeader(line_number: max_line + 1, path: path)
      Ok(DocumentConstructor(lines: list.reverse([line, ..lines])))
    }
  }
}

/// Get all entries in a table.
pub fn get_table(
  doc: Document,
  path: List(String),
) -> Result(List(#(String, TomlValue)), EditError) {
  let lines = list.reverse(doc.lines)
  do_get_table(lines, path, [])
}

fn do_get_table(
  lines: List(Line),
  table_path: List(String),
  acc: List(#(String, TomlValue)),
) -> Result(List(#(String, TomlValue)), EditError) {
  case lines {
    [] -> {
      case acc {
        [] -> Error(TableNotFound(path: string.join(table_path, ".")))
        _ -> Ok(list.reverse(acc))
      }
    }

    [TableHeader(_, path), ..rest] if path == table_path -> {
      do_get_table_entries(rest, table_path, acc)
    }

    [ArrayOfTablesHeader(_, path), ..rest] if path == table_path -> {
      do_get_table_entries(rest, table_path, acc)
    }

    [Entry(_, entry_key, value), ..rest] -> {
      let key_len = list.length(entry_key)
      let path_len = list.length(table_path)
      case key_len > path_len {
        True -> {
          let prefix = list.take(entry_key, path_len)
          case prefix == table_path {
            True -> {
              let entry_key_str = string.join(entry_key, ".")
              do_get_table_entries(rest, table_path, [
                #(entry_key_str, value),
                ..acc
              ])
            }
            False -> do_get_table(rest, table_path, acc)
          }
        }
        False -> do_get_table(rest, table_path, acc)
      }
    }

    [_, ..rest] -> do_get_table(rest, table_path, acc)
  }
}

fn do_get_table_entries(
  lines: List(Line),
  table_path: List(String),
  acc: List(#(String, TomlValue)),
) -> Result(List(#(String, TomlValue)), EditError) {
  case lines {
    [] -> Ok(list.reverse(acc))

    // Stop at next table header
    [TableHeader(_, _), ..] -> Ok(list.reverse(acc))
    [ArrayOfTablesHeader(_, _), ..] -> Ok(list.reverse(acc))

    [Entry(_, key, value), ..rest] -> {
      let key_len = list.length(key)
      let path_len = list.length(table_path)
      case key_len >= path_len {
        True -> {
          let prefix = list.take(key, path_len)
          case prefix == table_path {
            True -> {
              let entry_key_str = string.join(key, ".")
              do_get_table_entries(rest, table_path, [
                #(entry_key_str, value),
                ..acc
              ])
            }
            False -> Ok(list.reverse(acc))
          }
        }
        False -> do_get_table_entries(rest, table_path, acc)
      }
    }

    [_, ..rest] -> do_get_table_entries(rest, table_path, acc)
  }
}

/// Get a value at a specific line number.
pub fn get_at_line(
  doc: Document,
  line_number: Int,
) -> Result(GetResult, EditError) {
  let lines = list.reverse(doc.lines)
  do_get_at_line(lines, line_number)
}

// ── Typed Getters ────────────────────────────────────────────

/// Get a string value by key.
pub fn get_string(
  doc: Document,
  key: List(String),
) -> Result(#(String, Int), EditError) {
  case get(doc, key) {
    Error(e) -> Error(e)
    Ok(result) -> {
      case result.value {
        TomlString(v) -> Ok(#(v, result.line_number))
        _ -> Error(KeyNotFound(key: string.join(key, ".")))
      }
    }
  }
}

/// Get an integer value by key.
pub fn get_int(
  doc: Document,
  key: List(String),
) -> Result(#(Int, Int), EditError) {
  case get(doc, key) {
    Error(e) -> Error(e)
    Ok(result) -> {
      case result.value {
        TomlInteger(v) -> Ok(#(v, result.line_number))
        _ -> Error(KeyNotFound(key: string.join(key, ".")))
      }
    }
  }
}

/// Get a float value by key.
pub fn get_float(
  doc: Document,
  key: List(String),
) -> Result(#(Float, Int), EditError) {
  case get(doc, key) {
    Error(e) -> Error(e)
    Ok(result) -> {
      case result.value {
        TomlFloat(v) -> Ok(#(v, result.line_number))
        _ -> Error(KeyNotFound(key: string.join(key, ".")))
      }
    }
  }
}

/// Get a boolean value by key.
pub fn get_bool(
  doc: Document,
  key: List(String),
) -> Result(#(Bool, Int), EditError) {
  case get(doc, key) {
    Error(e) -> Error(e)
    Ok(result) -> {
      case result.value {
        TomlBoolean(v) -> Ok(#(v, result.line_number))
        _ -> Error(KeyNotFound(key: string.join(key, ".")))
      }
    }
  }
}

/// Get an array value by key.
pub fn get_array(
  doc: Document,
  key: List(String),
) -> Result(#(List(TomlValue), Int), EditError) {
  case get(doc, key) {
    Error(e) -> Error(e)
    Ok(result) -> {
      case result.value {
        TomlArray(v) -> Ok(#(v, result.line_number))
        _ -> Error(KeyNotFound(key: string.join(key, ".")))
      }
    }
  }
}

/// Get a date value by key.
pub fn get_date(
  doc: Document,
  key: List(String),
) -> Result(#(types.TomlDate, Int), EditError) {
  case get(doc, key) {
    Error(e) -> Error(e)
    Ok(result) -> {
      case result.value {
        TomlDate(v) -> Ok(#(v, result.line_number))
        _ -> Error(KeyNotFound(key: string.join(key, ".")))
      }
    }
  }
}

/// Get a time value by key.
pub fn get_time(
  doc: Document,
  key: List(String),
) -> Result(#(types.TomlTime, Int), EditError) {
  case get(doc, key) {
    Error(e) -> Error(e)
    Ok(result) -> {
      case result.value {
        TomlTime(v) -> Ok(#(v, result.line_number))
        _ -> Error(KeyNotFound(key: string.join(key, ".")))
      }
    }
  }
}

/// Get a datetime value by key.
pub fn get_datetime(
  doc: Document,
  key: List(String),
) -> Result(#(types.TomlDateTime, Int), EditError) {
  case get(doc, key) {
    Error(e) -> Error(e)
    Ok(result) -> {
      case result.value {
        TomlDateTime(v) -> Ok(#(v, result.line_number))
        _ -> Error(KeyNotFound(key: string.join(key, ".")))
      }
    }
  }
}

fn do_get_at_line(
  lines: List(Line),
  line_number: Int,
) -> Result(GetResult, EditError) {
  case lines {
    [] -> Error(KeyNotFound(key: int_to_string(line_number)))

    [Entry(ln, key, value), ..] if ln == line_number -> {
      Ok(GetResultConstructor(
        key: string.join(key, "."),
        value: value,
        line_number: ln,
      ))
    }

    [_, ..rest] -> do_get_at_line(rest, line_number)
  }
}

// ── Internal Helpers ──────────────────────────────────────────

fn insert_at_line(
  lines: List(Line),
  key: List(String),
  value: TomlValue,
  line_number: Int,
) -> List(Line) {
  case lines {
    [] -> [Entry(line_number: line_number, key: key, value: value)]

    [line, ..rest] -> {
      let ln = get_line_number(line)
      case ln >= line_number {
        True -> {
          // Insert before this line
          [
            Entry(line_number: line_number, key: key, value: value),
            line,
            ..rest
          ]
        }

        False -> [line, ..insert_at_line(rest, key, value, line_number)]
      }
    }
  }
}

fn insert_line_at(
  lines: List(Line),
  line_number: Int,
  new_line: Line,
) -> List(Line) {
  case lines {
    [] -> [new_line]

    [line, ..rest] -> {
      let ln = get_line_number(line)
      case ln >= line_number {
        True -> {
          [new_line, line, ..rest]
        }

        False -> [line, ..insert_line_at(rest, line_number, new_line)]
      }
    }
  }
}

fn update_or_append(
  lines: List(Line),
  key: List(String),
  value: TomlValue,
) -> List(Line) {
  case lines {
    [] -> [Entry(line_number: 0, key: key, value: value)]

    [Entry(_, entry_key, _), ..rest] if entry_key == key -> {
      // Update existing entry (keep original line number)
      let line_number = get_line_number(hd_or_default(lines))
      [Entry(line_number: line_number, key: key, value: value), ..rest]
    }

    [line, ..rest] -> [line, ..update_or_append(rest, key, value)]
  }
}

fn find_max_line_number(lines: List(Line), max: Int) -> Int {
  case lines {
    [] -> max
    [line, ..rest] -> {
      let ln = get_line_number(line)
      let max = case ln > max {
        True -> ln
        False -> max
      }
      find_max_line_number(rest, max)
    }
  }
}

fn get_line_number(line: Line) -> Int {
  case line {
    Comment(line_number, _) -> line_number
    Blank(line_number) -> line_number
    TableHeader(line_number, _) -> line_number
    ArrayOfTablesHeader(line_number, _) -> line_number
    Entry(line_number, _, _) -> line_number
  }
}

fn hd_or_default(list: List(a)) -> a {
  case list {
    [first, ..] -> first
    _ -> panic as "empty list"
  }
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(a: Int) -> String
