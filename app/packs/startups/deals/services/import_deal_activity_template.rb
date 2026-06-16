class ImportDealActivityTemplate < ImportUtil
  # Only "Title" and "Days" are required; any extra columns are ignored.
  def standard_headers
    %w[Title Days]
  end

  # Deal activity templates have no custom fields — skip that step.
  def create_custom_fields(_ctx, **)
    true
  end

  def save_row(user_data, import_upload, _custom_field_headers, _ctx)
    deal  = import_upload.owner # owner is the Deal
    title = user_data["Title"].to_s.strip
    days  = user_data["Days"].to_i

    raise "Title is required" if title.blank?
    raise "Days must be a positive number" if days <= 0

    # Place the new template after all existing ones.
    max_seq = DealActivity.where(deal_id: deal.id, deal_investor_id: nil).maximum(:sequence) || 0

    DealActivity.create!(
      deal_id: deal.id,
      deal_investor_id: nil,
      entity_id: deal.entity_id,
      status: "Template",
      title: title,
      days: days,
      sequence: max_seq + 1,
      import_upload_id: import_upload.id
    )
    true
  end
end
