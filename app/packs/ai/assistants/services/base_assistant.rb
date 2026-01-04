# BaseAssistant
#
# Common base class for all AI assistants to share core logic for running queries and reports.
#
class BaseAssistant
  attr_reader :data_manager

  def initialize(user:, chat: nil)
    @user = user
    @chat = chat
  end

  # --- Public API ---

  # Executes the AI assistant with a user prompt.
  #
  # @param prompt [String] The user's input.
  # @return [RubyLLM::Response] The assistant's response.
  def run(prompt)
    Rails.logger.debug { "#{self.class.name} User: #{prompt}" }

    @chat ||= find_or_create_chat

    @chat.with_instructions(system_prompt)
    @chat.with_tools(*tools)

    # RubyLLM handles the tool execution loop automatically
    begin
      response = @chat.ask(prompt)
    rescue StandardError => e
      handle_tool_call_error(e, prompt)
      retry
    end

    # Clean up internal monologue
    clean_response!(response)

    Rails.logger.debug { "\n🤖 #{self.class.name}:" }
    Rails.logger.debug response.content

    response
  end

  # Convenience helper to run a report by iterating through queries.
  #
  # @param queries [Array<String>] The prompts to ask in order.
  # @param sleep_seconds [Numeric] Delay between prompts to avoid bursty traffic.
  # @param max_retries [Integer] Retries per prompt when the provider returns rate-limit/quota errors.
  # @param base_backoff_seconds [Numeric] Base delay for exponential backoff.
  # @param on_error [Symbol] What to do when retries are exhausted. (:raise or :collect)
  # @return [Array<Hash>] Array of { prompt:, response: } pairs.
  def run_report(
    queries: default_report_queries,
    sleep_seconds: ENV.fetch('AI_MONTHLY_REPORT_SLEEP_SECONDS', '1').to_f,
    max_retries: ENV.fetch('AI_MONTHLY_REPORT_MAX_RETRIES', '5').to_i,
    base_backoff_seconds: ENV.fetch('AI_MONTHLY_REPORT_BACKOFF_SECONDS', '1.0').to_f,
    on_error: :collect
  )
    total_input_tokens = 0
    total_output_tokens = 0

    queries.map do |q|
      tries = 0

      begin
        result = ask_ephemeral(q)
        result = { content: result.to_s, input_tokens: 0, output_tokens: 0 } unless result.is_a?(Hash)

        response_text = result[:content]

        total_input_tokens += result[:input_tokens].to_i
        total_output_tokens += result[:output_tokens].to_i

        sleep(sleep_seconds) if sleep_seconds.positive?

        log_cumulative_tokens(total_input_tokens, total_output_tokens)

        { prompt: q, response: response_text, input_tokens: result[:input_tokens], output_tokens: result[:output_tokens] }
      rescue RubyLLM::RateLimitError => e
        tries += 1
        raise e if tries > max_retries && on_error == :raise

        if tries > max_retries
          { prompt: q, error: e.class.name, message: e.message }
        else
          backoff = base_backoff_seconds * (2**(tries - 1))
          jitter = rand * 0.25
          sleep(backoff + jitter)
          retry
        end
      end
    end
  end

  # --- Methods to be overridden by subclasses ---

  def tools
    raise NotImplementedError, "#{self.class.name} must implement #tools"
  end

  def system_prompt
    raise NotImplementedError, "#{self.class.name} must implement #system_prompt"
  end

  def default_report_queries
    []
  end

  # --- Internal Helpers ---

  private

  # Runs a single prompt using a fresh, in-memory RubyLLM chat.
  def ask_ephemeral(prompt)
    Rails.logger.debug "\n\n#############################################"
    Rails.logger.debug { "🤖 Asking ephemeral prompt: #{prompt.inspect}" }

    begin
      response = run(prompt)
    rescue StandardError => e
      handle_bad_request(e)
    end

    content = extract_content(response)

    Rails.logger.debug { "🤖 Ephemeral response: #{content.inspect}" }
    { content: content, input_tokens: response.input_tokens, output_tokens: response.output_tokens }
  end

  def find_or_create_chat
    # Subclasses can override this to provide specific chat scoping
    Chat.where(
      user: @user,
      entity_id: @user.entity_id,
      assistant_type: self.class.name,
      model: self.class::AI_MODEL
    ).first_or_create!(
      owner: @user,
      enable_broadcast: false,
      name: "#{self.class.name} Chat #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}"
    )
  end

  def clean_response!(response)
    content = response.content

    if content.is_a?(String) && content.include?("thought")
      response.content = content.split("thought").last.to_s.strip
    elsif content.respond_to?(:text) && content.text.to_s.include?("thought")
      content.text = content.text.to_s.split("thought").last.to_s.strip
    end
  end

  def extract_content(response)
    content = response.content
    if content.respond_to?(:text)
      content.text
    else
      content
    end
  end

  def handle_bad_request(error)
    Rails.logger.debug { "⚠️ Caught BadRequestError: #{error.message}" }
    Rails.logger.debug error.backtrace.join("\n")
    if error.message.include?("Repeated map key")
      Rails.logger.debug "⚠️ Caught repeated map key error, retrying without some tools or instructions..."
      return "Error: The AI encountered a technical issue with the data query (repeated parameters). Please try rephrasing your question."
    end
    raise error
  end

  def handle_tool_call_error(exception, user_prompt)
    Rails.logger.error { "Tool execution failed: #{exception.message} for #{user_prompt}" }
    @retry_count ||= 0
    if @retry_count < 3
      @retry_count += 1
      Rails.logger.info "Retrying tool execution (#{@retry_count}/3)..."
      @chat.messages.create!(role: "system", content: "The previous tool call failed with error: #{exception.message}. Please try again with corrected parameters.")
    else
      @retry_count = 0
      raise exception
    end
  end

  def log_cumulative_tokens(input, output)
    Rails.logger.debug "\n\n#############################################"
    Rails.logger.debug { "Cumulative Tokens - Input: #{input}, Output: #{output}, Total: #{input + output}" }
    Rails.logger.debug "#############################################\n\n"
  end
end
