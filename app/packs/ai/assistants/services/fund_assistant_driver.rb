class FundAssistantDriver
  def initialize(user_id: nil, user: nil)
    @user = user || User.find(user_id)
    @assistant = FundAssistant.new(user: @user)

    # Initialize the chat client and register tools from the assistant
    @client = RubyLLM.chat(model: 'gemini-2.5-flash')
    @client.with_tools(*@assistant.tools) # Splat the array of tools

    @started = false
  end

  # Run the conversation
  def run(prompt)
    Rails.logger.debug { "User: #{prompt}" }

    # Prepend system prompt to the first message to avoid premature execution
    input = if @started
              prompt
            else
              @started = true
              "#{@assistant.system_prompt}\n\n#{prompt}"
            end

    # RubyLLM handles the tool execution loop automatically
    response = @client.ask(input)

    # The AI often includes an internal 'thought' process in the final text response.
    # We strip this internal monologue to only return the final, clean answer.
    content = response.content

    if content.is_a?(String) && content.include?("thought")
      response.content = content.split("thought").last.to_s.strip
    elsif content.respond_to?(:text) && content.text.to_s.include?("thought")
      content.text = content.text.to_s.split("thought").last.to_s.strip
    end

    Rails.logger.debug "\n🤖 Assistant:"
    Rails.logger.debug response.content

    response
  end
end
