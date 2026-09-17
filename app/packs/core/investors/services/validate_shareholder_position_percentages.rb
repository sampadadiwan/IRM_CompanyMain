# frozen_string_literal: true

# Dry-run check (writes nothing, creates no ImportUpload) of a ShareholderPosition workbook's
# Fully Dilluted % totals and ShareHolder/Portfolio Company/As Of/Instrument/Category
# uniqueness - the same rules ImportShareholderPosition#pre_process enforces as a hard gate at
# real import time (see percentage_total_errors/duplicate_row_errors there). Run from
# ImportUploadsController#validate_upload the moment a file is chosen, so the user can fix and
# re-upload the sheet before ever clicking Save (see xlsx_preview_controller.js).
#
# Resolves the workbook from either:
#   - `file_data` : the Shrine cached-file JSON the upload widget hands the form right after
#                   upload (nothing is persisted yet - the cached object is opened directly), or
#   - `file`      : a raw uploaded file (multipart) - fallback for tests/upload libs without a cache.
#
# Usage:
#   result = ValidateShareholderPositionPercentages.call(file_data: params[:file_data])
#   result[:errors] # => [] when every Portfolio Company/Stakeholder + As Of round totals ~100%
#                   #    and no ShareHolder/Portfolio Company/As Of/Instrument/Category
#                   #    combination repeats. Each entry is prefixed with its kind ("Fully
#                   #    Dilluted % must total 100%: ..." or "Duplicate ShareHolder/Portfolio
#                   #    Company/As Of/Instrument/Category combination: ...") so the two kinds
#                   #    stay distinguishable when rendered one per line.
class ValidateShareholderPositionPercentages < Trailblazer::Operation
  step :resolve_source
  step :compute_errors

  def resolve_source(ctx, file_data: nil, file: nil, **)
    if file_data.present?
      data = file_data.is_a?(String) ? JSON.parse(file_data) : file_data.to_h
      # Only the upload widget's own cache is a legitimate source - never let the client name
      # another storage (e.g. "store" + someone else's key) and have us open that file's cells.
      unless data["storage"].to_s == "cache" && data["id"].present?
        ctx[:errors] = ["The uploaded file reference is not valid."]
        return false
      end
      uploaded = FileUploader.uploaded_file(data.slice("id", "storage", "metadata"))
      ext = File.extname(data.dig("metadata", "filename").to_s)
      tempfile = Tempfile.new(["shareholder_position_validate", ext], binmode: true)
      uploaded.open { |io| IO.copy_stream(io, tempfile) }
      tempfile.flush
      ctx[:file_path] = tempfile.path
      ctx[:tempfile] = tempfile
    elsif file.present?
      ext = File.extname(file.original_filename.to_s)
      tempfile = Tempfile.new(["shareholder_position_validate", ext], binmode: true)
      IO.copy_stream(file.tempfile.tap(&:rewind), tempfile)
      tempfile.flush
      ctx[:file_path] = tempfile.path
      ctx[:tempfile] = tempfile
    else
      ctx[:errors] = ["No file was uploaded."]
      return false
    end
    true
  rescue JSON::ParserError, Shrine::FileNotFound, Shrine::Error => e
    ctx[:errors] = ["Could not read the uploaded file: #{e.message}"]
    false
  end

  def compute_errors(ctx, file_path:, **)
    sheet = Roo::Spreadsheet.open(file_path).sheet(0)
    first_row = sheet.row(1)
    if first_row.compact.empty?
      ctx[:errors] = ["The first sheet is blank or the first row is empty."]
      return true
    end

    importer = ImportShareholderPosition.new
    headers = importer.get_headers(first_row)
    mismatches = importer.percentage_total_errors(headers, sheet).map { |msg| "Fully Dilluted % must total 100%: #{msg}" }
    duplicates = importer.duplicate_row_errors(headers, sheet).map { |msg| "Duplicate ShareHolder/Portfolio Company/As Of/Instrument/Category combination: #{msg}" }
    ctx[:errors] = mismatches + duplicates
    true
  rescue StandardError => e
    ctx[:errors] = ["Could not check the file: #{e.message}"]
    true
  ensure
    ctx[:tempfile]&.close!
  end
end
