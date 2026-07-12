class AddSkipPortfolioFmvToRatioFormulas < ActiveRecord::Migration[8.1]
  def change
    add_column :ratio_formulas, :skip_portfolio_fmv, :boolean, default: false, null: false unless column_exists?(:ratio_formulas, :skip_portfolio_fmv)
  end
end
