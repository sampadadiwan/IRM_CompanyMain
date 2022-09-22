json.extract! access_right, :id,
              :owner_type,
              :owner_id,
              :access_to_investor_id,
              :access_type,
              :metadata,
              :created_at,
              :updated_at,
              :entity_id,
              :access_to_category,
              :deleted_at

json.url access_right_url(access_right, format: :json)
