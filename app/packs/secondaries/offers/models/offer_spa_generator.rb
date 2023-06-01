class OfferSpaGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir

  def initialize(offer, template)
    # Cleanup esigns first
    OfferEsignProvider.new(offer).cleanup_prev

    create_working_dir(offer)
    template_path ||= download_template(template)
    generate(offer, template_path)
    upload(template, offer)
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
  def generate(offer, template_path)
    template = Sablon.template(File.expand_path(template_path))

    context = {}
    context.store  :effective_date, Time.zone.today.strftime("%d %B %Y")
    context.store  :offer_quantity, offer.quantity
    context.store  :company_name, offer.entity.name

    context.store  :allocation_quantity, offer.allocation_quantity
    context.store  :share_price, offer.secondary_sale.final_price
    context.store  :allocation_amount, money_to_currency(offer.allocation_amount)

    amount_in_words = offer.entity.currency == "INR" ? offer.allocation_amount.to_i.rupees.humanize : offer.allocation_amount.to_i.to_words.humanize
    context.store :allocation_amount_words, amount_in_words

    add_seller_fields(context, offer)
    add_image(context, :seller_signature, offer.signature)

    add_buyer_fields(context, offer)
    add_image(context, :buyer_signature, offer.interest&.signature)

    file_name = "#{@working_dir}/Offer-#{offer.id}"
    convert(template, context, file_name)

    additional_footers = nil
    additional_headers = nil
    if offer.interest
      # Get any footers from the interest
      additional_footers = offer.interest.documents.where(name: %w[Footer Signature])
      additional_headers = offer.interest.documents.where(name: ["Header", "Stamp Paper"])
    end
    add_header_footers(offer, "#{@working_dir}/Offer-#{offer.id}.pdf", additional_headers, additional_footers)
  end

  def add_seller_fields(context, offer)
    context.store  :seller_name, offer.full_name
    context.store  :seller_address, offer.address
    context.store  :seller_pan, offer.PAN
    context.store  :seller_email, offer.user.email
    context.store  :seller_bank_account, offer.bank_account_number
    context.store  :seller_ifsc_code, offer.ifsc_code
    context.store  :seller_demat, offer.demat
    context.store  :seller_city, offer.city

    if offer.secondary_sale.fees
      fees = offer.compute_fees(offer.secondary_sale.fees)
      fee_amount = fees.sum(Money.new(0, offer.entity.currency)) { |i| i[:fee] }

      context.store  :seller_fees, fee_amount
      context.store  :net_allocation_amount, money_to_currency(offer.allocation_amount - fee_amount)
    end

    offer.properties.each do |k, v|
      context.store  "seller_#{k}", v
    end
  end

  def add_buyer_fields(context, offer)
    if offer.interest
      context.store  :buyer_name, offer.interest.buyer_entity_name
      context.store  :buyer_address, offer.interest.address
      context.store  :buyer_email, offer.interest.email
      context.store  :buyer_pan, offer.interest.PAN
      context.store  :buyer_city, offer.interest.city
      context.store  :buyer_demat, offer.interest.demat
      context.store  :buyer_contact, offer.interest.contact_name

      offer.interest.properties.each do |k, v|
        context.store "buyer_#{k}", v
      end
    end
  end

  def upload(document, offer)
    file_name = "#{@working_dir}/Offer-#{offer.id}.pdf"
    Rails.logger.debug { "Uploading new file #{file_name}" }

    new_generated_doc = Document.new(document.attributes.slice("entity_id", "name", "orignal", "download", "printing", "user_id"))

    # Delete SOA for the same start_date, end_date
    offer.documents.where(name: new_generated_doc.name).each(&:destroy)

    # Create and attach the new SOA
    new_generated_doc.file = File.open(file_name, "rb")
    new_generated_doc.from_template = document
    new_generated_doc.owner = offer
    new_generated_doc.owner_tag = "Generated"
    new_generated_doc.send_email = false
    new_generated_doc.locked = true
    new_generated_doc.save
  end
end
