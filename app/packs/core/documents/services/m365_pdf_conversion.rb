require "faraday"
require "securerandom"

# Converts a merged .docx to PDF via Microsoft Graph API instead of LibreOffice, for
# templates that opted in via Document#pdf_conversion_engine == "m365". Uploads the file
# to a dedicated SharePoint site's drive, asks Graph to hand it back converted to PDF, and
# deletes the temp file whether the conversion succeeded or not.
#
# Deliberately raises rather than falling back to LibreOffice on any failure -- silently
# falling back would reintroduce the exact footnote-placement defect this path exists to
# avoid, on a template chosen specifically because that defect matters for it. See
# docs/modules/documents/m365_graph_pdf_conversion.md for the full design and setup steps.
#
# A single step wraps the whole upload/convert/download/cleanup sequence rather than
# splitting each call into its own Trailblazer step: there's no branching to express here
# (every call either succeeds or the whole thing fails), and it lets a plain `ensure`
# guarantee the temp file cleanup runs on every exit path -- simpler and easier to verify
# than wiring a separate step onto Trailblazer's failure track for the same purpose.
class M365PdfConversion < Trailblazer::Operation
  GRAPH_BASE = "https://graph.microsoft.com/v1.0".freeze
  TOKEN_CACHE_KEY = "m365_graph_token".freeze
  # Conversion of a large (~140 page) docx is untested against real Graph API latency (see
  # "Open questions" in docs/modules/documents/m365_graph_pdf_conversion.md) -- generous but bounded
  # rather than unbounded, so a stalled request fails the job instead of hanging a worker
  # indefinitely. Revisit once real timing data exists.
  REQUEST_TIMEOUT = 120
  TOKEN_TIMEOUT = 15

  step :convert

  def convert(ctx, docx_path:, pdf_path:, **)
    access_token = fetch_access_token
    item_id = upload_docx(docx_path, access_token)
    begin
      pdf_bytes = request_pdf(item_id, access_token)
      File.binwrite(pdf_path, pdf_bytes)
    ensure
      cleanup_temp_file(item_id, access_token)
    end
    true
  rescue StandardError => e
    ctx[:errors] = "M365 PDF conversion failed: #{e.message}"
    ctx[:exception] = e # kept alongside the string so the caller can re-raise with the
    # original class and backtrace intact instead of an opaque RuntimeError -- this is
    # the only diagnostic signal for a failure on a path with no LibreOffice fallback.
    Rails.logger.error { "[M365PdfConversion] #{ctx[:errors]}" }
    false
  end

  private

  def fetch_access_token
    Rails.cache.fetch(TOKEN_CACHE_KEY, expires_in: 55.minutes) do
      tenant_id = credential!("M365_TENANT_ID")
      response = token_connection.post("https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token") do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(
          client_id: credential!("M365_CLIENT_ID"),
          client_secret: credential!("M365_CLIENT_SECRET"),
          scope: "https://graph.microsoft.com/.default",
          grant_type: "client_credentials"
        )
      end
      raise "token request failed (#{response.status}): #{response.body}" unless response.success?

      response.body["access_token"]
    end
  end

  def upload_docx(docx_path, access_token)
    temp_name = "docgen-#{SecureRandom.uuid}.docx"
    response = graph_connection(access_token).put(
      "#{GRAPH_BASE}/drives/#{credential!('M365_DRIVE_ID')}/root:/tmp/#{temp_name}:/content"
    ) do |req|
      req.headers["Content-Type"] = "application/octet-stream"
      req.body = File.binread(docx_path)
    end
    raise "upload failed (#{response.status}): #{response.body}" unless response.success?

    response.body["id"]
  end

  def request_pdf(item_id, access_token)
    response = graph_connection(access_token, parse_json: false).get(
      "#{GRAPH_BASE}/drives/#{credential!('M365_DRIVE_ID')}/items/#{item_id}/content?format=pdf"
    )

    # Graph's ?format=pdf export responds with a redirect to a pre-signed download URL
    # rather than the PDF bytes directly. Faraday doesn't follow redirects by default, and
    # the redirect target must be fetched unauthenticated -- it rejects the Graph bearer
    # token on the Authorization header.
    response = Faraday.new { |f| f.options.timeout = REQUEST_TIMEOUT }.get(response.headers["location"]) if
      response.status.between?(300, 399) && response.headers["location"].present?

    raise "conversion failed (#{response.status})" unless response.success?

    response.body
  end

  # Best-effort: a cleanup failure is logged but never masks the real result of the
  # conversion attempt above it.
  def cleanup_temp_file(item_id, access_token)
    return if item_id.blank?

    graph_connection(access_token).delete("#{GRAPH_BASE}/drives/#{credential!('M365_DRIVE_ID')}/items/#{item_id}")
  rescue StandardError => e
    Rails.logger.error { "[M365PdfConversion] failed to clean up temp file #{item_id}: #{e.message}" }
  end

  def credential!(key)
    Rails.application.credentials[key].presence || raise("Missing Rails credential #{key} -- see docs/modules/documents/m365_graph_pdf_conversion.md")
  end

  def token_connection
    Faraday.new do |f|
      f.options.timeout = TOKEN_TIMEOUT
      f.options.open_timeout = TOKEN_TIMEOUT
      f.response :json, content_type: /\bjson$/
    end
  end

  def graph_connection(access_token, parse_json: true)
    Faraday.new do |f|
      f.options.timeout = REQUEST_TIMEOUT
      f.options.open_timeout = TOKEN_TIMEOUT
      f.headers["Authorization"] = "Bearer #{access_token}"
      f.response :json, content_type: /\bjson$/ if parse_json
    end
  end
end
