# Upload of subscription and redemption orders on behalf of investors. Each row runs the same
# checks as a portal order (DealingOrderCreate); failures are reported per row in the results sheet.
# The import upload's owner is the evergreen fund.
# Worked examples X13, X16 — openspec/changes/open-ended-funds/design.md#worked-examples
class ImportDealingOrder < ImportUtil
  STANDARD_HEADERS = ["Type", "Folio No", "Investor", "Unit Class", "Amount", "Units", "All Units", "Received At"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(row_data, import_upload, _custom_field_headers, _ctx)
    fund = import_upload.owner
    raise "Upload orders from an evergreen fund" unless fund.is_a?(Fund) && fund.evergreen?

    kind = row_data["Type"].to_s.strip.downcase
    investor = fund.entity.investors.find_by(investor_name: row_data["Investor"].to_s.strip) if row_data["Investor"].present?
    params = {
      kind:, unit_type: row_data["Unit Class"].to_s.strip, folio_id: row_data["Folio No"].to_s.strip.presence,
      investor_id: investor&.id, amount: row_data["Amount"].presence, units: row_data["Units"].presence,
      all_units: row_data["All Units"].to_s.strip.casecmp?("yes"), received_at: row_data["Received At"].presence&.to_s,
      investor_kyc_id: investing_entity_id(investor, row_data["Investing Entity"])
    }
    result = DealingOrderCreate.call(fund:, params:, current_user: import_upload.user, source: "upload", import_upload:)
    raise result[:errors].presence || "Order not created" unless result.success?

    true
  end

  # Optional "Investing Entity" column (not a standard header, so older sheets still load): the KYC
  # full name within the investor. Blank → OrderEligibility uses the only approved KYC, or refuses
  # when there are several (evergreen-folio-soa E4). An unknown name is refused rather than ignored.
  def investing_entity_id(investor, name)
    return nil if investor.nil? || name.blank?

    investor.investor_kycs.find_by(full_name: name.to_s.strip)&.id || raise("Investing entity \"#{name.to_s.strip}\" is not a KYC of #{investor.investor_name}")
  end
end
