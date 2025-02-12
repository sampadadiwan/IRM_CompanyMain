json.extract! investment, :id, :portfolio_company_id, :category, :investor_name, :investment_type, :funding_round, :quantity, :investment_date, :notes, :created_at, :updated_at, :currency

json.url investment_url(investment, format: :json)
json.portfolio_company_name investment.portfolio_company.investor_name
json.price investment.price.to_f
json.amount investment.amount.to_f

json.dt_actions begin
  links = []
  links << link_to('Show', investment_path(investment), class: "btn btn-outline-primary")
  links << link_to('Edit', edit_investment_path(investment), class: "btn btn-outline-success") if policy(investment).update?
  safe_join(links, '')
end
