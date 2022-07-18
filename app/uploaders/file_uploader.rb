class FileUploader < Shrine
  ALLOWED_TYPES = %w[image/* application/* video/*].freeze
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

    trailing = "#{table.titleize}/#{id}/#{prefix}-#{super}"
    owner_path = record.respond_to?(:owner) && record.owner ? "#{record.owner_type.pluralize.titleize}/#{record.owner_id}/#{trailing}" : nil

    get_path(entity, record, owner_path, trailing)
  end

  private

  def get_path(entity, record, owner_path, trailing)
    if owner_path
      if %w[SecondarySale Deal OptionPool Holding Approval].include? record.owner_type
        "#{entity}/#{owner_path}"
      elsif %w[Offer Interest].include? record.owner_type
        # Put it inside the SecondarySale folder
        "#{entity}/SecondarySale/#{record.owner.secondary_sale_id}/#{owner_path}"
      elsif ["DealInvestor"].include? record.owner_type
        # Put it inside the Deal folder
        "#{entity}/Deal/#{record.owner.deal_id}/#{owner_path}"
      elsif ["Excercise"].include? record.owner_type
        # Put it inside the Deal folder
        "#{entity}/OptionPool/#{record.owner.option_pool_id}/#{owner_path}"
      end
    else
      "#{entity}/#{trailing}"
    end
  end
end
