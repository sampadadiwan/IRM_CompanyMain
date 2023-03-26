class AddCoInvestToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :co_invest_call_amount_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :funds, :co_invest_committed_amount_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :funds, :co_invest_distribution_amount_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :funds, :co_invest_collected_amount_cents, :decimal, precision: 20, scale: 2, default: 0
  end
end
