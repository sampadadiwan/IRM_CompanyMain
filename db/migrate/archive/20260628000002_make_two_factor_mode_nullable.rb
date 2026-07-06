class MakeTwoFactorModeNullable < ActiveRecord::Migration[8.1]
  def up
    # Remove the default so new users get NULL until they explicitly choose a mode
    change_column_default :users, :two_factor_mode, from: "authenticator", to: nil
    change_column_null    :users, :two_factor_mode, true

    # Un-enrolled users (no otp_secret) haven't chosen a mode yet — reset to NULL
    # so they are routed through the mode-selection screen on next login.
    # Enrolled users (otp_secret present) were set up with an authenticator app
    # before this feature existed, so "authenticator" is the correct mode for them.
    User.where(otp_secret: nil).update_all(two_factor_mode: nil)
  end

  def down
    User.where(two_factor_mode: nil).update_all(two_factor_mode: "authenticator")
    change_column_null    :users, :two_factor_mode, false, "authenticator"
    change_column_default :users, :two_factor_mode, from: nil, to: "authenticator"
  end
end
