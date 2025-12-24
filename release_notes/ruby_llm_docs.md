# RubyLLM Documentation

RubyLLM is a delightful Ruby way to work with AI. It provides a unified interface to OpenAI, Anthropic, Google, DeepSeek, and more.

## Installation

Add RubyLLM to your Gemfile:

```ruby
bundle add ruby_llm
```

### Rails Quick Setup

For Rails applications, use the generator to set up database-backed conversations:

```bash
rails generate ruby_llm:install
```

This creates `Chat` and `Message` models with ActiveRecord persistence.

### Adding a Chat UI

After running the install generator, you can optionally add a ready-to-use chat interface:

```bash
rails generate ruby_llm:chat_ui
```

This creates:
- Controllers for managing chats and messages
- Views with Turbo streaming for real-time updates
- Background job for processing AI responses
- Routes for the chat interface

## Configuration

RubyLLM needs API keys for the AI providers you want to use.

```ruby
# config/initializers/ruby_llm.rb (in Rails) or at the start of your script
require 'ruby_llm'

RubyLLM.configure do |config|
  # Add keys ONLY for the providers you intend to use.
  config.openai_api_key = ENV.fetch('OPENAI_API_KEY', nil)
  config.anthropic_api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)

  # Set a default model
  config.default_model = "gpt-4-1-nano"
end
```

### Layered Configuration

RubyLLM supports three levels of configuration:

1. **Global Configuration**: Applies everywhere.
2. **Context Configuration**: Isolated scope for multi-tenancy.
   ```ruby
   context = RubyLLM.context do |config|
     config.openai_api_key = tenant.api_key
     config.default_model = "gpt-4.1"
   end
   chat = context.chat
   ```
3. **Instance Configuration**: Override for a specific instance.
   ```ruby
   chat = RubyLLM.chat(model: "claude-opus-4", temperature: 0.7)
   ```

## Core Features

### Chat

Interact with language models using `RubyLLM.chat`.

```ruby
# Create a chat instance
chat = RubyLLM.chat

# Ask a question
response = chat.ask "What is Ruby on Rails?"
puts response.content
```

RubyLLM handles conversation history automatically.

### Tools

Tools allow AI models to call Ruby code during conversations.

```ruby
class Calculator < RubyLLM::Tool
  description "Performs basic arithmetic"
  param :expression, desc: "Mathematical expression to evaluate"

  def execute(expression:)
    { result: eval(expression) }
  end
end

chat = RubyLLM.chat(tools: [Calculator.new])
response = chat.ask "What is 2 + 2?"
```

### Stream Responses

Display AI responses in real-time as they're generated.

```ruby
chat.ask "Write a story about a space cat" do |chunk|
  print chunk.content
end
```

### Embeddings

Transform text into numerical vectors for semantic search.

```ruby
embedding = RubyLLM.embed("Ruby is optimized for programmer happiness.")
vector = embedding.vectors
puts "Vector dimension: #{vector.length}"
```

### Image Generation

Generate images using models like DALL-E 3 or Imagen.

```ruby
image = RubyLLM.paint("A photorealistic red panda coding Ruby")
if image.url
  puts image.url
end
image.save("red_panda.png")
```

## Design Principles

- **Provider Agnostic**: The framework treats all AI providers equally. The code looks the same whether using OpenAI, Anthropic, or local models via Ollama.
- **Progressive Disclosure**: Simple things are simple (one line for chat), but complex things are possible (streaming, tool calling, structured output).
- **Ruby Conventions**: Built for developer happiness, following standard Ruby and Rails patterns.
- **Minimal Dependencies**: Lightweight and fast.

## Advanced Usage

### Rails Integration
RubyLLM integrates deeply with Rails, providing ActiveRecord models for persistence and Turbo Stream support for real-time UIs.

### Async Support
Scale your AI applications with built-in async support for handling multiple requests efficiently.

### Error Handling
Robust error handling for API failures, rate limits, and provider-specific issues.
