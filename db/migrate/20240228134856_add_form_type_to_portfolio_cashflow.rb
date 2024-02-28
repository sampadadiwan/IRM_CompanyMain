class AddFormTypeToPortfolioCashflow < ActiveRecord::Migration[7.1]
  def change
    add_reference :portfolio_cashflows, :form_type, null: true, foreign_key: true
    add_column :portfolio_cashflows, :json_fields, :json
    add_reference :portfolio_cashflows, :document_folder, null: true, foreign_key: {to_table: :folders}
  end
end
