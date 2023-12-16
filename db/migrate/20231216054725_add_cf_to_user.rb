class AddCfToUser < ActiveRecord::Migration[7.1]
  # This is a key change - moving to json to store custom fields, enables native SQL into the json
  def change
    add_column :users, :json_fields, :json
    add_reference :users, :form_type, foreign_key: true, null: true
    
    add_column :account_entries, :json_fields, :json
    add_column :approvals, :json_fields, :json
    add_column :capital_calls, :json_fields, :json
    add_column :capital_commitments, :json_fields, :json
    add_column :capital_distribution_payments, :json_fields, :json
    add_column :capital_distributions, :json_fields, :json
    add_column :capital_remittance_payments, :json_fields, :json
    add_column :capital_remittances, :json_fields, :json
    add_column :deals, :json_fields, :json
    add_column :documents, :json_fields, :json
    add_column :expression_of_interests, :json_fields, :json
    add_column :fund_unit_settings, :json_fields, :json
    add_column :funds, :json_fields, :json
    add_column :holdings, :json_fields, :json
    add_column :interests, :json_fields, :json
    add_column :investment_opportunities, :json_fields, :json
    add_column :investor_kycs, :json_fields, :json
    add_column :investors, :json_fields, :json
    add_column :kpi_reports, :json_fields, :json
    add_column :kpis, :json_fields, :json
    add_column :offers, :json_fields, :json
    add_column :portfolio_investments, :json_fields, :json
    add_column :secondary_sales, :json_fields, :json
    add_column :valuations, :json_fields, :json

    # Migrate old data from properties to json_fields
    existing = [Fund, AccountEntry, Approval, CapitalCall, CapitalCommitment, CapitalDistributionPayment, CapitalDistribution, CapitalRemittancePayment, CapitalRemittance, Deal, Document, ExpressionOfInterest, FundUnitSetting, Fund, Holding, Interest, InvestmentOpportunity, InvestorKyc, Investor, KpiReport, Kpi, Offer, PortfolioInvestment, SecondarySale, Valuation]

    begin
      FormCustomField.migrate_old_data
    rescue Exception => e
      puts "Error migrating old data: #{e.message}"
    end

    existing.each do |klass|
      puts "Migrating custom fields for #{klass.name}"
      klass.where.not(properties: {}).all.each do |m|
        m.update_column(:json_fields, m.properties)
      end
    end
  end
end
