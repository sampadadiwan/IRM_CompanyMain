class OfferSpaGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir

  def initialize(offer, template, start_date, end_date, user_id, options: nil)
    Rails.logger.debug { "OfferSpaGenerator #{offer.id}, #{template.name}, #{start_date}, #{end_date}, #{user_id}, #{options} " }

    create_working_dir(offer)
    template_path ||= download_template(template)
    generate(offer, template, template_path)
    generated_document_name = "#{template.name} #{offer.full_name}"
    upload(template, offer, nil, nil, nil, generated_document_name, user_id: user_id)
  ensure
    cleanup
  end

  private

  def working_dir_path(offer)
    "tmp/offer_spa_generator/#{rand(1_000_000)}/#{offer.id}"
  end

  def download_template(template)
    file = template.file.download
    file.path
  end

  # template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(offer, template_document, template_path)
    template = Sablon.template(File.expand_path(template_path))

    context = {}
    context.store  :effective_date, Time.zone.today.strftime("%d %B %Y")
    context.store  :offer, TemplateDecorator.decorate(offer)
    context.store  :sale_entity, offer.secondary_sale.entity
    context.store  :offer_investor, offer.investor
    context.store  :offer_user, offer.user
    allocation_quantity_in_words = offer.entity.currency == "INR" ? offer.allocation_quantity.to_i.rupees.humanize : offer.allocation_quantity.to_i.to_words.humanize
    context.store :allocation_quantity_words, allocation_quantity_in_words

    context.store  :secondary_sale, TemplateDecorator.decorate(offer.secondary_sale)
    context.store  :allocations, TemplateDecorator.decorate(offer.allocations)
    offer_custom_fields = TemplateDecorator.decorate(context[:offer].custom_fields)
    context.store :offer_custom_fields, offer_custom_fields
    context.store :individual, %w[true yes 1].include?(offer.properties["individual"]&.downcase)

    amount_in_words = offer.entity.currency == "INR" ? offer.allocation_amount.to_i.rupees.humanize : offer.allocation_amount.to_i.to_words.humanize
    context.store :allocation_amount_words, amount_in_words
    current_date = Time.zone.now.strftime('%d/%m/%Y')
    context.store :current_date, current_date

    add_fees(context, offer)

    add_image(context, :offer_signature, offer.signature)

    file_name = generated_file_name(offer)
    convert(template, context, file_name)

    additional_footers = []
    additional_headers = []

    add_header_footers(offer, file_name, additional_headers, additional_footers, template_document.name)
  end

  def add_fees(context, offer)
    if offer.secondary_sale.fees
      fees = offer.compute_fees(offer.secondary_sale.fees)
      fee_amount = fees.sum(Money.new(0, offer.entity.currency)) { |i| i[:fee] }

      context.store  :seller_fees, fee_amount
      context.store  :net_allocation_amount, money_to_currency(offer.allocation_amount - fee_amount)
    end

    # context.store "individual", %w[true yes 1].include?(offer.properties["individual"]&.downcase)
  end
end
