class AddJsonFieldsToInvestmentInstrument < ActiveRecord::Migration[7.1]
  def change
    add_column :investment_instruments, :json_fields, :json
    add_reference :investment_instruments, :form_type, null: true, foreign_key: true
  end
end
