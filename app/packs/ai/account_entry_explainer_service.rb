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

    variables, other = breakdown.partition { |k, _| k.start_with?('@') && k.exclude?(' ') }
    # Last entry is the final result — post-order traversal inserts the outermost
    # expression last. max_by-length broke when addend expansion added long
    # intermediate keys (e.g. AccountEntry.total_amount(...)) longer than the result.
    result_row   = other.to_a.last
    steps_raw    = other.to_a[0..-2]
    steps        = steps_raw
    result_val   = result_row&.last

    var_lines    = variables.map { |k, v| "  #{k} = #{truncate_for_llm(v)}" }.join("\n")

    # Build the numbered step list we send to the LLM; it must return them in
    # the same order so we can match meanings back by index.
    step_lines   = steps.each_with_index.map do |(k, v), i|
      "  #{i + 1}. expression: #{k.inspect}\n     value: #{truncate_for_llm(v)}"
    end.join("\n\n")

    currency = @account_entry.fund.currency.presence || "USD"

    <<~PROMPT
      You are an expert fund accountant explaining a calculated account entry to a finance team.

      Entry name:      #{@account_entry.name}
      Entry type:      #{@account_entry.entry_type}
      Reporting period: #{@account_entry.period}
      Reporting date:  #{@account_entry.reporting_date}
      Fund currency:   #{currency}

      IMPORTANT: Monetary amounts in this entry are stored as integer values in the database.
      When referencing any monetary amount, always show both the raw value AND the #{currency} equivalent
      (e.g. "1,000,000,000 (#{currency} 10,000,000)") by dividing the raw value by 100 for the currency amount.
      Never use the words cents, paise, or any minor-unit name — just show the number and its #{currency} equivalent.

      --- Formula ---
      #{formula.presence || '(not available)'}

      #{"--- Description ---\n#{description}\n" if description.present?}
      --- Input Variables ---
      #{var_lines.presence || '  (none)'}

      --- Calculation Steps (simplest to most complex) ---
      #{step_lines.presence || '  (none)'}

      --- Final Result ---
      #{result_val.presence || '(not available)'}

      --- Authoritative Stored Amount ---
      The actual amount recorded in the database for this account entry is
      #{@account_entry.amount_cents} (#{currency} #{format('%.10g', @account_entry.amount_cents.to_f / 100)}).
      Your conclusion MUST reference this exact stored amount, not any value derived from the steps above.

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
        "conclusion": "<2 sentences strictly derived from the formula above: (1) restate what the final computed value represents — show both the raw value and its #{currency} equivalent (raw ÷ 100), never using the words cents or paise, (2) explain what the magnitude means in terms of the inputs actually visible above — do NOT infer or speculate about downstream accounting treatment, journal entries, NAV impact, or anything not explicitly present in the formula and steps>"
      }

      Guidelines for all text:
      - Audience: fund managers and finance ops — financially literate but not Ruby developers.
      - Always reference actual computed values (e.g. "the 90-day period", "the 2.0% annual rate").
      - Never use technical terms: eval, method, object, Ruby syntax, or implementation details.
      - Step meanings must build on each other — if step 4 uses the result of step 3, say so explicitly.
      - Be specific and concrete; avoid vague phrases like "this is used in the calculation".
      - STRICT: only explain what is explicitly present in the formula and steps above. Do NOT infer downstream
        accounting effects, journal entries, NAV impact, capital account treatment, or any other consequences
        that are not directly derivable from the data provided.
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

  # Truncates a value string that would otherwise blow up the LLM prompt.
  # Array summaries like "200 portfolio companies: [1, 2, 3, ...]" are the main
  # offender — the count and label are all the LLM needs; the full ID list adds
  # token cost without analytical value.
  def truncate_for_llm(value, max_chars: 150)
    str = value.to_s
    return str if str.length <= max_chars

    "#{str[0, max_chars]}... [list truncated]"
  end

  def parse_json(obj)
    JSON.parse(obj)
  rescue JSON::ParserError, TypeError
    nil
  end
end
