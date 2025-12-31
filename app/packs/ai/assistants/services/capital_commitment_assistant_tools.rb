# CapitalCommitmentAssistantTools
#
# A namespace for all the tool definitions used by the CapitalCommitmentAssistant.
#
class CapitalCommitmentAssistantTools < BaseAssistantTools
  # Tool to get details of a specific commitment.
  class GetCommitmentDetails < RubyLLM::Tool
    def name = "get_commitment_details"

    description "Get details of a specific capital commitment"
    param :commitment_id, type: "integer", desc: "The ID of the commitment", required: true

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(commitment_id:)
      @data_manager.get_commitment_details(commitment_id: commitment_id).to_json
    end
  end

  # Tool to list capital remittances for a specific commitment.
  class ListCapitalRemittances < RubyLLM::Tool
    def name = "list_capital_remittances"

    description "List capital remittances for a specific commitment. " \
                "Attributes for query: status, verified, payment_date, remittance_date, call_amount, collected_amount. " \
                "Ordering: pass `sort`, e.g. sort: 'payment_date desc'."
    param :commitment_id, type: "integer", desc: "The ID of the commitment", required: true
    param :scope, type: :string, desc: "Filter by scope: 'paid', 'pending', 'verified', 'unverified'", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(commitment_id:, scope: nil, query: {}, sort: nil)
      @data_manager.list_capital_remittances(commitment_id: commitment_id, scope: scope, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to list distribution payments for a specific commitment.
  class ListCapitalDistributionPayments < RubyLLM::Tool
    def name = "list_capital_distribution_payments"

    description "List distribution payments for a specific commitment. " \
                "Ordering: pass `sort`, e.g. sort: 'payment_date desc'."
    param :commitment_id, type: "integer", desc: "The ID of the commitment", required: true
    param :scope, type: :string, desc: "Filter by scope: 'completed', 'incomplete', 'notification_sent', 'notification_not_sent'", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(commitment_id:, scope: nil, sort: nil)
      @data_manager.list_capital_distribution_payments(commitment_id: commitment_id, scope: scope, sort: sort).to_json
    end
  end

  # Tool to list documents associated with a commitment.
  class ListDocuments < RubyLLM::Tool
    def name = "list_documents"

    description "List documents associated with a capital commitment only if you need documents. " \
                "Attributes for query: name, owner_tag, text, esign_status. " \
                "Ordering: pass `sort`, e.g. sort: 'created_at desc'."
    param :commitment_id, type: "integer", desc: "The ID of the commitment", required: true
    param :scope, type: :string, desc: "Filter by scope: 'approved', 'signed', 'esign_status_completed', etc.", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'created_at desc'.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(commitment_id:, scope: nil, query: {}, sort: nil)
      @data_manager.list_documents(commitment_id: commitment_id, scope: scope, query: query || {}, sort: sort).to_json
    end
  end

  # Tool to get details for a specific document.
  class GetDocument < RubyLLM::Tool
    def name = "get_document"

    description "Get detailed information and full text content for a specific document by ID or name."
    param :commitment_id, type: "integer", desc: "The ID of the commitment", required: true
    param :document_id, type: "integer", desc: "The ID of the document", required: false
    param :name, type: "string", desc: "The name of the document (can be partial)", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(commitment_id:, document_id: nil, name: nil)
      @data_manager.get_document(commitment_id: commitment_id, document_id: document_id, name: name).to_json
    end
  end

  # Tool to analyze one or more documents.
  class AnalyzeDocument < RubyLLM::Tool
    def name = "analyze_document"

    description "Analyze one or more documents to answer specific questions or perform extraction. Requires commitment ID, document IDs or names and a natural language prompt."
    param :commitment_id, type: "integer", desc: "The ID of the commitment", required: true
    param :document_ids, type: "array", desc: "List of document IDs to analyze", required: false
    param :document_names, type: "array", desc: "List of document names (can be partial) to analyze", required: false
    param :prompt, type: "string", desc: "Natural language instructions or question for the analysis", required: true

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(commitment_id:, prompt:, document_ids: [], document_names: [])
      @data_manager.analyze_documents(commitment_id: commitment_id, prompt: prompt, document_ids: document_ids, document_names: document_names).to_json
    end
  end

  # PlotChart is inherited from BaseAssistantTools
  class PlotChart < BaseAssistantTools::PlotChart
    def name = "plot_chart"
  end
end
