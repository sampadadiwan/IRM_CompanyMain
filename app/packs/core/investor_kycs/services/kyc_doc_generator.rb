class KycDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  # investor_kyc - we want to generate the document for this CapitalCommitment
  # fund document template - the document are we using as  template for generation
  def initialize(investor_kyc, doc_template, start_date, end_date, user_id = nil)
    doc_template.file.download do |tempfile|
      doc_template_path = tempfile.path
      create_working_dir(investor_kyc)
      generate(investor_kyc, start_date, end_date, doc_template_path)
      upload(doc_template, investor_kyc, start_date, end_date)
      notify(doc_template, investor_kyc, user_id) if user_id
    ensure
      cleanup
    end
  end

  private

  def notify(doc_template, investor_kyc, user_id)
    send_notification("KYC #{doc_template.name} generated for #{investor_kyc.full_name}. Please refresh the page.", user_id)
  end

  # doc_template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(investor_kyc, start_date, end_date, doc_template_path)
    template = Sablon.template(File.expand_path(doc_template_path))

    investor_kyc.entity.currency == "INR" ? investor_kyc.committed_amount.to_i.rupees.humanize : investor_kyc.committed_amount.to_i.to_words.humanize

    context = {
      date: Time.zone.today.strftime("%d %B %Y"),
      start_date:,
      format_start_date: Time.zone.parse(start_date).strftime("%d %B %Y"),
      end_date:,
      format_end_date: Time.zone.parse(end_date).strftime("%d %B %Y"),
      investor_kyc: TemplateDecorator.decorate(investor_kyc),
      entity: investor_kyc.entity,

      capital_commitments: TemplateDecorator.decorate_collection(investor_kyc.capital_commitments),
      capital_remittances: TemplateDecorator.decorate_collection(investor_kyc.capital_remittances),
      capital_remittance_payments: TemplateDecorator.decorate_collection(investor_kyc.capital_remittance_payments),
      capital_distribution_payments: TemplateDecorator.decorate_collection(investor_kyc.capital_distribution_payments)

    }

    generate_custom_fields(context, investor_kyc)

    Rails.logger.debug { "Using context #{context.keys} to render template" }
    Rails.logger.debug "Rendering template"

    file_name = "#{@working_dir}/KYC-#{investor_kyc.id}"
    convert(template, context, file_name)
  end

  def generate_custom_fields(context, investor_kyc)
    investor_kyc.properties.each do |k, v|
      context.store "kyc_#{k}", v
    end
  end

  def upload(document, investor_kyc, start_date, end_date)
    file_name = "#{@working_dir}/KYC-#{investor_kyc.id}.pdf"
    Rails.logger.debug { "Uploading new generated file #{file_name}" }

    new_generated_doc = Document.new(document.attributes.slice("entity_id", "name", "orignal", "download", "printing", "user_id"))

    doc_name = "#{new_generated_doc.name}-#{start_date}-#{end_date}"
    # Delete KYC doc for the same start_date, end_date
    investor_kyc.documents.where(name: doc_name).find_each(&:destroy)

    # Create and attach the new KYC doc
    new_generated_doc.name = doc_name
    new_generated_doc.file = File.open(file_name, "rb")
    new_generated_doc.from_template = document
    new_generated_doc.owner = investor_kyc
    new_generated_doc.owner_tag = "Generated"
    new_generated_doc.send_email = false

    new_generated_doc.save
  end
end
