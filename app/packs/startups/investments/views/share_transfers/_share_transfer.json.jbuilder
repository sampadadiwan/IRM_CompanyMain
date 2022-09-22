json.extract! share_transfer, :id, :entity_id, :from_investor_id, :from_user_id, :from_investment_id, :to_investor_id, :to_user_id, :to_investment_id, :quantity, :price, :transfer_date, :transfered_by_id, :created_at, :updated_at
json.url share_transfer_url(share_transfer, format: :json)
