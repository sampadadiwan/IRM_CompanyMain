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
    report = ODFReport::Report.new(master_spa_path) do |r|
      r.add_field :effectivedate, Time.zone.today
      r.add_field :allocationqty, offer.allocation_quantity
      r.add_field :shareprice, offer.secondary_sale.final_price
      r.add_field :allocationamount, offer.allocation_amount

      r.add_field :sellername, offer.user.full_name
      r.add_field :selleraddress, offer.address
      r.add_field :selleremail, offer.user.email
      r.add_field :sellerbankaccount, offer.bank_account_number
      r.add_field :sellerifsccode, offer.ifsc_code

      r.add_field :buyername, offer.interest&.buyer_entity_name
      r.add_field :buyeraddress, offer.interest&.address
      r.add_field :buyeremail, offer.interest&.email
      r.add_field :buyercontact, offer.interest&.contact_name

      r.add_field :companyname, offer.entity.name

      if offer.signature
        signature = offer.signature.download
        r.add_image :buyersignature, signature.path
      end
    end

    report.generate("tmp/Offer-#{offer.id}.odt")
    system("libreoffice --headless --convert-to pdf tmp/Offer-#{offer.id}.odt --outdir tmp")

    if offer.signature
        File.delete(signature)
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
