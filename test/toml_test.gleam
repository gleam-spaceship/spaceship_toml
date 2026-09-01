import gleam/int
import gleam/io
import gleam/list
import gleeunit
import spaceship_toml
import spaceship_toml/internal/tokenizer
import spaceship_toml/internal/types

pub fn main() {
  gleeunit.main()
}

pub fn parse_inline_table_test() {
  let input = "note_shared = { path = \"../shared\" }\n"
  
  // First, let's see what tokens we get
  case tokenizer.tokenize(input) {
    Ok(tokens) -> {
      io.println("Tokens:")
      list.each(tokens, fn(t) { io.println(token_to_string(t)) })
    }
    Error(e) -> {
      io.println("Tokenize error")
    }
  }
  
  // Now try parsing
  let result = spaceship_toml.parse(input)
  case result {
    Ok(doc) -> {
      io.println("\nParsed successfully")
      io.println(spaceship_toml.to_string(doc))
    }
    Error(e) -> {
      io.println("\nParse failed: " <> error_to_string(e))
    }
  }
}

fn token_to_string(t) -> String {
  case t {
    tokenizer.LBrace(_) -> "LBrace"
    tokenizer.RBrace(_) -> "RBrace"
    tokenizer.Equals(_) -> "Equals"
    tokenizer.BareKey(_, v) -> "BareKey(" <> v <> ")"
    tokenizer.BareString(_, v) -> "BareString(" <> v <> ")"
    tokenizer.Whitespace(_, _) -> "Whitespace"
    tokenizer.Newline(_) -> "Newline"
    _ -> "Other"
  }
}

fn error_to_string(e) -> String {
  case e {
    types.InvalidKey(line) -> "InvalidKey at line " <> int.to_string(line)
    types.InvalidValue(line) -> "InvalidValue at line " <> int.to_string(line)
    types.UnterminatedString(line) -> "UnterminatedString at line " <> int.to_string(line)
    types.UnexpectedCharacter(char, expected, line) ->
      "UnexpectedCharacter '" <> char <> "' expected '" <> expected <> "' at line " <> int.to_string(line)
    types.UnexpectedEOF(expected) -> "UnexpectedEOF expected '" <> expected <> "'"
    types.DuplicateKey(_key, line) -> "DuplicateKey at line " <> int.to_string(line)
    types.InvalidTableHeader(line) -> "InvalidTableHeader at line " <> int.to_string(line)
  }
}
