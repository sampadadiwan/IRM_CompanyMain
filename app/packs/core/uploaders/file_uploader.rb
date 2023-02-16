class FileUploader < Shrine
  ALLOWED_TYPES = %w[*/*].freeze
  Attacher.validate do
    # validate_mime_type ALLOWED_TYPES
    validate_max_size 500 * 1024 * 1024, message: "is too large (max is 500 MB)"
  end

  def generate_location(io, record: nil, derivative: nil, **)
    return super unless record

    entity = record.instance_of?(Entity) ? record.name : record.entity.name
    table  = record.class.table_name
    id     = record.id
    prefix = derivative || "original"

    trailing = "#{table.titleize}/#{id}/#{prefix}-#{super}"

    get_path(entity, record, trailing)
  end

  private

  def get_path(entity, record, trailing)
    if record.respond_to?(:owner) && record.owner.respond_to?(:folder_path)
      "#{entity}#{record.owner.folder_path}/#{trailing}"
    else
      "#{entity}/#{trailing}"
    end
  end
end
