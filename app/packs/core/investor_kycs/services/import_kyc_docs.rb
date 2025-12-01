class ImportKycDocs < ImportUtil
  step nil, delete: :create_custom_fields

  STANDARD_HEADERS = ["Investing Entity", "PAN/Tax ID", "Document Type", "Document Name", "File Name", "Tags"].freeze
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

  def save_kyc_document(user_data, import_upload, custom_field_headers, context)
    Rails.logger.debug { "Processing investor kyc doc #{user_data}" }

    dir = context[:unzip_dir]
    name = user_data["Document Name"]
    orignal = user_data["Allow Orignal Format Download"].to_s.downcase.strip == "yes"

    owner = get_owner(user_data, import_upload, custom_field_headers)

    send_email = user_data["Send Email"] == "Yes"
    file_path = find_case_insensitive_file(dir, user_data["File Name"])

    if owner && File.exist?(file_path)
      if Document.exists?(owner: owner, entity_id: owner.entity_id, name: name)
        [false, "#{name} already present"]
      else
        doc = Document.new(
          owner: owner,
          entity_id: owner.entity_id,
          name: name,
          tag_list: user_data["Tags"],
          import_upload_id: import_upload.id,
          user_id: import_upload.user_id,
          send_email: send_email,
          orignal: orignal
        )

        doc.file = File.open(file_path, "rb")
        doc.save!
        Rails.logger.debug { "Saved document #{doc.name} for KYC #{owner.full_name}" }
        [true, "Success"]
      end
    elsif owner.nil?
      Rails.logger.debug { "KYC not found for #{user_data['Investing Entity']} with PAN #{user_data['Pan/Tax Id']}" }
      [false, "KYC not found"]
    else
      Rails.logger.debug { "File not found: #{user_data['File Name']} in zip" }
      [false, "File name #{user_data['File Name']} not found in zip, please include this file and upload."]
    end
  end

  def post_process(_ctx, unzip_dir:, **)
    FileUtils.rm_rf unzip_dir
  end

  def get_owner(user_data, import_upload, custom_field_headers)
    if user_data["Kyc Id"].to_s.strip.present?
      # Sometimes the "Id" header is included in the custom fields, so we need to remove it
      custom_field_headers -= ["Kyc Id"]
      Rails.logger.debug { "Removing Id from custom_field_headers #{custom_field_headers}" }
      # Sometimes we get an ID for the specific KYC we want to attach the document to. This happens when there are 2 KYCs with the same details (One for Gift City and one for regular)
      import_upload.entity.investor_kycs.find_by(id: user_data["Kyc Id"].strip)
    elsif user_data["Pan/Tax Id"].to_s.strip.blank?
      # If we have a PAN/Tax ID thats blank then we try to find by name only
      import_upload.entity.investor_kycs.find_by(full_name: user_data["Investing Entity"].strip)
    elsif user_data["Document Type"] == "KYC"
      # Otherwise we try to find it by the standard details
      import_upload.entity.investor_kycs.find_by(full_name: user_data["Investing Entity"], PAN: user_data["Pan/Tax Id"])
    end
  end
end
