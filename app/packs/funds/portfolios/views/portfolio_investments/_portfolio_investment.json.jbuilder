json.extract! portfolio_investment, :id, :entity_id, :fund_id, :investment_date, :quantity, :proforma, :ref_id, :notes, :sold_quantity, :transfer_quantity, :net_quantity, :quantity_as_of_date, :created_at, :updated_at
json.portfolio_company_name portfolio_investment.decorate.portfolio_company_name
json.url portfolio_investment_url(portfolio_investment, format: :json)

# Fund details
json.fund_name portfolio_investment.fund.name
json.fund_currency portfolio_investment.fund.currency.to_s

# Instrument details
json.investment_instrument_name portfolio_investment.investment_instrument.name
json.instrument_currency portfolio_investment.investment_instrument&.currency&.to_s

# Amounts
json.amount_in_instrument_currency portfolio_investment.base_amount.to_d
json.ex_expenses_base_amount portfolio_investment.ex_expenses_base_amount.to_d
json.base_amount portfolio_investment.base_amount.to_d
json.quantity portfolio_investment.quantity.to_f
json.ex_expenses_amount portfolio_investment.ex_expenses_amount.to_f.round(2)
json.amount portfolio_investment.quantity >= 0 ? portfolio_investment.amount.to_f.round(2) : -portfolio_investment.amount.to_f.round(2)
json.cost portfolio_investment.cost.to_f.round(2)
json.cost_of_sold portfolio_investment.cost_of_sold.to_f.round(2)
json.cost_of_remaining portfolio_investment.cost_of_remaining.to_f.round(2)
json.transfer_amount portfolio_investment.transfer_amount.to_f.round(2)
json.fmv portfolio_investment.fmv.to_f.round(2)
json.gain portfolio_investment.gain.to_f.round(2)
json.realized_gain portfolio_investment.gain.to_f.round(2)
json.unrealized_gain portfolio_investment.unrealized_gain.to_f.round(2)

# Instrument Currency amounts
json.instrument_currency_fmv portfolio_investment.instrument_currency_fmv.to_f.round(2)
json.instrument_currency_cost_of_remaining portfolio_investment.instrument_currency_cost_of_remaining.to_f.round(2)
json.instrument_currency_unrealized_gain portfolio_investment.instrument_currency_unrealized_gain.to_f.round(2)

# Per share prices
json.sale_price_per_share portfolio_investment.sale_price_per_share.to_f.round(2)
json.cost_of_sold_per_share portfolio_investment.cost_of_sold_per_share.to_f.round(2)

# Tracking currency
json.tracking_amount portfolio_investment.tracking_amount.to_f.round(2)
json.tracking_fmv portfolio_investment.tracking_fmv.to_f.round(2)

json.created_at l(portfolio_investment.created_at)

json.portfolio_company portfolio_investment.portfolio_company, partial: 'investors/investor', as: :investor
json.valuation portfolio_investment.valuation, partial: 'valuations/valuation', as: :valuation
json.investment_instrument portfolio_investment.investment_instrument, partial: 'investment_instruments/investment_instrument', as: :investment_instrument

# Send the custom_fields
json.custom_fields portfolio_investment.json_fields

# Explicitly render the HTML partial as a string
json.dt_actions ApplicationController.render(
  partial: "portfolio_investments/dt_actions",
  locals: { portfolio_investment: portfolio_investment },
  formats: [:html]
)
