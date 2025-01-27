module AccountEntryAllocation
  ############################################################
  # 14. AllocateEntry Operation
  ############################################################
  class CommitmentCache
    def initialize(engine)
      @engine = engine
      @cached_generated_fields = {}
    end

    # This is used to cache the computed values during allocation.
    # Each commitment has its own set of cached values
    def computed_fields_cache(capital_commitment, end_date)
      cached_commitment_fields ||= {}
      # Check if we already have some cached fields for this commitment
      if @cached_generated_fields[capital_commitment.id]
        cached_commitment_fields = @cached_generated_fields[capital_commitment.id]
      else

        # Commitment remittance and dist
        cached_commitment_fields["remittances_collected"] = capital_commitment.capital_remittances.where(remittance_date: ..@end_date).sum(:collected_amount_cents)
        cached_commitment_fields["remittances_called"] = capital_commitment.capital_remittances.where(remittance_date: ..@end_date).sum(:call_amount_cents)
        cached_commitment_fields["remittance_capital_fees"] = capital_commitment.capital_remittances.where(remittance_date: ..@end_date).sum(:capital_fee_cents)
        cached_commitment_fields["remittance_other_fees"] = capital_commitment.capital_remittances.where(remittance_date: ..@end_date).sum(:other_fee_cents)

        cached_commitment_fields["distributions"] = capital_commitment.capital_distribution_payments.where(payment_date: ..@end_date).sum(:net_payable_cents)

        # Income and Expense
        cached_commitment_fields["income_before_start_date"] = AccountEntry.total_amount(capital_commitment.account_entries, entry_type: 'Income', end_date: @start_date)

        cached_commitment_fields["expense_before_start_date"] = AccountEntry.total_amount(capital_commitment.account_entries, entry_type: 'Expense', end_date: @start_date)

        # Portfolio fields
        cached_commitment_fields["units"] = capital_commitment.fund_units.where(issue_date: ..@end_date).sum(:quantity)

        date = end_date.month > 3 ? end_date.beginning_of_year : (end_date.beginning_of_year - 1.year)
        start_of_financial_year = (date + 3.months)
        cached_commitment_fields["start_of_financial_year"] = start_of_financial_year

        @cached_generated_fields[capital_commitment.id] = cached_commitment_fields
      end

      @engine.create_variables(cached_commitment_fields)
      # return the cached fields
      cached_commitment_fields
    end

    # This is used to simplify the formulas, use these variables inside the formulas
    def add_to_computed_fields_cache(capital_commitment, account_entry)
      @cached_generated_fields[capital_commitment.id] ||= {}
      cached_commitment_fields = @cached_generated_fields[capital_commitment.id]
      cached_commitment_fields[to_varable_name(account_entry.name)] = account_entry.amount_cents
    end

    def to_varable_name(name)
      name.strip.titleize.squeeze(" ").tr(" ", "_").underscore.gsub(/[^0-9A-Za-z_]/, '').squeeze("_")
    end
  end
end
