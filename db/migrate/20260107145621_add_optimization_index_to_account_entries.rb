class AddOptimizationIndexToAccountEntries < ActiveRecord::Migration[8.0]
  def change
    add_index :account_entries, [:fund_id, :generated, :reporting_date, :fund_formula_id], name: 'idx_ae_fund_gen_date_formula'
  end
end
