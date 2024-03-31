class AddLatestToFundRatio < ActiveRecord::Migration[7.1]
  def change
    add_column :fund_ratios, :latest, :boolean, default: false

    Fund.all.each do |fund|
      last_fund_ratio = fund.fund_ratios.order(end_date: :desc).first
      fund.update_latest_fund_ratios(last_fund_ratio.end_date) if last_fund_ratio
    end
  end
end
