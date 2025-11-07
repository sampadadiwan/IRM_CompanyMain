class ImportKycDocs < ImportUtil
  step nil, delete: :create_custom_fields

  STANDARD_HEADERS = ["Investor", "PAN", "Document Type", "Document Name", "File Name", "Tags"].freeze
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
      row << e.backtrace
      import_upload.failed_row_count += 1
    end
  end

  def save_kyc_document(user_data, import_upload, _custom_field_headers, context)
    Rails.logger.debug { "Processing fund doc #{user_data}" }

    investor = import_upload.entity.investors.find_by(investor_name: user_data["Investor"])
    dir = context[:unzip_dir]
    name = user_data["Document Name"]
    model = InvestorKyc.find_by(investor_id: investor&.id, PAN: user_data["Pan"]) if user_data["Document Type"] == "KYC"
    send_email = user_data["Send Email"] == "Yes"

    file_path = find_case_insensitive_file(dir, user_data["File Name"])

    if investor && model && File.exist?(file_path)
      if Document.exists?(owner: model, entity_id: model.entity_id, name: name)
        [false, "#{name} already present"]
      else
        doc = Document.new(
          owner: model,
          entity_id: model.entity_id,
          name: name,
          tag_list: user_data["Tags"],
          orignal: true,
          import_upload_id: import_upload.id,
          user_id: import_upload.user_id,
          send_email: send_email
        )

        doc.file = File.open(file_path, "rb")
        saved = doc.save
        [saved, saved ? "Success" : doc.errors.full_messages]
      end
    elsif investor.nil?
      [false, "Investor not found"]
    elsif model.nil?
      [false, "KYC not found"]
    else
      [false, "File name #{user_data['File Name']} not found in zip, please include this file and upload."]
    end
  end

  def post_process(_ctx, unzip_dir:, **)
    FileUtils.rm_rf unzip_dir
  end
end
