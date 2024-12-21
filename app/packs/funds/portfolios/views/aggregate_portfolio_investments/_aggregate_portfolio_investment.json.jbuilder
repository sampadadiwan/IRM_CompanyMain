json.extract! aggregate_portfolio_investment, :id, :entity_id, :fund_id, :portfolio_company_id, :bought_quantity, :sold_quantity, :quantity, :created_at, :updated_at

json.bought_amount aggregate_portfolio_investment.bought_amount.to_f
json.sold_amount aggregate_portfolio_investment.sold_amount.to_f
json.avg_cost aggregate_portfolio_investment.avg_cost.to_f
json.fmv aggregate_portfolio_investment.fmv.to_f
json.unrealized_gain aggregate_portfolio_investment.unrealized_gain.to_f
json.portfolio_company_name aggregate_portfolio_investment.portfolio_company.investor_name
