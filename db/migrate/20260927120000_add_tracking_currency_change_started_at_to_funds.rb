# When the current tracking currency change was claimed (ChangeTrackingCurrencyJob).
#
# The job runs with retry: 0 and releases its claim itself, so a worker that is hard-killed
# (OOM on the account_entries rebuild, a deploy SIGKILL) leaves the fund "in_progress" forever -
# blocking allocation runs, tracking numbers and the nightly job. With a start time, a claim
# older than FundTrackingCurrencyChange::STALE_AFTER is treated as dead and can be retried.
class AddTrackingCurrencyChangeStartedAtToFunds < ActiveRecord::Migration[8.1]
  def change
    add_column :funds, :tracking_currency_change_started_at, :datetime
  end
end
