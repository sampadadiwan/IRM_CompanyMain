class AllowNullEntityForFundFormula < ActiveRecord::Migration[7.1]
  def up
    change_column :fund_formulas, :entity_id, :bigint, null: true
    change_column :fund_formulas, :fund_id, :bigint, null: true
  end

  def down
    change_column :fund_formulas, :entity_id, :bigint
    change_column :fund_formulas, :fund_id, :bigint
  end
end
