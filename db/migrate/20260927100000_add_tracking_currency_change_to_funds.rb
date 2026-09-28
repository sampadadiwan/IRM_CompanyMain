# Marker columns for a support-initiated tracking currency change (ChangeTrackingCurrencyJob).
#
# Changing `funds.tracking_currency` means rebuilding every stored tracking amount for the fund at
# historical rates. That happens in a background job, so the fund needs a durable record that a
# change is under way:
#   - `tracking_currency_change_state` is nil when idle, "in_progress" while the job runs and
#     "failed" when a rebuild raised partway. It doubles as the lock: the change is claimed with a
#     conditional UPDATE on this column, so two changes can never run on one fund at once.
#   - `tracking_currency_changing_to` is the currency being moved to. nil together with a non-nil
#     state means "remove the tracking currency", which is why the target cannot live in the state.
# Both are columns rather than a cache key because production's cache store (solid_cache) evicts,
# and a lock that silently disappears would let the nightly TrackingCurrencyJob or an allocation
# run write tracking amounts in the middle of a rebuild.
class AddTrackingCurrencyChangeToFunds < ActiveRecord::Migration[8.1]
  def change
    change_table :funds, bulk: true do |t|
      t.string :tracking_currency_change_state, limit: 20
      t.string :tracking_currency_changing_to, limit: 3
    end
  end
end
