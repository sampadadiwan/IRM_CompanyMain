class CreatePortfolioScenarios < ActiveRecord::Migration[7.0]
  def change
    create_table :portfolio_scenarios do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.string :name, limit: 100
      t.references :user, null: false, foreign_key: true
      t.text :calculations
      t.timestamps
    end
  end
end
