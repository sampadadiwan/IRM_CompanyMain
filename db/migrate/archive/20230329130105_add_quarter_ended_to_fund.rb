class AddQuarterEndedToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :start_date, :date
    add_column :funds, :target_committed_amount_cents, :decimal, precision: 20, scale: 2, default: "0.0"

    Fund.update_all("target_committed_amount_cents=committed_amount_cents")
  end
end
