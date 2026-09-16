# Records when a user's two-factor method was last reset and by whom, so the
# mode-selection screen shown at their next login can explain WHY they are being asked to
# choose again ("reset on 19 Aug 2026 by your administrator"). Both columns are nil for a
# user who has never had a reset. See docs/modules/two_factor_auth/two_factor_authentication.md,
# "Resetting the two-factor method".
class AddTwoFactorResetTrackingToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      # when the method was last cleared back to "none"
      t.datetime :two_factor_reset_at
      # users.id of whoever performed the reset — the user themselves or an administrator
      t.integer :two_factor_reset_by_id
    end
  end
end
