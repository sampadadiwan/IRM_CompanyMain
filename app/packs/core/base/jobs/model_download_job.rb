# Generic job for downloading large datasets as XLSX files.
# This job triggers the ModelDownload Trailblazer operation which handles
# fetching records, rendering XLSX, uploading as a Document, and sending notifications/emails.
#
# Usage:
#   ModelDownloadJob.perform_later(
#     model_class: 'AccountEntry',
#     params: params.to_unsafe_h,
#     user_id: current_user.id,
#     template: 'account_entries/index',
#     filename: 'account_entries.xlsx'
#   )
#
class ModelDownloadJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 0

  # @param model_class [String] The name of the model class (e.g., 'AccountEntry')
  # @param params [Hash] The params hash including ransack query params
  # @param user_id [Integer] The ID of the user requesting the download
  # @param template [String] The template path for rendering (e.g., 'account_entries/index')
  # @param filename [String] The filename for the downloaded file (e.g., 'account_entries.xlsx')
  def perform(model_class:, params:, user_id:, template:, filename:, url: nil)
    user = User.find(user_id)

    Chewy.strategy(:sidekiq) do
      send_notification("Your download is being prepared...", user_id)

      # Call the ModelDownload Trailblazer operation
      result = ModelDownload.call(
        model_class: model_class.constantize,
        params: params.with_indifferent_access,
        user: user,
        template: template,
        filename: filename,
        url: url
      )

      unless result.success?
        error_msg = result[:errors] || "Unknown error generating download"
        raise StandardError, error_msg
      end
    end
  rescue StandardError => e
    Rails.logger.error { "ModelDownloadJob error: #{e.message}" }
    Rails.logger.error { e.backtrace.join("\n") }
    send_notification("Error generating download: #{e.message}", user_id, "danger")
    raise e
  end
end
