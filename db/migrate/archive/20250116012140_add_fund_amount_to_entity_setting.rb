class AddFundAmountToEntitySetting < ActiveRecord::Migration[7.2]
  def change
    add_column :funds, :remittance_generation_basis, :string, limit: 12, default: 'Folio Amount'
  end
end
