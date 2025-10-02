class EoiDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir, :io_doc_template_name

  # expression_of_interest - we want to generate the document for this ExpressionOfInterest
  # investment_opportunity document template - the document are we using as  template for generation
  def initialize(expression_of_interest, io_doc_template, user_id = nil, options: nil)
    Rails.logger.debug { "EoiDocGenerator #{expression_of_interest.id}, #{io_doc_template.name}, #{user_id}, #{options} " }

    @io_doc_template_name = io_doc_template.name

    io_doc_template.file.download do |tempfile|
      io_doc_template_path = tempfile.path
      create_working_dir(expression_of_interest)
      generate(expression_of_interest, io_doc_template_path)
      upload(io_doc_template, expression_of_interest, user_id: user_id)
      notify(io_doc_template, expression_of_interest, user_id) if user_id
    ensure
      cleanup
    end
  end

  private

  def notify(io_doc_template, expression_of_interest, user_id)
    UserAlert.new(user_id:, message: "Document #{io_doc_template.name} generated for #{expression_of_interest.investor.investor_name}. Please refresh the page.", level: "success").broadcast
  end

  def working_dir_path(expression_of_interest)
    "tmp/eoi_doc_generator/#{rand(1_000_000)}/#{expression_of_interest.id}"
  end

  # io_doc_template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(expression_of_interest, io_doc_template_path)
    template = Sablon.template(File.expand_path(io_doc_template_path))

    context = {}

    context.store  :date, Time.zone.today.strftime("%d %B %Y")

    context.store  :expression_of_interest, expression_of_interest
    context.store  :investment_opportunity, expression_of_interest.investment_opportunity
    context.store  :amount, money_to_currency(expression_of_interest.amount)

    amount_in_words = expression_of_interest.investment_opportunity.currency == "INR" ? expression_of_interest.amount.to_i.rupees.humanize : expression_of_interest.amount.to_i.to_words.humanize
    context.store :amount_words, amount_in_words

    # Can we have more than one LP signer ?
    add_image(context, :investor_signature, expression_of_interest.investor_kyc.signature)

    file_name = generated_file_name(expression_of_interest)
    convert(template, context, file_name)

    additional_footers = expression_of_interest.documents.where(name: ["#{@io_doc_template_name} Footer" + "#{@io_doc_template_name} Signature"])
    additional_headers = expression_of_interest.documents.where(name: ["#{@io_doc_template_name} Header", "#{@io_doc_template_name} Stamp Paper"])
    add_header_footers(expression_of_interest, file_name, additional_headers, additional_footers)
  end
end
