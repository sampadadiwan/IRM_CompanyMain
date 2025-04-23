class DocumentsTool < RubyLLM::Tool
    description "Searches for a document within the owner and returns it"
  
    attr_accessor :model
    attr_accessor :chat

    param :query, desc: "The query by the user for the llm", required: true
    param :name, desc: "The name of the document to be used in the query", required: true
    def execute(query:, name:)
      file_url = @model.documents.where("name like '%#{name}%'").first.file_url
      @chat.ask(query, with: {pdf: file_url})
    end

    def setup(model:, chat:)
      @model = model
      @chat = chat
      self
    end
end
  
# Let the AI use it
# chat.with_tool(DocumentTool).ask "Find Investor Presentation document for the kpi report "