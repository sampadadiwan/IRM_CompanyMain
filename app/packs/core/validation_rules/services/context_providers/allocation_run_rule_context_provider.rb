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
      prev_run_date:                prev&.created_at&.to_date,
      missing_valuation_companies:  end_dt && missing_valuation_companies(record, end_dt, n_days),
      missing_fx_rates:             end_dt && missing_fx_rates(record, entity, end_dt, n_days),
      account_entries_exist:        end_dt && account_entries_exist?(record, end_dt, n_days, params["account_entry_names"])
    }
  end

  private

  def find_previous_run(record, entity)
    scope = AllocationRun.where(entity:, fund_id: record.fund_id)
    scope = scope.where.not(id: record.id) if record.persisted?
    scope.order(created_at: :desc).first
  end

  # Returns a comma-separated string of portfolio company names that have no valuation
  # (owner_type: Investor) within [end_date - n_days, end_date].
  # Returns nil when the fund has no portfolio investments (rule not applicable).
  # Returns nil (empty result) when all companies have valuations — rule does not fire.
  def missing_valuation_companies(record, end_date, n_days)
    return nil unless record.fund_id.present?

    pc_ids = PortfolioInvestment.where(fund_id: record.fund_id)
                                .distinct
                                .pluck(:portfolio_company_id)
    return nil if pc_ids.empty?

    since = end_date - n_days.days

    # Collect IDs of portfolio companies with at least one valuation in the window
    valued_ids = Valuation.unscoped
                          .where(owner_type: "Investor", owner_id: pc_ids)
                          .where(valuation_date: since..end_date)
                          .distinct
                          .pluck(:owner_id)
                          .to_set

    missing_ids = pc_ids.reject { |id| valued_ids.include?(id) }
    return nil if missing_ids.empty?

    # Resolve names in one query and return as a readable comma-separated string
    Investor.where(id: missing_ids).pluck(:investor_name).join(", ")
  end

  # Returns a comma-separated string describing each missing FX rate and who needs it.
  # Format: "USD → INR (USStock, feeder: Offshore Fund), INR → USD (tracking currency)"
  #
  # Three sources are checked:
  #   instruments  — instrument.currency → fund.currency, labelled by instrument name
  #   feeders      — feeder.currency → fund.currency, labelled "feeder: <name>"
  #   tracking     — fund.currency → fund.tracking_currency, labelled "tracking currency"
  #
  # When multiple sources share the same (from, to) pair their labels are merged.
  # Returns nil when no foreign currencies exist (nothing to check) or all rates are present.
  def missing_fx_rates(record, entity, end_date, n_days)
    return nil unless record.fund_id.present?

    fund = Fund.find_by(id: record.fund_id)
    return nil unless fund

    since = end_date - n_days.days

    # Accumulate named sources per (from, to) pair
    sources = Hash.new { |h, k| h[k] = [] }

    fund.investment_instruments
        .reject { |i| i.currency.blank? || i.currency == fund.currency }
        .group_by(&:currency)
        .each do |currency, instruments|
      sources[[currency, fund.currency]].concat(instruments.map(&:name).uniq)
    end

    fund.feeder_funds
        .reject { |f| f.currency.blank? || f.currency == fund.currency }
        .group_by(&:currency)
        .each do |currency, feeders|
      sources[[currency, fund.currency]].concat(feeders.map { |f| "feeder: #{f.name}" }.uniq)
    end

    sources[[fund.currency, fund.tracking_currency]] << "tracking currency" if fund.has_tracking_currency?

    return nil if sources.empty?

    missing = sources.reject do |(from, to), _|
      ExchangeRate.where(entity_id: entity.id, from:, to:)
                  .where(as_of: since..end_date)
                  .exists?
    end

    return nil if missing.empty?

    missing.map { |(from, to), labels| "#{from} → #{to} (#{labels.join(', ')})" }.join(", ")
  end

  # Returns true if all required account entries (named in the CSV param) are present
  # for the fund with reporting_date in [end_date - n_days, end_date].
  # Returns nil when no account_entry_names param is configured.
  def account_entries_exist?(record, end_date, n_days, names_csv)
    return nil if names_csv.blank?
    return nil unless record.fund_id.present?

    names = names_csv.to_s.split(",").map(&:strip).reject(&:blank?)
    return nil if names.empty?

    since = end_date - n_days.days

    # All named entries must be present — check each required name exists at least once
    names.all? do |name|
      AccountEntry.where(fund_id: record.fund_id, name: name, capital_commitment_id: nil)
                  .where(reporting_date: since..end_date)
                  .exists?
    end
  end
end
