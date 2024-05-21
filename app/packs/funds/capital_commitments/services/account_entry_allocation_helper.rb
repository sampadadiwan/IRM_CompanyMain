class AccountEntryAllocationHelper
  # This is to split the formula and retain the delimiters
  # See https://stackoverflow.com/questions/18089562/how-do-i-keep-the-delimiters-when-splitting-a-ruby-string
  # This is used for simple formulas, see print_formula() below
  FORMULA_DELIMS = %r{([%*+\-/()?:])}
  # This one is used for complex formulas, where we need to split on spaces
  FORMULA_DELIMS_WITH_SPACES = %r{( [%*+\-/()?:] )}
  # These are just random delimiters, used to split the formula, which seem to work sometimes :(
  FORMULA_DELIMS_NO_PAREN = %r{([%*+\-/?:])}
  FORMULA_DELIMS_NO_PAREN_NO_COLON = %r{([%*+\-/?])}

  def initialize(engine, fund, start_date, end_date, user_id: nil)
    @engine = engine
    @fund = fund
    @start_date = start_date
    @end_date = end_date
    @user_id = user_id
    # This is the cache for storing expensive computations used across the formulas
    @cached_generated_fields = {}
  end

  # Remove all prev allocations for this period, as we will recompute it
  def cleaup_prev_allocation(rule_for: nil)
    ae = AccountEntry.where(fund_id: @fund.id, generated: true, reporting_date: @start_date..).where(reporting_date: ..@end_date)

    ae = ae.where(rule_for:) if rule_for.present?

    ae.update_all(deleted_at: Time.zone.now)
    notify("Cleaned up prev allocated entries", :success, @user_id)
  end

  # generate the SOAs if the user has requested it, kick off SOA generation jobs
  def generate_soa(template_name)
    @fund.capital_commitments.each do |capital_commitment|
      CapitalCommitmentSoaJob.perform_later(capital_commitment.id, @start_date.to_s, @end_date.to_s, user_id: @user_id, template_name:)
    end
    # notify("Done Genrating SOAs for #{@start_date} - #{@end_date}", :success, @user_id)
  end

  # generate the Fund ratios if the user has requested it, kick off FundRatiosJob
  def generate_fund_ratios
    FundRatiosJob.perform_now(@fund.id, nil, @end_date, @user_id, true)
    notify("Done generating fund ratios for #{@start_date} - #{@end_date}", :success, @user_id)
  end

  def notify(message, level, user_id)
    UserAlert.new(user_id:, message:, level:).broadcast if user_id.present?
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

      cached_commitment_fields["distributions"] = capital_commitment.capital_distribution_payments.where(payment_date: ..@end_date).sum(:amount_cents)

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
    cached_commitment_fields[account_entry.name.titleize.delete(' ').underscore] = account_entry.amount_cents
  end

  def print_formula(fund_formula, bdg)
    printable = ""
    # We try and parse out each formula to print it so its values can be explained
    [FORMULA_DELIMS, FORMULA_DELIMS_WITH_SPACES, FORMULA_DELIMS_NO_PAREN, FORMULA_DELIMS_NO_PAREN_NO_COLON].each do |delims|
      # We need to use the FORMULA_DELIMS_NO_PAREN only if we cant parse with the FORMULA_DELIMS
      # Sometimes function calls with params, fail to be parsed for printing
      printable_token = ""
      fund_formula.formula.split(delims).each do |token|
        # puts "token = #{token}"
        printable_token = token
        pt = token.strip.length > 1 ? safe_eval(token, bdg).to_s : token.to_s
        printable += " #{pt}"
      end
      # We have a printable formula with no errors, so break
      break
    rescue Exception => e
      Rails.logger.debug "##########Printable Error############"
      Rails.logger.debug fund_formula.formula
      Rails.logger.error printable_token
      Rails.logger.error e.message
      Rails.logger.debug "##########Printable Error############"
      printable = ""
    end
    Rails.logger.debug { "printable = #{printable}" }
    printable = safe_eval(fund_formula.formula, bdg).to_s if printable == ""
    printable
  end

  def safe_eval(eval_string, bdg)
    AccountEntry.transaction(requires_new: true) do
      eval(eval_string, bdg)
      # This is so that, nothing in the DB changes due to eval
      # TODO - Rollback is not working, need to investigate
      # raise ActiveRecord::Rollback
    end
  end
end
