import gleam/dict.{type Dict}

// ── Document ──────────────────────────────────────────────────

pub type Document {
  Document(lines: List(Line))
}

// ── Lines ─────────────────────────────────────────────────────

pub type Line {
  Comment(line_number: Int, raw: String)
  Blank(line_number: Int)
  TableHeader(line_number: Int, path: List(String))
  ArrayOfTablesHeader(line_number: Int, path: List(String))
  Entry(line_number: Int, key: List(String), value: TomlValue)
}

// ── TOML Values ───────────────────────────────────────────────

pub type TomlValue {
  TomlString(String)
  TomlInteger(Int)
  TomlFloat(Float)
  TomlBoolean(Bool)
  TomlDate(TomlDate)
  TomlTime(TomlTime)
  TomlDateTime(TomlDateTime)
  TomlArray(List(TomlValue))
  TomlTable(Dict(String, TomlValue))
  TomlInlineTable(Dict(String, TomlValue))
}

// ── Date / Time / DateTime ────────────────────────────────────

pub type TomlDate {
  Date(year: Int, month: Int, day: Int)
}

pub type TomlTime {
  Time(hour: Int, minute: Int, second: Int, nanosecond: Int)
}

pub type DateTimeOffset {
  Utc
  Offset(hours: Int, minutes: Int)
  Local
}

pub type TomlDateTime {
  DateTime(date: TomlDate, time: TomlTime, offset: DateTimeOffset)
}

// ── Get Result ────────────────────────────────────────────────

pub type GetResult {
  GetResult(key: String, value: TomlValue, line_number: Int)
}

// ── Errors ────────────────────────────────────────────────────

pub type ParseError {
  UnexpectedCharacter(char: String, expected: String, line: Int)
  UnterminatedString(line: Int)
  InvalidValue(line: Int)
  UnexpectedEOF(expected: String)
  InvalidKey(line: Int)
  DuplicateKey(key: List(String), line: Int)
  InvalidTableHeader(line: Int)
}

pub type EditError {
  KeyNotFound(key: String)
  TableNotFound(path: String)
  InvalidOperation(message: String)
}
