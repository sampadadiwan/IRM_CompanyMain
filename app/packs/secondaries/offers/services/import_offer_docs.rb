class ImportOfferDocs < ImportUtil
  STANDARD_HEADERS = ["Id", "User", "Email", "Folder", "Document Name", "File Name",
                      "Tags", "Send Email"].freeze
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
      status, msg = save_offer_doc(user_data, import_upload, custom_field_headers, context)
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

  def save_offer_doc(user_data, import_upload, _custom_field_headers, context)
    Rails.logger.debug { "Processing offer doc #{user_data}" }

    # Get the Offer
    offer = import_upload.entity.offers.where(id: user_data["Id"]).first
    raise "Offer #{user_data['Id']} not found" unless offer

    send_email = user_data["Send Email"]&.strip == "Yes"
    file_name = "#{context.unzip_dir}/#{user_data['File Name'].strip}"

    if offer
      # Create the doc and attach it to the commitment
      if Document.exists?(owner: offer, entity_id: offer.entity_id,
                          name: user_data["Document Name"].strip)
        [false, "#{user_data['Document Name']} already present"]
      else
        # Check if we need to create a folder
        folder = user_data["Folder"].presence
        folder = offer.document_folder.children.where(name: folder, entity_id: offer.entity_id).first_or_create if folder
        # Create the document
        doc = Document.new(owner: offer, entity_id: offer.entity_id, folder:,
                           name: user_data["Document Name"].strip, tag_list: user_data["Tags"]&.strip,
                           user_id: import_upload.user_id, send_email:)

        doc.file = File.open(file_name, "rb")
        doc.save ? [true, "Success"] : [false, doc.errors.full_messages.join(", ")]
      end
    else
      [false, "Offer not found"]
    end
  end

  def post_process(_import_upload, context)
    FileUtils.rm_rf context.unzip_dir
  end
end
