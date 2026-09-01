import gleam/dict.{type Dict}
import gleam/option.{type Option}
import spaceship_toml/internal/editor
import spaceship_toml/internal/parser
import spaceship_toml/internal/serializer
import spaceship_toml/internal/types.{
  type Document, type EditError, type GetResult, type ParseError, type TomlDate,
  type TomlDateTime, type TomlTime, type TomlValue,
}

// ── Parse ─────────────────────────────────────────────────────

pub fn parse(input: String) -> Result(Document, ParseError) {
  parser.parse(input)
}

// ── Serialize ─────────────────────────────────────────────────

pub fn to_string(doc: Document) -> String {
  serializer.to_string(doc)
}

// ── Get ───────────────────────────────────────────────────────

pub fn get(doc: Document, key: List(String)) -> Result(GetResult, EditError) {
  editor.get(doc, key)
}

// ── Typed Getters ────────────────────────────────────────────

pub fn get_string(
  doc: Document,
  key: List(String),
) -> Result(#(String, Int), EditError) {
  editor.get_string(doc, key)
}

pub fn get_int(
  doc: Document,
  key: List(String),
) -> Result(#(Int, Int), EditError) {
  editor.get_int(doc, key)
}

pub fn get_float(
  doc: Document,
  key: List(String),
) -> Result(#(Float, Int), EditError) {
  editor.get_float(doc, key)
}

pub fn get_bool(
  doc: Document,
  key: List(String),
) -> Result(#(Bool, Int), EditError) {
  editor.get_bool(doc, key)
}

pub fn get_array(
  doc: Document,
  key: List(String),
) -> Result(#(List(TomlValue), Int), EditError) {
  editor.get_array(doc, key)
}

pub fn get_date(
  doc: Document,
  key: List(String),
) -> Result(#(TomlDate, Int), EditError) {
  editor.get_date(doc, key)
}

pub fn get_time(
  doc: Document,
  key: List(String),
) -> Result(#(TomlTime, Int), EditError) {
  editor.get_time(doc, key)
}

pub fn get_datetime(
  doc: Document,
  key: List(String),
) -> Result(#(TomlDateTime, Int), EditError) {
  editor.get_datetime(doc, key)
}

// ── Set ───────────────────────────────────────────────────────

pub fn set(
  doc: Document,
  key: List(String),
  value: TomlValue,
  line_number: Option(Int),
) -> Result(Document, EditError) {
  editor.set(doc, key, value, line_number)
}

// ── Delete ────────────────────────────────────────────────────

pub fn delete(doc: Document, key: List(String)) -> Result(Document, EditError) {
  editor.delete(doc, key)
}

// ── Rename ────────────────────────────────────────────────────

pub fn rename_key(
  doc: Document,
  old_key: List(String),
  new_key: List(String),
) -> Result(Document, EditError) {
  editor.rename_key(doc, old_key, new_key)
}

// ── Table Operations ──────────────────────────────────────────

pub fn get_table(
  doc: Document,
  path: List(String),
) -> Result(List(#(String, TomlValue)), EditError) {
  editor.get_table(doc, path)
}

pub fn add_table(
  doc: Document,
  path: List(String),
  line_number: Option(Int),
) -> Result(Document, EditError) {
  editor.add_table(doc, path, line_number)
}

pub fn add_array_of_tables(
  doc: Document,
  path: List(String),
  line_number: Option(Int),
) -> Result(Document, EditError) {
  editor.add_array_of_tables(doc, path, line_number)
}

// ── Value Constructors ────────────────────────────────────────

pub fn string(value: String) -> TomlValue {
  types.TomlString(value)
}

pub fn integer(value: Int) -> TomlValue {
  types.TomlInteger(value)
}

pub fn float(value: Float) -> TomlValue {
  types.TomlFloat(value)
}

pub fn boolean(value: Bool) -> TomlValue {
  types.TomlBoolean(value)
}

pub fn array(items: List(TomlValue)) -> TomlValue {
  types.TomlArray(items)
}

pub fn table(entries: Dict(String, TomlValue)) -> TomlValue {
  types.TomlTable(entries)
}

pub fn inline_table(entries: Dict(String, TomlValue)) -> TomlValue {
  types.TomlInlineTable(entries)
}

pub fn date(year: Int, month: Int, day: Int) -> TomlValue {
  types.TomlDate(types.Date(year: year, month: month, day: day))
}

pub fn time(hour: Int, minute: Int, second: Int) -> TomlValue {
  types.TomlTime(types.Time(
    hour: hour,
    minute: minute,
    second: second,
    nanosecond: 0,
  ))
}

pub fn datetime(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
  minute: Int,
  second: Int,
) -> TomlValue {
  types.TomlDateTime(types.DateTime(
    date: types.Date(year: year, month: month, day: day),
    time: types.Time(hour: hour, minute: minute, second: second, nanosecond: 0),
    offset: types.Local,
  ))
}
