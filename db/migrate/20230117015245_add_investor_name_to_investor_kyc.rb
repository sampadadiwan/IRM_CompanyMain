class AddInvestorNameToInvestorKyc < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_kycs, :investor_name, :string
    InvestorKyc.all.each do |cc|
      cc.investor_name = cc.investor.investor_name
      cc.save
    end
  end
end
