# Reads a fund formula's source and reports which other numbers it depends on, so a computed
# account entry can be opened into the entries it was built from. See
# docs/modules/allocation/allocation_run_review_proposals.md (proposal 1).
#
# Formulas refer to other entries in two ways, and only the first was previously understood
# anywhere in the codebase:
#
#   1. "@field" references  — @net_income, resolved from this run's earlier entries for the same
#      folio (FundFormula#referenced_field_names, FundFormulaDependencyGraph).
#   2. By NAME, through a helper call — capital_commitment.since_inception("Management Fees", …),
#      .quarterly(nil, "Operating Cost", …), .account_entries.where(name: "Management Fees").
#      Roughly a third of enabled formulas in production do this. A tree that saw only way 1
#      would show "Since Inception Management Fees" as a raw fact rather than a sum that can be
#      opened, which is precisely the number a reviewer wants to open.
#
# Text only: nothing here touches the database, and nothing is evaluated. A formula whose helper
# arguments are computed rather than literal cannot be resolved from text at all — those are
# reported as `unresolved` and shown to the reviewer as such, never guessed at.
class FormulaReferenceScanner
  # Helpers on CapitalCommitment that total this folio's other entries over a window. Values are
  # how the window is described to a reviewer. See
  # app/packs/funds/capital_commitments/models/concerns/commitment_account_entry.rb.
  WINDOW_HELPERS = {
    "quarterly" => "this quarter", "period" => "this quarter",
    "year_to_date" => "this year to date",
    "since_inception" => "since inception",
    "on_date" => "on this date", "as_on_date" => "on this date"
  }.freeze

  # `helper`, not `method`: a Struct member called :method would override Object#method.
  # Helpers that fetch one named entry at a date the formula chooses, rather than totalling a
  # window. ~10% of enabled formulas in production read other entries this way
  # (get_account_entry_or_zero: 344, get_account_entry: 43), and before these were recognised a
  # total read only through them looked, wrongly, like nothing depended on it.
  ENTRY_READERS = %w[get_account_entry get_account_entry_or_zero get_ic_account_entry].freeze

  # Reading a figure off a fetched entry, or converting it, passes its sign straight through —
  # "@a - get_account_entry_or_zero('X', d).amount_cents" still subtracts X.
  TRANSPARENT_READS = %i[amount_cents amount folio_amount_cents to_d to_f to_i].freeze

  # date_source: the date argument as written. "@end_date" means the run's own date; anything
  # else (@end_date.beginning_of_quarter, say) reads another period's figure.
  NamedRead = Struct.new(:name, :source, :date_source, keyword_init: true) do
    def same_period? = date_source.to_s.strip == "@end_date"
  end

  HelperCall = Struct.new(:helper, :name, :entry_type, :source, :window, keyword_init: true) do
    # What the aggregate node is called in the tree.
    def label
      subject = name.presence || entry_type.presence || "entries"
      "#{subject} #{window}"
    end
  end

  # signs: { "@net_income" => 1, "capital_commitment.since_inception(…)" => -1 } — whether each
  # reference is added to or taken away from the result. Without it a derivation can only list
  # what a number was built from; with it, it can show the arithmetic and check that the parts
  # come back to the whole, which is the difference between a list of numbers and an
  # explanation.
  # additive: whether every reference is combined by nothing but + and −. A formula that
  # multiplies or divides has inputs, not addends, so asking whether its parts "add up to" the
  # result is a category error — "@nav / total_units" would set ₹1.24 crore plus 50,000 units
  # against ₹248.63 and call the gap a discrepancy.
  Result = Struct.new(:field_names, :input_names, :helper_calls, :name_filters, :named_reads,
                      :unresolved, :bare_identifiers, :signs, :additive, :parse_error,
                      keyword_init: true)

  # @param source [String] the formula text, normally AccountEntry#explanation.first
  def initialize(source)
    @source = source.to_s
  end

  # @return [Result] always; a formula that will not parse comes back empty with parse_error set
  def call
    ast = parse
    return empty_result(@parse_error) if ast.nil?

    walk(ast)
    @signs = {}
    @additive = true
    record_signs(ast, 1, pure: true)
    Result.new(
      field_names: @field_names.uniq, input_names: @input_names.uniq,
      helper_calls: @helper_calls.uniq(&:source), name_filters: @name_filters.uniq,
      named_reads: @named_reads.uniq(&:source),
      unresolved: @unresolved.uniq, bare_identifiers: @bare_identifiers.uniq,
      signs: @signs, additive: @additive, parse_error: nil
    )
  end

  private

  def empty_result(parse_error)
    Result.new(field_names: [], input_names: [], helper_calls: [], name_filters: [], named_reads: [],
               unresolved: [], bare_identifiers: [], signs: {}, additive: false,
               parse_error: parse_error)
  end

  def parse
    @field_names = []
    @input_names = []
    @helper_calls = []
    @name_filters = []
    @named_reads = []
    @unresolved = []
    @bare_identifiers = []
    return nil if @source.blank?

    buffer = Parser::Source::Buffer.new("(formula)")
    buffer.source = @source
    # A formula that no longer parses is a fact about the formula, not an error to raise at a
    # reviewer who only asked how a number was reached. The parser returns nil on a syntax
    # error rather than raising, and would otherwise write its diagnostics to stderr on every
    # page view, so its own reporting is turned off and the nil turned into a message here.
    parser = Parser::CurrentRuby.new
    parser.diagnostics.consumer = ->(_diagnostic) {}
    parser.diagnostics.all_errors_are_fatal = false
    ast = parser.parse(buffer)
    @parse_error = "this formula could not be read" if ast.nil?
    ast
  rescue StandardError => e
    @parse_error = e.message
    nil
  end

  # Second pass, carrying the sign down the expression: everything to the right of a minus is
  # negated, and a nested "a - (b + c)" negates both b and c. Anything that is not plain
  # addition or subtraction — a multiplication, a division, a method call — passes the sign
  # through unchanged, because a reference inside it still contributes in that direction.
  # `pure` is whether everything so far has been plain addition or subtraction. A reference
  # reached any other way — through a multiplication, a division, an argument — is an input to
  # the calculation rather than a term of a sum, and one of those is enough to make the whole
  # formula non-additive.
  def record_signs(node, sign, pure:)
    return unless node.is_a?(Parser::AST::Node)

    if node.type == :send && %i[+ -].include?(node.children[1]) && node.children.size == 3
      record_signs(node.children[0], sign, pure: pure)
      record_signs(node.children[2], node.children[1] == :- ? -sign : sign, pure: pure)
      return
    end

    # ".amount_cents" on a fetched entry, or a ".to_d", is still the same term.
    if node.type == :send && TRANSPARENT_READS.include?(node.children[1]) && node.children.size == 2 &&
       node.children[0].is_a?(Parser::AST::Node)
      record_signs(node.children[0], sign, pure: pure)
      return
    end

    # A formula of several statements returns its last one; the ones before it set locals up.
    if node.type == :begin
      node.children.each_with_index do |child, index|
        record_signs(child, sign, pure: pure && index == node.children.size - 1)
      end
      return
    end

    # A condition decides which branch runs; the branches are what the formula returns.
    if node.type == :if
      record_signs(node.children[0], sign, pure: false)
      node.children[1..].each { |branch| record_signs(branch, sign, pure: pure) }
      return
    end

    case node.type
    when :ivar
      field = node.children[0].to_s.delete_prefix("@")
      # @fund, @start_date, @end_date and the commitment's base fields are supplied by the
      # engine, not produced by another formula. They are arguments, so finding one inside a
      # helper call says nothing about whether the formula adds its terms up.
      unless engine_input?(field)
        @signs["@#{field}"] ||= sign
        @additive = false unless pure
      end
    when :send
      if WINDOW_HELPERS.key?(node.children[1].to_s) || ENTRY_READERS.include?(node.children[1].to_s)
        @signs[node.location.expression&.source.to_s] ||= sign
        @additive = false unless pure
      end
    end

    # Anything below a node that is not itself a sum is reached impurely.
    node.children.each { |child| record_signs(child, sign, pure: false) }
  end

  def walk(node)
    return unless node.is_a?(Parser::AST::Node)

    case node.type
    when :ivar then record_ivar(node)
    when :send then record_send(node)
    when :lvar then @bare_identifiers << node.children[0].to_s
    end

    node.children.each { |child| walk(child) }
  end

  # @fund / @start_date / @end_date and the commitment's always-available base fields are inputs
  # the engine supplies, not entries produced by another formula — there is nothing behind them
  # to open.
  def record_ivar(node)
    field = node.children[0].to_s.delete_prefix("@")
    if engine_input?(field)
      @input_names << field
    else
      @field_names << field
    end
  end

  def engine_input?(field)
    AccountEntryAllocation::AllocationBaseOperation::ENGINE_PROVIDED_FIELDS.include?(field) ||
      AccountEntryAllocation::CommitmentCache::BASE_FIELDS.include?(field)
  end

  def record_send(node)
    method = node.children[1].to_s
    return record_window_helper(node, method) if WINDOW_HELPERS.key?(method)
    return record_named_read(node) if ENTRY_READERS.include?(method)
    return record_name_filter(node) if method == "where"

    # A bare identifier parses as a method call with no receiver until the parser has seen it
    # assigned; the derived Quarterly/YTD/Since Inception entries the engine writes end in one
    # (".quarterly('X', …) + x"), so they matter.
    @bare_identifiers << method if node.children[0].nil? && node.children.size == 2
  end

  def record_window_helper(node, method)
    name = literal_or_nil(node.children[2])
    entry_type = literal_or_nil(node.children[3])
    source = node.location.expression&.source.to_s

    # Neither argument is a literal string — the name is decided at run time and no amount of
    # reading the text will say which entries were summed.
    if name == :not_literal || entry_type == :not_literal || (name.nil? && entry_type.nil?)
      @unresolved << source
      return
    end

    @helper_calls << HelperCall.new(helper: method, name: name, entry_type: entry_type,
                                    source: source, window: WINDOW_HELPERS.fetch(method))
  end

  # get_account_entry_or_zero("Ending Unfunded Commitment", @end_date.beginning_of_quarter - 1)
  def record_named_read(node)
    name = literal_or_nil(node.children[2])
    source = node.location.expression&.source.to_s
    if name.nil? || name == :not_literal
      @unresolved << source
      return
    end

    @named_reads << NamedRead.new(name: name, source: source,
                                  date_source: node.children[3]&.location&.expression&.source.to_s)
  end

  # `…account_entries.where(name: "Management Fees", …)` — the other way a formula names the
  # entries it reads.
  def record_name_filter(node)
    node.children[2..].each do |argument|
      next unless argument.is_a?(Parser::AST::Node) && argument.type == :hash

      argument.children.each do |pair|
        next unless pair.type == :pair && pair.children[0].children[0].to_s == "name"

        value = pair.children[1]
        case value.type
        when :str then @name_filters << value.children[0]
        when :array then value.children.each { |element| @name_filters << element.children[0] if element.type == :str }
        end
      end
    end
  end

  # A string literal, an explicit nil, or :not_literal for anything computed.
  def literal_or_nil(node)
    return nil if node.nil?

    case node.type
    when :str then node.children[0]
    when :nil then nil
    else :not_literal
    end
  end
end
