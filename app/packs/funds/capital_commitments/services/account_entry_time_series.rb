class AccountEntryTimeSeries
  def initialize(account_entries)
    @account_entries = account_entries
  end

  def call
    time_series = Hash.new { |h, k| h[k] = {} }

    @account_entries.order(:reporting_date).each do |account_entry|
      time_series[account_entry.name][account_entry.reporting_date] = account_entry.amount
    end

    time_series
  end
end
