class CapitalCommitmentDocGenerator
  include EmailCurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir

  # capital_commitment - we want to generate the document for this CapitalCommitment
  # fund document template - the document are we using as  template for generation
  # user - The investor user, whose kyc data and signature will be used
  def initialize(capital_commitment, fund_doc_template, user)
    fund_doc_template.file.download do |tempfile|
      fund_doc_template_path = tempfile.path
      create_working_dir(capital_commitment)
      generate(capital_commitment, fund_doc_template_path, user)
      upload(fund_doc_template, user, capital_commitment)
    ensure
      cleanup
    end
  end

  private

  def working_dir_path(capital_commitment)
    "tmp/fund_doc_generator/#{capital_commitment.id}"
  end

  # fund_doc_template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(capital_commitment, fund_doc_template_path, user)
    odt_file_path = get_odt_file(fund_doc_template_path)

    report = ODFReport::Report.new(odt_file_path) do |r|
      r.add_field :date, Time.zone.today.strftime("%d %B %Y")

      r.add_field :company_name, capital_commitment.entity.name
      r.add_field :fund_name, capital_commitment.fund.name
      r.add_field :commitment_ppm_number, capital_commitment.ppm_number
      r.add_field :fund_details, capital_commitment.fund.details

      r.add_field :investor_name, capital_commitment.investor.investor_name
      r.add_field :commitment_amount, money_to_currency(capital_commitment.committed_amount)

      amount_in_words = capital_commitment.fund.currency == "INR" ? capital_commitment.committed_amount.to_i.rupees.humanize : capital_commitment.committed_amount.to_i.to_words.humanize
      r.add_field :commitment_amount_words, amount_in_words

      generate_custom_fields(r, capital_commitment)

      # Can we have more than one LP signer ?
      add_image(r, :investor_signature, user.signature)

      investor_kyc = InvestorKyc.where(investor_id: capital_commitment.investor_id,
                                       entity_id: capital_commitment.entity_id, user_id: user.id).first

      generate_kyc_fields(r, investor_kyc)
    end

    report.generate("#{@working_dir}/CapitalCommitment-#{capital_commitment.id}.odt")
    system("libreoffice --headless --convert-to pdf #{@working_dir}/CapitalCommitment-#{capital_commitment.id}.odt --outdir #{@working_dir}")

    additional_footers = capital_commitment.fund.documents.where(name: %w[Footer Signature])
    additional_headers = capital_commitment.fund.documents.where(name: ["Header", "Stamp Paper"])
    add_header_footers(capital_commitment, "#{@working_dir}/CapitalCommitment-#{capital_commitment.id}.pdf", additional_headers, additional_footers)
  end

  def generate_custom_fields(report, capital_commitment)
    capital_commitment.properties.each do |k, v|
      report.add_field "commitment_#{k}", v
    end

    capital_commitment.fund.properties.each do |k, v|
      report.add_field "fund_#{k}", v
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

  def upload(document, user, capital_commitment)
    file_name = "#{@working_dir}/CapitalCommitment-#{capital_commitment.id}.pdf"
    Rails.logger.debug { "Uploading new signed file #{file_name}" }

    signed_document = Document.new(document.attributes.slice("entity_id", "name", "folder_id", "orignal", "download", "printing", "user_id"))

    signed_document.name = document.name
    signed_document.file = File.open(file_name, "rb")
    signed_document.signed_by = user
    signed_document.from_template = document
    signed_document.owner = capital_commitment

    signed_document.save
  end
end
