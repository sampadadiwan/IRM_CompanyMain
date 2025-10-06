class CapitalCommitmentDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir, :fund_doc_template_name

  # capital_commitment - we want to generate the document for this CapitalCommitment
  # fund document template - the document are we using as  template for generation
  def initialize(capital_commitment, fund_doc_template, start_date, end_date, user_id, options: nil)
    Rails.logger.debug { "CapitalCommitmentDocGenerator #{capital_commitment.id}, #{fund_doc_template.name}, #{start_date}, #{end_date}, #{user_id}, #{options} " }

    @fund_doc_template_name = fund_doc_template.name

    fund_doc_template.file.download do |tempfile|
      fund_doc_template_path = tempfile.path
      create_working_dir(capital_commitment)
      generate(capital_commitment, fund_doc_template_path, fund_doc_template)
      upload(fund_doc_template, capital_commitment, user_id: user_id)
      notify(fund_doc_template, capital_commitment, user_id) if user_id
    ensure
      cleanup
    end
  end

  private

  def notify(fund_doc_template, capital_commitment, user_id)
    UserAlert.new(user_id:, message: "Document #{fund_doc_template.name} generated for #{capital_commitment.investor_name}. Please refresh the page.", level: "success").broadcast
  end

  def generate(capital_commitment, fund_doc_template_path, fund_doc_template)
    template = Sablon.template(File.expand_path(fund_doc_template_path))

    context = {
      date: Time.zone.today.strftime("%d %B %Y"),
      entity: capital_commitment.entity,
      fund: TemplateDecorator.decorate(capital_commitment.fund),
      capital_commitment: TemplateDecorator.decorate(capital_commitment),
      investor_kyc: TemplateDecorator.decorate(capital_commitment.investor_kyc),
      fund_unit_setting: TemplateDecorator.decorate(capital_commitment.fund_unit_setting)
    }

    # Can we have more than one LP signer ?
    add_image(context, :investor_signature, capital_commitment.investor_kyc.signature)
    add_image(context, :profile_image, capital_commitment.investor_kyc.documents.where(owner_tag: "Profile Image").first&.file)
    add_image(context, :profile_image_2, capital_commitment.investor_kyc.documents.where(owner_tag: "Profile Image 2").first&.file) # rubocop:disable Naming/VariableNumber

    Rails.logger.debug { "Using context #{context} to render template" }

    file_name = generated_file_name(capital_commitment)
    convert(template, context, file_name)

    # Sometimes we have additional documents we want to append to the contribution agreement.
    # E.x Kyc PAN, KYC address proof etc
    additional_footers = []

    append_to_commitment_agreement = capital_commitment.entity.entity_setting.append_to_commitment_agreement
    if fund_doc_template.template_docs_to_append.present?
      doc_names = fund_doc_template.template_docs_to_append.downcase.split(",").map(&:strip)
      # Ensure the additional_footers are in the order specified in the append_to_commitment_agreement
      footer_docs = capital_commitment.investor_kyc.documents.where(name: doc_names).to_a.sort_by { |doc| doc_names.index(doc.name.downcase) || Float::INFINITY }
      Rails.logger.debug { "Appending #{footer_docs.map(&:name)} to the commitment agreement" }
      additional_footers += footer_docs
    end

    additional_footers += capital_commitment.documents.where(name: ["#{@fund_doc_template_name} Footer", "#{@fund_doc_template_name} Signature"])
    additional_headers = capital_commitment.documents.where(name: ["#{@fund_doc_template_name} Header", "#{@fund_doc_template_name} Stamp Paper"])
    add_header_footers(capital_commitment, file_name, additional_headers, additional_footers)
  end
end
