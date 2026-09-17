# frozen_string_literal: true

# Dry-run validation of a KPI workbook for a KpiReport — the single source of truth the portco
# sees BEFORE saving and the controller uses as the submit gate
# (docs/technical/kpi_portco_upload_validation_review.md §3.1 A/C).
#
# Resolves the workbook from either:
#   - `file_data`  : the Shrine cached-file JSON Uppy hands the form after upload (nothing is
#                    persisted yet — we open the cached object directly), or
#   - `file`       : a raw uploaded file (multipart) — used by tests and as a fallback, or
#   - the report's existing "KPIs" Document.
#
# Runs KpiWorkbookReader#validate (writes nothing) and stores the verdict on the report
# (validation_result / validated_at) for display; the gate always recomputes.
#
# Usage:
#   result = KpiUploadValidate.call(kpi_report:, user:, file_data: params[:file_data])
#   result.success? → result[:verdict] (Hash: ok/errors/warnings/summary/cells)
class KpiUploadValidate < Trailblazer::Operation
  step :resolve_source
  left :handle_no_file, Output(:failure) => End(:failure)
  step :run_reader
  step :persist_verdict

  # Works out where the workbook bytes come from and yields a local path + filename.
  # Sets ctx[:file_path], ctx[:file_name], ctx[:document] and a cleanup proc.
  def resolve_source(ctx, kpi_report:, file_data: nil, file: nil, **)
    if file_data.present?
      data = file_data.is_a?(String) ? JSON.parse(file_data) : file_data.to_h
      # Only the Uppy cache is a legitimate source here — never let the client name another storage
      # (e.g. "store" + someone else's key) and have us open and echo that file's cells back.
      unless data["storage"].to_s == "cache" && data["id"].present?
        ctx[:errors] = "The uploaded file reference is not valid."
        return false
      end
      # Shrine::UploadedFile for the cached object (storage "cache", id = object key)
      uploaded = FileUploader.uploaded_file(data.slice("id", "storage", "metadata"))
      ext = File.extname(data.dig("metadata", "filename").to_s)
      tempfile = Tempfile.new(["kpi_validate", ext], binmode: true)
      uploaded.open { |io| IO.copy_stream(io, tempfile) }
      tempfile.flush
      ctx[:file_path] = tempfile.path
      ctx[:file_name] = data.dig("metadata", "filename").presence || "KPIs#{ext}"
      ctx[:tempfile] = tempfile
      ctx[:source] = 'cached'
    elsif file.present?
      # ActionDispatch::Http::UploadedFile (multipart) — write to a temp path Roo can open by extension
      ext = File.extname(file.original_filename.to_s)
      tempfile = Tempfile.new(["kpi_validate", ext], binmode: true)
      IO.copy_stream(file.tempfile.tap(&:rewind), tempfile)
      tempfile.flush
      ctx[:file_path] = tempfile.path
      ctx[:file_name] = file.original_filename
      ctx[:tempfile] = tempfile
      ctx[:source] = 'upload'
    else
      ctx[:document] = kpi_report.documents.where(name: "KPIs").first
      ctx[:file_path] = nil
      # The uploaded filename (Shrine metadata), not the document label "KPIs" — shown in the panel and
      # used by the reader for Roo's extension fallback
      ctx[:file_name] = ctx[:document]&.file&.original_filename.presence || ctx[:document]&.name
      ctx[:source] = 'document'
      # No document either → the reader reports :no_file; still a "success" of this op so the
      # caller gets a verdict to display rather than an exception.
    end
    true
  rescue JSON::ParserError, Shrine::FileNotFound, Shrine::Error => e
    ctx[:errors] = "Could not read the uploaded file: #{e.message}"
    false
  end

  def handle_no_file(ctx, **)
    ctx[:verdict] = {
      'ok' => false,
      'errors' => [{ 'severity' => 'error', 'code' => 'no_file', 'message' => ctx[:errors] || 'No KPI workbook has been uploaded yet.' }],
      'warnings' => [], 'summary' => {}, 'cells' => [], 'generated_at' => Time.current.iso8601
    }
    false
  end

  # Runs the reader in dry-run mode against the portco's non-computed mappings.
  def run_reader(ctx, kpi_report:, user:, **)
    portfolio_company = kpi_report.portfolio_company
    if portfolio_company.blank?
      ctx[:verdict] = {
        'ok' => false,
        'errors' => [{ 'severity' => 'error', 'code' => 'no_portfolio_company', 'message' => 'This KPI report is not linked to a portfolio company.' }],
        'warnings' => [], 'summary' => {}, 'cells' => [], 'generated_at' => Time.current.iso8601
      }
      return true
    end

    kpi_mappings = portfolio_company.investor_kpi_mappings.not_compute
    reader = KpiWorkbookReader.new(kpi_report, ctx[:document], kpi_mappings, user, portfolio_company,
                                   dry_run: true, file_path: ctx[:file_path], file_name: ctx[:file_name])
    ctx[:verdict] = reader.validate
    # Where the bytes came from — the edit page only trusts a stored verdict that describes the
    # document actually attached to the report (a checked-but-never-saved upload must not drive the UI).
    ctx[:verdict]['source'] = ctx[:source]
    ctx[:verdict]['document_id'] = ctx[:document]&.id
    ctx[:reader] = reader
    true
  ensure
    ctx[:tempfile]&.close!
  end

  # Store the verdict for display (panel on reload, fund dashboard). update_columns: no callbacks,
  # no after_commit import trigger, no updated_at churn.
  def persist_verdict(_ctx, kpi_report:, verdict:, **)
    return true unless kpi_report.persisted?

    kpi_report.update_columns(validation_result: verdict, validated_at: Time.current)
    true
  end
end
