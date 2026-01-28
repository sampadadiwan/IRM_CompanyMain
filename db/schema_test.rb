# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_24_073251) do
  create_table "access_rights", force: :cascade do |t|
    t.string "access_to_category", limit: 20
    t.string "access_to_email", limit: 30
    t.bigint "access_to_investor_id"
    t.string "access_type", limit: 25
    t.boolean "cascade", default: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "entity_id", null: false
    t.bigint "granted_by_id"
    t.string "metadata"
    t.boolean "notify", default: false
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.integer "parent_access_right_id"
    t.bigint "permissions", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["access_to_investor_id"], name: "index_access_rights_on_access_to_investor_id"
    t.index ["deleted_at"], name: "index_access_rights_on_deleted_at"
    t.index ["entity_id"], name: "index_access_rights_on_entity_id"
    t.index ["granted_by_id"], name: "index_access_rights_on_granted_by_id"
    t.index ["owner_type", "owner_id"], name: "index_access_rights_on_owner"
    t.index ["user_id"], name: "index_access_rights_on_user_id"
  end

  create_table "account_entries", force: :cascade do |t|
    t.bigint "allocation_run_id"
    t.decimal "amount_cents", precision: 30, scale: 8, default: "0.0"
    t.bigint "capital_commitment_id"
    t.string "commitment_name"
    t.datetime "created_at", null: false
    t.boolean "cumulative", default: false
    t.datetime "deleted_at"
    t.bigint "entity_id", null: false
    t.string "entry_type", limit: 60
    t.bigint "exchange_rate_id"
    t.text "explanation"
    t.decimal "folio_amount_cents", precision: 30, scale: 8, default: "0.0"
    t.string "folio_id", limit: 40
    t.bigint "form_type_id"
    t.bigint "fund_formula_id"
    t.bigint "fund_id", null: false
    t.boolean "generated", default: false
    t.datetime "generated_deleted", default: "1900-01-01 00:00:00", null: false
    t.bigint "import_upload_id"
    t.bigint "investor_id"
    t.json "json_fields"
    # Very important to have this NOCASE, else tests start failing
    t.string "name", limit: 125, collation: "NOCASE"
    t.text "notes"
    t.bigint "parent_id"
    t.string "parent_name"
    t.string "parent_type"
    t.string "period", limit: 25
    t.integer "ref_id", default: 0, null: false
    t.date "reporting_date", null: false
    t.string "rule_for", limit: 10, default: "Accounting"
    t.decimal "tracking_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.index ["allocation_run_id"], name: "index_account_entries_on_allocation_run_id"
    t.index ["capital_commitment_id", "name", "reporting_date"], name: "idx_ae_cc_name_date"
    t.index ["capital_commitment_id"], name: "index_account_entries_on_capital_commitment_id"
    t.index ["entity_id"], name: "index_account_entries_on_entity_id"
    t.index ["exchange_rate_id"], name: "index_account_entries_on_exchange_rate_id"
    t.index ["form_type_id"], name: "index_account_entries_on_form_type_id"
    t.index ["fund_formula_id"], name: "index_account_entries_on_fund_formula_id"
    t.index ["fund_id", "entry_type", "reporting_date"], name: "idx_fund_id_and_entry_type_and_reporting_date"
    t.index ["fund_id", "generated", "reporting_date", "fund_formula_id"], name: "idx_ae_fund_gen_date_formula"
    t.index ["fund_id", "name", "reporting_date"], name: "idx_fund_id_and_name_and_reporting_date"
    t.index ["fund_id", "reporting_date", "fund_formula_id", "deleted_at"], name: "idx_ae_fund_date_formula_deleted"
    t.index ["fund_id"], name: "index_account_entries_on_fund_id"
    t.index ["import_upload_id"], name: "index_account_entries_on_import_upload_id"
    t.index ["investor_id"], name: "index_account_entries_on_investor_id"
    t.index ["parent_type", "parent_id", "fund_id", "name", "deleted_at", "cumulative"], name: "idx_ae_parent_fund_name_flags"
    t.index ["reporting_date"], name: "index_account_entries_on_reporting_date"
  end

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "message_checksum", null: false
    t.string "message_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_admin_comments", force: :cascade do |t|
    t.bigint "author_id"
    t.string "author_type"
    t.text "body"
    t.datetime "created_at", null: false
    t.string "namespace"
    t.bigint "resource_id"
    t.string "resource_type"
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author"
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admin_users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "agent_charts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "document_names"
    t.bigint "entity_id", null: false
    t.text "error"
    t.integer "import_upload_id"
    t.integer "kpi_before", default: 12
    t.string "kpi_before_period", limit: 10, default: "Months"
    t.string "kpi_names"
    t.string "llm_model", limit: 20
    t.bigint "owner_id"
    t.string "owner_type"
    t.text "prompt"
    t.json "raw_data"
    t.integer "report_id"
    t.json "spec"
    t.string "status", limit: 10
    t.string "tag_list"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_agent_charts_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_agent_charts_on_owner"
  end

  create_table "aggregate_portfolio_investments", force: :cascade do |t|
    t.decimal "avg_cost_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "bought_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "bought_quantity", precision: 20, scale: 2, default: "0.0"
    t.decimal "cost_of_remaining_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "cost_of_sold_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.decimal "ex_expenses_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "fmv_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "form_type_id"
    t.bigint "fund_id", null: false
    t.decimal "gain_cents", precision: 20, scale: 2, default: "0.0", null: false
    t.decimal "instrument_currency_cost_of_remaining_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "instrument_currency_fmv_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "instrument_currency_unrealized_gain_cents", precision: 20, scale: 2, default: "0.0"
    t.string "investment_domicile", limit: 10
    t.bigint "investment_instrument_id"
    t.string "investment_type"
    t.decimal "net_bought_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "orignal_id"
    t.bigint "portfolio_company_id", null: false
    t.string "portfolio_company_name", limit: 100
    t.decimal "portfolio_income_cents", precision: 20, scale: 2, default: "0.0", null: false
    t.decimal "quantity", precision: 24, scale: 8, default: "0.0"
    t.boolean "show_portfolio", default: false
    t.boolean "snapshot", default: false
    t.date "snapshot_date"
    t.decimal "sold_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "sold_quantity", precision: 20, scale: 2, default: "0.0"
    t.decimal "tracking_bought_amount_cents", precision: 20, scale: 2, default: "0.0", null: false
    t.decimal "tracking_fmv_cents", precision: 20, scale: 2, default: "0.0", null: false
    t.decimal "tracking_sold_amount_cents", precision: 20, scale: 2, default: "0.0", null: false
    t.decimal "transfer_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "transfer_quantity", precision: 20, scale: 2, default: "0.0"
    t.decimal "unrealized_gain_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_aggregate_portfolio_investments_on_deleted_at"
    t.index ["document_folder_id"], name: "index_aggregate_portfolio_investments_on_document_folder_id"
    t.index ["entity_id"], name: "index_aggregate_portfolio_investments_on_entity_id"
    t.index ["form_type_id"], name: "index_aggregate_portfolio_investments_on_form_type_id"
    t.index ["fund_id"], name: "index_aggregate_portfolio_investments_on_fund_id"
    t.index ["investment_instrument_id"], name: "idx_on_investment_instrument_id_9bc45b0212"
    t.index ["portfolio_company_id"], name: "index_aggregate_portfolio_investments_on_portfolio_company_id"
    t.index ["snapshot_date"], name: "index_aggregate_portfolio_investments_on_snapshot_date"
  end

  create_table "ai_chat_messages", force: :cascade do |t|
    t.bigint "ai_chat_session_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.json "metadata"
    t.string "role"
    t.datetime "updated_at", null: false
    t.index ["ai_chat_session_id"], name: "index_ai_chat_messages_on_ai_chat_session_id"
  end

  create_table "ai_chat_sessions", force: :cascade do |t|
    t.bigint "ai_portfolio_report_id", null: false
    t.integer "analyst_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["ai_portfolio_report_id"], name: "index_ai_chat_sessions_on_ai_portfolio_report_id"
  end

  create_table "ai_checks", force: :cascade do |t|
    t.bigint "ai_rule_id"
    t.json "audit_log"
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.text "explanation"
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.bigint "parent_id", null: false
    t.string "parent_type", null: false
    t.string "rule_type", limit: 15
    t.string "status", limit: 5
    t.datetime "updated_at", null: false
    t.index ["ai_rule_id"], name: "index_ai_checks_on_ai_rule_id"
    t.index ["entity_id"], name: "index_ai_checks_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_ai_checks_on_owner"
    t.index ["parent_type", "parent_id"], name: "index_ai_checks_on_parent"
  end

  create_table "ai_portfolio_reports", force: :cascade do |t|
    t.integer "analyst_id"
    t.text "collated_report_html"
    t.datetime "created_at", null: false
    t.bigint "folder_id"
    t.integer "portfolio_company_id"
    t.date "report_date"
    t.string "status"
    t.datetime "updated_at", null: false
    t.boolean "web_search_enabled", default: false
    t.index ["folder_id"], name: "index_ai_portfolio_reports_on_folder_id"
  end

  create_table "ai_presentations", force: :cascade do |t|
    t.text "blueprint"
    t.bigint "chat_id", null: false
    t.text "content_html"
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_ai_presentations_on_chat_id"
    t.index ["entity_id"], name: "index_ai_presentations_on_entity_id"
  end

  create_table "ai_report_sections", force: :cascade do |t|
    t.json "agent_chart_ids"
    t.text "ai_generated_summary"
    t.bigint "ai_portfolio_report_id", null: false
    t.text "content_html"
    t.text "content_html_with_web"
    t.datetime "created_at", null: false
    t.datetime "created_at_document_only"
    t.datetime "created_at_web_included"
    t.json "metadata"
    t.integer "order_index"
    t.json "refinement_history"
    t.boolean "reviewed", default: false
    t.string "section_type"
    t.string "status"
    t.datetime "updated_at", null: false
    t.datetime "updated_at_document_only"
    t.datetime "updated_at_web_included"
    t.boolean "web_search_enabled", default: false, null: false
    t.index ["ai_portfolio_report_id"], name: "index_ai_report_sections_on_ai_portfolio_report_id"
  end

  create_table "ai_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true
    t.bigint "entity_id", null: false
    t.string "for_class", limit: 20
    t.string "name"
    t.text "rule"
    t.string "rule_type", limit: 15
    t.string "schedule", limit: 40
    t.string "tags"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_ai_rules_on_entity_id"
  end

  create_table "allocation_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "end_date"
    t.bigint "entity_id", null: false
    t.bigint "fund_id", null: false
    t.boolean "fund_ratios"
    t.boolean "generate_soa"
    t.boolean "locked", default: false
    t.string "rule_for", limit: 10, default: "Accounting"
    t.boolean "run_allocations", default: true
    t.date "start_date"
    t.text "status"
    t.string "tag_list"
    t.string "template_name", limit: 50
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["entity_id"], name: "index_allocation_runs_on_entity_id"
    t.index ["fund_id"], name: "index_allocation_runs_on_fund_id"
    t.index ["user_id"], name: "index_allocation_runs_on_user_id"
  end

  create_table "allocations", force: :cascade do |t|
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "avail_interest_quantity", precision: 10, scale: 2, default: "0.0"
    t.decimal "avail_offer_quantity", precision: 10, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.bigint "import_upload_id"
    t.bigint "interest_id", null: false
    t.json "json_fields"
    t.text "notes"
    t.bigint "offer_id", null: false
    t.decimal "price", precision: 20, scale: 2, default: "0.0"
    t.decimal "quantity", precision: 10, scale: 2, default: "0.0"
    t.bigint "secondary_sale_id", null: false
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false
    t.index ["deleted_at"], name: "index_allocations_on_deleted_at"
    t.index ["document_folder_id"], name: "index_allocations_on_document_folder_id"
    t.index ["entity_id"], name: "index_allocations_on_entity_id"
    t.index ["form_type_id"], name: "index_allocations_on_form_type_id"
    t.index ["interest_id"], name: "index_allocations_on_interest_id"
    t.index ["offer_id"], name: "index_allocations_on_offer_id"
    t.index ["secondary_sale_id"], name: "index_allocations_on_secondary_sale_id"
  end

  create_table "aml_reports", force: :cascade do |t|
    t.string "PAN"
    t.datetime "birth_date"
    t.datetime "created_at", null: false
    t.string "custom_name"
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.bigint "investor_id", null: false
    t.bigint "investor_kyc_id", null: false
    t.string "match_status"
    t.json "request_data"
    t.string "request_id"
    t.json "response_data"
    t.datetime "updated_at", null: false
    t.index ["document_folder_id"], name: "index_aml_reports_on_document_folder_id"
    t.index ["entity_id"], name: "index_aml_reports_on_entity_id"
    t.index ["investor_id"], name: "index_aml_reports_on_investor_id"
    t.index ["investor_kyc_id"], name: "index_aml_reports_on_investor_kyc_id"
  end

  create_table "approval_responses", force: :cascade do |t|
    t.bigint "approval_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.bigint "investor_id", null: false
    t.json "json_fields"
    t.boolean "notification_sent", default: false
    t.bigint "owner_id"
    t.string "owner_type"
    t.bigint "response_entity_id", null: false
    t.bigint "response_user_id"
    t.string "status", limit: 50
    t.datetime "updated_at", null: false
    t.index ["approval_id"], name: "index_approval_responses_on_approval_id"
    t.index ["deleted_at"], name: "index_approval_responses_on_deleted_at"
    t.index ["document_folder_id"], name: "index_approval_responses_on_document_folder_id"
    t.index ["entity_id"], name: "index_approval_responses_on_entity_id"
    t.index ["form_type_id"], name: "index_approval_responses_on_form_type_id"
    t.index ["investor_id"], name: "index_approval_responses_on_investor_id"
    t.index ["owner_type", "owner_id"], name: "index_approval_responses_on_owner"
    t.index ["response_entity_id"], name: "index_approval_responses_on_response_entity_id"
    t.index ["response_user_id"], name: "index_approval_responses_on_response_user_id"
  end

  create_table "approvals", force: :cascade do |t|
    t.boolean "approved", default: false
    t.integer "approved_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "document_folder_id"
    t.date "due_date"
    t.boolean "enable_approval_show_kycs", default: false
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.json "json_fields"
    t.boolean "locked"
    t.bigint "owner_id"
    t.string "owner_type"
    t.integer "pending_count", default: 0
    t.integer "rejected_count", default: 0
    t.boolean "response_enabled_email", default: false, null: false
    t.string "response_status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_approvals_on_deleted_at"
    t.index ["document_folder_id"], name: "index_approvals_on_document_folder_id"
    t.index ["entity_id"], name: "index_approvals_on_entity_id"
    t.index ["form_type_id"], name: "index_approvals_on_form_type_id"
    t.index ["owner_type", "owner_id"], name: "index_approvals_on_owner"
  end

  create_table "assistant_tasks", force: :cascade do |t|
    t.string "assistant_metadata"
    t.string "assistant_type", limit: 50
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.text "instructions"
    t.string "period", limit: 10
    t.string "tag_list"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["entity_id"], name: "index_assistant_tasks_on_entity_id"
    t.index ["user_id"], name: "index_assistant_tasks_on_user_id"
  end

  create_table "audits", force: :cascade do |t|
    t.string "action"
    t.integer "associated_id"
    t.string "associated_type"
    t.integer "auditable_id"
    t.string "auditable_type"
    t.text "audited_changes"
    t.string "comment"
    t.datetime "created_at"
    t.string "remote_address"
    t.string "request_uuid"
    t.integer "user_id"
    t.string "user_type"
    t.string "username"
    t.integer "version", default: 0
    t.index ["associated_type", "associated_id"], name: "associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end

  create_table "blazer_audits", force: :cascade do |t|
    t.datetime "created_at"
    t.string "data_source"
    t.bigint "query_id"
    t.text "statement"
    t.bigint "user_id"
    t.index ["query_id"], name: "index_blazer_audits_on_query_id"
    t.index ["user_id"], name: "index_blazer_audits_on_user_id"
  end

  create_table "blazer_checks", force: :cascade do |t|
    t.string "check_type"
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.text "emails"
    t.datetime "last_run_at"
    t.text "message"
    t.bigint "query_id"
    t.string "schedule"
    t.text "slack_channels"
    t.string "state"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_checks_on_creator_id"
    t.index ["query_id"], name: "index_blazer_checks_on_query_id"
  end

  create_table "blazer_dashboard_queries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "dashboard_id"
    t.integer "position"
    t.bigint "query_id"
    t.datetime "updated_at", null: false
    t.index ["dashboard_id"], name: "index_blazer_dashboard_queries_on_dashboard_id"
    t.index ["query_id"], name: "index_blazer_dashboard_queries_on_query_id"
  end

  create_table "blazer_dashboards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_dashboards_on_creator_id"
  end

  create_table "blazer_queries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "creator_id"
    t.string "data_source"
    t.text "description"
    t.string "name"
    t.text "statement"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_queries_on_creator_id"
  end

  create_table "blogs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "tag_list", limit: 100
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "call_fees", force: :cascade do |t|
    t.bigint "capital_call_id", null: false
    t.datetime "created_at", null: false
    t.date "end_date"
    t.bigint "entity_id", null: false
    t.string "fee_type", limit: 20
    t.boolean "formula", default: false
    t.bigint "fund_id", null: false
    t.string "name", limit: 50
    t.string "notes"
    t.date "start_date"
    t.datetime "updated_at", null: false
    t.index ["capital_call_id"], name: "index_call_fees_on_capital_call_id"
    t.index ["entity_id"], name: "index_call_fees_on_entity_id"
    t.index ["fund_id"], name: "index_call_fees_on_fund_id"
  end

  create_table "capital_calls", force: :cascade do |t|
    t.decimal "amount_to_be_called_cents", precision: 20, scale: 2, default: "0.0"
    t.boolean "approved", default: false
    t.bigint "approved_by_user_id"
    t.decimal "call_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.string "call_basis", limit: 40
    t.date "call_date"
    t.decimal "capital_fee_cents", precision: 20, scale: 2, default: "0.0"
    t.text "close_percentages"
    t.decimal "collected_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "document_folder_id"
    t.date "due_date"
    t.bigint "entity_id", null: false
    t.string "fee_formula_ids"
    t.bigint "form_type_id"
    t.string "fund_closes"
    t.bigint "fund_id", null: false
    t.boolean "generate_remittances", default: true
    t.boolean "generate_remittances_verified", default: false
    t.bigint "import_upload_id"
    t.json "json_fields"
    t.boolean "manual_generation", default: false
    t.string "name"
    t.text "notes"
    t.decimal "other_fee_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "percentage_called", precision: 11, scale: 8, default: "0.0"
    t.boolean "send_call_notice_flag", default: true
    t.boolean "send_payment_notification_flag", default: true
    t.text "unit_prices"
    t.datetime "updated_at", null: false
    t.index ["approved_by_user_id"], name: "index_capital_calls_on_approved_by_user_id"
    t.index ["deleted_at"], name: "index_capital_calls_on_deleted_at"
    t.index ["document_folder_id"], name: "index_capital_calls_on_document_folder_id"
    t.index ["entity_id"], name: "index_capital_calls_on_entity_id"
    t.index ["form_type_id"], name: "index_capital_calls_on_form_type_id"
    t.index ["fund_id"], name: "index_capital_calls_on_fund_id"
  end

  create_table "capital_commitments", force: :cascade do |t|
    t.decimal "adjustment_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "adjustment_folio_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "arrear_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "arrear_folio_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "call_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "collected_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.date "commitment_date"
    t.decimal "committed_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.boolean "compliant", default: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.decimal "distribution_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.boolean "esign_completed", default: false
    t.string "esign_emails"
    t.string "esign_link"
    t.string "esign_provider", limit: 10
    t.boolean "esign_required", default: false
    t.bigint "exchange_rate_id"
    t.bigint "feeder_fund_id"
    t.decimal "folio_call_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "folio_collected_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "folio_committed_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.string "folio_currency", limit: 5
    t.string "folio_id", limit: 40
    t.bigint "form_type_id"
    t.string "fund_close"
    t.bigint "fund_id", null: false
    t.datetime "generated_deleted", default: "1900-01-01 00:00:00"
    t.bigint "import_upload_id"
    t.bigint "investor_id", null: false
    t.bigint "investor_kyc_id"
    t.string "investor_name"
    t.bigint "investor_signatory_id"
    t.string "investor_signature_types", limit: 20
    t.boolean "is_feeder_fund", default: false
    t.json "json_fields"
    t.text "notes"
    t.boolean "onboarding_completed", default: false
    t.decimal "orig_committed_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "orig_folio_committed_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "other_fee_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "percentage", precision: 20, scale: 10, default: "0.0"
    t.bigint "ppm_number", default: 0
    t.string "slug"
    t.decimal "total_allocated_expense_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "total_allocated_income_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "total_fund_units_quantity", precision: 20, scale: 2, default: "0.0"
    t.decimal "total_units_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "total_units_premium_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "tracking_adjustment_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.decimal "tracking_collected_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.decimal "tracking_committed_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.decimal "tracking_distribution_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.decimal "tracking_orig_committed_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.string "unit_type", limit: 40
    t.datetime "updated_at", null: false
    t.string "virtual_bank_account", limit: 20
    t.index ["commitment_date"], name: "index_capital_commitments_on_commitment_date"
    t.index ["deleted_at"], name: "index_capital_commitments_on_deleted_at"
    t.index ["document_folder_id"], name: "index_capital_commitments_on_document_folder_id"
    t.index ["entity_id"], name: "index_capital_commitments_on_entity_id"
    t.index ["exchange_rate_id"], name: "index_capital_commitments_on_exchange_rate_id"
    t.index ["feeder_fund_id"], name: "index_capital_commitments_on_feeder_fund_id"
    t.index ["form_type_id"], name: "index_capital_commitments_on_form_type_id"
    t.index ["fund_id", "folio_id", "generated_deleted"], name: "unique_commitment", unique: true
    t.index ["fund_id"], name: "index_capital_commitments_on_fund_id"
    t.index ["investor_id"], name: "index_capital_commitments_on_investor_id"
    t.index ["investor_kyc_id"], name: "index_capital_commitments_on_investor_kyc_id"
    t.index ["investor_signatory_id"], name: "index_capital_commitments_on_investor_signatory_id"
    t.index ["slug"], name: "index_capital_commitments_on_slug", unique: true
  end

  create_table "capital_distribution_payments", force: :cascade do |t|
    t.bigint "capital_commitment_id"
    t.bigint "capital_distribution_id", null: false
    t.boolean "completed", default: false
    t.decimal "cost_of_investment_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "cost_of_investment_with_fees_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.bigint "exchange_rate_id"
    t.decimal "folio_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.string "folio_id", limit: 40
    t.bigint "form_type_id"
    t.bigint "fund_id", null: false
    t.decimal "gross_of_account_entries_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "gross_payable_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "import_upload_id"
    t.decimal "income_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "income_with_fees_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "investor_id", null: false
    t.string "investor_name"
    t.json "json_fields"
    t.decimal "net_of_account_entries_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "net_payable_cents", precision: 20, scale: 2, default: "0.0"
    t.boolean "notification_sent", default: false, null: false
    t.date "payment_date"
    t.decimal "percentage", precision: 12, scale: 8, default: "0.0"
    t.decimal "reinvestment_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "reinvestment_with_fees_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "tracking_gross_payable_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "tracking_net_payable_cents", precision: 20, scale: 4, default: "0.0"
    t.decimal "tracking_reinvestment_with_fees_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "units_quantity", precision: 20, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.index ["capital_commitment_id"], name: "index_capital_distribution_payments_on_capital_commitment_id"
    t.index ["capital_distribution_id"], name: "index_capital_distribution_payments_on_capital_distribution_id"
    t.index ["deleted_at"], name: "index_capital_distribution_payments_on_deleted_at"
    t.index ["document_folder_id"], name: "index_capital_distribution_payments_on_document_folder_id"
    t.index ["entity_id"], name: "index_capital_distribution_payments_on_entity_id"
    t.index ["exchange_rate_id"], name: "index_capital_distribution_payments_on_exchange_rate_id"
    t.index ["form_type_id"], name: "index_capital_distribution_payments_on_form_type_id"
    t.index ["fund_id"], name: "index_capital_distribution_payments_on_fund_id"
    t.index ["investor_id"], name: "index_capital_distribution_payments_on_investor_id"
  end

  create_table "capital_distributions", force: :cascade do |t|
    t.boolean "approved", default: false
    t.bigint "approved_by_user_id"
    t.bigint "capital_commitment_id"
    t.decimal "carry_cents", precision: 20, scale: 2, default: "0.0"
    t.boolean "completed", default: false
    t.decimal "completed_distribution_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.boolean "compliant", default: false
    t.decimal "cost_of_investment_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.decimal "distribution_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.date "distribution_date"
    t.integer "distribution_on", default: 0
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.decimal "fee_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "form_type_id"
    t.bigint "fund_id", null: false
    t.boolean "generate_payments", default: true
    t.boolean "generate_payments_paid", default: false
    t.decimal "gross_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "import_upload_id"
    t.decimal "income_cents", precision: 20, scale: 2, default: "0.0", null: false
    t.json "json_fields"
    t.boolean "manual_generation", default: false
    t.decimal "net_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.text "notes"
    t.decimal "reinvestment_cents", precision: 20, scale: 2, default: "0.0"
    t.boolean "send_notification_on_complete", default: true
    t.string "title"
    t.text "unit_prices"
    t.datetime "updated_at", null: false
    t.index ["approved_by_user_id"], name: "index_capital_distributions_on_approved_by_user_id"
    t.index ["capital_commitment_id"], name: "index_capital_distributions_on_capital_commitment_id"
    t.index ["deleted_at"], name: "index_capital_distributions_on_deleted_at"
    t.index ["document_folder_id"], name: "index_capital_distributions_on_document_folder_id"
    t.index ["entity_id"], name: "index_capital_distributions_on_entity_id"
    t.index ["form_type_id"], name: "index_capital_distributions_on_form_type_id"
    t.index ["fund_id"], name: "index_capital_distributions_on_fund_id"
  end

  create_table "capital_remittance_payments", force: :cascade do |t|
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "capital_remittance_id", null: false
    t.boolean "convert_to_fund_currency", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "entity_id", null: false
    t.bigint "exchange_rate_id"
    t.decimal "folio_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "form_type_id"
    t.bigint "fund_id", null: false
    t.bigint "import_upload_id"
    t.bigint "investor_id"
    t.json "json_fields"
    t.text "notes"
    t.date "payment_date"
    t.boolean "payment_notification_sent", default: false
    t.text "payment_proof_data"
    t.string "reference_no", limit: 40
    t.decimal "tracking_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.datetime "updated_at", null: false
    t.index ["capital_remittance_id"], name: "index_capital_remittance_payments_on_capital_remittance_id"
    t.index ["deleted_at"], name: "index_capital_remittance_payments_on_deleted_at"
    t.index ["entity_id"], name: "index_capital_remittance_payments_on_entity_id"
    t.index ["exchange_rate_id"], name: "index_capital_remittance_payments_on_exchange_rate_id"
    t.index ["form_type_id"], name: "index_capital_remittance_payments_on_form_type_id"
    t.index ["fund_id"], name: "index_capital_remittance_payments_on_fund_id"
    t.index ["investor_id"], name: "index_capital_remittance_payments_on_investor_id"
    t.index ["payment_date"], name: "index_capital_remittance_payments_on_payment_date"
  end

  create_table "capital_remittances", force: :cascade do |t|
    t.decimal "arrear_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "arrear_folio_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "call_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.string "call_basis", limit: 40
    t.bigint "capital_call_id", null: false
    t.bigint "capital_commitment_id"
    t.decimal "capital_fee_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "collected_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "committed_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.boolean "compliant", default: false
    t.decimal "computed_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.string "created_by", limit: 10
    t.datetime "deleted_at"
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.bigint "exchange_rate_id"
    t.decimal "folio_call_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "folio_capital_fee_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "folio_collected_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "folio_committed_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.string "folio_id", limit: 40
    t.decimal "folio_investment_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "folio_other_fee_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "form_type_id"
    t.bigint "fund_id", null: false
    t.bigint "import_upload_id"
    t.decimal "investment_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "investor_id", null: false
    t.string "investor_name"
    t.json "json_fields"
    t.text "notes"
    t.boolean "notification_sent", default: false
    t.decimal "other_fee_cents", precision: 20, scale: 2, default: "0.0"
    t.date "payment_date"
    t.text "payment_proof_data"
    t.decimal "percentage", precision: 12, scale: 8, default: "0.0"
    t.date "remittance_date"
    t.string "status", limit: 10
    t.decimal "tracking_call_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.decimal "tracking_collected_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.decimal "units_quantity", precision: 20, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false
    t.index ["capital_call_id"], name: "index_capital_remittances_on_capital_call_id"
    t.index ["capital_commitment_id"], name: "index_capital_remittances_on_capital_commitment_id"
    t.index ["deleted_at"], name: "index_capital_remittances_on_deleted_at"
    t.index ["document_folder_id"], name: "index_capital_remittances_on_document_folder_id"
    t.index ["entity_id"], name: "index_capital_remittances_on_entity_id"
    t.index ["exchange_rate_id"], name: "index_capital_remittances_on_exchange_rate_id"
    t.index ["form_type_id"], name: "index_capital_remittances_on_form_type_id"
    t.index ["fund_id"], name: "index_capital_remittances_on_fund_id"
    t.index ["investor_id"], name: "index_capital_remittances_on_investor_id"
    t.index ["remittance_date"], name: "index_capital_remittances_on_remittance_date"
  end

  create_table "chats", force: :cascade do |t|
    t.string "assistant_type", limit: 50
    t.datetime "created_at", null: false
    t.boolean "enable_broadcast", default: true, null: false
    t.bigint "entity_id"
    t.bigint "model_id"
    t.string "name"
    t.bigint "owner_id"
    t.string "owner_type"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["entity_id"], name: "index_chats_on_entity_id"
    t.index ["model_id"], name: "index_chats_on_model_id"
    t.index ["owner_type", "owner_id"], name: "index_chats_on_owner"
    t.index ["user_id"], name: "index_chats_on_user_id"
  end

  create_table "ci_profiles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3
    t.datetime "deleted_at"
    t.text "details"
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.bigint "fund_id"
    t.decimal "fund_size_cents", precision: 20, scale: 2
    t.string "geography", limit: 50
    t.decimal "min_investment_cents", precision: 20, scale: 2
    t.text "properties"
    t.string "sector", limit: 50
    t.string "stage", limit: 50
    t.string "status"
    t.string "title"
    t.text "track_record"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_ci_profiles_on_deleted_at"
    t.index ["entity_id"], name: "index_ci_profiles_on_entity_id"
    t.index ["fund_id"], name: "index_ci_profiles_on_fund_id"
  end

  create_table "ci_track_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "details"
    t.bigint "entity_id", null: false
    t.bigint "investment_opportunity_id"
    t.string "name", limit: 50
    t.bigint "owner_id"
    t.string "owner_type"
    t.string "prefix", limit: 5
    t.string "suffix", limit: 5
    t.datetime "updated_at", null: false
    t.decimal "value", precision: 20, scale: 4
    t.index ["entity_id"], name: "index_ci_track_records_on_entity_id"
    t.index ["investment_opportunity_id"], name: "index_ci_track_records_on_investment_opportunity_id"
    t.index ["owner_type", "owner_id"], name: "index_ci_track_records_on_owner"
  end

  create_table "ci_widgets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "details"
    t.text "details_top"
    t.text "embed_script"
    t.bigint "entity_id", null: false
    t.text "image_data"
    t.string "image_placement", limit: 6, default: "Left"
    t.bigint "investment_opportunity_id"
    t.bigint "owner_id"
    t.string "owner_type"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["entity_id"], name: "index_ci_widgets_on_entity_id"
    t.index ["investment_opportunity_id"], name: "index_ci_widgets_on_investment_opportunity_id"
    t.index ["owner_type", "owner_id"], name: "index_ci_widgets_on_owner"
  end

  create_table "commitment_adjustments", force: :cascade do |t|
    t.string "adjustment_type", limit: 20, default: "Top Up", null: false
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.date "as_of"
    t.bigint "capital_commitment_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "entity_id", null: false
    t.bigint "exchange_rate_id"
    t.decimal "folio_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "fund_id", null: false
    t.bigint "owner_id"
    t.string "owner_type"
    t.decimal "post_adjustment_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "pre_adjustment_cents", precision: 20, scale: 2, default: "0.0"
    t.text "reason"
    t.decimal "tracking_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.date "transfer_date"
    t.datetime "updated_at", null: false
    t.index ["capital_commitment_id"], name: "index_commitment_adjustments_on_capital_commitment_id"
    t.index ["deleted_at"], name: "index_commitment_adjustments_on_deleted_at"
    t.index ["entity_id"], name: "index_commitment_adjustments_on_entity_id"
    t.index ["exchange_rate_id"], name: "index_commitment_adjustments_on_exchange_rate_id"
    t.index ["fund_id"], name: "index_commitment_adjustments_on_fund_id"
    t.index ["owner_type", "owner_id"], name: "index_commitment_adjustments_on_owner"
  end

  create_table "custom_grid_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id", "owner_type"], name: "index_custom_grid_views_on_owner_id_and_owner_type"
  end

  create_table "custom_notifications", force: :cascade do |t|
    t.string "attachment_names"
    t.string "attachment_password"
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "document_folder_id"
    t.string "email_method", limit: 100
    t.boolean "enabled", default: true
    t.bigint "entity_id", null: false
    t.string "for_type", limit: 100
    t.boolean "is_erb", default: false
    t.boolean "latest", default: true
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.boolean "password_protect_attachment", default: false
    t.boolean "show_details", default: false
    t.boolean "show_details_link", default: true
    t.string "subject"
    t.string "tag", limit: 30
    t.string "to", limit: 40
    t.datetime "updated_at", null: false
    t.string "whatsapp"
    t.index ["deleted_at"], name: "index_custom_notifications_on_deleted_at"
    t.index ["document_folder_id"], name: "index_custom_notifications_on_document_folder_id"
    t.index ["entity_id"], name: "index_custom_notifications_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_custom_notifications_on_owner"
  end

  create_table "dashboard_widgets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "dashboard_name", limit: 30
    t.boolean "display_name", default: false
    t.boolean "display_tag", default: false
    t.boolean "enabled", default: true
    t.bigint "entity_id", null: false
    t.integer "import_upload_id"
    t.text "metadata"
    t.string "name", limit: 20, default: "Default"
    t.bigint "owner_id"
    t.string "owner_type"
    t.integer "position"
    t.boolean "show_menu", default: true, null: false
    t.string "size", limit: 10
    t.string "tags", limit: 100
    t.datetime "updated_at", null: false
    t.string "widget_name", limit: 30
    t.index ["entity_id"], name: "index_dashboard_widgets_on_entity_id"
    t.index ["import_upload_id"], name: "index_dashboard_widgets_on_import_upload_id"
    t.index ["owner_type", "owner_id"], name: "index_dashboard_widgets_on_owner"
  end

  create_table "deal_activities", force: :cascade do |t|
    t.date "by_date"
    t.string "completed", limit: 5, default: "No"
    t.datetime "created_at", null: false
    t.integer "days"
    t.bigint "deal_id", null: false
    t.bigint "deal_investor_id"
    t.datetime "deleted_at"
    t.text "details"
    t.boolean "details_required_for_na", default: false
    t.boolean "docs_required_for_completion", default: false
    t.bigint "document_folder_id"
    t.integer "entity_id"
    t.integer "sequence"
    t.string "status", default: "incomplete"
    t.string "status_temp", limit: 20
    t.integer "template_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["deal_id"], name: "index_deal_activities_on_deal_id"
    t.index ["deal_investor_id"], name: "index_deal_activities_on_deal_investor_id"
    t.index ["deleted_at"], name: "index_deal_activities_on_deleted_at"
    t.index ["document_folder_id"], name: "index_deal_activities_on_document_folder_id"
    t.index ["entity_id"], name: "index_deal_activities_on_entity_id"
  end

  create_table "deal_docs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "deal_activity_id"
    t.bigint "deal_id", null: false
    t.bigint "deal_investor_id"
    t.datetime "deleted_at"
    t.string "file_content_type"
    t.string "file_file_name"
    t.bigint "file_file_size"
    t.datetime "file_updated_at"
    t.integer "impressions_count", default: 0
    t.string "name"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["deal_activity_id"], name: "index_deal_docs_on_deal_activity_id"
    t.index ["deal_id"], name: "index_deal_docs_on_deal_id"
    t.index ["deal_investor_id"], name: "index_deal_docs_on_deal_investor_id"
    t.index ["deleted_at"], name: "index_deal_docs_on_deleted_at"
    t.index ["user_id"], name: "index_deal_docs_on_user_id"
  end

  create_table "deal_investors", force: :cascade do |t|
    t.string "company_advisor", limit: 100
    t.datetime "created_at", null: false
    t.bigint "deal_activity_id"
    t.bigint "deal_id", null: false
    t.string "deal_lead"
    t.datetime "deleted_at"
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.decimal "fee_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "form_type_id"
    t.datetime "generated_deleted", default: "1900-01-01 00:00:00"
    t.integer "impressions_count"
    t.string "investor_advisor", limit: 100
    t.integer "investor_entity_id"
    t.bigint "investor_id", null: false
    t.string "investor_name"
    t.json "json_fields"
    t.text "notes"
    t.decimal "pre_money_valuation_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "primary_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "secondary_investment_cents", precision: 20, scale: 2, default: "0.0"
    t.string "slug"
    t.string "source"
    t.string "status", limit: 20
    t.string "tags"
    t.string "tier", limit: 20
    t.integer "todays_messages_investee", default: 0
    t.integer "todays_messages_investor", default: 0
    t.decimal "total_amount_cents", precision: 20, scale: 2
    t.integer "unread_messages_investee", default: 0
    t.integer "unread_messages_investor", default: 0
    t.datetime "updated_at", null: false
    t.index ["deal_activity_id"], name: "index_deal_investors_on_deal_activity_id"
    t.index ["deal_id"], name: "index_deal_investors_on_deal_id"
    t.index ["deleted_at"], name: "index_deal_investors_on_deleted_at"
    t.index ["document_folder_id"], name: "index_deal_investors_on_document_folder_id"
    t.index ["entity_id"], name: "index_deal_investors_on_entity_id"
    t.index ["form_type_id"], name: "index_deal_investors_on_form_type_id"
    t.index ["investor_entity_id"], name: "index_deal_investors_on_investor_entity_id"
    t.index ["investor_id", "deal_id", "generated_deleted"], name: "unique_deal_investor", unique: true
    t.index ["investor_id"], name: "index_deal_investors_on_investor_id"
    t.index ["slug"], name: "index_deal_investors_on_slug", unique: true
  end

  create_table "deals", force: :cascade do |t|
    t.text "activity_list"
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.boolean "archived", default: false
    t.json "card_view_attrs"
    t.bigint "clone_from_id"
    t.datetime "created_at", null: false
    t.string "currency", limit: 10
    t.bigint "data_room_folder_id"
    t.bigint "deal_documents_folder_id"
    t.datetime "deleted_at"
    t.bigint "document_folder_id"
    t.date "end_date"
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.integer "impressions_count", default: 0
    t.json "json_fields"
    t.string "name"
    t.string "slug"
    t.date "start_date"
    t.string "status", limit: 20
    t.string "tags", limit: 100
    t.string "units", limit: 15
    t.datetime "updated_at", null: false
    t.index ["clone_from_id"], name: "index_deals_on_clone_from_id"
    t.index ["data_room_folder_id"], name: "index_deals_on_data_room_folder_id"
    t.index ["deal_documents_folder_id"], name: "index_deals_on_deal_documents_folder_id"
    t.index ["deleted_at"], name: "index_deals_on_deleted_at"
    t.index ["document_folder_id"], name: "index_deals_on_document_folder_id"
    t.index ["entity_id"], name: "index_deals_on_entity_id"
    t.index ["form_type_id"], name: "index_deals_on_form_type_id"
    t.index ["slug"], name: "index_deals_on_slug", unique: true
  end

  create_table "devise_api_tokens", force: :cascade do |t|
    t.string "access_token", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.string "previous_refresh_token"
    t.string "refresh_token"
    t.bigint "resource_owner_id", null: false
    t.string "resource_owner_type", null: false
    t.datetime "revoked_at"
    t.datetime "updated_at", null: false
    t.index ["access_token"], name: "index_devise_api_tokens_on_access_token"
    t.index ["previous_refresh_token"], name: "index_devise_api_tokens_on_previous_refresh_token"
    t.index ["refresh_token"], name: "index_devise_api_tokens_on_refresh_token"
    t.index ["resource_owner_type", "resource_owner_id"], name: "index_devise_api_tokens_on_resource_owner"
  end

  create_table "distribution_fees", force: :cascade do |t|
    t.bigint "capital_distribution_id", null: false
    t.datetime "created_at", null: false
    t.date "end_date"
    t.bigint "entity_id", null: false
    t.string "fee_type", limit: 20
    t.boolean "formula", default: false
    t.bigint "fund_id", null: false
    t.string "name", limit: 50
    t.string "notes"
    t.date "start_date"
    t.datetime "updated_at", null: false
    t.index ["capital_distribution_id"], name: "index_distribution_fees_on_capital_distribution_id"
    t.index ["entity_id"], name: "index_distribution_fees_on_entity_id"
    t.index ["fund_id"], name: "index_distribution_fees_on_fund_id"
  end

  create_table "doc_questions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "document_name"
    t.bigint "entity_id", null: false
    t.string "for_class", limit: 25
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.string "qtype", limit: 10
    t.text "question"
    t.string "response_hint"
    t.string "tags", limit: 100
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_doc_questions_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_doc_questions_on_owner"
  end

  create_table "doc_shares", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.string "email", null: false
    t.boolean "email_sent", default: false
    t.datetime "updated_at", null: false
    t.integer "view_count", default: 0
    t.datetime "viewed_at"
    t.index ["document_id"], name: "index_doc_shares_on_document_id"
  end

  create_table "documents", force: :cascade do |t|
    t.boolean "adhaar_esign_completed", default: false
    t.boolean "adhaar_esign_enabled", default: false
    t.boolean "approved", default: false, null: false
    t.bigint "approved_by_id"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "display_on_page", limit: 6
    t.boolean "download", default: false
    t.boolean "embed", default: false
    t.bigint "entity_id", null: false
    t.string "esign_status", default: "", null: false
    t.text "file_data"
    t.bigint "folder_id", null: false
    t.boolean "force_esign_order", default: false
    t.bigint "form_type_id"
    t.bigint "from_template_id"
    t.bigint "import_upload_id"
    t.integer "impressions_count", default: 0
    t.json "json_fields"
    t.datetime "last_status_updated_at"
    t.boolean "locked", default: false, null: false
    t.string "name"
    t.boolean "orignal", default: false
    t.bigint "owner_id"
    t.string "owner_tag", limit: 40
    t.string "owner_type"
    t.boolean "printing", default: false
    t.string "provider_doc_id"
    t.boolean "public_visibility", default: false
    t.text "qna"
    t.boolean "send_email", null: false
    t.boolean "sent_for_esign", default: false, null: false
    t.datetime "sent_for_esign_date"
    t.boolean "signature_enabled", default: false, null: false
    t.string "signature_type", limit: 100
    t.boolean "signed_by_accept", default: false
    t.bigint "signed_by_id"
    t.string "tag_list", limit: 120
    t.boolean "template", default: false
    t.string "template_docs_to_append"
    t.string "text", default: "--- []\n"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "visible_to", default: "--- []\n"
    t.index ["approved_by_id"], name: "index_documents_on_approved_by_id"
    t.index ["deleted_at"], name: "index_documents_on_deleted_at"
    t.index ["entity_id"], name: "index_documents_on_entity_id"
    t.index ["folder_id"], name: "index_documents_on_folder_id"
    t.index ["form_type_id"], name: "index_documents_on_form_type_id"
    t.index ["owner_type", "owner_id"], name: "index_documents_on_owner"
    t.index ["signed_by_id"], name: "index_documents_on_signed_by_id"
    t.index ["user_id"], name: "index_documents_on_user_id"
  end

  create_table "e_signatures", force: :cascade do |t|
    t.text "api_updates"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "document_id"
    t.string "email", limit: 60
    t.bigint "entity_id", null: false
    t.string "label", limit: 50
    t.text "notes"
    t.integer "position"
    t.integer "remind_in", default: 0
    t.string "signature_type", limit: 10
    t.string "signer_id", limit: 20
    t.string "status", default: ""
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["deleted_at"], name: "index_e_signatures_on_deleted_at"
    t.index ["document_id"], name: "index_e_signatures_on_document_id"
    t.index ["entity_id"], name: "index_e_signatures_on_entity_id"
    t.index ["user_id"], name: "index_e_signatures_on_user_id"
  end

  create_table "entities", force: :cascade do |t|
    t.boolean "active", default: true
    t.integer "active_deal_id"
    t.boolean "activity_details_required_for_na", default: false
    t.boolean "activity_docs_required_for_completion", default: false
    t.string "category"
    t.datetime "created_at", null: false
    t.integer "created_by"
    t.string "currency", limit: 10
    t.integer "customization_flags", default: 0
    t.integer "deal_investors_count", default: 0, null: false
    t.integer "deals_count", default: 0, null: false
    t.datetime "deleted_at"
    t.integer "documents_count", default: 0, null: false
    t.string "domain"
    t.string "entity_type", limit: 25
    t.integer "equity", default: 0
    t.date "founded"
    t.string "instrument_types"
    t.integer "investments_count", default: 0, null: false
    t.string "investor_categories"
    t.integer "investors_count", default: 0, null: false
    t.boolean "is_holdings_entity", default: false
    t.text "logo_data"
    t.text "logo_url"
    t.string "name"
    t.integer "options", default: 0
    t.string "pan", limit: 40
    t.integer "parent_entity_id"
    t.integer "pending_accesses_count"
    t.decimal "per_share_value_cents", precision: 15, scale: 2, default: "0.0"
    t.boolean "percentage_in_progress", default: false
    t.bigint "permissions"
    t.integer "preferred", default: 0
    t.string "primary_email"
    t.integer "primary_region_id"
    t.bigint "root_folder_id"
    t.string "s3_bucket"
    t.string "sub_domain"
    t.integer "support_agents", default: 0, null: false
    t.integer "tasks_count"
    t.decimal "total_investments", precision: 20, default: "0"
    t.string "tracking_currency", limit: 4
    t.integer "units", default: 0
    t.datetime "updated_at", null: false
    t.string "url"
    t.boolean "white_label", default: false
    t.index ["deleted_at"], name: "index_entities_on_deleted_at"
    t.index ["name"], name: "index_entities_on_name"
    t.index ["pan"], name: "index_entities_on_pan"
    t.index ["parent_entity_id"], name: "index_entities_on_parent_entity_id"
    t.index ["root_folder_id"], name: "index_entities_on_root_folder_id"
    t.index ["sub_domain"], name: "index_entities_on_sub_domain", unique: true
  end

  create_table "entity_settings", force: :cascade do |t|
    t.boolean "aml_enabled", default: false
    t.string "append_to_commitment_agreement"
    t.boolean "bank_verification"
    t.string "call_basis"
    t.string "cc"
    t.boolean "ckyc_kra_enabled"
    t.datetime "created_at", null: false
    t.text "custom_dashboards"
    t.integer "custom_flags", default: 0
    t.datetime "deleted_at"
    t.string "digio_client_id"
    t.string "digio_client_secret"
    t.datetime "digio_cutover_date"
    t.string "domain"
    t.integer "email_delay_seconds", default: 0
    t.string "entity_bcc"
    t.bigint "entity_id", null: false
    t.string "esign_provider", limit: 15, default: "Digio"
    t.string "fi_code"
    t.string "formula_tag_list"
    t.string "from_email", limit: 100
    t.string "individual_kyc_doc_list"
    t.string "investor_presentations_email", limit: 50
    t.json "kanban_steps"
    t.string "kpi_doc_list"
    t.integer "kpi_reminder_before"
    t.string "kpi_reminder_frequency", limit: 10
    t.string "kyc_bank_account_types"
    t.text "kyc_docs_note"
    t.date "last_snapshot_on"
    t.string "mailbox", limit: 30
    t.string "non_individual_kyc_doc_list"
    t.integer "notification_retention_months", default: 2
    t.boolean "pan_verification"
    t.string "portflio_expense_account_entry_filter"
    t.string "regulatory_env", limit: 20, default: "SEBI"
    t.string "reply_to"
    t.boolean "sandbox"
    t.string "sandbox_emails"
    t.string "sandbox_numbers"
    t.integer "snapshot_frequency_months"
    t.string "stamp_paper_tags"
    t.boolean "test_account", default: false
    t.boolean "trial"
    t.date "trial_end_date"
    t.datetime "updated_at", null: false
    t.string "valuation_math"
    t.string "value_bridge_cols"
    t.string "whatsapp_endpoint"
    t.json "whatsapp_templates"
    t.text "whatsapp_token"
    t.index ["deleted_at"], name: "index_entity_settings_on_deleted_at"
    t.index ["entity_id"], name: "index_entity_settings_on_entity_id"
  end

  create_table "esign_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "document_id"
    t.bigint "entity_id", null: false
    t.json "manual_update_data"
    t.json "request_data"
    t.json "response_data"
    t.datetime "updated_at", null: false
    t.json "webhook_data"
    t.index ["document_id"], name: "index_esign_logs_on_document_id"
    t.index ["entity_id"], name: "index_esign_logs_on_entity_id"
  end

  create_table "events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "end_time", null: false
    t.bigint "entity_id", null: false
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.datetime "start_time", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["entity_id"], name: "index_events_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_events_on_owner"
    t.index ["user_id"], name: "index_events_on_user_id"
  end

  create_table "exception_tracks", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", precision: nil, null: false
    t.string "title"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "exchange_rates", force: :cascade do |t|
    t.date "as_of"
    t.datetime "created_at", null: false
    t.decimal "decimal", precision: 20, scale: 8, default: "0.0"
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.string "from", limit: 5
    t.bigint "import_upload_id"
    t.boolean "latest", default: true
    t.text "notes"
    t.decimal "rate", precision: 20, scale: 8, default: "0.0"
    t.string "to", limit: 5
    t.datetime "updated_at", null: false
    t.index ["document_folder_id"], name: "index_exchange_rates_on_document_folder_id"
    t.index ["entity_id", "from", "to", "as_of"], name: "idx_exchange_rates_entity_from_to_as_of", order: { as_of: :desc }
    t.index ["entity_id"], name: "index_exchange_rates_on_entity_id"
    t.index ["import_upload_id"], name: "index_exchange_rates_on_import_upload_id"
  end

  create_table "excused_investors", force: :cascade do |t|
    t.bigint "aggregate_portfolio_investment_id"
    t.bigint "capital_commitment_id", null: false
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "fund_id", null: false
    t.string "notes"
    t.bigint "portfolio_company_id"
    t.bigint "portfolio_investment_id"
    t.datetime "updated_at", null: false
    t.index ["aggregate_portfolio_investment_id"], name: "index_excused_investors_on_aggregate_portfolio_investment_id"
    t.index ["capital_commitment_id"], name: "index_excused_investors_on_capital_commitment_id"
    t.index ["entity_id"], name: "index_excused_investors_on_entity_id"
    t.index ["fund_id"], name: "index_excused_investors_on_fund_id"
    t.index ["portfolio_company_id"], name: "index_excused_investors_on_portfolio_company_id"
    t.index ["portfolio_investment_id"], name: "index_excused_investors_on_portfolio_investment_id"
  end

  create_table "expression_of_interests", force: :cascade do |t|
    t.decimal "allocation_amount_cents", precision: 15, scale: 2, default: "0.0"
    t.decimal "allocation_percentage", precision: 5, scale: 2, default: "0.0"
    t.decimal "amount_cents", precision: 15, scale: 2, default: "0.0"
    t.boolean "approved", default: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.bigint "eoi_entity_id", null: false
    t.boolean "esign_completed", default: false
    t.boolean "esign_required", default: false
    t.bigint "form_type_id"
    t.bigint "investment_opportunity_id", null: false
    t.string "investor_email"
    t.bigint "investor_id", null: false
    t.bigint "investor_kyc_id"
    t.string "investor_name", limit: 100
    t.bigint "investor_signatory_id"
    t.json "json_fields"
    t.boolean "show_data_room", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.boolean "verified", default: false
    t.index ["document_folder_id"], name: "index_expression_of_interests_on_document_folder_id"
    t.index ["entity_id"], name: "index_expression_of_interests_on_entity_id"
    t.index ["eoi_entity_id"], name: "index_expression_of_interests_on_eoi_entity_id"
    t.index ["form_type_id"], name: "index_expression_of_interests_on_form_type_id"
    t.index ["investment_opportunity_id"], name: "index_expression_of_interests_on_investment_opportunity_id"
    t.index ["investor_id"], name: "index_expression_of_interests_on_investor_id"
    t.index ["investor_kyc_id"], name: "index_expression_of_interests_on_investor_kyc_id"
    t.index ["investor_signatory_id"], name: "index_expression_of_interests_on_investor_signatory_id"
    t.index ["user_id"], name: "index_expression_of_interests_on_user_id"
  end

  create_table "faq_threads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "messages"
    t.string "openai_thread_id"
    t.string "title", default: "New Support Chat"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_faq_threads_on_user_id"
  end

  create_table "favorites", force: :cascade do |t|
    t.boolean "blocked", default: false, null: false
    t.datetime "created_at", null: false
    t.bigint "favoritable_id", null: false
    t.string "favoritable_type", null: false
    t.bigint "favoritor_id", null: false
    t.string "favoritor_type", null: false
    t.string "scope", default: "favorite", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked"], name: "index_favorites_on_blocked"
    t.index ["favoritable_id", "favoritable_type"], name: "fk_favoritables"
    t.index ["favoritable_type", "favoritable_id", "favoritor_id", "scope"], name: "uniq_favs_and_favoritables", unique: true
    t.index ["favoritable_type", "favoritable_id"], name: "index_favorites_on_favoritable"
    t.index ["favoritor_id", "favoritor_type"], name: "fk_favorites"
    t.index ["favoritor_type", "favoritor_id"], name: "index_favorites_on_favoritor"
    t.index ["scope"], name: "index_favorites_on_scope"
  end

  create_table "fees", force: :cascade do |t|
    t.string "advisor_name", limit: 30
    t.decimal "amount_cents", precision: 10, scale: 2, default: "0.0"
    t.string "amount_label", limit: 10
    t.string "bank_account_number", limit: 40
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.string "ifsc_code", limit: 20
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_fees_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_fees_on_owner"
  end

  create_table "folders", force: :cascade do |t|
    t.string "ancestry"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.integer "documents_count", default: 0, null: false
    t.boolean "download", default: false
    t.bigint "entity_id", null: false
    t.integer "folder_type", default: 0
    t.string "full_path"
    t.boolean "knowledge_base", default: false
    t.integer "level"
    t.string "name"
    t.boolean "orignal", default: false
    t.bigint "owner_id"
    t.string "owner_type"
    t.boolean "printing", default: false
    t.boolean "private", default: false
    t.datetime "updated_at", null: false
    t.index ["ancestry"], name: "index_folders_on_ancestry"
    t.index ["deleted_at"], name: "index_folders_on_deleted_at"
    t.index ["entity_id"], name: "index_folders_on_entity_id"
    t.index ["full_path", "owner_id", "owner_type", "entity_id", "deleted_at"], name: "index_folders_on_full_path_and_owner_entity_with_deleted_at", unique: true
    t.index ["owner_type", "owner_id"], name: "index_folders_on_owner"
  end

  create_table "form_custom_fields", force: :cascade do |t|
    t.string "condition_criteria", limit: 10, default: "eq"
    t.string "condition_on"
    t.string "condition_params"
    t.string "condition_state", limit: 5, default: "show"
    t.datetime "created_at", null: false
    t.string "field_type", limit: 20
    t.bigint "form_type_id", null: false
    t.boolean "has_attachment", default: false
    t.text "help_text"
    t.integer "import_upload_id", comment: "ID of the import upload that created or updated this form custom field"
    t.boolean "internal", default: false
    t.string "js_events"
    t.string "label"
    t.text "meta_data"
    t.string "name", limit: 100
    t.integer "position"
    t.boolean "read_only", default: false
    t.string "reg_env", limit: 15
    t.text "regulation_type"
    t.boolean "regulatory_field", default: false
    t.boolean "required"
    t.string "show_user_ids", limit: 50
    t.integer "step", default: 100
    t.datetime "updated_at", null: false
    t.index ["form_type_id"], name: "index_form_custom_fields_on_form_type_id"
    t.index ["import_upload_id"], name: "index_form_custom_fields_on_import_upload_id"
    t.index ["name", "form_type_id"], name: "index_form_custom_fields_on_name_and_form_type_id", unique: true
  end

  create_table "form_types", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.string "name"
    t.string "tag", limit: 50, default: "Default", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_form_types_on_entity_id"
  end

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.datetime "created_at"
    t.string "scope"
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true, length: { slug: 70, scope: 70 }
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type", length: { slug: 140 }
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "fund_formulas", force: :cascade do |t|
    t.boolean "add_to_commitment_cache", default: true, null: false
    t.text "ai_description"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.boolean "enabled", default: false
    t.bigint "entity_id"
    t.string "entry_type", limit: 60
    t.integer "execution_time"
    t.boolean "explain", default: true
    t.text "formula"
    t.bigint "fund_id"
    t.boolean "generate_ytd_qtly", default: false
    t.integer "import_upload_id"
    t.boolean "is_template", default: false
    t.text "meta_data"
    t.string "name", limit: 125
    t.boolean "roll_up", default: false
    t.string "rule_for", limit: 10, default: "Accounting"
    t.string "rule_type", limit: 50
    t.integer "sequence", default: 0
    t.string "tag_list"
    t.json "timing"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_fund_formulas_on_deleted_at"
    t.index ["entity_id"], name: "index_fund_formulas_on_entity_id"
    t.index ["fund_id"], name: "index_fund_formulas_on_fund_id"
  end

  create_table "fund_ratios", force: :cascade do |t|
    t.bigint "capital_commitment_id"
    t.json "cash_flows"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "display_value", limit: 50
    t.date "end_date"
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.bigint "fund_id", null: false
    t.bigint "import_upload_id"
    t.string "label", limit: 50
    t.boolean "latest", default: false
    t.string "name"
    t.text "notes"
    t.bigint "owner_id"
    t.string "owner_type"
    t.bigint "portfolio_scenario_id"
    t.string "scenario", limit: 40, default: "Default"
    t.datetime "updated_at", null: false
    t.bigint "valuation_id"
    t.decimal "value", precision: 20, scale: 8, default: "0.0"
    t.index ["capital_commitment_id"], name: "index_fund_ratios_on_capital_commitment_id"
    t.index ["deleted_at"], name: "index_fund_ratios_on_deleted_at"
    t.index ["entity_id"], name: "index_fund_ratios_on_entity_id"
    t.index ["form_type_id"], name: "index_fund_ratios_on_form_type_id"
    t.index ["fund_id"], name: "index_fund_ratios_on_fund_id"
    t.index ["owner_type", "owner_id"], name: "index_fund_ratios_on_owner"
    t.index ["portfolio_scenario_id"], name: "index_fund_ratios_on_portfolio_scenario_id"
    t.index ["valuation_id"], name: "index_fund_ratios_on_valuation_id"
  end

  create_table "fund_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.date "end_date"
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.bigint "fund_id", null: false
    t.string "name", limit: 50
    t.string "name_of_scheme"
    t.date "start_date"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_fund_reports_on_entity_id"
    t.index ["form_type_id"], name: "index_fund_reports_on_form_type_id"
    t.index ["fund_id"], name: "index_fund_reports_on_fund_id"
  end

  create_table "fund_sebi_infos", force: :cascade do |t|
    t.decimal "amount_invested_in_offshore", precision: 15, scale: 2
    t.string "any_extension_of_term_permitted", limit: 3
    t.decimal "cash_in_hand_till_eoq", precision: 20, scale: 2
    t.datetime "created_at", null: false
    t.string "details_of_security"
    t.date "end_date_of_extended_term"
    t.date "end_date_of_initial_term"
    t.bigint "entity_id", null: false
    t.decimal "estimated_expenses", precision: 20, scale: 2
    t.date "final_close_date"
    t.date "final_draft_ppm_date"
    t.string "fully_liquidated_before_liquidation_end", limit: 3
    t.bigint "fund_id", null: false
    t.decimal "in_specie_bid_arranged_for", precision: 20, scale: 2
    t.decimal "in_specie_bid_received_value", precision: 20, scale: 2
    t.string "in_specie_distribution_consent", limit: 3
    t.date "in_specie_distribution_date"
    t.date "in_specie_distribution_winding_up_date"
    t.string "in_specie_scheme_name", limit: 100
    t.decimal "in_specie_unliquidated_investments_cost", precision: 20, scale: 2
    t.decimal "in_specie_valuer_1_value", precision: 20, scale: 2
    t.decimal "in_specie_valuer_2_value", precision: 20, scale: 2
    t.date "initial_close_date"
    t.string "investee_company_name"
    t.string "is_associate"
    t.string "is_managed_or_sponsored_by_aif"
    t.string "isin"
    t.date "launch_date"
    t.string "liquidation_scheme", limit: 3
    t.decimal "liquidation_scheme_bid_arranged_for", precision: 20, scale: 2
    t.decimal "liquidation_scheme_bid_received_value", precision: 20, scale: 2
    t.date "liquidation_scheme_end_date"
    t.string "liquidation_scheme_launch_consent", limit: 3
    t.date "liquidation_scheme_launch_date"
    t.date "liquidation_scheme_ppm_date"
    t.integer "liquidation_scheme_tenure"
    t.decimal "liquidation_scheme_unliquidated_investments_cost", precision: 20, scale: 2
    t.decimal "liquidation_scheme_valuer_1_value", precision: 20, scale: 2
    t.decimal "liquidation_scheme_valuer_2_value", precision: 20, scale: 2
    t.string "mandatory_in_specie_distribution", limit: 3
    t.date "mdtin_specie_distribution_winding_up_date"
    t.integer "mdtin_specie_no_of_investors_accepted"
    t.integer "mdtin_specie_no_of_investors_not_accepted"
    t.decimal "mdtin_specie_unliquidated_investments_cost", precision: 20, scale: 2
    t.string "name_of_liquidation_scheme", limit: 100
    t.string "name_of_original_scheme", limit: 100
    t.string "offshore_investment"
    t.date "original_scheme_winding_up_date"
    t.string "pan"
    t.date "scheme_winding_up_date"
    t.date "sebi_intimation_date_of_winding_up"
    t.date "sebi_ppm_communication_date"
    t.string "sebi_registration_number"
    t.string "sector"
    t.decimal "temporary_investments_made_till_eoq", precision: 20, scale: 2
    t.integer "tenure"
    t.decimal "total_commitment_received", precision: 20, scale: 2
    t.string "type_of_investee_company"
    t.string "type_of_security"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_fund_sebi_infos_on_entity_id"
    t.index ["fund_id"], name: "index_fund_sebi_infos_on_fund_id"
  end

  create_table "fund_unit_settings", force: :cascade do |t|
    t.decimal "carry", precision: 24, scale: 8, default: "0.0"
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.bigint "fund_id", null: false
    t.boolean "gp_units", default: false
    t.bigint "import_upload_id"
    t.string "isin", limit: 15
    t.json "json_fields"
    t.decimal "management_fee", precision: 24, scale: 8, default: "0.0"
    t.string "name", limit: 40
    t.text "notes"
    t.decimal "setup_fee", precision: 24, scale: 8, default: "0.0"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_fund_unit_settings_on_entity_id"
    t.index ["form_type_id"], name: "index_fund_unit_settings_on_form_type_id"
    t.index ["fund_id"], name: "index_fund_unit_settings_on_fund_id"
  end

  create_table "fund_unit_transfers", force: :cascade do |t|
    t.string "account_entries_excluded"
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "from_commitment_id", null: false
    t.bigint "fund_id", null: false
    t.decimal "premium", precision: 20, scale: 2
    t.decimal "price", precision: 20, scale: 2
    t.string "status"
    t.bigint "to_commitment_id", null: false
    t.boolean "transfer_account_entries"
    t.date "transfer_date"
    t.integer "transfer_ratio"
    t.string "transfer_token"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_fund_unit_transfers_on_entity_id"
    t.index ["from_commitment_id"], name: "index_fund_unit_transfers_on_from_commitment_id"
    t.index ["fund_id"], name: "index_fund_unit_transfers_on_fund_id"
    t.index ["to_commitment_id"], name: "index_fund_unit_transfers_on_to_commitment_id"
  end

  create_table "fund_units", force: :cascade do |t|
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "capital_commitment_id", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "entity_id", null: false
    t.bigint "fund_id", null: false
    t.boolean "gp_units", default: false
    t.bigint "import_upload_id"
    t.bigint "investor_id", null: false
    t.date "issue_date"
    t.bigint "owner_id"
    t.string "owner_type"
    t.decimal "premium_cents", precision: 20, scale: 2, default: "0.0", null: false
    t.decimal "premium_old", precision: 20, scale: 2, default: "0.0"
    t.decimal "price_cents", precision: 20, scale: 2, default: "0.0", null: false
    t.decimal "price_old", precision: 20, scale: 2, default: "0.0"
    t.decimal "quantity", precision: 26, scale: 8, default: "0.0", null: false
    t.text "reason"
    t.decimal "total_premium_cents", precision: 20, scale: 2, default: "0.0"
    t.string "transfer", limit: 8
    t.string "unit_type", limit: 40
    t.datetime "updated_at", null: false
    t.index ["capital_commitment_id"], name: "index_fund_units_on_capital_commitment_id"
    t.index ["deleted_at"], name: "index_fund_units_on_deleted_at"
    t.index ["entity_id"], name: "index_fund_units_on_entity_id"
    t.index ["fund_id"], name: "index_fund_units_on_fund_id"
    t.index ["investor_id"], name: "index_fund_units_on_investor_id"
    t.index ["owner_type", "owner_id"], name: "index_fund_units_on_owner"
  end

  create_table "funding_rounds", force: :cascade do |t|
    t.decimal "amount_raised_cents", precision: 20, scale: 2, default: "0.0"
    t.string "anti_dilution", limit: 50
    t.date "closed_on"
    t.datetime "created_at", null: false
    t.string "currency", limit: 5
    t.datetime "deleted_at"
    t.bigint "entity_id", null: false
    t.integer "equity", default: 0
    t.string "liq_pref_type", limit: 25
    t.string "name"
    t.integer "options", default: 0
    t.decimal "post_money_valuation_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "pre_money_valuation_cents", precision: 20, scale: 2, default: "0.0"
    t.integer "preferred", default: 0
    t.decimal "price_cents", precision: 20, scale: 2, default: "0.0"
    t.string "status", default: "Open"
    t.decimal "total_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.integer "units", default: 0
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_funding_rounds_on_deleted_at"
    t.index ["entity_id"], name: "index_funding_rounds_on_entity_id"
  end

  create_table "funds", force: :cascade do |t|
    t.decimal "call_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.integer "capital_commitments_count", default: 0, null: false
    t.decimal "capital_fee_cents", precision: 20, scale: 2, default: "0.0"
    t.string "category", limit: 15
    t.decimal "collected_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.string "commitment_doc_list", limit: 100
    t.decimal "committed_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.string "currency", limit: 5, null: false
    t.bigint "data_room_folder_id"
    t.datetime "deleted_at"
    t.text "details"
    t.decimal "distribution_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "document_folder_id"
    t.boolean "editable_formulas", default: false
    t.bigint "entity_id", null: false
    t.string "esign_emails"
    t.date "first_close_date"
    t.bigint "form_type_id"
    t.bigint "fund_signatory_id"
    t.string "fund_signature_types", limit: 20
    t.bigint "funding_round_id"
    t.bigint "import_upload_id"
    t.string "investor_signature_types", limit: 20
    t.json "json_fields"
    t.date "last_close_date"
    t.bigint "master_fund_id"
    t.string "name"
    t.bigint "orignal_id"
    t.decimal "other_fee_cents", precision: 20, scale: 2, default: "0.0"
    t.integer "permissions", default: 0, null: false
    t.string "portfolio_cost_type", limit: 10, default: "FIFO", null: false
    t.string "regulatory_env"
    t.boolean "show_fund_ratios", default: false
    t.boolean "show_portfolios", default: false
    t.boolean "show_valuations", default: false
    t.string "slug"
    t.boolean "snapshot", default: false
    t.date "snapshot_date"
    t.date "start_date"
    t.string "tag_list"
    t.decimal "target_committed_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "total_units_premium_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "tracking_call_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.decimal "tracking_co_invest_call_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.decimal "tracking_collected_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.decimal "tracking_committed_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.string "tracking_currency", limit: 3
    t.decimal "tracking_distribution_amount_cents", precision: 20, scale: 4, default: "0.0"
    t.bigint "trustee_signatory_id"
    t.string "unit_types"
    t.string "units_allocation_engine", limit: 50
    t.datetime "updated_at", null: false
    t.index ["data_room_folder_id"], name: "index_funds_on_data_room_folder_id"
    t.index ["deleted_at"], name: "index_funds_on_deleted_at"
    t.index ["document_folder_id"], name: "index_funds_on_document_folder_id"
    t.index ["entity_id"], name: "index_funds_on_entity_id"
    t.index ["form_type_id"], name: "index_funds_on_form_type_id"
    t.index ["fund_signatory_id"], name: "index_funds_on_fund_signatory_id"
    t.index ["funding_round_id"], name: "index_funds_on_funding_round_id"
    t.index ["import_upload_id"], name: "index_funds_on_import_upload_id"
    t.index ["master_fund_id"], name: "index_funds_on_master_fund_id"
    t.index ["slug"], name: "index_funds_on_slug", unique: true
    t.index ["snapshot_date"], name: "index_funds_on_snapshot_date"
    t.index ["trustee_signatory_id"], name: "index_funds_on_trustee_signatory_id"
  end

  create_table "grid_view_preferences", force: :cascade do |t|
    t.string "alignment", limit: 12
    t.datetime "created_at", null: false
    t.bigint "custom_grid_view_id"
    t.string "data_type"
    t.boolean "derived_field"
    t.bigint "entity_id", null: false
    t.string "key"
    t.string "label"
    t.string "name"
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.boolean "selected"
    t.integer "sequence"
    t.datetime "updated_at", null: false
    t.index ["custom_grid_view_id", "sequence"], name: "idx_on_custom_grid_view_id_sequence_ef881fc72b"
    t.index ["custom_grid_view_id"], name: "index_grid_view_preferences_on_custom_grid_view_id"
    t.index ["entity_id"], name: "index_grid_view_preferences_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_grid_view_preferences_on_owner"
  end

  create_table "import_uploads", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "custom_fields_created"
    t.bigint "entity_id", null: false
    t.text "error_text"
    t.integer "failed_row_count", default: 0
    t.text "import_file_data"
    t.text "import_results_data"
    t.string "import_type", limit: 50
    t.string "name"
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.integer "processed_row_count", default: 0
    t.text "status"
    t.integer "total_rows_count", default: 0
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["entity_id"], name: "index_import_uploads_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_import_uploads_on_owner"
    t.index ["user_id"], name: "index_import_uploads_on_user_id"
  end

  create_table "incoming_emails", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.bigint "document_folder_id"
    t.bigint "entity_id"
    t.string "from"
    t.bigint "owner_id"
    t.string "owner_type"
    t.string "subject"
    t.string "to"
    t.datetime "updated_at", null: false
    t.index ["document_folder_id"], name: "index_incoming_emails_on_document_folder_id"
    t.index ["entity_id"], name: "index_incoming_emails_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_incoming_emails_on_owner"
  end

  create_table "interests", force: :cascade do |t|
    t.string "PAN", limit: 15
    t.text "address"
    t.decimal "allocation_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "allocation_percentage", precision: 5, scale: 2, default: "0.0"
    t.bigint "allocation_quantity", default: 0
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.string "bank_account_number", limit: 40
    t.text "bank_verification_response"
    t.string "bank_verification_status"
    t.boolean "bank_verified"
    t.string "buyer_entity_name", limit: 100
    t.string "buyer_signatory_emails"
    t.string "city", limit: 20
    t.text "comments"
    t.boolean "completed", default: false
    t.string "contact_name", limit: 50
    t.datetime "created_at", null: false
    t.string "custom_matching_vals"
    t.datetime "deleted_at"
    t.string "demat", limit: 20
    t.bigint "document_folder_id"
    t.string "email"
    t.integer "entity_id"
    t.boolean "escrow_deposited", default: false
    t.boolean "final_agreement", default: false
    t.bigint "final_agreement_user_id"
    t.decimal "final_price", precision: 10, scale: 2, default: "0.0"
    t.boolean "finalized", default: false
    t.bigint "form_type_id"
    t.bigint "funding_round_id"
    t.string "ifsc_code", limit: 20
    t.bigint "import_upload_id"
    t.integer "interest_entity_id"
    t.bigint "investor_id"
    t.json "json_fields"
    t.integer "offer_quantity", default: 0
    t.text "pan_verification_response"
    t.string "pan_verification_status"
    t.boolean "pan_verified"
    t.decimal "price", precision: 10
    t.integer "quantity"
    t.bigint "secondary_sale_id", null: false
    t.string "short_listed_status", default: "pending", null: false
    t.text "signature_data"
    t.text "spa_data"
    t.datetime "status_updated_at"
    t.bigint "status_updated_by_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.boolean "verified", default: false
    t.index ["custom_matching_vals"], name: "index_interests_on_custom_matching_vals"
    t.index ["deleted_at"], name: "index_interests_on_deleted_at"
    t.index ["document_folder_id"], name: "index_interests_on_document_folder_id"
    t.index ["entity_id"], name: "index_interests_on_entity_id"
    t.index ["final_agreement_user_id"], name: "index_interests_on_final_agreement_user_id"
    t.index ["form_type_id"], name: "index_interests_on_form_type_id"
    t.index ["funding_round_id"], name: "index_interests_on_funding_round_id"
    t.index ["import_upload_id"], name: "index_interests_on_import_upload_id"
    t.index ["interest_entity_id"], name: "index_interests_on_interest_entity_id"
    t.index ["investor_id"], name: "index_interests_on_investor_id"
    t.index ["secondary_sale_id"], name: "index_interests_on_secondary_sale_id"
    t.index ["status_updated_by_id"], name: "index_interests_on_status_updated_by_id"
    t.index ["user_id"], name: "index_interests_on_user_id"
  end

  create_table "investment_criteria_templates", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id", null: false
    t.json "criteria", null: false
    t.bigint "entity_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0, null: false
    t.index ["created_by_user_id", "usage_count"], name: "index_investment_criteria_templates_on_user_and_usage"
    t.index ["created_by_user_id"], name: "index_investment_criteria_templates_on_created_by_user_id"
    t.index ["entity_id", "usage_count"], name: "index_investment_criteria_templates_on_entity_and_usage"
    t.index ["entity_id"], name: "index_investment_criteria_templates_on_entity_id"
  end

  create_table "investment_instruments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "category", limit: 15
    t.datetime "created_at", null: false
    t.string "currency", limit: 5
    t.datetime "deleted_at"
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.bigint "import_upload_id"
    t.string "investment_domicile", limit: 15
    t.json "json_fields"
    t.string "name"
    t.bigint "portfolio_company_id", null: false
    t.string "sector", limit: 100
    t.boolean "startup", default: false
    t.string "sub_category", limit: 100
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_investment_instruments_on_deleted_at"
    t.index ["entity_id"], name: "index_investment_instruments_on_entity_id"
    t.index ["form_type_id"], name: "index_investment_instruments_on_form_type_id"
    t.index ["portfolio_company_id"], name: "index_investment_instruments_on_portfolio_company_id"
  end

  create_table "investment_opportunities", force: :cascade do |t|
    t.text "buyer_docs_list"
    t.string "company_name", limit: 100
    t.datetime "created_at", null: false
    t.string "currency", limit: 10
    t.bigint "data_room_folder_id"
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.decimal "eoi_amount_cents", precision: 15, scale: 2, default: "0.0"
    t.bigint "form_type_id"
    t.decimal "fund_raise_amount_cents", precision: 15, scale: 2, default: "0.0"
    t.bigint "funding_round_id"
    t.json "json_fields"
    t.date "last_date"
    t.boolean "lock_allocations", default: false
    t.boolean "lock_eoi", default: false
    t.text "logo_data"
    t.decimal "min_ticket_size_cents", precision: 15, scale: 2, default: "0.0"
    t.boolean "shareable", default: false
    t.string "tag_list", limit: 120
    t.datetime "updated_at", null: false
    t.decimal "valuation_cents", precision: 15, scale: 2, default: "0.0"
    t.text "video_data"
    t.index ["data_room_folder_id"], name: "index_investment_opportunities_on_data_room_folder_id"
    t.index ["document_folder_id"], name: "index_investment_opportunities_on_document_folder_id"
    t.index ["entity_id"], name: "index_investment_opportunities_on_entity_id"
    t.index ["form_type_id"], name: "index_investment_opportunities_on_form_type_id"
    t.index ["funding_round_id"], name: "index_investment_opportunities_on_funding_round_id"
  end

  create_table "investments", force: :cascade do |t|
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.string "category", limit: 10
    t.datetime "created_at", null: false
    t.string "currency", limit: 3
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.string "funding_round", limit: 40
    t.integer "import_upload_id"
    t.string "instrument_name", limit: 50
    t.decimal "instrument_quantity", precision: 10, scale: 2
    t.date "investment_date"
    t.string "investment_type", limit: 15
    t.string "investor_name"
    t.json "json_fields"
    t.text "notes"
    t.bigint "portfolio_company_id", null: false
    t.decimal "price_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "quantity", precision: 10
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_investments_on_entity_id"
    t.index ["form_type_id"], name: "index_investments_on_form_type_id"
    t.index ["portfolio_company_id"], name: "index_investments_on_portfolio_company_id"
  end

  create_table "investor_accesses", force: :cascade do |t|
    t.boolean "approved"
    t.string "call_code", limit: 3
    t.text "cc"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email"
    t.boolean "email_enabled", default: true
    t.integer "entity_id"
    t.string "first_name", limit: 20
    t.integer "granted_by"
    t.bigint "import_upload_id"
    t.bigint "investor_entity_id"
    t.integer "investor_id"
    t.boolean "is_investor_advisor", default: false
    t.string "last_name", limit: 20
    t.string "phone", limit: 15
    t.boolean "send_confirmation", default: false
    t.string "tags", limit: 50
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.boolean "whatsapp_enabled", default: false
    t.index ["deleted_at"], name: "index_investor_accesses_on_deleted_at"
    t.index ["email"], name: "index_investor_accesses_on_email"
    t.index ["entity_id"], name: "index_investor_accesses_on_entity_id"
    t.index ["investor_entity_id"], name: "index_investor_accesses_on_investor_entity_id"
    t.index ["investor_id"], name: "index_investor_accesses_on_investor_id"
    t.index ["user_id"], name: "index_investor_accesses_on_user_id"
  end

  create_table "investor_advisors", force: :cascade do |t|
    t.string "allowed_roles", limit: 100
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.datetime "deleted_at"
    t.string "email"
    t.bigint "entity_id", null: false
    t.integer "extended_permissions"
    t.bigint "import_upload_id"
    t.bigint "permissions", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_by_id"], name: "index_investor_advisors_on_created_by_id"
    t.index ["deleted_at"], name: "index_investor_advisors_on_deleted_at"
    t.index ["entity_id"], name: "index_investor_advisors_on_entity_id"
    t.index ["user_id"], name: "index_investor_advisors_on_user_id"
  end

  create_table "investor_kpi_mappings", force: :cascade do |t|
    t.string "ancestry", collation: "NOCASE"
    t.boolean "base_for_common_size", default: false, null: false
    t.string "category", limit: 40
    t.integer "child_count", default: 0
    t.datetime "created_at", null: false
    t.boolean "cumulate", default: false
    t.string "data_type", limit: 10, default: "numeric"
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.bigint "import_upload_id"
    t.bigint "investor_id", null: false
    t.json "json_fields"
    t.decimal "lower_threshold", precision: 20, scale: 2, default: "0.0"
    t.integer "position", default: 0
    t.json "rag_rules"
    t.string "reported_kpi_name", limit: 100
    t.boolean "show_in_report", default: false
    t.string "standard_kpi_name", limit: 100
    t.datetime "updated_at", null: false
    t.decimal "upper_threshold", precision: 20, scale: 2, default: "0.0"
    t.index ["ancestry"], name: "index_investor_kpi_mappings_on_ancestry"
    t.index ["entity_id"], name: "index_investor_kpi_mappings_on_entity_id"
    t.index ["form_type_id"], name: "index_investor_kpi_mappings_on_form_type_id"
    t.index ["investor_id"], name: "index_investor_kpi_mappings_on_investor_id"
    t.index ["reported_kpi_name"], name: "index_investor_kpi_mappings_on_reported_kpi_name"
    t.index ["standard_kpi_name"], name: "index_investor_kpi_mappings_on_standard_kpi_name"
  end

  create_table "investor_kycs", force: :cascade do |t|
    t.string "PAN", limit: 15
    t.text "address"
    t.decimal "agreement_committed_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.string "agreement_unit_type", limit: 20
    t.boolean "all_docs_valid", default: false
    t.string "aml_status"
    t.string "bank_account_number", limit: 40
    t.string "bank_account_type", limit: 40
    t.string "bank_branch"
    t.string "bank_name", limit: 100
    t.text "bank_verification_response"
    t.string "bank_verification_status"
    t.boolean "bank_verified", default: false
    t.datetime "birth_date"
    t.decimal "call_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "collected_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.text "comments"
    t.decimal "committed_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.boolean "completed_by_investor", default: false
    t.boolean "compliant", default: false
    t.text "corr_address"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.decimal "distribution_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.json "doc_question_answers"
    t.boolean "docs_completed", default: false
    t.bigint "document_folder_id"
    t.decimal "due_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "entity_id", null: false
    t.string "esign_emails"
    t.date "expiry_date"
    t.bigint "form_type_id"
    t.string "full_name"
    t.string "ifsc_code", limit: 20
    t.bigint "import_upload_id"
    t.bigint "investor_id", null: false
    t.string "investor_name"
    t.bigint "investor_user_id"
    t.datetime "investor_user_updated_at"
    t.json "json_fields"
    t.string "kyc_type", limit: 15, default: "Individual"
    t.text "notification_msg"
    t.decimal "other_fee_cents", precision: 12, scale: 2, default: "0.0"
    t.text "pan_card_data"
    t.text "pan_verification_response"
    t.string "pan_verification_status"
    t.boolean "pan_verified", default: false
    t.boolean "reminder_sent", default: false
    t.datetime "reminder_sent_date"
    t.string "residency", limit: 10
    t.boolean "send_kyc_form_to_user", default: false
    t.text "signature_data"
    t.string "slug"
    t.string "type", limit: 20
    t.decimal "uncalled_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false
    t.bigint "verified_by_id"
    t.index ["deleted_at"], name: "index_investor_kycs_on_deleted_at"
    t.index ["document_folder_id"], name: "index_investor_kycs_on_document_folder_id"
    t.index ["entity_id"], name: "index_investor_kycs_on_entity_id"
    t.index ["form_type_id"], name: "index_investor_kycs_on_form_type_id"
    t.index ["investor_id"], name: "index_investor_kycs_on_investor_id"
    t.index ["investor_user_id"], name: "index_investor_kycs_on_investor_user_id"
    t.index ["slug"], name: "index_investor_kycs_on_slug", unique: true
    t.index ["verified_by_id"], name: "index_investor_kycs_on_verified_by_id"
  end

  create_table "investor_notice_entries", force: :cascade do |t|
    t.boolean "active", default: false
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "investor_entity_id", null: false
    t.bigint "investor_id", null: false
    t.bigint "investor_notice_id", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_investor_notice_entries_on_entity_id"
    t.index ["investor_entity_id"], name: "index_investor_notice_entries_on_investor_entity_id"
    t.index ["investor_id"], name: "index_investor_notice_entries_on_investor_id"
    t.index ["investor_notice_id"], name: "index_investor_notice_entries_on_investor_notice_id"
  end

  create_table "investor_notice_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "details"
    t.bigint "entity_id", null: false
    t.bigint "investor_notice_id", null: false
    t.string "link"
    t.integer "position"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_investor_notice_items_on_entity_id"
    t.index ["investor_notice_id"], name: "index_investor_notice_items_on_investor_notice_id"
  end

  create_table "investor_notices", force: :cascade do |t|
    t.string "access_rights_metadata"
    t.boolean "active", default: false
    t.string "btn_label", limit: 40
    t.string "category", limit: 30
    t.datetime "created_at", null: false
    t.date "end_date"
    t.bigint "entity_id", null: false
    t.boolean "generate", default: false
    t.string "link"
    t.bigint "owner_id"
    t.string "owner_type"
    t.date "start_date"
    t.text "title"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_investor_notices_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_investor_notices_on_owner"
  end

  create_table "investors", force: :cascade do |t|
    t.string "category", limit: 100
    t.string "city", limit: 50
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "document_folder_id"
    t.integer "entity_id", null: false
    t.bigint "form_type_id"
    t.bigint "import_upload_id"
    t.boolean "imported", default: false
    t.integer "investor_access_count", default: 0
    t.integer "investor_entity_id", null: false
    t.string "investor_name"
    t.boolean "is_holdings_entity", default: false
    t.boolean "is_trust", default: false
    t.json "json_fields"
    t.date "last_interaction_date"
    t.string "pan", limit: 40
    t.string "primary_email"
    t.string "slug"
    t.string "tag_list", limit: 120
    t.integer "unapproved_investor_access_count", default: 0
    t.datetime "updated_at", null: false
    t.integer "will_receive_email", default: 0, null: false
    t.string "sector"
    t.index ["deleted_at"], name: "index_investors_on_deleted_at"
    t.index ["document_folder_id"], name: "index_investors_on_document_folder_id"
    t.index ["entity_id"], name: "index_investors_on_entity_id"
    t.index ["form_type_id"], name: "index_investors_on_form_type_id"
    t.index ["investor_entity_id", "entity_id", "deleted_at"], name: "idx_on_investor_entity_id_entity_id_deleted_at_983d7c8e7a", unique: true
    t.index ["investor_entity_id"], name: "index_investors_on_investor_entity_id"
    t.index ["investor_name", "entity_id"], name: "index_investors_on_investor_name_and_entity_id", unique: true
    t.index ["pan"], name: "index_investors_on_pan"
    t.index ["slug"], name: "index_investors_on_slug", unique: true
    t.index ["tag_list"], name: "index_investors_on_tag_list"
  end

  create_table "kanban_boards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "entity_id", null: false
    t.string "name"
    t.integer "owner_id"
    t.string "owner_type"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_kanban_boards_on_entity_id"
    t.index ["owner_id", "owner_type"], name: "index_kanban_boards_on_owner_id_and_owner_type"
  end

  create_table "kanban_cards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "data_source_id"
    t.string "data_source_type"
    t.datetime "deleted_at"
    t.bigint "entity_id", null: false
    t.string "info_field"
    t.bigint "kanban_board_id", null: false
    t.bigint "kanban_column_id", null: false
    t.text "notes"
    t.integer "sequence"
    t.string "tags"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_kanban_cards_on_entity_id"
    t.index ["kanban_board_id"], name: "index_kanban_cards_on_kanban_board_id"
    t.index ["kanban_column_id"], name: "index_kanban_cards_on_kanban_column_id"
    t.index ["sequence"], name: "index_kanban_cards_on_sequence"
  end

  create_table "kanban_columns", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "entity_id", null: false
    t.bigint "kanban_board_id", null: false
    t.string "name"
    t.integer "sequence"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_kanban_columns_on_entity_id"
    t.index ["kanban_board_id"], name: "index_kanban_columns_on_kanban_board_id"
  end

  create_table "key_biz_metrics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_value"
    t.string "metric_type"
    t.string "name"
    t.string "notes"
    t.text "query"
    t.datetime "run_date"
    t.datetime "updated_at", null: false
    t.decimal "value", precision: 20, scale: 2, default: "0.0"
  end

  create_table "kpi_reports", force: :cascade do |t|
    t.text "analysis"
    t.date "as_of"
    t.datetime "created_at", null: false
    t.boolean "cumulation_completed", default: false, null: false
    t.datetime "deleted_at"
    t.bigint "document_folder_id"
    t.boolean "enable_portco_upload", default: false, null: false
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.bigint "import_upload_id"
    t.json "json_fields"
    t.text "notes"
    t.bigint "owner_id"
    t.string "period", limit: 12, default: "Quarter"
    t.bigint "portfolio_company_id"
    t.string "tag_list", default: "Actual"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["deleted_at"], name: "index_kpi_reports_on_deleted_at"
    t.index ["document_folder_id"], name: "index_kpi_reports_on_document_folder_id"
    t.index ["entity_id"], name: "index_kpi_reports_on_entity_id"
    t.index ["form_type_id"], name: "index_kpi_reports_on_form_type_id"
    t.index ["owner_id"], name: "index_kpi_reports_on_owner_id"
    t.index ["portfolio_company_id"], name: "index_kpi_reports_on_portfolio_company_id"
    t.index ["user_id"], name: "index_kpi_reports_on_user_id"
  end

  create_table "kpis", force: :cascade do |t|
    t.decimal "common_size_value", precision: 6, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "display_value", limit: 30
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.bigint "import_upload_id"
    t.bigint "investor_kpi_mapping_id"
    t.json "json_fields"
    t.bigint "kpi_report_id", null: false
    t.string "name", limit: 100
    t.string "notes"
    t.bigint "owner_id"
    t.decimal "percentage_change", precision: 5, scale: 2, default: "0.0"
    t.bigint "portfolio_company_id"
    t.json "rag_status"
    t.string "source", limit: 100
    t.datetime "updated_at", null: false
    t.decimal "value", precision: 20, scale: 6
    t.index ["deleted_at"], name: "index_kpis_on_deleted_at"
    t.index ["entity_id"], name: "index_kpis_on_entity_id"
    t.index ["form_type_id"], name: "index_kpis_on_form_type_id"
    t.index ["investor_kpi_mapping_id"], name: "index_kpis_on_investor_kpi_mapping_id"
    t.index ["kpi_report_id"], name: "index_kpis_on_kpi_report_id"
    t.index ["owner_id"], name: "index_kpis_on_owner_id"
    t.index ["portfolio_company_id"], name: "index_kpis_on_portfolio_company_id"
  end

  create_table "kyc_data", force: :cascade do |t|
    t.string "PAN", limit: 10
    t.datetime "birth_date"
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.string "external_identifier"
    t.bigint "investor_kyc_id"
    t.string "name"
    t.integer "otp_resend_count", default: 0, null: false
    t.datetime "otp_sent_at"
    t.string "phone", limit: 10
    t.json "request_data"
    t.json "response"
    t.json "response_data"
    t.string "source"
    t.string "status", limit: 20
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_kyc_data_on_entity_id"
    t.index ["investor_kyc_id"], name: "index_kyc_data_on_investor_kyc_id"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "cache_creation_tokens"
    t.integer "cached_tokens"
    t.bigint "chat_id", null: false
    t.text "content"
    t.json "content_raw"
    t.datetime "created_at", null: false
    t.integer "input_tokens"
    t.bigint "model_id"
    t.integer "output_tokens"
    t.string "role", null: false
    t.bigint "tool_call_id"
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["model_id"], name: "index_messages_on_model_id"
    t.index ["role"], name: "index_messages_on_role"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
  end

  create_table "models", force: :cascade do |t|
    t.json "capabilities"
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.string "family"
    t.date "knowledge_cutoff"
    t.integer "max_output_tokens"
    t.json "metadata"
    t.json "modalities"
    t.datetime "model_created_at"
    t.string "model_id", null: false
    t.string "name", null: false
    t.json "pricing"
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["family"], name: "index_models_on_family"
    t.index ["provider", "model_id"], name: "index_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_models_on_provider"
  end

  create_table "notes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "details"
    t.integer "entity_id"
    t.integer "investor_id"
    t.date "on"
    t.string "tags", limit: 100
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["deleted_at"], name: "index_notes_on_deleted_at"
    t.index ["entity_id"], name: "index_notes_on_entity_id"
    t.index ["investor_id"], name: "index_notes_on_investor_id"
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "noticed_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.virtual "entity_id", type: :bigint
    t.integer "notifications_count"
    t.json "params"
    t.bigint "record_id"
    t.string "record_type"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_noticed_events_on_entity_id"
    t.index ["record_type", "record_id"], name: "index_noticed_events_on_record"
  end

  create_table "noticed_notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "email"
    t.boolean "email_sent", default: false
    t.bigint "event_id", null: false
    t.datetime "read_at", precision: nil
    t.bigint "recipient_id", null: false
    t.string "recipient_type", null: false
    t.datetime "seen_at", precision: nil
    t.string "subject"
    t.string "type"
    t.datetime "updated_at", null: false
    t.text "whatsapp"
    t.boolean "whatsapp_sent", default: false
    t.index ["event_id"], name: "index_noticed_notifications_on_event_id"
    t.index ["recipient_type", "recipient_id"], name: "index_noticed_notifications_on_recipient"
  end

  create_table "notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "email"
    t.boolean "email_sent", default: false
    t.bigint "entity_id", null: false
    t.json "params"
    t.datetime "read_at"
    t.bigint "recipient_id", null: false
    t.string "recipient_type", null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.text "whatsapp"
    t.boolean "whatsapp_sent", default: false
    t.index ["entity_id"], name: "index_notifications_on_entity_id"
    t.index ["read_at"], name: "index_notifications_on_read_at"
    t.index ["recipient_type", "recipient_id"], name: "index_notifications_on_recipient"
  end

  create_table "nudges", force: :cascade do |t|
    t.text "bcc"
    t.text "cc"
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "item_id"
    t.string "item_type"
    t.text "msg_body"
    t.text "subject"
    t.text "to"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["entity_id"], name: "index_nudges_on_entity_id"
    t.index ["item_type", "item_id"], name: "index_nudges_on_item"
    t.index ["user_id"], name: "index_nudges_on_user_id"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.bigint "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.string "refresh_token"
    t.bigint "resource_owner_id"
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.string "secret", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "oauth_openid_requests", force: :cascade do |t|
    t.bigint "access_grant_id", null: false
    t.string "nonce", null: false
    t.index ["access_grant_id"], name: "index_oauth_openid_requests_on_access_grant_id"
  end

  create_table "offers", force: :cascade do |t|
    t.string "PAN", limit: 15
    t.string "acquirer_name"
    t.text "address"
    t.text "address_proof_data"
    t.decimal "allocation_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "allocation_percentage", precision: 5, scale: 2, default: "0.0"
    t.bigint "allocation_quantity", default: 0
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.boolean "approved", default: false
    t.boolean "auto_match", default: true
    t.string "bank_account_number", limit: 40
    t.string "bank_name", limit: 50
    t.text "bank_routing_info"
    t.text "bank_verification_response"
    t.string "bank_verification_status"
    t.boolean "bank_verified", default: false
    t.string "buyer_confirmation", limit: 10
    t.bigint "buyer_id"
    t.text "buyer_notes"
    t.string "city", limit: 20
    t.text "comments"
    t.boolean "completed", default: false
    t.datetime "created_at", null: false
    t.string "custom_matching_vals"
    t.datetime "deleted_at"
    t.string "demat", limit: 20
    t.text "docs_uploaded_check"
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.boolean "esign_completed", default: false
    t.boolean "final_agreement", default: false
    t.bigint "final_agreement_user_id"
    t.decimal "final_price", precision: 10, scale: 2, default: "0.0"
    t.bigint "form_type_id"
    t.string "full_name", limit: 100
    t.integer "granted_by_user_id"
    t.bigint "holding_id"
    t.text "id_proof_data"
    t.string "ifsc_code", limit: 20
    t.bigint "import_upload_id"
    t.bigint "interest_id"
    t.bigint "investor_id", null: false
    t.json "json_fields"
    t.text "notes"
    t.string "offer_type", limit: 15
    t.text "pan_card_data"
    t.text "pan_verification_response"
    t.string "pan_verification_status"
    t.boolean "pan_verified", default: false
    t.decimal "percentage", precision: 10, default: "0"
    t.decimal "price", precision: 20, scale: 2, default: "0.0"
    t.integer "quantity", default: 0
    t.bigint "secondary_sale_id", null: false
    t.string "seller_signatory_emails"
    t.text "signature_data"
    t.text "spa_data"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.boolean "verified", default: false
    t.index ["buyer_id"], name: "index_offers_on_buyer_id"
    t.index ["custom_matching_vals"], name: "index_offers_on_custom_matching_vals"
    t.index ["deleted_at"], name: "index_offers_on_deleted_at"
    t.index ["document_folder_id"], name: "index_offers_on_document_folder_id"
    t.index ["entity_id"], name: "index_offers_on_entity_id"
    t.index ["final_agreement_user_id"], name: "index_offers_on_final_agreement_user_id"
    t.index ["form_type_id"], name: "index_offers_on_form_type_id"
    t.index ["interest_id"], name: "index_offers_on_interest_id"
    t.index ["investor_id"], name: "index_offers_on_investor_id"
    t.index ["secondary_sale_id"], name: "index_offers_on_secondary_sale_id"
    t.index ["user_id"], name: "index_offers_on_user_id"
  end

  create_table "payments", force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.decimal "discount", precision: 10, scale: 2, default: "0.0"
    t.bigint "entity_id", null: false
    t.string "plan", limit: 30
    t.string "reference_number"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["deleted_at"], name: "index_payments_on_deleted_at"
    t.index ["entity_id"], name: "index_payments_on_entity_id"
    t.index ["user_id"], name: "index_payments_on_user_id"
  end

  create_table "permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.bigint "entity_id", null: false
    t.bigint "granted_by_id", null: false
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.integer "permissions"
    t.string "role", limit: 20
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["entity_id"], name: "index_permissions_on_entity_id"
    t.index ["granted_by_id"], name: "index_permissions_on_granted_by_id"
    t.index ["owner_type", "owner_id"], name: "index_permissions_on_owner"
    t.index ["user_id"], name: "index_permissions_on_user_id"
  end

  create_table "portfolio_attributions", force: :cascade do |t|
    t.bigint "bought_pi_id", null: false
    t.decimal "cost_of_sold_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "entity_id", null: false
    t.bigint "fund_id", null: false
    t.decimal "gain_cents", precision: 20, scale: 2, default: "0.0"
    t.date "investment_date"
    t.decimal "quantity", precision: 24, scale: 8, default: "0.0"
    t.decimal "sale_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "sold_pi_id", null: false
    t.datetime "updated_at", null: false
    t.index ["bought_pi_id", "deleted_at", "sold_pi_id", "quantity"], name: "idx_pa_bought_deleted_sold_qty"
    t.index ["bought_pi_id", "deleted_at", "sold_pi_id"], name: "idx_portfolio_attributions_bought_sold_deleted"
    t.index ["bought_pi_id"], name: "index_portfolio_attributions_on_bought_pi_id"
    t.index ["deleted_at"], name: "index_portfolio_attributions_on_deleted_at"
    t.index ["entity_id"], name: "index_portfolio_attributions_on_entity_id"
    t.index ["fund_id"], name: "index_portfolio_attributions_on_fund_id"
    t.index ["sold_pi_id"], name: "index_portfolio_attributions_on_sold_pi_id"
  end

  create_table "portfolio_cashflows", force: :cascade do |t|
    t.bigint "aggregate_portfolio_investment_id", null: false
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.bigint "fund_id", null: false
    t.bigint "import_upload_id"
    t.string "instrument"
    t.bigint "investment_instrument_id", null: false
    t.json "json_fields"
    t.text "notes"
    t.date "payment_date"
    t.bigint "portfolio_company_id", null: false
    t.string "tag", limit: 100, default: ""
    t.datetime "updated_at", null: false
    t.index ["aggregate_portfolio_investment_id"], name: "index_portfolio_cashflows_on_aggregate_portfolio_investment_id"
    t.index ["document_folder_id"], name: "index_portfolio_cashflows_on_document_folder_id"
    t.index ["entity_id"], name: "index_portfolio_cashflows_on_entity_id"
    t.index ["form_type_id"], name: "index_portfolio_cashflows_on_form_type_id"
    t.index ["fund_id"], name: "index_portfolio_cashflows_on_fund_id"
    t.index ["investment_instrument_id"], name: "index_portfolio_cashflows_on_investment_instrument_id"
    t.index ["payment_date"], name: "index_portfolio_cashflows_on_payment_date"
    t.index ["portfolio_company_id"], name: "index_portfolio_cashflows_on_portfolio_company_id"
  end

  create_table "portfolio_investments", force: :cascade do |t|
    t.bigint "aggregate_portfolio_investment_id", null: false
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "base_amount_cents", precision: 20, scale: 2
    t.bigint "capital_commitment_id"
    t.bigint "capital_distribution_id"
    t.string "category", limit: 10
    t.boolean "compliant", default: false
    t.date "conversion_date"
    t.decimal "cost_of_remaining_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "cost_of_sold_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.decimal "ex_expenses_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "ex_expenses_base_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "exchange_rate_id"
    t.json "excused_folio_ids", null: false
    t.decimal "fmv_cents", precision: 20, scale: 2, default: "0.0"
    t.string "folio_id", limit: 40
    t.bigint "form_type_id"
    t.bigint "fund_id", null: false
    t.decimal "gain_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "import_upload_id"
    t.decimal "instrument_currency_cost_of_remaining_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "instrument_currency_fmv_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "instrument_currency_unrealized_gain_cents", precision: 20, scale: 2, default: "0.0"
    t.date "investment_date"
    t.string "investment_domicile", limit: 10, default: "Domestic"
    t.bigint "investment_instrument_id"
    t.json "json_fields"
    t.decimal "net_amount_cents", precision: 20, scale: 2
    t.decimal "net_bought_amount_cents", precision: 20, scale: 2
    t.decimal "net_bought_quantity", precision: 20, scale: 2
    t.decimal "net_quantity", precision: 24, scale: 8, default: "0.0"
    t.text "notes"
    t.bigint "orignal_id"
    t.bigint "portfolio_company_id", null: false
    t.string "portfolio_company_name", limit: 100
    t.boolean "proforma", default: false, null: false
    t.decimal "quantity", precision: 24, scale: 8, default: "0.0"
    t.decimal "quantity_as_of_date", precision: 10, default: "0"
    t.bigint "ref_id", default: 0, null: false
    t.bigint "reference_id", default: 0, null: false
    t.string "sector", limit: 100
    t.boolean "snapshot", default: false
    t.date "snapshot_date"
    t.decimal "sold_quantity", precision: 24, scale: 8, default: "0.0"
    t.string "stage"
    t.boolean "startup", default: true
    t.string "sub_category", limit: 100
    t.decimal "tracking_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "tracking_fmv_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "transfer_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "transfer_quantity", precision: 20, scale: 2, default: "0.0"
    t.decimal "unrealized_gain_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "updated_at", null: false
    t.bigint "valuation_id"
    t.index ["aggregate_portfolio_investment_id"], name: "index_portfolio_investments_on_aggregate_portfolio_investment_id"
    t.index ["capital_commitment_id"], name: "index_portfolio_investments_on_capital_commitment_id"
    t.index ["capital_distribution_id"], name: "index_portfolio_investments_on_capital_distribution_id"
    t.index ["conversion_date"], name: "index_portfolio_investments_on_conversion_date"
    t.index ["deleted_at"], name: "index_portfolio_investments_on_deleted_at"
    t.index ["document_folder_id"], name: "index_portfolio_investments_on_document_folder_id"
    t.index ["entity_id"], name: "index_portfolio_investments_on_entity_id"
    t.index ["exchange_rate_id"], name: "index_portfolio_investments_on_exchange_rate_id"
    t.index ["form_type_id"], name: "index_portfolio_investments_on_form_type_id"
    t.index ["fund_id"], name: "index_portfolio_investments_on_fund_id"
    t.index ["id", "investment_date"], name: "idx_portfolio_investments_id_date"
    t.index ["investment_date"], name: "index_portfolio_investments_on_investment_date"
    t.index ["investment_instrument_id"], name: "index_portfolio_investments_on_investment_instrument_id"
    t.index ["portfolio_company_id", "id"], name: "idx_pi_company_id_id"
    t.index ["portfolio_company_id"], name: "index_portfolio_investments_on_portfolio_company_id"
    t.index ["snapshot_date"], name: "index_portfolio_investments_on_snapshot_date"
    t.index ["valuation_id"], name: "index_portfolio_investments_on_valuation_id"
  end

  create_table "portfolio_report_extracts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.datetime "deleted_at"
    t.date "end_date"
    t.bigint "entity_id", null: false
    t.bigint "portfolio_company_id", null: false
    t.bigint "portfolio_report_id", null: false
    t.bigint "portfolio_report_section_id"
    t.date "start_date"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_portfolio_report_extracts_on_deleted_at"
    t.index ["entity_id"], name: "index_portfolio_report_extracts_on_entity_id"
    t.index ["portfolio_company_id"], name: "index_portfolio_report_extracts_on_portfolio_company_id"
    t.index ["portfolio_report_id"], name: "index_portfolio_report_extracts_on_portfolio_report_id"
    t.index ["portfolio_report_section_id"], name: "index_portfolio_report_extracts_on_portfolio_report_section_id"
  end

  create_table "portfolio_report_sections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "data"
    t.string "name", limit: 50
    t.bigint "portfolio_report_id", null: false
    t.string "tags", limit: 100
    t.datetime "updated_at", null: false
    t.index ["portfolio_report_id"], name: "index_portfolio_report_sections_on_portfolio_report_id"
  end

  create_table "portfolio_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "document_folder_id"
    t.bigint "entity_id", null: false
    t.boolean "include_kpi", default: false
    t.boolean "include_portfolio_investments", default: false
    t.string "name"
    t.json "sections"
    t.string "tags", limit: 100
    t.datetime "updated_at", null: false
    t.index ["document_folder_id"], name: "index_portfolio_reports_on_document_folder_id"
    t.index ["entity_id"], name: "index_portfolio_reports_on_entity_id"
  end

  create_table "portfolio_scenarios", force: :cascade do |t|
    t.text "calculations"
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "fund_id", null: false
    t.string "name", limit: 100
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["entity_id"], name: "index_portfolio_scenarios_on_entity_id"
    t.index ["fund_id"], name: "index_portfolio_scenarios_on_fund_id"
    t.index ["user_id"], name: "index_portfolio_scenarios_on_user_id"
  end

  create_table "quick_link_steps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.text "link"
    t.string "name"
    t.integer "position"
    t.bigint "quick_link_id", null: false
    t.datetime "updated_at", null: false
    t.index ["quick_link_id"], name: "index_quick_link_steps_on_quick_link_id"
  end

  create_table "quick_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "entity_id"
    t.string "name"
    t.string "tags"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_quick_links_on_entity_id"
  end

  create_table "regulatory_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.json "json_fields"
    t.bigint "owner_id"
    t.string "owner_type"
    t.string "regulatory_env"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_regulatory_reports_on_entity_id"
    t.index ["form_type_id"], name: "index_regulatory_reports_on_form_type_id"
    t.index ["owner_type", "owner_id"], name: "index_regulatory_reports_on_owner"
  end

  create_table "reminders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "due_date"
    t.string "email"
    t.bigint "entity_id", null: false
    t.text "note"
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.boolean "sent", default: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_reminders_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_reminders_on_owner"
  end

  create_table "report_insights", force: :cascade do |t|
    t.bigint "report_id", null: false
    t.bigint "entity_id", null: false
    t.string "status"
    t.text "ai_response"
    t.text "status_message"
    t.text "summary"
    t.string "trigger_type"
    t.datetime "triggered_at"
    t.bigint "triggered_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_report_insights_on_entity_id"
    t.index ["report_id"], name: "index_report_insights_on_report_id"
  end

  create_table "reports", force: :cascade do |t|
    t.text "ai_prompt"
    t.string "category", limit: 50
    t.datetime "created_at", null: false
    t.string "curr_role", limit: 10, default: "employee"
    t.text "description"
    t.bigint "entity_id"
    t.text "metadata"
    t.string "model"
    t.string "name"
    t.string "notification_ccs"
    t.string "notification_recipients"
    t.integer "notification_repeat_interval", default: 1
    t.string "notification_repeat_unit", default: "days"
    t.integer "notification_start_after", default: 0
    t.string "notification_start_unit", default: "days"
    t.datetime "notify_last_run_at"
    t.datetime "notify_next_run_at"
    t.boolean "send_notification", default: false
    t.string "tag_list"
    t.json "template"
    t.text "template_xls_data"
    t.datetime "updated_at", null: false
    t.text "url"
    t.bigint "user_id", null: false
    t.index ["entity_id"], name: "index_reports_on_entity_id"
    t.index ["notify_next_run_at"], name: "index_reports_on_notify_next_run_at"
    t.index ["user_id"], name: "index_reports_on_user_id"
  end

  create_table "rm_mappings", force: :cascade do |t|
    t.boolean "approved", default: false
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "investor_id", null: false
    t.integer "permissions", default: 0
    t.bigint "rm_entity_id", null: false
    t.bigint "rm_id", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_rm_mappings_on_entity_id"
    t.index ["investor_id"], name: "index_rm_mappings_on_investor_id"
    t.index ["rm_entity_id"], name: "index_rm_mappings_on_rm_entity_id"
    t.index ["rm_id"], name: "index_rm_mappings_on_rm_id"
  end

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "name"
    t.bigint "resource_id"
    t.string "resource_type"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_roles_on_deleted_at"
    t.index ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id"
    t.index ["name"], name: "index_roles_on_name"
    t.index ["resource_type", "resource_id"], name: "index_roles_on_resource"
  end

  create_table "scenario_investments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "fund_id", null: false
    t.bigint "investment_instrument_id"
    t.text "notes"
    t.bigint "portfolio_company_id", null: false
    t.bigint "portfolio_scenario_id", null: false
    t.decimal "price_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "quantity", precision: 20, scale: 2, default: "0.0"
    t.date "transaction_date"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["entity_id"], name: "index_scenario_investments_on_entity_id"
    t.index ["fund_id"], name: "index_scenario_investments_on_fund_id"
    t.index ["investment_instrument_id"], name: "index_scenario_investments_on_investment_instrument_id"
    t.index ["portfolio_company_id"], name: "index_scenario_investments_on_portfolio_company_id"
    t.index ["portfolio_scenario_id"], name: "index_scenario_investments_on_portfolio_scenario_id"
    t.index ["user_id"], name: "index_scenario_investments_on_user_id"
  end

  create_table "secondary_sales", force: :cascade do |t|
    t.boolean "active", default: true
    t.decimal "allocation_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "allocation_percentage", precision: 7, scale: 4, default: "0.0"
    t.decimal "allocation_quantity", precision: 10, scale: 2, default: "0.0"
    t.string "allocation_status", limit: 10
    t.text "buyer_doc_list"
    t.text "cmf_allocation_percentage"
    t.datetime "created_at", null: false
    t.text "custom_matching_fields"
    t.bigint "data_room_folder_id"
    t.datetime "deleted_at"
    t.boolean "disable_bank_kyc", default: false
    t.boolean "disable_pan_kyc", default: false
    t.bigint "document_folder_id"
    t.date "end_date"
    t.bigint "entity_id", null: false
    t.decimal "final_price", precision: 10, scale: 2, default: "0.0"
    t.boolean "finalized", default: false
    t.bigint "form_type_id"
    t.bigint "indicative_quantity", default: 0
    t.bigint "interest_form_type_id"
    t.text "interest_pivot_custom_fields"
    t.json "json_fields"
    t.boolean "lock_allocations", default: false
    t.boolean "manage_interests", default: false
    t.boolean "manage_offers", default: false
    t.decimal "max_price", precision: 20, scale: 2
    t.decimal "min_price", precision: 20, scale: 2
    t.string "name"
    t.boolean "no_interest_emails", default: false
    t.boolean "no_offer_emails", default: false
    t.string "notification_employee_ids"
    t.date "offer_end_date"
    t.bigint "offer_form_type_id"
    t.text "offer_pivot_custom_fields"
    t.integer "percent_allowed", default: 0
    t.string "price_type", limit: 15
    t.string "sale_type", limit: 10, default: "Regular"
    t.bigint "secondary_sale_form_type_id"
    t.text "seller_doc_list"
    t.decimal "seller_transaction_fees_pct", precision: 5, scale: 2
    t.boolean "show_holdings", default: true
    t.string "show_quantity", limit: 10
    t.text "spa_data"
    t.date "start_date"
    t.string "support_email"
    t.decimal "total_interest_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.integer "total_interest_quantity", default: 0
    t.decimal "total_offered_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.integer "total_offered_quantity", default: 0
    t.datetime "updated_at", null: false
    t.boolean "visible_externally", default: false
    t.index ["data_room_folder_id"], name: "index_secondary_sales_on_data_room_folder_id"
    t.index ["deleted_at"], name: "index_secondary_sales_on_deleted_at"
    t.index ["document_folder_id"], name: "index_secondary_sales_on_document_folder_id"
    t.index ["entity_id"], name: "index_secondary_sales_on_entity_id"
    t.index ["form_type_id"], name: "index_secondary_sales_on_form_type_id"
    t.index ["interest_form_type_id"], name: "index_secondary_sales_on_interest_form_type_id"
    t.index ["offer_form_type_id"], name: "index_secondary_sales_on_offer_form_type_id"
    t.index ["secondary_sale_form_type_id"], name: "index_secondary_sales_on_secondary_sale_form_type_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", limit: 1024, null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "stamp_papers", force: :cascade do |t|
    t.string "amounts"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "doc_ref_id"
    t.string "document_category"
    t.string "duty_paid_by"
    t.string "duty_payer_email_id"
    t.string "duty_payer_phone_number"
    t.string "duty_payment_method"
    t.bigint "entity_id", null: false
    t.string "note_on_page", limit: 5
    t.text "notes"
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.string "ref_id"
    t.string "sign_on_page", limit: 5
    t.string "stamp_type"
    t.string "state"
    t.string "tags"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_stamp_papers_on_deleted_at"
    t.index ["entity_id"], name: "index_stamp_papers_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_stamp_papers_on_owner"
  end

  create_table "stock_adjustments", force: :cascade do |t|
    t.decimal "adjustment", precision: 10, scale: 8, default: "0.0"
    t.string "category", limit: 10
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "investment_instrument_id"
    t.text "notes"
    t.bigint "portfolio_company_id", null: false
    t.string "sub_category", limit: 100
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["entity_id"], name: "index_stock_adjustments_on_entity_id"
    t.index ["investment_instrument_id"], name: "index_stock_adjustments_on_investment_instrument_id"
    t.index ["portfolio_company_id"], name: "index_stock_adjustments_on_portfolio_company_id"
    t.index ["user_id"], name: "index_stock_adjustments_on_user_id"
  end

  create_table "stock_conversions", force: :cascade do |t|
    t.date "conversion_date"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "entity_id", null: false
    t.bigint "from_instrument_id", null: false
    t.bigint "from_portfolio_investment_id", null: false
    t.decimal "from_quantity", precision: 20, scale: 2
    t.bigint "fund_id", null: false
    t.text "notes"
    t.bigint "to_instrument_id", null: false
    t.bigint "to_portfolio_investment_id"
    t.decimal "to_quantity", precision: 20, scale: 2
    t.datetime "updated_at", null: false
    t.index ["conversion_date"], name: "index_stock_conversions_on_conversion_date"
    t.index ["deleted_at"], name: "index_stock_conversions_on_deleted_at"
    t.index ["entity_id"], name: "index_stock_conversions_on_entity_id"
    t.index ["from_instrument_id"], name: "index_stock_conversions_on_from_instrument_id"
    t.index ["from_portfolio_investment_id", "conversion_date", "deleted_at"], name: "idx_stock_conversions_from_investment_date_deleted"
    t.index ["from_portfolio_investment_id"], name: "index_stock_conversions_on_from_portfolio_investment_id"
    t.index ["fund_id"], name: "index_stock_conversions_on_fund_id"
    t.index ["to_instrument_id"], name: "index_stock_conversions_on_to_instrument_id"
    t.index ["to_portfolio_investment_id"], name: "index_stock_conversions_on_to_portfolio_investment_id"
  end

  create_table "support_agent_reports", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "json_fields"
    t.bigint "owner_id", null: false
    t.string "owner_name", limit: 50
    t.string "owner_type", null: false
    t.string "status", limit: 10
    t.bigint "support_agent_id", null: false
    t.string "support_agent_name", limit: 50
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id"], name: "index_support_agent_reports_on_owner"
    t.index ["support_agent_id"], name: "index_support_agent_reports_on_support_agent_id"
  end

  create_table "support_agents", force: :cascade do |t|
    t.string "agent_type", limit: 30
    t.datetime "created_at", null: false
    t.string "description"
    t.bigint "document_folder_id"
    t.boolean "enabled", default: true, null: false
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.json "json_fields"
    t.string "name", limit: 30
    t.datetime "updated_at", null: false
    t.boolean "with_steps", default: false
    t.index ["document_folder_id"], name: "index_support_agents_on_document_folder_id"
    t.index ["entity_id"], name: "index_support_agents_on_entity_id"
    t.index ["form_type_id"], name: "index_support_agents_on_form_type_id"
  end

  create_table "support_client_mappings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.boolean "enable_user_login", default: false
    t.boolean "enabled", default: true
    t.date "end_date"
    t.bigint "entity_id", null: false
    t.datetime "updated_at", null: false
    t.string "user_emails"
    t.bigint "user_id", null: false
    t.index ["deleted_at"], name: "index_support_client_mappings_on_deleted_at"
    t.index ["entity_id"], name: "index_support_client_mappings_on_entity_id"
    t.index ["user_id"], name: "index_support_client_mappings_on_user_id"
  end

  create_table "sync_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "openwebui_id"
    t.bigint "syncable_id", null: false
    t.string "syncable_type", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["openwebui_id"], name: "index_sync_records_on_openwebui_id"
    t.index ["syncable_type", "syncable_id"], name: "index_sync_records_on_syncable"
  end

  create_table "taggings", force: :cascade do |t|
    t.string "context", limit: 128
    t.datetime "created_at"
    t.bigint "tag_id"
    t.bigint "taggable_id"
    t.string "taggable_type"
    t.bigint "tagger_id"
    t.string "tagger_type"
    t.string "tenant", limit: 128
    t.index ["context"], name: "index_taggings_on_context"
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "taggings_taggable_context_idx"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable_type_and_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
    t.index ["tagger_type", "tagger_id"], name: "index_taggings_on_tagger_type_and_tagger_id"
    t.index ["tenant"], name: "index_taggings_on_tenant"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "taggings_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "task_templates", force: :cascade do |t|
    t.string "action_link"
    t.datetime "created_at", null: false
    t.text "details"
    t.integer "due_in_days", default: 1
    t.bigint "entity_id"
    t.string "for_class", limit: 40, null: false
    t.string "help_link"
    t.integer "position"
    t.string "tag_list", limit: 100, null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_task_templates_on_entity_id"
    t.index ["for_class"], name: "index_task_templates_on_for_class"
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "assigned_to_id"
    t.boolean "completed", default: false
    t.datetime "created_at", null: false
    t.text "details"
    t.date "due_date"
    t.bigint "entity_id", null: false
    t.bigint "for_entity_id"
    t.boolean "for_support", default: false
    t.bigint "form_type_id"
    t.bigint "owner_id"
    t.string "owner_type"
    t.text "response"
    t.string "tags", limit: 50
    t.bigint "task_template_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["entity_id"], name: "index_tasks_on_entity_id"
    t.index ["for_entity_id"], name: "index_tasks_on_for_entity_id"
    t.index ["form_type_id"], name: "index_tasks_on_form_type_id"
    t.index ["owner_type", "owner_id"], name: "index_tasks_on_owner"
    t.index ["task_template_id"], name: "index_tasks_on_task_template_id"
    t.index ["user_id"], name: "index_tasks_on_user_id"
  end

  create_table "tear_sheet_presentations", force: :cascade do |t|
    t.json "blueprint"
    t.text "content_html"
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "portfolio_report_extract_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_tear_sheet_presentations_on_entity_id"
    t.index ["portfolio_report_extract_id"], name: "index_tear_sheet_presentations_on_portfolio_report_extract_id", unique: true
  end

  create_table "ticker_feeds", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3
    t.date "for_date"
    t.datetime "for_time"
    t.string "name", limit: 100
    t.decimal "price_cents", precision: 20, scale: 2
    t.string "price_type", limit: 3
    t.string "source", limit: 10
    t.string "ticker", limit: 10
    t.datetime "updated_at", null: false
  end

  create_table "tool_calls", force: :cascade do |t|
    t.json "arguments"
    t.datetime "created_at", null: false
    t.bigint "message_id", null: false
    t.string "name", null: false
    t.text "thought_signature"
    t.string "tool_call_id", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_tool_calls_on_message_id"
    t.index ["name"], name: "index_tool_calls_on_name"
    t.index ["tool_call_id"], name: "index_tool_calls_on_tool_call_id", unique: true
  end

  create_table "user_alerts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.string "level", limit: 8
    t.string "message"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["entity_id"], name: "index_user_alerts_on_entity_id"
    t.index ["user_id"], name: "index_user_alerts_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "accept_terms", default: false
    t.timestamp "accepted_terms_on"
    t.text "access_rights_cache"
    t.integer "access_rights_cached_permissions"
    t.boolean "active", default: true
    t.bigint "advisor_entity_id"
    t.string "advisor_entity_roles", limit: 100
    t.string "call_code", limit: 3, default: "91"
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "curr_role", limit: 20
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.datetime "deleted_at"
    t.string "dept", limit: 20
    t.string "email", default: "", null: false
    t.boolean "enable_support"
    t.string "encrypted_password", default: "", null: false
    t.integer "entity_id"
    t.string "entity_type", limit: 25
    t.integer "extended_permissions", default: 0
    t.integer "failed_attempts", default: 0
    t.string "first_name"
    t.bigint "form_type_id"
    t.bigint "investor_advisor_id"
    t.json "json_fields"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "last_synced_at"
    t.string "last_synced_ccf_hex", limit: 64
    t.datetime "locked_at"
    t.bigint "permissions", default: 0, null: false
    t.string "phone", limit: 100
    t.string "primary_region"
    t.integer "primary_region_id"
    t.string "regions"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.boolean "sale_notification", default: false
    t.string "session_token"
    t.integer "sign_in_count", default: 0, null: false
    t.text "signature_data"
    t.boolean "system_created", default: false
    t.string "tag_list"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.boolean "whatsapp_enabled", default: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["entity_id"], name: "index_users_on_entity_id"
    t.index ["form_type_id"], name: "index_users_on_form_type_id"
    t.index ["last_synced_ccf_hex"], name: "index_users_on_last_synced_ccf_hex"
    t.index ["regions"], name: "index_users_on_regions"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "users_roles", id: false, force: :cascade do |t|
    t.bigint "role_id"
    t.bigint "user_id"
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id"
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  create_table "valuations", force: :cascade do |t|
    t.decimal "base_amount_cents", precision: 20, scale: 2
    t.string "category", limit: 10
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.bigint "import_upload_id"
    t.bigint "investment_instrument_id"
    t.json "json_fields"
    t.string "name", limit: 60
    t.decimal "net_valuation_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "owner_id"
    t.string "owner_type"
    t.decimal "per_share_value_cents", precision: 20, scale: 8, default: "0.0"
    t.text "report_data"
    t.string "sub_category", limit: 100
    t.boolean "synthetic", default: false, null: false
    t.datetime "updated_at", null: false
    t.decimal "valuation_cents", precision: 20, scale: 2, default: "0.0"
    t.date "valuation_date"
    t.index ["deleted_at"], name: "index_valuations_on_deleted_at"
    t.index ["entity_id"], name: "index_valuations_on_entity_id"
    t.index ["form_type_id"], name: "index_valuations_on_form_type_id"
    t.index ["investment_instrument_id", "deleted_at", "synthetic", "valuation_date"], name: "idx_latest_valuation"
    t.index ["investment_instrument_id"], name: "index_valuations_on_investment_instrument_id"
    t.index ["owner_id", "owner_type", "deleted_at"], name: "idx_valuations_full_optimized"
    t.index ["owner_type", "owner_id"], name: "index_valuations_on_owner"
    t.index ["valuation_date"], name: "index_valuations_on_valuation_date"
  end

  create_table "versions", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type"
    t.text "object"
    t.text "object_changes"
    t.string "whodunnit"
    t.string "{:null=>false, :limit=>191}"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "video_kycs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "investor_kyc_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["entity_id"], name: "index_video_kycs_on_entity_id"
    t.index ["investor_kyc_id"], name: "index_video_kycs_on_investor_kyc_id"
    t.index ["user_id"], name: "index_video_kycs_on_user_id"
  end

  create_table "viewed_bies", force: :cascade do |t|
    t.integer "count", default: 0
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["entity_id"], name: "index_viewed_bies_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_viewed_bies_on_owner"
    t.index ["user_id"], name: "index_viewed_bies_on_user_id"
  end

  add_foreign_key "access_rights", "entities"
  add_foreign_key "access_rights", "investors", column: "access_to_investor_id"
  add_foreign_key "access_rights", "users"
  add_foreign_key "access_rights", "users", column: "granted_by_id"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_charts", "entities"
  add_foreign_key "aggregate_portfolio_investments", "entities"
  add_foreign_key "aggregate_portfolio_investments", "folders", column: "document_folder_id"
  add_foreign_key "aggregate_portfolio_investments", "form_types"
  add_foreign_key "aggregate_portfolio_investments", "funds"
  add_foreign_key "aggregate_portfolio_investments", "investment_instruments"
  add_foreign_key "aggregate_portfolio_investments", "investors", column: "portfolio_company_id"
  add_foreign_key "ai_chat_messages", "ai_chat_sessions"
  add_foreign_key "ai_chat_sessions", "ai_portfolio_reports"
  add_foreign_key "ai_checks", "ai_rules"
  add_foreign_key "ai_checks", "entities"
  add_foreign_key "ai_portfolio_reports", "folders"
  add_foreign_key "ai_presentations", "entities"
  add_foreign_key "ai_report_sections", "ai_portfolio_reports"
  add_foreign_key "ai_rules", "entities"
  add_foreign_key "allocation_runs", "entities"
  add_foreign_key "allocation_runs", "funds"
  add_foreign_key "allocation_runs", "users"
  add_foreign_key "allocations", "entities"
  add_foreign_key "allocations", "folders", column: "document_folder_id"
  add_foreign_key "allocations", "form_types"
  add_foreign_key "allocations", "interests"
  add_foreign_key "allocations", "offers"
  add_foreign_key "allocations", "secondary_sales"
  add_foreign_key "aml_reports", "entities"
  add_foreign_key "aml_reports", "folders", column: "document_folder_id"
  add_foreign_key "aml_reports", "investor_kycs"
  add_foreign_key "aml_reports", "investors"
  add_foreign_key "approval_responses", "approvals"
  add_foreign_key "approval_responses", "entities"
  add_foreign_key "approval_responses", "entities", column: "response_entity_id"
  add_foreign_key "approval_responses", "folders", column: "document_folder_id"
  add_foreign_key "approval_responses", "form_types"
  add_foreign_key "approval_responses", "investors"
  add_foreign_key "approval_responses", "users", column: "response_user_id"
  add_foreign_key "approvals", "entities"
  add_foreign_key "approvals", "folders", column: "document_folder_id"
  add_foreign_key "assistant_tasks", "entities"
  add_foreign_key "assistant_tasks", "users"
  add_foreign_key "call_fees", "capital_calls"
  add_foreign_key "call_fees", "entities"
  add_foreign_key "call_fees", "funds"
  add_foreign_key "capital_calls", "entities"
  add_foreign_key "capital_calls", "folders", column: "document_folder_id"
  add_foreign_key "capital_calls", "funds"
  add_foreign_key "capital_calls", "users", column: "approved_by_user_id"
  add_foreign_key "capital_commitments", "entities"
  add_foreign_key "capital_commitments", "exchange_rates"
  add_foreign_key "capital_commitments", "folders", column: "document_folder_id"
  add_foreign_key "capital_commitments", "funds"
  add_foreign_key "capital_commitments", "funds", column: "feeder_fund_id"
  add_foreign_key "capital_commitments", "investor_kycs"
  add_foreign_key "capital_commitments", "investors"
  add_foreign_key "capital_commitments", "users", column: "investor_signatory_id"
  add_foreign_key "capital_distribution_payments", "capital_commitments"
  add_foreign_key "capital_distribution_payments", "capital_distributions"
  add_foreign_key "capital_distribution_payments", "entities"
  add_foreign_key "capital_distribution_payments", "exchange_rates"
  add_foreign_key "capital_distribution_payments", "folders", column: "document_folder_id"
  add_foreign_key "capital_distribution_payments", "form_types"
  add_foreign_key "capital_distribution_payments", "funds"
  add_foreign_key "capital_distribution_payments", "investors"
  add_foreign_key "capital_distributions", "capital_commitments"
  add_foreign_key "capital_distributions", "entities"
  add_foreign_key "capital_distributions", "folders", column: "document_folder_id"
  add_foreign_key "capital_distributions", "form_types"
  add_foreign_key "capital_distributions", "funds"
  add_foreign_key "capital_distributions", "users", column: "approved_by_user_id"
  add_foreign_key "capital_remittance_payments", "capital_remittances"
  add_foreign_key "capital_remittance_payments", "entities"
  add_foreign_key "capital_remittance_payments", "exchange_rates"
  add_foreign_key "capital_remittance_payments", "form_types"
  add_foreign_key "capital_remittance_payments", "funds"
  add_foreign_key "capital_remittances", "capital_calls"
  add_foreign_key "capital_remittances", "capital_commitments"
  add_foreign_key "capital_remittances", "entities"
  add_foreign_key "capital_remittances", "exchange_rates"
  add_foreign_key "capital_remittances", "folders", column: "document_folder_id"
  add_foreign_key "capital_remittances", "funds"
  add_foreign_key "capital_remittances", "investors"
  add_foreign_key "chats", "models"
  add_foreign_key "ci_profiles", "entities"
  add_foreign_key "ci_profiles", "funds"
  add_foreign_key "ci_track_records", "entities"
  add_foreign_key "ci_track_records", "investment_opportunities"
  add_foreign_key "ci_widgets", "entities"
  add_foreign_key "ci_widgets", "investment_opportunities"
  add_foreign_key "commitment_adjustments", "capital_commitments"
  add_foreign_key "commitment_adjustments", "entities"
  add_foreign_key "commitment_adjustments", "exchange_rates"
  add_foreign_key "commitment_adjustments", "funds"
  add_foreign_key "custom_notifications", "entities"
  add_foreign_key "custom_notifications", "folders", column: "document_folder_id"
  add_foreign_key "dashboard_widgets", "entities"
  add_foreign_key "deal_activities", "deal_investors"
  add_foreign_key "deal_activities", "deals"
  add_foreign_key "deal_activities", "folders", column: "document_folder_id"
  add_foreign_key "deal_docs", "deal_activities"
  add_foreign_key "deal_docs", "deal_investors"
  add_foreign_key "deal_docs", "deals"
  add_foreign_key "deal_docs", "users"
  add_foreign_key "deal_investors", "deal_activities"
  add_foreign_key "deal_investors", "deals"
  add_foreign_key "deal_investors", "entities"
  add_foreign_key "deal_investors", "folders", column: "document_folder_id"
  add_foreign_key "deal_investors", "form_types"
  add_foreign_key "deal_investors", "investors"
  add_foreign_key "deals", "deals", column: "clone_from_id"
  add_foreign_key "deals", "entities"
  add_foreign_key "deals", "folders", column: "data_room_folder_id"
  add_foreign_key "deals", "folders", column: "deal_documents_folder_id"
  add_foreign_key "deals", "folders", column: "document_folder_id"
  add_foreign_key "deals", "form_types"
  add_foreign_key "doc_questions", "entities"
  add_foreign_key "doc_shares", "documents"
  add_foreign_key "documents", "folders"
  add_foreign_key "documents", "form_types"
  add_foreign_key "documents", "users"
  add_foreign_key "documents", "users", column: "approved_by_id"
  add_foreign_key "documents", "users", column: "signed_by_id"
  add_foreign_key "e_signatures", "documents"
  add_foreign_key "e_signatures", "entities"
  add_foreign_key "e_signatures", "users"
  add_foreign_key "entities", "folders", column: "root_folder_id"
  add_foreign_key "entity_settings", "entities"
  add_foreign_key "esign_logs", "documents"
  add_foreign_key "esign_logs", "entities"
  add_foreign_key "events", "entities"
  add_foreign_key "exchange_rates", "entities"
  add_foreign_key "exchange_rates", "folders", column: "document_folder_id"
  add_foreign_key "exchange_rates", "import_uploads"
  add_foreign_key "excused_investors", "aggregate_portfolio_investments"
  add_foreign_key "excused_investors", "capital_commitments"
  add_foreign_key "excused_investors", "entities"
  add_foreign_key "excused_investors", "funds"
  add_foreign_key "excused_investors", "investors", column: "portfolio_company_id"
  add_foreign_key "excused_investors", "portfolio_investments"
  add_foreign_key "expression_of_interests", "entities"
  add_foreign_key "expression_of_interests", "entities", column: "eoi_entity_id"
  add_foreign_key "expression_of_interests", "folders", column: "document_folder_id"
  add_foreign_key "expression_of_interests", "form_types"
  add_foreign_key "expression_of_interests", "investment_opportunities"
  add_foreign_key "expression_of_interests", "investor_kycs"
  add_foreign_key "expression_of_interests", "investors"
  add_foreign_key "expression_of_interests", "users"
  add_foreign_key "expression_of_interests", "users", column: "investor_signatory_id"
  add_foreign_key "faq_threads", "users"
  add_foreign_key "fees", "entities"
  add_foreign_key "folders", "entities"
  add_foreign_key "form_custom_fields", "form_types"
  add_foreign_key "form_types", "entities"
  add_foreign_key "fund_formulas", "entities"
  add_foreign_key "fund_formulas", "funds"
  add_foreign_key "fund_ratios", "capital_commitments"
  add_foreign_key "fund_ratios", "entities"
  add_foreign_key "fund_ratios", "form_types"
  add_foreign_key "fund_ratios", "funds"
  add_foreign_key "fund_ratios", "portfolio_scenarios"
  add_foreign_key "fund_ratios", "valuations"
  add_foreign_key "fund_reports", "entities"
  add_foreign_key "fund_reports", "form_types"
  add_foreign_key "fund_reports", "funds"
  add_foreign_key "fund_sebi_infos", "entities"
  add_foreign_key "fund_sebi_infos", "funds"
  add_foreign_key "fund_unit_settings", "entities"
  add_foreign_key "fund_unit_settings", "form_types"
  add_foreign_key "fund_unit_settings", "funds"
  add_foreign_key "fund_unit_transfers", "capital_commitments", column: "from_commitment_id"
  add_foreign_key "fund_unit_transfers", "capital_commitments", column: "to_commitment_id"
  add_foreign_key "fund_unit_transfers", "entities"
  add_foreign_key "fund_unit_transfers", "funds"
  add_foreign_key "fund_units", "capital_commitments"
  add_foreign_key "fund_units", "entities"
  add_foreign_key "fund_units", "funds"
  add_foreign_key "fund_units", "investors"
  add_foreign_key "funding_rounds", "entities"
  add_foreign_key "funds", "entities"
  add_foreign_key "funds", "folders", column: "data_room_folder_id"
  add_foreign_key "funds", "folders", column: "document_folder_id"
  add_foreign_key "funds", "funds", column: "master_fund_id"
  add_foreign_key "funds", "import_uploads"
  add_foreign_key "funds", "users", column: "fund_signatory_id"
  add_foreign_key "funds", "users", column: "trustee_signatory_id"
  add_foreign_key "grid_view_preferences", "custom_grid_views"
  add_foreign_key "import_uploads", "entities"
  add_foreign_key "import_uploads", "users"
  add_foreign_key "incoming_emails", "entities"
  add_foreign_key "incoming_emails", "folders", column: "document_folder_id"
  add_foreign_key "interests", "folders", column: "document_folder_id"
  add_foreign_key "interests", "form_types"
  add_foreign_key "interests", "funding_rounds"
  add_foreign_key "interests", "import_uploads"
  add_foreign_key "interests", "investors"
  add_foreign_key "interests", "secondary_sales"
  add_foreign_key "interests", "users"
  add_foreign_key "interests", "users", column: "final_agreement_user_id"
  add_foreign_key "interests", "users", column: "status_updated_by_id"
  add_foreign_key "investment_instruments", "entities"
  add_foreign_key "investment_instruments", "form_types"
  add_foreign_key "investment_instruments", "investors", column: "portfolio_company_id"
  add_foreign_key "investment_opportunities", "entities"
  add_foreign_key "investment_opportunities", "folders", column: "data_room_folder_id"
  add_foreign_key "investment_opportunities", "folders", column: "document_folder_id"
  add_foreign_key "investment_opportunities", "form_types"
  add_foreign_key "investments", "form_types"
  add_foreign_key "investments", "investors", column: "portfolio_company_id"
  add_foreign_key "investor_accesses", "entities", column: "investor_entity_id"
  add_foreign_key "investor_advisors", "entities"
  add_foreign_key "investor_advisors", "users"
  add_foreign_key "investor_advisors", "users", column: "created_by_id"
  add_foreign_key "investor_kpi_mappings", "entities"
  add_foreign_key "investor_kpi_mappings", "form_types"
  add_foreign_key "investor_kpi_mappings", "investors"
  add_foreign_key "investor_kycs", "entities"
  add_foreign_key "investor_kycs", "folders", column: "document_folder_id"
  add_foreign_key "investor_kycs", "form_types"
  add_foreign_key "investor_kycs", "investors"
  add_foreign_key "investor_kycs", "users", column: "investor_user_id"
  add_foreign_key "investor_kycs", "users", column: "verified_by_id"
  add_foreign_key "investor_notice_entries", "entities"
  add_foreign_key "investor_notice_entries", "entities", column: "investor_entity_id"
  add_foreign_key "investor_notice_entries", "investor_notices"
  add_foreign_key "investor_notice_entries", "investors"
  add_foreign_key "investor_notice_items", "entities"
  add_foreign_key "investor_notice_items", "investor_notices"
  add_foreign_key "investor_notices", "entities"
  add_foreign_key "investors", "folders", column: "document_folder_id"
  add_foreign_key "investors", "form_types"
  add_foreign_key "kanban_boards", "entities"
  add_foreign_key "kanban_cards", "entities"
  add_foreign_key "kanban_cards", "kanban_boards"
  add_foreign_key "kanban_cards", "kanban_columns"
  add_foreign_key "kanban_columns", "entities"
  add_foreign_key "kanban_columns", "kanban_boards"
  add_foreign_key "kpi_reports", "entities"
  add_foreign_key "kpi_reports", "entities", column: "owner_id"
  add_foreign_key "kpi_reports", "folders", column: "document_folder_id"
  add_foreign_key "kpi_reports", "form_types"
  add_foreign_key "kpi_reports", "investors", column: "portfolio_company_id"
  add_foreign_key "kpi_reports", "users"
  add_foreign_key "kpis", "entities"
  add_foreign_key "kpis", "entities", column: "owner_id"
  add_foreign_key "kpis", "form_types"
  add_foreign_key "kpis", "investor_kpi_mappings"
  add_foreign_key "kpis", "investors", column: "portfolio_company_id"
  add_foreign_key "kpis", "kpi_reports"
  add_foreign_key "kyc_data", "entities"
  add_foreign_key "kyc_data", "investor_kycs"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "models"
  add_foreign_key "messages", "tool_calls"
  add_foreign_key "nudges", "entities"
  add_foreign_key "nudges", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_openid_requests", "oauth_access_grants", column: "access_grant_id", on_delete: :cascade
  add_foreign_key "offers", "entities"
  add_foreign_key "offers", "folders", column: "document_folder_id"
  add_foreign_key "offers", "form_types"
  add_foreign_key "offers", "interests"
  add_foreign_key "offers", "secondary_sales"
  add_foreign_key "offers", "users"
  add_foreign_key "offers", "users", column: "final_agreement_user_id"
  add_foreign_key "payments", "entities"
  add_foreign_key "payments", "users"
  add_foreign_key "permissions", "entities"
  add_foreign_key "permissions", "users"
  add_foreign_key "permissions", "users", column: "granted_by_id"
  add_foreign_key "portfolio_attributions", "entities"
  add_foreign_key "portfolio_attributions", "funds"
  add_foreign_key "portfolio_attributions", "portfolio_investments", column: "bought_pi_id"
  add_foreign_key "portfolio_attributions", "portfolio_investments", column: "sold_pi_id"
  add_foreign_key "portfolio_cashflows", "aggregate_portfolio_investments"
  add_foreign_key "portfolio_cashflows", "entities"
  add_foreign_key "portfolio_cashflows", "folders", column: "document_folder_id"
  add_foreign_key "portfolio_cashflows", "form_types"
  add_foreign_key "portfolio_cashflows", "funds"
  add_foreign_key "portfolio_cashflows", "investment_instruments"
  add_foreign_key "portfolio_cashflows", "investors", column: "portfolio_company_id"
  add_foreign_key "portfolio_investments", "capital_commitments"
  add_foreign_key "portfolio_investments", "capital_distributions"
  add_foreign_key "portfolio_investments", "entities"
  add_foreign_key "portfolio_investments", "exchange_rates"
  add_foreign_key "portfolio_investments", "folders", column: "document_folder_id"
  add_foreign_key "portfolio_investments", "form_types"
  add_foreign_key "portfolio_investments", "funds"
  add_foreign_key "portfolio_investments", "investment_instruments"
  add_foreign_key "portfolio_investments", "investors", column: "portfolio_company_id"
  add_foreign_key "portfolio_investments", "valuations"
  add_foreign_key "portfolio_report_extracts", "entities"
  add_foreign_key "portfolio_report_extracts", "investors", column: "portfolio_company_id"
  add_foreign_key "portfolio_report_extracts", "portfolio_report_sections"
  add_foreign_key "portfolio_report_extracts", "portfolio_reports"
  add_foreign_key "portfolio_report_sections", "portfolio_reports"
  add_foreign_key "portfolio_reports", "entities"
  add_foreign_key "portfolio_reports", "folders", column: "document_folder_id"
  add_foreign_key "portfolio_scenarios", "entities"
  add_foreign_key "portfolio_scenarios", "funds"
  add_foreign_key "portfolio_scenarios", "users"
  add_foreign_key "quick_link_steps", "quick_links"
  add_foreign_key "quick_links", "entities"
  add_foreign_key "regulatory_reports", "entities"
  add_foreign_key "regulatory_reports", "form_types"
  add_foreign_key "reminders", "entities"
  add_foreign_key "report_insights", "entities"
  add_foreign_key "report_insights", "reports"
  add_foreign_key "reports", "entities"
  add_foreign_key "reports", "users"
  add_foreign_key "rm_mappings", "entities"
  add_foreign_key "rm_mappings", "entities", column: "rm_entity_id"
  add_foreign_key "rm_mappings", "investors"
  add_foreign_key "rm_mappings", "investors", column: "rm_id"
  add_foreign_key "scenario_investments", "entities"
  add_foreign_key "scenario_investments", "funds"
  add_foreign_key "scenario_investments", "investment_instruments"
  add_foreign_key "scenario_investments", "investors", column: "portfolio_company_id"
  add_foreign_key "scenario_investments", "portfolio_scenarios"
  add_foreign_key "scenario_investments", "users"
  add_foreign_key "secondary_sales", "entities"
  add_foreign_key "secondary_sales", "folders", column: "data_room_folder_id"
  add_foreign_key "secondary_sales", "folders", column: "document_folder_id"
  add_foreign_key "secondary_sales", "form_types"
  add_foreign_key "secondary_sales", "form_types", column: "interest_form_type_id"
  add_foreign_key "secondary_sales", "form_types", column: "offer_form_type_id"
  add_foreign_key "secondary_sales", "form_types", column: "secondary_sale_form_type_id"
  add_foreign_key "stamp_papers", "entities"
  add_foreign_key "stock_adjustments", "entities"
  add_foreign_key "stock_adjustments", "investment_instruments"
  add_foreign_key "stock_adjustments", "investors", column: "portfolio_company_id"
  add_foreign_key "stock_adjustments", "users"
  add_foreign_key "stock_conversions", "entities"
  add_foreign_key "stock_conversions", "funds"
  add_foreign_key "stock_conversions", "investment_instruments", column: "from_instrument_id"
  add_foreign_key "stock_conversions", "investment_instruments", column: "to_instrument_id"
  add_foreign_key "stock_conversions", "portfolio_investments", column: "from_portfolio_investment_id"
  add_foreign_key "stock_conversions", "portfolio_investments", column: "to_portfolio_investment_id"
  add_foreign_key "support_agent_reports", "support_agents"
  add_foreign_key "support_agents", "entities"
  add_foreign_key "support_agents", "folders", column: "document_folder_id"
  add_foreign_key "support_agents", "form_types"
  add_foreign_key "support_client_mappings", "entities"
  add_foreign_key "support_client_mappings", "users"
  add_foreign_key "taggings", "tags"
  add_foreign_key "task_templates", "entities"
  add_foreign_key "tasks", "entities"
  add_foreign_key "tasks", "form_types"
  add_foreign_key "tasks", "task_templates"
  add_foreign_key "tasks", "users"
  add_foreign_key "tool_calls", "messages"
  add_foreign_key "user_alerts", "entities"
  add_foreign_key "user_alerts", "users"
  add_foreign_key "users", "form_types"
  add_foreign_key "valuations", "entities"
  add_foreign_key "valuations", "form_types"
  add_foreign_key "valuations", "investment_instruments"
  add_foreign_key "video_kycs", "entities"
  add_foreign_key "video_kycs", "investor_kycs"
  add_foreign_key "video_kycs", "users"
  add_foreign_key "viewed_bies", "entities"
  add_foreign_key "viewed_bies", "users"
end
