class AddFormTypeToInvestmentOpportunity < ActiveRecord::Migration[7.0]
  def change
    add_reference :investment_opportunities, :form_type, null: true, foreign_key: true
  end
end
