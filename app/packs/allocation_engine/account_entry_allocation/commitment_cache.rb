module AccountEntryAllocation
  ############################################################
  # 14. AllocateEntry Operation
  ############################################################
  class CommitmentCache
    def initialize(engine)
      @engine = engine
      @cached_generated_fields = {}
      @referenced_field_names = Set.new
      @last_consumer_index = {}
    end

    # Called once per run by RunFormulas after scanning every enabled formula's
    # source for @field references (FundFormula#referenced_field_names).
    # referenced_field_names: every field name some in-scope formula reads.
    # last_consumer_index: field name -> sequence-position of the LAST in-scope
    # formula that reads it, used by #formula_completed to evict early.
    def configure_dependencies(referenced_field_names, last_consumer_index)
      @referenced_field_names = referenced_field_names
      @last_consumer_index = last_consumer_index
    end

    # Fields always available to a formula regardless of what earlier formulas produced.
    # Keep this in sync with the literal keys assigned in #computed_fields_cache below --
    # FundFormulaDependencyGraph relies on this list to avoid flagging these as "no producer".
    BASE_FIELDS = %w[
      remittances_collected remittances_called remittance_capital_fees remittance_other_fees
      distributions income_before_start_date expense_before_start_date units start_of_financial_year
    ].freeze

    # This is used to cache the computed values during allocation.
    # Each commitment has its own set of cached values
    def computed_fields_cache(capital_commitment, start_date, end_date)
      cached_commitment_fields ||= {}
      # Check if we already have some cached fields for this commitment
      if @cached_generated_fields[capital_commitment.id]
        cached_commitment_fields = @cached_generated_fields[capital_commitment.id]
        # cached_commitment_fields["start_of_financial_year"] ||= capital_commitment.start_of_financial_year_date(start_date)
      else

        # Commitment remittance and dist
        cached_commitment_fields["remittances_collected"] = capital_commitment.capital_remittances.where(remittance_date: ..end_date).sum(:collected_amount_cents)
        cached_commitment_fields["remittances_called"] = capital_commitment.capital_remittances.where(remittance_date: ..end_date).sum(:call_amount_cents)
        cached_commitment_fields["remittance_capital_fees"] = capital_commitment.capital_remittances.where(remittance_date: ..end_date).sum(:capital_fee_cents)
        cached_commitment_fields["remittance_other_fees"] = capital_commitment.capital_remittances.where(remittance_date: ..end_date).sum(:other_fee_cents)

        cached_commitment_fields["distributions"] = capital_commitment.capital_distribution_payments.where(payment_date: ..end_date).sum(:net_payable_cents)

        # Income and Expense
        cached_commitment_fields["income_before_start_date"] = AccountEntrySqlite.total_amount(AccountEntrySqlite.where(capital_commitment_id: capital_commitment.id), entry_type: 'Income', end_date: start_date)

        cached_commitment_fields["expense_before_start_date"] = AccountEntrySqlite.total_amount(AccountEntrySqlite.where(capital_commitment_id: capital_commitment.id), entry_type: 'Expense', end_date: start_date)

        # Portfolio fields
        cached_commitment_fields["units"] = capital_commitment.fund_units.where(issue_date: ..end_date).sum(:quantity)

        cached_commitment_fields["start_of_financial_year"] = capital_commitment.start_of_financial_year_date(end_date)

        @cached_generated_fields[capital_commitment.id] = cached_commitment_fields
      end

      @engine.create_variables(cached_commitment_fields)
      # return the cached fields

      cached_commitment_fields
    end

    # This is used to simplify the formulas, use these variables inside the formulas.
    # Only actually caches the field if some later formula's source reads it
    # (@referenced_field_names) or the formula is explicitly flagged to force it
    # (fund_formula.add_to_commitment_cache) -- otherwise it's a value nothing will
    # ever read again, and caching it just grows @cached_generated_fields forever.
    #
    # The formula is read off ctx rather than taken as an argument: every caller runs
    # inside RunFormulas#execute_formula, which merges the formula being executed into
    # the sub-operation ctx, so ctx[:fund_formula] is always the right one. Passing it
    # separately just gave four call sites an extra argument to keep in sync.
    def add_to_computed_fields_cache(ctx, capital_commitment, account_entry)
      fund_formula = ctx[:fund_formula]
      field_name = to_varable_name(account_entry.name)
      return unless fund_formula&.add_to_commitment_cache || @referenced_field_names.include?(field_name)

      cached_commitment_fields = computed_fields_cache(capital_commitment, ctx[:start_date], ctx[:end_date])
      cached_commitment_fields[field_name] = account_entry.amount_cents
    end

    # Called by RunFormulas once a formula (at the given sequence-position) has
    # finished running for every commitment. Drops any cached field whose last
    # known reader was that formula, so memory reflects "fields still awaiting a
    # reader" rather than every field ever computed across the whole run.
    # Fields cached only because of the manual add_to_commitment_cache flag, with no
    # detected reader, are never in @last_consumer_index and so are never evicted --
    # we can't prove nothing still needs them.
    def formula_completed(formula_index)
      field_names_to_evict = @last_consumer_index.select { |_name, idx| idx == formula_index }.keys
      return if field_names_to_evict.empty?

      @cached_generated_fields.each_value do |fields|
        field_names_to_evict.each { |name| fields.delete(name) }
      end
    end

    delegate :to_varable_name, to: :FundFormula
  end
end
