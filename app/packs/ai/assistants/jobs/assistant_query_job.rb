class AssistantQueryJob < ApplicationJob
  queue_as :default

  # Runs the assistant in the background and replaces the placeholder turbo-frame in the UI.
  #
  # @param user_id [Integer]
  # @param request_id [String] client-generated id used to target a turbo-frame in the DOM
  # @param query [String]
  def perform(user_id, request_id, query)
    user = User.find(user_id)

    response = FundAssistant.new(user: user).run(query)

    Turbo::StreamsChannel.broadcast_replace_to(
      [user, "assistant"],
      target: turbo_frame_dom_id(request_id),
      partial: "assistants/ask_frame",
      locals: { query: query, response: response, request_id: request_id, error: nil }
    )
  rescue StandardError => e
    Rails.logger.error { "AssistantQueryJob failed: #{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}" }

    user = User.find_by(id: user_id)
    return unless user

    Turbo::StreamsChannel.broadcast_replace_to(
      [user, "assistant"],
      target: turbo_frame_dom_id(request_id),
      partial: "assistants/ask_frame",
      locals: { query: query, response: nil, request_id: request_id, error: e.message }
    )
  end

  private

  def turbo_frame_dom_id(request_id)
    "assistant_response_#{request_id}"
  end
end
