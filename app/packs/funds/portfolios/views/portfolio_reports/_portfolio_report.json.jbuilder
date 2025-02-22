json.extract! portfolio_report, :id, :entity_id, :name, :tags, :include_kpi, :include_portfolio_investments, :extraction_questions, :created_at, :updated_at
json.url portfolio_report_url(portfolio_report, format: :json)
