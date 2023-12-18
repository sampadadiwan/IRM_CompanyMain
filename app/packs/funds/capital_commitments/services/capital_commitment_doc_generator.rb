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

    context = {
      effective_date: Time.zone.today.strftime("%d %B %Y"),
      entity: capital_commitment.entity,
      fund: TemplateDecorator.decorate(capital_commitment.fund),
      capital_commitment: TemplateDecorator.decorate(capital_commitment),
      investor_kyc: TemplateDecorator.decorate(capital_commitment.investor_kyc),
      fund_unit_setting: TemplateDecorator.decorate(capital_commitment.fund_unit_setting)
    }

    # Can we have more than one LP signer ?
    add_image(context, :investor_signature, capital_commitment.investor_kyc.signature)
    Rails.logger.debug { "Using context #{context} to render template" }

    file_name = "#{@working_dir}/CapitalCommitment-#{capital_commitment.id}"
    convert(template, context, file_name)

    additional_footers = capital_commitment.documents.where(name: ["#{@fund_doc_template_name} Footer" "#{@fund_doc_template_name} Signature"])
    additional_headers = capital_commitment.documents.where(name: ["#{@fund_doc_template_name} Header", "#{@fund_doc_template_name} Stamp Paper"])
    add_header_footers(capital_commitment, "#{@working_dir}/CapitalCommitment-#{capital_commitment.id}.pdf", additional_headers, additional_footers)
  end
end
