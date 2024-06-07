class AddJsonFieldsToDealInvestor < ActiveRecord::Migration[7.1]
  def change
    add_column :deal_investors, :json_fields, :json
    add_reference :deal_investors, :form_type, null: true, foreign_key: true
  end
end
