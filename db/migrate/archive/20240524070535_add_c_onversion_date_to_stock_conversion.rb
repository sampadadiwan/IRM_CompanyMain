class AddCOnversionDateToStockConversion < ActiveRecord::Migration[7.1]
  def change
    add_column :stock_conversions, :conversion_date, :date
    # This is cause now we are saving the net_quantity for sells also
    PortfolioInvestment.all.each do |pi|
      pi.compute_fmv
      pi.save
    end
  end
end
