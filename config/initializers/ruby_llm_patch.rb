# config/initializers/ruby_llm_patch.rb
#
# Written against ruby_llm 2.x, where Chat#complete is a loop of #step calls and every
# model request goes through #generate (one call per tool round).

module RubyLLM
  class Chat
    attr_reader :message_filter_block
    attr_accessor :max_tool_iterations

    # Adds a with_messages method that allows filtering messages before they're sent to the provider.
    def with_messages(&block)
      @message_filter_block = block
      self
    end

    # Reset the tool iteration count once per completion loop. Both Chat#ask and the
    # ActiveRecord chat's #ask reach this exactly once per user question.
    alias original_complete complete
    def complete(&)
      @tool_iteration_count = 0
      original_complete(&)
    end

    # Tool Loop Protection: count model requests within one completion loop and stop
    # once the limit is passed. Default raised from 15 → 25 to accommodate the KPI batching
    # flow in PortfolioAssistant (list_portfolio_companies → list_portfolio_kpis → plot_chart)
    # which legitimately requires more turns than a simple single-tool query.
    # Configurable via MAX_TOOL_ITERATIONS env var to allow per-environment tuning.
    alias original_generate generate
    def generate(&)
      @tool_iteration_count ||= 0
      @tool_iteration_count += 1

      limit = @max_tool_iterations || ENV.fetch('MAX_TOOL_ITERATIONS', '25').to_i
      return original_generate(&) if @tool_iteration_count <= limit

      error_msg = "Error: Maximum tool execution limit reached (#{limit} turns). " \
                  "The assistant stopped to prevent an excessively long processing time or infinite loop. " \
                  "Please try refining your request or asking for data in smaller batches."

      # A plain assistant reply (no tool calls) ends the #complete loop. Add it the way a
      # generated reply is added so the ActiveRecord callbacks persist and broadcast it.
      response = RubyLLM::Message.new(role: :assistant, content: error_msg)
      run_callbacks(:before_message)
      add_message(response)
      run_callbacks(:after_message, response)

      response
    end

    private

    # with_messages Filter Logic: narrow the list sent to the provider only. The chat's own
    # message history (and therefore persistence and later turns) is left untouched.
    alias original_preprocessed_messages preprocessed_messages
    def preprocessed_messages(list = messages)
      list = @message_filter_block.call(list) if @message_filter_block
      original_preprocessed_messages(list)
    end
  end

  module ActiveRecord
    module ChatMethods
      # Forward with_messages to the underlying LLM chat object
      def with_messages(&)
        to_llm.with_messages(&)
        self
      end
    end
  end
end
