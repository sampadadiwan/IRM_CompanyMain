class AddAccountTypesToEntitySetting < ActiveRecord::Migration[8.0]
  def change
    add_column :entity_settings, :kyc_bank_account_types, :string
  end
end
