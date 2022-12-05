class AddCurrencyToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :currency, :string, null: false, limit: 5
    
    Fund.all.each do |f|
      f.currency = f.entity.currency
      f.save
    end

  end

  
end
