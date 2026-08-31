import gleam/int
import gleam/list
import gleam/regexp
import gleam/string

// ── Token Types ───────────────────────────────────────────────

pub type Token {
  // Structure
  LSquare(line: Int)
  RSquare(line: Int)
  DoubleLSquare(line: Int)
  DoubleRSquare(line: Int)
  LBrace(line: Int)
  RBrace(line: Int)
  Equals(line: Int)
  Comma(line: Int)
  Dot(line: Int)

  // Literals
  BareKey(line: Int, value: String)
  BareString(line: Int, value: String)
  LiteralString(line: Int, value: String)
  MultiLineString(line: Int, value: String)
  MultiLineLiteralString(line: Int, value: String)
  Integer(line: Int, value: Int)
  Float(line: Int, value: Float)
  Boolean(line: Int, value: Bool)

  // Datetime
  DateTime(line: Int, value: String)

  // Special float values
  Nan(line: Int, positive: Bool)
  Infinity(line: Int, positive: Bool)

  // Formatting (preserved for serialization)
  Comment(line: Int, raw: String)
  Newline(line: Int)
  Whitespace(line: Int, value: String)
}

// ── Tokenizer State ───────────────────────────────────────────

type State {
  State(
    input: List(String),
    line: Int,
    col: Int,
    tokens: List(Token),
    in_multiline_string: Bool,
    multiline_delimiter: String,
  )
}

pub type TokenizeError {
  UnterminatedString(line: Int)
  UnexpectedCharacter(char: String, line: Int)
  UnterminatedMultilineString(line: Int)
}

// ── Public API ────────────────────────────────────────────────

pub fn tokenize(input: String) -> Result(List(Token), TokenizeError) {
  let graphemes = string.to_graphemes(input)
  let state =
    State(
      input: graphemes,
      line: 1,
      col: 1,
      tokens: [],
      in_multiline_string: False,
      multiline_delimiter: "",
    )
  case do_tokenize(state) {
    Ok(state) -> Ok(list.reverse(state.tokens))
    Error(e) -> Error(e)
  }
}

fn do_tokenize(state: State) -> Result(State, TokenizeError) {
  case state.input {
    [] -> Ok(state)

    // Newlines
    ["\r", "\n", ..rest] -> {
      let state = push_token(state, Newline(state.line))
      do_tokenize(State(..state, input: rest, line: state.line + 1, col: 1))
    }

    ["\n", ..rest] -> {
      let state = push_token(state, Newline(state.line))
      do_tokenize(State(..state, input: rest, line: state.line + 1, col: 1))
    }

    // Comments — take_until_newline consumes the \n, so advance line by 1
    ["#", ..rest] -> {
      let #(comment_chars, remaining) = take_until_newline(rest, [])
      let raw = "#" <> string_join(comment_chars, "")
      let state = push_token(state, Comment(state.line, raw))
      let next_line = case remaining {
        [] -> state.line
        _ -> state.line + 1
      }
      do_tokenize(State(..state, input: remaining, line: next_line, col: 1))
    }

    // Whitespace (spaces and tabs only, not newlines)
    [ch, ..rest] if ch == " " || ch == "\t" -> {
      let #(ws_chars, remaining) = take_while_ws(rest, [ch])
      let raw = string_join(ws_chars, "")
      let state = push_token(state, Whitespace(state.line, raw))
      do_tokenize(
        State(..state, input: remaining, col: state.col + list.length(ws_chars)),
      )
    }

    // Triple-quoted multiline strings
    ["\"", "\"", "\"", ..rest] if !state.in_multiline_string -> {
      case parse_multiline_string(state, rest, "\"\"\"", []) {
        Ok(state) -> Ok(state)
        Error(e) -> Error(e)
      }
    }

    ["'", "'", "'", ..rest] if !state.in_multiline_string -> {
      case parse_multiline_string(state, rest, "'''", []) {
        Ok(state) -> Ok(state)
        Error(e) -> Error(e)
      }
    }

    // Regular strings
    ["\"", ..rest] -> {
      parse_quoted_string(state, rest, "\"", [])
    }

    ["'", ..rest] -> {
      parse_quoted_string(state, rest, "'", [])
    }

    // Brackets and braces
    ["[", "[", ..rest] -> {
      let state = push_token(state, DoubleLSquare(state.line))
      do_tokenize(State(..state, input: rest, col: state.col + 2))
    }

    ["]", "]", ..rest] -> {
      let state = push_token(state, DoubleRSquare(state.line))
      do_tokenize(State(..state, input: rest, col: state.col + 2))
    }

    ["[", ..rest] -> {
      let state = push_token(state, LSquare(state.line))
      do_tokenize(State(..state, input: rest, col: state.col + 1))
    }

    ["]", ..rest] -> {
      let state = push_token(state, RSquare(state.line))
      do_tokenize(State(..state, input: rest, col: state.col + 1))
    }

    ["{", ..rest] -> {
      let state = push_token(state, LBrace(state.line))
      do_tokenize(State(..state, input: rest, col: state.col + 1))
    }

    ["}", ..rest] -> {
      let state = push_token(state, RBrace(state.line))
      do_tokenize(State(..state, input: rest, col: state.col + 1))
    }

    // Equals
    ["=", ..rest] -> {
      let state = push_token(state, Equals(state.line))
      do_tokenize(State(..state, input: rest, col: state.col + 1))
    }

    // Comma
    [",", ..rest] -> {
      let state = push_token(state, Comma(state.line))
      do_tokenize(State(..state, input: rest, col: state.col + 1))
    }

    // Dot (for dotted keys)
    [".", ..rest] -> {
      let state = push_token(state, Dot(state.line))
      do_tokenize(State(..state, input: rest, col: state.col + 1))
    }

    // Numbers and identifiers
    [ch, ..rest] -> {
      case ch {
        // Special values
        "t" | "f" -> parse_boolean_or_bare(state, [ch, ..rest])
        "n" | "N" -> parse_nan_or_bare(state, [ch, ..rest], True)
        "i" | "I" -> parse_inf_or_bare(state, [ch, ..rest], True)
        // Signs
        "+" -> parse_sign_or_number(state, rest, True)
        "-" -> parse_sign_or_number(state, rest, False)
        // Numbers
        "0" -> parse_zero_or_hex(state, rest)
        _ -> {
          case is_digit(ch) {
            True -> parse_integer(state, rest, digit_to_int(ch))
            False -> parse_bare_key(state, [ch, ..rest])
          }
        }
      }
    }
  }
}

// ── String Parsing ────────────────────────────────────────────

fn parse_quoted_string(
  state: State,
  input: List(String),
  delimiter: String,
  acc: List(String),
) -> Result(State, TokenizeError) {
  case input {
    [] -> Error(UnterminatedString(state.line))

    [ch, ..rest] if ch == delimiter -> {
      let value = string_join(list.reverse(acc), "")
      let token = case delimiter {
        "\"" -> BareString(state.line, value)
        _ -> LiteralString(state.line, value)
      }
      let state = push_token(state, token)
      do_tokenize(State(..state, input: rest, col: state.col + 1))
    }

    ["\\", "n", ..rest] -> {
      parse_quoted_string(state, rest, delimiter, ["\n", ..acc])
    }

    ["\\", "t", ..rest] -> {
      parse_quoted_string(state, rest, delimiter, ["\t", ..acc])
    }

    ["\\", "r", ..rest] -> {
      parse_quoted_string(state, rest, delimiter, ["\r", ..acc])
    }

    ["\\", "\\", ..rest] -> {
      parse_quoted_string(state, rest, delimiter, ["\\", ..acc])
    }

    ["\\", "\"", ..rest] -> {
      parse_quoted_string(state, rest, delimiter, ["\"", ..acc])
    }

    ["\\", "'", ..rest] -> {
      parse_quoted_string(state, rest, delimiter, ["'", ..acc])
    }

    ["\n", ..] -> Error(UnterminatedString(state.line))

    [ch, ..rest] -> {
      parse_quoted_string(state, rest, delimiter, [ch, ..acc])
    }
  }
}

fn parse_multiline_string(
  state: State,
  input: List(String),
  delimiter: String,
  acc: List(String),
) -> Result(State, TokenizeError) {
  case input {
    [] -> Error(UnterminatedMultilineString(state.line))

    ["\"", "\"", "\"", ..rest] if delimiter == "\"\"\"" -> {
      let value = string_join(list.reverse(acc), "")
      let state = push_token(state, MultiLineString(state.line, value))
      do_tokenize(State(..state, input: rest, col: state.col + 3))
    }

    ["'", "'", "'", ..rest] if delimiter == "'''" -> {
      let value = string_join(list.reverse(acc), "")
      let state = push_token(state, MultiLineLiteralString(state.line, value))
      do_tokenize(State(..state, input: rest, col: state.col + 3))
    }

    ["\n", ..rest] -> {
      parse_multiline_string(state, rest, delimiter, ["\n", ..acc])
    }

    ["\\", "n", ..rest] -> {
      parse_multiline_string(state, rest, delimiter, ["\n", ..acc])
    }

    ["\\", "t", ..rest] -> {
      parse_multiline_string(state, rest, delimiter, ["\t", ..acc])
    }

    ["\\", "\\", ..rest] -> {
      parse_multiline_string(state, rest, delimiter, ["\\", ..acc])
    }

    ["\\", "\"", ..rest] -> {
      parse_multiline_string(state, rest, delimiter, ["\"", ..acc])
    }

    [ch, ..rest] -> {
      parse_multiline_string(state, rest, delimiter, [ch, ..acc])
    }
  }
}

// ── Number Parsing ────────────────────────────────────────────

fn parse_sign_or_number(
  state: State,
  input: List(String),
  positive: Bool,
) -> Result(State, TokenizeError) {
  case input {
    ["n", "a", "n", ..rest] -> {
      let state = push_token(state, Nan(state.line, positive))
      do_tokenize(State(..state, input: rest, col: state.col + 3))
    }

    ["i", "n", "f", ..rest] -> {
      let state = push_token(state, Infinity(state.line, positive))
      do_tokenize(State(..state, input: rest, col: state.col + 3))
    }

    ["0", "x", ..rest] -> parse_hex(state, rest, 0, positive)
    ["0", "o", ..rest] -> parse_octal(state, rest, 0, positive)
    ["0", "b", ..rest] -> parse_binary(state, rest, 0, positive)

    [d, ..rest] -> {
      case is_digit(d) {
        True -> parse_integer_signed(state, rest, digit_to_int(d), positive)
        False -> {
          let ch = case input {
            [c, ..] -> c
            [] -> "EOF"
          }
          Error(UnexpectedCharacter(ch, state.line))
        }
      }
    }

    _ -> {
      let ch = case input {
        [c, ..] -> c
        [] -> "EOF"
      }
      Error(UnexpectedCharacter(ch, state.line))
    }
  }
}

fn parse_zero_or_hex(
  state: State,
  input: List(String),
) -> Result(State, TokenizeError) {
  case input {
    ["x", ..rest] -> parse_hex(state, rest, 0, True)
    ["o", ..rest] -> parse_octal(state, rest, 0, True)
    ["b", ..rest] -> parse_binary(state, rest, 0, True)
    [".", ..] -> parse_float(state, input, 0.0, 0.1, True)
    ["e", ..] | ["E", ..] -> parse_exponent(state, input, 0.0, 0, True)
    _ -> {
      let state = push_token(state, Integer(state.line, 0))
      do_tokenize(State(..state, input: input, col: state.col + 1))
    }
  }
}

fn parse_integer_signed(
  state: State,
  input: List(String),
  value: Int,
  positive: Bool,
) -> Result(State, TokenizeError) {
  do_parse_integer(state, input, value, positive)
}

fn parse_integer(
  state: State,
  input: List(String),
  first_digit: Int,
) -> Result(State, TokenizeError) {
  do_parse_integer(state, input, first_digit, True)
}

fn do_parse_integer(
  state: State,
  input: List(String),
  value: Int,
  positive: Bool,
) -> Result(State, TokenizeError) {
  case input {
    [d, ..rest] -> {
      case is_digit(d) {
        True -> {
          let digit = digit_to_int(d)
          do_parse_integer(state, rest, value * 10 + digit, positive)
        }

        False -> {
          case d {
            "_" -> do_parse_integer(state, rest, value, positive)
            "." -> parse_float(state, rest, int.to_float(value), 0.1, positive)
            "e" | "E" ->
              parse_exponent(state, rest, int.to_float(value), 0, positive)
            _ -> {
              let final_value = case positive {
                True -> value
                False -> -value
              }
              let state = push_token(state, Integer(state.line, final_value))
              do_tokenize(State(..state, input: input))
            }
          }
        }
      }
    }

    [] -> {
      let final_value = case positive {
        True -> value
        False -> -value
      }
      let state = push_token(state, Integer(state.line, final_value))
      do_tokenize(State(..state, input: []))
    }
  }
}

fn parse_hex(
  state: State,
  input: List(String),
  value: Int,
  positive: Bool,
) -> Result(State, TokenizeError) {
  case input {
    [d, ..rest] -> {
      case is_hex_digit(d) {
        True -> {
          let digit = hex_digit_to_int(d)
          parse_hex(state, rest, value * 16 + digit, positive)
        }

        False -> {
          case d {
            "_" -> parse_hex(state, rest, value, positive)
            _ -> {
              let value = case positive {
                True -> value
                False -> -value
              }
              let state = push_token(state, Integer(state.line, value))
              do_tokenize(State(..state, input: input))
            }
          }
        }
      }
    }

    [] -> {
      let value = case positive {
        True -> value
        False -> -value
      }
      let state = push_token(state, Integer(state.line, value))
      do_tokenize(State(..state, input: []))
    }
  }
}

fn parse_octal(
  state: State,
  input: List(String),
  value: Int,
  positive: Bool,
) -> Result(State, TokenizeError) {
  case input {
    [d, ..rest] -> {
      case is_octal_digit(d) {
        True -> {
          let digit = digit_to_int(d)
          parse_octal(state, rest, value * 8 + digit, positive)
        }

        False -> {
          case d {
            "_" -> parse_octal(state, rest, value, positive)
            _ -> {
              let value = case positive {
                True -> value
                False -> -value
              }
              let state = push_token(state, Integer(state.line, value))
              do_tokenize(State(..state, input: input))
            }
          }
        }
      }
    }

    [] -> {
      let value = case positive {
        True -> value
        False -> -value
      }
      let state = push_token(state, Integer(state.line, value))
      do_tokenize(State(..state, input: []))
    }
  }
}

fn parse_binary(
  state: State,
  input: List(String),
  value: Int,
  positive: Bool,
) -> Result(State, TokenizeError) {
  case input {
    [d, ..rest] -> {
      case d == "0" || d == "1" {
        True -> {
          let digit = digit_to_int(d)
          parse_binary(state, rest, value * 2 + digit, positive)
        }

        False -> {
          case d {
            "_" -> parse_binary(state, rest, value, positive)
            _ -> {
              let value = case positive {
                True -> value
                False -> -value
              }
              let state = push_token(state, Integer(state.line, value))
              do_tokenize(State(..state, input: input))
            }
          }
        }
      }
    }

    [] -> {
      let value = case positive {
        True -> value
        False -> -value
      }
      let state = push_token(state, Integer(state.line, value))
      do_tokenize(State(..state, input: []))
    }
  }
}

fn parse_float(
  state: State,
  input: List(String),
  value: Float,
  unit: Float,
  positive: Bool,
) -> Result(State, TokenizeError) {
  case input {
    [d, ..rest] -> {
      case is_digit(d) {
        True -> {
          let digit = int.to_float(digit_to_int(d))
          parse_float(
            state,
            rest,
            value +. digit *. unit,
            unit *. 0.1,
            positive,
          )
        }

        False -> {
          case d {
            "_" -> parse_float(state, rest, value, unit, positive)
            "e" | "E" -> parse_exponent(state, rest, value, 0, True)
            _ -> {
              let value = case positive {
                True -> value
                False -> value *. -1.0
              }
              let state = push_token(state, Float(state.line, value))
              do_tokenize(State(..state, input: input))
            }
          }
        }
      }
    }

    [] -> {
      let value = case positive {
        True -> value
        False -> value *. -1.0
      }
      let state = push_token(state, Float(state.line, value))
      do_tokenize(State(..state, input: []))
    }
  }
}

fn parse_exponent(
  state: State,
  input: List(String),
  value: Float,
  exponent: Int,
  positive: Bool,
) -> Result(State, TokenizeError) {
  case input {
    ["+", ..rest] -> parse_exponent(state, rest, value, exponent, True)
    ["-", ..rest] -> parse_exponent(state, rest, value, exponent, False)

    [d, ..rest] -> {
      case is_digit(d) {
        True -> {
          let digit = digit_to_int(d)
          parse_exponent(state, rest, value, exponent * 10 + digit, positive)
        }

        False -> {
          let exponent = case positive {
            True -> exponent
            False -> -exponent
          }
          let multiplier = power_of_10(exponent)
          let value = value *. multiplier
          let state = push_token(state, Float(state.line, value))
          do_tokenize(State(..state, input: input))
        }
      }
    }

    [] -> {
      let exponent = case positive {
        True -> exponent
        False -> -exponent
      }
      let multiplier = power_of_10(exponent)
      let value = value *. multiplier
      let state = push_token(state, Float(state.line, value))
      do_tokenize(State(..state, input: []))
    }
  }
}

// ── Boolean / Special Value Parsing ──────────────────────────

fn parse_boolean_or_bare(
  state: State,
  input: List(String),
) -> Result(State, TokenizeError) {
  case input {
    ["t", "r", "u", "e", ..rest] -> {
      let state = push_token(state, Boolean(state.line, True))
      do_tokenize(State(..state, input: rest, col: state.col + 4))
    }

    ["f", "a", "l", "s", "e", ..rest] -> {
      let state = push_token(state, Boolean(state.line, False))
      do_tokenize(State(..state, input: rest, col: state.col + 5))
    }

    _ -> parse_bare_key(state, input)
  }
}

fn parse_nan_or_bare(
  state: State,
  input: List(String),
  positive: Bool,
) -> Result(State, TokenizeError) {
  case input {
    ["a", "n", ..rest] -> {
      let state = push_token(state, Nan(state.line, positive))
      do_tokenize(State(..state, input: rest, col: state.col + 2))
    }

    _ -> parse_bare_key(state, input)
  }
}

fn parse_inf_or_bare(
  state: State,
  input: List(String),
  positive: Bool,
) -> Result(State, TokenizeError) {
  case input {
    ["n", "f", ..rest] -> {
      let state = push_token(state, Infinity(state.line, positive))
      do_tokenize(State(..state, input: rest, col: state.col + 2))
    }

    _ -> parse_bare_key(state, input)
  }
}

// ── Bare Key Parsing ─────────────────────────────────────────

fn parse_bare_key(
  state: State,
  input: List(String),
) -> Result(State, TokenizeError) {
  do_parse_bare_key(state, input, [])
}

fn do_parse_bare_key(
  state: State,
  input: List(String),
  acc: List(String),
) -> Result(State, TokenizeError) {
  case input {
    [] -> {
      let value = string_join(list.reverse(acc), "")
      case value {
        "" -> Error(UnexpectedCharacter("EOF", state.line))
        _ -> {
          let state = push_token(state, BareKey(state.line, value))
          Ok(State(..state, input: []))
        }
      }
    }

    [ch, ..rest] -> {
      case is_bare_key_char(ch) {
        True -> do_parse_bare_key(state, rest, [ch, ..acc])
        False -> {
          let value = string_join(list.reverse(acc), "")
          case value {
            "" -> Error(UnexpectedCharacter(ch, state.line))
            _ -> {
              let state = push_token(state, BareKey(state.line, value))
              do_tokenize(State(..state, input: input))
            }
          }
        }
      }
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────

fn push_token(state: State, token: Token) -> State {
  State(..state, tokens: [token, ..state.tokens])
}

fn take_until_newline(
  input: List(String),
  acc: List(String),
) -> #(List(String), List(String)) {
  case input {
    [] -> #(list.reverse(acc), [])
    ["\n", ..rest] -> #(list.reverse(acc), rest)
    ["\r", "\n", ..rest] -> #(list.reverse(acc), rest)
    [ch, ..rest] -> take_until_newline(rest, [ch, ..acc])
  }
}

fn take_while_ws(
  input: List(String),
  acc: List(String),
) -> #(List(String), List(String)) {
  case input {
    [] -> #(list.reverse(acc), [])
    [ch, ..rest] if ch == " " || ch == "\t" -> take_while_ws(rest, [ch, ..acc])
    _ -> #(list.reverse(acc), input)
  }
}

// ── Character Classification (using regex) ────────────────────

const re_bare_key_char = "^[A-Za-z0-9_\\-\\x{00B2}\\x{00B3}\\x{00B9}\\x{2070}-\\x{2079}\\x{2080}-\\x{2089}\\x{2160}-\\x{216F}\\x{2170}-\\x{217F}\\x{2460}-\\x{24FF}\\x{FF10}-\\x{FF19}]"

const re_digit = "^[0-9]"

const re_hex_digit = "^[0-9a-fA-F]"

const re_octal_digit = "^[0-7]"

fn is_bare_key_char(ch: String) -> Bool {
  let assert Ok(re) = regexp.from_string(re_bare_key_char)
  regexp.check(re, ch)
}

fn is_digit(ch: String) -> Bool {
  let assert Ok(re) = regexp.from_string(re_digit)
  regexp.check(re, ch)
}

fn is_hex_digit(ch: String) -> Bool {
  let assert Ok(re) = regexp.from_string(re_hex_digit)
  regexp.check(re, ch)
}

fn is_octal_digit(ch: String) -> Bool {
  let assert Ok(re) = regexp.from_string(re_octal_digit)
  regexp.check(re, ch)
}

fn digit_to_int(ch: String) -> Int {
  case ch {
    "0" -> 0
    "1" -> 1
    "2" -> 2
    "3" -> 3
    "4" -> 4
    "5" -> 5
    "6" -> 6
    "7" -> 7
    "8" -> 8
    "9" -> 9
    _ -> 0
  }
}

fn hex_digit_to_int(ch: String) -> Int {
  case ch {
    "0" -> 0
    "1" -> 1
    "2" -> 2
    "3" -> 3
    "4" -> 4
    "5" -> 5
    "6" -> 6
    "7" -> 7
    "8" -> 8
    "9" -> 9
    "a" | "A" -> 10
    "b" | "B" -> 11
    "c" | "C" -> 12
    "d" | "D" -> 13
    "e" | "E" -> 14
    "f" | "F" -> 15
    _ -> 0
  }
}

fn power_of_10(exp: Int) -> Float {
  case exp {
    0 -> 1.0
    1 -> 10.0
    2 -> 100.0
    3 -> 1000.0
    4 -> 10_000.0
    5 -> 100_000.0
    6 -> 1_000_000.0
    7 -> 10_000_000.0
    8 -> 100_000_000.0
    9 -> 1_000_000_000.0
    10 -> 10_000_000_000.0
    n if n > 10 -> 10.0 *. power_of_10(n - 1)
    n -> 1.0 /. power_of_10(-n)
  }
}

fn string_join(list: List(String), sep: String) -> String {
  case list {
    [] -> ""
    [first, ..rest] -> {
      do_string_join(rest, sep, first)
    }
  }
}

fn do_string_join(list: List(String), sep: String, acc: String) -> String {
  case list {
    [] -> acc
    [first, ..rest] -> do_string_join(rest, sep, acc <> sep <> first)
  }
}
