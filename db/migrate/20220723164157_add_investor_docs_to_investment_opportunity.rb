class AddInvestorDocsToInvestmentOpportunity < ActiveRecord::Migration[7.0]
  def change
    add_column :investment_opportunities, :buyer_docs_list, :text
  end
end
