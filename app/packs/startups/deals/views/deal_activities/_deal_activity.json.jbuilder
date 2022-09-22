json.extract! deal_activity, :id, :deal_id, :deal_investor_id, :by_date, :status, :completed, :entity_id, :created_at, :updated_at
json.url deal_activity_url(deal_activity, format: :json)
