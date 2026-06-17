module WithTurboFlash
  extend ActiveSupport::Concern

  TURBO_FLASH_METHODS = %w[POST PATCH PUT DELETE].freeze
  private_constant :TURBO_FLASH_METHODS

  included do
    # Only fire on mutating requests — flash is never set by GETs in normal use.
    after_action :append_flash_to_turbo_stream,
                 if: -> { request.format.turbo_stream? && TURBO_FLASH_METHODS.include?(request.method) }
  end

  private

  def append_flash_to_turbo_stream
    # Guard on exactly the keys _alerts.html.erb renders — other keys (e.g. :info)
    # would produce an empty partial and silently clear #page_alerts.
    return unless flash[:notice].present? || flash[:alert].present?

    # Render the shared alerts partial to an HTML string (formats: must be :html
    # because we're inside a turbo_stream request).
    flash_html = render_to_string(
      partial: "layouts/alerts",
      formats: [:html]
    )

    # Append a turbo-stream tag that replaces the #page_alerts inner HTML.
    # "update" (not "replace") keeps the wrapping div stable so Bootstrap dismiss animations work.
    response.body += "<turbo-stream action=\"update\" target=\"page_alerts\"><template>#{flash_html}</template></turbo-stream>"

    # Discard now so the messages don't also appear on the next full-page load.
    flash.discard
  end
end
