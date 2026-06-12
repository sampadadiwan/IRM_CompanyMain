class ReportBuilderFormulaService
  def initialize(formulas)
    @formulas = Array(formulas)
    @calculator = Dentaku::Calculator.new
  end

  # Evaluates all formulas for a single row.
  # @param row [Hash] { "column_key" => value }
  # @return [Hash] Updated row with formula results
  def evaluate(row)
    return row if @formulas.empty?

    # Map row keys to safe variable names for Dentaku (e.g., "a.b" -> "a__b")
    # This avoids issues with dots in variable names.
    data = row.each_with_object({}) do |(k, v), h|
      safe_key = k.to_s.split(";").first.strip.gsub(".", "__")
      h[safe_key] = v
    end

    @formulas.each do |formula|
      key   = formula["key"]
      expr  = formula["expression"].to_s

      # Replace [column.key] with safe__key in the expression
      safe_expr = expr.gsub(/\[([^\]]+)\]/) do
        ::Regexp.last_match(1).split(";").first.strip.gsub(".", "__")
      end

      begin
        result = @calculator.evaluate(safe_expr, data)
        row[key] = result

        # Update data hash so subsequent formulas can use this result
        data[key.to_s.gsub(".", "__")] = result
      rescue StandardError => e
        Rails.logger.warn "[ReportBuilderFormulaService] Error evaluating formula '#{key}': #{e.message}"
        row[key] = nil
      end
    end

    row
  end

  # Validates a formula expression against a sample row.
  def self.validate(expression, sample_row = {})
    calculator = Dentaku::Calculator.new
    data = sample_row.transform_keys { |k| k.to_s.gsub(".", "__") }
    safe_expr = expression.to_s.gsub(/\[([^\]]+)\]/) { ::Regexp.last_match(1).gsub(".", "__") }

    begin
      calculator.evaluate!(safe_expr, data)
      true
    rescue StandardError => e
      e.message
    end
  end
end
