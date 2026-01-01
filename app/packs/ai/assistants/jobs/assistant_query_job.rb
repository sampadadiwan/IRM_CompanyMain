class AssistantQueryJob < ApplicationJob
  queue_as :default

  # The maximum time the job is allowed to run before being interrupted.
  TIMEOUT = 90.seconds

  # Runs the assistant in the background and replaces the placeholder turbo-frame in the UI.
  #
  # @param user_id [Integer]
  # @param chat_id [Integer]
  # @param request_id [String] client-generated id used to target a turbo-frame in the DOM
  # @param query [String]
  def perform(user_id, chat_id, request_id, query, assistant_type = 'fund')
    user = User.find(user_id)
    chat = Chat.find(chat_id)

    assistant = case assistant_type.to_s
                when 'portfolio_company'
                  portfolio_company = chat.owner if chat.owner_type == 'Investor'
                  PortfolioCompanyAssistant.new(user: user, portfolio_company: portfolio_company)
                when 'portfolio'
                  PortfolioAssistant.new(user: user)
                when 'capital_commitment'
                  commitment = chat.owner if chat.owner_type == 'CapitalCommitment'
                  CapitalCommitmentAssistant.new(user: user, capital_commitment: commitment)
                when 'specific_fund'
                  fund = chat.owner if chat.owner_type == 'Fund'
                  SpecificFundAssistant.new(user: user, fund: fund)
                else
                  FundAssistant.new(user: user)
                end

    response = Timeout.timeout(TIMEOUT) do
      assistant.run(query)
    end

    Turbo::StreamsChannel.broadcast_replace_to(
      [user, "assistant"],
      target: turbo_frame_dom_id(request_id),
      partial: "assistants/ask_frame",
      locals: { query: query, response: response, request_id: request_id, error: nil }
    )
  rescue Timeout::Error => e
    Rails.logger.error { "AssistantQueryJob timed out after #{TIMEOUT} seconds: #{e.message}" }
    broadcast_error(user_id, request_id, query, "The request timed out. Please try again or refine your query.")
  rescue StandardError => e
    Rails.logger.error { "AssistantQueryJob failed: #{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}" }
    broadcast_error(user_id, request_id, query, e.message)
  end

  private

  def broadcast_error(user_id, request_id, query, error_message)
    user = User.find_by(id: user_id)
    return unless user

    Turbo::StreamsChannel.broadcast_replace_to(
      [user, "assistant"],
      target: turbo_frame_dom_id(request_id),
      partial: "assistants/ask_frame",
      locals: { query: query, response: nil, request_id: request_id, error: error_message }
    )
  end

  def turbo_frame_dom_id(request_id)
    "assistant_response_#{request_id}"
  end
end
