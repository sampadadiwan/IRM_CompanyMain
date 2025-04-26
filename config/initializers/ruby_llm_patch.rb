# config/initializers/ruby_llm_patch.rb

module RubyLLM
  module ActiveRecord
    module ChatMethods
      # Replaces the original `ask` method with a new signature and implementation
      # This is to allow ChatMethods to also ask query with: {pdf: "xyz.pdf"}
      def ask(message, with: {}, &)
        # Save the user message to the DB
        messages.create!(
          role: :user,
          content: message
        )

        # Forward to the in-memory chat object with additional metadata
        to_llm.ask(message, with: with, &)
      end

      alias say ask
    end
  end
end
