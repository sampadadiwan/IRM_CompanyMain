class FileUploader < Shrine
  ALLOWED_TYPES = %w[*/*].freeze
  MIME_TYPES = [
    "text/html", "image/jpeg", "image/png", "image/gif", "image/bmp", "application/pdf", "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/vnd.ms-excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "application/vnd.ms-powerpoint", "application/vnd.openxmlformats-officedocument.presentationml.presentation", "text/plain", "text/html", "text/css", "text/csv", "application/xml", "application/json", "audio/mpeg", "audio/wav", "video/mp4", "video/mpeg", "application/zip", "application/x-rar-compressed", "application/x-tar", "application/x-gzip", "application/x-7z-compressed", "application/x-bzip2", "application/x-iso9660-image", "application/x-ole-storage"
  ].freeze
  Attacher.validate do
    # validate_mime_type ALLOWED_TYPES
    validate_mime_type MIME_TYPES, message: "upload with this extension '#{file.mime_type}' is not allowed"
    validate_max_size 2048 * 1024 * 1024, message: "is too large (max is 2GB)"
  end

  def generate_location(io, record: nil, derivative: nil, **)
    return super unless record

    entity = record.instance_of?(Entity) ? record.name : record.entity&.name
    return super unless entity

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
