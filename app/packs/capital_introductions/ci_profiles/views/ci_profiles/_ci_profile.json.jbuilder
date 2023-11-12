json.extract! ci_profile, :id, :entity_id, :fund_id, :title, :geography, :stage, :sector, :fund_size_cents, :min_investment_cents, :status, :details, :text, :created_at, :updated_at
json.url ci_profile_url(ci_profile, format: :json)
