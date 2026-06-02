# Generates a structured, step-annotated AI explanation for an AccountEntry's
# formula breakdown. Returns a Hash with :summary, :steps (array of
# {expression, value, meaning}), and :conclusion. Called from AccountEntryExplainJob.
class AccountEntryExplainerService
  def self.explain(account_entry)
    new(account_entry).explain
  end

  def initialize(account_entry)
    @account_entry = account_entry
  end

  # Returns a Hash: { "summary" => "...", "steps" => [...], "conclusion" => "..." }
  # or nil if the LLM response can't be parsed.
  def explain
    chat = LlmService.ruby_llm_chat(entity: @account_entry.entity)
    raw  = chat.ask(build_prompt).content.strip

    # Strip markdown fences the LLM may wrap around JSON
    json_str = raw.gsub(/\A```(?:json)?\s*/, "").gsub(/\s*```\z/, "").strip
    JSON.parse(json_str)
  rescue JSON::ParserError => e
    Rails.logger.error "AccountEntryExplainerService: JSON parse failed — #{e.message}\nRaw: #{raw}"
    nil
  end

  private

  def build_prompt
    formula      = extract_formula
    description  = extract_description
    breakdown    = extract_breakdown

    variables    = breakdown.select { |k, _| k.start_with?('@') && !k.include?(' ') }
    other        = breakdown.reject { |k, _| k.start_with?('@') && !k.include?(' ') }
    result_row   = other.max_by { |k, _| k.length }
    steps        = other.reject { |k, _| k == result_row&.first }
                        .sort_by { |k, _| k.length }  # simplest → complex
    result_val   = result_row&.last

    var_lines    = variables.map { |k, v| "  #{k} = #{v}" }.join("\n")

    # Build the numbered step list we send to the LLM; it must return them in
    # the same order so we can match meanings back by index.
    step_lines   = steps.each_with_index.map { |(k, v), i|
      "  #{i + 1}. expression: #{k.inspect}\n     value: #{v}"
    }.join("\n\n")

    currency = @account_entry.fund.currency.presence || "USD"

    <<~PROMPT
      You are an expert fund accountant explaining a calculated account entry to a finance team.

      Entry name:      #{@account_entry.name}
      Entry type:      #{@account_entry.entry_type}
      Reporting period: #{@account_entry.period}
      Reporting date:  #{@account_entry.reporting_date}
      Fund currency:   #{currency}

      IMPORTANT: All monetary amounts in this entry are denominated in #{currency}, stored as cents.
      When referencing amounts, always use #{currency} — never assume USD unless that is the fund currency.

      --- Formula ---
      #{formula.presence || '(not available)'}

      #{"--- Description ---\n#{description}\n" if description.present?}
      --- Input Variables ---
      #{var_lines.presence || '  (none)'}

      --- Calculation Steps (simplest to most complex) ---
      #{step_lines.presence || '  (none)'}

      --- Final Result ---
      #{result_val.presence || '(not available)'}

      ---
      Return ONLY a JSON object — no markdown, no prose outside the JSON.

      The JSON must have exactly these keys:

      {
        "summary": "<3 sentences that orient the reader before they look at the steps: (1) what this entry calculates and why it exists as a distinct line item, (2) which key input variables drive the calculation and what they represent in fund terms, (3) the high-level approach the formula takes — e.g. 'it annualises the fee rate, scales it to the exact number of days in the period, then applies it to the committed capital base'>",
        "steps": [
          {
            "expression": "<exact expression text from step N above>",
            "value": "<value>",
            "meaning": "<2-3 sentences: (1) what this sub-expression computes in plain business terms, referencing the actual value, (2) why this intermediate result is needed in the overall calculation — connect it explicitly to the step(s) it feeds into, (3) if the value is surprising or requires context, explain it — e.g. why 89/1 represents a date difference in days>"
          },
          ...one object per step, in the same order as above...
        ],
        "conclusion": "<3 sentences that close the loop: (1) restate what the final computed value represents — include units, e.g. cents vs dollars, percentage vs absolute amount, (2) explain how to interpret the magnitude — is this the expected order of magnitude given the inputs? what does it mean for the LP or the fund? (3) describe what happens with this number next — e.g. it will be debited from the investor account, it feeds into the NAV calculation, it is compared against a hurdle rate>"
      }

      Guidelines for all text:
      - Audience: fund managers and finance ops — financially literate but not Ruby developers.
      - Always reference actual computed values (e.g. "the 90-day period", "the 2.0% annual rate").
      - Never use technical terms: eval, method, object, Ruby syntax, or implementation details.
      - Step meanings must build on each other — if step 4 uses the result of step 3, say so explicitly.
      - Be specific and concrete; avoid vague phrases like "this is used in the calculation".
    PROMPT
  end

  def extract_formula
    @account_entry.explanation.find { |e| parse_json(e).nil? && e.present? }
  end

  def extract_description
    non_json = @account_entry.explanation.select { |e| parse_json(e).nil? && e.present? }
    non_json[1]
  end

  def extract_breakdown
    json_entry = @account_entry.explanation.find { |e| parse_json(e).is_a?(Hash) }
    json_entry ? parse_json(json_entry) : {}
  end

  def parse_json(obj)
    JSON.parse(obj)
  rescue JSON::ParserError, TypeError
    nil
  end
end
