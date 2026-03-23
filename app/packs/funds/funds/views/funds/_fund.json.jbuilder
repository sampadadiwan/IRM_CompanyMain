json.extract! fund, :id, :name, :category, :details, :entity_id, :currency, :tracking_currency, :unit_types, :master_fund_id, :tag_list, :created_at, :updated_at

json.committed_amount fund.committed_amount.to_f
json.collected_amount fund.collected_amount.to_f
json.call_amount fund.call_amount.to_f
json.distribution_amount fund.distribution_amount.to_f
json.target_committed_amount fund.target_committed_amount.to_f

json.tracking_collected_amount fund.tracking_collected_amount.to_f
json.tracking_call_amount fund.tracking_call_amount.to_f
json.tracking_co_invest_call_amount fund.tracking_co_invest_call_amount.to_f
json.tracking_distribution_amount fund.tracking_distribution_amount.to_f
json.tracking_committed_amount fund.tracking_committed_amount.to_f

json.url fund_url(fund, format: :json)
