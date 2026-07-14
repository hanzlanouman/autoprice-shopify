# Single entry point for turning inbound values (Shopify strings, API params,
# Gemini output) into BigDecimal. Money is BigDecimal in Ruby, decimal in the
# DB, and a string in JSON — never a float.
module Money
  module_function

  # Returns a BigDecimal, or nil if the value is blank/uncoercible.
  def parse(value)
    return nil if value.nil?
    if value.is_a?(BigDecimal)
      return value if value.finite?
      return nil
    end
    if value.is_a?(Numeric)
      parsed = BigDecimal(value.to_s)
      return parsed if parsed.finite?
      return nil
    end

    str = value.to_s.strip
    return nil if str.empty?

    parsed = BigDecimal(str)
    parsed if parsed.finite?
  rescue ArgumentError
    nil
  end

  # Rounds to 2 decimal places (half-up), the currency precision we store.
  def round(value)
    parse(value)&.round(2, BigDecimal::ROUND_HALF_UP)
  end

  # Canonical string form for JSON/storage: always 2 decimals ("10.00"),
  # never engineering notation. Returns nil for blank/uncoercible input.
  def format(value)
    bd = round(value)
    return nil if bd.nil?

    Kernel.format("%.2f", bd)
  end
end
