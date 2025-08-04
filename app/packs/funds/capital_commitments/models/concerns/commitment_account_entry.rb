module CommitmentAccountEntry
  extend ActiveSupport::Concern

  # These are set by the SOA generator
  attr_accessor :start_date, :end_date

  def reset_committed_amount(new_folio_committed_amount)
    # Zero everything out
    self.committed_amount_cents = 0
    self.orig_committed_amount_cents = 0
    self.orig_folio_committed_amount_cents = 0
    self.folio_committed_amount_cents = 0
    # Set the folio_committed_amount
    self.folio_committed_amount_cents = new_folio_committed_amount
    # Call set_committed_amount
    set_committed_amount
    save
  end

  ###########################################################
  # Account Entry Stuff
  ###########################################################

  # In some cases name is nil - Ex Cumulative for portfolio FMV or costs @see AccountEntryAllocationEngine.allocate_portfolio_investments()
  #
  def rollup_account_entries(name, entry_type, start_date, end_date, save_now: false)
    Rails.logger.debug { "rollup_account_entries(#{name}, #{entry_type}, #{start_date}, #{end_date})" }

    # Remove the prev computed cumulative rollups
    deletable = account_entries.where(entry_type:, reporting_date: start_date..end_date, cumulative: true)
    deletable = deletable.where(name:) if name
    deletable.delete_all

    # Find the cum_amount_cents
    addable = account_entries.where(entry_type:, cumulative: false, reporting_date: ..end_date)
    addable = addable.where(name:) if name
    cum_amount_cents = addable.sum(:amount_cents)

    # Create a new Cumulative entry
    new_name = name || entry_type
    ae = account_entries.new(name: new_name, entry_type:, amount_cents: cum_amount_cents, entity_id:, fund_id:, investor_id:, folio_id:, reporting_date: end_date, period: "As of #{end_date}",
                             cumulative: true, generated: true)

    if save_now
      ae.save!
    else
      ae.validate!
    end
    ae
  end

  def cumulative_account_entry(name, entry_type, start_date, end_date, cumulative: true)
    cae = account_entries.where(cumulative:).order(reporting_date: :asc)
    cae = cae.where(reporting_date: start_date..) if start_date
    cae = cae.where(reporting_date: ..end_date) if end_date
    cae = cae.where(name:) if name
    cae = cae.where(entry_type:) if entry_type

    cae.last || AccountEntry.new(name:, fund_id:, amount_cents: 0)
  end

  def get_account_entry(name, date, raise_error: true)
    ae = account_entries.where(name:, reporting_date: ..date).order(reporting_date: :desc).first
    raise "No Account Entry found for #{name} on #{date}" if ae.nil? && raise_error

    ae
  end

  def get_account_entry_or_zero(name, date)
    ae = get_account_entry(name, date, raise_error: false)
    ae ||= AccountEntry.new(name:, entity_id:, fund_id:, amount_cents: 0)
    ae
  end

  def start_of_financial_year_date(end_date)
    # Some funds want to set the start of the financial year to Jan some to April, this allows for that.
    month_offset_for_fy = fund.custom_fields.month_offset_for_fy.present? ? fund.custom_fields.month_offset_for_fy.to_i : 3
    date = end_date.month > month_offset_for_fy ? end_date.beginning_of_year : (end_date.beginning_of_year - 1.year)
    (date + month_offset_for_fy.months)
  end

  def start_of_financial_year(name, _entry_type, end_date)
    get_account_entry(name, start_of_financial_year_date(end_date), raise_error: false)
  end

  def on_date(name, entry_type, end_date)
    entries = account_entries
    entries = entries.not_cumulative.where(name:) if name.present?
    entries = entries.where(entry_type:) if entry_type.present?

    entries.where(reporting_date: end_date).sum(:amount_cents)
  end
  alias as_on_date on_date

  def quarterly(name, entry_type, _start_date, end_date)
    entries = account_entries
    entries = entries.not_cumulative.where(name:) if name.present?
    entries = entries.where(entry_type:) if entry_type.present?

    entries.where(reporting_date: end_date.beginning_of_quarter..end_date).sum(:amount_cents)
  end
  alias period quarterly

  def since_inception(name, entry_type, _start_date, end_date)
    entries = account_entries
    entries = entries.not_cumulative.where(name:) if name.present?
    entries = entries.where(entry_type:) if entry_type.present?

    entries.not_cumulative.where(reporting_date: ..end_date).sum(:amount_cents)
  end

  def year_to_date(name, entry_type, _start_date, end_date)
    entries = account_entries
    entries = entries.not_cumulative.where(name:) if name.present?
    entries = entries.where(entry_type:) if entry_type.present?

    entries.not_cumulative.where(reporting_date: start_of_financial_year_date(end_date)..end_date).sum(:amount_cents)
  end

  def call_amount_cents_start_end(_start_date, _end_date, exclude_call_name: nil)
    total_cac = 0
    remittances = capital_remittances.joins(:capital_call)
    remittances = remittances.where.not(capital_calls: { name: exclude_call_name }) if exclude_call_name
    remittances = remittances.where(remittance_date: @start_date..@end_date)
    remittances.each do |cr|
      total_cac += cr.call_amount_cents
    end
    total_cac
  end


  # # Allocate FMV
  # CC, PI -> AE

  # @folio_investable_capital_percentage_wo_excused_folios = @investable_capital_account_entries.where(capital_commitment_id: cc.id, owner_id: pi.id, name: "Investable Capital Percentage for PI without excused folios").last

  # pi.fmv * @folio_investable_capital_percentage_wo_excused_folios

  # This method is used to calculate the percentage of investable capital for a portfolio investment which has excused folios
  # Calculates the percentage of investable capital for a portfolio investment,
  # excluding excused folios from the calculation.
  #
  # @param portfolio_investment [PortfolioInvestment] The portfolio investment object
  # @param start_date [Date] The start date for the calculation range
  # @param end_date [Date] The end date for the calculation range
  # @param account_entry_name [String] The name of the account entry to filter by Ex Investable Capital Percentage
  # @return [Float] The percentage of investable capital for the folio, excluding excused folios
  def excused_folio_percentage(portfolio_investment, start_date, end_date, account_entry_name)
    # Get the fund associated with the portfolio investment
    fund = portfolio_investment.fund

    # Fetch all generated account entries for the fund within the date range and with the given name
    investable_capital_account_entries = fund.account_entries.generated.where(
      name: account_entry_name,
      reporting_date: start_date..end_date
    )

    # Calculate the total investable capital (in cents) for all account entries in the range
    total_investable_capital_cents = investable_capital_account_entries.sum(:amount_cents)

    # Get the IDs of folios that are excused from this portfolio investment
    excused_folio_ids = portfolio_investment.excused_folio_ids

    # Calculate the investable capital (in cents) excluding excused folios
    investable_capital_cents_without_excused_folios = investable_capital_account_entries
      .where.not(capital_commitment_id: excused_folio_ids)
      .sum(:amount_cents)

    # Find the account entry for this specific capital commitment (folio)
    # Order by reporting_date to ensure deterministic retrieval of the latest entry.
    folio_investable_capital = investable_capital_account_entries
      .where(capital_commitment_id: capital_commitment.id)
      .order(reporting_date: :desc)
      .first

    # If there is investable capital without excused folios, calculate the percentage for this folio
    if investable_capital_cents_without_excused_folios > 0 && folio_investable_capital
      folio_investable_capital_percentage_wo_excused_folios =
        folio_investable_capital.amount_cents.to_f /
        investable_capital_cents_without_excused_folios * 100
    else
      # If there is no investable capital or no entry for the folio, return 0.0
      folio_investable_capital_percentage_wo_excused_folios = 0.0
    end

    folio_investable_capital_percentage_wo_excused_folios
  end

end
