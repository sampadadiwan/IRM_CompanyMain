class RemoveCategorySubCategoryFromScenarioInvestment < ActiveRecord::Migration[8.0]
  def change
    if column_exists?(:scenario_investments, :category)
      remove_column :scenario_investments, :category, :string
    end
    if column_exists?(:scenario_investments, :sub_category)
      remove_column :scenario_investments, :sub_category, :string
    end
  end
end
