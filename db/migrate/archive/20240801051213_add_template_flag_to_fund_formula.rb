class AddTemplateFlagToFundFormula < ActiveRecord::Migration[7.1]
  def change
    add_column :fund_formulas, :is_template, :boolean, default: false
    # Mark old formulas as templates
    FundFormula.where(entity_id: nil).update_all(is_template: true)
  end
end
