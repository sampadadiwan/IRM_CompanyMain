class AddSnapshotToFund < ActiveRecord::Migration[8.0]
  TABLES = %w[funds capital_commitments portfolio_investments aggregate_portfolio_investments]

  def up
    # Add the new columns to the funds table
    add_column :funds, :snapshot_date, :date
    add_column :funds, :snapshot, :boolean, default: false
    add_column :funds, :orignal_id, :bigint, null: true
    remove_column :funds, :slug, :string
    # Set orignal_id to the current id for existing records
    execute "UPDATE funds SET orignal_id = id"
    # Add an index for the snapshot_date
    add_index :funds, :snapshot_date, name: "index_funds_on_snapshot_date"


    add_column :aggregate_portfolio_investments, :snapshot_date, :date
    add_column :aggregate_portfolio_investments, :snapshot, :boolean, default: false
    add_column :aggregate_portfolio_investments, :orignal_id, :bigint, null: true
    # Set orignal_id to the current id for existing records
    execute "UPDATE aggregate_portfolio_investments SET orignal_id = id"
    add_index :aggregate_portfolio_investments, :snapshot_date, name: "index_aggregate_portfolio_investments_on_snapshot_date"

    add_column :portfolio_investments, :snapshot_date, :date
    add_column :portfolio_investments, :snapshot, :boolean, default: false
    add_column :portfolio_investments, :orignal_id, :bigint, null: true
    # Set orignal_id to the current id for existing records
    execute "UPDATE portfolio_investments SET orignal_id = id"
    add_index :portfolio_investments, :snapshot_date, name: "index_portfolio_investments_on_snapshot_date"

    TABLES.each do |table|
      # Drop the table
      drop_table "#{table.singularize}_snapshots"
    end
  end

  def down
    remove_column :funds, :snapshot_date
    remove_column :funds, :snapshot
    remove_column :funds, :orignal_id
    add_column :funds, :slug, :string

    remove_column :aggregate_portfolio_investments, :snapshot_date
    remove_column :aggregate_portfolio_investments, :snapshot
    remove_column :aggregate_portfolio_investments, :orignal_id

    remove_column :portfolio_investments, :snapshot_date
    remove_column :portfolio_investments, :snapshot
    remove_column :portfolio_investments, :orignal_id
  end
end
