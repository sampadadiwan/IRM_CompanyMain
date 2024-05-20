class ImportFund < ImportUtil
  STANDARD_HEADERS = ["Name", "Currency", "Unit Types", "Commitment Doc List", "Tag List", "Details", "Fund Signatory Emails", "Show Fund Ratios To Lps", "Show Fund Portfolios To Lps"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def save_row(row_data, import_upload, _custom_field_headers)
    Rails.logger.debug row_data
    name = row_data["Name"]
    currency = row_data["Currency"]
    unit_types = row_data["Unit Types"]
    commitment_doc_list = row_data["Commitment Doc List"]
    tag_list = row_data["Tag List"]
    details = row_data["Details"]
    esign_emails = row_data["Fund Signatory Emails"]
    show_fund_ratios = row_data["Show Fund Ratios To Lps"]&.downcase == "yes"
    show_portfolios = row_data["Show Fund Portfolios To Lps"]&.downcase == "yes"

    fund = import_upload.entity.funds.where(name:).first
    raise "Fund already exists" if fund

    Fund.create!(entity_id: import_upload.entity_id, import_upload_id: import_upload.id, name:, currency:, unit_types:, commitment_doc_list:, tag_list:, details:, esign_emails:, show_fund_ratios:, show_portfolios:)

    true
  end
end
