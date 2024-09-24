class AddTagListToFundFormula < ActiveRecord::Migration[7.1]
  def change
    add_column :fund_formulas, :tag_list, :string
    add_column :allocation_runs, :tag_list, :string
    add_column :entity_settings, :formula_tag_list, :string
  end
end
