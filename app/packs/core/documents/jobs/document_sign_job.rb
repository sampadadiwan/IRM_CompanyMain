class DocumentSignJob < ApplicationJob
  queue_as :default

  def perform(document_id, user_id)
    document = Document.find(document_id).freeze
    user = User.find(user_id)

    if document.signature_enabled && user.signature
      Chewy.strategy(:sidekiq) do
        file_path = download_file(document)
        convert(file_path, document, user)
        upload(document, user)
        cleanup(document, user)
      end
    else
      logger.error "Document #{document_id} is not signature enabled" unless document.signature_enabled
      logger.error "User signature not available" unless user.signature
    end
  end

  private

  def upload(document, user)
    file_name = "tmp/Document-#{document.id}-#{user.id}.signed.pdf"
    Rails.logger.debug { "Uploading new signed file #{file_name}" }

    signed_document = Document.new(document.attributes.slice("entity_id", "name", "folder_id", "download", "printing", "owner_type", "owner_id", "user_id"))

    signed_document.name = document.name + " - Signed: #{user.full_name}"
    signed_document.file = File.open(file_name, "rb")
    signed_document.signed_by = user
    signed_document.from_template = document
    signed_document.save

    File.delete(file_name)
  end

  def cleanup(document, user); end

  def download_file(document)
    file = document.file.download
    file.path
  end

  # file_path is a docx template file with a placeholder singature image named investorsignature
  def convert(file_path, document, user)
    # Convert from docx to odt, odt is the only format supported by the ODF gem
    file_name = "Document-#{document.id}-#{user.id}"
    odt_file_path = get_odt_file(file_path)

    # Generate a new odt file inserting the signature image from the user
    Rails.logger.debug { "Signing document #{odt_file_path}" }
    user_signature = nil
    report = ODFReport::Report.new(odt_file_path) do |r|
      user_signature = add_signature(r, :investorsignature, user.signature)
    end
    report.generate("tmp/#{file_name}.signed.odt")

    # Convert the signed odt to pdf
    Rails.logger.debug { "Converting tmp/#{file_name}.signed.odt to pdf" }
    system("libreoffice --headless --convert-to pdf tmp/#{file_name}.signed.odt --outdir tmp")

    Rails.logger.debug "Deleting tmp files"
    File.delete(user_signature) if user_signature
    File.delete(odt_file_path) if odt_file_path
    File.delete(file_path) if odt_file_path
  end

  def get_odt_file(file_path)
    Rails.logger.debug { "Converting #{file_path} to odt" }
    system("libreoffice --headless --convert-to odt #{file_path} --outdir tmp")
    "tmp/#{File.basename(file_path, '.*')}.odt"
  end

  def add_signature(report, field_name, signature)
    if signature
      file = signature.download
      sleep(1)
      report.add_image field_name.to_sym, file.path
      file.path
    end
  end
end
