class ImportAllocation < ImportUtil
  STANDARD_HEADERS = ["Offer Id",	"Interest Id",	"Allocation Quantity", "Allocation Price", "Verified"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def initialize(**)
    super
    @allocations = []
  end

  def save_row(user_data, import_upload, _custom_field_headers, _ctx)
    Rails.logger.debug { "Processing allocation #{user_data}" }
    offer = Offer.find(user_data["Offer Id"])
    secondary_sale = offer.secondary_sale
    interest = secondary_sale.interests.find(user_data["Interest Id"])
    quantity = user_data["Allocation Quantity"].to_d
    price = user_data["Allocation Price"].to_d
    verified = user_data["Verified"].downcase == "yes"

    allocation = Allocation.build_from(offer, interest, quantity, price)
    allocation.verified = verified
    allocation.import_upload_id = import_upload.id
    allocation.save!
  end
end
