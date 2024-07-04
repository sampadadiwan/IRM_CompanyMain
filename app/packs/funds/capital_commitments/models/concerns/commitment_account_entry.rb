module CommitmentAccountEntry
  extend ActiveSupport::Concern

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
    deletable = account_entries.where(entry_type:, reporting_date: start_date.., cumulative: true)
    deletable = deletable.where(reporting_date: ..end_date)
    deletable = deletable.where(name:) if name
    deletable.delete_all

    # Find the cum_amount_cents
    addable = account_entries.where(entry_type:, cumulative: false, reporting_date: ..end_date)
    addable = addable.where(name:) if name
    cum_amount_cents = addable.sum(:amount_cents)

    # Create a new Cumulative entry
    new_name = name || entry_type
    ae = account_entries.new(name: new_name, entry_type:, amount_cents: cum_amount_cents, entity_id:, fund_id:, investor_id:, folio_id:, reporting_date: end_date, period: "As of #{end_date}", cumulative: true, generated: true)

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

  def on_date(name, entry_type, end_date)
    entries = account_entries
    entries = entries.not_cumulative.where(name:) if name.present?
    entries = entries.where(entry_type:) if entry_type.present?

    entries.where(reporting_date: end_date).sum(:amount_cents)
  end

  def quarterly(name, entry_type, _start_date, end_date)
    entries = account_entries
    entries = entries.not_cumulative.where(name:) if name.present?
    entries = entries.where(entry_type:) if entry_type.present?

    entries.where(reporting_date: end_date.beginning_of_quarter..end_date).sum(:amount_cents)
  end

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

    date = end_date.month > 3 ? end_date.beginning_of_year : (end_date.beginning_of_year - 1.year)
    start_of_financial_year = (date + 3.months)

    entries.not_cumulative.where(reporting_date: start_of_financial_year..end_date).sum(:amount_cents)
  end

  def management_fee_start_end(start_date, end_date, exclude_call_name: nil)
    management_fees = 0
    remittances = capital_remittances.joins(:capital_call)
    remittances = remittances.where.not("capital_calls.name = ?", exclude_call_name) if exclude_call_name
    remittances = remittances.where(remittance_date: @start_date..@end_date)
    remittances.each do |cr|
      management_fees += cr.call_amount_cents * (fund_unit_setting.management_fee * ((end_date - start_date).to_i + 1) / 365) / 100
    end
    management_fees
  end
end
