class AddInvestmentDateToInvestment < ActiveRecord::Migration[7.0]
  def change
    add_column :investments, :investment_date, :date
  end
end
