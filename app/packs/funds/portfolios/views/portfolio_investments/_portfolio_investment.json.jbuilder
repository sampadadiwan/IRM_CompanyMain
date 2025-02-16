json.extract! portfolio_investment, :id, :entity_id, :fund_id, :portfolio_company_name, :notes
json.url portfolio_investment_url(portfolio_investment, format: :json)

json.quantity portfolio_investment.quantity.to_f
json.amount portfolio_investment.quantity >= 0 ? portfolio_investment.amount.to_f : -portfolio_investment.amount.to_f
json.cost portfolio_investment.cost.to_f
json.fmv portfolio_investment.fmv.to_f
json.cost_of_sold portfolio_investment.cost_of_sold.to_f
json.created_at l(portfolio_investment.created_at)
json.investment_instrument_name portfolio_investment.investment_instrument.name

# Send the custom_fields
json.custom_fields portfolio_investment.json_fields
json.investment_date l(portfolio_investment.investment_date)

# Explicitly render the HTML partial as a string
json.dt_actions ApplicationController.render(
  partial: "portfolio_investments/dt_actions",
  locals: { portfolio_investment: portfolio_investment },
  formats: [:html]
)
