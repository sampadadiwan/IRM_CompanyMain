class AddEndDateToFundRatio < ActiveRecord::Migration[7.0]
  def change
    add_column :fund_ratios, :end_date, :date
    change_column :fund_ratios, :valuation_id, :bigint, null: true
  end
end
