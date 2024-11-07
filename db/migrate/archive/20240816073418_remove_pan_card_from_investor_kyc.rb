class RemovePanCardFromInvestorKyc < ActiveRecord::Migration[7.1]
  def change
    remove_column :investor_kycs, :pan_card_data, :text if column_exists?(:investor_kycs, :pan_card_data)
  end
end
