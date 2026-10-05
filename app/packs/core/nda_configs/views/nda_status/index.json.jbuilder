# NDA Status AG Grid JSON data — renders investor-level rows with nested user detail.
# Each investor row includes a users array for AG Grid row grouping.
# Changed: New jbuilder for Module 3 GP Dashboard.
# Why: AG Grid needs a flat JSON array; row grouping is handled client-side.

json.array! @status_data[:investor_rows] do |row|
  json.investor_name row[:investor].investor_name
  json.investor_id row[:investor].id
  json.status row[:status]
  json.signed_by row[:signed_by]&.full_name
  json.signed_at row[:signed_at] ? l(row[:signed_at], format: :short) : nil
  json.category row[:investor].category

  json.users row[:users] do |user_row|
    json.user_name user_row[:user].full_name
    json.user_email user_row[:user].email
    json.user_id user_row[:user].id
    json.user_status user_row[:status]
    json.nda_tagged user_row[:nda_tagged]
    json.exempt user_row[:exempt]
    json.signer user_row[:signer]

    if user_row[:exempt]
      exemption = NdaExemption.find_by(nda_config_id: @nda_config.id, user_id: user_row[:user].id)
      json.exemption_id exemption&.id
      json.exemption_reason exemption&.reason
    end
  end
end
