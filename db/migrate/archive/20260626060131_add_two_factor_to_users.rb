class AddTwoFactorToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :two_factor_enabled, :boolean, default: false, null: false
    add_column :users, :otp_secret, :text
    add_column :users, :consumed_timestep, :integer
    add_column :users, :otp_backup_codes, :text
  end
end
