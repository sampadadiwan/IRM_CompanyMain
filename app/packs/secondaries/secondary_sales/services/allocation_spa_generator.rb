class AllocationSpaGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir

  def initialize(allocation, template, start_date, end_date, user_id, options: nil)
    Rails.logger.info "AllocationSpaGenerator: #{allocation.id} #{template.name} #{start_date} #{end_date} #{user_id} #{options}"
    create_working_dir(allocation)
    template_path ||= download_template(template)
    generate(allocation, template, template_path)
    generated_document_name = "#{template.name} #{allocation.offer.full_name} #{allocation.interest.buyer_entity_name}"
    upload(template, allocation, nil, nil, nil, generated_document_name, user_id: user_id)
  ensure
    cleanup
  end

  private

  def working_dir_path(allocation)
    "tmp/allocation_spa_generator/#{rand(1_000_000)}/#{allocation.id}"
  end

  def download_template(template)
    file = template.file.download
    file.path
  end

  # template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(allocation, template_document, template_path)
    template = Sablon.template(File.expand_path(template_path))

    context = {}
    context.store  :effective_date, Time.zone.today.strftime("%d %B %Y")
    context.store  :allocation, TemplateDecorator.decorate(allocation)
    context.store  :sale_entity, allocation.secondary_sale.entity
    context.store  :offer, TemplateDecorator.decorate(allocation.offer)
    context.store  :interest, TemplateDecorator.decorate(allocation.interest)
    allocation_quantity_in_words = allocation.entity.currency == "INR" ? allocation.quantity.to_i.rupees.humanize : allocation.quantity.to_i.to_words.humanize
    context.store :allocation_quantity_in_words, allocation_quantity_in_words

    context.store :secondary_sale, TemplateDecorator.decorate(allocation.secondary_sale)

    allocation_custom_fields = TemplateDecorator.decorate(allocation.custom_fields)
    context.store :allocation_custom_fields, allocation_custom_fields

    context.store :individual, %w[true yes 1].include?(allocation.offer.properties["individual"]&.downcase)

    amount_in_words = allocation.entity.currency == "INR" ? allocation.amount.to_i.rupees.humanize : allocation.amount.to_i.to_words.humanize
    context.store :allocation_allocation_amount_words, amount_in_words
    current_date = Time.zone.now.strftime('%d/%m/%Y')
    context.store :current_date, current_date

    # add_fees(context, allocation)

    add_image(context, :offer_signature, allocation.offer.signature)
    add_image(context, :interest_signature, allocation.interest.signature)

    file_name = generated_file_name(allocation)
    convert(template, context, file_name)

    additional_footers = []
    additional_headers = []
    if allocation.interest
      # Get any footers from the interest
      additional_footers += allocation.interest.documents.where(name: %w[Footer])
      additional_footers += allocation.interest.documents.where(name: ["#{template_document.name} Footer", "#{template_document.name} Signature"])
      additional_headers += allocation.interest.documents.where(name: ["Header", "Stamp Paper"])
      additional_headers += allocation.interest.documents.where(name: ["#{template_document.name} Header", "#{template_document.name} Stamp Paper"])
    end

    add_header_footers(allocation, file_name, additional_headers, additional_footers, template_document.name)
  end

  def add_fees(context, allocation)
    if allocation.secondary_sale.fees
      fees = allocation.compute_fees(allocation.secondary_sale.fees)
      fee_amount = fees.sum(Money.new(0, allocation.entity.currency)) { |i| i[:fee] }

      context.store  :seller_fees, fee_amount
      context.store  :net_allocation_amount, money_to_currency(allocation.allocation_amount - fee_amount)
    end

    # context.store "individual", %w[true yes 1].include?(allocation.properties["individual"]&.downcase)
  end
end
