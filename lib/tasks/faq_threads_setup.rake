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
end