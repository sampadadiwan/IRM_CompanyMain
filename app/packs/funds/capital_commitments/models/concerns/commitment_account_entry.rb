module CommitmentAccountEntry
  extend ActiveSupport::Concern

  ###########################################################
  # Account Entry Stuff
  ###########################################################

  # In some cases name is nil - Ex Cumulative for portfolio FMV or costs @see AccountEntryAllocationEngine.allocate_portfolio_investments()
  #
  def rollup_account_entries(name, entry_type, start_date, end_date)
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

    ae.save!
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

  def get_account_entry(name, date)
    account_entries.where(name:, reporting_date: ..date).order(reporting_date: :desc).first
  end
end
