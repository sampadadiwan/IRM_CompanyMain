class AddIssueDateToFundUnit < ActiveRecord::Migration[7.0]
  def change
    add_column :fund_units, :issue_date, :date
  end
end
