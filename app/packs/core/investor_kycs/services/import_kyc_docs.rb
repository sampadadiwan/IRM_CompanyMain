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

  def save_kyc_document(user_data, import_upload, _custom_field_headers, context)
    Rails.logger.debug { "Processing investor kyc doc #{user_data}" }

    dir = context[:unzip_dir]
    name = user_data["Document Name"]
    orignal = user_data["Allow Orignal Format Download"].to_s.downcase.strip == "yes"

    owner = get_owner(user_data, import_upload)

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

  # Locates the Investor KYC record based on user data.
  #
  # It attempts to find the KYC record using the Investing Entity name and optionally the PAN/Tax ID.
  # - If PAN is provided, it searches by Name and PAN.
  # - If PAN is missing but Document Type is "KYC", it searches by Name only.
  # - Otherwise, it returns nil.
  #
  # @param user_data [Hash] The row data from the import.
  # @param import_upload [ImportUpload] The import upload record.
  # @return [InvestorKyc, nil] The found KYC record or nil.
  def get_owner(user_data, import_upload)
    query = { full_name: user_data["Investing Entity"].to_s.strip }
    pan_tax_id = user_data["Pan/Tax Id"].to_s.strip
    query[:PAN] = pan_tax_id if pan_tax_id.present?

    return nil unless pan_tax_id.present? || user_data["Document Type"] == "KYC"

    kycs = import_upload.entity.investor_kycs.where(query)
    resolve_kycs(kycs, user_data)
  end

  private

  # Resolves the specific KYC record from a collection of potential matches.
  #
  # If multiple records are found, it uses the "Kyc Id" from user_data to disambiguate.
  # Raises an error if multiple records exist but no KYC Id is provided.
  #
  # @param kycs [ActiveRecord::Relation] The collection of matching KYC records.
  # @param user_data [Hash] The row data containing potential "Kyc Id".
  # @return [InvestorKyc, nil] The single matching KYC record.
  def resolve_kycs(kycs, user_data)
    if kycs.many?
      kyc_id = user_data["Kyc Id"].to_s.strip
      if kyc_id.present?
        # NOTE: Previous code attempted to remove "Kyc Id" from custom_field_headers here,
        # but it was a local variable reassignment with no side effect.
        kycs.find_by(id: kyc_id)
      else
        msg = "Multiple KYCs found for #{user_data['Investing Entity']}. " \
              "Please specify the KYC Id to attach the document to the correct KYC."
        Rails.logger.debug msg
        raise msg
      end
    else
      kycs.first
    end
  end
end
