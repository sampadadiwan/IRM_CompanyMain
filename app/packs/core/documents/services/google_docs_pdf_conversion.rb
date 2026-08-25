require "faraday"
require "jwt"
require "openssl"
require "securerandom"

# Converts a merged .docx to PDF via the Google Drive API instead of LibreOffice, for
# templates that opted in via Document#pdf_conversion_engine == "google_docs". Uploads the
# file to a dedicated scratch folder (a Shared Drive, so a bare service account has
# somewhere to write -- personal Drive storage isn't available to service accounts),
# converts it to a Google Doc on upload, exports that as PDF, and deletes the temp file
# whether the conversion succeeded or not. Mirrors M365PdfConversion's shape; see
# docs/technical/google_docs_pdf_conversion.md for the full design and setup steps.
#
# Deliberately raises rather than falling back to LibreOffice on any failure -- silently
# falling back would reintroduce the exact footnote-placement defect this path exists to
# avoid, on a template chosen specifically because that defect matters for it.
#
# A single step wraps the whole upload/convert/export/cleanup sequence, same reasoning as
# M365PdfConversion: no branching to express, and a plain `ensure` guarantees the temp file
# cleanup runs on every exit path.
class GoogleDocsPdfConversion < Trailblazer::Operation
  DRIVE_UPLOAD_BASE = "https://www.googleapis.com/upload/drive/v3".freeze
  DRIVE_BASE = "https://www.googleapis.com/drive/v3".freeze
  TOKEN_URL = "https://oauth2.googleapis.com/token".freeze
  TOKEN_CACHE_KEY = "google_docs_access_token".freeze
  DOCX_MIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document".freeze
  GOOGLE_DOC_MIME = "application/vnd.google-apps.document".freeze
  # See the matching constant/comment in M365PdfConversion -- same reasoning: generous but
  # bounded rather than unbounded, untested against a large real document.
  REQUEST_TIMEOUT = 120
  TOKEN_TIMEOUT = 15

  step :convert

  def convert(ctx, docx_path:, pdf_path:, **)
    access_token = fetch_access_token
    file_id = upload_and_convert(docx_path, access_token)
    begin
      pdf_bytes = export_pdf(file_id, access_token)
      File.binwrite(pdf_path, pdf_bytes)
    ensure
      cleanup_temp_file(file_id, access_token)
    end
    true
  rescue StandardError => e
    ctx[:errors] = "Google Docs PDF conversion failed: #{e.message}"
    ctx[:exception] = e # kept alongside the string so the caller can re-raise with the
    # original class and backtrace intact -- the only diagnostic signal on a path with no
    # LibreOffice fallback.
    Rails.logger.error { "[GoogleDocsPdfConversion] #{ctx[:errors]}" }
    false
  end

  private

  # Service-account JWT Bearer flow (RFC 7523) -- no user consent screen, no refresh token
  # to manage, just a self-signed assertion exchanged directly for an access token.
  def fetch_access_token
    Rails.cache.fetch(TOKEN_CACHE_KEY, expires_in: 55.minutes) do
      now = Time.now.to_i
      claims = {
        iss: credential!("GOOGLE_DOCS_CLIENT_EMAIL"),
        scope: "https://www.googleapis.com/auth/drive",
        aud: TOKEN_URL,
        iat: now,
        exp: now + 3600
      }
      private_key = OpenSSL::PKey::RSA.new(credential!("GOOGLE_DOCS_PRIVATE_KEY"))
      assertion = JWT.encode(claims, private_key, "RS256")

      response = token_connection.post(TOKEN_URL) do |req|
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = URI.encode_www_form(
          grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
          assertion: assertion
        )
      end
      raise "token request failed (#{response.status}): #{response.body}" unless response.success?

      response.body["access_token"]
    end
  end

  # uploadType=multipart with mimeType application/vnd.google-apps.document as the target
  # is what makes Drive convert the uploaded docx into an editable Google Doc on the way
  # in, rather than storing the raw docx bytes -- that conversion step is what lets the
  # later export produce a real (non-LibreOffice) PDF rendering.
  def upload_and_convert(docx_path, access_token)
    boundary = "docgen-#{SecureRandom.hex(8)}"
    metadata = {
      name: "docgen-#{SecureRandom.uuid}",
      mimeType: GOOGLE_DOC_MIME,
      parents: [credential!("GOOGLE_DOCS_FOLDER_ID")]
    }.to_json
    body = build_multipart_body(boundary, metadata, File.binread(docx_path))

    response = graph_connection(access_token).post(
      "#{DRIVE_UPLOAD_BASE}/files?uploadType=multipart&supportsAllDrives=true"
    ) do |req|
      req.headers["Content-Type"] = "multipart/related; boundary=#{boundary}"
      req.body = body
    end
    raise "upload/convert failed (#{response.status}): #{response.body}" unless response.success?

    response.body["id"]
  end

  # Drive's multipart/related upload isn't the standard multipart/form-data Faraday builds
  # helpers for (it's a JSON metadata part plus a raw media part), so it's built by hand.
  def build_multipart_body(boundary, metadata_json, docx_bytes)
    header = "--#{boundary}\r\n"
    header << "Content-Type: application/json; charset=UTF-8\r\n\r\n"
    header << "#{metadata_json}\r\n"
    header << "--#{boundary}\r\n"
    header << "Content-Type: #{DOCX_MIME}\r\n\r\n"

    footer = "\r\n--#{boundary}--"

    header.b + docx_bytes.b + footer.b
  end

  def export_pdf(file_id, access_token)
    response = graph_connection(access_token, parse_json: false).get(
      "#{DRIVE_BASE}/files/#{file_id}/export?mimeType=application/pdf"
    )
    raise "export failed (#{response.status})" unless response.success?

    response.body
  end

  # Best-effort: a cleanup failure is logged but never masks the real result of the
  # conversion attempt above it.
  def cleanup_temp_file(file_id, access_token)
    return if file_id.blank?

    graph_connection(access_token).delete("#{DRIVE_BASE}/files/#{file_id}?supportsAllDrives=true")
  rescue StandardError => e
    Rails.logger.error { "[GoogleDocsPdfConversion] failed to clean up temp file #{file_id}: #{e.message}" }
  end

  def credential!(key)
    Rails.application.credentials[key].presence || raise("Missing Rails credential #{key} -- see docs/technical/google_docs_pdf_conversion.md")
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
