class AddCloseDateToFund < ActiveRecord::Migration[7.1]
  def change
    add_column :funds, :first_close_date, :date
    add_column :funds, :last_close_date, :date
  end
end
