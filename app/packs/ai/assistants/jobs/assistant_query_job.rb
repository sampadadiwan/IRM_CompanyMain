class AssistantQueryJob < ApplicationJob
  queue_as :default

  # The maximum time the job is allowed to run before being interrupted.
  TIMEOUT = 180.seconds

  # Runs the assistant in the background and replaces the pending answer in the chat kit's thread
  # (assistants/ask.turbo_stream put it there), then re-renders the question box.
  #
  # @param user_id [Integer]
  # @param chat_id [Integer]
  # @param request_id [String] client-generated id used to target a turbo-frame in the DOM
  # @param query [String]
  def perform(user_id, chat_id, request_id, query, assistant_type)
    user = User.find(user_id)
    chat = Chat.find_by(id: chat_id)

    assistant = case assistant_type.to_s
                when 'PortfolioCompanyAssistant'
                  portfolio_company = chat.owner if chat.owner_type == 'Investor'
                  PortfolioCompanyAssistant.new(user: user, portfolio_company: portfolio_company, chat: chat)
                when 'PortfolioAssistant'
                  PortfolioAssistant.new(user: user, chat: chat)
                when 'CapitalCommitmentAssistant'
                  commitment = chat.owner if chat.owner_type == 'CapitalCommitment'
                  CapitalCommitmentAssistant.new(user: user, capital_commitment: commitment, chat: chat)
                when 'SpecificFundAssistant'
                  fund = chat.owner if chat.owner_type == 'Fund'
                  SpecificFundAssistant.new(user: user, fund: fund, chat: chat)
                else
                  FundAssistant.new(user: user, chat: chat)
                end

    response = Timeout.timeout(TIMEOUT) do
      assistant.run(query)
    end

    # Which layout sections and widgets the answer used — over-use of a widget shows in the logs.
    AiChatAnswerLayout.log_usage("assistants:#{assistant_type}", response.content)

    # H3 — the answer replaces the pending one in the thread (ai_chat/_answer, rich mode).
    broadcast_answer(chat, request_id, AiChatItem.transient(dom_id: turbo_frame_dom_id(request_id), role: "assistant",
                                                            content: response.content))
    broadcast_composer(chat)
  rescue Timeout::Error => e
    Rails.logger.error { "AssistantQueryJob timed out after #{TIMEOUT} seconds: #{e.message}" }
    # X3 — a timeout reads "Not answered" with the reason; the question goes back in the box.
    broadcast_error(chat, request_id, query, "The request timed out. Please try again or refine your query.")
  rescue StandardError => e
    Rails.logger.error { "AssistantQueryJob failed: #{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}" }
    broadcast_error(chat, request_id, query, e.message)
  end

  private

  # Streams are per chat, so another open assistant tab is never touched.
  #
  # @param chat [Chat]
  # @param request_id [String]
  # @param item [AiChatItem]
  def broadcast_answer(chat, request_id, item)
    Turbo::StreamsChannel.broadcast_replace_to(
      [chat, :assistant],
      target: turbo_frame_dom_id(request_id),
      partial: "ai_chat/answer",
      locals: { item: item, mode: :rich }
    )
  end

  # Re-renders the question box once the turn ends: Ask enabled again, and a failed question back in it.
  #
  # @param chat [Chat]
  # @param value [String, nil]
  def broadcast_composer(chat, value: nil)
    Turbo::StreamsChannel.broadcast_replace_to(
      [chat, :assistant],
      target: "assistant-composer",
      partial: "assistants/composer",
      locals: { chat: chat, running: false, value: value }
    )
  end

  def broadcast_error(chat, request_id, query, error_message)
    return unless chat

    broadcast_answer(chat, request_id, AiChatItem.transient(dom_id: turbo_frame_dom_id(request_id), role: "assistant",
                                                            content: error_message, status: :failed))
    broadcast_composer(chat, value: query)
  end

  def turbo_frame_dom_id(request_id)
    "assistant_response_#{request_id}"
  end
end
