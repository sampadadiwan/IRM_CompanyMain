class AddEditableRulesToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :editable_formulas, :boolean, default: false
  end
end
