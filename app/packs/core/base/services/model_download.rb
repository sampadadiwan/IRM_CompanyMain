# Trailblazer operation for downloading model data as XLSX files.
# This operation handles fetching records, rendering XLSX, uploading as a Document,
# and sending notifications/emails.
#
# Usage:
#   result = ModelDownload.call(
#     model_class: AccountEntry,
#     params: params,
#     user: current_user,
#     template: 'account_entries/index',
#     filename: 'account_entries.xlsx'
#   )
#
class ModelDownload < Trailblazer::Operation
  step :fetch_records
  step :render_xlsx
  step :write_to_tempfile
  step :upload_as_document
  step :cleanup
  step :send_notification
  step :send_email
  left :handle_errors

  def fetch_records(ctx, model_class:, params:, user:, **)
    ctx[:model_name] = model_class.name.underscore.humanize.pluralize
    list_class = "#{model_class.name}List".safe_constantize
    raise "No List service found for #{model_class.name}" unless list_class

    result = list_class.call(user, params) do |relation|
      policy_class = "#{model_class.name}Policy::Scope".constantize
      policy_class.new(user, relation).resolve
    end

    records_attr = model_class.name.underscore.pluralize.to_sym
    ctx[:records] = result.send(records_attr)

    # Carry over pivot data when the list service built one (e.g. pivot=true export)
    ctx[:pivot] = result.pivot if result.respond_to?(:pivot) && result.pivot.present?

    # Carry over row limit flag so notifications/emails can warn the user (pivot path)
    ctx[:row_limit_exceeded] = true if result.respond_to?(:row_limit_exceeded) && result.row_limit_exceeded

    # For non-pivot exports, enforce the same 50,000-row cap on the records relation
    if ctx[:pivot].blank? && ctx[:records].respond_to?(:count)
      max_rows = 50_000
      total = ctx[:records].count
      if total > max_rows
        Rails.logger.warn("[ModelDownload] Truncating non-pivot export to #{max_rows} rows (total: #{total})")
        ctx[:records] = ctx[:records].limit(max_rows)
        ctx[:row_limit_exceeded] = true
      end
    end

    true
  rescue StandardError => e
    ctx[:errors] = e.message
    false
  end

  def render_xlsx(ctx, records:, model_class:, params:, user:, template:, **)
    controller = ApplicationController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.response = ActionDispatch::TestResponse.new

    # Set instance variables that the template expects
    instance_var_name = "@#{model_class.name.underscore.pluralize}"
    controller.instance_variable_set(instance_var_name.to_sym, records)

    # Set @pivot when a pivot table was built (e.g. pivot=true export)
    controller.instance_variable_set(:@pivot, ctx[:pivot]) if ctx[:pivot].present?

    # Set params for the template (some templates use params)
    controller.instance_variable_set(:@params, params)
    controller.params = ActionController::Parameters.new(params)

    # Set current_user for helpers that need it
    controller.instance_variable_set(:@current_user, user)

    # axlsx produces binary (ASCII-8BIT) content; force encoding to avoid
    # "incompatible character encodings: BINARY and UTF-8" errors.
    raw = controller.render_to_string(template: template, formats: [:xlsx])
    ctx[:xlsx_content] = raw.dup.force_encoding("ASCII-8BIT")
    true
  rescue StandardError => e
    Rails.logger.error { "Error rendering XLSX: #{e.message}\n#{e.backtrace.first(5).join("\n")}" }
    ctx[:errors] = "Error rendering XLSX: #{e.message}"
    false
  end

  def write_to_tempfile(ctx, xlsx_content:, filename:, **)
    file = Tempfile.new([filename.sub('.xlsx', ''), '.xlsx'])
    file.binmode
    file.write(xlsx_content)
    file.rewind
    ctx[:tempfile] = file
    true
  rescue StandardError => e
    ctx[:errors] = "Error writing temp file: #{e.message}"
    false
  end

  def upload_as_document(ctx, tempfile:, user:, url:, filename:, **)
    # Create a tmp folder if it doesn't exist in the root folder
    entity_root_folder = user.entity.root_folder
    tmp_folder = entity_root_folder.children.where(entity_id: user.entity_id, name: "tmp").first_or_create

    # Create a unique name for the document
    name = "#{filename.sub('.xlsx', '')}-#{Time.zone.now.strftime('%Y%m%d%H%M%S')}"

    # Create the document
    doc = Document.new(
      name: name,
      folder: tmp_folder,
      entity: user.entity,
      orignal: true,
      user: user,
      owner_tag: "Generated",
      json_fields: { url: url }
    )

    File.open(tempfile.path, "rb") do |f|
      doc.file = f
      doc.save!
    end

    ctx[:document] = doc
    ctx[:download_url] = doc.file.url(expires_in: 60 * 60 * 24) # 24 hour expiry
    true
  rescue StandardError => e
    ctx[:errors] = "Error uploading document: #{e.message}"
    false
  end

  def send_notification(_ctx, model_name:, download_url:, user:, row_limit_exceeded: false, **)
    download_link = "<a href='#{download_url}' class='mb-1 badge bg-primary-subtle text-primary' target='_blank'>Download #{model_name}</a>"
    msg = "Your download is ready! #{download_link}<br/><small>Link expires in 1 day. A copy has also been sent to your email.</small>"
    msg += "<br/><span class='badge bg-warning-subtle text-warning'>⚠️ Export truncated to 50,000 rows. Please narrow your filters to export all data.</span>" if row_limit_exceeded
    UserAlert.new(user_id: user.id, message: msg, level: "success").broadcast
    true
  end

  def send_email(_ctx, model_name:, document:, user:, filename:, row_limit_exceeded: false, **)
    subject = row_limit_exceeded ? "Your #{model_name} download is ready (truncated to 50,000 rows)" : "Your #{model_name} download is ready"
    UserNotifier.with(record: user, entity_id: user.entity_id, user_id: user.id, document: document, filename: filename, model_name: model_name, subject: subject, email_method: "model_download", row_limit_exceeded: row_limit_exceeded).deliver_later(user)

    true
  rescue StandardError => e
    Rails.logger.error { "Error sending email: #{e.message}" }
    # Don't fail the operation if email fails
    true
  end

  def cleanup(_ctx, tempfile:, **)
    tempfile.close
    tempfile.unlink
    true
  rescue StandardError => e
    Rails.logger.warn { "Error cleaning up temp file: #{e.message}" }
    true
  end

  def handle_errors(ctx, **)
    Rails.logger.error { "ModelDownload failed: #{ctx[:errors]}" }
    # Cleanup tempfile if it was created before the failure
    if ctx[:tempfile]
      begin
        ctx[:tempfile].close
        ctx[:tempfile].unlink
      rescue StandardError
        # Ignore cleanup errors
      end
    end
    false
  end
end
