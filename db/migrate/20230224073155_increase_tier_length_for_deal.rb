class IncreaseTierLengthForDeal < ActiveRecord::Migration[7.0]
  def change
    change_column :deal_investors, :tier, :string, limit: 20
  end
end
