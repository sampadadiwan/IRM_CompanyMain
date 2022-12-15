class EoiDocGenerator
  include EmailCurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir, :io_doc_template_name

  # expression_of_interest - we want to generate the document for this ExpressionOfInterest
  # investment_opportunity document template - the document are we using as  template for generation
  def initialize(expression_of_interest, io_doc_template)
    @io_doc_template_name = io_doc_template.name

    io_doc_template.file.download do |tempfile|
      io_doc_template_path = tempfile.path
      create_working_dir(expression_of_interest)
      generate(expression_of_interest, io_doc_template_path)
      upload(io_doc_template, expression_of_interest)
    ensure
      cleanup
    end
  end

  private

  def working_dir_path(expression_of_interest)
    "tmp/eoi_doc_generator/#{expression_of_interest.id}"
  end

  # io_doc_template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(expression_of_interest, io_doc_template_path)
    odt_file_path = get_odt_file(io_doc_template_path)

    report = ODFReport::Report.new(odt_file_path) do |r|
      r.add_field :date, Time.zone.today.strftime("%d %B %Y")

      r.add_field :company_name, expression_of_interest.entity.name
      r.add_field :investment_opportunity_name, expression_of_interest.investment_opportunity.company_name
      r.add_field :investment_opportunity_details, expression_of_interest.investment_opportunity.details&.to_plain_text
      r.add_field :investor_name, expression_of_interest.investor.investor_name
      r.add_field :amount, money_to_currency(expression_of_interest.amount)

      amount_in_words = expression_of_interest.investment_opportunity.currency == "INR" ? expression_of_interest.amount.to_i.rupees.humanize : expression_of_interest.amount.to_i.to_words.humanize
      r.add_field :amount_words, amount_in_words

      generate_custom_fields(r, expression_of_interest)

      investor_kyc = InvestorKyc.where(investor_id: expression_of_interest.investor_id,
                                       entity_id: expression_of_interest.entity_id).first

      # Can we have more than one LP signer ?
      add_image(r, :investor_signature, investor_kyc.signature)
      generate_kyc_fields(r, investor_kyc)
    end

    report.generate("#{@working_dir}/ExpressionOfInterest-#{expression_of_interest.id}.odt")
    system("libreoffice --headless --convert-to pdf #{@working_dir}/ExpressionOfInterest-#{expression_of_interest.id}.odt --outdir #{@working_dir}")

    additional_footers = expression_of_interest.documents.where(name: ["#{@io_doc_template_name} Footer" "#{@io_doc_template_name} Signature"])
    additional_headers = expression_of_interest.documents.where(name: ["#{@io_doc_template_name} Header", "#{@io_doc_template_name} Stamp Paper"])
    add_header_footers(expression_of_interest, "#{@working_dir}/ExpressionOfInterest-#{expression_of_interest.id}.pdf", additional_headers, additional_footers)
  end

  def generate_custom_fields(report, expression_of_interest)
    expression_of_interest.properties.each do |k, v|
      report.add_field "eoi_#{k}", v
    end

    expression_of_interest.investment_opportunity.properties.each do |k, v|
      report.add_field "investment_opportunity_#{k}", v
    end
  end

  def generate_kyc_fields(report, investor_kyc)
    if investor_kyc
      report.add_field :kyc_full_name, investor_kyc.full_name
      report.add_field :kyc_pan, investor_kyc.PAN
      report.add_field :kyc_address, investor_kyc.address
      report.add_field :kyc_bank_account_number, investor_kyc.bank_account_number
      report.add_field :kyc_ifsc_code, investor_kyc.ifsc_code

      investor_kyc.properties.each do |k, v|
        report.add_field "kyc_#{k}", v
      end
    end
  end

  def upload(document, expression_of_interest)
    file_name = "#{@working_dir}/ExpressionOfInterest-#{expression_of_interest.id}.pdf"
    Rails.logger.debug { "Uploading new signed file #{file_name}" }

    signed_document = Document.new(document.attributes.slice("entity_id", "name", "folder_id", "orignal", "download", "printing", "user_id"))

    signed_document.name = document.name
    signed_document.file = File.open(file_name, "rb")
    signed_document.from_template = document
    signed_document.owner = expression_of_interest
    signed_document.owner_tag = "Generated"

    signed_document.save
  end
end
