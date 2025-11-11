class ImportFundDocs < ImportUtil
  step nil, delete: :create_custom_fields

  STANDARD_HEADERS = ["Fund", "Investing Entity", "Folio No", "Document Type", "Document Name", "File Name",
                      "Tags", "Send Email", "Folder", "Call / Distribution Name"].freeze
  attr_accessor :commitments

  def standard_headers
    STANDARD_HEADERS
  end

  def initialize(**)
    super
    @commitments = []
    @docs_added = Set.new
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

    # Prevent duplicate uploads (case-insensitive)
    @docs_added ||= Set.new
    file_name = user_data['File Name']&.strip
    norm_name = file_name&.downcase
    if @docs_added.include?(norm_name)
      raise "#{user_data['File Name']} cannot be uploaded again"
    else
      @docs_added.add(norm_name)
    end

    # Get the Model
    model = fetch_required_fields(user_data, import_upload)
    folio_id = user_data["Folio No"].presence
    send_email = user_data["Send Email"] == "Yes"
    dir = context[:unzip_dir]
    doc_name = user_data["Document Name"]

    # Case-insensitive file path resolution
    file_path = find_case_insensitive_file(dir, file_name)

    if model
      if Document.exists?(owner: model, entity_id: model.entity_id, name: doc_name)
        [false, "#{doc_name} already present"]
      else
        # Check if we need to create a folder
        folder = user_data["Folder"].presence
        folder = model.document_folder.children.where(name: folder, entity_id: model.entity_id).first_or_create if folder

        raise "#{user_data['File Name']} does not exist. Check for missing file or extension" unless File.exist?(file_path)

        doc = Document.new(owner: model, entity_id: model.entity_id, folder: folder, name: doc_name, tag_list: user_data["Tags"], import_upload_id: import_upload.id, user_id: import_upload.user_id, send_email: send_email)

        doc.file = File.open(file_path, "rb")
        doc.save ? [true, "Success"] : [false, doc.errors.full_messages.join(", ")]
      end
    else
      [false, "#{user_data['Document Type']} not found for #{folio_id}"]
    end
  end

  def find_model(user_data, fund, kyc)
    folio_id = user_data["Folio No"].presence

    case user_data["Document Type"]
    when "Commitment"
      cc = CapitalCommitment.where(fund_id: fund.id, folio_id:, investor_kyc_id: kyc.id).last
      raise "Capital Commitment not found for #{fund.name}, #{folio_id} and #{kyc.full_name}" unless cc

      return cc
    when "Remittance"
      call_name = user_data["Call / Distribution Name"]
      raise "Call Name not found" unless call_name

      call = CapitalCall.where(fund_id: fund.id, name: call_name).last
      raise "Capital Call not found for #{call_name}" unless call

      capital_remittance = CapitalRemittance.where(fund_id: fund.id, folio_id:, capital_call_id: call.id, investor_id: kyc.investor_id).last
      raise "Capital Remittance not found for #{fund.name}, #{call_name}, #{folio_id} and #{kyc.full_name}" unless capital_remittance && capital_remittance.investor_kyc.id == kyc.id

      return capital_remittance
    when "Distribution"
      distribution_name = user_data["Call / Distribution Name"]
      raise "Distribution Name not found" unless distribution_name

      distribution = CapitalDistribution.where(fund_id: fund.id, title: distribution_name).last
      raise "Capital Distribution not found for #{fund.name}, #{distribution_name}" unless distribution

      cdp = CapitalDistributionPayment.where(fund_id: fund.id, folio_id:, capital_distribution_id: distribution.id, investor_id: kyc.investor_id).last
      raise "Capital Distribution Payment not found for #{fund.name}, #{distribution_name}, #{folio_id} and #{kyc.full_name}" unless cdp && cdp.investor_kyc.id == kyc.id

      return cdp
    end

    nil
  end

  def fetch_required_fields(user_data, import_upload)
    raise "Fund is blank" if user_data["Fund"].blank?
    raise "Investing Entity is blank" if user_data["Investing Entity"].blank?
    raise "Folio No is blank" if user_data["Folio No"].blank?

    fund = import_upload.entity.funds.where(name: user_data["Fund"]).first
    raise "Fund #{user_data['Fund']} not found" unless fund

    kyc = import_upload.entity.investor_kycs.where(full_name: user_data["Investing Entity"]).first
    raise "Investing Entity #{user_data['Investing Entity']} not found" unless kyc

    find_model(user_data, fund, kyc)
  end

  def post_process(_ctx, unzip_dir:, **)
    FileUtils.rm_rf unzip_dir
  end
end
