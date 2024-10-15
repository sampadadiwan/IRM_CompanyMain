class ImportSecondarySaleDocs < ImportUtil
  step nil, delete: :create_custom_fields

  STANDARD_HEADERS = ["SecondarySale", "Investor", "Id No", "Document Type", "Document Name", "File Name",
                      "Tags", "Send Email", "Orignal Format", "Folder"].freeze
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
      [false, "#{user_data['Document Type']} not found for #{id_no}"]
    elsif investor.nil?
      [false, "Investor not found"]
    else
      [false, "SecondarySale not found"]
    end
  end

  def key_info
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

    case user_data["Document Type"]
    when "Offer"
      offer = Offer.where(secondary_sale_id: secondary_sale.id, id:).last
      raise "Offer not found for #{id_no}" unless offer

      return offer
    when "Interest"

      interest = Interest.where(secondary_sale_id: secondary_sale.id, id:).last
      raise "Interest not found" unless interest

      interest
    when "Allocation"
      allocation = Allocation.where(secondary_sale_id: secondary_sale.id, id:).last
      raise "Allocation not found" unless allocation

      allocation
    end

    nil
  end

  def post_process(_ctx, unzip_dir:, **)
    FileUtils.rm_rf unzip_dir
  end
end
