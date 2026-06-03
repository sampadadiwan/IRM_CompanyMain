class FundFormula < ApplicationRecord
  include ForInvestor
  include Trackable.new

  # Make all models searchable
  update_index('fund_formula') { self if index_record? }

  TYPES = %w[AllocateMasterFundAccountEntry-Name AllocateMasterFundAccountEntryIndividual-Name AllocateMasterFundAccountEntry-EntryType AllocateMasterFundAccountEntryIndividual-EntryType AllocateAccountEntry-Name AllocateAccountEntryIndividual-Name AllocateAccountEntry-EntryType AllocateAccountEntryIndividual-EntryType AllocateAggregatePortfolios AllocatePortfolioInvestment AllocatePortfolioInvestment-Proforma AllocateMasterFundPortfolioInvestment AllocateMasterFundPortfolioInvestment-Proforma GenerateAccountEntry CumulateAccountEntry GenerateCustomField Percentage GeneratePortfolioNumbersForFund AllocateForPortfolioCompany AllocateForPortfolioCompany-Folio].sort.freeze

  STANDARD_COLUMNS = { "Sequence; num-col" => "sequence; num-col",
                       "Name; text-col" => "name; text-col",
                       "For; text-col" => "formula_for; text-col",
                       "Formula; text-col" => "formula; text-col",
                       "Entry Type; text-col" => "entry_type; text-col",
                       "Roll Up; text-col" => "roll_up; text-col",
                       "Enabled; text-col" => "enabled; text-col" }.freeze

  DEBUG_COLUMNS = { "Sequence; num-col" => "sequence; num-col",
                    "Name; text-col" => "name; text-col",
                    "For; text-col" => "formula_for; text-col",
                    "Template; text-col" => "template_field_name; text-col",
                    "Execution (ms); num-col" => "execution_time; num-col",
                    "Entry Type; text-col" => "entry_type; text-col",
                    "Roll Up; text-col" => "roll_up; text-col",
                    "Enabled; text-col" => "enabled; text-col" }.freeze

  belongs_to :fund, optional: true, touch: true
  belongs_to :entity, optional: true
  acts_as_list scope: %i[fund_id], column: :sequence

  enum :rule_for, { accounting: "Accounting", reporting: "Reporting" }

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :accounting, -> { where(rule_for: "Accounting") }
  scope :reporting, -> { where(rule_for: "Reporting") }
  scope :without_ai_description, -> { where(ai_description: [nil, ""]) }

  validates :rule_type, length: { maximum: 50 }
  validates :entry_type, length: { maximum: 60 }
  validates :name, length: { maximum: 125 }
  validates :formula, :entry_type, :name, :rule_type, presence: true
  normalizes :name, with: ->(name) { name.strip.squeeze(" ") }
  # remove non-breaking spaces
  normalizes :formula, with: ->(formula) { formula.strip.tr("\u00A0", ' ') }
  validates :tag_list, length: { maximum: 255 }

  scope :with_tags, ->(tags) { where(tags.map { |_tag| "fund_formulas.tag_list LIKE ?" }.join(" OR "), *tags.map { |tag| "%#{tag}%" }) }
  scope :templates, -> { where(is_template: true) }

  delegate :to_s, to: :name

  validate :formula_kosher?
  def formula_kosher?
    errors.add(:formula, "You cannot do CRUD operations in a formula") if formula.downcase.match?(SAFE_EVAL_REGEX)
  end

  def tag_list=(tags)
    self[:tag_list] = if tags.is_a?(Array)
                        tags.join(",")
                      else
                        tags
                      end
  end

  def tag_list
    self[:tag_list].split(",").map(&:strip) if self[:tag_list].present?
  end

  # Sometimes we just want to sample the commitments to check if all the formulas are ok
  def commitments(end_date, sample)
    cc = if fund.custom_fields[:sample_commitment_ids_for_allocation].present?
           fund.capital_commitments.where(id: fund.custom_fields[:sample_commitment_ids_for_allocation].split(",").map(&:strip))
         else
           fund.capital_commitments.where(commitment_date: ..end_date)
         end
    logger.debug "Sampling 1 commitment" if sample
    sample ? cc.limit(3) : cc
  end

  def template_field_name
    name.titleize.delete(' :,;').underscore
  end

  def interpolate_formula(eval_string: nil)
    # Regular expression to match variable names

    statement = eval_string || formula

    # Define a regular expression to match different types of variables
    # variable_regex = /[@$]?[a-z_][a-zA-Z_0-9]*\b/
    # Define a regex to match only instance variables (starting with @)
    variable_regex = /@[\w_]+\b/

    # Extract all potential variables from the statement
    potential_variables = statement.scan(variable_regex)

    # Filter out method calls by checking if they are followed by an opening parenthesis
    variables = potential_variables.select { |var| statement.scan(/#{Regexp.escape(var)}\s*\(/).empty? }

    # Remove any potential duplicates
    variables.uniq
  end

  # Evaluates a formula against a live binding and returns an ordered Hash of
  # { expression_string => evaluated_value } pairs suitable for display and LLM
  # explanation. The result is stored as explanation[2] on the AccountEntry.
  #
  # Design goals
  # ------------
  # 1. One logical step per entry — the map should read like a plain-English
  #    walkthrough of the formula, not a dump of every Ruby sub-expression.
  # 2. Insertion order preserved — entries appear in the order a reader encounters
  #    them in the formula so downstream consumers (UI table, LLM prompt) can
  #    present them without re-sorting.
  # 3. No noise — class constants (PortfolioInvestment), bare string literals
  #    ("Total "), AR::Relation objects, and other non-scalar values that carry no
  #    information for the end user are filtered by skip_statement.
  #
  # Two code paths based on formula shape
  # --------------------------------------
  # MULTI-STATEMENT (:begin AST root — formulas using ; or newlines)
  #   Before this approach the old recursive walker extracted every sub-expression
  #   from every method chain, producing 20+ entries for a 6-line formula: partial
  #   chains, redundant string literals, class name constants, and intermediate
  #   .sub() calls that all produced the same value. The LLM received noise instead
  #   of a narrative.
  #
  #   New approach — two passes:
  #   Pass 1 (inputs): collect_ivar_expressions finds every @ivar and one-level
  #     attribute read (@fund.id, @fund.master_fund_id, @end_date). These are the
  #     external context the formula receives — shown as "Input Variables" in the UI.
  #   Pass 2 (steps): walk only the top-level AST nodes (one per formula line):
  #     - :lvasgn  → use the variable NAME as the key (e.g. "all_portfolio_company_ids")
  #                  The value comes from evaluating the name in the binding AFTER the
  #                  full formula has already been eval'd, so it's always the final
  #                  assigned value for that variable.
  #     - :ivasgn  → "@variable_name" key, same approach.
  #     - anything else → the full source expression (typically the final result line).
  #   Result: 9 clean entries for a 6-line formula instead of 21 noisy ones.
  #
  # SINGLE-EXPRESSION (:send/:op etc. AST root — one-liner formulas)
  #   e.g. "@committed_capital * @fee_rate / 365 * @days_in_period"
  #   There are no named intermediate variables, so sub-expressions ARE the steps.
  #   The original recursive find_expressions walk is kept here: it extracts every
  #   operand and intermediate product so the LLM can explain each multiplication,
  #   division, etc. in turn.
  #
  # Array values
  # ------------
  # Previously any expression evaluating to an Array was silently dropped by
  # skip_statement, so key filtering variables like all_portfolio_company_ids
  # never appeared in the breakdown at all. Now summarise_array converts them to
  # a readable "N portfolio companies: [...]" string before the skip check, so
  # they are included and the LLM knows what was actually filtered.
  def parse_statement(binding, external_formula: nil)
    statement = external_formula || formula
    buffer    = Parser::Source::Buffer.new('(string)')
    buffer.source = statement
    ast       = Parser::CurrentRuby.new.parse(buffer)

    expression_map = {}

    # rubocop:disable Style/RescueStandardError
    if ast.type == :begin
      # Pass 1 — instance-variable inputs (external context, not derived by formula)
      ivar_exprs = []
      collect_ivar_expressions(ast, ivar_exprs)
      ivar_exprs.uniq.each do |exp|
        begin
          val = eval(exp, binding)
          val = summarise_array(val, exp)  if val.is_a?(Array)
          val = summarise_record(val)      if val.is_a?(ApplicationRecord)
          expression_map[exp] = val unless skip_statement(exp, val)
        rescue
          # Silently skip — the ivar may not be set in this particular binding context
        end
      end

      # Pass 2 — walk top-level statements in formula order, per-node strategy:
      #
      # ASSIGNMENT nodes (:lvasgn / :ivasgn)
      #   Use the variable name as the key.  The RHS expression can be arbitrarily
      #   complex, but naming it is what the formula author intended — showing the
      #   name and its value is what makes the breakdown readable (e.g. "fx_rate → 85.0"
      #   rather than "ExchangeRate.get_rate(api.investment_instrument.currency, ...)").
      #
      # BARE EXPRESSION nodes (anything else — typically the final result line)
      #   Apply the same recursive sub-expression extraction used for single-expression
      #   formulas.  This is essential when the final line is a multi-operand arithmetic
      #   expression like:
      #     api.unrealized_gain_cents * (10.0 / 100) * fx_rate * commitment.percentage / 100
      #   Without recursion that entire line appears as one opaque entry and the
      #   breakdown loses all intermediate values (gain, rate, percentage) that explain
      #   how the result was reached.
      ast.children.each do |node|
        case node.type
        when :lvasgn, :ivasgn
          exp = node.type == :lvasgn ? node.children[0].to_s : "@#{node.children[0]}"
          next if exp.blank? || exp.include?("SkipRule")
          begin
            val = eval(exp, binding)
            val = summarise_array(val, exp)  if val.is_a?(Array)
            val = summarise_record(val)      if val.is_a?(ApplicationRecord)
            expression_map[exp] = val unless skip_statement(exp, val)
          rescue
            logger.error "Error evaluating expression '#{exp}'"
          end
        else
          exprs = []
          find_expressions(node, exprs)
          exprs.uniq.each do |exp|
            next if exp.include?("SkipRule")
            begin
              val = eval(exp, binding)
              val = summarise_array(val, exp)  if val.is_a?(Array)
              val = summarise_record(val)      if val.is_a?(ApplicationRecord)
              expression_map[exp] = val unless skip_statement(exp, val)
            rescue
              logger.error "Error evaluating expression '#{exp}'"
            end
          end
        end
      end
    else
      # Single-expression formula: recursively extract sub-expressions so every
      # intermediate computation is visible (e.g. each operand in a fee calculation).
      exprs = []
      find_expressions(ast, exprs)
      exprs.uniq.each do |exp|
        next if exp.include?("SkipRule")
        begin
          val = eval(exp, binding)
          val = summarise_array(val, exp)  if val.is_a?(Array)
          val = summarise_record(val)      if val.is_a?(ApplicationRecord)
          expression_map[exp] = val unless skip_statement(exp, val)
        rescue
          logger.error "Error evaluating expression '#{exp}'"
        end
      end
    end
    # rubocop:enable Style/RescueStandardError

    expression_map
  end

  # Rebuilds the formula breakdown for an existing AccountEntry and persists it.
  # Use this when the breakdown is stale (e.g. after a parse_statement logic change)
  # without needing to re-run a full allocation.
  #
  # Two-step eval approach — why both evals are required:
  #   Step 1: eval(formula, bdg) runs the formula so local variables defined inside
  #     it (e.g. all_portfolio_company_ids, result_ids) are populated in the binding.
  #     Without this, evaluating those variable names in parse_statement's pass 2
  #     would raise NameError — they don't exist until the formula has executed.
  #   Step 2: parse_statement(bdg, ...) walks the now-populated binding to extract
  #     the value of each named variable and the final expression.
  #
  # Result pinning — why the result key is overwritten with amount_cents:
  #   Step 1 re-evaluates the formula against the CURRENT database state, which may
  #   differ from when the allocation originally ran (other entries added since then,
  #   data corrections, etc.). Using the live re-eval as the "final result" would
  #   make the conclusion disagree with the stored amount_cents on the AccountEntry.
  #   Pinning to amount_cents keeps the breakdown consistent with what was actually
  #   persisted and avoids confusing end users.
  #
  # Parent-derived locals — why parent_type drives the binding setup:
  #   Each allocation operation places different local variables in scope before
  #   passing `binding` to CreateAccountEntry:
  #     AllocateAggregatePortfolios  → api (as_of snapshot), orig_api
  #     AllocatePortfolioInvestments → portfolio_investment
  #     AllocateForPortfolioCompany  → portfolio_company
  #     AllocateEntry / AllocateAccountEntries → fund_account_entry
  #   We infer which set is needed from account_entry.parent_type and reconstruct
  #   them here so the formula eval doesn't raise NameError.
  #   Note: api is set to parent.as_of(end_date) matching AllocateAggregatePortfolios,
  #   which stores the snapshotted object rather than the raw DB record.
  #
  # end_date / start_date as locals — why both forms are set:
  #   Allocation operations expose end_date and start_date as plain local variables
  #   in the binding (from ctx[:end_date]) in addition to the @end_date / @start_date
  #   instance variables set by create_instance_variables. Formulas use both forms
  #   interchangeably, so we expose both.
  #
  # @start_date note — derived from the period string (e.g. "Q1-2025" → 2025-01-01).
  #   This assumes calendar-aligned quarters. For funds with non-calendar fiscal years
  #   this will be wrong, but @start_date is often unused in the formula so the
  #   breakdown is still correct in practice.
  def reparse_and_save(account_entry)
    capital_commitment = account_entry.capital_commitment
    fund_formula       = self
    @fund              = account_entry.fund
    @end_date          = account_entry.reporting_date

    quarter, year = account_entry.period.split('-')
    q             = quarter.delete('Q').to_i
    @start_date   = Date.new(year.to_i, (q - 1) * 3 + 1, 1)

    # Expose as plain locals too — formulas use end_date and start_date
    # (not just @end_date / @start_date) depending on which operation ran them.
    end_date   = @end_date
    start_date = @start_date

    # Set up parent-derived locals that the originating allocation operation
    # would have had in scope when it passed binding to CreateAccountEntry.
    parent = account_entry.parent
    case account_entry.parent_type
    when 'AggregatePortfolioInvestment'
      orig_api = parent
      api      = parent.respond_to?(:as_of) ? parent.as_of(end_date) : parent
    when 'PortfolioInvestment'
      portfolio_investment = parent
    when 'Investor'
      portfolio_company = parent
    when 'AccountEntry'
      fund_account_entry = parent
    end

    formula = account_entry.explanation.first
    return false if formula.blank?

    bdg = binding
    # rubocop:disable Security/Eval
    eval(formula, bdg)   # Step 1: populate formula-defined local variables in the binding
    # rubocop:enable Security/Eval

    breakdown  = parse_statement(bdg, external_formula: formula)   # Step 2: extract values
    result_key = breakdown.max_by { |k, _| k.length }&.first
    breakdown[result_key] = account_entry.amount_cents.to_s if result_key  # pin to stored value

    account_entry.explanation[2] = breakdown.to_json
    account_entry.save!(validate: false)
    breakdown
  end

  # Decides whether an expression+value pair should be excluded from the breakdown.
  #
  # Excluded categories:
  # - AR objects / relations / proxies — not serialisable and carry no scalar meaning
  # - Bare string literals ("Total ", "Master Fund ") — the expression IS the value;
  #   showing both sides adds no information. Previously these slipped through because
  #   the old check stripped quotes and compared without stripping the value side,
  #   so "Total " (with trailing space) never matched "Total" (stripped expression).
  #   Fixed by stripping both sides and removing both quote character types.
  # - Self-naming constants (PortfolioInvestment → "PortfolioInvestment") — class
  #   references used as method receivers; their "value" is just their own name.
  def skip_statement(exp, val)
    # AR::Relation and proxy types are implementation internals — not useful to display.
    # Plain ApplicationRecord instances are now converted to "ClassName: to_s" by
    # summarise_record before this check, so they are no longer filtered here.
    return true if val.is_a?(OpenStruct) || val.is_a?(CustomFieldsProxy) ||
                   val.is_a?(ActiveRecord::Relation) || val.is_a?(ActiveRecord::QueryMethods::WhereChain)
    return true if exp.strip.match?(/\A["'].*["']\z/)   # bare string literal
    exp.delete("\"'").strip == val.to_s.strip            # self-naming constant / class constant
  end

  # Collects @ivar reads and one-level attribute reads (@fund.id, @fund.master_fund_id)
  # from anywhere in the AST, used to build the "Input Variables" section.
  #
  # Why stop at one level:
  #   Deeper chains like @fund.capital_commitments.active would return AR::Relations
  #   (filtered by skip_statement anyway) and add noise. One level covers all real
  #   input values used in formulas (@fund.id, @fund.master_fund_id, @fund.currency).
  #
  # Why not early-return on all :send nodes:
  #   Expressions like [@fund.id, @fund.master_fund_id].compact have a :send node
  #   (.compact) whose receiver is an :array, not an :ivar. If we returned on every
  #   :send we would never recurse into the array's children and would miss @fund.id
  #   and @fund.master_fund_id entirely. We only stop recursion when we have already
  #   captured the expression (receiver IS an :ivar).
  def collect_ivar_expressions(node, exprs)
    case node.type
    when :ivar
      exprs << node.loc.name.source
    when :send
      if node.children[0]&.type == :ivar
        exprs << node.loc.expression.source   # e.g. "@fund.id"
        return                                # captured — no need to recurse deeper
      end
      # Receiver is not an @ivar (e.g. an array literal, another send) — keep
      # recursing so nested @ivar reads inside compound expressions are found.
    end
    node.children.each { |c| collect_ivar_expressions(c, exprs) if c.is_a?(Parser::AST::Node) }
  end

  # Converts an ApplicationRecord instance to a one-line descriptive string.
  #
  # Previously ALL ApplicationRecord objects were silently dropped by skip_statement.
  # That meant named context objects — capital_commitment, api,
  # portfolio_investment, fund_account_entry — never appeared in the breakdown,
  # so the explanation gave no indication of WHICH investor, portfolio company, or
  # fund entry the formula was operating on.
  #
  # By converting the object to "ClassName: to_s" before the skip check it is
  # preserved as a readable label. Internal proxy types (OpenStruct,
  # CustomFieldsProxy) and AR query objects (Relation, WhereChain) are still
  # filtered — they are implementation details, not business context.
  def summarise_record(record)
    "#{record.class.name}: #{record}"
  end

  # Converts an Array value to a human-readable count + preview string.
  #
  # Previously any expression that evaluated to an Array was silently dropped by
  # skip_statement (val.is_a?(Array) returned true). Key filtering variables like
  # all_portfolio_company_ids, master_fund_portfolio_company_ids, and result_ids
  # therefore never appeared in the breakdown, so neither the UI table nor the LLM
  # prompt knew what was actually being filtered — making the explanation incomplete.
  #
  # By converting to a string before the skip check, arrays are preserved as a
  # readable summary. The label is inferred from the expression/variable name so
  # "19 portfolio companies: [814, ...]" is shown instead of "19 IDs: [814, ...]".
  def summarise_array(arr, expression)
    label = case expression.to_s
            when /portfolio_company/i then "portfolio companies"
            when /investor/i          then "investors"
            when /commitment/i        then "commitments"
            when /fund/i              then "funds"
            else                           "items"
            end
    "#{arr.length} #{label}: #{arr.first(5).inspect}#{arr.length > 5 ? ' ...' : ''}"
  end

  def find_expressions(node, expressions)
    case node.type
    when :send
      expressions << node.loc.expression.source
    when :lvar, :ivar, :const
      expressions << node.loc.name.source
    when :str
      expressions << node.loc.expression.source
    end

    node.children.each do |child|
      find_expressions(child, expressions) if child.is_a?(Parser::AST::Node)
    end
  end

  def meta_data_hash
    @mdh ||= meta_data.split(";").to_h { |pair| pair.split("=", 2) } if meta_data
    @mdh
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name description formula rule_type entry_type rule_for tag_list meta_data ai_description sequence enabled roll_up].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund].sort
  end

  # rubocop:disable Rails/SkipsModelValidations
  def self.update_formulas_to_json_fields(fund_id)
    FundFormula.where(fund_id: fund_id).find_each do |ff|
      next if ff.formula.blank?

      new_formula = ff.formula
                      .gsub(/custom_fields\.(?!send\()([a-zA-Z0-9_]+)/, "json_fields['\\1']")
                      .gsub(/custom_fields\.send\((.+?)\)/, 'json_fields[\1]')
                      .gsub(".properties[", ".json_fields[")
                      .gsub("fund.account_entries_sqlite_sqlite.", "fund.account_entries_sqlite.")
                      .gsub("last.amount_cents", "last&.amount_cents || 0")
                      .gsub("last_amount_cents", "last&.amount_cents")
                      .gsub("amount_cents || 0))", "amount_cents || 0)")
                      .gsub("where(name: (fund_formula.name,parent_type", "where(name: fund_formula.name,parent_type")
                      .gsub('+ fund.account_entries_sqlite.fund_entries.cumulative.where(name: fund_formula.name,parent_type: "Investor", parent_id: portfolio_company.id, reporting_date: ..@end_date).order(:reporting_date).last&.amount_cents || 0)', '+ (fund.account_entries_sqlite.fund_entries.cumulative.where(name: fund_formula.name,parent_type: "Investor", parent_id: portfolio_company.id, reporting_date: ..@end_date).order(:reporting_date).last&.amount_cents || 0)')
                      # .gsub('capital_commitment.account_entries.cumulative.where(name: fund_formula.name,parent_type: "Investor", parent_id: portfolio_company.id, reporting_date: ..@end_date).order(:reporting_date).last&.amount_cents || 0', '(capital_commitment.account_entries.cumulative.where(name: fund_formula.name,parent_type: "Investor", parent_id: portfolio_company.id, reporting_date: ..@end_date).order(:reporting_date).last&.amount_cents || 0)')
                      # .gsub('fund_formula.name,parent_type: "Investor", parent_id: portfolio_company.id, reporting_date: ..@end_date).order(:reporting_date).last&.amount_cents || 0', '(fund_formula.name,parent_type: "Investor", parent_id: portfolio_company.id, reporting_date: ..@end_date).order(:reporting_date).last&.amount_cents || 0)')
                      # .gsub("capital_commitment.account_entries", "capital_commitment.account_entries_sqlite")
                      .gsub("fund.account_entries.", "fund.account_entries_sqlite.")
                      .gsub("AccountEntry.total_amount", "AccountEntrySqlite.total_amount")
                      .gsub("where(parent: portfolio_investment)", "where(parent_id: portfolio_investment.id, parent_type: 'PortfolioInvestment')")
                      .gsub("for_portfolio_investments.where(portfolio_investments: { fund_id: fund.id })", "for_portfolio_investments.where(parent_id: fund.portfolio_investment_ids).")
                      .gsub("for_pi_portfolio_company(portfolio_company.id).where(portfolio_investments: { portfolio_company_id: include_portfolio_company_ids, fund_id: fund.id })", "for_pi_portfolio_company(portfolio_company.id).where(parent_id: fund.portfolio_investment_ids)")

      ff.update_column(:formula, new_formula) if new_formula != ff.formula
    end
  end

  def self.update_skip_portfolio_company(fund_id)
    FundFormula.where(fund_id:).where("formula like '%skip_portfolio_company_ids = [7700,7704,7705,7706];%'").find_each do |ff|
      ff.meta_data ||= ""
      ff.meta_data += ";where='investors.id not in (7700,7704,7705,7706)'"
      ff.save
    end

    FundFormula.where(fund_id:).where("formula like '%include_portfolio_company_ids = [7700,7704,7705,7706];%'").find_each do |ff|
      ff.meta_data ||= ""
      ff.meta_data += ";where='investors.id not in (7700,7704,7705,7706)'"
      ff.save
    end

    FundFormula.where(fund_id: fund_id).find_each do |ff|
      next if ff.formula.blank?

      new_formula = ff.formula
                      .gsub("skip_portfolio_company_ids = [7700,7704,7705,7706];", "")
                      .gsub('raise SkipRule.new("Not our intended Portfolio company") if skip_portfolio_company_ids.include?(portfolio_company.id);', "")
                      .gsub("include_portfolio_company_ids = [7700,7704,7705,7706];", "")
                      .gsub('raise SkipRule.new("Not our intended Portfolio company") unless include_portfolio_company_ids.include?(portfolio_company.id);', "")

      ff.update_column(:formula, new_formula) if new_formula != ff.formula
    end
  end

  # rubocop:enable Rails/SkipsModelValidations
end
