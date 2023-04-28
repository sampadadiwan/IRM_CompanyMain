class AddStartDateToFundReport < ActiveRecord::Migration[7.0]
  def change
    remove_column :fund_reports, :report_date
    add_column :fund_reports, :start_date, :date
    add_column :fund_reports, :end_date, :date    
  end
end
