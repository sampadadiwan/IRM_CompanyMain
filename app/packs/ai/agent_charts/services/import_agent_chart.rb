class ImportAgentChart < ImportUtil
  # Remove the creation of custom fields - AgentChart does not have custom fields
  step nil, delete: :create_custom_fields

  STANDARD_HEADERS = ["Title", "Status", "Prompt", "Document Ids", "Error"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def post_process(ctx, import_upload:, **)
    super
    # No specific post-processing for AgentChart yet, similar to InvestorNoticeJob
    true
  end

  def save_row(user_data, import_upload, custom_field_headers, _ctx)
    title, status, prompt, document_names = get_data(user_data, custom_field_headers)

    agent_chart = AgentChart.where(title:, entity_id: import_upload.entity_id).first

    if agent_chart.present?
      Rails.logger.debug { "AgentChart #{title} already exists for entity #{import_upload.entity_id}" }
      raise "AgentChart #{title} already exists."
    else
      # Create a new agent_chart
      Rails.logger.debug user_data
      agent_chart = AgentChart.new(title:, status:, prompt:, document_names:,
                                   import_upload_id: import_upload.id,
                                   entity_id: import_upload.entity_id)
    end

    # Save the agent_chart
    Rails.logger.debug { "Saving AgentChart with title '#{agent_chart.title}'" }
    agent_chart.save!
  end

  def get_data(user_data, _custom_field_headers)
    title = user_data['Title']
    status = user_data['Status']
    prompt = user_data['Prompt']
    document_names = user_data['Document Ids']&.split(',')&.map(&:strip) # Split by comma and strip whitespace

    [title, status, prompt, document_names]
  end
end
