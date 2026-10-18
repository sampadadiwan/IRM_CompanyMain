# When the last allocate-units (call) / redeem-units (distribution) job finished, so an API client can tell
# its request has been processed instead of polling unit quantities.
# openspec/changes/funds-json-api-hardening — phase 10, G18. Nullable: older records never ran it here.
class AddUnitsJobFinishedAtToCallsAndDistributions < ActiveRecord::Migration[8.1]
  def change
    add_column :capital_calls, :units_job_finished_at, :datetime
    add_column :capital_distributions, :units_job_finished_at, :datetime
  end
end
