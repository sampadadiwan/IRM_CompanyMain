class AddTypeToFundFormula < ActiveRecord::Migration[7.0]
  def change
    add_column :fund_formulas, :commitment_type, :string, limit: 10, default: "All"
  end
end
