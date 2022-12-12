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

ActiveRecord::Schema[7.0].define(version: 2022_12_12_070017) do
  create_table "abraham_histories", id: :integer, charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "controller_name"
    t.string "action_name"
    t.string "tour_name"
    t.integer "creator_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["created_at"], name: "index_abraham_histories_on_created_at"
    t.index ["creator_id"], name: "index_abraham_histories_on_creator_id"
    t.index ["updated_at"], name: "index_abraham_histories_on_updated_at"
  end

  create_table "access_rights", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.string "access_to_email", limit: 30
    t.bigint "access_to_investor_id"
    t.string "access_type", limit: 25
    t.string "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_id", null: false
    t.string "access_to_category", limit: 20
    t.datetime "deleted_at"
    t.boolean "cascade", default: false
    t.bigint "user_id"
    t.bigint "permissions", default: 0, null: false
    t.boolean "notify", default: true
    t.index ["access_to_investor_id"], name: "index_access_rights_on_access_to_investor_id"
    t.index ["deleted_at"], name: "index_access_rights_on_deleted_at"
    t.index ["entity_id"], name: "index_access_rights_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_access_rights_on_owner"
    t.index ["user_id"], name: "index_access_rights_on_user_id"
  end

  create_table "action_text_rich_texts", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name", null: false
    t.text "body", size: :long
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_admin_comments", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "namespace"
    t.text "body"
    t.string "resource_type"
    t.bigint "resource_id"
    t.string "author_type"
    t.bigint "author_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author"
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource"
  end

  create_table "active_storage_attachments", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activities", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "trackable_type"
    t.bigint "trackable_id"
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "key"
    t.text "parameters"
    t.string "recipient_type"
    t.bigint "recipient_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "entity_id"
    t.index ["entity_id"], name: "index_activities_on_entity_id"
    t.index ["owner_id", "owner_type"], name: "index_activities_on_owner_id_and_owner_type"
    t.index ["owner_type", "owner_id"], name: "index_activities_on_owner"
    t.index ["recipient_id", "recipient_type"], name: "index_activities_on_recipient_id_and_recipient_type"
    t.index ["recipient_type", "recipient_id"], name: "index_activities_on_recipient"
    t.index ["trackable_id", "trackable_type"], name: "index_activities_on_trackable_id_and_trackable_type"
    t.index ["trackable_type", "trackable_id"], name: "index_activities_on_trackable"
  end

  create_table "adhaar_esigns", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "document_id", null: false
    t.string "esign_doc_id", limit: 100
    t.text "signed_file_url"
    t.boolean "is_signed", default: false
    t.text "esign_document_reponse"
    t.text "esign_retrieve_reponse"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "owner_type"
    t.bigint "owner_id"
    t.index ["document_id"], name: "index_adhaar_esigns_on_document_id"
    t.index ["entity_id"], name: "index_adhaar_esigns_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_adhaar_esigns_on_owner"
  end

  create_table "admin_users", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admin_users_on_reset_password_token", unique: true
  end

  create_table "aggregate_investments", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "shareholder"
    t.bigint "investor_id", null: false
    t.integer "equity", default: 0
    t.integer "preferred", default: 0
    t.integer "options", default: 0
    t.decimal "percentage", precision: 5, scale: 2, default: "0.0"
    t.decimal "full_diluted_percentage", precision: 5, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "funding_round_id"
    t.integer "units", default: 0
    t.integer "preferred_converted_qty", default: 0
    t.index ["entity_id"], name: "index_aggregate_investments_on_entity_id"
    t.index ["funding_round_id"], name: "index_aggregate_investments_on_funding_round_id"
    t.index ["investor_id"], name: "index_aggregate_investments_on_investor_id"
  end

  create_table "approval_responses", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "response_entity_id", null: false
    t.bigint "response_user_id"
    t.bigint "approval_id", null: false
    t.string "status", limit: 10
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "investor_id", null: false
    t.index ["approval_id"], name: "index_approval_responses_on_approval_id"
    t.index ["entity_id"], name: "index_approval_responses_on_entity_id"
    t.index ["investor_id"], name: "index_approval_responses_on_investor_id"
    t.index ["response_entity_id"], name: "index_approval_responses_on_response_entity_id"
    t.index ["response_user_id"], name: "index_approval_responses_on_response_user_id"
  end

  create_table "approvals", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "title"
    t.bigint "entity_id", null: false
    t.integer "approved_count", default: 0
    t.integer "rejected_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "pending_count", default: 0
    t.boolean "approved", default: false
    t.text "properties"
    t.bigint "form_type_id"
    t.date "due_date"
    t.index ["entity_id"], name: "index_approvals_on_entity_id"
    t.index ["form_type_id"], name: "index_approvals_on_form_type_id"
  end

  create_table "audits", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.integer "auditable_id"
    t.string "auditable_type"
    t.integer "associated_id"
    t.string "associated_type"
    t.integer "user_id"
    t.string "user_type"
    t.string "username"
    t.string "action"
    t.text "audited_changes"
    t.integer "version", default: 0
    t.string "comment"
    t.string "remote_address"
    t.string "request_uuid"
    t.datetime "created_at"
    t.index ["associated_type", "associated_id"], name: "associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "auditable_index"
    t.index ["created_at"], name: "index_audits_on_created_at"
    t.index ["request_uuid"], name: "index_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "user_index"
  end

  create_table "capital_calls", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "fund_id", null: false
    t.string "name"
    t.decimal "percentage_called", precision: 5, scale: 2, default: "0.0"
    t.decimal "collected_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "call_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.date "due_date"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "properties"
    t.bigint "form_type_id"
    t.boolean "approved", default: false
    t.bigint "approved_by_user_id"
    t.boolean "manual_generation", default: false
    t.boolean "generate_remittances", default: true
    t.boolean "generate_remittances_verified", default: false
    t.index ["approved_by_user_id"], name: "index_capital_calls_on_approved_by_user_id"
    t.index ["entity_id"], name: "index_capital_calls_on_entity_id"
    t.index ["form_type_id"], name: "index_capital_calls_on_form_type_id"
    t.index ["fund_id"], name: "index_capital_calls_on_fund_id"
  end

  create_table "capital_commitments", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "investor_id", null: false
    t.bigint "fund_id", null: false
    t.decimal "committed_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "collected_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "properties"
    t.bigint "form_type_id"
    t.decimal "percentage", precision: 11, scale: 8, default: "0.0"
    t.bigint "ppm_number", default: 0
    t.string "investor_signature_types", limit: 20
    t.string "folio_id", limit: 20
    t.bigint "investor_signatory_id"
    t.boolean "esign_required", default: false
    t.boolean "esign_completed", default: false
    t.string "esign_provider", limit: 10
    t.string "esign_link"
    t.decimal "call_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "distribution_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.boolean "onboarding_completed", default: false
    t.index ["entity_id"], name: "index_capital_commitments_on_entity_id"
    t.index ["form_type_id"], name: "index_capital_commitments_on_form_type_id"
    t.index ["fund_id"], name: "index_capital_commitments_on_fund_id"
    t.index ["investor_id"], name: "index_capital_commitments_on_investor_id"
    t.index ["investor_signatory_id"], name: "index_capital_commitments_on_investor_signatory_id"
  end

  create_table "capital_distribution_payments", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "fund_id", null: false
    t.bigint "entity_id", null: false
    t.bigint "capital_distribution_id", null: false
    t.bigint "investor_id", null: false
    t.bigint "form_type_id"
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.date "payment_date"
    t.text "properties"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "completed", default: false
    t.decimal "percentage", precision: 5, scale: 2, default: "0.0"
    t.string "folio_id", limit: 20
    t.bigint "capital_commitment_id"
    t.index ["capital_commitment_id"], name: "index_capital_distribution_payments_on_capital_commitment_id"
    t.index ["capital_distribution_id"], name: "index_capital_distribution_payments_on_capital_distribution_id"
    t.index ["entity_id"], name: "index_capital_distribution_payments_on_entity_id"
    t.index ["form_type_id"], name: "index_capital_distribution_payments_on_form_type_id"
    t.index ["fund_id"], name: "index_capital_distribution_payments_on_fund_id"
    t.index ["investor_id"], name: "index_capital_distribution_payments_on_investor_id"
  end

  create_table "capital_distributions", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "fund_id", null: false
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.decimal "gross_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "carry_cents", precision: 20, scale: 2, default: "0.0"
    t.date "distribution_date"
    t.text "properties"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "title"
    t.boolean "completed", default: false
    t.decimal "distribution_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "net_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.boolean "approved", default: false
    t.bigint "approved_by_user_id"
    t.boolean "manual_generation", default: false
    t.boolean "generate_payments", default: true
    t.boolean "generate_payments_paid", default: false
    t.index ["approved_by_user_id"], name: "index_capital_distributions_on_approved_by_user_id"
    t.index ["entity_id"], name: "index_capital_distributions_on_entity_id"
    t.index ["form_type_id"], name: "index_capital_distributions_on_form_type_id"
    t.index ["fund_id"], name: "index_capital_distributions_on_fund_id"
  end

  create_table "capital_remittances", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "fund_id", null: false
    t.bigint "capital_call_id", null: false
    t.bigint "investor_id", null: false
    t.string "status", limit: 10
    t.decimal "call_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "collected_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "capital_commitment_id"
    t.text "properties"
    t.bigint "form_type_id"
    t.boolean "verified", default: false
    t.text "payment_proof_data"
    t.string "folio_id", limit: 20
    t.index ["capital_call_id"], name: "index_capital_remittances_on_capital_call_id"
    t.index ["capital_commitment_id"], name: "index_capital_remittances_on_capital_commitment_id"
    t.index ["entity_id"], name: "index_capital_remittances_on_entity_id"
    t.index ["form_type_id"], name: "index_capital_remittances_on_form_type_id"
    t.index ["fund_id"], name: "index_capital_remittances_on_fund_id"
    t.index ["investor_id"], name: "index_capital_remittances_on_investor_id"
  end

  create_table "deal_activities", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "deal_id", null: false
    t.bigint "deal_investor_id"
    t.date "by_date"
    t.string "status", limit: 20
    t.boolean "completed"
    t.integer "entity_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "title"
    t.text "details"
    t.integer "sequence"
    t.integer "days"
    t.datetime "deleted_at"
    t.integer "template_id"
    t.index ["deal_id"], name: "index_deal_activities_on_deal_id"
    t.index ["deal_investor_id"], name: "index_deal_activities_on_deal_investor_id"
    t.index ["deleted_at"], name: "index_deal_activities_on_deleted_at"
    t.index ["entity_id"], name: "index_deal_activities_on_entity_id"
  end

  create_table "deal_docs", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name"
    t.bigint "deal_id", null: false
    t.bigint "deal_investor_id"
    t.bigint "deal_activity_id"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "file_file_name"
    t.string "file_content_type"
    t.bigint "file_file_size"
    t.datetime "file_updated_at"
    t.datetime "deleted_at"
    t.integer "impressions_count", default: 0
    t.index ["deal_activity_id"], name: "index_deal_docs_on_deal_activity_id"
    t.index ["deal_id"], name: "index_deal_docs_on_deal_id"
    t.index ["deal_investor_id"], name: "index_deal_docs_on_deal_investor_id"
    t.index ["deleted_at"], name: "index_deal_docs_on_deleted_at"
    t.index ["user_id"], name: "index_deal_docs_on_user_id"
  end

  create_table "deal_investors", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "deal_id", null: false
    t.bigint "investor_id", null: false
    t.string "status", limit: 20
    t.decimal "primary_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "secondary_investment_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "entity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "investor_entity_id"
    t.datetime "deleted_at"
    t.integer "impressions_count"
    t.integer "unread_messages_investor", default: 0
    t.integer "unread_messages_investee", default: 0
    t.integer "todays_messages_investor", default: 0
    t.integer "todays_messages_investee", default: 0
    t.decimal "pre_money_valuation_cents", precision: 20, scale: 2, default: "0.0"
    t.string "company_advisor", limit: 100
    t.string "investor_advisor", limit: 100
    t.string "investor_name"
    t.string "tier", limit: 10
    t.index ["deal_id"], name: "index_deal_investors_on_deal_id"
    t.index ["deleted_at"], name: "index_deal_investors_on_deleted_at"
    t.index ["entity_id"], name: "index_deal_investors_on_entity_id"
    t.index ["investor_entity_id"], name: "index_deal_investors_on_investor_entity_id"
    t.index ["investor_id", "deal_id"], name: "index_deal_investors_on_investor_id_and_deal_id", unique: true
    t.index ["investor_id"], name: "index_deal_investors_on_investor_id"
  end

  create_table "deals", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "name"
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.string "status", limit: 20
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "activity_list"
    t.date "start_date"
    t.date "end_date"
    t.datetime "deleted_at"
    t.integer "impressions_count", default: 0
    t.boolean "archived", default: false
    t.string "currency", limit: 10
    t.string "units", limit: 15
    t.text "properties"
    t.bigint "form_type_id"
    t.index ["deleted_at"], name: "index_deals_on_deleted_at"
    t.index ["entity_id"], name: "index_deals_on_entity_id"
    t.index ["form_type_id"], name: "index_deals_on_form_type_id"
  end

  create_table "documents", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name"
    t.string "visible_to", default: "--- []\n"
    t.string "text", default: "--- []\n"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_id", null: false
    t.datetime "deleted_at"
    t.bigint "folder_id", null: false
    t.integer "impressions_count", default: 0
    t.text "properties"
    t.bigint "form_type_id"
    t.boolean "download", default: false
    t.boolean "printing", default: false
    t.text "file_data"
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "owner_tag", limit: 20
    t.boolean "orignal", default: false
    t.bigint "user_id", null: false
    t.boolean "signature_enabled", default: false
    t.bigint "signed_by_id"
    t.bigint "from_template_id"
    t.boolean "signed_by_accept", default: false
    t.string "signature_type", limit: 100
    t.boolean "locked", default: false
    t.boolean "public_visibility", default: false
    t.index ["deleted_at"], name: "index_documents_on_deleted_at"
    t.index ["entity_id"], name: "index_documents_on_entity_id"
    t.index ["folder_id"], name: "index_documents_on_folder_id"
    t.index ["form_type_id"], name: "index_documents_on_form_type_id"
    t.index ["from_template_id"], name: "index_documents_on_from_template_id"
    t.index ["owner_type", "owner_id"], name: "index_documents_on_owner"
    t.index ["signed_by_id"], name: "index_documents_on_signed_by_id"
    t.index ["user_id"], name: "index_documents_on_user_id"
  end

  create_table "entities", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name"
    t.string "url"
    t.string "category"
    t.date "founded"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "logo_url"
    t.boolean "active", default: true
    t.string "entity_type", limit: 25
    t.integer "created_by"
    t.string "investor_categories"
    t.string "instrument_types"
    t.string "s3_bucket"
    t.datetime "deleted_at"
    t.integer "investors_count", default: 0, null: false
    t.integer "investments_count", default: 0, null: false
    t.integer "deals_count", default: 0, null: false
    t.integer "deal_investors_count", default: 0, null: false
    t.integer "documents_count", default: 0, null: false
    t.decimal "total_investments", precision: 20, default: "0"
    t.boolean "is_holdings_entity", default: false
    t.boolean "enable_documents", default: false
    t.boolean "enable_deals", default: false
    t.boolean "enable_investments", default: false
    t.boolean "enable_holdings", default: false
    t.boolean "enable_secondary_sale", default: false
    t.integer "parent_entity_id"
    t.string "currency", limit: 10
    t.date "trial_end_date"
    t.boolean "trial", default: false
    t.integer "tasks_count"
    t.integer "pending_accesses_count"
    t.integer "active_deal_id"
    t.integer "equity", default: 0
    t.integer "preferred", default: 0
    t.integer "options", default: 0
    t.boolean "percentage_in_progress", default: false
    t.decimal "per_share_value_cents", precision: 15, scale: 2, default: "0.0"
    t.text "sandbox_emails"
    t.boolean "sandbox", default: false
    t.integer "snapshot_frequency_months", default: 0
    t.date "last_snapshot_on", default: "2022-08-11"
    t.string "from_email", limit: 100
    t.boolean "enable_funds", default: false
    t.boolean "enable_inv_opportunities", default: false
    t.integer "units", default: 0
    t.boolean "enable_options", default: false
    t.boolean "enable_captable", default: false
    t.boolean "enable_investor_kyc", default: false
    t.string "sub_domain"
    t.text "logo_data"
    t.string "kyc_doc_list", limit: 100
    t.index ["deleted_at"], name: "index_entities_on_deleted_at"
    t.index ["name"], name: "index_entities_on_name", unique: true
    t.index ["parent_entity_id"], name: "index_entities_on_parent_entity_id"
    t.index ["sub_domain"], name: "index_entities_on_sub_domain", unique: true
  end

  create_table "esigns", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.integer "sequence_no"
    t.string "link"
    t.text "reason"
    t.string "status", limit: 100
    t.string "signature_type", limit: 10
    t.string "string", limit: 10
    t.boolean "completed", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "document_id"
    t.index ["document_id"], name: "index_esigns_on_document_id"
    t.index ["entity_id"], name: "index_esigns_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_esigns_on_owner"
    t.index ["user_id"], name: "index_esigns_on_user_id"
  end

  create_table "exception_tracks", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "title"
    t.text "body", size: :medium
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "excercises", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "holding_id", null: false
    t.bigint "user_id", null: false
    t.bigint "option_pool_id", null: false
    t.integer "quantity", default: 0
    t.decimal "price_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "tax_cents", precision: 20, scale: 2, default: "0.0"
    t.boolean "approved", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "tax_rate", precision: 5, scale: 2, default: "0.0"
    t.date "approved_on"
    t.text "payment_proof_data"
    t.index ["entity_id"], name: "index_excercises_on_entity_id"
    t.index ["holding_id"], name: "index_excercises_on_holding_id"
    t.index ["option_pool_id"], name: "index_excercises_on_option_pool_id"
    t.index ["user_id"], name: "index_excercises_on_user_id"
  end

  create_table "expression_of_interests", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "user_id", null: false
    t.bigint "eoi_entity_id", null: false
    t.bigint "investment_opportunity_id", null: false
    t.decimal "amount_cents", precision: 15, scale: 2, default: "0.0"
    t.boolean "approved", default: false
    t.boolean "verified", default: false
    t.decimal "allocation_percentage", precision: 5, scale: 2, default: "0.0"
    t.decimal "allocation_amount_cents", precision: 15, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "comment"
    t.index ["entity_id"], name: "index_expression_of_interests_on_entity_id"
    t.index ["eoi_entity_id"], name: "index_expression_of_interests_on_eoi_entity_id"
    t.index ["investment_opportunity_id"], name: "index_expression_of_interests_on_investment_opportunity_id"
    t.index ["user_id"], name: "index_expression_of_interests_on_user_id"
  end

  create_table "fees", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "advisor_name", limit: 30
    t.decimal "amount_cents", precision: 10, scale: 2, default: "0.0"
    t.string "amount_label", limit: 10
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.bigint "entity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "bank_account_number", limit: 40
    t.string "ifsc_code", limit: 20
    t.index ["entity_id"], name: "index_fees_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_fees_on_owner"
  end

  create_table "folders", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name"
    t.string "full_path"
    t.integer "level"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_id", null: false
    t.integer "documents_count", default: 0, null: false
    t.integer "folder_type", default: 0
    t.string "owner_type"
    t.bigint "owner_id"
    t.datetime "deleted_at"
    t.string "ancestry"
    t.index ["ancestry"], name: "index_folders_on_ancestry"
    t.index ["deleted_at"], name: "index_folders_on_deleted_at"
    t.index ["entity_id"], name: "index_folders_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_folders_on_owner"
  end

  create_table "form_custom_fields", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name", limit: 50
    t.string "field_type", limit: 20
    t.boolean "required"
    t.bigint "form_type_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "meta_data"
    t.boolean "has_attachment", default: false
    t.integer "position"
    t.text "help_text"
    t.index ["form_type_id"], name: "index_form_custom_fields_on_form_type_id"
  end

  create_table "form_types", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_id", null: false
    t.index ["entity_id"], name: "index_form_types_on_entity_id"
  end

  create_table "funding_rounds", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name"
    t.decimal "total_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.string "currency", limit: 5
    t.decimal "pre_money_valuation_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "post_money_valuation_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "entity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "amount_raised_cents", precision: 20, scale: 2, default: "0.0"
    t.string "status", default: "Open"
    t.date "closed_on"
    t.datetime "deleted_at"
    t.integer "equity", default: 0
    t.integer "preferred", default: 0
    t.integer "options", default: 0
    t.string "liq_pref_type", limit: 25
    t.string "anti_dilution", limit: 50
    t.decimal "price_cents", precision: 20, scale: 2, default: "0.0"
    t.integer "units", default: 0
    t.index ["deleted_at"], name: "index_funding_rounds_on_deleted_at"
    t.index ["entity_id"], name: "index_funding_rounds_on_entity_id"
  end

  create_table "funds", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name"
    t.decimal "committed_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.text "details"
    t.decimal "collected_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "entity_id", null: false
    t.string "tag_list"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "call_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.text "properties"
    t.bigint "form_type_id"
    t.decimal "distribution_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "funding_round_id", null: false
    t.boolean "show_valuations", default: false
    t.boolean "show_fund_ratios", default: false
    t.string "fund_signature_types", limit: 20
    t.string "investor_signature_types", limit: 20
    t.bigint "fund_signatory_id"
    t.bigint "trustee_signatory_id"
    t.string "currency", limit: 5, null: false
    t.string "commitment_doc_list", limit: 100
    t.decimal "rvpi", precision: 9, scale: 6, default: "0.0"
    t.decimal "dpi", precision: 9, scale: 6, default: "0.0"
    t.decimal "tvpi", precision: 9, scale: 6, default: "0.0"
    t.decimal "xirr", precision: 9, scale: 6, default: "0.0"
    t.decimal "moic", precision: 9, scale: 6, default: "0.0"
    t.index ["entity_id"], name: "index_funds_on_entity_id"
    t.index ["form_type_id"], name: "index_funds_on_form_type_id"
    t.index ["fund_signatory_id"], name: "index_funds_on_fund_signatory_id"
    t.index ["funding_round_id"], name: "index_funds_on_funding_round_id"
    t.index ["trustee_signatory_id"], name: "index_funds_on_trustee_signatory_id"
  end

  create_table "holding_actions", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "holding_id", null: false
    t.bigint "user_id"
    t.integer "quantity"
    t.string "action", limit: 20
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_holding_actions_on_entity_id"
    t.index ["holding_id"], name: "index_holding_actions_on_holding_id"
    t.index ["user_id"], name: "index_holding_actions_on_user_id"
  end

  create_table "holding_audit_trails", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "action", limit: 100
    t.string "parent_id", limit: 50
    t.string "owner", limit: 30
    t.bigint "quantity"
    t.integer "operation"
    t.boolean "completed", default: false
    t.string "ref_type", null: false
    t.bigint "ref_id", null: false
    t.text "comments"
    t.bigint "entity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_holding_audit_trails_on_entity_id"
    t.index ["ref_type", "ref_id"], name: "index_holding_audit_trails_on_ref"
  end

  create_table "holdings", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "entity_id", null: false
    t.integer "quantity", default: 0
    t.decimal "value_cents", precision: 20, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "investment_instrument", limit: 100
    t.bigint "investor_id", null: false
    t.string "holding_type", limit: 15, null: false
    t.bigint "investment_id"
    t.decimal "price_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "funding_round_id", null: false
    t.bigint "option_pool_id"
    t.integer "excercised_quantity", default: 0
    t.date "grant_date"
    t.integer "vested_quantity", default: 0
    t.boolean "lapsed", default: false
    t.string "employee_id", limit: 20
    t.bigint "import_upload_id"
    t.boolean "fully_vested", default: false
    t.integer "lapsed_quantity", default: 0
    t.integer "orig_grant_quantity", default: 0
    t.integer "sold_quantity", default: 0
    t.bigint "created_from_excercise_id"
    t.boolean "cancelled", default: false
    t.boolean "approved", default: false
    t.bigint "approved_by_user_id"
    t.boolean "emp_ack", default: false
    t.date "emp_ack_date"
    t.integer "uncancelled_quantity", default: 0
    t.integer "cancelled_quantity", default: 0
    t.integer "gross_avail_to_excercise_quantity", default: 0
    t.integer "unexcercised_cancelled_quantity", default: 0
    t.integer "net_avail_to_excercise_quantity", default: 0
    t.integer "gross_unvested_quantity", default: 0
    t.integer "unvested_cancelled_quantity", default: 0
    t.integer "net_unvested_quantity", default: 0
    t.boolean "manual_vesting", default: false
    t.text "properties"
    t.bigint "form_type_id"
    t.string "department", limit: 25
    t.string "option_type", limit: 12
    t.boolean "option_dilutes", default: true
    t.integer "preferred_conversion", default: 1
    t.text "grant_letter_data"
    t.index ["created_from_excercise_id"], name: "index_holdings_on_created_from_excercise_id"
    t.index ["entity_id"], name: "index_holdings_on_entity_id"
    t.index ["form_type_id"], name: "index_holdings_on_form_type_id"
    t.index ["funding_round_id"], name: "index_holdings_on_funding_round_id"
    t.index ["investment_id"], name: "index_holdings_on_investment_id"
    t.index ["investor_id"], name: "index_holdings_on_investor_id"
    t.index ["option_pool_id"], name: "index_holdings_on_option_pool_id"
    t.index ["user_id"], name: "index_holdings_on_user_id"
  end

  create_table "import_uploads", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name"
    t.bigint "entity_id", null: false
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.bigint "user_id", null: false
    t.string "import_type", limit: 50
    t.text "status"
    t.text "error_text"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "total_rows_count", default: 0
    t.integer "processed_row_count", default: 0
    t.integer "failed_row_count", default: 0
    t.text "import_file_data"
    t.text "import_results_data"
    t.index ["entity_id"], name: "index_import_uploads_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_import_uploads_on_owner"
    t.index ["user_id"], name: "index_import_uploads_on_user_id"
  end

  create_table "impressions", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "impressionable_type"
    t.integer "impressionable_id"
    t.integer "user_id"
    t.string "controller_name"
    t.string "action_name"
    t.string "view_name"
    t.string "request_hash"
    t.string "ip_address"
    t.string "session_hash"
    t.text "message"
    t.text "referrer"
    t.text "params"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["controller_name", "action_name", "ip_address"], name: "controlleraction_ip_index"
    t.index ["controller_name", "action_name", "request_hash"], name: "controlleraction_request_index"
    t.index ["controller_name", "action_name", "session_hash"], name: "controlleraction_session_index"
    t.index ["impressionable_type", "impressionable_id", "ip_address"], name: "poly_ip_index"
    t.index ["impressionable_type", "impressionable_id", "params"], name: "poly_params_request_index", length: { params: 255 }
    t.index ["impressionable_type", "impressionable_id", "request_hash"], name: "poly_request_index"
    t.index ["impressionable_type", "impressionable_id", "session_hash"], name: "poly_session_index"
    t.index ["impressionable_type", "message", "impressionable_id"], name: "impressionable_type_message_index", length: { message: 255 }
    t.index ["user_id"], name: "index_impressions_on_user_id"
  end

  create_table "interests", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.integer "entity_id"
    t.integer "quantity"
    t.decimal "price", precision: 10
    t.bigint "user_id", null: false
    t.integer "interest_entity_id"
    t.bigint "secondary_sale_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "short_listed", default: false
    t.boolean "escrow_deposited", default: false
    t.decimal "final_price", precision: 10, scale: 2, default: "0.0"
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "allocation_quantity", default: 0
    t.decimal "allocation_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "allocation_percentage", precision: 5, scale: 2, default: "0.0"
    t.boolean "finalized", default: false
    t.string "buyer_entity_name", limit: 100
    t.text "address"
    t.string "contact_name", limit: 50
    t.string "email", limit: 40
    t.string "PAN", limit: 15
    t.boolean "final_agreement", default: false
    t.text "properties"
    t.bigint "form_type_id"
    t.integer "offer_quantity", default: 0
    t.boolean "verified", default: false
    t.text "comments"
    t.text "spa_data"
    t.bigint "funding_round_id"
    t.text "signature_data"
    t.string "demat", limit: 20
    t.string "city", limit: 20
    t.string "bank_account_number", limit: 40
    t.string "ifsc_code", limit: 20
    t.bigint "final_agreement_user_id"
    t.string "custom_matching_vals"
    t.string "buyer_signature_types", limit: 20, default: ""
    t.index ["custom_matching_vals"], name: "index_interests_on_custom_matching_vals"
    t.index ["entity_id"], name: "index_interests_on_entity_id"
    t.index ["final_agreement_user_id"], name: "index_interests_on_final_agreement_user_id"
    t.index ["form_type_id"], name: "index_interests_on_form_type_id"
    t.index ["funding_round_id"], name: "index_interests_on_funding_round_id"
    t.index ["interest_entity_id"], name: "index_interests_on_interest_entity_id"
    t.index ["secondary_sale_id"], name: "index_interests_on_secondary_sale_id"
    t.index ["user_id"], name: "index_interests_on_user_id"
  end

  create_table "investment_opportunities", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "company_name", limit: 100
    t.decimal "fund_raise_amount_cents", precision: 15, scale: 2, default: "0.0"
    t.decimal "valuation_cents", precision: 15, scale: 2, default: "0.0"
    t.decimal "min_ticket_size_cents", precision: 15, scale: 2, default: "0.0"
    t.date "last_date"
    t.string "currency", limit: 10
    t.text "logo_data"
    t.text "video_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "form_type_id"
    t.decimal "eoi_amount_cents", precision: 15, scale: 2, default: "0.0"
    t.boolean "lock_allocations", default: false
    t.boolean "lock_eoi", default: false
    t.text "buyer_docs_list"
    t.text "properties"
    t.bigint "funding_round_id", null: false
    t.index ["entity_id"], name: "index_investment_opportunities_on_entity_id"
    t.index ["form_type_id"], name: "index_investment_opportunities_on_form_type_id"
    t.index ["funding_round_id"], name: "index_investment_opportunities_on_funding_round_id"
  end

  create_table "investment_snapshots", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "investment_type", limit: 100
    t.bigint "investor_id", null: false
    t.string "investor_type", limit: 100
    t.bigint "entity_id", null: false
    t.string "status", limit: 20
    t.string "investment_instrument", limit: 100
    t.integer "quantity", default: 0
    t.decimal "initial_value", precision: 20, scale: 2, default: "0.0"
    t.decimal "current_value", precision: 20, scale: 2, default: "0.0"
    t.string "category", limit: 100
    t.datetime "deleted_at"
    t.decimal "percentage_holding", precision: 5, scale: 2, default: "0.0"
    t.boolean "employee_holdings", default: false
    t.integer "diluted_quantity", default: 0
    t.decimal "diluted_percentage", precision: 5, scale: 2, default: "0.0"
    t.string "currency", limit: 10
    t.string "units", limit: 15
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "price_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "funding_round_id", null: false
    t.decimal "liquidation_preference", precision: 10, scale: 2
    t.string "spv", limit: 50
    t.date "investment_date"
    t.string "liq_pref_type", limit: 25
    t.string "anti_dilution", limit: 50
    t.date "as_of"
    t.string "tag", limit: 20
    t.bigint "investment_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_investment_snapshots_on_entity_id"
    t.index ["funding_round_id"], name: "index_investment_snapshots_on_funding_round_id"
    t.index ["investment_id"], name: "index_investment_snapshots_on_investment_id"
    t.index ["investor_id"], name: "index_investment_snapshots_on_investor_id"
  end

  create_table "investments", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "investment_type", limit: 100
    t.integer "investor_id"
    t.string "investor_type", limit: 100
    t.integer "entity_id"
    t.string "status", limit: 20
    t.string "investment_instrument", limit: 100
    t.integer "quantity", default: 0
    t.decimal "initial_value", precision: 20, scale: 2, default: "0.0"
    t.decimal "current_value", precision: 20, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "category", limit: 100
    t.datetime "deleted_at"
    t.decimal "percentage_holding", precision: 5, scale: 2, default: "0.0"
    t.boolean "employee_holdings", default: false
    t.integer "diluted_quantity", default: 0
    t.decimal "diluted_percentage", precision: 5, scale: 2, default: "0.0"
    t.string "currency", limit: 10
    t.string "units", limit: 15
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "price_cents", precision: 20, scale: 2
    t.bigint "funding_round_id"
    t.decimal "liquidation_preference", precision: 10, scale: 2
    t.bigint "aggregate_investment_id"
    t.string "spv", limit: 50
    t.date "investment_date"
    t.string "liq_pref_type", limit: 25
    t.string "anti_dilution", limit: 50
    t.integer "preferred_conversion"
    t.integer "preferred_converted_qty", default: 0
    t.text "notes"
    t.index ["aggregate_investment_id"], name: "index_investments_on_aggregate_investment_id"
    t.index ["deleted_at"], name: "index_investments_on_deleted_at"
    t.index ["entity_id"], name: "index_investments_on_entity_id"
    t.index ["funding_round_id"], name: "index_investments_on_funding_round_id"
    t.index ["investor_id"], name: "index_investments_on_investor"
  end

  create_table "investor_accesses", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.integer "investor_id"
    t.integer "user_id"
    t.string "email"
    t.boolean "approved"
    t.integer "granted_by"
    t.integer "entity_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.string "first_name", limit: 20
    t.string "last_name", limit: 20
    t.boolean "send_confirmation", default: false
    t.index ["deleted_at"], name: "index_investor_accesses_on_deleted_at"
    t.index ["email"], name: "index_investor_accesses_on_email"
    t.index ["entity_id"], name: "index_investor_accesses_on_entity_id"
    t.index ["investor_id"], name: "index_investor_accesses_on_investor_id"
    t.index ["user_id"], name: "index_investor_accesses_on_user_id"
  end

  create_table "investor_kycs", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "investor_id", null: false
    t.bigint "entity_id", null: false
    t.bigint "form_type_id"
    t.string "PAN", limit: 15
    t.text "address"
    t.string "bank_account_number", limit: 40
    t.string "ifsc_code", limit: 20
    t.boolean "bank_verified", default: false
    t.text "bank_verification_response"
    t.string "bank_verification_status"
    t.text "signature_data"
    t.text "pan_card_data"
    t.boolean "pan_verified", default: false
    t.text "pan_verification_response"
    t.string "pan_verification_status"
    t.text "comments"
    t.text "properties"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false
    t.text "video_data"
    t.string "full_name", limit: 100
    t.boolean "send_confirmation", default: false
    t.bigint "verified_by_id"
    t.index ["entity_id"], name: "index_investor_kycs_on_entity_id"
    t.index ["form_type_id"], name: "index_investor_kycs_on_form_type_id"
    t.index ["investor_id"], name: "index_investor_kycs_on_investor_id"
    t.index ["verified_by_id"], name: "index_investor_kycs_on_verified_by_id"
  end

  create_table "investor_notice_entries", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "investor_notice_id", null: false
    t.bigint "entity_id", null: false
    t.bigint "investor_id", null: false
    t.bigint "investor_entity_id", null: false
    t.boolean "active", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_investor_notice_entries_on_entity_id"
    t.index ["investor_entity_id"], name: "index_investor_notice_entries_on_investor_entity_id"
    t.index ["investor_id"], name: "index_investor_notice_entries_on_investor_id"
    t.index ["investor_notice_id"], name: "index_investor_notice_entries_on_investor_notice_id"
  end

  create_table "investor_notices", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "owner_type"
    t.bigint "owner_id"
    t.date "start_date"
    t.text "title"
    t.string "link"
    t.string "access_rights_metadata"
    t.date "end_date"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "btn_label", limit: 40
    t.boolean "generate", default: false
    t.string "category", limit: 30
    t.index ["entity_id"], name: "index_investor_notices_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_investor_notices_on_owner"
  end

  create_table "investors", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.integer "investor_entity_id"
    t.integer "entity_id"
    t.string "category", limit: 100
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "investor_name"
    t.datetime "deleted_at"
    t.date "last_interaction_date"
    t.integer "investor_access_count", default: 0
    t.integer "unapproved_investor_access_count", default: 0
    t.boolean "is_holdings_entity", default: false
    t.boolean "is_trust", default: false
    t.string "city", limit: 50
    t.text "properties"
    t.bigint "form_type_id"
    t.string "tag_list", limit: 30
    t.boolean "imported", default: false
    t.index ["deleted_at"], name: "index_investors_on_deleted_at"
    t.index ["entity_id"], name: "index_investors_on_entity_id"
    t.index ["form_type_id"], name: "index_investors_on_form_type_id"
    t.index ["investor_entity_id", "entity_id"], name: "index_investors_on_investor_entity_id_and_entity_id", unique: true
    t.index ["investor_entity_id"], name: "index_investors_on_investor_entity_id"
    t.index ["investor_name", "entity_id"], name: "index_investors_on_investor_name_and_entity_id", unique: true
  end

  create_table "messages", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_id", null: false
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.bigint "investor_id"
    t.index ["entity_id"], name: "index_messages_on_entity_id"
    t.index ["investor_id"], name: "index_messages_on_investor_id"
    t.index ["owner_type", "owner_id"], name: "index_messages_on_owner"
    t.index ["user_id"], name: "index_messages_on_user_id"
  end

  create_table "notes", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.text "details"
    t.integer "entity_id"
    t.integer "user_id"
    t.integer "investor_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.date "on"
    t.index ["deleted_at"], name: "index_notes_on_deleted_at"
    t.index ["entity_id"], name: "index_notes_on_entity_id"
    t.index ["investor_id"], name: "index_notes_on_investor_id"
    t.index ["user_id"], name: "index_notes_on_user_id"
  end

  create_table "nudges", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.text "to"
    t.text "subject"
    t.text "msg_body"
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.string "item_type"
    t.bigint "item_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "cc"
    t.text "bcc"
    t.index ["entity_id"], name: "index_nudges_on_entity_id"
    t.index ["item_type", "item_id"], name: "index_nudges_on_item"
    t.index ["user_id"], name: "index_nudges_on_user_id"
  end

  create_table "offers", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "entity_id", null: false
    t.bigint "secondary_sale_id", null: false
    t.integer "quantity", default: 0
    t.decimal "percentage", precision: 10, default: "0"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "holding_id", null: false
    t.boolean "approved", default: false
    t.integer "granted_by_user_id"
    t.bigint "investor_id", null: false
    t.string "offer_type", limit: 15
    t.string "PAN", limit: 15
    t.text "address"
    t.string "bank_account_number", limit: 40
    t.string "bank_name", limit: 50
    t.text "bank_routing_info"
    t.string "buyer_confirmation", limit: 10
    t.text "buyer_notes"
    t.bigint "buyer_id"
    t.decimal "final_price", precision: 10, scale: 2, default: "0.0"
    t.decimal "amount_cents", precision: 20, scale: 2, default: "0.0"
    t.bigint "allocation_quantity", default: 0
    t.decimal "allocation_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "allocation_percentage", precision: 5, scale: 2, default: "0.0"
    t.string "acquirer_name"
    t.boolean "verified", default: false
    t.text "comments"
    t.boolean "final_agreement", default: false
    t.bigint "interest_id"
    t.text "properties"
    t.bigint "form_type_id"
    t.text "signature_data"
    t.text "spa_data"
    t.text "id_proof_data"
    t.text "address_proof_data"
    t.text "docs_uploaded_check"
    t.boolean "auto_match", default: true
    t.text "pan_card_data"
    t.boolean "pan_verified", default: false
    t.text "pan_verification_response"
    t.string "pan_verification_status"
    t.string "ifsc_code", limit: 20
    t.boolean "bank_verified", default: false
    t.text "bank_verification_response"
    t.string "bank_verification_status"
    t.string "full_name", limit: 100
    t.string "demat", limit: 20
    t.string "city", limit: 20
    t.bigint "final_agreement_user_id"
    t.string "custom_matching_vals"
    t.boolean "esign_required", default: false
    t.boolean "esign_completed", default: false
    t.string "esign_provider", limit: 10
    t.string "esign_link"
    t.string "seller_signature_types", limit: 20, default: ""
    t.index ["buyer_id"], name: "index_offers_on_buyer_id"
    t.index ["custom_matching_vals"], name: "index_offers_on_custom_matching_vals"
    t.index ["entity_id"], name: "index_offers_on_entity_id"
    t.index ["final_agreement_user_id"], name: "index_offers_on_final_agreement_user_id"
    t.index ["form_type_id"], name: "index_offers_on_form_type_id"
    t.index ["holding_id"], name: "index_offers_on_holding_id"
    t.index ["interest_id"], name: "index_offers_on_interest_id"
    t.index ["investor_id"], name: "index_offers_on_investor_id"
    t.index ["secondary_sale_id"], name: "index_offers_on_secondary_sale_id"
    t.index ["user_id"], name: "index_offers_on_user_id"
  end

  create_table "option_details", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "option_id", null: false
    t.integer "excercised_quantity", default: 0
    t.integer "vested_quantity", default: 0
    t.boolean "lapsed", default: false
    t.boolean "fully_vested", default: false
    t.integer "lapsed_quantity", default: 0
    t.integer "gross_avail_to_excercise_quantity", default: 0
    t.integer "unexcercised_cancelled_quantity", default: 0
    t.integer "net_avail_to_excercise_quantity", default: 0
    t.integer "gross_unvested_quantity", default: 0
    t.integer "unvested_cancelled_quantity", default: 0
    t.integer "net_unvested_quantity", default: 0
    t.boolean "manual_vesting", default: false
    t.string "option_type", limit: 30
    t.boolean "option_dilutes", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["option_id"], name: "index_option_details_on_option_id"
  end

  create_table "option_pools", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name"
    t.date "start_date"
    t.bigint "number_of_options", default: 0
    t.decimal "excercise_price_cents", precision: 20, scale: 2, default: "0.0"
    t.integer "excercise_period_months", default: 0
    t.bigint "entity_id", null: false
    t.bigint "funding_round_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "allocated_quantity", default: 0
    t.bigint "excercised_quantity", default: 0
    t.bigint "vested_quantity", default: 0
    t.bigint "lapsed_quantity", default: 0
    t.boolean "approved", default: false
    t.bigint "cancelled_quantity", default: 0
    t.bigint "gross_avail_to_excercise_quantity", default: 0
    t.bigint "unexcercised_cancelled_quantity", default: 0
    t.bigint "net_avail_to_excercise_quantity", default: 0
    t.bigint "gross_unvested_quantity", default: 0
    t.bigint "unvested_cancelled_quantity", default: 0
    t.bigint "net_unvested_quantity", default: 0
    t.boolean "manual_vesting", default: false
    t.text "properties"
    t.bigint "form_type_id"
    t.text "certificate_signature_data"
    t.text "grant_letter_data"
    t.index ["entity_id"], name: "index_option_pools_on_entity_id"
    t.index ["form_type_id"], name: "index_option_pools_on_form_type_id"
    t.index ["funding_round_id"], name: "index_option_pools_on_funding_round_id"
  end

  create_table "payments", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.decimal "amount", precision: 10, scale: 2, default: "0.0", null: false
    t.string "plan", limit: 30
    t.decimal "discount", precision: 10, scale: 2, default: "0.0"
    t.string "reference_number"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["deleted_at"], name: "index_payments_on_deleted_at"
    t.index ["entity_id"], name: "index_payments_on_entity_id"
    t.index ["user_id"], name: "index_payments_on_user_id"
  end

  create_table "permissions", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.string "email"
    t.integer "permissions"
    t.bigint "entity_id", null: false
    t.bigint "granted_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "role", limit: 20
    t.index ["entity_id"], name: "index_permissions_on_entity_id"
    t.index ["granted_by_id"], name: "index_permissions_on_granted_by_id"
    t.index ["owner_type", "owner_id"], name: "index_permissions_on_owner"
    t.index ["user_id"], name: "index_permissions_on_user_id"
  end

  create_table "reminders", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.boolean "sent", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "note"
    t.date "due_date"
    t.string "email"
    t.index ["entity_id"], name: "index_reminders_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_reminders_on_owner"
  end

  create_table "roles", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name"
    t.string "resource_type"
    t.bigint "resource_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "deleted_at"
    t.index ["deleted_at"], name: "index_roles_on_deleted_at"
    t.index ["name", "resource_type", "resource_id"], name: "index_roles_on_name_and_resource_type_and_resource_id"
    t.index ["name"], name: "index_roles_on_name"
    t.index ["resource_type", "resource_id"], name: "index_roles_on_resource"
  end

  create_table "secondary_sales", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name"
    t.bigint "entity_id", null: false
    t.date "start_date"
    t.date "end_date"
    t.integer "percent_allowed", default: 0
    t.decimal "min_price", precision: 20, scale: 2
    t.decimal "max_price", precision: 20, scale: 2
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "total_offered_quantity", default: 0
    t.boolean "visible_externally", default: false
    t.datetime "deleted_at"
    t.decimal "final_price", precision: 10, scale: 2, default: "0.0"
    t.decimal "total_offered_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "total_interest_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.integer "total_interest_quantity", default: 0
    t.bigint "offer_allocation_quantity", default: 0
    t.bigint "interest_allocation_quantity", default: 0
    t.decimal "allocation_percentage", precision: 7, scale: 4, default: "0.0"
    t.decimal "allocation_offer_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "allocation_interest_amount_cents", precision: 20, scale: 2, default: "0.0"
    t.string "allocation_status", limit: 10
    t.string "price_type", limit: 15
    t.boolean "finalized", default: false
    t.text "seller_doc_list"
    t.decimal "seller_transaction_fees_pct", precision: 5, scale: 2
    t.text "properties"
    t.bigint "form_type_id"
    t.boolean "lock_allocations", default: false
    t.date "offer_end_date"
    t.string "support_email"
    t.text "buyer_doc_list"
    t.string "sale_type", limit: 10, default: "Regular"
    t.bigint "indicative_quantity", default: 0
    t.string "show_quantity", limit: 10
    t.boolean "no_offer_emails", default: false
    t.boolean "no_interest_emails", default: false
    t.boolean "manage_offers", default: false
    t.boolean "manage_interests", default: false
    t.text "spa_data"
    t.boolean "disable_pan_kyc", default: false
    t.boolean "disable_bank_kyc", default: false
    t.text "custom_matching_fields"
    t.text "cmf_allocation_percentage"
    t.string "buyer_signature_types", limit: 20, default: "0"
    t.string "seller_signature_types", limit: 20, default: "0"
    t.index ["deleted_at"], name: "index_secondary_sales_on_deleted_at"
    t.index ["entity_id"], name: "index_secondary_sales_on_entity_id"
    t.index ["form_type_id"], name: "index_secondary_sales_on_form_type_id"
  end

  create_table "share_transfers", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.bigint "from_investor_id"
    t.bigint "from_investment_id"
    t.bigint "to_investor_id"
    t.bigint "to_investment_id"
    t.integer "quantity"
    t.decimal "price", precision: 20, scale: 2, default: "0.0"
    t.date "transfer_date"
    t.bigint "transfered_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "transfer_type", limit: 10
    t.integer "to_quantity", default: 0
    t.bigint "from_holding_id"
    t.bigint "to_holding_id"
    t.bigint "to_user_id"
    t.bigint "from_user_id"
    t.index ["entity_id"], name: "index_share_transfers_on_entity_id"
    t.index ["from_holding_id"], name: "index_share_transfers_on_from_holding_id"
    t.index ["from_investment_id"], name: "index_share_transfers_on_from_investment_id"
    t.index ["from_investor_id"], name: "index_share_transfers_on_from_investor_id"
    t.index ["from_user_id"], name: "index_share_transfers_on_from_user_id"
    t.index ["to_holding_id"], name: "index_share_transfers_on_to_holding_id"
    t.index ["to_investment_id"], name: "index_share_transfers_on_to_investment_id"
    t.index ["to_investor_id"], name: "index_share_transfers_on_to_investor_id"
    t.index ["to_user_id"], name: "index_share_transfers_on_to_user_id"
    t.index ["transfered_by_id"], name: "index_share_transfers_on_transfered_by_id"
  end

  create_table "signature_workflows", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.bigint "entity_id", null: false
    t.text "state"
    t.string "status"
    t.boolean "sequential", default: false
    t.boolean "completed", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "paused", default: false
    t.bigint "document_id"
    t.index ["document_id"], name: "index_signature_workflows_on_document_id"
    t.index ["entity_id"], name: "index_signature_workflows_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_signature_workflows_on_owner"
  end

  create_table "taggings", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "tag_id"
    t.string "taggable_type"
    t.bigint "taggable_id"
    t.string "tagger_type"
    t.bigint "tagger_id"
    t.string "context", limit: 128
    t.datetime "created_at"
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

  create_table "tags", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "name", collation: "utf8mb3_bin"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "taggings_count", default: 0
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "tasks", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.text "details"
    t.bigint "entity_id", null: false
    t.bigint "for_entity_id"
    t.boolean "completed", default: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "owner_type"
    t.bigint "owner_id"
    t.bigint "form_type_id"
    t.date "due_date"
    t.integer "assigned_to_id"
    t.string "tags", limit: 50
    t.index ["entity_id"], name: "index_tasks_on_entity_id"
    t.index ["for_entity_id"], name: "index_tasks_on_for_entity_id"
    t.index ["form_type_id"], name: "index_tasks_on_form_type_id"
    t.index ["owner_type", "owner_id"], name: "index_tasks_on_owner"
    t.index ["user_id"], name: "index_tasks_on_user_id"
  end

  create_table "users", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "phone", limit: 100
    t.boolean "active", default: true
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.integer "entity_id"
    t.datetime "deleted_at"
    t.boolean "system_created", default: false
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.boolean "accept_terms", default: false
    t.boolean "whatsapp_enabled", default: false
    t.boolean "sale_notification", default: false
    t.string "curr_role", limit: 20
    t.bigint "permissions", default: 0, null: false
    t.string "dept", limit: 20
    t.text "signature_data"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["entity_id"], name: "index_users_on_entity_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "users_roles", id: false, charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "role_id"
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id"
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  create_table "valuations", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.date "valuation_date"
    t.decimal "pre_money_valuation_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "per_share_value_cents", precision: 15, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "form_type_id"
    t.string "owner_type"
    t.bigint "owner_id"
    t.text "report_data"
    t.index ["entity_id"], name: "index_valuations_on_entity_id"
    t.index ["form_type_id"], name: "index_valuations_on_form_type_id"
    t.index ["owner_type", "owner_id"], name: "index_valuations_on_owner"
  end

  create_table "versions", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "item_type"
    t.string "{:null=>false, :limit=>191}"
    t.bigint "item_id", null: false
    t.string "event", null: false
    t.string "whodunnit"
    t.text "object", size: :long
    t.datetime "created_at"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "vesting_schedules", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.integer "months_from_grant"
    t.integer "vesting_percent"
    t.bigint "option_pool_id", null: false
    t.bigint "entity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_vesting_schedules_on_entity_id"
    t.index ["option_pool_id"], name: "index_vesting_schedules_on_option_pool_id"
  end

  create_table "video_kycs", charset: "utf8", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "investor_kyc_id", null: false
    t.bigint "entity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_video_kycs_on_entity_id"
    t.index ["investor_kyc_id"], name: "index_video_kycs_on_investor_kyc_id"
    t.index ["user_id"], name: "index_video_kycs_on_user_id"
  end

  add_foreign_key "access_rights", "entities"
  add_foreign_key "access_rights", "investors", column: "access_to_investor_id"
  add_foreign_key "access_rights", "users"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "adhaar_esigns", "documents"
  add_foreign_key "adhaar_esigns", "entities"
  add_foreign_key "aggregate_investments", "entities"
  add_foreign_key "aggregate_investments", "funding_rounds"
  add_foreign_key "aggregate_investments", "investors"
  add_foreign_key "approval_responses", "approvals"
  add_foreign_key "approval_responses", "entities"
  add_foreign_key "approval_responses", "entities", column: "response_entity_id"
  add_foreign_key "approval_responses", "investors"
  add_foreign_key "approval_responses", "users", column: "response_user_id"
  add_foreign_key "approvals", "entities"
  add_foreign_key "capital_calls", "entities"
  add_foreign_key "capital_calls", "funds"
  add_foreign_key "capital_calls", "users", column: "approved_by_user_id"
  add_foreign_key "capital_commitments", "entities"
  add_foreign_key "capital_commitments", "funds"
  add_foreign_key "capital_commitments", "investors"
  add_foreign_key "capital_commitments", "users", column: "investor_signatory_id"
  add_foreign_key "capital_distribution_payments", "capital_commitments"
  add_foreign_key "capital_distribution_payments", "capital_distributions"
  add_foreign_key "capital_distribution_payments", "entities"
  add_foreign_key "capital_distribution_payments", "form_types"
  add_foreign_key "capital_distribution_payments", "funds"
  add_foreign_key "capital_distribution_payments", "investors"
  add_foreign_key "capital_distributions", "entities"
  add_foreign_key "capital_distributions", "form_types"
  add_foreign_key "capital_distributions", "funds"
  add_foreign_key "capital_distributions", "users", column: "approved_by_user_id"
  add_foreign_key "capital_remittances", "capital_calls"
  add_foreign_key "capital_remittances", "capital_commitments"
  add_foreign_key "capital_remittances", "entities"
  add_foreign_key "capital_remittances", "funds"
  add_foreign_key "capital_remittances", "investors"
  add_foreign_key "deal_activities", "deal_investors"
  add_foreign_key "deal_activities", "deals"
  add_foreign_key "deal_docs", "deal_activities"
  add_foreign_key "deal_docs", "deal_investors"
  add_foreign_key "deal_docs", "deals"
  add_foreign_key "deal_docs", "users"
  add_foreign_key "deal_investors", "deals"
  add_foreign_key "deal_investors", "entities"
  add_foreign_key "deal_investors", "investors"
  add_foreign_key "deals", "entities"
  add_foreign_key "deals", "form_types"
  add_foreign_key "documents", "documents", column: "from_template_id"
  add_foreign_key "documents", "folders"
  add_foreign_key "documents", "form_types"
  add_foreign_key "documents", "users"
  add_foreign_key "documents", "users", column: "signed_by_id"
  add_foreign_key "esigns", "documents"
  add_foreign_key "esigns", "entities"
  add_foreign_key "esigns", "users"
  add_foreign_key "excercises", "entities"
  add_foreign_key "excercises", "holdings"
  add_foreign_key "excercises", "option_pools"
  add_foreign_key "excercises", "users"
  add_foreign_key "expression_of_interests", "entities"
  add_foreign_key "expression_of_interests", "entities", column: "eoi_entity_id"
  add_foreign_key "expression_of_interests", "investment_opportunities"
  add_foreign_key "expression_of_interests", "users"
  add_foreign_key "fees", "entities"
  add_foreign_key "folders", "entities"
  add_foreign_key "form_custom_fields", "form_types"
  add_foreign_key "form_types", "entities"
  add_foreign_key "funding_rounds", "entities"
  add_foreign_key "funds", "entities"
  add_foreign_key "funds", "funding_rounds"
  add_foreign_key "funds", "users", column: "fund_signatory_id"
  add_foreign_key "funds", "users", column: "trustee_signatory_id"
  add_foreign_key "holding_actions", "entities"
  add_foreign_key "holding_actions", "holdings"
  add_foreign_key "holding_actions", "users"
  add_foreign_key "holding_audit_trails", "entities"
  add_foreign_key "holdings", "entities"
  add_foreign_key "holdings", "excercises", column: "created_from_excercise_id"
  add_foreign_key "holdings", "form_types"
  add_foreign_key "holdings", "investments"
  add_foreign_key "holdings", "investors"
  add_foreign_key "holdings", "option_pools"
  add_foreign_key "holdings", "users"
  add_foreign_key "import_uploads", "entities"
  add_foreign_key "import_uploads", "users"
  add_foreign_key "interests", "form_types"
  add_foreign_key "interests", "funding_rounds"
  add_foreign_key "interests", "secondary_sales"
  add_foreign_key "interests", "users"
  add_foreign_key "interests", "users", column: "final_agreement_user_id"
  add_foreign_key "investment_opportunities", "entities"
  add_foreign_key "investment_opportunities", "form_types"
  add_foreign_key "investment_opportunities", "funding_rounds"
  add_foreign_key "investment_snapshots", "entities"
  add_foreign_key "investment_snapshots", "funding_rounds"
  add_foreign_key "investment_snapshots", "investments"
  add_foreign_key "investment_snapshots", "investors"
  add_foreign_key "investments", "aggregate_investments"
  add_foreign_key "investments", "funding_rounds"
  add_foreign_key "investor_kycs", "entities"
  add_foreign_key "investor_kycs", "form_types"
  add_foreign_key "investor_kycs", "investors"
  add_foreign_key "investor_kycs", "users", column: "verified_by_id"
  add_foreign_key "investor_notice_entries", "entities"
  add_foreign_key "investor_notice_entries", "entities", column: "investor_entity_id"
  add_foreign_key "investor_notice_entries", "investor_notices"
  add_foreign_key "investor_notice_entries", "investors"
  add_foreign_key "investor_notices", "entities"
  add_foreign_key "investors", "form_types"
  add_foreign_key "messages", "investors"
  add_foreign_key "messages", "users"
  add_foreign_key "nudges", "entities"
  add_foreign_key "nudges", "users"
  add_foreign_key "offers", "entities"
  add_foreign_key "offers", "form_types"
  add_foreign_key "offers", "holdings"
  add_foreign_key "offers", "interests"
  add_foreign_key "offers", "secondary_sales"
  add_foreign_key "offers", "users"
  add_foreign_key "offers", "users", column: "final_agreement_user_id"
  add_foreign_key "option_details", "holdings", column: "option_id"
  add_foreign_key "option_pools", "entities"
  add_foreign_key "option_pools", "form_types"
  add_foreign_key "option_pools", "funding_rounds"
  add_foreign_key "payments", "entities"
  add_foreign_key "payments", "users"
  add_foreign_key "permissions", "entities"
  add_foreign_key "permissions", "users"
  add_foreign_key "permissions", "users", column: "granted_by_id"
  add_foreign_key "reminders", "entities"
  add_foreign_key "secondary_sales", "entities"
  add_foreign_key "secondary_sales", "form_types"
  add_foreign_key "share_transfers", "entities"
  add_foreign_key "share_transfers", "holdings", column: "from_holding_id"
  add_foreign_key "share_transfers", "holdings", column: "to_holding_id"
  add_foreign_key "share_transfers", "investments", column: "from_investment_id"
  add_foreign_key "share_transfers", "investments", column: "to_investment_id"
  add_foreign_key "share_transfers", "investors", column: "from_investor_id"
  add_foreign_key "share_transfers", "investors", column: "to_investor_id"
  add_foreign_key "share_transfers", "users", column: "from_user_id"
  add_foreign_key "share_transfers", "users", column: "to_user_id"
  add_foreign_key "share_transfers", "users", column: "transfered_by_id"
  add_foreign_key "signature_workflows", "documents"
  add_foreign_key "signature_workflows", "entities"
  add_foreign_key "taggings", "tags"
  add_foreign_key "tasks", "entities"
  add_foreign_key "tasks", "form_types"
  add_foreign_key "tasks", "users"
  add_foreign_key "valuations", "entities"
  add_foreign_key "valuations", "form_types"
  add_foreign_key "vesting_schedules", "entities"
  add_foreign_key "vesting_schedules", "option_pools"
  add_foreign_key "video_kycs", "entities"
  add_foreign_key "video_kycs", "investor_kycs"
  add_foreign_key "video_kycs", "users"
end
