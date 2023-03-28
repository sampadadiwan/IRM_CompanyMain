class ImportKycDocs < ImportUtil
  STANDARD_HEADERS = ["Investor", "PAN", "Document Type", "Document Name", "File Name", "Tags"].freeze
  attr_accessor :commitments

  def standard_headers
    STANDARD_HEADERS
  end

  def initialize(params)
    super(params)
    @commitments = []
  end

  def process_row(headers, custom_field_headers, row, import_upload, context)
    # create hash from headers and cells
    user_data = [headers, row].transpose.to_h

    begin
      status, msg = save_kyc_document(user_data, import_upload, custom_field_headers, context)
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
      import_upload.failed_row_count += 1
    end
  end

  def save_kyc_document(user_data, import_upload, _custom_field_headers, context)
    Rails.logger.debug { "Processing fund doc #{user_data}" }

    # Get the Fund
    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"].strip).first
    file_name = "#{context.unzip_dir}/#{user_data['File Name'].strip}"
    name = user_data["Document Name"].strip
    model = InvestorKyc.where(investor_id: investor.id, PAN: user_data["PAN"].strip).first if user_data["Document Type"].strip == "KYC"

    if investor && model && File.exist?(file_name)
      if name == "PAN"
        # PAN is handled slightly differently, its not a separate document.
        model.pan_card = File.open(file_name, "rb")
        [model.save, model.errors.full_messages]
      elsif Document.exists?(owner: model, entity_id: model.entity_id,
                             name: user_data["Document Name"].strip)
        # All other docs are attached as documents
        # Create the doc and attach it to the commitment
        [false, "#{user_data['Document Name']} already present"]
      else
        # Create the document
        doc = Document.new(owner: model, entity_id: model.entity_id,
                           name:, tag_list: user_data["Tags"]&.strip,
                           user_id: import_upload.user_id)

        doc.file = File.open(file_name, "rb")
        [doc.save, doc.errors.full_messages]
      end
    elsif model.nil?
      [false, "#{user_data['Document Type'].strip} not found"]
    elsif investor.nil?
      [false, "Investor not found"]
    else
      [false, "File name #{user_data['File Name']} not found in zip, please include this file and upload."]
    end
  end

  def post_process(_import_upload, context)
    FileUtils.rm_rf context.unzip_dir
  end
end
