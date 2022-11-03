# require 'rmagick'

class OfferSpaGenerator
  include EmailCurrencyHelper
  # include Magick

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
    stamp_paper_download_paths = []

    odt_file_path = get_odt_file(master_spa_path)

    report = ODFReport::Report.new(odt_file_path) do |r|
      r.add_field :effective_date, Time.zone.today
      r.add_field :offer_quantity, offer.quantity
      r.add_field :company_name, offer.entity.name

      r.add_field :allocation_quantity, offer.allocation_quantity
      r.add_field :share_price, offer.secondary_sale.final_price
      r.add_field :allocation_amount, money_to_currency(offer.allocation_amount)

      add_seller_fields(r, offer)
      offer_signature = add_image(r, :seller_signature, offer.signature)

      add_buyer_fields(r, offer)
      interest_signature = add_image(r, :buyer_signature, offer.interest&.signature)

      stamp_paper_download_paths = add_stamp_paper(r, offer)
    end

    report.generate("#{@working_dir}/Offer-#{offer.id}.odt")
    system("libreoffice --headless --convert-to pdf #{@working_dir}/Offer-#{offer.id}.odt --outdir #{@working_dir}")

    File.delete(offer_signature) if offer_signature
    File.delete(interest_signature) if interest_signature
    stamp_paper_download_paths.each do |path|
      File.delete(path)
    end
  end

  def add_image(report, field_name, image)
    if image
      file = image.download
      sleep(1)
      report.add_image field_name.to_sym, file.path
      file.path
    end
  end

  def add_stamp_paper(report, offer)
    stamp_paper_download_path = []
    stamp_papers = offer.documents.where(name: "Stamp Paper")
    stamp_paper_count = stamp_papers.count

    if stamp_paper_count == 1
      # Use the single stamp paper
      Rails.logger.debug { "1 stamp paper found for offer #{offer.id}" }
      stamp_paper = offer.documents.where(name: "Stamp Paper").first
      stamp_paper_download_path << add_image(report, :stamp_paper, stamp_paper.file)
    elsif stamp_paper_count > 1
      # # Merge the stamp papers into one single stamp paper & then use that
      # Rails.logger.debug { "Multiple stamp paper found for offer #{offer.id}" }
      # stamp_papers.each do |sp|
      #   # Download each of the stamp papers
      #   sp_download = sp.file.download
      #   sleep(1)
      #   stamp_paper_download_path << sp_download.path
      # end
      # # Merge the downloaded stamp papers
      # Rails.logger.debug { "Merging images #{stamp_paper_download_path}" }
      # sp_merged_image = ImageList.new(*stamp_paper_download_path).append(true)
      # sp_merged_file_path = "/tmp/sp_merged_image_#{offer.id}.png"
      # sp_merged_image.write(sp_merged_file_path)
      # # sp_merged_image.display
      # sleep(1)
      # # Add the merged image to the report
      # report.add_image :stamp_paper, sp_merged_file_path
      # # stamp_paper_download_path << sp_merged_file_path
    else
      Rails.logger.debug { "No stamp paper for offer #{offer.id}" }
    end

    stamp_paper_download_path
  end

  def add_seller_fields(report, offer)
    report.add_field :seller_name, offer.full_name
    report.add_field :seller_address, offer.address
    report.add_field :seller_pan, offer.PAN
    report.add_field :seller_email, offer.user.email
    report.add_field :seller_bank_account, offer.bank_account_number
    report.add_field :seller_ifsc_code, offer.ifsc_code
    report.add_field :seller_demat, offer.demat
    report.add_field :seller_city, offer.city

    if offer.secondary_sale.fees
      fees = offer.compute_fees(offer.secondary_sale.fees)
      fee_amount = fees.sum(Money.new(0, offer.entity.currency)) { |i| i[:fee] }

      report.add_field :seller_fees, fee_amount
      report.add_field :net_allocation_amount, money_to_currency(offer.allocation_amount - fee_amount)
    end
  end

  def add_buyer_fields(report, offer)
    report.add_field :buyer_name, offer.interest&.buyer_entity_name
    report.add_field :buyer_address, offer.interest&.address
    report.add_field :buyer_email, offer.interest&.email
    report.add_field :buyer_pan, offer.interest&.PAN
    report.add_field :buyer_city, offer.interest&.city
    report.add_field :buyer_demat, offer.interest&.demat
    report.add_field :buyer_contact, offer.interest&.contact_name
  end

  def attach(offer)
    offer.spa = File.open("#{@working_dir}/Offer-#{offer.id}.pdf", "rb")
    offer.save
  end
end
