class AddSnapshotToFund < ActiveRecord::Migration[8.0]
  def up
    # Add the new columns to the funds table
    add_column :funds, :snapshot_date, :date
    add_column :funds, :snapshot, :boolean, default: false
    add_column :funds, :orignal_id, :bigint, null: false
    remove_column :funds, :slug, :string
    # Set orignal_id to the current id for existing records
    execute "UPDATE funds SET orignal_id = id"


    add_column :aggregate_portfolio_investments, :snapshot_date, :date
    add_column :aggregate_portfolio_investments, :snapshot, :boolean, default: false
    add_column :aggregate_portfolio_investments, :orignal_id, :bigint, null: false
    # Set orignal_id to the current id for existing records
    execute "UPDATE aggregate_portfolio_investments SET orignal_id = id"

    add_column :portfolio_investments, :snapshot_date, :date
    add_column :portfolio_investments, :snapshot, :boolean, default: false
    add_column :portfolio_investments, :orignal_id, :bigint, null: false
    # Set orignal_id to the current id for existing records
    execute "UPDATE portfolio_investments SET orignal_id = id"
  end

  def down
    remove_column :funds, :snapshot_date
    remove_column :funds, :snapshot
    remove_column :funds, :orignal_id
    add_column :funds, :slug, :string
  end
end
