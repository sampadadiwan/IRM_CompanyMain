# frozen_string_literal: true

class GenerateSlidesJob < ApplicationJob
  queue_as :default

  # Generates slides in the background and updates the presentation UI via Turbo Streams.
  #
  # The presentation page subscribes to the stream:
  #   [user, "assistant_slides", chat_id]
  # and expects a target with id `slides_container`.
  def perform(user_id, chat_id, force_generate: false)
    user = User.find(user_id)

    html = SlideGeneratorService.new(chat_id: chat_id).call(force_generate: force_generate)

    # Replace the Reveal `.slides` container so Reveal.js can re-sync cleanly.
    Turbo::StreamsChannel.broadcast_update_to(
      [user, "assistant_slides", chat_id.to_s],
      target: "slides_container",
      html: html
    )
  rescue StandardError => e
    Rails.logger.error { "GenerateSlidesJob failed: #{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}" }

    user = User.find_by(id: user_id)
    return unless user

    Turbo::StreamsChannel.broadcast_update_to(
      [user, "assistant_slides", chat_id.to_s],
      target: "slides_container",
      html: <<~HTML
        <section>
          <div class="p-10">
            <h2 class="text-2xl font-semibold text-slate-900">Failed to generate slides</h2>
            <p class="mt-2 text-slate-700">#{ERB::Util.html_escape(e.message)}</p>
          </div>
        </section>
      HTML
    )
  end
end
