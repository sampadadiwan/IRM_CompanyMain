# Provides named context values for AllocationRun rules.
#
# Context keys returned:
#   prev_run_date                — date of the most recent prior allocation run for the same fund
#   missing_valuation_companies  — comma-separated names of portfolio companies with no valuation in the n_days window,
#                                  nil when not applicable (no portfolio investments or end_date missing)
#   missing_fx_rates             — comma-separated labelled pairs missing a rate in the window, e.g.
#                                  "USD → INR (USStock, feeder: Offshore Fund), INR → USD (tracking currency)"
#                                  nil when not applicable or all rates are present
#   account_entries_exist        — true/false/nil: whether required account entries (by name CSV) exist within n_days
#
# nil means "not applicable" (rule should not fire); a non-blank string / false means the check failed.
class AllocationRunRuleContextProvider
  # @param record [AllocationRun]
  # @param entity [Entity]
  # @param params [Hash]  resolved rule params (e.g. "n_days", "account_entry_names")
  # @return [Hash] symbol-keyed context values
  def call(record:, entity:, params: {})
    prev   = find_previous_run(record, entity)
    n_days = params.fetch("n_days", 30).to_i
    end_dt = record.end_date.presence&.to_date

    {
      prev_run_date: prev&.created_at&.to_date,
      missing_valuation_companies: end_dt && missing_valuation_companies(record, end_dt, n_days),
      missing_fx_rates: end_dt && missing_fx_rates(record, entity, end_dt, n_days),
      account_entries_exist: end_dt && account_entries_exist?(record, end_dt, n_days, params["account_entry_names"])
    }
  end

  private

  def find_previous_run(record, entity)
    scope = AllocationRun.where(entity:, fund_id: record.fund_id)
    scope = scope.where.not(id: record.id) if record.persisted?
    scope.order(created_at: :desc).first
  end

  # Comma-separated names of held portfolio companies with no valuation in the window.
  # nil when the fund has no active position (rule not applicable) or every company is valued.
  # The rules themselves live in AllocationRunReadiness, shared with the fund-level pre-run checks.
  def missing_valuation_companies(record, end_date, n_days)
    return nil if record.fund_id.blank?

    fund = Fund.find_by(id: record.fund_id)
    return nil unless fund

    missing = AllocationRunReadiness.new(fund:, entity_id: record.entity_id, end_date:, n_days:).missing_valuation_companies
    missing.presence&.map(&:last)&.join(", ")
  end

  # Each missing FX rate and who needs it, e.g.
  # "USD → INR (USStock, feeder: Offshore Fund), INR → USD (tracking currency)".
  # nil when the fund needs no foreign rate or every rate is present. See AllocationRunReadiness.
  def missing_fx_rates(record, entity, end_date, n_days)
    return nil if record.fund_id.blank?

    fund = Fund.find_by(id: record.fund_id)
    return nil unless fund

    missing = AllocationRunReadiness.new(fund:, entity_id: entity.id, end_date:, n_days:).missing_fx_rates
    return nil if missing.blank?

    missing.map { |(from, to), labels| "#{from} → #{to} (#{labels.join(', ')})" }.join(", ")
  end

  # Returns true if all required account entries (named in the CSV param) are present
  # for the fund with reporting_date in [end_date - n_days, end_date].
  # Returns nil when no account_entry_names param is configured.
  def account_entries_exist?(record, end_date, n_days, names_csv)
    return nil if names_csv.blank?
    return nil if record.fund_id.blank?

    names = names_csv.to_s.split(",").map(&:strip).compact_blank
    return nil if names.empty?

    since = end_date - n_days.days

    # All named entries must be present — check each required name exists at least once
    names.all? do |name|
      AccountEntry.where(fund_id: record.fund_id, name: name, capital_commitment_id: nil)
                  .exists?(reporting_date: since..end_date)
    end
  end
end
