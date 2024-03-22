class AddCurrActivityToDealInvestor < ActiveRecord::Migration[7.1]
  def change
    add_reference :deal_investors, :deal_activity, null: true, foreign_key: true
  end
end
