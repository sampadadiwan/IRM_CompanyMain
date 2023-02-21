class CapitalCommitmentDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir, :fund_doc_template_name

  # capital_commitment - we want to generate the document for this CapitalCommitment
  # fund document template - the document are we using as  template for generation
  def initialize(capital_commitment, fund_doc_template, user_id = nil)
    @fund_doc_template_name = fund_doc_template.name

    fund_doc_template.file.download do |tempfile|
      fund_doc_template_path = tempfile.path
      create_working_dir(capital_commitment)
      generate(capital_commitment, fund_doc_template_path)
      upload(fund_doc_template, capital_commitment)
      notify(fund_doc_template, capital_commitment, user_id) if user_id
    ensure
      cleanup
    end
  end

  private

  def working_dir_path(capital_commitment)
    "tmp/fund_doc_generator/#{rand(1_000_000)}/#{capital_commitment.id}"
  end

  def notify(fund_doc_template, capital_commitment, user_id)
    UserAlert.new(user_id:, message: "Document #{fund_doc_template.name} generated for #{capital_commitment.investor_name}. Please refresh the page.", level: "success").broadcast
  end

  # fund_doc_template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(capital_commitment, fund_doc_template_path)
    template = Sablon.template(File.expand_path(fund_doc_template_path))

    amount_in_words = capital_commitment.fund.currency == "INR" ? capital_commitment.committed_amount.to_i.rupees.humanize : capital_commitment.committed_amount.to_i.to_words.humanize

    context = {
      date: Time.zone.today.strftime("%d %B %Y"),
      company_name: capital_commitment.entity.name,
      fund_name: capital_commitment.fund.name,
      commitment_ppm_number: capital_commitment.ppm_number,
      folio_id: capital_commitment.folio_id,
      fund_details: capital_commitment.fund.details,
      investor_name: capital_commitment.investor_name,
      commitment_amount: money_to_currency(capital_commitment.committed_amount),
      commitment_amount_words: amount_in_words
    }

    generate_custom_fields(context, capital_commitment)

    # Can we have more than one LP signer ?
    add_image(context, :investor_signature, capital_commitment.investor_kyc.signature)
    generate_kyc_fields(context, capital_commitment.investor_kyc)
    Rails.logger.debug { "Using context #{context} to render template" }
    template.render_to_file File.expand_path("#{@working_dir}/CapitalCommitment-#{capital_commitment.id}.docx"), context

    system("libreoffice --headless --convert-to pdf #{@working_dir}/CapitalCommitment-#{capital_commitment.id}.docx --outdir #{@working_dir}")

    additional_footers = capital_commitment.documents.where(name: ["#{@fund_doc_template_name} Footer" "#{@fund_doc_template_name} Signature"])
    additional_headers = capital_commitment.documents.where(name: ["#{@fund_doc_template_name} Header", "#{@fund_doc_template_name} Stamp Paper"])
    add_header_footers(capital_commitment, "#{@working_dir}/CapitalCommitment-#{capital_commitment.id}.pdf", additional_headers, additional_footers)
  end

  def generate_custom_fields(context, capital_commitment)
    capital_commitment.properties.each do |k, v|
      context["commitment_#{k}"] = v
    end

    capital_commitment.fund.properties.each do |k, v|
      context["fund_#{k}"] = v
    end
  end

  def generate_kyc_fields(context, investor_kyc)
    if investor_kyc
      context.store :kyc_full_name, investor_kyc.full_name
      context.store :kyc_pan, investor_kyc.PAN
      context.store :kyc_address, investor_kyc.address
      context.store :kyc_bank_account_number, investor_kyc.bank_account_number
      context.store :kyc_ifsc_code, investor_kyc.ifsc_code

      investor_kyc.properties.each do |k, v|
        context.store "kyc_#{k}", v
      end
    end
  end

  def upload(document, capital_commitment)
    file_name = "#{@working_dir}/CapitalCommitment-#{capital_commitment.id}.pdf"
    Rails.logger.debug { "Uploading new signed file #{file_name}" }

    signed_document = Document.new(document.attributes.slice("entity_id", "name", "orignal", "download", "printing", "user_id"))

    signed_document.name = document.name
    signed_document.file = File.open(file_name, "rb")
    signed_document.from_template = document
    signed_document.owner = capital_commitment
    signed_document.owner_tag = "Generated"

    signed_document.save
  end

  def add_image2(context, field_name, image)
    if image
      file = image.download
      stored_file_path = "#{@working_dir}/#{File.basename(file.path)}"

      FileUtils.mv(file.path, stored_file_path)

      context.store "image:#{field_name}", stored_file_path
      stored_file_path
    end
  end
end
