json.partial! "approval_responses/approval_response", approval_response: @approval_response

# What the LP mobile app's Approval screen needs to show and answer the request
approval = @approval_response.approval
json.approval do
  json.id approval.id
  json.title approval.title
  json.due_date approval.due_date
  json.agreements_reference approval.agreements_reference
  json.entity_name approval.entity.name
  # The answers the GP offers; Pending is the unanswered state, never a choice (ApprovalResponse#no_pending_response)
  json.response_options approval.response_status.to_s.split(",").map(&:strip).reject { |s| s.blank? || s == "Pending" }
  # Still answerable: the same due-date rule as ApprovalResponsePolicy#approve?
  json.open approval.due_date.present? && approval.due_date >= Time.zone.today
end
# Who this response is for — the folio, offer or deal it is attached to, else the investor
json.owner_label @approval_response.owner.present? ? "#{@approval_response.investor.investor_name} – #{@approval_response.owner}" : @approval_response.investor.investor_name
# The GP's custom fields for responses: the app sends these to the website form rather than render them
json.needs_form @approval_response.form_type.present? && @approval_response.form_type.form_custom_fields.visible.not_regulatory.exists?
json.responded_at(@approval_response.status == "Pending" ? nil : @approval_response.updated_at)
# The approval's documents the investor may see — the website's rule (MobileDocuments::APPROVED_SQL, non-private folder)
json.documents approval.documents.not_template.where(MobileDocuments::APPROVED_SQL)
                       .joins(:folder).where(folders: { private: false })
                       .order(id: :desc).pluck(:id, :name).map { |id, name| { id:, name: } }
