# Turns a question (and, when refining, the current report and an instruction)
# into a Report Builder report spec with the company's own AI model. Two short
# asks keep the prompt small:
#
#   1. REPORT TABLE — the question and the company's report tables → the table
#   2. REPORT SPEC  — the question, that table's columns and related data, two
#                     starter templates as examples (and the current spec +
#                     instruction when refining) → the spec, questions,
#                     assumptions, what it couldn't do and a name
#
# No row data, fund names, investor names or amounts are ever sent. Each ask is
# tried once more after an error or an answer that isn't JSON; then Failed.
# The answer is NOT trusted: ReportSpecPruner checks every part afterwards.
#
# Worked examples H2, H4, E1, E3, E5, X1, X2, X4 — openspec/changes/report-builder-assistant/business-rules.md
class ReportDraftGenerator
  class Failed < StandardError; end

  FAILED_MESSAGE = "Couldn't draft this right now — try again in a moment".freeze

  # Business words → tables, so "each folio" isn't drafted as one row per fund
  BUSINESS_WORDS = <<~WORDS.freeze
    Business words: an LP, investor or stakeholder is an Investor; a folio or a commitment is a
    CapitalCommitment (one investor in one fund); a close (First Close, Second Close) is the
    commitment's fund_close; a call is a CapitalCall and each investor's share of it a
    CapitalRemittance; a distribution to an investor is a CapitalDistributionPayment; an
    investment is a PortfolioInvestment; a company's KPIs are Kpi rows of a KpiReport.
  WORDS

  # What the formula engine (Dentaku) evaluates; it has no date functions
  FORMULA_FUNCTIONS = "IF, AND, OR, NOT, ROUND, ROUNDUP, ROUNDDOWN, MIN, MAX, SUM, AVG, ABS".freeze
  QUESTION_KINDS = %w[pick_fund choice text].freeze

  # X4 — a model for the company, or the platform's default
  def self.available?(entity)
    entity&.entity_setting&.default_llm_model.present? || ENV["DEFAULT_MODEL"].present?
  end

  def initialize(entity:, question:, spec: nil, instruction: nil)
    @entity      = entity
    @question    = question.to_s
    @spec        = spec
    @instruction = instruction
  end

  # { "spec" =>, "questions" =>, "assumptions" =>, "cannot" =>, "name" => }
  def call
    # Step 1 only for a new draft; a refinement keeps its table
    root, cannot = @spec.present? ? [@spec["root_model"], []] : pick_table
    return { "spec" => {}, "questions" => [], "assumptions" => [], "cannot" => cannot, "name" => nil } if root.blank?
    # E4 — a table outside the company's reports: the pruner says so; no second ask
    return { "spec" => { "root_model" => root.to_s }, "questions" => [], "assumptions" => [], "cannot" => cannot, "name" => nil } if tables.none? { |klass| klass.name == root.to_s }

    answer = ask_json(spec_prompt(root))
    normalise(answer, root, cannot)
  end

  private

  def chat
    @chat ||= LlmService.ruby_llm_chat(entity: @entity)
  end

  # Step 1: which report table (from the company's tables only)
  def pick_table
    answer = ask_json(table_prompt)
    root = answer["root_model"].to_s
    [root.presence, Array(answer["cannot"]).map { |c| cannot_text(c) }]
  end

  def tables
    ReportBuilderModelDiscovery.roots.select { |klass| ReportBuilderModelDiscovery.pack_enabled_for?(klass, @entity) }
  end

  # A report has ONE table for its rows, plus related data pulled in from other
  # tables (totalled per row: Sum, Count, Latest …). The first version listed only
  # table names, so the AI refused questions that span tables ("investors, their
  # commitments and their units") as needing several tables.
  def table_prompt
    <<~PROMPT
      REPORT TABLE
      You choose the table a report's rows come from. A report has ONE row table and can
      also pull in related data from other tables — for example, investor rows can show each
      investor's capital commitments, calls and fund units as totals (sum, count, latest …).
      So a question that mentions several kinds of data is still ONE report: pick the table
      whose rows the answer lists, and the rest comes in as related data.

      #{BUSINESS_WORDS}

      Answer with ONLY a JSON object:
      {"root_model": "<one model name from the list>", "cannot": ["<one short sentence per part of the question no table covers>"]}
      Always pick the closest table. Leave root_model empty only when nothing in the list relates to the question.

      Tables — model: what each row is; related data it can pull in:
      #{tables.map { |klass| "#{klass.name}: one row per #{ReportBuilder::Wizard.model_label(klass.name).downcase}; related: #{related_names(klass)}" }.join("\n")}

      Question: #{@question}
    PROMPT
  end

  # "capital commitments, capital calls, fund units" — names only, for step 1
  def related_names(klass)
    names = ReportBuilderModelDiscovery.associations_for(klass, entity: @entity).map { |a| a[:name].to_s.humanize.downcase }
    names.presence ? names.first(12).join(", ") : "none"
  end

  # Step 2: the spec, from one table's catalog
  def spec_prompt(root)
    klass = tables.find { |k| k.name == root.to_s }
    <<~PROMPT
      REPORT SPEC
      You write a Report Builder report spec for the question below. Answer with ONLY a JSON object:
      {"spec": {...}, "questions": [{"kind": "pick_fund|choice|text", "text": "...", "options": ["..."]}],
       "assumptions": ["..."], "cannot": ["<what you left out and why, with a suggestion if any>"], "name": "<short report name>"}

      Spec format:
      {"root_model": "#{root}",
       "columns": [{"key": "<column key>", "label": "<optional>", "total": "sum|count|avg|min|max"} | {"formula": "<formula key>"}],
       "joins": [{"relation": "<related data>", "child_filters": {"<field>_<op>": "<value>"},
                  "pivot": {"group_bys": ["<related column>"], "value_col": "<related column>", "aggregate": "sum|count|latest"}}],
       "root_filters": {"<field>_<op>": "<value>"},
       "formulas": [{"key": "<key>", "label": "<label>", "expression": "[<column key>] - [<column key>]"}],
       "sort": {"key": "<column or formula key>", "dir": "asc|desc"}}
      Rules:
      - Use only the column keys and related data listed below. A related column's key is "<relation>.<column>".
      - A total goes ONLY on columns of related data with many rows per row (sum for amounts, count for ids, max or latest for dates). The row table's own columns, and related data with one row per row (e.g. fund), never have a total.
      - "One column per X" is a pivot: add "pivot" to that related data's join and a {"pivot": "<relation>"} column.
      - Formulas only reference column keys that are in "columns"; add a {"formula": key} column to show one. Functions: #{FORMULA_FUNCTIONS} and + - * /. There are no date functions — use a filter with a fixed date instead.
      - Operators: eq, not_eq, cont, in, gteq, lteq, null, not_null.
      - Never filter on a fund: if the question needs one fund, add a question {"kind": "pick_fund", "text": "Which fund?"}.
      - Turn relative dates ("last quarter") into fixed dates and say so in assumptions. Today is #{Time.zone.today.iso8601}.
      - Put in cannot only what the question asked for and you left out — one short sentence each, with a suggestion if there is one. No caveats or explanations. Never invent columns.
      #{BUSINESS_WORDS}

      Examples:
      #{examples_for(root)}

      Table #{root} (#{ReportBuilder::Wizard.model_label(root)}) columns — key | label | type:
      #{own_columns(klass)}

      Related data — relation (one|many per row): column keys:
      #{related_data(klass)}
      #{refinement_text}
      Question: #{@question}
    PROMPT
  end

  def refinement_text
    return "" if @spec.blank?

    "\nCurrent report spec (keep everything the instruction doesn't change):\n#{@spec.to_json}\nInstruction: #{@instruction}\n"
  end

  def own_columns(klass)
    config = ReportBuilderConfig.new("root_model" => klass.name)
    ReportBuilderColumnCatalog.columns_for(klass).map do |col|
      key = col[:key].to_s.split(";").first.strip
      "#{key} | #{col[:label]} | #{config.column_type.base_type(key)}"
    end.join("\n")
  end

  def related_data(klass)
    ReportBuilderModelDiscovery.associations_for(klass, entity: @entity).filter_map do |assoc|
      relation = assoc[:name]
      config = ReportBuilderConfig.new("root_model" => klass.name, "joins" => [{ "relation" => relation }])
      strategy = config.column_type.strategy_for(relation)
      next unless strategy

      related = ReportBuilderColumnCatalog.related_class(klass, relation)
      keys = ReportBuilderColumnCatalog.related_columns_for(related).map { |c| c[:key].to_s.split(";").first.strip }
      "#{relation} (#{strategy == :grouped ? 'many' : 'one'}): #{keys.join(', ')}"
    end.join("\n")
  end

  # Two starter templates as worked examples, of this table when there are any
  def examples_for(root)
    templates = ReportBuilderTemplates.all.values
    chosen = templates.select { |t| t.dig("spec", "root_model") == root.to_s }.first(2)
    chosen = templates.first(2) if chosen.empty?
    chosen.map { |t| "Question: #{t['question']}\nSpec: #{t['spec'].to_json}" }.join("\n\n")
  end

  # One ask, tried once more on an error or an answer that isn't a JSON object (X1, X2)
  def ask_json(prompt)
    2.times do |attempt|
      text = reply_text(attempt.zero? ? chat.ask(prompt) : chat.ask("#{prompt}\n\nAnswer with the JSON object only."))
      parsed = parse(text)
      return parsed if parsed
    rescue StandardError => e
      Rails.logger.warn("[ReportDraftGenerator] attempt #{attempt + 1} failed: #{e.message}")
      @chat = nil
    end
    raise Failed, FAILED_MESSAGE
  end

  def reply_text(reply)
    reply.respond_to?(:content) ? reply.content.to_s : reply.to_s
  end

  # The first {...} of the answer, without code fences
  def parse(text)
    body = text.to_s.gsub(/```(?:json)?/i, "")
    start = body.index("{")
    stop  = body.rindex("}")
    return nil unless start && stop && stop > start

    parsed = JSON.parse(body[start..stop])
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    nil
  end

  def normalise(answer, root, cannot)
    spec = answer["spec"].is_a?(Hash) ? answer["spec"].merge("root_model" => root.to_s) : { "root_model" => root.to_s }
    {
      "spec" => spec,
      "questions" => Array(answer["questions"]).select { |q| q.is_a?(Hash) && QUESTION_KINDS.include?(q["kind"].to_s) }
                                               .map { |q| q.slice("kind", "text", "options") },
      "assumptions" => Array(answer["assumptions"]).map(&:to_s).compact_blank,
      "cannot" => cannot + Array(answer["cannot"]).map { |c| cannot_text(c) }.compact_blank,
      "name" => answer["name"].to_s.presence
    }
  end

  def cannot_text(item)
    item.is_a?(Hash) ? item.values.map(&:to_s).compact_blank.join(" — ") : item.to_s
  end
end
