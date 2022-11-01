class OfferSpaGenerator
  attr_accessor :working_dir

  def initialize(offer, master_spa_path = nil)
    create_working_dir(offer)
    master_spa_path ||= download_master_spa(offer)
    generate(offer, master_spa_path)
    attach(offer)
  ensure
    cleanup
  end

  private

  def working_dir_path(offer)
    "tmp/offer_spa_generator/#{offer.id}"
  end

  def create_working_dir(offer)
    @working_dir = working_dir_path(offer)
    FileUtils.mkdir_p @working_dir
  end

  def cleanup
    FileUtils.rm_rf(@working_dir)
  end

  def download_master_spa(offer)
    file = offer.secondary_sale.spa.download
    file.path
  end

  def get_odt_file(file_path)
    Rails.logger.debug { "Converting #{file_path} to odt" }
    system("libreoffice --headless --convert-to odt #{file_path} --outdir #{@working_dir}")
    "#{@working_dir}/#{File.basename(file_path, '.*')}.odt"
  end

  # master_spa_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(offer, master_spa_path)
    offer_signature = nil
    interest_signature = nil

    odt_file_path = get_odt_file(master_spa_path)

    report = ODFReport::Report.new(odt_file_path) do |r|
      r.add_field :effective_date, Time.zone.today
      r.add_field :offer_quantity, offer.quantity
      r.add_field :company_name, offer.entity.name

      r.add_field :allocation_quantity, offer.allocation_quantity
      r.add_field :share_price, offer.secondary_sale.final_price
      r.add_field :allocation_amount, offer.allocation_amount.to_s

      r.add_field :seller_name, offer.full_name
      r.add_field :seller_address, offer.address
      r.add_field :seller_pan, offer.PAN
      r.add_field :seller_email, offer.user.email
      r.add_field :seller_bank_account, offer.bank_account_number
      r.add_field :seller_ifsc_code, offer.ifsc_code

      offer_signature = add_signature(r, :seller_signature, offer.signature)

      r.add_field :buyer_name, offer.interest&.buyer_entity_name
      r.add_field :buyer_address, offer.interest&.address
      r.add_field :buyer_email, offer.interest&.email
      r.add_field :buyer_pan, offer.interest&.PAN
      r.add_field :buyer_contact, offer.interest&.contact_name

      interest_signature = add_signature(r, :buyer_signature, offer.interest&.signature)
    end

    report.generate("#{@working_dir}/Offer-#{offer.id}.odt")
    system("libreoffice --headless --convert-to pdf #{@working_dir}/Offer-#{offer.id}.odt --outdir #{@working_dir}")

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
    offer.spa = File.open("#{@working_dir}/Offer-#{offer.id}.pdf", "rb")
    offer.save
  end
end
