class AddGeneratedDeletedToDealInvestors < ActiveRecord::Migration[7.1]
  def change
    ActiveRecord::Base.transaction do
      # https://stackoverflow.com/questions/25844786/unique-multiple-columns-and-null-in-one-column
      execute "ALTER TABLE deal_investors ADD generated_deleted datetime(6) AS (ifNull(deleted_at, '1900-01-01 00:00:00')) NOT NULL"

      # remove old index without generated_deleted
      # t.index ["investor_id", "deal_id"], name: "index_deal_investors_on_investor_id_and_deal_id", unique: true
      # remove_index :deal_investors, name: 'index_deal_investors_on_investor_id_and_deal_id'
      remove_index :deal_investors, column: [:investor_id, :deal_id], name: 'index_deal_investors_on_investor_id_and_deal_id'

      add_index :deal_investors, %i[investor_id deal_id generated_deleted], unique: true, name: 'unique_deal_investor'
    end
  end
end
