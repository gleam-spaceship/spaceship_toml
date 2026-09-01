import gleam/dict
import gleam/list
import gleam/string
import spaceship_toml/internal/types.{
  type Document, type Line, type TomlDate, type TomlDateTime, type TomlTime,
  type TomlValue, ArrayOfTablesHeader, Blank, Comment, Date as DateConstructor,
  DateTime as DateTimeConstructor, Entry, Local, Offset, TableHeader,
  Time as TimeConstructor, TomlArray, TomlBoolean, TomlDate, TomlDateTime,
  TomlFloat, TomlInlineTable, TomlInteger, TomlString, TomlTable, TomlTime, Utc,
}

// ── Public API ────────────────────────────────────────────────

/// Serialize a Document back to a TOML string.
pub fn to_string(doc: Document) -> String {
  do_to_string(doc.lines, "", [], False)
}

fn do_to_string(lines: List(Line), acc: String, table: List(String), prev_was_entry: Bool) -> String {
  case lines {
    [] -> acc

    [Comment(_, raw), ..rest] -> {
      do_to_string(rest, acc <> raw <> "\n", table, False)
    }

    [Blank(_), ..rest] -> {
      do_to_string(rest, acc <> "\n", table, False)
    }

    [TableHeader(_, path), ..rest] -> {
      let header = "[" <> string.join(path, ".") <> "]"
      let acc = case prev_was_entry {
        True -> acc <> "\n"
        False -> acc
      }
      do_to_string(rest, acc <> header <> "\n", path, False)
    }

    [ArrayOfTablesHeader(_, path), ..rest] -> {
      let header = "[[" <> string.join(path, ".") <> "]]"
      let acc = case prev_was_entry {
        True -> acc <> "\n"
        False -> acc
      }
      do_to_string(rest, acc <> header <> "\n", path, False)
    }

    [Entry(_, key, value), ..rest] -> {
      // Only strip table prefix if key starts with it
      let leaf_key = case key, table {
        [first, .._rest_key], [table_first, .._rest_table] if first == table_first -> {
          list.drop(key, list.length(table))
        }
        _, _ -> key
      }
      let key_str = format_key(leaf_key)
      let val_str = serialize_value(value)
      do_to_string(rest, acc <> key_str <> " = " <> val_str <> "\n", table, True)
    }
  }
}

// ── Value Serialization ───────────────────────────────────────

fn serialize_value(value: TomlValue) -> String {
  case value {
    TomlString(s) -> serialize_string(s)
    TomlInteger(i) -> int_to_string(i)
    TomlFloat(f) -> float_to_string(f)
    TomlBoolean(True) -> "true"
    TomlBoolean(False) -> "false"
    TomlDate(d) -> serialize_date(d)
    TomlTime(t) -> serialize_time(t)
    TomlDateTime(dt) -> serialize_datetime(dt)
    TomlArray(arr) -> serialize_array(arr)
    TomlTable(t) -> serialize_table(t)
    TomlInlineTable(t) -> serialize_inline_table(t)
  }
}

fn serialize_string(s: String) -> String {
  let needs_escape =
    string.contains(s, "\"")
    || string.contains(s, "\\")
    || string.contains(s, "\n")
    || string.contains(s, "\r")
    || string.contains(s, "\t")

  case needs_escape {
    True -> {
      let escaped =
        s
        |> string.replace("\\", "\\\\")
        |> string.replace("\"", "\\\"")
        |> string.replace("\n", "\\n")
        |> string.replace("\r", "\\r")
        |> string.replace("\t", "\\t")
      "\"" <> escaped <> "\""
    }

    False -> "\"" <> s <> "\""
  }
}

fn serialize_date(d: TomlDate) -> String {
  case d {
    DateConstructor(year:, month:, day:) -> {
      let year_str = int_to_string(year)
      let month_str = int_to_string(month) |> string.pad_start(2, "0")
      let day_str = int_to_string(day) |> string.pad_start(2, "0")
      year_str <> "-" <> month_str <> "-" <> day_str
    }
  }
}

fn serialize_time(t: TomlTime) -> String {
  case t {
    TimeConstructor(hour:, minute:, second:, nanosecond:) -> {
      let hour_str = int_to_string(hour) |> string.pad_start(2, "0")
      let minute_str = int_to_string(minute) |> string.pad_start(2, "0")
      let second_str = int_to_string(second) |> string.pad_start(2, "0")
      case nanosecond {
        0 -> hour_str <> ":" <> minute_str <> ":" <> second_str
        ns -> {
          let ns_str = int_to_string(ns) |> string.pad_end(9, "0")
          hour_str <> ":" <> minute_str <> ":" <> second_str <> "." <> ns_str
        }
      }
    }
  }
}

fn serialize_datetime(dt: TomlDateTime) -> String {
  case dt {
    DateTimeConstructor(date:, time:, offset:) -> {
      let date_str = serialize_date(date)
      let time_str = serialize_time(time)
      let offset_str = case offset {
        Utc -> "Z"
        Offset(hours:, minutes:) -> {
          let sign = case hours >= 0 {
            True -> "+"
            False -> "-"
          }
          let abs_hours =
            int_to_string(case hours < 0 {
              True -> -hours
              False -> hours
            })
          let abs_minutes =
            int_to_string(case minutes < 0 {
              True -> -minutes
              False -> minutes
            })
          sign
          <> string.pad_start(abs_hours, 2, "0")
          <> ":"
          <> string.pad_start(abs_minutes, 2, "0")
        }
        Local -> ""
      }
      date_str <> "T" <> time_str <> offset_str
    }
  }
}

fn serialize_array(arr: List(TomlValue)) -> String {
  case arr {
    [] -> "[]"

    _ -> {
      let items = list.map(arr, serialize_value) |> string.join(", ")
      "[" <> items <> "]"
    }
  }
}

fn serialize_table(t: dict.Dict(String, TomlValue)) -> String {
  let entries = dict.to_list(t)
  case entries {
    [] -> "{}"

    _ -> {
      let items =
        list.map(entries, fn(entry) {
          let #(key, value) = entry
          key <> " = " <> serialize_value(value)
        })
        |> string.join(", ")
      "{" <> items <> "}"
    }
  }
}

fn serialize_inline_table(t: dict.Dict(String, TomlValue)) -> String {
  serialize_table(t)
}

// ── Key Formatting ────────────────────────────────────────────

fn format_key(key: List(String)) -> String {
  case key {
    [single] -> {
      case is_bare_key(single) {
        True -> single
        False -> escape_key(single)
      }
    }

    _ -> {
      list.map(key, fn(segment) {
        case is_bare_key(segment) {
          True -> segment
          False -> escape_key(segment)
        }
      })
      |> string.join(".")
    }
  }
}

fn is_bare_key(s: String) -> Bool {
  let graphemes = string.to_graphemes(s)
  do_is_bare_key(graphemes)
}

fn do_is_bare_key(graphemes: List(String)) -> Bool {
  case graphemes {
    [] -> False
    _ -> {
      list.all(graphemes, fn(ch) {
        case ch {
          "a"
          | "b"
          | "c"
          | "d"
          | "e"
          | "f"
          | "g"
          | "h"
          | "i"
          | "j"
          | "k"
          | "l"
          | "m"
          | "n"
          | "o"
          | "p"
          | "q"
          | "r"
          | "s"
          | "t"
          | "u"
          | "v"
          | "w"
          | "x"
          | "y"
          | "z" -> True
          "A"
          | "B"
          | "C"
          | "D"
          | "E"
          | "F"
          | "G"
          | "H"
          | "I"
          | "J"
          | "K"
          | "L"
          | "M"
          | "N"
          | "O"
          | "P"
          | "Q"
          | "R"
          | "S"
          | "T"
          | "U"
          | "V"
          | "W"
          | "X"
          | "Y"
          | "Z" -> True
          "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
          "-" | "_" -> True
          _ -> False
        }
      })
    }
  }
}

fn escape_key(s: String) -> String {
  let escaped =
    s
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
  "\"" <> escaped <> "\""
}

// ── External Helpers ──────────────────────────────────────────

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string(a: Int) -> String

@external(erlang, "erlang", "float_to_binary")
fn float_to_string(a: Float) -> String
