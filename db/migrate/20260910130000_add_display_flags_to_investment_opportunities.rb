# frozen_string_literal: true

# Per-opportunity display flags for the investor-facing detail page:
# whether to show the key metrics row (fund raise amount / min ticket size /
# last date) and whether to show the Express Interest calls to action.
# Both default to true so existing opportunities keep rendering as before.
class AddDisplayFlagsToInvestmentOpportunities < ActiveRecord::Migration[8.1]
  def change
    add_column :investment_opportunities, :show_key_metrics, :boolean, default: true, null: false
    add_column :investment_opportunities, :show_express_interest, :boolean, default: true, null: false
  end
end
