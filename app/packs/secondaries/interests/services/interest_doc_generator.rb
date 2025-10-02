class InterestDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir

  def initialize(interest, template, start_date, end_date, user_id, options: nil)
    Rails.logger.debug { "InterestDocGenerator #{interest.id}, #{template.name}, #{start_date}, #{end_date}, #{user_id}, #{options} " }

    create_working_dir(interest)
    template_path ||= download_template(template)
    generate(interest, template, template_path)
    generated_document_name = "#{template.name} #{interest.buyer_entity_name}"
    upload(template, interest, nil, nil, nil, generated_document_name, user_id: user_id)
  ensure
    cleanup
  end

  private

  def working_dir_path(interest)
    "tmp/interest_spa_generator/#{rand(1_000_000)}/#{interest.id}"
  end

  def download_template(template)
    file = template.file.download
    file.path
  end

  # template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(interest, template_document, template_path)
    template = Sablon.template(File.expand_path(template_path))

    context = {}
    context.store  :effective_date, Time.zone.today.strftime("%d %B %Y")
    context.store  :interest, TemplateDecorator.decorate(interest)
    context.store  :sale_entity, interest.secondary_sale.entity
    context.store  :interest_investor, interest.investor
    context.store  :interest_user, interest.user

    interest_quantity_in_words = interest.entity.currency == "INR" ? interest.quantity.to_i.rupees.humanize : interest.quantity.to_i.to_words.humanize
    context.store :interest_quantity_words, interest_quantity_in_words

    interest_price_in_words = interest.entity.currency == "INR" ? interest.price.to_i.rupees.humanize : interest.price.to_i.to_words.humanize
    context.store :interest_price_in_words, interest_price_in_words

    context.store  :secondary_sale, TemplateDecorator.decorate(interest.secondary_sale)
    context.store  :offers, TemplateDecorator.decorate(interest.offers)
    interest_custom_fields = TemplateDecorator.decorate(context[:interest].custom_fields)
    context.store :interest_custom_fields, interest_custom_fields

    current_date = Time.zone.now.strftime('%d/%m/%Y')
    context.store :current_date, current_date

    add_image(context, :interest_signature, interest.signature)

    file_name = generated_file_name(interest)
    convert(template, context, file_name)

    additional_footers = []
    additional_headers = []

    # Get any footers from the interest
    additional_footers += interest.documents.where(name: %w[Footer])
    additional_footers += interest.documents.where(name: ["#{template_document.name} Footer", "#{template_document.name} Signature"])
    additional_headers += interest.documents.where(name: ["Header", "Stamp Paper"])
    additional_headers += interest.documents.where(name: ["#{template_document.name} Header", "#{template_document.name} Stamp Paper"])

    add_header_footers(interest, file_name, additional_headers, additional_footers, template_document.name)
  end
end
