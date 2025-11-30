namespace :faq_threads do
  desc "Uploads docs from docs/ folder and creates an OpenAI Assistant"
  task setup: :environment do
    # Ensure you have a folder named 'docs' in your root with .pdf, .txt or .md files
    docs_path = Rails.root.join("public/docs")

    unless Dir.exist?(docs_path)
      puts "❌ Error: Directory 'docs' not found. Please create it and add files."
      exit
    end

    KnowledgeBaseSetupService.new(
      docs_path: docs_path,
      assistant_name: "CapHive Support Bot"
    ).call
  end

  desc "Deletes an OpenAI Assistant given an FAQ_ASSISTANT_ID"
  task delete_assistant: :environment do
    assistant_id = ENV['FAQ_ASSISTANT_ID']
    unless assistant_id
      puts "❌ Error: Please provide FAQ_ASSISTANT_ID environment variable."
      exit
    end

    KnowledgeBaseSetupService.delete_assistant(assistant_id)
  end

  desc "Recreates an OpenAI Assistant using an existing VECTOR_STORE_ID"
  task recreate_assistant: :environment do
    vector_store_id = ENV['VECTOR_STORE_ID']
    unless vector_store_id
      puts "❌ Error: Please provide VECTOR_STORE_ID environment variable."
      exit
    end

    KnowledgeBaseSetupService.new(
      assistant_name: "CapHive Support Bot",
      vector_store_id: vector_store_id
    ).call
  end

  desc "Retrieves an OpenAI Assistant details including Vector Store IDs"
  task get_assistant: :environment do
    assistant_id = ENV['FAQ_ASSISTANT_ID']
    unless assistant_id
      puts "❌ Error: Please provide FAQ_ASSISTANT_ID environment variable."
      exit
    end

    response = KnowledgeBaseSetupService.get_assistant(assistant_id)
    if response
      puts "\n📋 Assistant Details:"
      puts "ID: #{response['id']}"
      puts "Name: #{response['name']}"
      puts "Model: #{response['model']}"

      if response['tool_resources']&.dig('file_search', 'vector_store_ids')
        puts "📂 Vector Store IDs: #{response['tool_resources']['file_search']['vector_store_ids']}"
      else
        puts "⚠️ No vector stores attached."
      end
    end
  end
end