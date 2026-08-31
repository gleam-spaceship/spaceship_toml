# spaceship_toml

[![Package Version](https://img.shields.io/hexpm/v/spaceship_toml)](https://hex.pm/packages/spaceship_toml)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://spaceship-toml.hexdocs.pm/)

A TOML parser, editor, and serializer for Gleam that preserves comments, formatting, and line numbers.

Parse a TOML config file, edit values programmatically, and serialize it back — all without losing your comments or indentation.

```sh
gleam add spaceship_toml
```

## Quick Start

```gleam
import spaceship_toml
import gleam/option.{None}

pub fn main() {
  let input = "
# App config
name = \"my-app\"

[server]
host = \"localhost\"
port = 8080
"

  // Parse
  let assert Ok(doc) = spaceship_toml.parse(input)

  // Get a value (with line number)
  let assert Ok(result) = spaceship_toml.get(doc, ["server", "port"])
  // result.value == TomlInteger(8080)
  // result.line_number == 7

  // Edit
  let assert Ok(doc) =
    spaceship_toml.set(doc, ["server", "port"], spaceship_toml.integer(9090), None)

  // Serialize (preserves comments and formatting)
  let output = spaceship_toml.to_string(doc)
  // "# App config\nname = \"my-app\"\n\n[server]\nhost = \"localhost\"\nport = 9090\n"
}
```

## API

### Parsing & Serialization

```gleam
// Parse TOML string into a Document
spaceship_toml.parse(input: String) -> Result(Document, ParseError)

// Serialize a Document back to a TOML string
spaceship_toml.to_string(doc: Document) -> String
```

### Reading Values

```gleam
// Get a value by key path, returns key, value, and line number
spaceship_toml.get(doc, ["server", "host"])
// -> Ok(GetResult(key: "server.host", value: TomlString("localhost"), line_number: 5))
```

### Typed Getters

Type-safe getters that return the value directly, avoiding manual pattern matching:

```gleam
// Returns #(value, line_number)
let assert Ok(#(name, _line)) = spaceship_toml.get_string(doc, ["name"])
let assert Ok(#(count, _line)) = spaceship_toml.get_int(doc, ["count"])
let assert Ok(#(pi, _line)) = spaceship_toml.get_float(doc, ["pi"])
let assert Ok(#(debug, _line)) = spaceship_toml.get_bool(doc, ["debug"])
let assert Ok(#(items, _line)) = spaceship_toml.get_array(doc, ["items"])
let assert Ok(#(created, _line)) = spaceship_toml.get_date(doc, ["created"])
let assert Ok(#(time, _line)) = spaceship_toml.get_time(doc, ["time"])
let assert Ok(#(timestamp, _line)) = spaceship_toml.get_datetime(doc, ["timestamp"])
```

Returns `Error(KeyNotFound(...))` if the key doesn't exist or the type doesn't match.

### Editing Values

```gleam
// Set a value (update existing or append)
spaceship_toml.set(doc, ["key"], spaceship_toml.string("value"), None)

// Set at a specific line number
spaceship_toml.set(doc, ["key"], spaceship_toml.string("value"), Some(10))

// Delete a key
spaceship_toml.delete(doc, ["key"])

// Rename a key
spaceship_toml.rename_key(doc, ["old_name"], ["new_name"])
```

### Table Operations

```gleam
// Get all entries in a table
spaceship_toml.get_table(doc, ["server"])
// -> Ok([#("server.host", TomlString("localhost")), #("server.port", TomlInteger(8080))])

// Add a new table header
spaceship_toml.add_table(doc, ["database"], None)
```

### Value Constructors

```gleam
spaceship_toml.string("hello")       // -> TomlString("hello")
spaceship_toml.integer(42)           // -> TomlInteger(42)
spaceship_toml.float(3.14)           // -> TomlFloat(3.14)
spaceship_toml.boolean(True)         // -> TomlBoolean(True)
spaceship_toml.array([a, b, c])      // -> TomlArray([...])
spaceship_toml.table(entries)        // -> TomlTable(...)
spaceship_toml.inline_table(entries) // -> TomlInlineTable(...)
spaceship_toml.date(2025, 1, 15)     // -> TomlDate(...)
spaceship_toml.time(14, 30, 0)       // -> TomlTime(...)
spaceship_toml.datetime(2025, 1, 15, 14, 30, 0) // -> TomlDateTime(...)
```

## Supported TOML Features

- Strings (basic, literal, multiline)
- Integers (decimal, hex `0x`, octal `0o`, binary `0b`)
- Floats (with exponents, `inf`, `nan`)
- Booleans
- Dates, Times, and DateTimes
- Tables (`[table]`) and arrays of tables (`[[array]]`)
- Inline tables (`{ key = value }`)
- Arrays (`[1, 2, 3]`)
- Comments (`# comment`)
- Dotted keys (`server.host = "localhost"`)

## Types

```gleam
pub type Document   // The parsed TOML document
pub type TomlValue  // All TOML value types
pub type GetResult  // Result of get(): key, value, and line_number
pub type ParseError // Parse error with line information
pub type EditError  // Edit error (key not found, etc.)
```

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
gleam format  # Format the code
```

## License

Apache-2.0
