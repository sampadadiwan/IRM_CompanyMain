# How one account entry's number was worked out: its formula broken into the terms it returns,
# each term carrying the value the run recorded, and every term that is itself another entry
# opening into that entry's own breakdown. Replaces the entry page's flat Explanation box — see
# docs/modules/allocation/allocation_run_review_proposals.md (proposal 1).
#
#   Management Fees                                    ₹2,95,000.00
#    ├─ Total applicable Management Fee      ▸         ₹X     (opens into its own formula)
#    └─ − Management Fees since inception    ▸         ₹Y     (opens into the entries it summed)
#
# WHAT IS A NODE, AND WHAT IS NOT. The formula is split only at the arithmetic of what it
# returns — the terms of a sum, the factors of a product — and at the named locals it uses,
# which open into their own expressions. Conditions, id comparisons and record lookups are never
# nodes: they decide which branch runs, they do not add up to anything. The first attempt at
# this rendered every recorded expression and produced pages of
# "7295==account_entry.parent.portfolio_company_id -> false".
#
# WHERE VALUES COME FROM. Only from what the run recorded (FundFormula#parse_statement): a
# sub-expression under its exact source text, a local under its name, a reference under
# "@name". Nothing is re-evaluated — the question is what this was when the run happened. A run
# made without "Explain Formulas" recorded no values, and the structure is shown without them.
#
# WHAT IS MONEY. A figure is shown as currency only when it is known to be money: another entry,
# a total of entries, a source text naming a *_cents column, or arithmetic whose money-ness
# follows from its terms. Everything else is a plain number. Formatting every value as currency
# turned "end_date.year = 2026" into "20.26".
#
# COST. One query per breakdown — this folio's entries on this date, narrow select — to resolve
# references. Opening another entry is a separate request (see AccountEntriesController#
# explanation_node), so the entry page never builds more than its own level.
class AccountEntryExplanation
  # Methods that read a figure off something already fetched, or convert it, and so pass the
  # term straight through.
  TRANSPARENT = %i[amount_cents amount folio_amount_cents to_d to_f to_i].freeze

  # A source text naming a money column: "amount_cents", "committed_amount_cents_before(…)".
  # Not /_cents\b/ — "_" is a word character, so that never matched "_cents_before".
  MONEY_SOURCE = /_cents(?![a-z])/

  # Scopes that narrow which of this folio's entries are read, in words.
  ENTRY_SCOPES = { cumulative: "cumulative", not_cumulative: nil,
                   for_parent_account_entries: "for the same investment",
                   for_portfolio_investments: "for its portfolio investments" }.freeze

  # Plain words for what the engine supplies.
  INPUT_LABELS = { "end_date" => "Period end date", "start_date" => "Period start date",
                   "fund" => "The fund" }.freeze

  Node = Struct.new(:kind, :label, :expression, :value, :money, :sign, :op, :children,
                    :entry_id, :reporting_date, :note, :helper, :name, :entry_type,
                    keyword_init: true) do
    def children = self[:children] || []
    def sign = self[:sign] || 1
    def subtracted? = sign.negative?
    def divisor? = op == :divide
    def money? = money == true

    # Opens into another entry's breakdown, or the entries a total summed — fetched on demand.
    def lazy? = %i[entry aggregate source].include?(kind) && (entry_id.present? || kind == :aggregate)

    # Opens into terms already on the page.
    def composite? = children.any?

    def numeric_value
      return value if value.is_a?(Numeric)

      text = value.to_s.strip
      text.match?(/\A-?\d+(\.\d+)?\z/) ? BigDecimal(text) : nil
    end
  end

  attr_reader :entry

  def initialize(entry)
    @entry = entry
  end

  # The formula the run evaluated — a snapshot stored on the entry.
  def formula = Array(@entry.explanation).first.to_s.presence

  def description = Array(@entry.explanation).find { |el| el.is_a?(String) && el != formula && !el.strip.start_with?("{") }

  def breakdown_recorded? = breakdown.any?

  # Every value the run recorded, as [source text or name, value] pairs, for the calculation
  # steps table: the rule's named steps first, in the order it assigns them, so the table reads
  # down the rule; then the sub-expressions recorded inside them, in the order they were
  # recorded. The engine's own inputs ("@start_date", "@end_date") are left out — they are the
  # run's dates, not steps of this rule. ES4 (order), ES6 (nothing recorded) —
  # features/fund/entry_explanation.feature.
  # @return [Array<Array(String, Object)>]
  def steps
    rows = breakdown.reject { |key, _| key.start_with?("@") && key.exclude?(" ") }.to_a
    order = parsed ? assignment_order : []
    named, rest = rows.partition { |key, _| order.include?(key) }
    named.sort_by { |key, _| order.index(key) } + rest
  end

  # The entry, with what it is made of beneath it.
  # @return [Node]
  def root
    @root ||= begin
      children = []
      # Named by the formula itself when it uses "fund_account_entry"; listed first otherwise.
      children << source_node if allocated? && formula.to_s.exclude?("fund_account_entry")
      children.concat(term_children) if parsed
      Node.new(kind: :root, label: @entry.name, value: @entry.amount_cents, money: true,
               children: children, expression: formula)
    end
  end

  # Whether what the rule returns is a straight sum of its terms. Only then does "do the terms
  # come back to the entry" mean anything — for a product or a quotient they are inputs, and
  # totalling them would set, say, NAV against NAV per unit.
  def additive?
    return false if parsed.nil?

    node = build(result_node, sign: 1, seen: Set.new)
    node.present? && node.kind == :sum
  end

  # The terms' recorded values, added with their signs — when every term has one and is money.
  # @return [BigDecimal, nil]
  def parts_total
    terms = root.children
    return nil unless additive? && terms.any? && terms.all? { |t| t.money? && t.numeric_value }

    terms.sum { |t| t.sign * t.numeric_value }
  end

  def reconciles?
    total = parts_total
    return nil if total.nil?

    (total / 100).round(2) == (@entry.amount_cents.to_d / 100).round(2)
  end

  # Why there is nothing to break down, when there is nothing.
  def leaf_reason
    return "This entry was uploaded or entered by hand — it was not computed." unless @entry.generated?
    return "Percentage entries are worked out across all folios at once, so no formula was recorded." if percentage?
    return "The rule that produced this could not be read." if formula.present? && parsed.nil?

    nil
  end

  # The entries one "since inception" / "quarterly" total summed, as nodes — for opening an
  # aggregate. Mirrors the helper's own window (see CommitmentAccountEntry).
  MAX_WINDOW = 12
  def window_nodes(helper:, name:, entry_type:)
    scope = AccountEntry.where(fund_id: @entry.fund_id, capital_commitment_id: @entry.capital_commitment_id,
                               deleted_at: nil).not_cumulative
    scope = scope.where(name: name) if name.present?
    scope = scope.where(entry_type: entry_type) if entry_type.present?
    scope = scope.where(reporting_date: window_range(helper))
    # Never the entry being explained: its rule ran before it existed, so it cannot be among the
    # entries it totalled — a rule reading its own name's history would otherwise list itself.
    scope = scope.where.not(id: @entry.id)
    rows = scope.select(:id, :reporting_date, :name, :amount_cents)
                .order(reporting_date: :desc).limit(MAX_WINDOW + 1).to_a
    more = rows.size > MAX_WINDOW
    nodes = rows.first(MAX_WINDOW).map do |row|
      Node.new(kind: :entry, label: "#{row.name} · #{I18n.l(row.reporting_date)}", value: row.amount_cents,
               money: true, entry_id: row.id, reporting_date: row.reporting_date)
    end
    [nodes, more]
  end

  private

  def allocated? = @entry.parent_type == "AccountEntry" && @entry.parent_id.present?
  def percentage? = @entry.fund_formula&.rule_type == "Percentage"

  def parsed
    return @parsed if defined?(@parsed)

    @parsed = begin
      source = formula
      if source.nil?
        nil
      else
        buffer = Parser::Source::Buffer.new("(formula)")
        buffer.source = source
        parser = Parser::CurrentRuby.new
        parser.diagnostics.consumer = ->(_d) {}
        parser.diagnostics.all_errors_are_fatal = false
        parser.parse(buffer)
      end
    rescue StandardError
      nil
    end
  end

  # { source text / local name / "@ref" => recorded value }
  def breakdown
    @breakdown ||= begin
      hash = Array(@entry.explanation).filter_map do |el|
        next unless el.is_a?(String) && el.strip.start_with?("{")

        begin
          JSON.parse(el)
        rescue JSON::ParserError
          nil
        end
      end.first
      hash.is_a?(Hash) ? hash : {}
    end
  end

  # Locals the formula assigns, wherever it assigns them — a real fee formula sets
  # "month_difference" inside the branch of an if — so a term naming one can open into its
  # expression.
  def locals
    @locals ||= {}.tap { |acc| collect_locals(parsed, acc) }
  end

  # Walks the rule in the order it runs, so a later assignment replaces an earlier one — a rule
  # that starts "forex_result = 0.0" and sets it for real inside an if must open into the real
  # one, not the zero. Only the branch the run took is walked: an assignment in a branch that did
  # not run never happened.
  # Covered by ES1 (reassigned after a starting zero) and ES3 (an if that did not run) —
  # features/fund/entry_explanation.feature.
  def collect_locals(node, acc)
    return unless node.is_a?(Parser::AST::Node)

    if node.type == :if
      # The condition is evaluated either way; then only the branch that ran.
      collect_locals(node.children[0], acc)
      collect_locals(chosen_branch(node), acc)
      return
    end

    # The right-hand side runs before the name is bound, so nested assignments come first.
    node.children.each { |child| collect_locals(child, acc) }
    acc[node.children[0].to_s] = node.children[1] if node.type == :lvasgn
  end

  # Every local the rule assigns, in the order it first appears in the text, whichever branch
  # it sits in — the order the calculation steps are listed in.
  def assignment_order
    @assignment_order ||= [].tap { |names| collect_assignment_names(parsed, names) }
  end

  def collect_assignment_names(node, names)
    return unless node.is_a?(Parser::AST::Node)

    names << node.children[0].to_s if node.type == :lvasgn && names.exclude?(node.children[0].to_s)
    node.children.each { |child| collect_assignment_names(child, names) }
  end

  def result_node = result_of(parsed)

  # What a block of code evaluates to: the last statement of a sequence, the branch of an if
  # that the run took, or the value an assignment gives.
  def result_of(node)
    node = unwrap(node)
    return nil unless node.is_a?(Parser::AST::Node)

    case node.type
    when :begin then result_of(node.children.last)
    when :lvasgn then result_of(node.children[1])
    when :if then result_of(chosen_branch(node))
    else node
    end
  end

  def term_children
    node = build(result_node, sign: 1, seen: Set.new)
    return [] if node.nil?

    # The formula's top-level shape becomes the root's children directly: "= a − b" rather than
    # a single child that says the same thing again.
    %i[sum product].include?(node.kind) ? node.children : [node]
  end

  # An Allocate* rule split a fund-level entry across folios; that entry comes first.
  def source_node
    parent = AccountEntry.select(:id, :reporting_date, :name, :amount_cents).find_by(id: @entry.parent_id)
    return Node.new(kind: :value, label: "The fund-level entry this was split from", note: "no longer exists") if parent.nil?

    Node.new(kind: :source, label: parent.name, value: parent.amount_cents, money: true,
             entry_id: parent.id, reporting_date: parent.reporting_date,
             note: "the fund-level amount this folio's share was taken from")
  end

  # ── building ──────────────────────────────────────────────────────────────────

  def build(node, sign:, seen:)
    return nil unless node.is_a?(Parser::AST::Node)

    node = unwrap(node)
    case node.type
    # "…last&.amount_cents" is a :csend; it is a send that tolerates nil, nothing more.
    when :send, :csend then build_send(node, sign: sign, seen: seen)
    when :ivar then build_ivar(node, sign: sign)
    when :lvar then build_local(node, sign: sign, seen: seen)
    when :int, :float
      number = node.children[0]
      label = ActiveSupport::NumberHelper.number_to_rounded(number, precision: 6, strip_insignificant_zeros: true,
                                                                    delimiter: ",")
      Node.new(kind: :constant, label: label, value: number, money: false, sign: sign, expression: source_of(node))
    when :if, :begin then build(result_of(node), sign: sign, seen: seen)
    when :or
      build(node.children[0], sign: sign, seen: seen)&.tap do |term|
        term.note = [term.note, "zero when there is none"].compact.join("; ")
      end
    else
      recorded(node, sign: sign)
    end
  end

  def build_send(node, sign:, seen:)
    method = node.children[1]
    receiver = node.children[0]

    # Allocate* rules are handed the fund-level entry they split as "fund_account_entry". The
    # formula never assigns it, so it parses as a bare method call, not a local — which is why
    # handling it as a local never fired and the card showed a line called "Fund account entry".
    return source_node.tap { |n| n.sign = sign } if receiver.nil? && node.children.size == 2 && method == :fund_account_entry && allocated?

    return sum_node(node, sign: sign, seen: seen) if %i[+ -].include?(method) && node.children.size == 3
    return product_node(node, sign: sign, seen: seen) if %i[* /].include?(method) && node.children.size == 3
    return build(receiver, sign: -sign, seen: seen) if method == :-@ && receiver

    if TRANSPARENT.include?(method) && node.children.size == 2 && receiver.is_a?(Parser::AST::Node)
      inner = build(receiver, sign: sign, seen: seen)
      if inner
        # The run records "….last" as the record it found and "….last.amount_cents" as the
        # figure; the figure is the one that belongs on the line.
        outer = lookup(node)
        inner.value = outer unless outer.nil?
        inner.value = nil if inner.value && inner.numeric_value.nil? && inner.money?
        return inner
      end
    end

    name = method.to_s
    return helper_node(node, name, sign: sign) if FormulaReferenceScanner::WINDOW_HELPERS.key?(name)
    return named_read_node(node, sign: sign) if FormulaReferenceScanner::ENTRY_READERS.include?(name)
    return entries_read_node(node, sign: sign) if entries_read?(node)

    recorded(node, sign: sign)
  end

  # "capital_commitment.account_entries.where(name: "X", reporting_date: @start_date..@end_date)
  # .sum(:amount_cents)" — the commonest way a formula reads other entries in production, and
  # before this it was shown as a bare figure called "Total amount of account entries".
  def entries_read?(node) = !entries_chain(node).nil?

  # The chain that reads account_entries: the node itself, or — for
  # "AccountEntrySqlite.total_amount(<chain>)" — the chain passed to it.
  def entries_chain(node)
    return node if chain(node).any? { |send| send.children[1] == :account_entries }

    node.children[2..].to_a.find { |arg| arg.is_a?(Parser::AST::Node) && chain(arg).any? { |send| send.children[1] == :account_entries } }
  end

  def entries_read_node(node, sign:)
    conditions = where_conditions(entries_chain(node))
    scope_words = chain(entries_chain(node)).filter_map { |send| ENTRY_SCOPES[send.children[1]] }.uniq
    name = conditions[:name]
    own_rule = conditions[:own_rule]
    helper = case conditions[:window]
             when :period then "run_period"
             when :on_date then "on_date"
             else "since_inception"
             end
    label_name = if own_rule then "#{@entry.name}, earlier"
                 elsif conditions[:own_type] then "#{@entry.name} entries"
                 else name
                 end
    unless label_name
      qualifier = scope_words.any? ? " #{scope_words.join(', ')}" : ""
      return Node.new(kind: :value, label: "Total of this folio's entries#{qualifier}", value: lookup(node),
                      money: true, sign: sign, expression: source_of(node),
                      note: "the rule picks which entries while it runs")
    end

    window_words = { period: "this period", on_date: "on this date" }.fetch(conditions[:window], "up to this date")
    note = conditions[:window] == :unknown ? "the rule applies its own conditions, so the list may be wider than what it totalled" : nil
    label_name = "#{label_name} (#{scope_words.join(', ')})" if scope_words.any?
    picks = chain(entries_chain(node)).map { |send| send.children[1] }
    label_name = "Latest #{label_name.sub(/\A\S/, &:downcase)}" if picks.include?(:last)
    label_name = "Earliest #{label_name.sub(/\A\S/, &:downcase)}" if picks.include?(:first)
    Node.new(kind: :aggregate, label: "#{label_name} — #{window_words}", value: lookup(node), money: true,
             sign: sign, helper: helper, name: own_rule ? @entry.name : name,
             entry_type: conditions[:own_type] ? @entry.name : conditions[:entry_type],
             expression: source_of(node), note: note)
  end

  # Every send in a method chain, outermost first.
  def chain(node)
    sends = []
    while node.is_a?(Parser::AST::Node) && %i[send csend].include?(node.type)
      sends << node
      node = node.children[0]
    end
    sends
  end

  # name / entry_type / reporting-date window from the where(...) calls in a chain.
  def where_conditions(node)
    found = { window: nil }
    chain(node).each do |send|
      next unless send.children[1] == :where

      send.children[2..].each do |arg|
        next unless arg.is_a?(Parser::AST::Node) && arg.type == :hash

        arg.children.each do |pair|
          next unless pair.type == :pair

          key = pair.children[0].children[0].to_s
          value = pair.children[1]
          case key
          when "name"
            if value.type == :str then found[:name] = value.children[0]
            elsif source_of(value).strip == "fund_formula.name" then found[:own_rule] = true
            end
          when "entry_type"
            if value.type == :str then found[:entry_type] = value.children[0]
            elsif source_of(value).strip == "fund_formula.name" then found[:own_type] = true
            end
          when "reporting_date"
            found[:window] = case source_of(value).gsub(/\s+/, "")
                             when "@start_date..@end_date" then :period
                             when "..@end_date" then :since_inception
                             when "@end_date" then :on_date
                             else :unknown
                             end
          end
        end
      end
    end
    found[:window] ||= :since_inception
    found
  end

  # a + b − c, flattened into one level of signed terms.
  def sum_node(node, sign:, seen:)
    terms = []
    flatten_sum(node, sign, terms)
    children = terms.filter_map { |term, term_sign| build(term, sign: term_sign, seen: seen) }
    Node.new(kind: :sum, label: children.map { |c| (c.subtracted? ? "− " : "+ ") + c.label }.join(" ").delete_prefix("+ "),
             value: lookup(node), sign: sign, children: children, expression: source_of(node),
             money: children.any? && children.all?(&:money?))
  end

  def flatten_sum(node, sign, out)
    node = unwrap(node)
    if node.type == :send && %i[+ -].include?(node.children[1]) && node.children.size == 3
      flatten_sum(node.children[0], sign, out)
      flatten_sum(node.children[2], node.children[1] == :- ? -sign : sign, out)
    else
      out << [node, sign]
    end
  end

  # a × b ÷ c, flattened into one level of factors.
  def product_node(node, sign:, seen:)
    factors = []
    flatten_product(node, :multiply, factors)
    children = factors.each_with_index.filter_map do |(factor, op), index|
      child = build(factor, sign: 1, seen: seen)
      # The first factor is what the rest multiply or divide; it has no operator of its own.
      child&.tap { |c| c.op = index.zero? ? nil : op }
    end
    label = children.each_with_index.map do |c, i|
      if i.zero?
        c.label
      else
        "#{c.divisor? ? '÷' : '×'} #{c.label}"
      end
    end.join(" ")
    # Money times rate is money; money divided by money, or rate by rate, is not.
    money_factors = children.reject(&:divisor?).count(&:money?)
    Node.new(kind: :product, label: label, value: lookup(node), sign: sign, children: children,
             expression: source_of(node), money: money_factors == 1 && children.select(&:divisor?).none?(&:money?))
  end

  def flatten_product(node, op, out)
    node = unwrap(node)
    if node.type == :send && %i[* /].include?(node.children[1]) && node.children.size == 3
      flatten_product(node.children[0], op, out)
      flatten_product(node.children[2], node.children[1] == :/ ? :divide : :multiply, out)
    else
      out << [node, op]
    end
  end

  def build_ivar(node, sign:)
    field = node.children[0].to_s.delete_prefix("@")
    if engine_input?(field)
      return Node.new(kind: :input, label: INPUT_LABELS.fetch(field, field.humanize), sign: sign,
                      value: breakdown["@#{field}"], money: false, expression: "@#{field}")
    end

    matches = siblings_by_field[field]
    if matches.blank?
      return Node.new(kind: :missing, label: field.humanize, sign: sign, value: breakdown["@#{field}"],
                      money: true, expression: "@#{field}",
                      note: "no entry of this name was produced for this folio on this date")
    end
    # More than one entry answers to this name, and nothing in the text says which the rule read.
    # Show the value the run recorded and let the line open into all of them, rather than
    # linking one at random and drawing its figure as if it were the one used.
    return several_node(matches, sign: sign, value: breakdown["@#{field}"], expression: "@#{field}") if matches.size > 1

    sibling = matches.first
    Node.new(kind: :entry, label: sibling.name, value: sibling.amount_cents, money: true, sign: sign,
             entry_id: sibling.id, reporting_date: sibling.reporting_date, expression: "@#{field}")
  end

  # A named local opens into the expression it was given.
  def build_local(node, sign:, seen:)
    name = node.children[0].to_s

    rhs = locals[name]
    children = if rhs && seen.exclude?(name)
                 inner = build(rhs, sign: 1, seen: seen + [name])
                 if inner.nil? || inner.kind == :value || inner.kind == :constant
                   # The local simply names a figure the rule looked up; a child repeating that
                   # figure under a worse label adds a line and says nothing.
                   []
                 elsif %i[sum product].include?(inner.kind)
                   inner.children
                 else
                   [inner]
                 end
               else
                 []
               end
    money = MONEY_SOURCE.match?(name) || (children.any? && children.all?(&:money?)) ||
            (rhs && MONEY_SOURCE.match?(source_of(rhs)))
    Node.new(kind: :local, label: name.humanize, value: breakdown[name], money: money, sign: sign,
             children: children, expression: name)
  end

  def helper_node(node, helper, sign:)
    name = literal(node.children[2])
    entry_type = literal(node.children[3])
    # Neither argument is written out: which entries it totals is decided while the rule runs.
    # Opening it would list the folio's most recent entries of any name as if they were the ones
    # summed, so it is shown with its value and not opened.
    if name.nil? && entry_type.nil? && computed_argument?(node)
      return Node.new(kind: :value, label: "A total chosen while the rule runs", value: lookup(node),
                      money: true, sign: sign, expression: source_of(node),
                      note: "which entries it adds up is worked out as the rule runs")
    end
    label = "#{name || entry_type || 'entries'} #{FormulaReferenceScanner::WINDOW_HELPERS[helper]}"
    Node.new(kind: :aggregate, label: label, value: lookup(node), money: true, sign: sign,
             helper: helper, name: name, entry_type: entry_type, expression: source_of(node))
  end

  # get_account_entry_or_zero("Name", date): the same period resolves to this folio's entry of
  # that name; another period is named as such and not opened, because its entry is not this
  # run's.
  def named_read_node(node, sign:)
    name = literal(node.children[2])
    date_source = node.children[3] ? source_of(node.children[3]) : ""
    matches = name ? Array(siblings_by_name[name]) : []
    if name && date_source.strip == "@end_date" && matches.any?
      # Several of that name, and the rule narrows by investment ("parent:") — which one it took
      # depends on the investment, so list them all under the value the run recorded.
      return several_node(matches, sign: sign, value: lookup(node), expression: source_of(node)) if matches.size > 1 && parent_kwarg?(node)

      # Otherwise it takes what get_account_entry takes: the latest by date, then highest id.
      sibling = matches.max_by(&:id)
      return Node.new(kind: :entry, label: sibling.name, value: sibling.amount_cents, money: true,
                      sign: sign, entry_id: sibling.id, reporting_date: sibling.reporting_date,
                      expression: source_of(node))
    end

    if name && date_source.strip == "@end_date"
      # get_account_entry reads the latest entry up to the date, so none on this date means it
      # fell back to an earlier one, or to zero.
      return Node.new(kind: :missing, label: name, value: lookup(node), money: true, sign: sign,
                      expression: source_of(node),
                      note: "none on this date — the rule used the latest earlier one, or zero")
    end

    Node.new(kind: :earlier, label: name || "An entry chosen while the rule runs", value: lookup(node), money: true,
             sign: sign, expression: source_of(node),
             note: name ? "as it stood #{date_in_words(date_source)}" : "which entry is decided while the rule runs")
  end

  # "@start_date" -> "at the start of this period". Only the common cases are named; anything
  # else is called what it is, an earlier date, rather than echoed as Ruby.
  def date_in_words(source)
    case source.gsub(/\s+/, "")
    when "@start_date" then "at the start of this period"
    when /\A@end_date\.beginning_of_quarter/ then "at the start of the quarter"
    when /\A@end_date\.beginning_of_year/ then "at the start of the year"
    else "at an earlier date"
    end
  end

  # A figure the rule read or worked out that is not itself an entry — a unit setting, a
  # committed amount, a count. Shown with its recorded value under a plain label.
  def recorded(node, sign:)
    source = source_of(node)
    Node.new(kind: :value, label: friendly(node), value: lookup(node), sign: sign, expression: source,
             money: MONEY_SOURCE.match?(source))
  end

  # ── helpers ───────────────────────────────────────────────────────────────────

  # (expr) parses as a one-child :begin.
  def unwrap(node)
    node = node.children[0] while node.is_a?(Parser::AST::Node) && node.type == :begin && node.children.size == 1
    node
  end

  # The branch the run took. Known first from the condition's own recorded true/false — a false
  # condition with no else ran nothing, so that is nil. Failing that, by which branch's result it
  # recorded a value for; the "then" branch otherwise. A branch that is a nested if is judged by
  # its own chosen branch. ES2 (nested ifs, recorded false) and ES3 (false, no else) —
  # features/fund/entry_explanation.feature.
  def chosen_branch(node)
    # "unless" parses as an if with its branches swapped, so children[1] is always the
    # branch taken when the condition is true.
    case condition_value(node.children[0])
    when true then return node.children[1]
    when false then return node.children[2]
    end

    branches = node.children[1..].compact
    branches.find { |b| !lookup(result_of(b)).nil? } || branches.first
  end

  # The recorded value of an if's condition, when it was recorded as a boolean; nil otherwise —
  # a truthy number or an unrecorded condition says nothing certain about which branch ran.
  def condition_value(condition)
    value = lookup(unwrap(condition))
    return true if value == true || value.to_s == "true"
    return false if value == false || value.to_s == "false"

    nil
  end

  def lookup(node)
    return nil unless node.is_a?(Parser::AST::Node)

    key = case node.type
          when :lvar, :ivar then node.children[0].to_s
          else source_of(node)
          end
    breakdown[key]
  end

  def source_of(node) = node.location.expression&.source.to_s

  def literal(node)
    node&.type == :str ? node.children[0] : nil
  end

  # A helper's name or entry-type argument that is neither a written string nor nil.
  def computed_argument?(node)
    node.children[2..3].any? { |arg| arg.is_a?(Parser::AST::Node) && %i[str nil].exclude?(arg.type) }
  end

  def parent_kwarg?(node)
    node.children.any? do |arg|
      arg.is_a?(Parser::AST::Node) && arg.type == :hash &&
        arg.children.any? { |pair| pair.type == :pair && pair.children[0].children[0].to_s == "parent" }
    end
  end

  # Several entries of one name on this date, as one line that opens into all of them.
  def several_node(matches, sign:, value:, expression:)
    Node.new(kind: :aggregate, label: "#{matches.first.name} (#{matches.size} on this date)", value: value,
             money: true, sign: sign, helper: "on_date", name: matches.first.name, expression: expression,
             note: "one per investment; the rule's own figure is shown")
  end

  def engine_input?(field)
    AccountEntryAllocation::AllocationBaseOperation::ENGINE_PROVIDED_FIELDS.include?(field) ||
      AccountEntryAllocation::CommitmentCache::BASE_FIELDS.include?(field)
  end

  # "capital_commitment.committed_amount_cents_before(@end_date)" -> "Committed amount before"
  # "fund_unit_setting.management_fee" -> "Management fee (fund unit setting)"
  def friendly(node)
    return node.children[0].to_s.humanize if %i[lvar ivar].include?(node.type)
    return source_of(node) unless node.type == :send

    # "json_fields[custom_field_key.to_s]" — a custom field, whichever one the rule picks.
    if node.children[1] == :[]
      key = node.children[2]
      return "Custom field “#{key.children[0]}”" if key&.type == :str

      return "Custom field value"
    end

    # "…fund_units.where(…).sum(:quantity)" -> "Total quantity of fund units"
    if %i[sum count].include?(node.children[1])
      column = node.children[2]&.type == :sym ? node.children[2].children[0].to_s.delete_suffix("_cents") : nil
      relation = relation_name(node.children[0])
      what = node.children[1] == :count ? "Number" : "Total #{column&.humanize&.downcase || 'amount'}"
      return relation ? "#{what} of #{relation.humanize.downcase}" : what
    end

    method = node.children[1].to_s.delete_suffix("?").sub(/_cents(?=_|\z)/, "")
    label = method.humanize
    receiver = node.children[0]
    if receiver&.type == :send && receiver.children[0].nil?
      owner = receiver.children[1].to_s
      label += " (#{owner.humanize.downcase})" unless %w[capital_commitment fund].include?(owner)
    elsif %i[lvar ivar].include?(receiver&.type)
      # "end_date.year" and "@end_date.year" are the same question; say whose year it is either way.
      owner = receiver.children[0].to_s.delete_prefix("@")
      label += " (#{owner.humanize.downcase})" unless %w[capital_commitment fund].include?(owner)
    end
    label
  end

  # The collection a chain is built on: "capital_remittance_payments" in
  # "capital_commitment.capital_remittance_payments.where(…).sum(…)". Taken as the first method
  # called on the chain's root object, not the last one before the sum — the last is usually a
  # scope ("not_cumulative"), which is how "Total amount of not cumulative" got onto the page.
  def relation_name(node)
    sends = chain(node)
    # "capital_commitment" in "capital_commitment.capital_remittance_payments" is itself a bare
    # send (no receiver); the relation is the call made on it.
    sends.pop if sends.last && sends.last.children[0].nil? && sends.size > 1
    sends.last&.children&.[](1)&.to_s
  end

  def financial_year_start(end_date)
    @entry.capital_commitment&.start_of_financial_year_date(end_date) || end_date.beginning_of_year
  end

  def siblings
    @siblings ||= AccountEntry.where(fund_id: @entry.fund_id, capital_commitment_id: @entry.capital_commitment_id,
                                     reporting_date: @entry.reporting_date, deleted_at: nil)
                              .where.not(id: @entry.id)
                              .select(:id, :reporting_date, :name, :amount_cents).to_a
  end

  # Grouped, not indexed: a folio can hold several entries of one name on one date — one per
  # portfolio investment, from Allocate* rules — and index_by would keep an arbitrary one.
  def siblings_by_field = @siblings_by_field ||= siblings.group_by { |row| FundFormula.to_varable_name(row.name) }
  def siblings_by_name = @siblings_by_name ||= siblings.group_by(&:name)

  def window_range(helper)
    end_date = @entry.reporting_date
    case helper
    when "run_period" then (@entry.allocation_run&.start_date || end_date.beginning_of_quarter)..end_date
    when "quarterly", "period" then end_date.beginning_of_quarter..end_date
    # The fund's financial year, as CommitmentAccountEntry#year_to_date sums — not the calendar
    # year, which lists the wrong months for any fund whose year starts in April.
    when "year_to_date" then financial_year_start(end_date)..end_date
    when "on_date", "as_on_date" then end_date..end_date
    else ..end_date
    end
  end
end
