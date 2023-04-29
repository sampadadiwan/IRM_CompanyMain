class AddInvestorNameToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :investor_name, :string
    add_column :capital_remittances, :investor_name, :string
    add_column :capital_distribution_payments, :investor_name, :string

    CapitalCommitment.all.each do |cc|
      cc.investor_name = cc.investor.investor_name
      cc.save
    end

    CapitalRemittance.all.each do |cc|
      cc.investor_name = cc.investor.investor_name
      cc.save
    end

    CapitalDistributionPayment.all.each do |cc|
      cc.investor_name = cc.investor.investor_name
      cc.save
    end
  end
end
