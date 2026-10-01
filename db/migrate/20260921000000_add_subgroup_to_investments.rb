class AddSubgroupToInvestments < ActiveRecord::Migration[8.0]
  def change
    change_table :investments, bulk: true do |t|
      t.string :subgroup, limit: 100, null: true
      t.index :subgroup
    end
  end
end
