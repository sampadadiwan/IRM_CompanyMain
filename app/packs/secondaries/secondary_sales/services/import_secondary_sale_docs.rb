class ImportSecondarySaleDocs < ImportUtil
  step nil, delete: :create_custom_fields

  STANDARD_HEADERS = ["SecondarySale", "Investor", "Id No", "Document Type", "Document Name", "File Name",
                      "Tags", "Send Email", "Orignal Format", "Folder"].freeze
  DOCUMENT_TYPES = %w[Offer Interest Allocation].freeze
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
      status, msg = save_secondary_sale_doc(user_data, import_upload, custom_field_headers, context)
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

  def save_secondary_sale_doc(user_data, import_upload, _custom_field_headers, context)
    Rails.logger.debug { "Processing secondary_sale doc #{user_data}" }

    secondary_sale, investor, id_no, send_email, orignal, file_name = key_info(user_data, import_upload, context)

    model = find_model(user_data, secondary_sale)
    if secondary_sale && investor && model
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
                           user_id: import_upload.user_id, send_email:, orignal:)

        # Save the document
        raise "#{user_data['File Name']} does not exist. Check for missing file or extension" unless File.exist?(file_name)

        doc.file = File.open(file_name, "rb")
        doc.save ? [true, "Success"] : [false, doc.errors.full_messages.join(", ")]
      end
    elsif model.nil?
      [false, "#{user_data['Document Type']} #{id_no} not found in #{secondary_sale.name}"]
    elsif investor.nil?
      [false, "Investor not found: #{user_data['Investor']}"]
    else
      [false, "SecondarySale not found: #{user_data['SecondarySale']}"]
    end
  end

  # save_secondary_sale_doc calls this with four arguments - the method took none,
  # so every row failed with "wrong number of arguments" before reaching any of
  # the messages below
  def key_info(user_data, import_upload, context)
    # Get the SecondarySale
    secondary_sale = import_upload.entity.secondary_sales.where(name: user_data["SecondarySale"]).first
    raise "SecondarySale #{user_data['SecondarySale']} not found" unless secondary_sale

    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"]).first
    id_no = user_data["Id No"].presence
    send_email = user_data["Send Email"] == "Yes"
    orignal = user_data["Orignal Format"] == "Yes"
    file_name = "#{context[:unzip_dir]}/#{user_data['File Name']}"

    [secondary_sale, investor, id_no, send_email, orignal, file_name]
  end

  def find_model(user_data, secondary_sale)
    id = user_data["Id No"].presence
    document_type = user_data["Document Type"]
    raise "Id No must be specified" if id.blank?

    # The trailing `nil` this method used to end with discarded the Interest and
    # Allocation branches, so those document types always resolved to no owner
    case document_type
    when "Offer"
      # `id_no` was not in scope here - the miss raised NameError instead of this message
      Offer.where(secondary_sale_id: secondary_sale.id, id:).last ||
        raise("Offer #{id} not found in secondary sale #{secondary_sale.name}")
    when "Interest"
      Interest.where(secondary_sale_id: secondary_sale.id, id:).last ||
        raise("Interest #{id} not found in secondary sale #{secondary_sale.name}")
    when "Allocation"
      Allocation.where(secondary_sale_id: secondary_sale.id, id:).last ||
        raise("Allocation #{id} not found in secondary sale #{secondary_sale.name}")
    else
      raise "Document Type '#{document_type}' is not valid. Use one of: #{DOCUMENT_TYPES.join(', ')}"
    end
  end

  def post_process(_ctx, unzip_dir:, **)
    FileUtils.rm_rf unzip_dir
  end
end
