import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/string
import spaceship_toml/internal/tokenizer.{type Token}
import spaceship_toml/internal/types.{
  type Document, type Line, type ParseError, type TomlValue, ArrayOfTablesHeader,
  Comment as CommentLine, Date as DateC, DateTime as DateTimeC, Entry,
  InvalidKey, InvalidValue, TableHeader, Time as TimeC, TomlArray, TomlBoolean,
  TomlDate, TomlDateTime, TomlFloat, TomlInlineTable, TomlInteger, TomlString,
  TomlTime, UnexpectedCharacter, UnexpectedEOF, UnterminatedString, Utc,
}

// ── Parser State ──────────────────────────────────────────────

type ParserState {
  ParserState(
    tokens: List(Token),
    lines: List(Line),
    current_table: List(String),
    current_line: Int,
  )
}

// ── Public API ────────────────────────────────────────────────

pub fn parse(input: String) -> Result(Document, ParseError) {
  case tokenizer.tokenize(input) {
    Error(e) ->
      Error(case e {
        tokenizer.UnterminatedString(line) -> UnterminatedString(line: line)
        tokenizer.UnterminatedMultilineString(line) ->
          UnterminatedString(line: line)
        tokenizer.UnexpectedCharacter(char, line) ->
          UnexpectedCharacter(char: char, expected: "", line: line)
      })

    Ok(tokens) -> {
      let state =
        ParserState(
          tokens: tokens,
          lines: [],
          current_table: [],
          current_line: 1,
        )
      case do_parse(state) {
        Ok(state) -> Ok(types.Document(lines: list.reverse(state.lines)))
        Error(e) -> Error(e)
      }
    }
  }
}

// ── Main Parse Loop ───────────────────────────────────────────

fn do_parse(state: ParserState) -> Result(ParserState, ParseError) {
  let tokens = skip_whitespace_tokens(state.tokens)
  case tokens {
    [] -> Ok(state)

    [tokenizer.Newline(_), ..rest] ->
      do_parse(
        ParserState(..state, tokens: rest, current_line: state.current_line + 1),
      )

    [token, ..rest] -> {
      let line = token_line(token)
      // Keep current token in state so parse_entry can parse it
      let state =
        ParserState(..state, tokens: [token, ..rest], current_line: line)
      case token {
        tokenizer.Comment(_, raw) -> {
          let line = CommentLine(line_number: line, raw: raw)
          do_parse(
            ParserState(..state, tokens: rest, lines: [line, ..state.lines]),
          )
        }

        tokenizer.LSquare(_) -> parse_table_header(state, rest)

        tokenizer.DoubleLSquare(_) -> parse_array_of_tables_header(state, rest)

        _ -> parse_entry(state)
      }
    }
  }
}

// ── Table Header Parsing ──────────────────────────────────────

fn parse_table_header(
  state: ParserState,
  tokens: List(Token),
) -> Result(ParserState, ParseError) {
  case parse_key_path(tokens) {
    Error(e) -> Error(e)
    Ok(#(path, remaining)) -> {
      let remaining = skip_whitespace_tokens(remaining)
      case remaining {
        [tokenizer.RSquare(_), ..rest] -> {
          let line = TableHeader(line_number: state.current_line, path: path)
          do_parse(
            ParserState(
              ..state,
              tokens: rest,
              lines: [line, ..state.lines],
              current_table: path,
            ),
          )
        }

        [] -> Error(UnexpectedEOF(expected: "']'"))

        [token, ..] ->
          Error(UnexpectedCharacter(
            char: describe_token(token),
            expected: "']'",
            line: token_line(token),
          ))
      }
    }
  }
}

// ── Array of Tables Header Parsing ────────────────────────────

fn parse_array_of_tables_header(
  state: ParserState,
  tokens: List(Token),
) -> Result(ParserState, ParseError) {
  case parse_key_path(tokens) {
    Error(e) -> Error(e)
    Ok(#(path, remaining)) -> {
      let remaining = skip_whitespace_tokens(remaining)
      case remaining {
        [tokenizer.DoubleRSquare(_), ..rest] -> {
          let line =
            ArrayOfTablesHeader(line_number: state.current_line, path: path)
          do_parse(
            ParserState(..state, tokens: rest, lines: [line, ..state.lines]),
          )
        }

        [] -> Error(UnexpectedEOF(expected: "']]'"))

        [token, ..] ->
          Error(UnexpectedCharacter(
            char: describe_token(token),
            expected: "']]'",
            line: token_line(token),
          ))
      }
    }
  }
}

// ── Entry Parsing ─────────────────────────────────────────────

fn parse_entry(state: ParserState) -> Result(ParserState, ParseError) {
  case parse_key_path(state.tokens) {
    Error(e) -> Error(e)
    Ok(#(key, remaining)) -> {
      // Skip whitespace before =
      let remaining = skip_whitespace_tokens(remaining)
      case remaining {
        [tokenizer.Equals(_), ..rest2] -> {
          // Skip whitespace after =
          let rest2 = skip_whitespace_tokens(rest2)
          case parse_value(rest2) {
            Error(e) -> Error(e)
            Ok(#(value, rest3)) -> {
              // Prepend table prefix to key
              let full_key = list.append(state.current_table, key)
              let line =
                Entry(
                  line_number: state.current_line,
                  key: full_key,
                  value: value,
                )
              do_parse(
                ParserState(..state, tokens: rest3, lines: [line, ..state.lines]),
              )
            }
          }
        }

        [] -> Error(UnexpectedEOF(expected: "'='"))

        [token, ..] ->
          Error(UnexpectedCharacter(
            char: describe_token(token),
            expected: "'='",
            line: token_line(token),
          ))
      }
    }
  }
}

// ── Key Path Parsing ──────────────────────────────────────────

fn parse_key_path(
  tokens: List(Token),
) -> Result(#(List(String), List(Token)), ParseError) {
  case parse_key_segment(tokens) {
    Error(e) -> Error(e)
    Ok(#(first, remaining)) -> {
      do_parse_key_path(remaining, [first])
    }
  }
}

fn do_parse_key_path(
  tokens: List(Token),
  segments: List(String),
) -> Result(#(List(String), List(Token)), ParseError) {
  case tokens {
    [tokenizer.Dot(_), ..rest] -> {
      case parse_key_segment(rest) {
        Error(e) -> Error(e)
        Ok(#(segment, remaining)) -> {
          do_parse_key_path(remaining, [segment, ..segments])
        }
      }
    }

    _ -> Ok(#(list.reverse(segments), tokens))
  }
}

fn parse_key_segment(
  tokens: List(Token),
) -> Result(#(String, List(Token)), ParseError) {
  case tokens {
    [tokenizer.BareKey(_, value), ..rest] -> Ok(#(value, rest))
    [tokenizer.BareString(_, value), ..rest] -> Ok(#(value, rest))
    [tokenizer.LiteralString(_, value), ..rest] -> Ok(#(value, rest))
    [] -> Error(UnexpectedEOF(expected: "key"))
    [token, ..] -> Error(InvalidKey(line: token_line(token)))
  }
}

// ── Value Parsing ─────────────────────────────────────────────

fn parse_value(
  tokens: List(Token),
) -> Result(#(TomlValue, List(Token)), ParseError) {
  case tokens {
    [] -> Error(UnexpectedEOF(expected: "value"))

    // Strings
    [tokenizer.BareString(_, value), ..rest] -> Ok(#(TomlString(value), rest))
    [tokenizer.LiteralString(_, value), ..rest] ->
      Ok(#(TomlString(value), rest))
    [tokenizer.MultiLineString(_, value), ..rest] ->
      Ok(#(TomlString(value), rest))
    [tokenizer.MultiLineLiteralString(_, value), ..rest] ->
      Ok(#(TomlString(value), rest))

    // Numbers
    [tokenizer.Integer(_, value), ..rest] -> Ok(#(TomlInteger(value), rest))
    [tokenizer.Float(_, value), ..rest] -> Ok(#(TomlFloat(value), rest))

    // Booleans
    [tokenizer.Boolean(_, value), ..rest] -> Ok(#(TomlBoolean(value), rest))

    // NaN
    [tokenizer.Nan(_, positive), ..rest] -> {
      let value = case positive {
        True -> 0.0 /. 0.0
        False -> 0.0 /. 0.0
      }
      Ok(#(TomlFloat(value), rest))
    }

    // Infinity
    [tokenizer.Infinity(_, positive), ..rest] -> {
      let value = case positive {
        True -> 1.0 /. 0.0
        False -> -1.0 /. 0.0
      }
      Ok(#(TomlFloat(value), rest))
    }

    // DateTime
    [tokenizer.DateTime(_, value), ..rest] -> {
      case parse_datetime_value(value) {
        Ok(tv) -> Ok(#(tv, rest))
        Error(e) -> Error(e)
      }
    }

    // Bare keys that might be true/false
    [tokenizer.BareKey(_, "true"), ..rest] -> Ok(#(TomlBoolean(True), rest))
    [tokenizer.BareKey(_, "false"), ..rest] -> Ok(#(TomlBoolean(False), rest))

    // Inline table { ... }
    [tokenizer.LBrace(_), ..rest] -> {
      parse_inline_table(rest)
    }

    // Array [ ... ]
    [tokenizer.LSquare(_), ..rest] -> {
      parse_array(rest)
    }

    [token, ..] -> Error(InvalidValue(line: token_line(token)))
  }
}

// ── Inline Table Parsing ──────────────────────────────────────

fn parse_inline_table(
  tokens: List(Token),
) -> Result(#(TomlValue, List(Token)), ParseError) {
  case tokens {
    [tokenizer.RBrace(_), ..rest] -> Ok(#(TomlInlineTable(dict.new()), rest))

    _ -> {
      parse_inline_table_entries(tokens, dict.new())
    }
  }
}

fn parse_inline_table_entries(
  tokens: List(Token),
  acc: Dict(String, TomlValue),
) -> Result(#(TomlValue, List(Token)), ParseError) {
  case parse_key_path(tokens) {
    Error(e) -> Error(e)
    Ok(#(key_parts, remaining)) -> {
      case remaining {
        [tokenizer.Equals(_), ..rest2] -> {
          case parse_value(rest2) {
            Error(e) -> Error(e)
            Ok(#(value, rest3)) -> {
              let key = string.join(key_parts, ".")
              let acc = dict.insert(acc, key, value)
              case rest3 {
                [tokenizer.Comma(_), ..rest4] ->
                  parse_inline_table_entries(rest4, acc)

                [tokenizer.RBrace(_), ..rest5] ->
                  Ok(#(TomlInlineTable(acc), rest5))

                [] -> Error(UnexpectedEOF(expected: "'}'"))

                _ -> Error(InvalidValue(line: 0))
              }
            }
          }
        }

        _ -> Error(InvalidValue(line: 0))
      }
    }
  }
}

// ── Array Parsing ─────────────────────────────────────────────

fn parse_array(
  tokens: List(Token),
) -> Result(#(TomlValue, List(Token)), ParseError) {
  case tokens {
    [tokenizer.RSquare(_), ..rest] -> Ok(#(TomlArray([]), rest))

    _ -> {
      case parse_value(tokens) {
        Error(e) -> Error(e)
        Ok(#(first, remaining)) -> {
          parse_array_items(remaining, [first])
        }
      }
    }
  }
}

fn parse_array_items(
  tokens: List(Token),
  acc: List(TomlValue),
) -> Result(#(TomlValue, List(Token)), ParseError) {
  // Skip commas and whitespace
  let tokens = skip_comma_and_whitespace(tokens)
  case tokens {
    [tokenizer.RSquare(_), ..rest] -> Ok(#(TomlArray(list.reverse(acc)), rest))

    [] -> Error(UnexpectedEOF(expected: "']'"))

    _ -> {
      case parse_value(tokens) {
        Error(e) -> Error(e)
        Ok(#(value, remaining)) -> {
          parse_array_items(remaining, [value, ..acc])
        }
      }
    }
  }
}

fn skip_comma_and_whitespace(tokens: List(Token)) -> List(Token) {
  case tokens {
    [tokenizer.Comma(_), ..rest] -> skip_whitespace_tokens(rest)
    [tokenizer.Newline(_), ..rest] -> skip_comma_and_whitespace(rest)
    [tokenizer.Whitespace(_, _), ..rest] -> skip_comma_and_whitespace(rest)
    _ -> tokens
  }
}

fn skip_whitespace_tokens(tokens: List(Token)) -> List(Token) {
  case tokens {
    [tokenizer.Whitespace(_, _), ..rest] -> skip_whitespace_tokens(rest)
    _ -> tokens
  }
}

// ── Date/Time Parsing ─────────────────────────────────────────

fn parse_datetime_value(value: String) -> Result(TomlValue, ParseError) {
  let has_t = string.contains(value, "T")
  let has_space = string.contains(value, " ")
  case has_t || has_space {
    True -> {
      let parts = case has_t {
        True -> string.split(value, "T")
        False -> string.split(value, " ")
      }
      case parts {
        [date_str, time_str] -> {
          case parse_date_string(date_str) {
            Error(e) -> Error(e)
            Ok(date) -> {
              case parse_time_string(time_str) {
                Error(e) -> Error(e)
                Ok(time) ->
                  Ok(
                    TomlDateTime(DateTimeC(date: date, time: time, offset: Utc)),
                  )
              }
            }
          }
        }
        _ -> Error(InvalidValue(line: 0))
      }
    }

    False -> {
      case string.contains(value, ":") {
        True ->
          case parse_time_string(value) {
            Ok(time) -> Ok(TomlTime(time))
            Error(e) -> Error(e)
          }

        False ->
          case parse_date_string(value) {
            Ok(date) -> Ok(TomlDate(date))
            Error(e) -> Error(e)
          }
      }
    }
  }
}

fn parse_date_string(s: String) -> Result(types.TomlDate, ParseError) {
  let parts = string.split(s, "-")
  case parts {
    [year_str, month_str, day_str] -> {
      case int.parse(year_str) {
        Error(_) -> Error(InvalidValue(line: 0))
        Ok(year) -> {
          case int.parse(month_str) {
            Error(_) -> Error(InvalidValue(line: 0))
            Ok(month) -> {
              case int.parse(day_str) {
                Error(_) -> Error(InvalidValue(line: 0))
                Ok(day) -> Ok(DateC(year: year, month: month, day: day))
              }
            }
          }
        }
      }
    }
    _ -> Error(InvalidValue(line: 0))
  }
}

fn parse_time_string(s: String) -> Result(types.TomlTime, ParseError) {
  let s = case string.ends_with(s, "Z") {
    True -> string.drop_end(s, 1)
    False -> s
  }
  let parts = string.split(s, ":")
  case parts {
    [hour_str, minute_str, rest] -> {
      case int.parse(hour_str) {
        Error(_) -> Error(InvalidValue(line: 0))
        Ok(hour) -> {
          case int.parse(minute_str) {
            Error(_) -> Error(InvalidValue(line: 0))
            Ok(minute) -> {
              case string.split(rest, ".") {
                [second_str] ->
                  case int.parse(second_str) {
                    Error(_) -> Error(InvalidValue(line: 0))
                    Ok(second) ->
                      Ok(TimeC(
                        hour: hour,
                        minute: minute,
                        second: second,
                        nanosecond: 0,
                      ))
                  }

                [second_str, ns_str] ->
                  case int.parse(second_str) {
                    Error(_) -> Error(InvalidValue(line: 0))
                    Ok(second) ->
                      case int.parse(string.pad_end(ns_str, 9, "0")) {
                        Error(_) -> Error(InvalidValue(line: 0))
                        Ok(ns) ->
                          Ok(TimeC(
                            hour: hour,
                            minute: minute,
                            second: second,
                            nanosecond: ns,
                          ))
                      }
                  }

                _ -> Error(InvalidValue(line: 0))
              }
            }
          }
        }
      }
    }
    _ -> Error(InvalidValue(line: 0))
  }
}

// ── Token Helpers ─────────────────────────────────────────────

fn token_line(token: Token) -> Int {
  case token {
    tokenizer.BareKey(line, _) -> line
    tokenizer.BareString(line, _) -> line
    tokenizer.LiteralString(line, _) -> line
    tokenizer.MultiLineString(line, _) -> line
    tokenizer.MultiLineLiteralString(line, _) -> line
    tokenizer.Integer(line, _) -> line
    tokenizer.Float(line, _) -> line
    tokenizer.Boolean(line, _) -> line
    tokenizer.DateTime(line, _) -> line
    tokenizer.Nan(line, _) -> line
    tokenizer.Infinity(line, _) -> line
    tokenizer.Comment(line, _) -> line
    tokenizer.Newline(line) -> line
    tokenizer.Whitespace(line, _) -> line
    tokenizer.LSquare(line) -> line
    tokenizer.RSquare(line) -> line
    tokenizer.DoubleLSquare(line) -> line
    tokenizer.DoubleRSquare(line) -> line
    tokenizer.LBrace(line) -> line
    tokenizer.RBrace(line) -> line
    tokenizer.Equals(line) -> line
    tokenizer.Comma(line) -> line
    tokenizer.Dot(line) -> line
  }
}

fn describe_token(token: Token) -> String {
  case token {
    tokenizer.LSquare(_) -> "["
    tokenizer.RSquare(_) -> "]"
    tokenizer.DoubleLSquare(_) -> "[["
    tokenizer.DoubleRSquare(_) -> "]]"
    tokenizer.LBrace(_) -> "{"
    tokenizer.RBrace(_) -> "}"
    tokenizer.Equals(_) -> "="
    tokenizer.Comma(_) -> ","
    tokenizer.Dot(_) -> "."
    tokenizer.BareKey(_, v) -> v
    tokenizer.BareString(_, v) -> "\"" <> v <> "\""
    tokenizer.LiteralString(_, v) -> "'" <> v <> "'"
    tokenizer.MultiLineString(_, v) -> "\"\"\"" <> v <> "\"\"\""
    tokenizer.MultiLineLiteralString(_, v) -> "'''" <> v <> "'''"
    tokenizer.Integer(_, v) -> int.to_string(v)
    tokenizer.Float(_, v) -> float_to_str(v)
    tokenizer.Boolean(_, True) -> "true"
    tokenizer.Boolean(_, False) -> "false"
    tokenizer.DateTime(_, v) -> v
    tokenizer.Nan(_, True) -> "nan"
    tokenizer.Nan(_, False) -> "-nan"
    tokenizer.Infinity(_, True) -> "inf"
    tokenizer.Infinity(_, False) -> "-inf"
    tokenizer.Comment(_, v) -> v
    tokenizer.Newline(_) -> "\\n"
    tokenizer.Whitespace(_, v) -> v
  }
}

@external(erlang, "float_to_str", "convert")
fn float_to_str(a: Float) -> String
