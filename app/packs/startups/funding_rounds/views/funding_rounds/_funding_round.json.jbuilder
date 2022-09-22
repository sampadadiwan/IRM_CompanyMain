json.extract! funding_round, :id, :name, :total_amount_cents, :currency, :pre_money_valuation_cents, :post_money_valuation_cents, :entity_id, :created_at, :updated_at
json.url funding_round_url(funding_round, format: :json)
