# The AI draft's prompt, response schema and parser (card ② of the design).
#   document_text — the uploaded statement as text (PDF via pdftotext -layout, Excel via Roo)
#   build         — the prompt: rules, enums, the fund's entry list, existing account names, the text
#   parse         — JSON → validated proposal: unknown enums dropped, rules naming an entry the fund
#                   doesn't have moved to "dropped" (E27), a pair claimed twice kept once
# Worked examples H11, E27, X18 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementMappingPrompt
  class Unreadable < StandardError; end

  MAX_TEXT = 60_000
  MAX_ENTRIES = 400
  ROLES = %w[account subtotal net_result opening closing].freeze
  STATEMENT_KINDS = FinancialStatementDefinition::KINDS

  # X18: no text (a scanned PDF) is a clear failure, not an empty draft
  def self.document_text(suggestion)
    text = +""
    # Downloaded to a tempfile, read by type
    suggestion.file.download do |file|
      text = case suggestion.file.extension.to_s.downcase
             when "pdf" then pdf_text(file.path)
             else excel_text(file.path)
             end
    end
    # Clean encoding and trailing spaces, then refuse an (almost) empty result
    text = text.to_s.encode("UTF-8", invalid: :replace, undef: :replace).gsub(/[ \t]+$/, "").strip
    raise Unreadable, "We couldn't read any text from this file. Upload a text PDF or the Excel version." if text.gsub(/\s/, "").length < 20

    text[0, MAX_TEXT]
  end

  def self.pdf_text(path)
    out = "#{path}.txt"
    # Array form: no shell. -layout keeps "Professional fees ..... 88,400 ..... 71,000" on one line
    raise Unreadable, "PDF text extraction is not available on this server." if system("pdftotext", "-layout", path, out).nil?

    File.exist?(out) ? File.read(out) : ""
  ensure
    FileUtils.rm_f(out) if out
  end

  def self.excel_text(path)
    spreadsheet = Roo::Spreadsheet.open(path)
    spreadsheet.sheets.map { |name| "--- Sheet: #{name} ---\n#{spreadsheet.sheet(name).to_csv}" }.join("\n")
  end

  # entries: [{ "entry_type", "name", "balance", "period" }] in cents
  def self.build(text:, entries:, existing_accounts:, as_at:, period_start:)
    # One line per entry, amounts in currency units (the prompt never sees cents)
    entry_lines = entries.first(MAX_ENTRIES).map do |e|
      "#{e['entry_type']} | #{e['name']} | #{(e['balance'].to_d / 100).round(2).to_s('F')} | #{(e['period'].to_d / 100).round(2).to_s('F')}"
    end
    <<~PROMPT
      You map an investment fund's account entries to the lines of its printed financial statements.

      The statements below are a sample of this fund's statements, possibly for another period than CapHive's entries, so the amounts
      need not agree. Map by MEANING (what each line represents and which entries belong to it); amounts are only a hint.

      Return ONLY a JSON object, no prose, no code fences, with this shape:
      {
        "statements": [{"kind": one of #{STATEMENT_KINDS.to_json}, "title": "title as printed", "column_style": "at_date" | "for_period"}],
        "lines": [{"key": "l1", "statement_title": "...", "section": "heading the line sits under", "label": "line label as printed",
                   "role": one of #{ROLES.to_json},
                   "account_type": one of #{FinancialStatementAccount::ACCOUNT_TYPES.to_json},
                   "behaviour": "balance" | "movement", "flip_sign": false, "printed": 12345.67, "subtotal_of": ["l2", "l3"]}],
        "rules": [{"entry_type": "...", "name": "... or empty string for every name of that type", "line": "l1"}],
        "excluded": [{"entry_type": "...", "name": "... or empty string"}]
      }

      Rules:
      - kind: balance_sheet (assets, liabilities, partners' capital / net assets), profit_and_loss (operations, income statement),
        changes_in_capital (changes in partners' capital / net assets), schedule (anything else).
      - Use ONLY the (entry type, name) pairs in the ENTRY LIST. Never invent or alter a name.
      - Each pair feeds at most one line. Put working figures that are not statement lines (per-investor allocations, NAV, units, percentages) under "excluded".
      - Prefer one rule with name "" when every name of that entry type belongs to the same line, so names added later are caught.
      - Map entries DIRECTLY to the lines that are printed. Never invent sub-lines that the statements don't print
        (e.g. if "Professional fees" is printed, map Audit Fees and Legal Fees to it; don't add "Audit Fees" lines).
      - role "subtotal" for totals ("Total expenses", "Net assets", "Net investment loss"): list the keys of the lines they add up in
        subtotal_of; give subtotals no rules.
      - role "net_result" ONLY for the final profit and loss result ("Net increase / decrease in net assets from operations") and, on the
        Balance Sheet, for the accumulated result / retained earnings line. Intermediate results such as "Net investment loss" are subtotals.
      - role "opening" / "closing" for opening and closing partners' capital.
      - A line that appears on more than one statement (e.g. contributions on the Balance Sheet and on the Changes statement) must use
        the SAME label on each; its entries' rule points at one of them.
      - behaviour: "balance" for assets, liabilities and partners' capital; "movement" for income, expenses, gains and losses.
      - flip_sign true when the entries are stored with the opposite sign to the account's natural sign
        (costs and amounts owed are positive; a distribution is a negative capital amount).
      - printed: the current-period figure as a plain number (not comparatives); brackets mean negative; null if none.
      - If a line means the same as one of the EXISTING ACCOUNTS, use that exact name as its label.

      ENTRY LIST (entry type | name | balance at #{as_at.iso8601} | movement since #{period_start.iso8601}):
      #{entry_lines.join("\n")}

      EXISTING ACCOUNTS:
      #{existing_accounts.presence&.join("\n") || '(none)'}

      STATEMENTS:
      #{text}
    PROMPT
  end

  # @return [Hash] the validated proposal (see FinancialStatementMappingSuggestion)
  def self.parse(raw, entries:)
    json = LlmJson.parse(raw)
    raise Unreadable, "The AI's answer could not be read. Try again." unless json.is_a?(Hash) && json["lines"].is_a?(Array)

    # What the fund really has: exact pairs, and entry types for any-name rules
    known = entries.to_set { |e| [e["entry_type"], e["name"]] }
    known_types = entries.to_set { |e| e["entry_type"] }
    dropped = []

    # Statements: only known kinds; a missing column style follows the kind
    statements = Array(json["statements"]).select { |s| s.is_a?(Hash) && STATEMENT_KINDS.include?(s["kind"]) }.map do |s|
      { "kind" => s["kind"], "title" => s["title"].to_s.strip[0, 100].presence || s["kind"].humanize,
        "column_style" => if FinancialStatementDefinition::COLUMN_STYLES.include?(s["column_style"])
                            s["column_style"]
                          else
                            (s["kind"] == "balance_sheet" ? "at_date" : "for_period")
                          end }
    end

    # Lines: role inferred when missing; an account line needs a valid type
    lines = Array(json["lines"]).filter_map do |l|
      next unless l.is_a?(Hash) && l["key"].present? && l["label"].present?

      role = if ROLES.include?(l["role"])
               l["role"]
             else
               (Array(l["subtotal_of"]).any? ? "subtotal" : "account")
             end
      if role == "account" && FinancialStatementAccount::ACCOUNT_TYPES.exclude?(l["account_type"])
        dropped << { "entry_type" => nil, "name" => l["label"].to_s, "reason" => "line has no valid account type" }
        next
      end
      { "key" => l["key"].to_s, "statement_title" => l["statement_title"].to_s.strip, "section" => l["section"].to_s.strip[0, 150],
        "label" => l["label"].to_s.strip.squeeze(" ")[0, 100], "role" => role, "account_type" => l["account_type"],
        "behaviour" => FinancialStatementAccount::BEHAVIOURS.include?(l["behaviour"]) ? l["behaviour"] : FinancialStatementAccount.default_behaviour_for(l["account_type"].to_s),
        "flip_sign" => l["flip_sign"] == true, "printed" => numeric(l["printed"]), "subtotal_of" => Array(l["subtotal_of"]).map(&:to_s) }
    end
    line_keys = lines.select { |l| l["role"] == "account" }.to_set { |l| l["key"] }

    # A pair may feed only one line; the first claim wins
    claimed = Set.new
    rules = Array(json["rules"]).filter_map do |r|
      next unless r.is_a?(Hash)

      entry_type = r["entry_type"].to_s.strip
      name = r["name"].to_s.strip
      # E27: the AI can't invent entries — a rule must name a pair (or an entry type) the fund has
      unless name.empty? ? known_types.include?(entry_type) : known.include?([entry_type, name])
        dropped << { "entry_type" => entry_type, "name" => name, "reason" => "not an entry of this fund" }
        next
      end
      next dropped << { "entry_type" => entry_type, "name" => name, "reason" => "points at a line that isn't an account" } unless line_keys.include?(r["line"].to_s)
      next dropped << { "entry_type" => entry_type, "name" => name, "reason" => "already feeds another line" } if claimed.include?([entry_type, name])

      claimed << [entry_type, name]
      { "entry_type" => entry_type, "name" => name, "line" => r["line"].to_s }
    end

    excluded = Array(json["excluded"]).filter_map do |r|
      next unless r.is_a?(Hash)

      pair = [r["entry_type"].to_s.strip, r["name"].to_s.strip]
      next unless pair[1].empty? ? known_types.include?(pair[0]) : known.include?(pair)
      next if claimed.include?(pair)

      claimed << pair
      { "entry_type" => pair[0], "name" => pair[1] }
    end

    { "statements" => statements, "lines" => lines, "rules" => rules, "excluded" => excluded, "dropped" => dropped }
  end

  def self.numeric(value)
    return nil if value.nil? || value.to_s.strip.empty?
    return value.to_d if value.is_a?(Numeric)

    text = value.to_s.strip
    # "(1,150)" -> -1150
    negative = text.start_with?("(") && text.end_with?(")")
    number = text.delete("(),").to_d
    negative ? -number : number
  rescue ArgumentError
    nil
  end

  # Thin wrapper over the app's LlmResponseParser (handles String / Hash / RubyLLM::Message, code fences)
  class LlmJson
    extend LlmResponseParser

    def self.parse(raw)
      parse_llm_json(raw.respond_to?(:content) ? raw.content : raw)
    end
  end
end
