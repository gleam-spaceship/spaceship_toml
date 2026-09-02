// Float to string conversion for TOML serialization

/**
 * Convert a float to its TOML string representation.
 * @param {number} value - The float value
 * @returns {string} TOML-compatible string representation
 */
export function convert(value) {
  // Handle special cases
  if (value === Infinity) return "inf";
  if (value === -Infinity) return "-inf";
  if (Number.isNaN(value)) return "nan";
  
  // Use the same format as Erlang's io_lib:format("~p", [F])
  // This produces a string without scientific notation for most values
  const str = String(value);
  
  // Ensure we have a decimal point for TOML compatibility
  if (!str.includes('.') && !str.includes('e') && !str.includes('E')) {
    return str + '.0';
  }
  
  return str;
}
