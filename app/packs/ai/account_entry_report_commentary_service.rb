# Generates AI commentary for one section of the Account Entries Period Report.
# Takes already-computed AccountEntryReport data as input - never re-derives
# numbers itself, only narrates and flags anomalies against trailing history.
# Returns a Hash with "narrative" and "anomalies" (array of
# {metric, current_value, trailing_average, deviation_pct, note}), or nil if the
# LLM response can't be parsed. Called from AccountEntryReportCommentaryJob.
class AccountEntryReportCommentaryService
  SECTION_LABELS = {
    "summary_kpis" => "Summary KPIs",
    "breakdown" => "Breakdown by Entry Name",
    "trend" => "Trailing-Period Trend"
  }.freeze

  def self.generate(report:, section_key:, fund:, start_date:, end_date:, capital_commitment: nil)
    new(report:, section_key:, fund:, start_date:, end_date:, capital_commitment:).generate
  end

  def initialize(report:, section_key:, fund:, start_date:, end_date:, capital_commitment: nil)
    @report = report
    @section_key = section_key
    @fund = fund
    @capital_commitment = capital_commitment
    @start_date = start_date
    @end_date = end_date
  end

  def generate
    chat = LlmService.ruby_llm_chat(entity: @fund.entity)
    raw  = chat.ask(build_prompt).content.strip

    json_str = raw.gsub(/\A```(?:json)?\s*/, "").gsub(/\s*```\z/, "").strip
    JSON.parse(json_str)
  rescue JSON::ParserError => e
    Rails.logger.error "AccountEntryReportCommentaryService: JSON parse failed — #{e.message}\nRaw: #{raw}"
    nil
  end

  private

  def currency
    @fund.currency
  end

  def scope_description
    @capital_commitment ? "Folio #{@capital_commitment.folio_id} (#{@capital_commitment.investor_name}) in fund #{@fund.name}" : "Fund #{@fund.name} (all folios)"
  end

  def format_money(cents)
    "#{cents} (#{currency} #{format('%.2f', cents.to_f / 100)})"
  end

  def trend_lines
    @report.trailing_trend.map do |name, periods|
      values = periods.map { |period, cents| "#{period}: #{format_money(cents)}" }.join(", ")
      "  #{name} — #{values}"
    end.join("\n")
  end

  def build_prompt
    <<~PROMPT
      You are an expert fund accountant writing commentary for a fund manager reviewing
      an Account Entries Period Report.

      Scope: #{scope_description}
      Reporting period: #{@start_date} to #{@end_date}
      Fund currency: #{currency}
      Section: #{SECTION_LABELS.fetch(@section_key)}

      IMPORTANT: Monetary amounts are stored as integer cents. Always show both the raw
      value AND the #{currency} equivalent, dividing by 100. Never use the words cents or paise.

      --- Section Data ---
      #{section_data_block}

      --- Trailing-Period History (for comparison only - not the current period) ---
      #{trend_lines.presence || '  (not enough history)'}

      ---
      Return ONLY a JSON object — no markdown, no prose outside the JSON.

      {
        "narrative": "<2-4 sentences describing what this section's numbers show, in plain
          business language a fund manager would use>",
        "anomalies": [
          {
            "metric": "<entry name or KPI label>",
            "current_value": "<value from Section Data, with currency equivalent>",
            "trailing_average": "<trailing-period average for the same metric, with currency equivalent>",
            "deviation_pct": <number, percentage deviation of current_value from trailing_average>,
            "note": "<1 sentence on why this deviation is worth flagging>"
          }
          // ...one entry per metric that deviates meaningfully from its trailing average.
          // Omit metrics with no meaningful deviation. Return an empty array if none.
        ]
      }

      Guidelines:
      - Audience: fund managers and finance ops — financially literate but not engineers.
      - STRICT: only describe what is explicitly present in the Section Data and Trailing-Period
        History above. Do not infer accounting treatment, NAV impact, or anything not shown.
      - Only flag an anomaly when the trailing history above actually supports a comparison —
        do not flag deviations against periods with zero data.
    PROMPT
  end

  def section_data_block
    case @section_key
    when "summary_kpis"
      kpis = @report.summary_kpis
      <<~DATA
        Total amount: #{format_money(kpis[:total_amount_cents])}
        Entry count: #{kpis[:entry_count]}
        Distinct folios touched: #{kpis[:distinct_folio_count]}
        Distinct entry names: #{kpis[:distinct_entry_names]}
      DATA
    when "breakdown"
      @report.breakdown_by_name.map { |name, cents| "  #{name}: #{format_money(cents)}" }.join("\n")
    when "trend"
      "(see Trailing-Period History below — this section's data IS that history)"
    else
      raise ArgumentError, "Unknown section_key: #{@section_key}"
    end
  end
end
