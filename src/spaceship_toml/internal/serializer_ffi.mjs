// Serializer FFI helpers for JavaScript

/**
 * Convert an integer to string.
 * @param {number} value - Integer value
 * @returns {string} String representation
 */
export function intToString(value) {
  return String(value);
}

/**
 * Convert a float to string.
 * @param {number} value - Float value
 * @returns {string} String representation
 */
export function floatToString(value) {
  // Handle special cases
  if (value === Infinity) return "inf";
  if (value === -Infinity) return "-inf";
  if (Number.isNaN(value)) return "nan";
  
  const str = String(value);
  
  // Ensure we have a decimal point for TOML compatibility
  if (!str.includes('.') && !str.includes('e') && !str.includes('E')) {
    return str + '.0';
  }
  
  return str;
}
