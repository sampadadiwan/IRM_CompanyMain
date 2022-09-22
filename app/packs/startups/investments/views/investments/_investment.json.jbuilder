json.extract! investment, :id, :investment_type, :investor_entity_id, :entity_id,
              :investor_type, :investment_instrument, :initial_value, :percentage_holding,
              :diluted_percentage, :price_cents, :amount_cents,
              :current_value, :created_at, :updated_at
json.url investment_url(investment, format: :json)
json.category investment.investor.category
json.investor_name investment.investor.investor_name
json.funding_round investment.funding_round.name
json.price money_to_currency investment.price, params, true
json.amount money_to_currency investment.price, params
json.quantity custom_format_number investment.quantity, params
json.investment_date investment.investment_date.strftime("%d/%m/%Y")
