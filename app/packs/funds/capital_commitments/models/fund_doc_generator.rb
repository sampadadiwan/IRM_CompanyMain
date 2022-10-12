class FundDocGenerator
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
      r.add_field :company_name, capital_commitment.entity.name
      r.add_field :fund_name, capital_commitment.fund.name
      r.add_field :fund_details, capital_commitment.fund.details

      r.add_field :investor_name, capital_commitment.investor.investor_name
      r.add_field :committed_amount, capital_commitment.committed_amount.to_s

      # Can we have more than one LP signer ?
      capital_commitment_signature = add_signature(r, :investor_signature, user.signature)

      investor_kyc = InvestorKyc.where(investor_id: capital_commitment.investor_id,
                                       entity_id: capital_commitment.entity_id, user_id: user.id).first

      generate_kyc_fields(r, investor_kyc)
    end

    report.generate("#{@working_dir}/CapitalCommitment-#{capital_commitment.id}.odt")
    system("libreoffice --headless --convert-to pdf #{@working_dir}/CapitalCommitment-#{capital_commitment.id}.odt --outdir #{@working_dir}")

    File.delete(capital_commitment_signature) if capital_commitment_signature
  end

  def generate_kyc_fields(report, investor_kyc)
    if investor_kyc
      report.add_field :user_first_name, investor_kyc.first_name
      report.add_field :user_middle_name, investor_kyc.middle_name
      report.add_field :user_last_name, investor_kyc.last_name
      report.add_field :user_pan, investor_kyc.PAN
      report.add_field :user_address, investor_kyc.address
      report.add_field :user_bank_account_number, investor_kyc.bank_account_number
      report.add_field :user_ifsc_code, investor_kyc.ifsc_code
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

  def upload(document, user, capital_commitment)
    file_name = "#{@working_dir}/CapitalCommitment-#{capital_commitment.id}.pdf"
    Rails.logger.debug { "Uploading new signed file #{file_name}" }

    signed_document = Document.new(document.attributes.slice("entity_id", "name", "folder_id", "download", "printing", "user_id"))

    signed_document.name = document.name + " | Signed by #{user.full_name}"
    signed_document.file = File.open(file_name, "rb")
    signed_document.signed_by = user
    signed_document.from_template = document
    signed_document.owner = capital_commitment

    signed_document.save
  end
end
