class OfferSpaGenerator
  def initialize(offer, master_spa_path = nil)
    master_spa_path ||= download_master_spa(offer)
    generate(offer, master_spa_path)
    attach(offer)
    cleanup(offer)
  end

  def download_master_spa(offer)
    file = offer.secondary_sale.spa.download
    file.path
  end

  # master_spa_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(offer, master_spa_path)
    offer_signature = nil
    interest_signature = nil

    report = ODFReport::Report.new(master_spa_path) do |r|
      r.add_field :effectivedate, Time.zone.today
      r.add_field :offerquantity, offer.quantity

      r.add_field :allocationqty, offer.allocation_quantity
      r.add_field :shareprice, offer.secondary_sale.final_price
      r.add_field :allocationamount, offer.allocation_amount

      r.add_field :sellername, [offer.first_name, offer.middle_name, offer.last_name].compact.join(" ")
      r.add_field :selleraddress, offer.address
      r.add_field :sellerpan, offer.PAN
      r.add_field :selleremail, offer.user.email
      r.add_field :sellerbankaccount, offer.bank_account_number
      r.add_field :sellerifsccode, offer.ifsc_code

      offer_signature = add_signature(r, :sellersignature, offer.signature)

      r.add_field :buyername, offer.interest&.buyer_entity_name
      r.add_field :buyeraddress, offer.interest&.address
      r.add_field :buyeremail, offer.interest&.email
      r.add_field :buyerpan, offer.interest&.PAN
      r.add_field :buyercontact, offer.interest&.contact_name

      interest_signature = add_signature(r, :buyersignature, offer.interest&.signature)

      r.add_field :companyname, offer.entity.name
    end

    report.generate("tmp/Offer-#{offer.id}.odt")
    system("libreoffice --headless --convert-to pdf tmp/Offer-#{offer.id}.odt --outdir tmp")

    File.delete(offer_signature) if offer_signature
    File.delete(interest_signature) if interest_signature
  end

  def add_signature(report, field_name, signature)
    if signature
      file = signature.download
      sleep(1)
      report.add_image field_name.to_sym, file.path
      file.path
    end
  end

  def attach(offer)
    offer.spa = File.open("tmp/Offer-#{offer.id}.pdf", "rb")
    offer.save
  end

  def cleanup(offer)
    File.delete("tmp/Offer-#{offer.id}.odt")
    File.delete("tmp/Offer-#{offer.id}.pdf")
  end
end
