# Read-only, run ON an app host: every Support Console lookup's SQL and outcome, as JSON on stdout
# after a JSON-START line. Save it locally as support_console/probes/out/staging_queries.json (README.md).
rows = SupportConsoleQuery.order(:id).pluck(:id, :entity_id, :outcome, :reason, :flagged, :row_count, :sql_text)
keys = %w[id entity_id outcome reason flagged row_count sql]
puts "JSON-START"
puts rows.map { |r| keys.zip(r).to_h }.to_json
