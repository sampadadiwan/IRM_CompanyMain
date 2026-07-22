json.extract! deal_investor, :id, :deal_id, :investor_id, :status, :entity_id, :created_at, :updated_at, :investor_name, :tier, :investor_advisor, :health_score, :tags, :deal_lead, :source
json.can_update policy(deal_investor).update?
json.properties deal_investor.json_fields
json.investor_logo_url deal_investor.investor&.investor_entity&.logo_url if deal_investor.investor&.investor_entity&.logo.present?
json.investor_initials deal_investor.investor&.investor_name&.split&.map(&:first)&.join&.upcase if deal_investor.investor&.investor_name.present?
json.stagnant deal_investor.stagnant?
json.stagnant_reason deal_investor.stagnant_reason
json.notes deal_investor.notes.to_plain_text if deal_investor.notes.present?
json.primary_amount deal_investor.primary_amount.to_f
json.secondary_investment deal_investor.secondary_investment.to_f
json.pre_money_valuation deal_investor.pre_money_valuation.to_f
json.fee deal_investor.fee.to_f
json.total_amount deal_investor.total_amount.to_f
json.company_advisor deal_investor.company_advisor
json.activities deal_investor.deal_activities do |activity|
  json.extract! activity, :id, :template_id, :status, :title
  json.details activity.details.to_plain_text if activity.details.present?
end
json.url deal_investor_url(deal_investor, format: :json)
