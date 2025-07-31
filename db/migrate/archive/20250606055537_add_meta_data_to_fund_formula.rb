class AddMetaDataToFundFormula < ActiveRecord::Migration[8.0]
  def change
    add_column :fund_formulas, :meta_data, :text
    FundFormula.where(rule_type: ["CumulateForPortfolioCompany", "CumulateForPortfolioCompany-Folio"]).each do |ff|
      # Set meta_data to cumulative:true for existing formulas
      ff.meta_data = "cumulative=true"
      # Update rule_type to AllocateForPortfolioCompany or AllocateForPortfolioCompany-Folio
      ff.rule_type = ff.rule_type.gsub("Cumulate", "Allocate")

      # Update formula to use the new method for cumulative entries
      if ff.rule_type.include?("Folio")
        if ff.formula.include?("AggregatePortfolioInvestment")
          ff.formula = "fund.account_entries.for_aggregate_porfolio_investments.for_api_portfolio_company(portfolio_company.id).where(name: fund_formula.name, capital_commitment_id: capital_commitment.id).not_cumulative.where(reporting_date: @start_date..@end_date).sum(:amount_cents)"
        elsif ff.formula.include?("PortfolioInvestment")
          ff.formula = "fund.account_entries.for_portfolio_investments.for_pi_portfolio_company(portfolio_company.id).where(name: fund_formula.name, capital_commitment_id: capital_commitment.id).not_cumulative.where(reporting_date: @start_date..@end_date).sum(:amount_cents)"
        end
      else
        if ff.formula.include?("AggregatePortfolioInvestment")
          ff.formula = "fund.account_entries.for_aggregate_porfolio_investments.for_api_portfolio_company(portfolio_company.id).where(name: fund_formula.name).not_cumulative.where(reporting_date: @start_date..@end_date).sum(:amount_cents)"
        elsif ff.formula.include?("PortfolioInvestment")
          ff.formula = "fund.account_entries.for_portfolio_investments.for_pi_portfolio_company(portfolio_company.id).where(name: fund_formula.name).not_cumulative.where(reporting_date: @start_date..@end_date).sum(:amount_cents)"
        end
      end
      # Save the updated fund formula
      ff.save
    end
  end
end
