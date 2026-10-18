json.extract! entity, :id, :name, :url, :category, :founded, :entity_type, :logo_url,
              :created_at, :updated_at
# Tax id only for users related to this company (B1, EntityPolicy#full_details?).
json.pan entity.pan if respond_to?(:policy) && policy(entity).full_details?
json.url entity_url(entity, format: :json)
json.value entity.name
# The entity's settings, only for those who can change them — the same users who can already set
# them through PATCH /entities/:id.json (funds-json-api-hardening phase 3, G9 — H17 E22 X27).
# The onboarding agent refuses to write unless it can read sandbox = true here.
# Policy first: no settings query for viewers who can't see them (search / index lists)
if respond_to?(:policy) && policy(entity).update? && entity.entity_setting
  json.entity_setting do
    # id: a PATCH can name the row it updates (P5)
    json.extract! entity.entity_setting, :id, :sandbox, :sandbox_emails, :sandbox_numbers,
                  :individual_kyc_doc_list, :non_individual_kyc_doc_list, :mcp_enabled
  end
end
