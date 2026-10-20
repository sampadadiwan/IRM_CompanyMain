# frozen_string_literal: true

require "administrate/base_dashboard"

# Admin › Support Console Queries: every lookup the assistant attempted (design card ⑧).
class SupportConsoleQueryDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    created_at: Field::DateTime,
    user: Field::BelongsTo,
    entity: Field::BelongsTo,
    agent_chat_session_id: Field::Number,
    outcome: Field::String,
    reason: Field::String,
    flagged: Field::BooleanEmoji,
    row_count: Field::Number,
    duration_ms: Field::Number,
    lag_seconds: Field::Number,
    code_rev: Field::String,
    sql_text: Field::Text
  }.freeze

  COLLECTION_ATTRIBUTES = %i[created_at user entity outcome flagged row_count duration_ms].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    created_at user entity agent_chat_session_id outcome reason flagged row_count duration_ms lag_seconds code_rev sql_text
  ].freeze

  FORM_ATTRIBUTES = [].freeze

  COLLECTION_FILTERS = {}.freeze
end
