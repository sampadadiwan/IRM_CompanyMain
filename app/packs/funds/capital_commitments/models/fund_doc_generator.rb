class FundDocGenerator
  include EmailCurrencyHelper
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

  def create_working_dir(capital_commitment)
    @working_dir = working_dir_path(capital_commitment)
    FileUtils.mkdir_p @working_dir
  end

  def cleanup
    FileUtils.rm_rf(@working_dir)
  end

  # fund_doc_template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(capital_commitment, fund_doc_template_path, user)
    capital_commitment_signature = nil

    odt_file_path = get_odt_file(fund_doc_template_path)

    report = ODFReport::Report.new(odt_file_path) do |r|
      r.add_field :date, Time.zone.today

      r.add_field :company_name, capital_commitment.entity.name
      r.add_field :fund_name, capital_commitment.fund.name
      r.add_field :commitment_ppm_number, capital_commitment.ppm_number
      r.add_field :fund_details, capital_commitment.fund.details

      r.add_field :investor_name, capital_commitment.investor.investor_name
      r.add_field :commitment_amount, money_to_currency(capital_commitment.committed_amount)

      amount_in_words = capital_commitment.entity.currency == "INR" ? capital_commitment.committed_amount.to_i.rupees.humanize : capital_commitment.committed_amount.to_i.to_words.humanize
      r.add_field :commitment_amount_words, amount_in_words

      generate_custom_fields(r, capital_commitment)

      # Can we have more than one LP signer ?
      capital_commitment_signature = add_signature(r, :investor_signature, user.signature)

      investor_kyc = InvestorKyc.where(investor_id: capital_commitment.investor_id,
                                       entity_id: capital_commitment.entity_id, user_id: user.id).first

      generate_kyc_fields(r, investor_kyc)
    end

    report.generate("#{@working_dir}/CapitalCommitment-#{capital_commitment.id}.odt")
    system("libreoffice --headless --convert-to pdf #{@working_dir}/CapitalCommitment-#{capital_commitment.id}.odt --outdir #{@working_dir}")

    add_header_footers(capital_commitment, "#{@working_dir}/CapitalCommitment-#{capital_commitment.id}.pdf")

    File.delete(capital_commitment_signature) if capital_commitment_signature
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

  def get_odt_file(file_path)
    Rails.logger.debug { "Converting #{file_path} to odt" }
    system("libreoffice --headless --convert-to odt #{file_path} --outdir #{@working_dir}")
    "#{@working_dir}/#{File.basename(file_path, '.*')}.odt"
  end

  def add_signature(report, field_name, signature)
    if signature
      file = signature.download
      sleep(1)
      report.add_image field_name.to_sym, file.path
      file.path
    end
  end

  def add_header_footers(capital_commitment, spa_path)
    header_footer_download_path = []

    # Get the headers
    headers = capital_commitment.documents.where(name: ["Header", "Stamp Paper"])
    header_count = headers.count

    combined_pdf = CombinePDF.new

    # Combine the headers
    if header_count.positive?
      headers.each do |header|
        file = header.file.download
        header_footer_download_path << file.path
        combined_pdf << CombinePDF.load(file.path)
      end
    else
      Rails.logger.debug { "No headers for capital_commitment #{capital_commitment.id}" }
    end

    # Combine the SPA
    combined_pdf << CombinePDF.load(spa_path)

    # Get the footers
    footers = capital_commitment.documents.where(name: %w[Footer Signature])
    footer_count = footers.count

    # Combine the footers
    if footer_count.positive?
      footers.each do |footer|
        file = footer.file.download
        header_footer_download_path << file.path
        combined_pdf << CombinePDF.load(file.path)
      end
    else
      Rails.logger.debug { "No footers for capital_commitment #{capital_commitment.id}" }
    end

    # Overwrite the orig SPA with the one with header and footer
    combined_pdf.save(spa_path)

    header_footer_download_path.each do |file_path|
      File.delete(file_path)
    end
  end

  def upload(document, user, capital_commitment)
    file_name = "#{@working_dir}/CapitalCommitment-#{capital_commitment.id}.pdf"
    Rails.logger.debug { "Uploading new signed file #{file_name}" }

    signed_document = Document.new(document.attributes.slice("entity_id", "name", "folder_id", "download", "printing", "user_id"))

    signed_document.name = document.name + " | #{user.full_name}"
    signed_document.file = File.open(file_name, "rb")
    signed_document.signed_by = user
    signed_document.from_template = document
    signed_document.owner = capital_commitment

    signed_document.save
  end
end
