class SupportBotService
  # USAGE:
  # thread = current_user.faq_threads.find(params[:id])
  # response = Ai::SupportBotService.new(faq_thread: thread).ask("How do I reset my password?")
  STATUSES = %w[queued in_progress completed failed].freeze
  IN_PROGRESS_STATUSES = %w[queued in_progress].freeze
  def initialize(faq_thread:)
    @client = OpenAI::Client.new
    @faq_thread = faq_thread
    @assistant_id = ENV.fetch("FAQ_ASSISTANT_ID")
  end

  def ask(user_message)
    ensure_openai_thread_exists!

    # 1. Add User Message to Thread
    @client.messages.create(
      thread_id: @faq_thread.openai_thread_id,
      parameters: { role: "user", content: user_message }
    )

    # 2. Create Run
    run = @client.runs.create(
      thread_id: @faq_thread.openai_thread_id,
      parameters: {
        assistant_id: @assistant_id
      }
    )

    # 3. Poll for completion
    while IN_PROGRESS_STATUSES.include?(run["status"])
      sleep 1
      run = @client.runs.retrieve(
        thread_id: @faq_thread.openai_thread_id,
        id: run["id"]
      )
    end

    # 4. Handle Result
    if run["status"] == "completed"
      response = retrieve_latest_assistant_message

      # Save assistant message to history
      @faq_thread.messages << { role: "assistant", content: response }
      @faq_thread.save!

      broadcast_response(response)
      response
    else
      Rails.logger.error("OpenAI Run Failed: #{run.inspect}")
      error_message = "I'm sorry, I encountered an error processing your request."

      # Save error message as assistant message
      @faq_thread.messages << { role: "assistant", content: error_message }
      @faq_thread.save!

      broadcast_response(error_message)
      error_message
    end
  end

  private

  def broadcast_response(response)
    Turbo::StreamsChannel.broadcast_append_to(
      @faq_thread,
      target: "faq_thread_messages",
      partial: "faq_threads/message",
      locals: { role: "assistant", content: response }
    )
  end

  def ensure_openai_thread_exists!
    # If the local DB record exists but hasn't been synced to OpenAI yet
    return if @faq_thread.openai_thread_id.present?

    # Create remote thread
    remote_thread = @client.threads.create

    # Save the ID to our new FaqThread model
    @faq_thread.update!(openai_thread_id: remote_thread['id'])
  end

  def retrieve_latest_assistant_message
    messages = @client.messages.list(
      thread_id: @faq_thread.openai_thread_id,
      parameters: { limit: 1 }
    )

    messages['data'].first['content'].first['text']['value']
  end
end
