# config/initializers/ruby_llm_patch.rb

module RubyLLM
  class Chat
    attr_reader :message_filter_block
    attr_accessor :max_tool_iterations

    # Adds a with_messages method that allows filtering messages before they're sent to the provider.
    def with_messages(&block)
      @message_filter_block = block
      self
    end

    # Reset tool iteration count on every new user ask
    alias original_ask ask
    def ask(message = nil, with: nil, &)
      @tool_iteration_count = 0
      original_ask(message, with: with, &)
    end

    # Override complete to apply the message filter and tool loop protection
    alias original_complete complete

    def complete(&)
      @tool_iteration_count ||= 0
      @tool_iteration_count += 1

      # Tool Loop Protection: Prevent infinite tool call loops
      limit = @max_tool_iterations || 15 # Default to 15 turns per request
      if @tool_iteration_count > limit
        error_msg = "Error: Maximum tool execution limit reached (#{limit} turns). " \
                    "The assistant stopped to prevent an excessively long processing time or infinite loop. " \
                    "Please try refining your request or asking for data in smaller batches."

        # Create a message object that looks like a real response
        response = RubyLLM::Message.new(role: :assistant, content: error_msg)

        # We MUST add it to the chat so persistence and UI show it
        add_message(response)
        @on[:end_message]&.call(response)

        return response
      end

      # with_messages Filter Logic
      if @message_filter_block
        filtered_messages = @message_filter_block.call(@messages)

        # Temporarily swap @messages to ensure @provider.complete uses the filtered list
        original_messages = @messages
        begin
          @messages = filtered_messages
          original_complete(&)
        ensure
          # Restore original messages so persistence and future turn items are correct
          @messages = original_messages
        end
      else
        original_complete(&)
      end
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
