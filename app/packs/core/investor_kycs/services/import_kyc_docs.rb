class ImportKycDocs < ImportUtil
  STANDARD_HEADERS = ["Investor", "Full Name", "Document Type", "Document Name", "File Name", "Tags"].freeze
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
      import_upload.failed_row_count += 1
    end
  end

  def save_fund_doc(user_data, import_upload, _custom_field_headers, context)
    Rails.logger.debug { "Processing fund doc #{user_data}" }

    # Get the Fund
    investor = import_upload.entity.investors.where(investor_name: user_data["Investor"].strip).first
    file_name = "#{context.unzip_dir}/#{user_data['File Name'].strip}"

    model = InvestorKyc.where(investor_id: investor.id, full_name: user_data["Full Name"].strip).first if user_data["Document Type"].strip == "KYC"

    if investor && model
      # Create the doc and attach it to the commitment
      if Document.exists?(owner: model, entity_id: model.entity_id,
                          name: user_data["Document Name"].strip)
        [false, "#{user_data['Document Name']} already present"]
      else
        # Create the document
        doc = Document.new(owner: model, entity_id: model.entity_id,
                           name: user_data["Document Name"].strip, tag_list: user_data["Tags"]&.strip,
                           user_id: import_upload.user_id)

        doc.file = File.open(file_name, "rb")
        [doc.save, doc.errors.full_messages]
      end
    elsif model.nil?
      [false, "#{user_data['Document Type'].strip} not found"]
    else
      [false, "Investor not found"]
    end
  end

  def post_process(_import_upload, context)
    FileUtils.rm_rf context.unzip_dir
  end
end
