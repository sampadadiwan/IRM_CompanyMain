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

    offer_id = cell(user_data, "Offer Id", required: true)
    interest_id = cell(user_data, "Interest Id", required: true)

    # Scoped to the entity and looked up with where/first rather than find, so a
    # wrong id reports the column instead of a raw "Couldn't find Offer with 'id'=..",
    # and an id belonging to another entity is not reachable at all
    offer = Offer.where(id: offer_id, entity_id: import_upload.entity_id).first
    raise "Offer not found: #{offer_id}" unless offer

    secondary_sale = offer.secondary_sale
    raise "Offer #{offer_id} is not linked to a secondary sale" unless secondary_sale

    interest = secondary_sale.interests.where(id: interest_id).first
    raise "Interest not found in secondary sale #{secondary_sale.name}: #{interest_id}" unless interest

    quantity = user_data["Allocation Quantity"].to_d
    price = user_data["Allocation Price"].to_d
    # flag? so a blank Verified cell is "no" rather than a NoMethodError on nil
    verified = flag?(user_data["Verified"])

    allocation = Allocation.build_from(offer, interest, quantity, price)
    allocation.verified = verified
    allocation.import_upload_id = import_upload.id
    allocation.save!
  end
end
