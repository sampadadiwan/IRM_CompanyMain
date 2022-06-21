class FileUploader < Shrine
  Attacher.validate do
    validate_mime_type %w[image/jpeg image/png image/webp application/pdf application/docx]
    validate_max_size 10 * 1024 * 1024, message: "is too large (max is 10 MB)"
  end

  def generate_location(io, record: nil, derivative: nil, **)
    return super unless record

    entity = record.entity ? record.entity.name : "Unknown"
    table  = record.class.table_name
    id     = record.id
    prefix = derivative || "original"

    "#{entity}/#{table}/#{id}/#{prefix}-#{super}"
  end
end
