# CapitalCommitmentAssistantTools
#
# A namespace for all the tool definitions used by the CapitalCommitmentAssistant.
#
class CapitalCommitmentAssistantTools < BaseAssistantTools
  # Tool to get details of the current commitment.
  class GetCommitmentDetails < RubyLLM::Tool
    def name = "get_commitment_details"

    description "Get details of the current capital commitment"

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(*)
      @data_manager.get_commitment_details.to_json
    end
  end

  # Tool to list capital remittances for the current commitment.
  class ListCapitalRemittances < RubyLLM::Tool
    def name = "list_capital_remittances"

    description "List capital remittances for the current commitment. " \
                "Attributes for query: status, verified, payment_date, remittance_date, call_amount, collected_amount. " \
                "Due date lives on the associated capital call, not on the remittance itself -- use the nested Ransack " \
                "attribute `capital_call_due_date` in `query` or `sort` (e.g. query: { capital_call_due_date_gteq: '2024-01-01' }, " \
                "sort: 'capital_call_due_date desc') for any 'due date' / 'coming due' / 'overdue by date' request. " \
                "NOTE: `capital_call_due_date` only works in `query`/`sort`, NOT as `group_by_field` -- grouping is a plain " \
                "column GROUP BY and doesn't support nested associations. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'top', 'latest', or 'largest' requests. Example: sort: 'payment_date desc', limit: 10. (Maps to Ransack `s`)"
    param :scope, type: :string, desc: "Filter by scope: 'paid', 'pending', 'verified', 'unverified'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`) ", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(scope: nil, query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @data_manager.list_capital_remittances(scope: scope, query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # Tool to list distribution payments for the current commitment.
  class ListCapitalDistributionPayments < RubyLLM::Tool
    def name = "list_capital_distribution_payments"

    description "List capital distribution payments for the current commitment. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'payment_date desc', limit: 10. (Maps to Ransack `s`)"
    param :scope, type: :string, desc: "Filter by scope: 'completed', 'incomplete', 'notification_sent', 'notification_not_sent'", required: false
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on (e.g., 'net_payable', 'gross_payable')", required: false
    param :group_by_field, type: :string, desc: "Field to group results by", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'payment_date desc'. (Maps to Ransack `s`) ", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(scope: nil, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      query = { aggregate_field: aggregate_field, group_by: group_by_field }.compact
      @data_manager.list_capital_distribution_payments(scope: scope, sort: sort, limit: limit, aggregate: aggregate, query: query).to_json
    end
  end

  # Tool to list documents associated with the current commitment.
  class ListDocuments < RubyLLM::Tool
    def name = "list_documents"

    description "List documents associated with the current capital commitment only if you need documents. " \
                "Attributes for query: name, owner_tag, text, esign_status. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency, especially for 'latest' or 'top' requests. Example: sort: 'created_at desc', limit: 10. (Maps to Ransack `s`)"
    param :scope, type: :string, desc: "Filter by scope: 'approved', 'signed', 'esign_status_completed', etc.", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'created_at desc'. (Maps to Ransack `s`) ", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(scope: nil, query: {}, sort: nil, limit: nil)
      @data_manager.list_documents(scope: scope, query: query || {}, sort: sort, limit: limit).to_json
    end
  end

  # Tool to get details for a specific document.
  class GetDocument < RubyLLM::Tool
    def name = "get_document"

    description "Get detailed information and full text content for a specific document by ID or name."
    param :document_id, type: "integer", desc: "The ID of the document", required: false
    param :name, type: "string", desc: "The name of the document (can be partial)", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(document_id: nil, name: nil)
      @data_manager.get_document(document_id: document_id, name: name).to_json
    end
  end

  # Tool to analyze one or more documents.
  class AnalyzeDocument < RubyLLM::Tool
    def name = "analyze_document"

    description "Analyze one or more documents to answer specific questions or perform extraction. Requires document IDs or names and a natural language prompt."
    param :document_ids, type: "array", desc: "List of document IDs to analyze", required: false
    param :document_names, type: "array", desc: "List of document names (can be partial) to analyze", required: false
    param :prompt, type: "string", desc: "Natural language instructions or question for the analysis", required: true

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(prompt:, document_ids: [], document_names: [])
      @data_manager.analyze_documents(prompt: prompt, document_ids: document_ids, document_names: document_names).to_json
    end
  end

  # Tool to list fund units for the current commitment.
  class ListFundUnits < RubyLLM::Tool
    def name = "list_fund_units"

    description "List fund units associated with the current capital commitment. " \
                "Attributes: unit_type, quantity, price, amount, as_of_date. " \
                "Ordering & Limiting: ALWAYS pass `sort` and `limit` for efficiency. Example: sort: 'as_of_date desc', limit: 10. (Maps to Ransack `s`)"
    param :aggregate_field, type: :string, desc: "Field to perform sum or group_by on (e.g., 'amount', 'quantity')", required: false
    param :group_by_field, type: :string, desc: "Field to group results by (e.g., 'unit_type')", required: false
    param :query, type: :object, desc: "Ransack query hash", required: false
    param :sort, type: :string, desc: "Optional sort string, e.g. 'as_of_date desc'. (Maps to Ransack `s`) ", required: false
    param :limit, type: :integer, desc: "Optional limit on the number of records returned. Recommended for efficiency.", required: false
    param :aggregate, type: :string, desc: "Perform an aggregation: 'count', 'sum', 'group_by'", required: false

    def initialize(data_manager)
      super()
      @data_manager = data_manager
    end

    def execute(query: {}, sort: nil, limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil, **_kwargs)
      q = (query || {}).with_indifferent_access
      q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
      q[:group_by] ||= group_by_field if group_by_field.present?

      @data_manager.list_fund_units(query: q, sort: sort, limit: limit, aggregate: aggregate).to_json
    end
  end

  # PlotChart is inherited from BaseAssistantTools
  class PlotChart < BaseAssistantTools::PlotChart
    def name = "plot_chart"
  end
end
