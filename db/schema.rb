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

ActiveRecord::Schema[7.0].define(version: 2022_06_21_022553) do
  create_table "abraham_histories", id: :integer, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "access_rights", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.string "access_to_email", limit: 30
    t.integer "access_to_investor_id"
    t.string "access_type", limit: 15
    t.string "metadata"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_id", null: false
    t.string "access_to_category", limit: 20
    t.datetime "deleted_at"
    t.index ["access_to_investor_id"], name: "index_access_rights_on_access_to_investor_id"
    t.index ["deleted_at"], name: "index_access_rights_on_deleted_at"
    t.index ["entity_id"], name: "index_access_rights_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_access_rights_on_owner"
  end

  create_table "action_text_rich_texts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.text "body", size: :long
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_admin_comments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "active_storage_attachments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "active_storage_variant_records", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activities", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "admin_users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "aggregate_investments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.index ["entity_id"], name: "index_aggregate_investments_on_entity_id"
    t.index ["investor_id"], name: "index_aggregate_investments_on_investor_id"
  end

  create_table "audits", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "deal_activities", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "deal_docs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "deal_investors", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.index ["deal_id"], name: "index_deal_investors_on_deal_id"
    t.index ["deleted_at"], name: "index_deal_investors_on_deleted_at"
    t.index ["entity_id"], name: "index_deal_investors_on_entity_id"
    t.index ["investor_entity_id"], name: "index_deal_investors_on_investor_entity_id"
    t.index ["investor_id", "deal_id"], name: "index_deal_investors_on_investor_id_and_deal_id", unique: true
    t.index ["investor_id"], name: "index_deal_investors_on_investor_id"
  end

  create_table "deals", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "documents", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.string "visible_to", default: "--- []\n"
    t.string "text", default: "--- []\n"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "file_file_name"
    t.string "file_content_type"
    t.bigint "file_file_size"
    t.datetime "file_updated_at"
    t.bigint "entity_id", null: false
    t.datetime "deleted_at"
    t.bigint "folder_id", null: false
    t.integer "impressions_count", default: 0
    t.text "properties"
    t.bigint "form_type_id"
    t.boolean "download", default: false
    t.boolean "printing", default: false
    t.index ["deleted_at"], name: "index_documents_on_deleted_at"
    t.index ["entity_id"], name: "index_documents_on_entity_id"
    t.index ["folder_id"], name: "index_documents_on_folder_id"
    t.index ["form_type_id"], name: "index_documents_on_form_type_id"
  end

  create_table "entities", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.string "url"
    t.string "category"
    t.date "founded"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "logo_url"
    t.boolean "active", default: true
    t.string "entity_type", limit: 15
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
    t.string "units", limit: 15
    t.date "trial_end_date"
    t.boolean "trial", default: false
    t.integer "tasks_count"
    t.integer "pending_accesses_count"
    t.integer "active_deal_id"
    t.integer "equity", default: 0
    t.integer "preferred", default: 0
    t.integer "options", default: 0
    t.boolean "percentage_in_progress", default: false
    t.index ["deleted_at"], name: "index_entities_on_deleted_at"
    t.index ["name"], name: "index_entities_on_name", unique: true
    t.index ["parent_entity_id"], name: "index_entities_on_parent_entity_id"
  end

  create_table "exception_tracks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "title"
    t.text "body", size: :medium
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "excercises", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.index ["entity_id"], name: "index_excercises_on_entity_id"
    t.index ["holding_id"], name: "index_excercises_on_holding_id"
    t.index ["option_pool_id"], name: "index_excercises_on_option_pool_id"
    t.index ["user_id"], name: "index_excercises_on_user_id"
  end

  create_table "folders", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.integer "parent_folder_id"
    t.text "full_path"
    t.integer "level"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_id", null: false
    t.integer "documents_count", default: 0, null: false
    t.string "path_ids"
    t.index ["entity_id"], name: "index_folders_on_entity_id"
    t.index ["parent_folder_id"], name: "index_folders_on_parent_folder_id"
  end

  create_table "form_custom_fields", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "form_types", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "entity_id", null: false
    t.index ["entity_id"], name: "index_form_types_on_entity_id"
  end

  create_table "funding_rounds", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.index ["deleted_at"], name: "index_funding_rounds_on_deleted_at"
    t.index ["entity_id"], name: "index_funding_rounds_on_entity_id"
  end

  create_table "holding_actions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "holding_audit_trails", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "holdings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.index ["created_from_excercise_id"], name: "index_holdings_on_created_from_excercise_id"
    t.index ["entity_id"], name: "index_holdings_on_entity_id"
    t.index ["form_type_id"], name: "index_holdings_on_form_type_id"
    t.index ["funding_round_id"], name: "index_holdings_on_funding_round_id"
    t.index ["investment_id"], name: "index_holdings_on_investment_id"
    t.index ["investor_id"], name: "index_holdings_on_investor_id"
    t.index ["option_pool_id"], name: "index_holdings_on_option_pool_id"
    t.index ["user_id"], name: "index_holdings_on_user_id"
  end

  create_table "import_uploads", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.index ["entity_id"], name: "index_import_uploads_on_entity_id"
    t.index ["owner_type", "owner_id"], name: "index_import_uploads_on_owner"
    t.index ["user_id"], name: "index_import_uploads_on_user_id"
  end

  create_table "impressions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "interests", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.index ["entity_id"], name: "index_interests_on_entity_id"
    t.index ["form_type_id"], name: "index_interests_on_form_type_id"
    t.index ["interest_entity_id"], name: "index_interests_on_interest_entity_id"
    t.index ["secondary_sale_id"], name: "index_interests_on_secondary_sale_id"
    t.index ["user_id"], name: "index_interests_on_user_id"
  end

  create_table "investments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.decimal "liquidation_preference", precision: 4, scale: 2
    t.bigint "aggregate_investment_id"
    t.string "spv", limit: 50
    t.index ["aggregate_investment_id"], name: "index_investments_on_aggregate_investment_id"
    t.index ["deleted_at"], name: "index_investments_on_deleted_at"
    t.index ["entity_id"], name: "index_investments_on_entity_id"
    t.index ["funding_round_id"], name: "index_investments_on_funding_round_id"
    t.index ["investor_id"], name: "index_investments_on_investor"
  end

  create_table "investor_accesses", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.index ["deleted_at"], name: "index_investor_accesses_on_deleted_at"
    t.index ["email"], name: "index_investor_accesses_on_email"
    t.index ["entity_id"], name: "index_investor_accesses_on_entity_id"
    t.index ["investor_id"], name: "index_investor_accesses_on_investor_id"
    t.index ["user_id"], name: "index_investor_accesses_on_user_id"
  end

  create_table "investors", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.index ["deleted_at"], name: "index_investors_on_deleted_at"
    t.index ["entity_id"], name: "index_investors_on_entity_id"
    t.index ["form_type_id"], name: "index_investors_on_form_type_id"
    t.index ["investor_entity_id", "entity_id"], name: "index_investors_on_investor_entity_id_and_entity_id", unique: true
    t.index ["investor_entity_id"], name: "index_investors_on_investor_entity_id"
    t.index ["investor_name", "entity_id"], name: "index_investors_on_investor_name_and_entity_id", unique: true
  end

  create_table "messages", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "notes", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "nudges", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "offers", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.string "first_name"
    t.string "middle_name"
    t.string "last_name"
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
    t.index ["buyer_id"], name: "index_offers_on_buyer_id"
    t.index ["entity_id"], name: "index_offers_on_entity_id"
    t.index ["form_type_id"], name: "index_offers_on_form_type_id"
    t.index ["holding_id"], name: "index_offers_on_holding_id"
    t.index ["interest_id"], name: "index_offers_on_interest_id"
    t.index ["investor_id"], name: "index_offers_on_investor_id"
    t.index ["secondary_sale_id"], name: "index_offers_on_secondary_sale_id"
    t.index ["user_id"], name: "index_offers_on_user_id"
  end

  create_table "option_pools", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.index ["entity_id"], name: "index_option_pools_on_entity_id"
    t.index ["form_type_id"], name: "index_option_pools_on_form_type_id"
    t.index ["funding_round_id"], name: "index_option_pools_on_funding_round_id"
  end

  create_table "payments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "roles", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "secondary_sales", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.index ["deleted_at"], name: "index_secondary_sales_on_deleted_at"
    t.index ["entity_id"], name: "index_secondary_sales_on_entity_id"
    t.index ["form_type_id"], name: "index_secondary_sales_on_form_type_id"
  end

  create_table "taggings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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

  create_table "tags", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name", collation: "utf8_bin"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "taggings_count", default: 0
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "tasks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.index ["entity_id"], name: "index_tasks_on_entity_id"
    t.index ["for_entity_id"], name: "index_tasks_on_for_entity_id"
    t.index ["form_type_id"], name: "index_tasks_on_form_type_id"
    t.index ["owner_type", "owner_id"], name: "index_tasks_on_owner"
    t.index ["user_id"], name: "index_tasks_on_user_id"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
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
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["entity_id"], name: "index_users_on_entity_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "users_roles", id: false, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "role_id"
    t.index ["role_id"], name: "index_users_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_users_roles_on_user_id_and_role_id"
    t.index ["user_id"], name: "index_users_roles_on_user_id"
  end

  create_table "valuations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "entity_id", null: false
    t.date "valuation_date"
    t.decimal "pre_money_valuation_cents", precision: 20, scale: 2, default: "0.0"
    t.decimal "per_share_value_cents", precision: 15, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "form_type_id"
    t.index ["entity_id"], name: "index_valuations_on_entity_id"
    t.index ["form_type_id"], name: "index_valuations_on_form_type_id"
  end

  create_table "versions", charset: "utf8mb4", collation: "utf8mb4_general_ci", force: :cascade do |t|
    t.string "item_type"
    t.string "{:null=>false, :limit=>191}"
    t.bigint "item_id", null: false
    t.string "event", null: false
    t.string "whodunnit"
    t.text "object", size: :long
    t.datetime "created_at"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "vesting_schedules", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "months_from_grant"
    t.integer "vesting_percent"
    t.bigint "option_pool_id", null: false
    t.bigint "entity_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_vesting_schedules_on_entity_id"
    t.index ["option_pool_id"], name: "index_vesting_schedules_on_option_pool_id"
  end

  add_foreign_key "access_rights", "entities"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "aggregate_investments", "entities"
  add_foreign_key "aggregate_investments", "investors"
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
  add_foreign_key "documents", "folders"
  add_foreign_key "documents", "form_types"
  add_foreign_key "excercises", "entities"
  add_foreign_key "excercises", "holdings"
  add_foreign_key "excercises", "option_pools"
  add_foreign_key "excercises", "users"
  add_foreign_key "folders", "entities"
  add_foreign_key "form_custom_fields", "form_types"
  add_foreign_key "form_types", "entities"
  add_foreign_key "funding_rounds", "entities"
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
  add_foreign_key "interests", "secondary_sales"
  add_foreign_key "interests", "users"
  add_foreign_key "investments", "aggregate_investments"
  add_foreign_key "investments", "funding_rounds"
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
  add_foreign_key "option_pools", "entities"
  add_foreign_key "option_pools", "form_types"
  add_foreign_key "option_pools", "funding_rounds"
  add_foreign_key "payments", "entities"
  add_foreign_key "payments", "users"
  add_foreign_key "secondary_sales", "entities"
  add_foreign_key "secondary_sales", "form_types"
  add_foreign_key "taggings", "tags"
  add_foreign_key "tasks", "entities"
  add_foreign_key "tasks", "form_types"
  add_foreign_key "tasks", "users"
  add_foreign_key "valuations", "entities"
  add_foreign_key "valuations", "form_types"
  add_foreign_key "vesting_schedules", "entities"
  add_foreign_key "vesting_schedules", "option_pools"
end
