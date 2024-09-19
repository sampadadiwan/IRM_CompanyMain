class ImportFundDocs < ImportUtil
  step nil, delete: :create_custom_fields

  STANDARD_HEADERS = ["Fund", "Investor", "Folio No", "Document Type", "Document Name", "File Name",
                      "Tags", "Send Email", "Folder", "Call / Distribution Name"].freeze
  attr_accessor :commitments

  def standard_headers
    STANDARD_HEADERS
  end

  def initialize(**)
    super
    @commitments = []
  end

  def process_row(headers, custom_field_headers, row, import_upload, context)
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h

    begin
      status, msg = save_fund_doc(user_data, import_upload, custom_field_headers, context)
      if status
        import_upload.processed_row_count += 1
      else
        import_upload.failed_row_count += 1
      end
      row << msg
    rescue ActiveRecord::Deadlocked => e
      raise e
    rescue StandardError => e
      Rails.logger.debug e.backtrace
      row << "Error #{e.message}"
      row << e.backtrace
      import_upload.failed_row_count += 1
    end
  end

  def save_fund_doc(user_data, import_upload, _custom_field_headers, context)
    Rails.logger.debug { "Processing fund doc #{user_data}" }

    # Get the Fund
    fund = import_upload.entity.funds.where(name: user_data["Fund"]).first
    raise "Fund #{user_data['Fund']} not found" unless fund

    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"]).first
    folio_id = user_data["Folio No"].presence
    send_email = user_data["Send Email"] == "Yes"
    file_name = "#{context[:unzip_dir]}/#{user_data['File Name']}"

    model = find_model(user_data, fund)
    if fund && investor && model
      # Create the doc and attach it to the commitment
      if Document.exists?(owner: model, entity_id: model.entity_id,
                          name: user_data["Document Name"])
        [false, "#{user_data['Document Name']} already present"]
      else
        # Check if we need to create a folder
        folder = user_data["Folder"].presence
        folder = model.document_folder.children.where(name: folder, entity_id: model.entity_id).first_or_create if folder
        # Create the document
        doc = Document.new(owner: model, entity_id: model.entity_id, folder:,
                           name: user_data["Document Name"], tag_list: user_data["Tags"],
                           import_upload_id: import_upload.id,
                           user_id: import_upload.user_id, send_email:)

        # Save the document
        raise "#{file_name} does not exist. Check for missing file or extension" unless File.exist?(file_name)

        doc.file = File.open(file_name, "rb")
        doc.save ? [true, "Success"] : [false, doc.errors.full_messages.join(", ")]
      end
    elsif model.nil?
      [false, "#{user_data['Document Type']} not found for #{folio_id}"]
    elsif investor.nil?
      [false, "Investor not found"]
    else
      [false, "Fund not found"]
    end
  end

  def find_model(user_data, fund)
    folio_id = user_data["Folio No"].presence

    case user_data["Document Type"]
    when "Commitment"
      return CapitalCommitment.where(fund_id: fund.id, folio_id:).last
    when "Remittance"
      call_name = user_data["Call / Distribution Name"]
      call = CapitalCall.where(fund_id: fund.id, name: call_name).last
      return CapitalRemittance.where(fund_id: fund.id, folio_id:, capital_call_id: call.id).last
    when "Distribution"
      distribution_name = user_data["Call / Distribution Name"]
      distribution = CapitalDistribution.where(fund_id: fund.id, title: distribution_name).last
      return CapitalDistributionPayment.where(fund_id: fund.id, folio_id:, capital_distribution_id: distribution.id).last
    end

    nil
  end

  def post_process(_ctx, unzip_dir:, **)
    FileUtils.rm_rf unzip_dir
  end
end
