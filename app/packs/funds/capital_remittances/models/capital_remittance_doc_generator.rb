class CapitalRemittanceDocGenerator
  include EmailCurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir, :fund_doc_template_name

  # capital_remittance - we want to generate the document for this remittance
  # fund document template - the document are we using as  template for generation
  def initialize(capital_remittance, fund_doc_template, user_id = nil)
    @fund_doc_template_name = fund_doc_template.name

    fund_doc_template.file.download do |tempfile|
      fund_doc_template_path = tempfile.path
      create_working_dir(capital_remittance)
      generate(capital_remittance, fund_doc_template_path)
      upload(fund_doc_template, capital_remittance)
      notify(fund_doc_template, capital_remittance, user_id) if user_id
    ensure
      cleanup
    end
  end

  private

  def working_dir_path(capital_remittance)
    "tmp/fund_doc_generator/capital_remittance/#{rand(1_000_000)}/#{capital_remittance.id}"
  end

  def notify(fund_doc_template, capital_remittance, user_id)
    UserAlert.new(user_id:, message: "Document #{fund_doc_template.name} generated for #{capital_remittance.investor.investor_name}. Please refresh the page.", level: "success").broadcast
  end

  def generate(capital_remittance, fund_doc_template_path)
    odt_file_path = get_odt_file(fund_doc_template_path)

    report = ODFReport::Report.new(odt_file_path) do |r|
      r.add_field :date, Time.zone.today.strftime("%d %B %Y")

      r.add_field :company_name, capital_remittance.entity.name
      r.add_field :fund_name, capital_remittance.fund.name
      r.add_field :folio_id, capital_remittance.folio_id
      r.add_field :fund_details, capital_remittance.fund.details

      r.add_field :investor_name, capital_remittance.investor.investor_name
      r.add_field :percentage_called, capital_remittance.capital_call.percentage_called
      r.add_field :call_amount, money_to_currency(capital_remittance.call_amount)
      r.add_field :due_date, capital_remittance.capital_call.due_date&.strftime("%d %B %Y")
      r.add_field :call_date, capital_remittance.capital_call.call_date&.strftime("%d %B %Y")

      add_amounts(capital_remittance, r)

      generate_custom_fields(r, capital_remittance)

      generate_kyc_fields(r, capital_remittance.capital_commitment.investor_kyc) if capital_remittance.capital_commitment.investor_kyc
    end

    report.generate("#{@working_dir}/CapitalRemittance-#{capital_remittance.id}.odt")
    system("libreoffice --headless --convert-to pdf #{@working_dir}/CapitalRemittance-#{capital_remittance.id}.odt --outdir #{@working_dir}")
  end

  def add_amounts(capital_remittance, report)
    call_amount_in_words = capital_remittance.fund.currency == "INR" ? capital_remittance.call_amount.to_i.rupees.humanize : capital_remittance.call_amount.to_i.to_words.humanize

    report.add_field :call_amount_words, call_amount_in_words
    report.add_field :call_amount, money_to_currency(capital_remittance.call_amount)

    report.add_field :committed_amount, money_to_currency(capital_remittance.capital_commitment.committed_amount)

    collected_amount_in_words = capital_remittance.fund.currency == "INR" ? capital_remittance.collected_amount.to_i.rupees.humanize : capital_remittance.collected_amount.to_i.to_words.humanize

    report.add_field :collected_amount_words, collected_amount_in_words
    report.add_field :collected_amount, money_to_currency(capital_remittance.collected_amount)
  end

  def generate_custom_fields(report, capital_remittance)
    capital_remittance.properties.each do |k, v|
      report.add_field "remittance_#{k}", v
    end

    capital_remittance.fund.properties.each do |k, v|
      report.add_field "fund_#{k}", v
    end

    capital_remittance.capital_call.properties.each do |k, v|
      report.add_field "call_#{k}", v
    end

    capital_remittance.capital_commitment.properties.each do |k, v|
      report.add_field "commitment_#{k}", v
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

  def upload(document, capital_remittance)
    file_name = "#{@working_dir}/CapitalRemittance-#{capital_remittance.id}.pdf"
    Rails.logger.debug { "Uploading new signed file #{file_name}" }

    signed_document = Document.new(document.attributes.slice("entity_id", "name", "folder_id", "orignal", "download", "printing", "user_id"))

    signed_document.name = document.name
    signed_document.file = File.open(file_name, "rb")
    signed_document.from_template = document
    signed_document.owner = capital_remittance
    signed_document.owner_tag = "Generated"

    signed_document.save
  end
end
