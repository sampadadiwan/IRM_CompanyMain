json.extract! aggregate_portfolio_investment, :id, :entity_id, :fund_id, :portfolio_company_id, :investment_instrument_id, :bought_quantity, :sold_quantity, :transfer_quantity, :quantity, :created_at, :updated_at

# Fund details
json.fund_name aggregate_portfolio_investment.fund.name
json.fund_currency aggregate_portfolio_investment.fund.currency.to_s

# Portfolio company & instrument
json.portfolio_company_name aggregate_portfolio_investment.portfolio_company.investor_name
json.investment_instrument_name aggregate_portfolio_investment.investment_instrument&.name
json.category aggregate_portfolio_investment.investment_instrument&.category
json.sub_category aggregate_portfolio_investment.investment_instrument&.sub_category
json.sector aggregate_portfolio_investment.investment_instrument&.sector

# Amounts
json.bought_amount aggregate_portfolio_investment.bought_amount.to_f
json.avg_cost aggregate_portfolio_investment.avg_cost.to_f
json.transfer_amount aggregate_portfolio_investment.transfer_amount.to_f
json.sold_amount aggregate_portfolio_investment.sold_amount.to_f
json.fifo_cost aggregate_portfolio_investment.cost_of_sold.to_f
json.cost_of_sold aggregate_portfolio_investment.cost_of_sold.to_f
json.realized_gain aggregate_portfolio_investment.gain.to_f
json.gain aggregate_portfolio_investment.gain.to_f
json.cost_of_remaining aggregate_portfolio_investment.cost_of_remaining.to_f
json.fmv aggregate_portfolio_investment.fmv.to_f
json.unrealized_gain aggregate_portfolio_investment.unrealized_gain.to_f

# The LP company page, only for an LP who may open it (nil for everyone else)
json.lp_company_path aggregate_portfolio_investment.lp_company_path

json.custom_fields aggregate_portfolio_investment.json_fields
