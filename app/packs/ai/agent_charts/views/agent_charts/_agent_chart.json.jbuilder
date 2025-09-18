json.extract! agent_chart, :id, :title, :prompt, :raw_data, :spec, :llm_model, :status, :error, :created_at, :updated_at
json.url agent_chart_url(agent_chart, format: :json)
