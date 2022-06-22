class FileUploader < Shrine
  ALLOWED_TYPES = %w[image/jpeg image/png image/webp application/* video/mp4].freeze
  Attacher.validate do
    # validate_mime_type ALLOWED_TYPES
    validate_max_size 500 * 1024 * 1024, message: "is too large (max is 500 MB)"
  end

  def generate_location(io, record: nil, derivative: nil, **)
    return super unless record

    entity = record.entity ? record.entity.name : "Unknown"
    table  = record.class.table_name
    id     = record.id
    prefix = derivative || "original"

    if %w[SecondarySale Deal].include? record.owner_type
      "#{entity}/#{record.owner_type}/#{record.owner_id}/#{table}/#{id}/#{prefix}-#{super}"
    elsif %w[Offer Interest].include? record.owner_type
      # Put it inside the SecondarySale folder
      "#{entity}/SecondarySale/#{record.owner.secodary_sale_id}/#{record.owner_type}/#{record.owner_id}/#{table}/#{id}/#{prefix}-#{super}"
    elsif ["DealInvestor"].include? record.owner_type
      # Put it inside the Deal folder
      "#{entity}/Deal/#{record.owner.deal_id}/#{record.owner_type}/#{record.owner_id}/#{table}/#{id}/#{prefix}-#{super}"
    else
      "#{entity}/#{table}/#{id}/#{prefix}-#{super}"
    end
  end
end
