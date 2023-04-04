class AddUniqueFolioToFund < ActiveRecord::Migration[7.0]
  def change
    # https://stackoverflow.com/questions/25844786/unique-multiple-columns-and-null-in-one-column
    # The problem is we need a unique index for capital commitments and deleted_at can be null
    execute "ALTER TABLE capital_commitments ADD generated_deleted datetime(6) AS (ifNull(deleted_at, '1900-01-01 00:00:00')) NOT NULL"
    add_index :capital_commitments, [:fund_id, :folio_id, :generated_deleted], unique: true, name: 'unique_commitment'
  end
end
