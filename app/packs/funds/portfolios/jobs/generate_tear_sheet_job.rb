# frozen_string_literal: true

class GenerateTearSheetJob < ApplicationJob
  queue_as :default

  def perform(user_id, extract_id, force_generate: false, palette: "serene_blue")
    user = User.find(user_id)
    PortfolioReportExtract.find(extract_id)

    html = TearSheetGeneratorService.new(extract_id: extract_id).call(force_generate: force_generate, palette: palette)

    Turbo::StreamsChannel.broadcast_update_to(
      [user, "tear_sheet_slides", extract_id.to_s],
      target: "slides_container",
      html: html
    )

    # Also broadcast the palette change to the body class
    # We can do this by broadcasting a stream that updates the body class
    Turbo::StreamsChannel.broadcast_replace_to(
      [user, "tear_sheet_slides", extract_id.to_s],
      target: "body_class_trigger",
      html: "<div id=\"body_class_trigger\" data-palette=\"#{palette}\"></div>"
    )
  rescue StandardError => e
    Rails.logger.error { "GenerateTearSheetJob failed: #{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}" }

    user = User.find_by(id: user_id)
    return unless user

    Turbo::StreamsChannel.broadcast_update_to(
      [user, "tear_sheet_slides", extract_id.to_s],
      target: "slides_container",
      html: <<~HTML
        <section>
          <div class="p-10">
            <h2 class="text-2xl font-semibold text-slate-900">Failed to generate tear sheet</h2>
            <p class="mt-2 text-slate-700">#{ERB::Util.html_escape(e.message)}</p>
          </div>
        </section>
      HTML
    )
  end
end
