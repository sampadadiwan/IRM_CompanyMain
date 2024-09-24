class AddFeeFormulaIdsToCapitalCalls < ActiveRecord::Migration[7.1]
  def change
    add_column :capital_calls, :fee_formula_ids, :string
  end
end
