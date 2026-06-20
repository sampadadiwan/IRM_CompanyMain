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

    # ── Critical: never steal flash from a redirect ──────────────────────────
    # When the action did a redirect_to (e.g. after a successful create/update),
    # the flash is meant for the *next* page, which will render it through the
    # standard _alerts.html.erb partial in the layout.  If we append a turbo-
    # stream element and call flash.discard here, the redirected page will find
    # an empty flash and the notice silently disappears.
    #
    # Turbo form submissions (form_with) can arrive with request.format set to
    # :turbo_stream even when the action does a redirect_to.  In that case the
    # response *is* a redirect (302 + Location header), not a turbo-stream
    # render — there is no turbo-stream response body to append to.
    #
    # Detect this by checking for a Location header (set by redirect_to).
    return if response.location.present?

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
    # This is safe because we've already confirmed the response is NOT a redirect
    # (see guard above), so the flash was consumed in THIS turbo-stream render.
    flash.discard
  end
end
