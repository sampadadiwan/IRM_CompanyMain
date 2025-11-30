class KnowledgeBaseSetupService
  # USAGE:
  #  KnowledgeBaseSetupService.new(
  #   docs_path: "docs/products",
  #   assistant_name: "Product Support Bot"
  # ).call

  def initialize(docs_path:, assistant_name:)
    @client = OpenAI::Client.new
    @docs_path = docs_path
    @assistant_name = assistant_name
  end

  def call
    Rails.logger.debug "📦 Starting Knowledge Base Setup..."

    # 1. Create Vector Store
    vector_store = create_vector_store
    Rails.logger.debug { "✅ Vector Store Created: #{vector_store['id']}" }

    # 2. Upload Files to Vector Store
    upload_files_to_store(vector_store['id'])

    # 3. Create/Update Assistant
    assistant = create_assistant(vector_store['id'])

    Rails.logger.debug "\n🎉 SETUP COMPLETE!"
    Rails.logger.debug "---------------------------------------------------"
    Rails.logger.debug "Add this to your .env file:"
    Rails.logger.debug { "FAQ_ASSISTANT_ID=#{assistant['id']}" }
    Rails.logger.debug "---------------------------------------------------"

    assistant
  end

  private

  def create_vector_store
    @client.vector_stores.create(parameters: {
                                   name: "#{@assistant_name} - Knowledge Base"
                                 })
  end

  def upload_files_to_store(vector_store_id)
    files = Dir.glob(File.join(@docs_path, "*"))
    Rails.logger.debug { "--- Found #{files.count} files. Uploading..." }

    file_ids = files.map do |file_path|
      # Upload each file individually
      response = @client.files.upload(parameters: { file: File.open(file_path), purpose: "assistants" })
      Rails.logger.debug "."
      response["id"]
    end
    Rails.logger.debug "\n✅ Files uploaded. Adding to Vector Store..."

    # Create a batch with the uploaded file IDs
    batch = @client.vector_store_file_batches.create(
      vector_store_id: vector_store_id,
      parameters: { file_ids: file_ids }
    )

    # Poll for completion
    Rails.logger.debug "--- Waiting for processing..."
    loop do
      sleep 2
      status = @client.vector_store_file_batches.retrieve(
        vector_store_id: vector_store_id,
        id: batch["id"]
      )
      state = status["status"]
      Rails.logger.debug { "Status: #{state}   \r" }

      if %w[completed failed cancelled expired].include?(state)
        Rails.logger.debug { "\nBatch finished with status: #{state}" }
        break
      end
    end

    Rails.logger.debug "✅ Files indexed successfully."
  end

  def create_assistant(vector_store_id)
    # Define the bot's persona
    instructions = <<~TEXT
      You are a helpful customer support agent for our company.
      Use the attached Knowledge Base files to answer questions.
      If the answer is not in the files, politely say you don't know
      and advise them to email support@example.com.
      Keep answers concise and friendly.
    TEXT

    @client.assistants.create(parameters: {
                                model: "gpt-4o", # Or gpt-3.5-turbo-0125
                                name: @assistant_name,
                                instructions: instructions,
                                tools: [{ type: "file_search" }],
                                tool_resources: {
                                  file_search: { vector_store_ids: [vector_store_id] }
                                }
                              })
  end
end
