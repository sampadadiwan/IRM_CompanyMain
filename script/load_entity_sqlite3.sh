#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG
############################################

ADAPTER="${ADAPTER:-mysql2}"
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-root}"
MYSQL_DB="${MYSQL_DB:-IRM_development}"
SOURCE_SQLITE_DB="${SOURCE_SQLITE_DB:-tmp/test.sqlite3}"
ENTITY_ID="${ENTITY_ID:-}"

if [ -z "$ENTITY_ID" ]; then
  echo "Error: ENTITY_ID is required."
  echo "Usage: ENTITY_ID=123 $0"
  exit 1
fi

SQLITE_DB="${SQLITE_DB:-/tmp/irm_entity_${ENTITY_ID}.sqlite3}"

START_TIME=$(date +%s)

log_step_time() {
  local step_name="$1"
  local step_start="$2"
  local now=$(date +%s)
  local diff=$((now - step_start))
  local total_diff=$((now - START_TIME))
  echo ">>> [TIME] ${step_name} took ${diff}s (Cumulative: ${total_diff}s)"
}

mysql_cmd() {
  MYSQL_PWD="$MYSQL_PASS" mysql \
    --host="$MYSQL_HOST" \
    --port="$MYSQL_PORT" \
    --user="$MYSQL_USER" \
    --database="$MYSQL_DB" \
    --batch --raw --skip-column-names \
    --quick \
    --net_buffer_length=16384 \
    "$@"
}

############################################
# TABLE DEFINITIONS
############################################
TABLES=("access_rights" "account_entries" "aggregate_portfolio_investments" "call_fees" "capital_calls" "capital_commitments" "capital_distribution_payments" "capital_distributions" "capital_remittance_payments" "capital_remittances" "commitment_adjustments" "distribution_fees" "documents" "e_signatures" "entities" "exchange_rates" "fees" "folders" "fund_ratios" "fund_unit_settings" "fund_unit_transfers" "fund_units" "funds" "interests" "investment_instruments" "investment_opportunities" "investments" "investor_kpi_mappings" "investor_kycs" "investors" "kpi_reports" "kpis" "kyc_data" "notes" "offers" "portfolio_attributions" "portfolio_cashflows" "portfolio_investments" "scenario_investments" "secondary_sales" "stock_adjustments" "stock_conversions" "tasks" "users" "valuations")
COLS_access_rights=("id" "access_to_category" "access_to_email" "access_to_investor_id" "access_type" "cascade" "created_at" "deleted_at" "entity_id" "granted_by_id" "metadata" "notify" "owner_id" "owner_type" "parent_access_right_id" "permissions" "updated_at" "user_id")
TEXT_COLS_access_rights=("access_to_category" "access_to_email" "access_type" "metadata" "owner_type")
SCHEMA_access_rights='
  "id" BIGINT PRIMARY KEY,
  "access_to_category" VARCHAR(255),
  "access_to_email" VARCHAR(255),
  "access_to_investor_id" BIGINT,
  "access_type" VARCHAR(255),
  "cascade" BOOLEAN,
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "entity_id" BIGINT,
  "granted_by_id" BIGINT,
  "metadata" VARCHAR(255),
  "notify" BOOLEAN,
  "owner_id" BIGINT,
  "owner_type" VARCHAR(255),
  "parent_access_right_id" INTEGER,
  "permissions" BIGINT,
  "updated_at" DATETIME,
  "user_id" BIGINT
'
INDEX_access_rights='
  CREATE INDEX "idx_access_rights_access_to_investor_id" ON "access_rights"("access_to_investor_id");
  CREATE INDEX "idx_access_rights_deleted_at" ON "access_rights"("deleted_at");
  CREATE INDEX "idx_access_rights_entity_id" ON "access_rights"("entity_id");
  CREATE INDEX "idx_access_rights_granted_by_id" ON "access_rights"("granted_by_id");
  CREATE INDEX "idx_access_rights_owner_type_owner_id" ON "access_rights"("owner_type", "owner_id");
  CREATE INDEX "idx_access_rights_user_id" ON "access_rights"("user_id");
'
COLS_account_entries=("id" "allocation_run_id" "amount_cents" "capital_commitment_id" "commitment_name" "created_at" "cumulative" "deleted_at" "entity_id" "entry_type" "exchange_rate_id" "explanation" "folio_amount_cents" "folio_id" "form_type_id" "fund_formula_id" "fund_id" "generated" "generated_deleted" "import_upload_id" "investor_id" "json_fields" "name" "notes" "parent_id" "parent_name" "parent_type" "period" "ref_id" "reporting_date" "rule_for" "tracking_amount_cents" "updated_at")
TEXT_COLS_account_entries=("commitment_name" "entry_type" "explanation" "folio_id" "json_fields" "name" "notes" "parent_name" "parent_type" "period" "rule_for")
SCHEMA_account_entries='
  "id" BIGINT PRIMARY KEY,
  "allocation_run_id" BIGINT,
  "amount_cents" DECIMAL(20,2),
  "capital_commitment_id" BIGINT,
  "commitment_name" VARCHAR(255),
  "created_at" DATETIME,
  "cumulative" BOOLEAN,
  "deleted_at" DATETIME,
  "entity_id" BIGINT,
  "entry_type" VARCHAR(255),
  "exchange_rate_id" BIGINT,
  "explanation" TEXT,
  "folio_amount_cents" DECIMAL(20,2),
  "folio_id" VARCHAR(255),
  "form_type_id" BIGINT,
  "fund_formula_id" BIGINT,
  "fund_id" BIGINT,
  "generated" BOOLEAN,
  "generated_deleted" DATETIME,
  "import_upload_id" BIGINT,
  "investor_id" BIGINT,
  "json_fields" JSON,
  "name" VARCHAR(255),
  "notes" TEXT,
  "parent_id" BIGINT,
  "parent_name" VARCHAR(255),
  "parent_type" VARCHAR(255),
  "period" VARCHAR(255),
  "ref_id" INTEGER,
  "reporting_date" DATE,
  "rule_for" VARCHAR(255),
  "tracking_amount_cents" DECIMAL(20,2),
  "updated_at" DATETIME
'
INDEX_account_entries='
  CREATE INDEX "idx_account_entries_allocation_run_id" ON "account_entries"("allocation_run_id");
  CREATE INDEX "idx_account_entries_capital_commitment_id_name_reporting_date" ON "account_entries"("capital_commitment_id", "name", "reporting_date");
  CREATE INDEX "idx_account_entries_capital_commitment_id" ON "account_entries"("capital_commitment_id");
  CREATE INDEX "idx_account_entries_entity_id" ON "account_entries"("entity_id");
  CREATE INDEX "idx_account_entries_exchange_rate_id" ON "account_entries"("exchange_rate_id");
  CREATE INDEX "idx_account_entries_form_type_id" ON "account_entries"("form_type_id");
  CREATE INDEX "idx_account_entries_fund_formula_id" ON "account_entries"("fund_formula_id");
  CREATE INDEX "idx_account_entries_fund_id_entry_type_reporting_date" ON "account_entries"("fund_id", "entry_type", "reporting_date");
  CREATE INDEX "idx_account_entries_fund_id_generated_reporting_date_fund_formula_id" ON "account_entries"("fund_id", "generated", "reporting_date", "fund_formula_id");
  CREATE INDEX "idx_account_entries_fund_id_name_reporting_date" ON "account_entries"("fund_id", "name", "reporting_date");
  CREATE INDEX "idx_account_entries_fund_id_reporting_date_fund_formula_id_deleted_at" ON "account_entries"("fund_id", "reporting_date", "fund_formula_id", "deleted_at");
  CREATE INDEX "idx_account_entries_fund_id" ON "account_entries"("fund_id");
  CREATE INDEX "idx_account_entries_import_upload_id" ON "account_entries"("import_upload_id");
  CREATE INDEX "idx_account_entries_investor_id" ON "account_entries"("investor_id");
  CREATE INDEX "idx_account_entries_parent_type_parent_id_fund_id_name_deleted_at_cumulative" ON "account_entries"("parent_type", "parent_id", "fund_id", "name", "deleted_at", "cumulative");
  CREATE INDEX "idx_account_entries_reporting_date" ON "account_entries"("reporting_date");
'
COLS_aggregate_portfolio_investments=("id" "avg_cost_cents" "bought_amount_cents" "bought_quantity" "cost_of_remaining_cents" "cost_of_sold_cents" "created_at" "deleted_at" "document_folder_id" "entity_id" "ex_expenses_amount_cents" "fmv_cents" "form_type_id" "fund_id" "gain_cents" "instrument_currency_cost_of_remaining_cents" "instrument_currency_fmv_cents" "instrument_currency_unrealized_gain_cents" "investment_domicile" "investment_instrument_id" "investment_type" "net_bought_amount_cents" "orignal_id" "portfolio_company_id" "portfolio_company_name" "portfolio_income_cents" "quantity" "show_portfolio" "snapshot" "snapshot_date" "sold_amount_cents" "sold_quantity" "tracking_bought_amount_cents" "tracking_fmv_cents" "tracking_sold_amount_cents" "transfer_amount_cents" "transfer_quantity" "unrealized_gain_cents" "updated_at")
TEXT_COLS_aggregate_portfolio_investments=("investment_domicile" "investment_type" "portfolio_company_name")
SCHEMA_aggregate_portfolio_investments='
  "id" BIGINT PRIMARY KEY,
  "avg_cost_cents" DECIMAL(20,2),
  "bought_amount_cents" DECIMAL(20,2),
  "bought_quantity" DECIMAL(20,2),
  "cost_of_remaining_cents" DECIMAL(20,2),
  "cost_of_sold_cents" DECIMAL(20,2),
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "document_folder_id" BIGINT,
  "entity_id" BIGINT,
  "ex_expenses_amount_cents" DECIMAL(20,2),
  "fmv_cents" DECIMAL(20,2),
  "form_type_id" BIGINT,
  "fund_id" BIGINT,
  "gain_cents" DECIMAL(20,2),
  "instrument_currency_cost_of_remaining_cents" DECIMAL(20,2),
  "instrument_currency_fmv_cents" DECIMAL(20,2),
  "instrument_currency_unrealized_gain_cents" DECIMAL(20,2),
  "investment_domicile" VARCHAR(255),
  "investment_instrument_id" BIGINT,
  "investment_type" VARCHAR(255),
  "net_bought_amount_cents" DECIMAL(20,2),
  "orignal_id" BIGINT,
  "portfolio_company_id" BIGINT,
  "portfolio_company_name" VARCHAR(255),
  "portfolio_income_cents" DECIMAL(20,2),
  "quantity" DECIMAL(20,2),
  "show_portfolio" BOOLEAN,
  "snapshot" BOOLEAN,
  "snapshot_date" DATE,
  "sold_amount_cents" DECIMAL(20,2),
  "sold_quantity" DECIMAL(20,2),
  "tracking_bought_amount_cents" DECIMAL(20,2),
  "tracking_fmv_cents" DECIMAL(20,2),
  "tracking_sold_amount_cents" DECIMAL(20,2),
  "transfer_amount_cents" DECIMAL(20,2),
  "transfer_quantity" DECIMAL(20,2),
  "unrealized_gain_cents" DECIMAL(20,2),
  "updated_at" DATETIME
'
INDEX_aggregate_portfolio_investments='
  CREATE INDEX "idx_aggregate_portfolio_investments_deleted_at" ON "aggregate_portfolio_investments"("deleted_at");
  CREATE INDEX "idx_aggregate_portfolio_investments_document_folder_id" ON "aggregate_portfolio_investments"("document_folder_id");
  CREATE INDEX "idx_aggregate_portfolio_investments_entity_id" ON "aggregate_portfolio_investments"("entity_id");
  CREATE INDEX "idx_aggregate_portfolio_investments_form_type_id" ON "aggregate_portfolio_investments"("form_type_id");
  CREATE INDEX "idx_aggregate_portfolio_investments_fund_id" ON "aggregate_portfolio_investments"("fund_id");
  CREATE INDEX "idx_aggregate_portfolio_investments_investment_instrument_id" ON "aggregate_portfolio_investments"("investment_instrument_id");
  CREATE INDEX "idx_aggregate_portfolio_investments_portfolio_company_id" ON "aggregate_portfolio_investments"("portfolio_company_id");
  CREATE INDEX "idx_aggregate_portfolio_investments_snapshot_date" ON "aggregate_portfolio_investments"("snapshot_date");
'
COLS_call_fees=("id" "capital_call_id" "created_at" "end_date" "entity_id" "fee_type" "formula" "fund_id" "name" "notes" "start_date" "updated_at")
TEXT_COLS_call_fees=("fee_type" "name" "notes")
SCHEMA_call_fees='
  "id" BIGINT PRIMARY KEY,
  "capital_call_id" BIGINT,
  "created_at" DATETIME,
  "end_date" DATE,
  "entity_id" BIGINT,
  "fee_type" VARCHAR(255),
  "formula" BOOLEAN,
  "fund_id" BIGINT,
  "name" VARCHAR(255),
  "notes" VARCHAR(255),
  "start_date" DATE,
  "updated_at" DATETIME
'
INDEX_call_fees='
  CREATE INDEX "idx_call_fees_capital_call_id" ON "call_fees"("capital_call_id");
  CREATE INDEX "idx_call_fees_entity_id" ON "call_fees"("entity_id");
  CREATE INDEX "idx_call_fees_fund_id" ON "call_fees"("fund_id");
'
COLS_capital_calls=("id" "amount_to_be_called_cents" "approved" "approved_by_user_id" "call_amount_cents" "call_basis" "call_date" "capital_fee_cents" "close_percentages" "collected_amount_cents" "created_at" "deleted_at" "document_folder_id" "due_date" "entity_id" "fee_formula_ids" "form_type_id" "fund_closes" "fund_id" "generate_remittances" "generate_remittances_verified" "import_upload_id" "json_fields" "manual_generation" "name" "notes" "other_fee_cents" "percentage_called" "send_call_notice_flag" "send_payment_notification_flag" "unit_prices" "updated_at")
TEXT_COLS_capital_calls=("call_basis" "close_percentages" "fee_formula_ids" "fund_closes" "json_fields" "name" "notes" "unit_prices")
SCHEMA_capital_calls='
  "id" BIGINT PRIMARY KEY,
  "amount_to_be_called_cents" DECIMAL(20,2),
  "approved" BOOLEAN,
  "approved_by_user_id" BIGINT,
  "call_amount_cents" DECIMAL(20,2),
  "call_basis" VARCHAR(255),
  "call_date" DATE,
  "capital_fee_cents" DECIMAL(20,2),
  "close_percentages" TEXT,
  "collected_amount_cents" DECIMAL(20,2),
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "document_folder_id" BIGINT,
  "due_date" DATE,
  "entity_id" BIGINT,
  "fee_formula_ids" VARCHAR(255),
  "form_type_id" BIGINT,
  "fund_closes" VARCHAR(255),
  "fund_id" BIGINT,
  "generate_remittances" BOOLEAN,
  "generate_remittances_verified" BOOLEAN,
  "import_upload_id" BIGINT,
  "json_fields" JSON,
  "manual_generation" BOOLEAN,
  "name" VARCHAR(255),
  "notes" TEXT,
  "other_fee_cents" DECIMAL(20,2),
  "percentage_called" DECIMAL(20,2),
  "send_call_notice_flag" BOOLEAN,
  "send_payment_notification_flag" BOOLEAN,
  "unit_prices" TEXT,
  "updated_at" DATETIME
'
INDEX_capital_calls='
  CREATE INDEX "idx_capital_calls_approved_by_user_id" ON "capital_calls"("approved_by_user_id");
  CREATE INDEX "idx_capital_calls_deleted_at" ON "capital_calls"("deleted_at");
  CREATE INDEX "idx_capital_calls_document_folder_id" ON "capital_calls"("document_folder_id");
  CREATE INDEX "idx_capital_calls_entity_id" ON "capital_calls"("entity_id");
  CREATE INDEX "idx_capital_calls_form_type_id" ON "capital_calls"("form_type_id");
  CREATE INDEX "idx_capital_calls_fund_id" ON "capital_calls"("fund_id");
'
COLS_capital_commitments=("id" "adjustment_amount_cents" "adjustment_folio_amount_cents" "arrear_amount_cents" "arrear_folio_amount_cents" "call_amount_cents" "collected_amount_cents" "commitment_date" "committed_amount_cents" "compliant" "created_at" "deleted_at" "distribution_amount_cents" "document_folder_id" "entity_id" "esign_completed" "esign_emails" "esign_link" "esign_provider" "esign_required" "exchange_rate_id" "feeder_fund_id" "folio_call_amount_cents" "folio_collected_amount_cents" "folio_committed_amount_cents" "folio_currency" "folio_id" "form_type_id" "fund_close" "fund_id" "generated_deleted" "import_upload_id" "investor_id" "investor_kyc_id" "investor_name" "investor_signatory_id" "investor_signature_types" "is_feeder_fund" "json_fields" "notes" "onboarding_completed" "orig_committed_amount_cents" "orig_folio_committed_amount_cents" "other_fee_cents" "percentage" "ppm_number" "slug" "total_allocated_expense_cents" "total_allocated_income_cents" "total_fund_units_quantity" "total_units_amount_cents" "total_units_premium_cents" "tracking_adjustment_amount_cents" "tracking_collected_amount_cents" "tracking_committed_amount_cents" "tracking_distribution_amount_cents" "tracking_orig_committed_amount_cents" "unit_type" "updated_at" "virtual_bank_account")
TEXT_COLS_capital_commitments=("esign_emails" "esign_link" "esign_provider" "folio_currency" "folio_id" "fund_close" "investor_name" "investor_signature_types" "json_fields" "notes" "slug" "unit_type" "virtual_bank_account")
SCHEMA_capital_commitments='
  "id" BIGINT PRIMARY KEY,
  "adjustment_amount_cents" DECIMAL(20,2),
  "adjustment_folio_amount_cents" DECIMAL(20,2),
  "arrear_amount_cents" DECIMAL(20,2),
  "arrear_folio_amount_cents" DECIMAL(20,2),
  "call_amount_cents" DECIMAL(20,2),
  "collected_amount_cents" DECIMAL(20,2),
  "commitment_date" DATE,
  "committed_amount_cents" DECIMAL(20,2),
  "compliant" BOOLEAN,
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "distribution_amount_cents" DECIMAL(20,2),
  "document_folder_id" BIGINT,
  "entity_id" BIGINT,
  "esign_completed" BOOLEAN,
  "esign_emails" VARCHAR(255),
  "esign_link" VARCHAR(255),
  "esign_provider" VARCHAR(255),
  "esign_required" BOOLEAN,
  "exchange_rate_id" BIGINT,
  "feeder_fund_id" BIGINT,
  "folio_call_amount_cents" DECIMAL(20,2),
  "folio_collected_amount_cents" DECIMAL(20,2),
  "folio_committed_amount_cents" DECIMAL(20,2),
  "folio_currency" VARCHAR(255),
  "folio_id" VARCHAR(255),
  "form_type_id" BIGINT,
  "fund_close" VARCHAR(255),
  "fund_id" BIGINT,
  "generated_deleted" DATETIME,
  "import_upload_id" BIGINT,
  "investor_id" BIGINT,
  "investor_kyc_id" BIGINT,
  "investor_name" VARCHAR(255),
  "investor_signatory_id" BIGINT,
  "investor_signature_types" VARCHAR(255),
  "is_feeder_fund" BOOLEAN,
  "json_fields" JSON,
  "notes" TEXT,
  "onboarding_completed" BOOLEAN,
  "orig_committed_amount_cents" DECIMAL(20,2),
  "orig_folio_committed_amount_cents" DECIMAL(20,2),
  "other_fee_cents" DECIMAL(20,2),
  "percentage" DECIMAL(20,2),
  "ppm_number" BIGINT,
  "slug" VARCHAR(255),
  "total_allocated_expense_cents" DECIMAL(20,2),
  "total_allocated_income_cents" DECIMAL(20,2),
  "total_fund_units_quantity" DECIMAL(20,2),
  "total_units_amount_cents" DECIMAL(20,2),
  "total_units_premium_cents" DECIMAL(20,2),
  "tracking_adjustment_amount_cents" DECIMAL(20,2),
  "tracking_collected_amount_cents" DECIMAL(20,2),
  "tracking_committed_amount_cents" DECIMAL(20,2),
  "tracking_distribution_amount_cents" DECIMAL(20,2),
  "tracking_orig_committed_amount_cents" DECIMAL(20,2),
  "unit_type" VARCHAR(255),
  "updated_at" DATETIME,
  "virtual_bank_account" VARCHAR(255)
'
INDEX_capital_commitments='
  CREATE INDEX "idx_capital_commitments_commitment_date" ON "capital_commitments"("commitment_date");
  CREATE INDEX "idx_capital_commitments_deleted_at" ON "capital_commitments"("deleted_at");
  CREATE INDEX "idx_capital_commitments_document_folder_id" ON "capital_commitments"("document_folder_id");
  CREATE INDEX "idx_capital_commitments_entity_id" ON "capital_commitments"("entity_id");
  CREATE INDEX "idx_capital_commitments_exchange_rate_id" ON "capital_commitments"("exchange_rate_id");
  CREATE INDEX "idx_capital_commitments_feeder_fund_id" ON "capital_commitments"("feeder_fund_id");
  CREATE INDEX "idx_capital_commitments_form_type_id" ON "capital_commitments"("form_type_id");
  CREATE INDEX "idx_capital_commitments_fund_id_folio_id_generated_deleted" ON "capital_commitments"("fund_id", "folio_id", "generated_deleted");
  CREATE INDEX "idx_capital_commitments_fund_id" ON "capital_commitments"("fund_id");
  CREATE INDEX "idx_capital_commitments_investor_id" ON "capital_commitments"("investor_id");
  CREATE INDEX "idx_capital_commitments_investor_kyc_id" ON "capital_commitments"("investor_kyc_id");
  CREATE INDEX "idx_capital_commitments_investor_signatory_id" ON "capital_commitments"("investor_signatory_id");
  CREATE INDEX "idx_capital_commitments_slug" ON "capital_commitments"("slug");
'
COLS_capital_distribution_payments=("id" "capital_commitment_id" "capital_distribution_id" "completed" "cost_of_investment_cents" "cost_of_investment_with_fees_cents" "created_at" "deleted_at" "document_folder_id" "entity_id" "exchange_rate_id" "folio_amount_cents" "folio_id" "form_type_id" "fund_id" "gross_of_account_entries_cents" "gross_payable_cents" "import_upload_id" "income_cents" "income_with_fees_cents" "investor_id" "investor_name" "json_fields" "net_of_account_entries_cents" "net_payable_cents" "notification_sent" "payment_date" "percentage" "reinvestment_cents" "reinvestment_with_fees_cents" "tracking_gross_payable_cents" "tracking_net_payable_cents" "tracking_reinvestment_with_fees_cents" "units_quantity" "updated_at")
TEXT_COLS_capital_distribution_payments=("folio_id" "investor_name" "json_fields")
SCHEMA_capital_distribution_payments='
  "id" BIGINT PRIMARY KEY,
  "capital_commitment_id" BIGINT,
  "capital_distribution_id" BIGINT,
  "completed" BOOLEAN,
  "cost_of_investment_cents" DECIMAL(20,2),
  "cost_of_investment_with_fees_cents" DECIMAL(20,2),
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "document_folder_id" BIGINT,
  "entity_id" BIGINT,
  "exchange_rate_id" BIGINT,
  "folio_amount_cents" DECIMAL(20,2),
  "folio_id" VARCHAR(255),
  "form_type_id" BIGINT,
  "fund_id" BIGINT,
  "gross_of_account_entries_cents" DECIMAL(20,2),
  "gross_payable_cents" DECIMAL(20,2),
  "import_upload_id" BIGINT,
  "income_cents" DECIMAL(20,2),
  "income_with_fees_cents" DECIMAL(20,2),
  "investor_id" BIGINT,
  "investor_name" VARCHAR(255),
  "json_fields" JSON,
  "net_of_account_entries_cents" DECIMAL(20,2),
  "net_payable_cents" DECIMAL(20,2),
  "notification_sent" BOOLEAN,
  "payment_date" DATE,
  "percentage" DECIMAL(20,2),
  "reinvestment_cents" DECIMAL(20,2),
  "reinvestment_with_fees_cents" DECIMAL(20,2),
  "tracking_gross_payable_cents" DECIMAL(20,2),
  "tracking_net_payable_cents" DECIMAL(20,2),
  "tracking_reinvestment_with_fees_cents" DECIMAL(20,2),
  "units_quantity" DECIMAL(20,2),
  "updated_at" DATETIME
'
INDEX_capital_distribution_payments='
  CREATE INDEX "idx_capital_distribution_payments_capital_commitment_id" ON "capital_distribution_payments"("capital_commitment_id");
  CREATE INDEX "idx_capital_distribution_payments_capital_distribution_id" ON "capital_distribution_payments"("capital_distribution_id");
  CREATE INDEX "idx_capital_distribution_payments_deleted_at" ON "capital_distribution_payments"("deleted_at");
  CREATE INDEX "idx_capital_distribution_payments_document_folder_id" ON "capital_distribution_payments"("document_folder_id");
  CREATE INDEX "idx_capital_distribution_payments_entity_id" ON "capital_distribution_payments"("entity_id");
  CREATE INDEX "idx_capital_distribution_payments_exchange_rate_id" ON "capital_distribution_payments"("exchange_rate_id");
  CREATE INDEX "idx_capital_distribution_payments_form_type_id" ON "capital_distribution_payments"("form_type_id");
  CREATE INDEX "idx_capital_distribution_payments_fund_id" ON "capital_distribution_payments"("fund_id");
  CREATE INDEX "idx_capital_distribution_payments_investor_id" ON "capital_distribution_payments"("investor_id");
'
COLS_capital_distributions=("id" "approved" "approved_by_user_id" "capital_commitment_id" "carry_cents" "completed" "completed_distribution_amount_cents" "compliant" "cost_of_investment_cents" "created_at" "deleted_at" "distribution_amount_cents" "distribution_date" "distribution_on" "document_folder_id" "entity_id" "fee_cents" "form_type_id" "fund_id" "generate_payments" "generate_payments_paid" "gross_amount_cents" "import_upload_id" "income_cents" "json_fields" "manual_generation" "net_amount_cents" "notes" "reinvestment_cents" "send_notification_on_complete" "title" "unit_prices" "updated_at")
TEXT_COLS_capital_distributions=("json_fields" "notes" "title" "unit_prices")
SCHEMA_capital_distributions='
  "id" BIGINT PRIMARY KEY,
  "approved" BOOLEAN,
  "approved_by_user_id" BIGINT,
  "capital_commitment_id" BIGINT,
  "carry_cents" DECIMAL(20,2),
  "completed" BOOLEAN,
  "completed_distribution_amount_cents" DECIMAL(20,2),
  "compliant" BOOLEAN,
  "cost_of_investment_cents" DECIMAL(20,2),
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "distribution_amount_cents" DECIMAL(20,2),
  "distribution_date" DATE,
  "distribution_on" INTEGER,
  "document_folder_id" BIGINT,
  "entity_id" BIGINT,
  "fee_cents" DECIMAL(20,2),
  "form_type_id" BIGINT,
  "fund_id" BIGINT,
  "generate_payments" BOOLEAN,
  "generate_payments_paid" BOOLEAN,
  "gross_amount_cents" DECIMAL(20,2),
  "import_upload_id" BIGINT,
  "income_cents" DECIMAL(20,2),
  "json_fields" JSON,
  "manual_generation" BOOLEAN,
  "net_amount_cents" DECIMAL(20,2),
  "notes" TEXT,
  "reinvestment_cents" DECIMAL(20,2),
  "send_notification_on_complete" BOOLEAN,
  "title" VARCHAR(255),
  "unit_prices" TEXT,
  "updated_at" DATETIME
'
INDEX_capital_distributions='
  CREATE INDEX "idx_capital_distributions_approved_by_user_id" ON "capital_distributions"("approved_by_user_id");
  CREATE INDEX "idx_capital_distributions_capital_commitment_id" ON "capital_distributions"("capital_commitment_id");
  CREATE INDEX "idx_capital_distributions_deleted_at" ON "capital_distributions"("deleted_at");
  CREATE INDEX "idx_capital_distributions_document_folder_id" ON "capital_distributions"("document_folder_id");
  CREATE INDEX "idx_capital_distributions_entity_id" ON "capital_distributions"("entity_id");
  CREATE INDEX "idx_capital_distributions_form_type_id" ON "capital_distributions"("form_type_id");
  CREATE INDEX "idx_capital_distributions_fund_id" ON "capital_distributions"("fund_id");
'
COLS_capital_remittance_payments=("id" "amount_cents" "capital_remittance_id" "convert_to_fund_currency" "created_at" "deleted_at" "entity_id" "exchange_rate_id" "folio_amount_cents" "form_type_id" "fund_id" "import_upload_id" "investor_id" "json_fields" "notes" "payment_date" "payment_notification_sent" "payment_proof_data" "reference_no" "tracking_amount_cents" "updated_at")
TEXT_COLS_capital_remittance_payments=("json_fields" "notes" "payment_proof_data" "reference_no")
SCHEMA_capital_remittance_payments='
  "id" BIGINT PRIMARY KEY,
  "amount_cents" DECIMAL(20,2),
  "capital_remittance_id" BIGINT,
  "convert_to_fund_currency" BOOLEAN,
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "entity_id" BIGINT,
  "exchange_rate_id" BIGINT,
  "folio_amount_cents" DECIMAL(20,2),
  "form_type_id" BIGINT,
  "fund_id" BIGINT,
  "import_upload_id" BIGINT,
  "investor_id" BIGINT,
  "json_fields" JSON,
  "notes" TEXT,
  "payment_date" DATE,
  "payment_notification_sent" BOOLEAN,
  "payment_proof_data" TEXT,
  "reference_no" VARCHAR(255),
  "tracking_amount_cents" DECIMAL(20,2),
  "updated_at" DATETIME
'
INDEX_capital_remittance_payments='
  CREATE INDEX "idx_capital_remittance_payments_capital_remittance_id" ON "capital_remittance_payments"("capital_remittance_id");
  CREATE INDEX "idx_capital_remittance_payments_deleted_at" ON "capital_remittance_payments"("deleted_at");
  CREATE INDEX "idx_capital_remittance_payments_entity_id" ON "capital_remittance_payments"("entity_id");
  CREATE INDEX "idx_capital_remittance_payments_exchange_rate_id" ON "capital_remittance_payments"("exchange_rate_id");
  CREATE INDEX "idx_capital_remittance_payments_form_type_id" ON "capital_remittance_payments"("form_type_id");
  CREATE INDEX "idx_capital_remittance_payments_fund_id" ON "capital_remittance_payments"("fund_id");
  CREATE INDEX "idx_capital_remittance_payments_investor_id" ON "capital_remittance_payments"("investor_id");
  CREATE INDEX "idx_capital_remittance_payments_payment_date" ON "capital_remittance_payments"("payment_date");
'
COLS_capital_remittances=("id" "arrear_amount_cents" "arrear_folio_amount_cents" "call_amount_cents" "call_basis" "capital_call_id" "capital_commitment_id" "capital_fee_cents" "collected_amount_cents" "committed_amount_cents" "compliant" "computed_amount_cents" "created_at" "created_by" "deleted_at" "document_folder_id" "entity_id" "exchange_rate_id" "folio_call_amount_cents" "folio_capital_fee_cents" "folio_collected_amount_cents" "folio_committed_amount_cents" "folio_id" "folio_investment_amount_cents" "folio_other_fee_cents" "form_type_id" "fund_id" "import_upload_id" "investment_amount_cents" "investor_id" "investor_name" "json_fields" "notes" "notification_sent" "other_fee_cents" "payment_date" "payment_proof_data" "percentage" "remittance_date" "status" "tracking_call_amount_cents" "tracking_collected_amount_cents" "units_quantity" "updated_at" "verified")
TEXT_COLS_capital_remittances=("call_basis" "created_by" "folio_id" "investor_name" "json_fields" "notes" "payment_proof_data" "status")
SCHEMA_capital_remittances='
  "id" BIGINT PRIMARY KEY,
  "arrear_amount_cents" DECIMAL(20,2),
  "arrear_folio_amount_cents" DECIMAL(20,2),
  "call_amount_cents" DECIMAL(20,2),
  "call_basis" VARCHAR(255),
  "capital_call_id" BIGINT,
  "capital_commitment_id" BIGINT,
  "capital_fee_cents" DECIMAL(20,2),
  "collected_amount_cents" DECIMAL(20,2),
  "committed_amount_cents" DECIMAL(20,2),
  "compliant" BOOLEAN,
  "computed_amount_cents" DECIMAL(20,2),
  "created_at" DATETIME,
  "created_by" VARCHAR(255),
  "deleted_at" DATETIME,
  "document_folder_id" BIGINT,
  "entity_id" BIGINT,
  "exchange_rate_id" BIGINT,
  "folio_call_amount_cents" DECIMAL(20,2),
  "folio_capital_fee_cents" DECIMAL(20,2),
  "folio_collected_amount_cents" DECIMAL(20,2),
  "folio_committed_amount_cents" DECIMAL(20,2),
  "folio_id" VARCHAR(255),
  "folio_investment_amount_cents" DECIMAL(20,2),
  "folio_other_fee_cents" DECIMAL(20,2),
  "form_type_id" BIGINT,
  "fund_id" BIGINT,
  "import_upload_id" BIGINT,
  "investment_amount_cents" DECIMAL(20,2),
  "investor_id" BIGINT,
  "investor_name" VARCHAR(255),
  "json_fields" JSON,
  "notes" TEXT,
  "notification_sent" BOOLEAN,
  "other_fee_cents" DECIMAL(20,2),
  "payment_date" DATE,
  "payment_proof_data" TEXT,
  "percentage" DECIMAL(20,2),
  "remittance_date" DATE,
  "status" VARCHAR(255),
  "tracking_call_amount_cents" DECIMAL(20,2),
  "tracking_collected_amount_cents" DECIMAL(20,2),
  "units_quantity" DECIMAL(20,2),
  "updated_at" DATETIME,
  "verified" BOOLEAN
'
INDEX_capital_remittances='
  CREATE INDEX "idx_capital_remittances_capital_call_id" ON "capital_remittances"("capital_call_id");
  CREATE INDEX "idx_capital_remittances_capital_commitment_id" ON "capital_remittances"("capital_commitment_id");
  CREATE INDEX "idx_capital_remittances_deleted_at" ON "capital_remittances"("deleted_at");
  CREATE INDEX "idx_capital_remittances_document_folder_id" ON "capital_remittances"("document_folder_id");
  CREATE INDEX "idx_capital_remittances_entity_id" ON "capital_remittances"("entity_id");
  CREATE INDEX "idx_capital_remittances_exchange_rate_id" ON "capital_remittances"("exchange_rate_id");
  CREATE INDEX "idx_capital_remittances_form_type_id" ON "capital_remittances"("form_type_id");
  CREATE INDEX "idx_capital_remittances_fund_id" ON "capital_remittances"("fund_id");
  CREATE INDEX "idx_capital_remittances_investor_id" ON "capital_remittances"("investor_id");
  CREATE INDEX "idx_capital_remittances_remittance_date" ON "capital_remittances"("remittance_date");
'
COLS_commitment_adjustments=("id" "adjustment_type" "amount_cents" "as_of" "capital_commitment_id" "created_at" "deleted_at" "entity_id" "exchange_rate_id" "folio_amount_cents" "fund_id" "owner_id" "owner_type" "post_adjustment_cents" "pre_adjustment_cents" "reason" "tracking_amount_cents" "transfer_date" "updated_at")
TEXT_COLS_commitment_adjustments=("adjustment_type" "owner_type" "reason")
SCHEMA_commitment_adjustments='
  "id" BIGINT PRIMARY KEY,
  "adjustment_type" VARCHAR(255),
  "amount_cents" DECIMAL(20,2),
  "as_of" DATE,
  "capital_commitment_id" BIGINT,
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "entity_id" BIGINT,
  "exchange_rate_id" BIGINT,
  "folio_amount_cents" DECIMAL(20,2),
  "fund_id" BIGINT,
  "owner_id" BIGINT,
  "owner_type" VARCHAR(255),
  "post_adjustment_cents" DECIMAL(20,2),
  "pre_adjustment_cents" DECIMAL(20,2),
  "reason" TEXT,
  "tracking_amount_cents" DECIMAL(20,2),
  "transfer_date" DATE,
  "updated_at" DATETIME
'
INDEX_commitment_adjustments='
  CREATE INDEX "idx_commitment_adjustments_capital_commitment_id" ON "commitment_adjustments"("capital_commitment_id");
  CREATE INDEX "idx_commitment_adjustments_deleted_at" ON "commitment_adjustments"("deleted_at");
  CREATE INDEX "idx_commitment_adjustments_entity_id" ON "commitment_adjustments"("entity_id");
  CREATE INDEX "idx_commitment_adjustments_exchange_rate_id" ON "commitment_adjustments"("exchange_rate_id");
  CREATE INDEX "idx_commitment_adjustments_fund_id" ON "commitment_adjustments"("fund_id");
  CREATE INDEX "idx_commitment_adjustments_owner_type_owner_id" ON "commitment_adjustments"("owner_type", "owner_id");
'
COLS_distribution_fees=("id" "capital_distribution_id" "created_at" "end_date" "entity_id" "fee_type" "formula" "fund_id" "name" "notes" "start_date" "updated_at")
TEXT_COLS_distribution_fees=("fee_type" "name" "notes")
SCHEMA_distribution_fees='
  "id" BIGINT PRIMARY KEY,
  "capital_distribution_id" BIGINT,
  "created_at" DATETIME,
  "end_date" DATE,
  "entity_id" BIGINT,
  "fee_type" VARCHAR(255),
  "formula" BOOLEAN,
  "fund_id" BIGINT,
  "name" VARCHAR(255),
  "notes" VARCHAR(255),
  "start_date" DATE,
  "updated_at" DATETIME
'
INDEX_distribution_fees='
  CREATE INDEX "idx_distribution_fees_capital_distribution_id" ON "distribution_fees"("capital_distribution_id");
  CREATE INDEX "idx_distribution_fees_entity_id" ON "distribution_fees"("entity_id");
  CREATE INDEX "idx_distribution_fees_fund_id" ON "distribution_fees"("fund_id");
'
COLS_documents=("id" "adhaar_esign_completed" "adhaar_esign_enabled" "approved" "approved_by_id" "created_at" "deleted_at" "display_on_page" "download" "embed" "entity_id" "esign_status" "file_data" "folder_id" "force_esign_order" "form_type_id" "from_template_id" "import_upload_id" "impressions_count" "json_fields" "last_status_updated_at" "locked" "name" "orignal" "owner_id" "owner_tag" "owner_type" "printing" "provider_doc_id" "public_visibility" "qna" "send_email" "sent_for_esign" "sent_for_esign_date" "signature_enabled" "signature_type" "signed_by_accept" "signed_by_id" "tag_list" "template" "template_docs_to_append" "text" "updated_at" "user_id" "visible_to")
TEXT_COLS_documents=("display_on_page" "esign_status" "file_data" "json_fields" "name" "owner_tag" "owner_type" "provider_doc_id" "qna" "signature_type" "tag_list" "template_docs_to_append" "text" "visible_to")
SCHEMA_documents='
  "id" BIGINT PRIMARY KEY,
  "adhaar_esign_completed" BOOLEAN,
  "adhaar_esign_enabled" BOOLEAN,
  "approved" BOOLEAN,
  "approved_by_id" BIGINT,
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "display_on_page" VARCHAR(255),
  "download" BOOLEAN,
  "embed" BOOLEAN,
  "entity_id" BIGINT,
  "esign_status" VARCHAR(255),
  "file_data" TEXT,
  "folder_id" BIGINT,
  "force_esign_order" BOOLEAN,
  "form_type_id" BIGINT,
  "from_template_id" BIGINT,
  "import_upload_id" BIGINT,
  "impressions_count" INTEGER,
  "json_fields" JSON,
  "last_status_updated_at" DATETIME,
  "locked" BOOLEAN,
  "name" VARCHAR(255),
  "orignal" BOOLEAN,
  "owner_id" BIGINT,
  "owner_tag" VARCHAR(255),
  "owner_type" VARCHAR(255),
  "printing" BOOLEAN,
  "provider_doc_id" VARCHAR(255),
  "public_visibility" BOOLEAN,
  "qna" TEXT,
  "send_email" BOOLEAN,
  "sent_for_esign" BOOLEAN,
  "sent_for_esign_date" DATETIME,
  "signature_enabled" BOOLEAN,
  "signature_type" VARCHAR(255),
  "signed_by_accept" BOOLEAN,
  "signed_by_id" BIGINT,
  "tag_list" VARCHAR(255),
  "template" BOOLEAN,
  "template_docs_to_append" VARCHAR(255),
  "text" VARCHAR(255),
  "updated_at" DATETIME,
  "user_id" BIGINT,
  "visible_to" VARCHAR(255)
'
INDEX_documents='
  CREATE INDEX "idx_documents_approved_by_id" ON "documents"("approved_by_id");
  CREATE INDEX "idx_documents_deleted_at" ON "documents"("deleted_at");
  CREATE INDEX "idx_documents_entity_id" ON "documents"("entity_id");
  CREATE INDEX "idx_documents_folder_id" ON "documents"("folder_id");
  CREATE INDEX "idx_documents_form_type_id" ON "documents"("form_type_id");
  CREATE INDEX "idx_documents_owner_type_owner_id" ON "documents"("owner_type", "owner_id");
  CREATE INDEX "idx_documents_signed_by_id" ON "documents"("signed_by_id");
  CREATE INDEX "idx_documents_user_id" ON "documents"("user_id");
'
COLS_e_signatures=("id" "api_updates" "created_at" "deleted_at" "document_id" "email" "entity_id" "label" "notes" "position" "remind_in" "signature_type" "signer_id" "status" "updated_at" "user_id")
TEXT_COLS_e_signatures=("api_updates" "email" "label" "notes" "signature_type" "signer_id" "status")
SCHEMA_e_signatures='
  "id" BIGINT PRIMARY KEY,
  "api_updates" TEXT,
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "document_id" BIGINT,
  "email" VARCHAR(255),
  "entity_id" BIGINT,
  "label" VARCHAR(255),
  "notes" TEXT,
  "position" INTEGER,
  "remind_in" INTEGER,
  "signature_type" VARCHAR(255),
  "signer_id" VARCHAR(255),
  "status" VARCHAR(255),
  "updated_at" DATETIME,
  "user_id" BIGINT
'
INDEX_e_signatures='
  CREATE INDEX "idx_e_signatures_deleted_at" ON "e_signatures"("deleted_at");
  CREATE INDEX "idx_e_signatures_document_id" ON "e_signatures"("document_id");
  CREATE INDEX "idx_e_signatures_entity_id" ON "e_signatures"("entity_id");
  CREATE INDEX "idx_e_signatures_user_id" ON "e_signatures"("user_id");
'
COLS_entities=("id" "name" "url" "category" "founded" "created_at" "updated_at" "logo_url" "active" "entity_type" "created_by" "investor_categories" "instrument_types" "s3_bucket" "deleted_at" "investors_count" "investments_count" "deals_count" "deal_investors_count" "documents_count" "total_investments" "is_holdings_entity" "parent_entity_id" "currency" "tasks_count" "pending_accesses_count" "active_deal_id" "equity" "preferred" "options" "percentage_in_progress" "per_share_value_cents" "units" "sub_domain" "logo_data" "activity_docs_required_for_completion" "activity_details_required_for_na" "pan" "permissions" "primary_email" "customization_flags" "root_folder_id" "primary_region_id" "tracking_currency" "support_agents" "domain" "white_label")
TEXT_COLS_entities=("name" "url" "category" "logo_url" "entity_type" "investor_categories" "instrument_types" "s3_bucket" "currency" "sub_domain" "logo_data" "pan" "primary_email" "tracking_currency" "domain")
SCHEMA_entities='
  "id" BIGINT PRIMARY KEY,
  "name" VARCHAR(255),
  "url" VARCHAR(255),
  "category" VARCHAR(255),
  "founded" DATE,
  "created_at" DATETIME,
  "updated_at" DATETIME,
  "logo_url" TEXT,
  "active" BOOLEAN,
  "entity_type" VARCHAR(25),
  "created_by" INTEGER,
  "investor_categories" VARCHAR(255),
  "instrument_types" VARCHAR(255),
  "s3_bucket" VARCHAR(255),
  "deleted_at" DATETIME,
  "investors_count" INTEGER,
  "investments_count" INTEGER,
  "deals_count" INTEGER,
  "deal_investors_count" INTEGER,
  "documents_count" INTEGER,
  "total_investments" DECIMAL(20,2),
  "is_holdings_entity" BOOLEAN,
  "parent_entity_id" INTEGER,
  "currency" VARCHAR(10),
  "tasks_count" INTEGER,
  "pending_accesses_count" INTEGER,
  "active_deal_id" INTEGER,
  "equity" INTEGER,
  "preferred" INTEGER,
  "options" INTEGER,
  "percentage_in_progress" BOOLEAN,
  "per_share_value_cents" DECIMAL(15,2),
  "units" INTEGER,
  "sub_domain" VARCHAR(255),
  "logo_data" TEXT,
  "activity_docs_required_for_completion" BOOLEAN,
  "activity_details_required_for_na" BOOLEAN,
  "pan" VARCHAR(40),
  "permissions" BIGINT,
  "primary_email" VARCHAR(255),
  "customization_flags" INTEGER,
  "root_folder_id" BIGINT,
  "primary_region_id" INTEGER,
  "tracking_currency" VARCHAR(4),
  "support_agents" INTEGER,
  "domain" VARCHAR(255),
  "white_label" BOOLEAN
'
INDEX_entities='
  CREATE INDEX "idx_entities_name" ON "entities"("name");
  CREATE INDEX "idx_entities_deleted_at" ON "entities"("deleted_at");
  CREATE INDEX "idx_entities_parent_entity_id" ON "entities"("parent_entity_id");
  CREATE INDEX "idx_entities_sub_domain" ON "entities"("sub_domain");
  CREATE INDEX "idx_entities_pan" ON "entities"("pan");
  CREATE INDEX "idx_entities_root_folder_id" ON "entities"("root_folder_id");
'
COLS_exchange_rates=("id" "as_of" "created_at" "decimal" "document_folder_id" "entity_id" "from" "import_upload_id" "latest" "notes" "rate" "to" "updated_at")
TEXT_COLS_exchange_rates=("from" "notes" "to")
SCHEMA_exchange_rates='
  "id" BIGINT PRIMARY KEY,
  "as_of" DATE,
  "created_at" DATETIME,
  "decimal" DECIMAL(20,2),
  "document_folder_id" BIGINT,
  "entity_id" BIGINT,
  "from" VARCHAR(255),
  "import_upload_id" BIGINT,
  "latest" BOOLEAN,
  "notes" TEXT,
  "rate" DECIMAL(20,2),
  "to" VARCHAR(255),
  "updated_at" DATETIME
'
INDEX_exchange_rates='
  CREATE INDEX "idx_exchange_rates_document_folder_id" ON "exchange_rates"("document_folder_id");
  CREATE INDEX "idx_exchange_rates_entity_id_from_to_as_of" ON "exchange_rates"("entity_id", "from", "to", "as_of");
  CREATE INDEX "idx_exchange_rates_entity_id" ON "exchange_rates"("entity_id");
  CREATE INDEX "idx_exchange_rates_import_upload_id" ON "exchange_rates"("import_upload_id");
'
COLS_fees=("id" "advisor_name" "amount_cents" "amount_label" "bank_account_number" "created_at" "entity_id" "ifsc_code" "owner_id" "owner_type" "updated_at")
TEXT_COLS_fees=("advisor_name" "amount_label" "bank_account_number" "ifsc_code" "owner_type")
SCHEMA_fees='
  "id" BIGINT PRIMARY KEY,
  "advisor_name" VARCHAR(255),
  "amount_cents" DECIMAL(20,2),
  "amount_label" VARCHAR(255),
  "bank_account_number" VARCHAR(255),
  "created_at" DATETIME,
  "entity_id" BIGINT,
  "ifsc_code" VARCHAR(255),
  "owner_id" BIGINT,
  "owner_type" VARCHAR(255),
  "updated_at" DATETIME
'
INDEX_fees='
  CREATE INDEX "idx_fees_entity_id" ON "fees"("entity_id");
  CREATE INDEX "idx_fees_owner_type_owner_id" ON "fees"("owner_type", "owner_id");
'
COLS_folders=("id" "ancestry" "created_at" "deleted_at" "documents_count" "download" "entity_id" "folder_type" "full_path" "knowledge_base" "level" "name" "orignal" "owner_id" "owner_type" "printing" "private" "updated_at")
TEXT_COLS_folders=("ancestry" "full_path" "name" "owner_type")
SCHEMA_folders='
  "id" BIGINT PRIMARY KEY,
  "ancestry" VARCHAR(255),
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "documents_count" INTEGER,
  "download" BOOLEAN,
  "entity_id" BIGINT,
  "folder_type" INTEGER,
  "full_path" VARCHAR(255),
  "knowledge_base" BOOLEAN,
  "level" INTEGER,
  "name" VARCHAR(255),
  "orignal" BOOLEAN,
  "owner_id" BIGINT,
  "owner_type" VARCHAR(255),
  "printing" BOOLEAN,
  "private" BOOLEAN,
  "updated_at" DATETIME
'
INDEX_folders='
  CREATE INDEX "idx_folders_ancestry" ON "folders"("ancestry");
  CREATE INDEX "idx_folders_deleted_at" ON "folders"("deleted_at");
  CREATE INDEX "idx_folders_entity_id" ON "folders"("entity_id");
  CREATE INDEX "idx_folders_full_path_owner_id_owner_type_entity_id_deleted_at" ON "folders"("full_path", "owner_id", "owner_type", "entity_id", "deleted_at");
  CREATE INDEX "idx_folders_owner_type_owner_id" ON "folders"("owner_type", "owner_id");
'
COLS_fund_ratios=("id" "capital_commitment_id" "cash_flows" "created_at" "deleted_at" "display_value" "end_date" "entity_id" "form_type_id" "fund_id" "import_upload_id" "label" "latest" "name" "notes" "owner_id" "owner_type" "portfolio_scenario_id" "scenario" "updated_at" "valuation_id" "value")
TEXT_COLS_fund_ratios=("cash_flows" "display_value" "label" "name" "notes" "owner_type" "scenario")
SCHEMA_fund_ratios='
  "id" BIGINT PRIMARY KEY,
  "capital_commitment_id" BIGINT,
  "cash_flows" JSON,
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "display_value" VARCHAR(255),
  "end_date" DATE,
  "entity_id" BIGINT,
  "form_type_id" BIGINT,
  "fund_id" BIGINT,
  "import_upload_id" BIGINT,
  "label" VARCHAR(255),
  "latest" BOOLEAN,
  "name" VARCHAR(255),
  "notes" TEXT,
  "owner_id" BIGINT,
  "owner_type" VARCHAR(255),
  "portfolio_scenario_id" BIGINT,
  "scenario" VARCHAR(255),
  "updated_at" DATETIME,
  "valuation_id" BIGINT,
  "value" DECIMAL(20,2)
'
INDEX_fund_ratios='
  CREATE INDEX "idx_fund_ratios_capital_commitment_id" ON "fund_ratios"("capital_commitment_id");
  CREATE INDEX "idx_fund_ratios_deleted_at" ON "fund_ratios"("deleted_at");
  CREATE INDEX "idx_fund_ratios_entity_id" ON "fund_ratios"("entity_id");
  CREATE INDEX "idx_fund_ratios_form_type_id" ON "fund_ratios"("form_type_id");
  CREATE INDEX "idx_fund_ratios_fund_id" ON "fund_ratios"("fund_id");
  CREATE INDEX "idx_fund_ratios_owner_type_owner_id" ON "fund_ratios"("owner_type", "owner_id");
  CREATE INDEX "idx_fund_ratios_portfolio_scenario_id" ON "fund_ratios"("portfolio_scenario_id");
  CREATE INDEX "idx_fund_ratios_valuation_id" ON "fund_ratios"("valuation_id");
'
COLS_fund_unit_settings=("id" "carry" "created_at" "entity_id" "form_type_id" "fund_id" "gp_units" "import_upload_id" "isin" "json_fields" "management_fee" "name" "notes" "setup_fee" "updated_at")
TEXT_COLS_fund_unit_settings=("isin" "json_fields" "name" "notes")
SCHEMA_fund_unit_settings='
  "id" BIGINT PRIMARY KEY,
  "carry" DECIMAL(20,2),
  "created_at" DATETIME,
  "entity_id" BIGINT,
  "form_type_id" BIGINT,
  "fund_id" BIGINT,
  "gp_units" BOOLEAN,
  "import_upload_id" BIGINT,
  "isin" VARCHAR(255),
  "json_fields" JSON,
  "management_fee" DECIMAL(20,2),
  "name" VARCHAR(255),
  "notes" TEXT,
  "setup_fee" DECIMAL(20,2),
  "updated_at" DATETIME
'
INDEX_fund_unit_settings='
  CREATE INDEX "idx_fund_unit_settings_entity_id" ON "fund_unit_settings"("entity_id");
  CREATE INDEX "idx_fund_unit_settings_form_type_id" ON "fund_unit_settings"("form_type_id");
  CREATE INDEX "idx_fund_unit_settings_fund_id" ON "fund_unit_settings"("fund_id");
'
COLS_fund_unit_transfers=("id" "account_entries_excluded" "created_at" "entity_id" "from_commitment_id" "fund_id" "premium" "price" "status" "to_commitment_id" "transfer_account_entries" "transfer_date" "transfer_ratio" "transfer_token" "updated_at")
TEXT_COLS_fund_unit_transfers=("account_entries_excluded" "status" "transfer_token")
SCHEMA_fund_unit_transfers='
  "id" BIGINT PRIMARY KEY,
  "account_entries_excluded" VARCHAR(255),
  "created_at" DATETIME,
  "entity_id" BIGINT,
  "from_commitment_id" BIGINT,
  "fund_id" BIGINT,
  "premium" DECIMAL(20,2),
  "price" DECIMAL(20,2),
  "status" VARCHAR(255),
  "to_commitment_id" BIGINT,
  "transfer_account_entries" BOOLEAN,
  "transfer_date" DATE,
  "transfer_ratio" INTEGER,
  "transfer_token" VARCHAR(255),
  "updated_at" DATETIME
'
INDEX_fund_unit_transfers='
  CREATE INDEX "idx_fund_unit_transfers_entity_id" ON "fund_unit_transfers"("entity_id");
  CREATE INDEX "idx_fund_unit_transfers_from_commitment_id" ON "fund_unit_transfers"("from_commitment_id");
  CREATE INDEX "idx_fund_unit_transfers_fund_id" ON "fund_unit_transfers"("fund_id");
  CREATE INDEX "idx_fund_unit_transfers_to_commitment_id" ON "fund_unit_transfers"("to_commitment_id");
'
COLS_fund_units=("id" "amount_cents" "capital_commitment_id" "created_at" "deleted_at" "entity_id" "fund_id" "gp_units" "import_upload_id" "investor_id" "issue_date" "owner_id" "owner_type" "premium_cents" "premium_old" "price_cents" "price_old" "quantity" "reason" "total_premium_cents" "transfer" "unit_type" "updated_at")
TEXT_COLS_fund_units=("owner_type" "reason" "transfer" "unit_type")
SCHEMA_fund_units='
  "id" BIGINT PRIMARY KEY,
  "amount_cents" DECIMAL(20,2),
  "capital_commitment_id" BIGINT,
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "entity_id" BIGINT,
  "fund_id" BIGINT,
  "gp_units" BOOLEAN,
  "import_upload_id" BIGINT,
  "investor_id" BIGINT,
  "issue_date" DATE,
  "owner_id" BIGINT,
  "owner_type" VARCHAR(255),
  "premium_cents" DECIMAL(20,2),
  "premium_old" DECIMAL(20,2),
  "price_cents" DECIMAL(20,2),
  "price_old" DECIMAL(20,2),
  "quantity" DECIMAL(20,2),
  "reason" TEXT,
  "total_premium_cents" DECIMAL(20,2),
  "transfer" VARCHAR(255),
  "unit_type" VARCHAR(255),
  "updated_at" DATETIME
'
INDEX_fund_units='
  CREATE INDEX "idx_fund_units_capital_commitment_id" ON "fund_units"("capital_commitment_id");
  CREATE INDEX "idx_fund_units_deleted_at" ON "fund_units"("deleted_at");
  CREATE INDEX "idx_fund_units_entity_id" ON "fund_units"("entity_id");
  CREATE INDEX "idx_fund_units_fund_id" ON "fund_units"("fund_id");
  CREATE INDEX "idx_fund_units_investor_id" ON "fund_units"("investor_id");
  CREATE INDEX "idx_fund_units_owner_type_owner_id" ON "fund_units"("owner_type", "owner_id");
'
COLS_funds=("id" "call_amount_cents" "capital_commitments_count" "capital_fee_cents" "category" "collected_amount_cents" "commitment_doc_list" "committed_amount_cents" "created_at" "currency" "data_room_folder_id" "deleted_at" "details" "distribution_amount_cents" "document_folder_id" "editable_formulas" "entity_id" "esign_emails" "first_close_date" "form_type_id" "fund_signatory_id" "fund_signature_types" "funding_round_id" "import_upload_id" "investor_signature_types" "json_fields" "last_close_date" "master_fund_id" "name" "orignal_id" "other_fee_cents" "permissions" "portfolio_cost_type" "regulatory_env" "show_fund_ratios" "show_portfolios" "show_valuations" "slug" "snapshot" "snapshot_date" "start_date" "tag_list" "target_committed_amount_cents" "total_units_premium_cents" "tracking_call_amount_cents" "tracking_co_invest_call_amount_cents" "tracking_collected_amount_cents" "tracking_committed_amount_cents" "tracking_currency" "tracking_distribution_amount_cents" "trustee_signatory_id" "unit_types" "units_allocation_engine" "updated_at")
TEXT_COLS_funds=("category" "commitment_doc_list" "currency" "details" "esign_emails" "fund_signature_types" "investor_signature_types" "json_fields" "name" "portfolio_cost_type" "regulatory_env" "slug" "tag_list" "tracking_currency" "unit_types" "units_allocation_engine")
SCHEMA_funds='
  "id" BIGINT PRIMARY KEY,
  "call_amount_cents" DECIMAL(20,2),
  "capital_commitments_count" INTEGER,
  "capital_fee_cents" DECIMAL(20,2),
  "category" VARCHAR(255),
  "collected_amount_cents" DECIMAL(20,2),
  "commitment_doc_list" VARCHAR(255),
  "committed_amount_cents" DECIMAL(20,2),
  "created_at" DATETIME,
  "currency" VARCHAR(255),
  "data_room_folder_id" BIGINT,
  "deleted_at" DATETIME,
  "details" TEXT,
  "distribution_amount_cents" DECIMAL(20,2),
  "document_folder_id" BIGINT,
  "editable_formulas" BOOLEAN,
  "entity_id" BIGINT,
  "esign_emails" VARCHAR(255),
  "first_close_date" DATE,
  "form_type_id" BIGINT,
  "fund_signatory_id" BIGINT,
  "fund_signature_types" VARCHAR(255),
  "funding_round_id" BIGINT,
  "import_upload_id" BIGINT,
  "investor_signature_types" VARCHAR(255),
  "json_fields" JSON,
  "last_close_date" DATE,
  "master_fund_id" BIGINT,
  "name" VARCHAR(255),
  "orignal_id" BIGINT,
  "other_fee_cents" DECIMAL(20,2),
  "permissions" INTEGER,
  "portfolio_cost_type" VARCHAR(255),
  "regulatory_env" VARCHAR(255),
  "show_fund_ratios" BOOLEAN,
  "show_portfolios" BOOLEAN,
  "show_valuations" BOOLEAN,
  "slug" VARCHAR(255),
  "snapshot" BOOLEAN,
  "snapshot_date" DATE,
  "start_date" DATE,
  "tag_list" VARCHAR(255),
  "target_committed_amount_cents" DECIMAL(20,2),
  "total_units_premium_cents" DECIMAL(20,2),
  "tracking_call_amount_cents" DECIMAL(20,2),
  "tracking_co_invest_call_amount_cents" DECIMAL(20,2),
  "tracking_collected_amount_cents" DECIMAL(20,2),
  "tracking_committed_amount_cents" DECIMAL(20,2),
  "tracking_currency" VARCHAR(255),
  "tracking_distribution_amount_cents" DECIMAL(20,2),
  "trustee_signatory_id" BIGINT,
  "unit_types" VARCHAR(255),
  "units_allocation_engine" VARCHAR(255),
  "updated_at" DATETIME
'
INDEX_funds='
  CREATE INDEX "idx_funds_data_room_folder_id" ON "funds"("data_room_folder_id");
  CREATE INDEX "idx_funds_deleted_at" ON "funds"("deleted_at");
  CREATE INDEX "idx_funds_document_folder_id" ON "funds"("document_folder_id");
  CREATE INDEX "idx_funds_entity_id" ON "funds"("entity_id");
  CREATE INDEX "idx_funds_form_type_id" ON "funds"("form_type_id");
  CREATE INDEX "idx_funds_fund_signatory_id" ON "funds"("fund_signatory_id");
  CREATE INDEX "idx_funds_funding_round_id" ON "funds"("funding_round_id");
  CREATE INDEX "idx_funds_import_upload_id" ON "funds"("import_upload_id");
  CREATE INDEX "idx_funds_master_fund_id" ON "funds"("master_fund_id");
  CREATE INDEX "idx_funds_slug" ON "funds"("slug");
  CREATE INDEX "idx_funds_snapshot_date" ON "funds"("snapshot_date");
  CREATE INDEX "idx_funds_trustee_signatory_id" ON "funds"("trustee_signatory_id");
'
COLS_interests=("id" "PAN" "address" "allocation_amount_cents" "allocation_percentage" "allocation_quantity" "amount_cents" "bank_account_number" "bank_verification_response" "bank_verification_status" "bank_verified" "buyer_entity_name" "buyer_signatory_emails" "city" "comments" "completed" "contact_name" "created_at" "custom_matching_vals" "deleted_at" "demat" "document_folder_id" "email" "entity_id" "escrow_deposited" "final_agreement" "final_agreement_user_id" "final_price" "finalized" "form_type_id" "funding_round_id" "ifsc_code" "import_upload_id" "interest_entity_id" "investor_id" "json_fields" "offer_quantity" "pan_verification_response" "pan_verification_status" "pan_verified" "price" "quantity" "secondary_sale_id" "short_listed_status" "signature_data" "spa_data" "status_updated_at" "status_updated_by_id" "updated_at" "user_id" "verified")
TEXT_COLS_interests=("PAN" "address" "bank_account_number" "bank_verification_response" "bank_verification_status" "buyer_entity_name" "buyer_signatory_emails" "city" "comments" "contact_name" "custom_matching_vals" "demat" "email" "ifsc_code" "json_fields" "pan_verification_response" "pan_verification_status" "short_listed_status" "signature_data" "spa_data")
SCHEMA_interests='
  "id" BIGINT PRIMARY KEY,
  "PAN" VARCHAR(255),
  "address" TEXT,
  "allocation_amount_cents" DECIMAL(20,2),
  "allocation_percentage" DECIMAL(20,2),
  "allocation_quantity" BIGINT,
  "amount_cents" DECIMAL(20,2),
  "bank_account_number" VARCHAR(255),
  "bank_verification_response" TEXT,
  "bank_verification_status" VARCHAR(255),
  "bank_verified" BOOLEAN,
  "buyer_entity_name" VARCHAR(255),
  "buyer_signatory_emails" VARCHAR(255),
  "city" VARCHAR(255),
  "comments" TEXT,
  "completed" BOOLEAN,
  "contact_name" VARCHAR(255),
  "created_at" DATETIME,
  "custom_matching_vals" VARCHAR(255),
  "deleted_at" DATETIME,
  "demat" VARCHAR(255),
  "document_folder_id" BIGINT,
  "email" VARCHAR(255),
  "entity_id" INTEGER,
  "escrow_deposited" BOOLEAN,
  "final_agreement" BOOLEAN,
  "final_agreement_user_id" BIGINT,
  "final_price" DECIMAL(20,2),
  "finalized" BOOLEAN,
  "form_type_id" BIGINT,
  "funding_round_id" BIGINT,
  "ifsc_code" VARCHAR(255),
  "import_upload_id" BIGINT,
  "interest_entity_id" INTEGER,
  "investor_id" BIGINT,
  "json_fields" JSON,
  "offer_quantity" INTEGER,
  "pan_verification_response" TEXT,
  "pan_verification_status" VARCHAR(255),
  "pan_verified" BOOLEAN,
  "price" DECIMAL(20,2),
  "quantity" INTEGER,
  "secondary_sale_id" BIGINT,
  "short_listed_status" VARCHAR(255),
  "signature_data" TEXT,
  "spa_data" TEXT,
  "status_updated_at" DATETIME,
  "status_updated_by_id" BIGINT,
  "updated_at" DATETIME,
  "user_id" BIGINT,
  "verified" BOOLEAN
'
INDEX_interests='
  CREATE INDEX "idx_interests_custom_matching_vals" ON "interests"("custom_matching_vals");
  CREATE INDEX "idx_interests_deleted_at" ON "interests"("deleted_at");
  CREATE INDEX "idx_interests_document_folder_id" ON "interests"("document_folder_id");
  CREATE INDEX "idx_interests_entity_id" ON "interests"("entity_id");
  CREATE INDEX "idx_interests_final_agreement_user_id" ON "interests"("final_agreement_user_id");
  CREATE INDEX "idx_interests_form_type_id" ON "interests"("form_type_id");
  CREATE INDEX "idx_interests_funding_round_id" ON "interests"("funding_round_id");
  CREATE INDEX "idx_interests_import_upload_id" ON "interests"("import_upload_id");
  CREATE INDEX "idx_interests_interest_entity_id" ON "interests"("interest_entity_id");
  CREATE INDEX "idx_interests_investor_id" ON "interests"("investor_id");
  CREATE INDEX "idx_interests_secondary_sale_id" ON "interests"("secondary_sale_id");
  CREATE INDEX "idx_interests_status_updated_by_id" ON "interests"("status_updated_by_id");
  CREATE INDEX "idx_interests_user_id" ON "interests"("user_id");
'
COLS_investment_instruments=("id" "category" "created_at" "currency" "deleted_at" "entity_id" "form_type_id" "import_upload_id" "investment_domicile" "json_fields" "name" "portfolio_company_id" "sector" "startup" "sub_category" "updated_at")
TEXT_COLS_investment_instruments=("category" "currency" "investment_domicile" "json_fields" "name" "sector" "sub_category")
SCHEMA_investment_instruments='
  "id" BIGINT PRIMARY KEY,
  "category" VARCHAR(255),
  "created_at" DATETIME,
  "currency" VARCHAR(255),
  "deleted_at" DATETIME,
  "entity_id" BIGINT,
  "form_type_id" BIGINT,
  "import_upload_id" BIGINT,
  "investment_domicile" VARCHAR(255),
  "json_fields" JSON,
  "name" VARCHAR(255),
  "portfolio_company_id" BIGINT,
  "sector" VARCHAR(255),
  "startup" BOOLEAN,
  "sub_category" VARCHAR(255),
  "updated_at" DATETIME
'
INDEX_investment_instruments='
  CREATE INDEX "idx_investment_instruments_deleted_at" ON "investment_instruments"("deleted_at");
  CREATE INDEX "idx_investment_instruments_entity_id" ON "investment_instruments"("entity_id");
  CREATE INDEX "idx_investment_instruments_form_type_id" ON "investment_instruments"("form_type_id");
  CREATE INDEX "idx_investment_instruments_portfolio_company_id" ON "investment_instruments"("portfolio_company_id");
'
COLS_investment_opportunities=("id" "buyer_docs_list" "company_name" "created_at" "currency" "data_room_folder_id" "document_folder_id" "entity_id" "eoi_amount_cents" "form_type_id" "fund_raise_amount_cents" "funding_round_id" "json_fields" "last_date" "lock_allocations" "lock_eoi" "logo_data" "min_ticket_size_cents" "shareable" "tag_list" "updated_at" "valuation_cents" "video_data")
TEXT_COLS_investment_opportunities=("buyer_docs_list" "company_name" "currency" "json_fields" "logo_data" "tag_list" "video_data")
SCHEMA_investment_opportunities='
  "id" BIGINT PRIMARY KEY,
  "buyer_docs_list" TEXT,
  "company_name" VARCHAR(255),
  "created_at" DATETIME,
  "currency" VARCHAR(255),
  "data_room_folder_id" BIGINT,
  "document_folder_id" BIGINT,
  "entity_id" BIGINT,
  "eoi_amount_cents" DECIMAL(20,2),
  "form_type_id" BIGINT,
  "fund_raise_amount_cents" DECIMAL(20,2),
  "funding_round_id" BIGINT,
  "json_fields" JSON,
  "last_date" DATE,
  "lock_allocations" BOOLEAN,
  "lock_eoi" BOOLEAN,
  "logo_data" TEXT,
  "min_ticket_size_cents" DECIMAL(20,2),
  "shareable" BOOLEAN,
  "tag_list" VARCHAR(255),
  "updated_at" DATETIME,
  "valuation_cents" DECIMAL(20,2),
  "video_data" TEXT
'
INDEX_investment_opportunities='
  CREATE INDEX "idx_investment_opportunities_data_room_folder_id" ON "investment_opportunities"("data_room_folder_id");
  CREATE INDEX "idx_investment_opportunities_document_folder_id" ON "investment_opportunities"("document_folder_id");
  CREATE INDEX "idx_investment_opportunities_entity_id" ON "investment_opportunities"("entity_id");
  CREATE INDEX "idx_investment_opportunities_form_type_id" ON "investment_opportunities"("form_type_id");
  CREATE INDEX "idx_investment_opportunities_funding_round_id" ON "investment_opportunities"("funding_round_id");
'
COLS_investments=("id" "amount_cents" "category" "created_at" "currency" "entity_id" "form_type_id" "funding_round" "import_upload_id" "instrument_name" "instrument_quantity" "investment_date" "investment_type" "investor_name" "json_fields" "notes" "portfolio_company_id" "price_cents" "quantity" "updated_at")
TEXT_COLS_investments=("category" "currency" "funding_round" "instrument_name" "investment_type" "investor_name" "json_fields" "notes")
SCHEMA_investments='
  "id" BIGINT PRIMARY KEY,
  "amount_cents" DECIMAL(20,2),
  "category" VARCHAR(255),
  "created_at" DATETIME,
  "currency" VARCHAR(255),
  "entity_id" BIGINT,
  "form_type_id" BIGINT,
  "funding_round" VARCHAR(255),
  "import_upload_id" INTEGER,
  "instrument_name" VARCHAR(255),
  "instrument_quantity" DECIMAL(20,2),
  "investment_date" DATE,
  "investment_type" VARCHAR(255),
  "investor_name" VARCHAR(255),
  "json_fields" JSON,
  "notes" TEXT,
  "portfolio_company_id" BIGINT,
  "price_cents" DECIMAL(20,2),
  "quantity" DECIMAL(20,2),
  "updated_at" DATETIME
'
INDEX_investments='
  CREATE INDEX "idx_investments_entity_id" ON "investments"("entity_id");
  CREATE INDEX "idx_investments_form_type_id" ON "investments"("form_type_id");
  CREATE INDEX "idx_investments_portfolio_company_id" ON "investments"("portfolio_company_id");
'
COLS_investor_kpi_mappings=("id" "ancestry" "autofill" "base_for_common_size" "category" "child_count" "compute_formula" "created_at" "data_type" "denomination" "entity_id" "form_type_id" "import_upload_id" "investor_id" "json_fields" "lower_threshold" "position" "rag_rules" "reported_kpi_name" "show_in_report" "standard_kpi_name" "updated_at" "upper_threshold")
TEXT_COLS_investor_kpi_mappings=("ancestry" "autofill" "category" "compute_formula" "data_type" "denomination" "json_fields" "rag_rules" "reported_kpi_name" "standard_kpi_name")
SCHEMA_investor_kpi_mappings='
  "id" BIGINT PRIMARY KEY,
  "ancestry" VARCHAR(255),
  "autofill" VARCHAR(255),
  "base_for_common_size" BOOLEAN,
  "category" VARCHAR(255),
  "child_count" INTEGER,
  "compute_formula" VARCHAR(255),
  "created_at" DATETIME,
  "data_type" VARCHAR(255),
  "denomination" VARCHAR(255),
  "entity_id" BIGINT,
  "form_type_id" BIGINT,
  "import_upload_id" BIGINT,
  "investor_id" BIGINT,
  "json_fields" JSON,
  "lower_threshold" DECIMAL(20,2),
  "position" INTEGER,
  "rag_rules" JSON,
  "reported_kpi_name" VARCHAR(255),
  "show_in_report" BOOLEAN,
  "standard_kpi_name" VARCHAR(255),
  "updated_at" DATETIME,
  "upper_threshold" DECIMAL(20,2)
'
INDEX_investor_kpi_mappings='
  CREATE INDEX "idx_investor_kpi_mappings_ancestry" ON "investor_kpi_mappings"("ancestry");
  CREATE INDEX "idx_investor_kpi_mappings_entity_id" ON "investor_kpi_mappings"("entity_id");
  CREATE INDEX "idx_investor_kpi_mappings_form_type_id" ON "investor_kpi_mappings"("form_type_id");
  CREATE INDEX "idx_investor_kpi_mappings_investor_id" ON "investor_kpi_mappings"("investor_id");
  CREATE INDEX "idx_investor_kpi_mappings_reported_kpi_name" ON "investor_kpi_mappings"("reported_kpi_name");
  CREATE INDEX "idx_investor_kpi_mappings_standard_kpi_name" ON "investor_kpi_mappings"("standard_kpi_name");
'
COLS_investor_kycs=("id" "PAN" "address" "agreement_committed_amount_cents" "agreement_unit_type" "all_docs_valid" "aml_status" "bank_account_number" "bank_account_type" "bank_branch" "bank_name" "bank_verification_response" "bank_verification_status" "bank_verified" "birth_date" "call_amount_cents" "collected_amount_cents" "comments" "committed_amount_cents" "completed_by_investor" "compliant" "corr_address" "created_at" "deleted_at" "distribution_amount_cents" "doc_question_answers" "docs_completed" "document_folder_id" "due_amount_cents" "entity_id" "esign_emails" "expiry_date" "form_type_id" "full_name" "ifsc_code" "import_upload_id" "investor_id" "investor_name" "investor_user_id" "investor_user_updated_at" "json_fields" "kyc_type" "notification_msg" "other_fee_cents" "pan_card_data" "pan_verification_response" "pan_verification_status" "pan_verified" "reminder_sent" "reminder_sent_date" "residency" "send_kyc_form_to_user" "signature_data" "slug" "type" "uncalled_amount_cents" "updated_at" "verified" "verified_by_id")
TEXT_COLS_investor_kycs=("PAN" "address" "agreement_unit_type" "aml_status" "bank_account_number" "bank_account_type" "bank_branch" "bank_name" "bank_verification_response" "bank_verification_status" "comments" "corr_address" "doc_question_answers" "esign_emails" "full_name" "ifsc_code" "investor_name" "json_fields" "kyc_type" "notification_msg" "pan_card_data" "pan_verification_response" "pan_verification_status" "residency" "signature_data" "slug" "type")
SCHEMA_investor_kycs='
  "id" BIGINT PRIMARY KEY,
  "PAN" VARCHAR(255),
  "address" TEXT,
  "agreement_committed_amount_cents" DECIMAL(20,2),
  "agreement_unit_type" VARCHAR(255),
  "all_docs_valid" BOOLEAN,
  "aml_status" VARCHAR(255),
  "bank_account_number" VARCHAR(255),
  "bank_account_type" VARCHAR(255),
  "bank_branch" VARCHAR(255),
  "bank_name" VARCHAR(255),
  "bank_verification_response" TEXT,
  "bank_verification_status" VARCHAR(255),
  "bank_verified" BOOLEAN,
  "birth_date" DATETIME,
  "call_amount_cents" DECIMAL(20,2),
  "collected_amount_cents" DECIMAL(20,2),
  "comments" TEXT,
  "committed_amount_cents" DECIMAL(20,2),
  "completed_by_investor" BOOLEAN,
  "compliant" BOOLEAN,
  "corr_address" TEXT,
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "distribution_amount_cents" DECIMAL(20,2),
  "doc_question_answers" JSON,
  "docs_completed" BOOLEAN,
  "document_folder_id" BIGINT,
  "due_amount_cents" DECIMAL(20,2),
  "entity_id" BIGINT,
  "esign_emails" VARCHAR(255),
  "expiry_date" DATE,
  "form_type_id" BIGINT,
  "full_name" VARCHAR(255),
  "ifsc_code" VARCHAR(255),
  "import_upload_id" BIGINT,
  "investor_id" BIGINT,
  "investor_name" VARCHAR(255),
  "investor_user_id" BIGINT,
  "investor_user_updated_at" DATETIME,
  "json_fields" JSON,
  "kyc_type" VARCHAR(255),
  "notification_msg" TEXT,
  "other_fee_cents" DECIMAL(20,2),
  "pan_card_data" TEXT,
  "pan_verification_response" TEXT,
  "pan_verification_status" VARCHAR(255),
  "pan_verified" BOOLEAN,
  "reminder_sent" BOOLEAN,
  "reminder_sent_date" DATETIME,
  "residency" VARCHAR(255),
  "send_kyc_form_to_user" BOOLEAN,
  "signature_data" TEXT,
  "slug" VARCHAR(255),
  "type" VARCHAR(255),
  "uncalled_amount_cents" DECIMAL(20,2),
  "updated_at" DATETIME,
  "verified" BOOLEAN,
  "verified_by_id" BIGINT
'
INDEX_investor_kycs='
  CREATE INDEX "idx_investor_kycs_deleted_at" ON "investor_kycs"("deleted_at");
  CREATE INDEX "idx_investor_kycs_document_folder_id" ON "investor_kycs"("document_folder_id");
  CREATE INDEX "idx_investor_kycs_entity_id" ON "investor_kycs"("entity_id");
  CREATE INDEX "idx_investor_kycs_form_type_id" ON "investor_kycs"("form_type_id");
  CREATE INDEX "idx_investor_kycs_investor_id" ON "investor_kycs"("investor_id");
  CREATE INDEX "idx_investor_kycs_investor_user_id" ON "investor_kycs"("investor_user_id");
  CREATE INDEX "idx_investor_kycs_slug" ON "investor_kycs"("slug");
  CREATE INDEX "idx_investor_kycs_verified_by_id" ON "investor_kycs"("verified_by_id");
'
COLS_investors=("id" "category" "city" "created_at" "deleted_at" "document_folder_id" "entity_id" "form_type_id" "import_upload_id" "imported" "investor_access_count" "investor_entity_id" "investor_name" "is_holdings_entity" "is_trust" "json_fields" "last_interaction_date" "pan" "primary_email" "sector" "slug" "tag_list" "unapproved_investor_access_count" "updated_at" "will_receive_email")
TEXT_COLS_investors=("category" "city" "investor_name" "json_fields" "pan" "primary_email" "sector" "slug" "tag_list")
SCHEMA_investors='
  "id" BIGINT PRIMARY KEY,
  "category" VARCHAR(255),
  "city" VARCHAR(255),
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "document_folder_id" BIGINT,
  "entity_id" INTEGER,
  "form_type_id" BIGINT,
  "import_upload_id" BIGINT,
  "imported" BOOLEAN,
  "investor_access_count" INTEGER,
  "investor_entity_id" INTEGER,
  "investor_name" VARCHAR(255),
  "is_holdings_entity" BOOLEAN,
  "is_trust" BOOLEAN,
  "json_fields" JSON,
  "last_interaction_date" DATE,
  "pan" VARCHAR(255),
  "primary_email" VARCHAR(255),
  "sector" VARCHAR(255),
  "slug" VARCHAR(255),
  "tag_list" VARCHAR(255),
  "unapproved_investor_access_count" INTEGER,
  "updated_at" DATETIME,
  "will_receive_email" INTEGER
'
INDEX_investors='
  CREATE INDEX "idx_investors_deleted_at" ON "investors"("deleted_at");
  CREATE INDEX "idx_investors_document_folder_id" ON "investors"("document_folder_id");
  CREATE INDEX "idx_investors_entity_id" ON "investors"("entity_id");
  CREATE INDEX "idx_investors_form_type_id" ON "investors"("form_type_id");
  CREATE INDEX "idx_investors_investor_entity_id_entity_id_deleted_at" ON "investors"("investor_entity_id", "entity_id", "deleted_at");
  CREATE INDEX "idx_investors_investor_entity_id" ON "investors"("investor_entity_id");
  CREATE INDEX "idx_investors_investor_name_entity_id" ON "investors"("investor_name", "entity_id");
  CREATE INDEX "idx_investors_pan" ON "investors"("pan");
  CREATE INDEX "idx_investors_slug" ON "investors"("slug");
  CREATE INDEX "idx_investors_tag_list" ON "investors"("tag_list");
'
COLS_kpi_reports=("id" "analysis" "as_of" "autofill_completed" "created_at" "deleted_at" "document_folder_id" "enable_portco_upload" "entity_id" "form_type_id" "import_upload_id" "json_fields" "notes" "owner_id" "period" "portfolio_company_id" "tag_list" "updated_at" "user_id")
TEXT_COLS_kpi_reports=("analysis" "json_fields" "notes" "period" "tag_list")
SCHEMA_kpi_reports='
  "id" BIGINT PRIMARY KEY,
  "analysis" TEXT,
  "as_of" DATE,
  "autofill_completed" BOOLEAN,
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "document_folder_id" BIGINT,
  "enable_portco_upload" BOOLEAN,
  "entity_id" BIGINT,
  "form_type_id" BIGINT,
  "import_upload_id" BIGINT,
  "json_fields" JSON,
  "notes" TEXT,
  "owner_id" BIGINT,
  "period" VARCHAR(255),
  "portfolio_company_id" BIGINT,
  "tag_list" VARCHAR(255),
  "updated_at" DATETIME,
  "user_id" BIGINT
'
INDEX_kpi_reports='
  CREATE INDEX "idx_kpi_reports_deleted_at" ON "kpi_reports"("deleted_at");
  CREATE INDEX "idx_kpi_reports_document_folder_id" ON "kpi_reports"("document_folder_id");
  CREATE INDEX "idx_kpi_reports_entity_id" ON "kpi_reports"("entity_id");
  CREATE INDEX "idx_kpi_reports_form_type_id" ON "kpi_reports"("form_type_id");
  CREATE INDEX "idx_kpi_reports_owner_id" ON "kpi_reports"("owner_id");
  CREATE INDEX "idx_kpi_reports_portfolio_company_id" ON "kpi_reports"("portfolio_company_id");
  CREATE INDEX "idx_kpi_reports_user_id" ON "kpi_reports"("user_id");
'
COLS_kpis=("id" "approved_at" "approved_by_user_id" "common_size_value" "created_at" "deleted_at" "display_value" "entity_id" "form_type_id" "import_upload_id" "investor_kpi_mapping_id" "json_fields" "kpi_report_id" "name" "notes" "owner_id" "percentage_change" "portfolio_company_id" "rag_status" "source" "status" "updated_at" "value")
TEXT_COLS_kpis=("display_value" "json_fields" "name" "notes" "rag_status" "source" "status")
SCHEMA_kpis='
  "id" BIGINT PRIMARY KEY,
  "approved_at" DATETIME,
  "approved_by_user_id" BIGINT,
  "common_size_value" DECIMAL(20,2),
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "display_value" VARCHAR(255),
  "entity_id" BIGINT,
  "form_type_id" BIGINT,
  "import_upload_id" BIGINT,
  "investor_kpi_mapping_id" BIGINT,
  "json_fields" JSON,
  "kpi_report_id" BIGINT,
  "name" VARCHAR(255),
  "notes" VARCHAR(255),
  "owner_id" BIGINT,
  "percentage_change" DECIMAL(20,2),
  "portfolio_company_id" BIGINT,
  "rag_status" JSON,
  "source" VARCHAR(255),
  "status" VARCHAR(255),
  "updated_at" DATETIME,
  "value" DECIMAL(20,2)
'
INDEX_kpis='
  CREATE INDEX "idx_kpis_approved_by_user_id" ON "kpis"("approved_by_user_id");
  CREATE INDEX "idx_kpis_deleted_at" ON "kpis"("deleted_at");
  CREATE INDEX "idx_kpis_entity_id" ON "kpis"("entity_id");
  CREATE INDEX "idx_kpis_form_type_id" ON "kpis"("form_type_id");
  CREATE INDEX "idx_kpis_investor_kpi_mapping_id" ON "kpis"("investor_kpi_mapping_id");
  CREATE INDEX "idx_kpis_kpi_report_id" ON "kpis"("kpi_report_id");
  CREATE INDEX "idx_kpis_owner_id" ON "kpis"("owner_id");
  CREATE INDEX "idx_kpis_portfolio_company_id" ON "kpis"("portfolio_company_id");
  CREATE INDEX "idx_kpis_status" ON "kpis"("status");
'
COLS_kyc_data=("id" "PAN" "birth_date" "created_at" "entity_id" "external_identifier" "investor_kyc_id" "name" "otp_resend_count" "otp_sent_at" "phone" "request_data" "response" "response_data" "source" "status" "updated_at")
TEXT_COLS_kyc_data=("PAN" "external_identifier" "name" "phone" "request_data" "response" "response_data" "source" "status")
SCHEMA_kyc_data='
  "id" BIGINT PRIMARY KEY,
  "PAN" VARCHAR(255),
  "birth_date" DATETIME,
  "created_at" DATETIME,
  "entity_id" BIGINT,
  "external_identifier" VARCHAR(255),
  "investor_kyc_id" BIGINT,
  "name" VARCHAR(255),
  "otp_resend_count" INTEGER,
  "otp_sent_at" DATETIME,
  "phone" VARCHAR(255),
  "request_data" JSON,
  "response" JSON,
  "response_data" JSON,
  "source" VARCHAR(255),
  "status" VARCHAR(255),
  "updated_at" DATETIME
'
INDEX_kyc_data='
  CREATE INDEX "idx_kyc_data_entity_id" ON "kyc_data"("entity_id");
  CREATE INDEX "idx_kyc_data_investor_kyc_id" ON "kyc_data"("investor_kyc_id");
'
COLS_notes=("id" "created_at" "deleted_at" "details" "entity_id" "investor_id" "on" "tags" "updated_at" "user_id")
TEXT_COLS_notes=("details" "tags")
SCHEMA_notes='
  "id" BIGINT PRIMARY KEY,
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "details" TEXT,
  "entity_id" INTEGER,
  "investor_id" INTEGER,
  "on" DATE,
  "tags" VARCHAR(255),
  "updated_at" DATETIME,
  "user_id" INTEGER
'
INDEX_notes='
  CREATE INDEX "idx_notes_deleted_at" ON "notes"("deleted_at");
  CREATE INDEX "idx_notes_entity_id" ON "notes"("entity_id");
  CREATE INDEX "idx_notes_investor_id" ON "notes"("investor_id");
  CREATE INDEX "idx_notes_user_id" ON "notes"("user_id");
'
COLS_offers=("id" "PAN" "acquirer_name" "address" "address_proof_data" "allocation_amount_cents" "allocation_percentage" "allocation_quantity" "amount_cents" "approved" "auto_match" "bank_account_number" "bank_name" "bank_routing_info" "bank_verification_response" "bank_verification_status" "bank_verified" "buyer_confirmation" "buyer_id" "buyer_notes" "city" "comments" "completed" "created_at" "custom_matching_vals" "deleted_at" "demat" "docs_uploaded_check" "document_folder_id" "entity_id" "esign_completed" "final_agreement" "final_agreement_user_id" "final_price" "form_type_id" "full_name" "granted_by_user_id" "holding_id" "id_proof_data" "ifsc_code" "import_upload_id" "interest_id" "investor_id" "json_fields" "notes" "offer_type" "pan_card_data" "pan_verification_response" "pan_verification_status" "pan_verified" "percentage" "price" "quantity" "secondary_sale_id" "seller_signatory_emails" "signature_data" "spa_data" "updated_at" "user_id" "verified")
TEXT_COLS_offers=("PAN" "acquirer_name" "address" "address_proof_data" "bank_account_number" "bank_name" "bank_routing_info" "bank_verification_response" "bank_verification_status" "buyer_confirmation" "buyer_notes" "city" "comments" "custom_matching_vals" "demat" "docs_uploaded_check" "full_name" "id_proof_data" "ifsc_code" "json_fields" "notes" "offer_type" "pan_card_data" "pan_verification_response" "pan_verification_status" "seller_signatory_emails" "signature_data" "spa_data")
SCHEMA_offers='
  "id" BIGINT PRIMARY KEY,
  "PAN" VARCHAR(255),
  "acquirer_name" VARCHAR(255),
  "address" TEXT,
  "address_proof_data" TEXT,
  "allocation_amount_cents" DECIMAL(20,2),
  "allocation_percentage" DECIMAL(20,2),
  "allocation_quantity" BIGINT,
  "amount_cents" DECIMAL(20,2),
  "approved" BOOLEAN,
  "auto_match" BOOLEAN,
  "bank_account_number" VARCHAR(255),
  "bank_name" VARCHAR(255),
  "bank_routing_info" TEXT,
  "bank_verification_response" TEXT,
  "bank_verification_status" VARCHAR(255),
  "bank_verified" BOOLEAN,
  "buyer_confirmation" VARCHAR(255),
  "buyer_id" BIGINT,
  "buyer_notes" TEXT,
  "city" VARCHAR(255),
  "comments" TEXT,
  "completed" BOOLEAN,
  "created_at" DATETIME,
  "custom_matching_vals" VARCHAR(255),
  "deleted_at" DATETIME,
  "demat" VARCHAR(255),
  "docs_uploaded_check" TEXT,
  "document_folder_id" BIGINT,
  "entity_id" BIGINT,
  "esign_completed" BOOLEAN,
  "final_agreement" BOOLEAN,
  "final_agreement_user_id" BIGINT,
  "final_price" DECIMAL(20,2),
  "form_type_id" BIGINT,
  "full_name" VARCHAR(255),
  "granted_by_user_id" INTEGER,
  "holding_id" BIGINT,
  "id_proof_data" TEXT,
  "ifsc_code" VARCHAR(255),
  "import_upload_id" BIGINT,
  "interest_id" BIGINT,
  "investor_id" BIGINT,
  "json_fields" JSON,
  "notes" TEXT,
  "offer_type" VARCHAR(255),
  "pan_card_data" TEXT,
  "pan_verification_response" TEXT,
  "pan_verification_status" VARCHAR(255),
  "pan_verified" BOOLEAN,
  "percentage" DECIMAL(20,2),
  "price" DECIMAL(20,2),
  "quantity" INTEGER,
  "secondary_sale_id" BIGINT,
  "seller_signatory_emails" VARCHAR(255),
  "signature_data" TEXT,
  "spa_data" TEXT,
  "updated_at" DATETIME,
  "user_id" BIGINT,
  "verified" BOOLEAN
'
INDEX_offers='
  CREATE INDEX "idx_offers_buyer_id" ON "offers"("buyer_id");
  CREATE INDEX "idx_offers_custom_matching_vals" ON "offers"("custom_matching_vals");
  CREATE INDEX "idx_offers_deleted_at" ON "offers"("deleted_at");
  CREATE INDEX "idx_offers_document_folder_id" ON "offers"("document_folder_id");
  CREATE INDEX "idx_offers_entity_id" ON "offers"("entity_id");
  CREATE INDEX "idx_offers_final_agreement_user_id" ON "offers"("final_agreement_user_id");
  CREATE INDEX "idx_offers_form_type_id" ON "offers"("form_type_id");
  CREATE INDEX "idx_offers_interest_id" ON "offers"("interest_id");
  CREATE INDEX "idx_offers_investor_id" ON "offers"("investor_id");
  CREATE INDEX "idx_offers_secondary_sale_id" ON "offers"("secondary_sale_id");
  CREATE INDEX "idx_offers_user_id" ON "offers"("user_id");
'
COLS_portfolio_attributions=("id" "bought_pi_id" "cost_of_sold_cents" "created_at" "deleted_at" "entity_id" "fund_id" "gain_cents" "investment_date" "quantity" "sale_amount_cents" "sold_pi_id" "updated_at")
TEXT_COLS_portfolio_attributions=()
SCHEMA_portfolio_attributions='
  "id" BIGINT PRIMARY KEY,
  "bought_pi_id" BIGINT,
  "cost_of_sold_cents" DECIMAL(20,2),
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "entity_id" BIGINT,
  "fund_id" BIGINT,
  "gain_cents" DECIMAL(20,2),
  "investment_date" DATE,
  "quantity" DECIMAL(20,2),
  "sale_amount_cents" DECIMAL(20,2),
  "sold_pi_id" BIGINT,
  "updated_at" DATETIME
'
INDEX_portfolio_attributions='
  CREATE INDEX "idx_portfolio_attributions_bought_pi_id_deleted_at_sold_pi_id_quantity" ON "portfolio_attributions"("bought_pi_id", "deleted_at", "sold_pi_id", "quantity");
  CREATE INDEX "idx_portfolio_attributions_bought_pi_id_deleted_at_sold_pi_id" ON "portfolio_attributions"("bought_pi_id", "deleted_at", "sold_pi_id");
  CREATE INDEX "idx_portfolio_attributions_bought_pi_id" ON "portfolio_attributions"("bought_pi_id");
  CREATE INDEX "idx_portfolio_attributions_deleted_at" ON "portfolio_attributions"("deleted_at");
  CREATE INDEX "idx_portfolio_attributions_entity_id" ON "portfolio_attributions"("entity_id");
  CREATE INDEX "idx_portfolio_attributions_fund_id" ON "portfolio_attributions"("fund_id");
  CREATE INDEX "idx_portfolio_attributions_sold_pi_id" ON "portfolio_attributions"("sold_pi_id");
'
COLS_portfolio_cashflows=("id" "aggregate_portfolio_investment_id" "amount_cents" "created_at" "document_folder_id" "entity_id" "form_type_id" "fund_id" "import_upload_id" "instrument" "investment_instrument_id" "json_fields" "notes" "payment_date" "portfolio_company_id" "tag" "updated_at")
TEXT_COLS_portfolio_cashflows=("instrument" "json_fields" "notes" "tag")
SCHEMA_portfolio_cashflows='
  "id" BIGINT PRIMARY KEY,
  "aggregate_portfolio_investment_id" BIGINT,
  "amount_cents" DECIMAL(20,2),
  "created_at" DATETIME,
  "document_folder_id" BIGINT,
  "entity_id" BIGINT,
  "form_type_id" BIGINT,
  "fund_id" BIGINT,
  "import_upload_id" BIGINT,
  "instrument" VARCHAR(255),
  "investment_instrument_id" BIGINT,
  "json_fields" JSON,
  "notes" TEXT,
  "payment_date" DATE,
  "portfolio_company_id" BIGINT,
  "tag" VARCHAR(255),
  "updated_at" DATETIME
'
INDEX_portfolio_cashflows='
  CREATE INDEX "idx_portfolio_cashflows_aggregate_portfolio_investment_id" ON "portfolio_cashflows"("aggregate_portfolio_investment_id");
  CREATE INDEX "idx_portfolio_cashflows_document_folder_id" ON "portfolio_cashflows"("document_folder_id");
  CREATE INDEX "idx_portfolio_cashflows_entity_id" ON "portfolio_cashflows"("entity_id");
  CREATE INDEX "idx_portfolio_cashflows_form_type_id" ON "portfolio_cashflows"("form_type_id");
  CREATE INDEX "idx_portfolio_cashflows_fund_id" ON "portfolio_cashflows"("fund_id");
  CREATE INDEX "idx_portfolio_cashflows_investment_instrument_id" ON "portfolio_cashflows"("investment_instrument_id");
  CREATE INDEX "idx_portfolio_cashflows_payment_date" ON "portfolio_cashflows"("payment_date");
  CREATE INDEX "idx_portfolio_cashflows_portfolio_company_id" ON "portfolio_cashflows"("portfolio_company_id");
'
COLS_portfolio_investments=("id" "aggregate_portfolio_investment_id" "amount_cents" "base_amount_cents" "capital_commitment_id" "capital_distribution_id" "category" "compliant" "conversion_date" "cost_of_remaining_cents" "cost_of_sold_cents" "created_at" "deleted_at" "document_folder_id" "entity_id" "ex_expenses_amount_cents" "ex_expenses_base_amount_cents" "exchange_rate_id" "excused_folio_ids" "fmv_cents" "folio_id" "form_type_id" "fund_id" "gain_cents" "import_upload_id" "instrument_currency_cost_of_remaining_cents" "instrument_currency_fmv_cents" "instrument_currency_unrealized_gain_cents" "investment_date" "investment_domicile" "investment_instrument_id" "json_fields" "net_amount_cents" "net_bought_amount_cents" "net_bought_quantity" "net_quantity" "notes" "orignal_id" "portfolio_company_id" "portfolio_company_name" "proforma" "quantity" "quantity_as_of_date" "ref_id" "reference_id" "sector" "snapshot" "snapshot_date" "sold_quantity" "startup" "sub_category" "tracking_amount_cents" "tracking_fmv_cents" "transfer_amount_cents" "transfer_quantity" "unrealized_gain_cents" "updated_at" "valuation_id")
TEXT_COLS_portfolio_investments=("category" "excused_folio_ids" "folio_id" "investment_domicile" "json_fields" "notes" "portfolio_company_name" "sector" "sub_category")
SCHEMA_portfolio_investments='
  "id" BIGINT PRIMARY KEY,
  "aggregate_portfolio_investment_id" BIGINT,
  "amount_cents" DECIMAL(20,2),
  "base_amount_cents" DECIMAL(20,2),
  "capital_commitment_id" BIGINT,
  "capital_distribution_id" BIGINT,
  "category" VARCHAR(255),
  "compliant" BOOLEAN,
  "conversion_date" DATE,
  "cost_of_remaining_cents" DECIMAL(20,2),
  "cost_of_sold_cents" DECIMAL(20,2),
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "document_folder_id" BIGINT,
  "entity_id" BIGINT,
  "ex_expenses_amount_cents" DECIMAL(20,2),
  "ex_expenses_base_amount_cents" DECIMAL(20,2),
  "exchange_rate_id" BIGINT,
  "excused_folio_ids" JSON,
  "fmv_cents" DECIMAL(20,2),
  "folio_id" VARCHAR(255),
  "form_type_id" BIGINT,
  "fund_id" BIGINT,
  "gain_cents" DECIMAL(20,2),
  "import_upload_id" BIGINT,
  "instrument_currency_cost_of_remaining_cents" DECIMAL(20,2),
  "instrument_currency_fmv_cents" DECIMAL(20,2),
  "instrument_currency_unrealized_gain_cents" DECIMAL(20,2),
  "investment_date" DATE,
  "investment_domicile" VARCHAR(255),
  "investment_instrument_id" BIGINT,
  "json_fields" JSON,
  "net_amount_cents" DECIMAL(20,2),
  "net_bought_amount_cents" DECIMAL(20,2),
  "net_bought_quantity" DECIMAL(20,2),
  "net_quantity" DECIMAL(20,2),
  "notes" TEXT,
  "orignal_id" BIGINT,
  "portfolio_company_id" BIGINT,
  "portfolio_company_name" VARCHAR(255),
  "proforma" BOOLEAN,
  "quantity" DECIMAL(20,2),
  "quantity_as_of_date" DECIMAL(20,2),
  "ref_id" BIGINT,
  "reference_id" BIGINT,
  "sector" VARCHAR(255),
  "snapshot" BOOLEAN,
  "snapshot_date" DATE,
  "sold_quantity" DECIMAL(20,2),
  "startup" BOOLEAN,
  "sub_category" VARCHAR(255),
  "tracking_amount_cents" DECIMAL(20,2),
  "tracking_fmv_cents" DECIMAL(20,2),
  "transfer_amount_cents" DECIMAL(20,2),
  "transfer_quantity" DECIMAL(20,2),
  "unrealized_gain_cents" DECIMAL(20,2),
  "updated_at" DATETIME,
  "valuation_id" BIGINT
'
INDEX_portfolio_investments='
  CREATE INDEX "idx_portfolio_investments_aggregate_portfolio_investment_id" ON "portfolio_investments"("aggregate_portfolio_investment_id");
  CREATE INDEX "idx_portfolio_investments_capital_commitment_id" ON "portfolio_investments"("capital_commitment_id");
  CREATE INDEX "idx_portfolio_investments_capital_distribution_id" ON "portfolio_investments"("capital_distribution_id");
  CREATE INDEX "idx_portfolio_investments_conversion_date" ON "portfolio_investments"("conversion_date");
  CREATE INDEX "idx_portfolio_investments_deleted_at" ON "portfolio_investments"("deleted_at");
  CREATE INDEX "idx_portfolio_investments_document_folder_id" ON "portfolio_investments"("document_folder_id");
  CREATE INDEX "idx_portfolio_investments_entity_id" ON "portfolio_investments"("entity_id");
  CREATE INDEX "idx_portfolio_investments_exchange_rate_id" ON "portfolio_investments"("exchange_rate_id");
  CREATE INDEX "idx_portfolio_investments_form_type_id" ON "portfolio_investments"("form_type_id");
  CREATE INDEX "idx_portfolio_investments_fund_id" ON "portfolio_investments"("fund_id");
  CREATE INDEX "idx_portfolio_investments_id_investment_date" ON "portfolio_investments"("id", "investment_date");
  CREATE INDEX "idx_portfolio_investments_investment_date" ON "portfolio_investments"("investment_date");
  CREATE INDEX "idx_portfolio_investments_investment_instrument_id" ON "portfolio_investments"("investment_instrument_id");
  CREATE INDEX "idx_portfolio_investments_portfolio_company_id_id" ON "portfolio_investments"("portfolio_company_id", "id");
  CREATE INDEX "idx_portfolio_investments_portfolio_company_id" ON "portfolio_investments"("portfolio_company_id");
  CREATE INDEX "idx_portfolio_investments_snapshot_date" ON "portfolio_investments"("snapshot_date");
  CREATE INDEX "idx_portfolio_investments_valuation_id" ON "portfolio_investments"("valuation_id");
'
COLS_scenario_investments=("id" "created_at" "entity_id" "fund_id" "investment_instrument_id" "notes" "portfolio_company_id" "portfolio_scenario_id" "price_cents" "quantity" "transaction_date" "updated_at" "user_id")
TEXT_COLS_scenario_investments=("notes")
SCHEMA_scenario_investments='
  "id" BIGINT PRIMARY KEY,
  "created_at" DATETIME,
  "entity_id" BIGINT,
  "fund_id" BIGINT,
  "investment_instrument_id" BIGINT,
  "notes" TEXT,
  "portfolio_company_id" BIGINT,
  "portfolio_scenario_id" BIGINT,
  "price_cents" DECIMAL(20,2),
  "quantity" DECIMAL(20,2),
  "transaction_date" DATE,
  "updated_at" DATETIME,
  "user_id" BIGINT
'
INDEX_scenario_investments='
  CREATE INDEX "idx_scenario_investments_entity_id" ON "scenario_investments"("entity_id");
  CREATE INDEX "idx_scenario_investments_fund_id" ON "scenario_investments"("fund_id");
  CREATE INDEX "idx_scenario_investments_investment_instrument_id" ON "scenario_investments"("investment_instrument_id");
  CREATE INDEX "idx_scenario_investments_portfolio_company_id" ON "scenario_investments"("portfolio_company_id");
  CREATE INDEX "idx_scenario_investments_portfolio_scenario_id" ON "scenario_investments"("portfolio_scenario_id");
  CREATE INDEX "idx_scenario_investments_user_id" ON "scenario_investments"("user_id");
'
COLS_secondary_sales=("id" "active" "allocation_amount_cents" "allocation_percentage" "allocation_quantity" "allocation_status" "buyer_doc_list" "cmf_allocation_percentage" "created_at" "custom_matching_fields" "data_room_folder_id" "deleted_at" "disable_bank_kyc" "disable_pan_kyc" "document_folder_id" "end_date" "entity_id" "final_price" "finalized" "form_type_id" "indicative_quantity" "interest_form_type_id" "interest_pivot_custom_fields" "json_fields" "lock_allocations" "manage_interests" "manage_offers" "max_price" "min_price" "name" "no_interest_emails" "no_offer_emails" "notification_employee_ids" "offer_end_date" "offer_form_type_id" "offer_pivot_custom_fields" "percent_allowed" "price_type" "sale_type" "secondary_sale_form_type_id" "seller_doc_list" "seller_transaction_fees_pct" "show_holdings" "show_quantity" "spa_data" "start_date" "support_email" "total_interest_amount_cents" "total_interest_quantity" "total_offered_amount_cents" "total_offered_quantity" "updated_at" "visible_externally")
TEXT_COLS_secondary_sales=("allocation_status" "buyer_doc_list" "cmf_allocation_percentage" "custom_matching_fields" "interest_pivot_custom_fields" "json_fields" "name" "notification_employee_ids" "offer_pivot_custom_fields" "price_type" "sale_type" "seller_doc_list" "show_quantity" "spa_data" "support_email")
SCHEMA_secondary_sales='
  "id" BIGINT PRIMARY KEY,
  "active" BOOLEAN,
  "allocation_amount_cents" DECIMAL(20,2),
  "allocation_percentage" DECIMAL(20,2),
  "allocation_quantity" DECIMAL(20,2),
  "allocation_status" VARCHAR(255),
  "buyer_doc_list" TEXT,
  "cmf_allocation_percentage" TEXT,
  "created_at" DATETIME,
  "custom_matching_fields" TEXT,
  "data_room_folder_id" BIGINT,
  "deleted_at" DATETIME,
  "disable_bank_kyc" BOOLEAN,
  "disable_pan_kyc" BOOLEAN,
  "document_folder_id" BIGINT,
  "end_date" DATE,
  "entity_id" BIGINT,
  "final_price" DECIMAL(20,2),
  "finalized" BOOLEAN,
  "form_type_id" BIGINT,
  "indicative_quantity" BIGINT,
  "interest_form_type_id" BIGINT,
  "interest_pivot_custom_fields" TEXT,
  "json_fields" JSON,
  "lock_allocations" BOOLEAN,
  "manage_interests" BOOLEAN,
  "manage_offers" BOOLEAN,
  "max_price" DECIMAL(20,2),
  "min_price" DECIMAL(20,2),
  "name" VARCHAR(255),
  "no_interest_emails" BOOLEAN,
  "no_offer_emails" BOOLEAN,
  "notification_employee_ids" VARCHAR(255),
  "offer_end_date" DATE,
  "offer_form_type_id" BIGINT,
  "offer_pivot_custom_fields" TEXT,
  "percent_allowed" INTEGER,
  "price_type" VARCHAR(255),
  "sale_type" VARCHAR(255),
  "secondary_sale_form_type_id" BIGINT,
  "seller_doc_list" TEXT,
  "seller_transaction_fees_pct" DECIMAL(20,2),
  "show_holdings" BOOLEAN,
  "show_quantity" VARCHAR(255),
  "spa_data" TEXT,
  "start_date" DATE,
  "support_email" VARCHAR(255),
  "total_interest_amount_cents" DECIMAL(20,2),
  "total_interest_quantity" INTEGER,
  "total_offered_amount_cents" DECIMAL(20,2),
  "total_offered_quantity" INTEGER,
  "updated_at" DATETIME,
  "visible_externally" BOOLEAN
'
INDEX_secondary_sales='
  CREATE INDEX "idx_secondary_sales_data_room_folder_id" ON "secondary_sales"("data_room_folder_id");
  CREATE INDEX "idx_secondary_sales_deleted_at" ON "secondary_sales"("deleted_at");
  CREATE INDEX "idx_secondary_sales_document_folder_id" ON "secondary_sales"("document_folder_id");
  CREATE INDEX "idx_secondary_sales_entity_id" ON "secondary_sales"("entity_id");
  CREATE INDEX "idx_secondary_sales_form_type_id" ON "secondary_sales"("form_type_id");
  CREATE INDEX "idx_secondary_sales_interest_form_type_id" ON "secondary_sales"("interest_form_type_id");
  CREATE INDEX "idx_secondary_sales_offer_form_type_id" ON "secondary_sales"("offer_form_type_id");
  CREATE INDEX "idx_secondary_sales_secondary_sale_form_type_id" ON "secondary_sales"("secondary_sale_form_type_id");
'
COLS_stock_adjustments=("id" "adjustment" "category" "created_at" "entity_id" "investment_instrument_id" "notes" "portfolio_company_id" "sub_category" "updated_at" "user_id")
TEXT_COLS_stock_adjustments=("category" "notes" "sub_category")
SCHEMA_stock_adjustments='
  "id" BIGINT PRIMARY KEY,
  "adjustment" DECIMAL(20,2),
  "category" VARCHAR(255),
  "created_at" DATETIME,
  "entity_id" BIGINT,
  "investment_instrument_id" BIGINT,
  "notes" TEXT,
  "portfolio_company_id" BIGINT,
  "sub_category" VARCHAR(255),
  "updated_at" DATETIME,
  "user_id" BIGINT
'
INDEX_stock_adjustments='
  CREATE INDEX "idx_stock_adjustments_entity_id" ON "stock_adjustments"("entity_id");
  CREATE INDEX "idx_stock_adjustments_investment_instrument_id" ON "stock_adjustments"("investment_instrument_id");
  CREATE INDEX "idx_stock_adjustments_portfolio_company_id" ON "stock_adjustments"("portfolio_company_id");
  CREATE INDEX "idx_stock_adjustments_user_id" ON "stock_adjustments"("user_id");
'
COLS_stock_conversions=("id" "conversion_date" "created_at" "deleted_at" "entity_id" "from_instrument_id" "from_portfolio_investment_id" "from_quantity" "fund_id" "notes" "to_instrument_id" "to_portfolio_investment_id" "to_quantity" "updated_at")
TEXT_COLS_stock_conversions=("notes")
SCHEMA_stock_conversions='
  "id" BIGINT PRIMARY KEY,
  "conversion_date" DATE,
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "entity_id" BIGINT,
  "from_instrument_id" BIGINT,
  "from_portfolio_investment_id" BIGINT,
  "from_quantity" DECIMAL(20,2),
  "fund_id" BIGINT,
  "notes" TEXT,
  "to_instrument_id" BIGINT,
  "to_portfolio_investment_id" BIGINT,
  "to_quantity" DECIMAL(20,2),
  "updated_at" DATETIME
'
INDEX_stock_conversions='
  CREATE INDEX "idx_stock_conversions_conversion_date" ON "stock_conversions"("conversion_date");
  CREATE INDEX "idx_stock_conversions_deleted_at" ON "stock_conversions"("deleted_at");
  CREATE INDEX "idx_stock_conversions_entity_id" ON "stock_conversions"("entity_id");
  CREATE INDEX "idx_stock_conversions_from_instrument_id" ON "stock_conversions"("from_instrument_id");
  CREATE INDEX "idx_stock_conversions_from_portfolio_investment_id_conversion_date_deleted_at" ON "stock_conversions"("from_portfolio_investment_id", "conversion_date", "deleted_at");
  CREATE INDEX "idx_stock_conversions_from_portfolio_investment_id" ON "stock_conversions"("from_portfolio_investment_id");
  CREATE INDEX "idx_stock_conversions_fund_id" ON "stock_conversions"("fund_id");
  CREATE INDEX "idx_stock_conversions_to_instrument_id" ON "stock_conversions"("to_instrument_id");
  CREATE INDEX "idx_stock_conversions_to_portfolio_investment_id" ON "stock_conversions"("to_portfolio_investment_id");
'
COLS_tasks=("id" "assigned_to_id" "category" "completed" "created_at" "details" "document_folder_id" "due_date" "entity_id" "for_entity_id" "for_support" "form_type_id" "import_upload_id" "is_exception" "original_start_date" "owner_id" "owner_type" "response" "tags" "task_recurrence_rule_id" "task_template_id" "updated_at" "user_id")
TEXT_COLS_tasks=("category" "details" "owner_type" "response" "tags")
SCHEMA_tasks='
  "id" BIGINT PRIMARY KEY,
  "assigned_to_id" INTEGER,
  "category" VARCHAR(255),
  "completed" BOOLEAN,
  "created_at" DATETIME,
  "details" TEXT,
  "document_folder_id" BIGINT,
  "due_date" DATE,
  "entity_id" BIGINT,
  "for_entity_id" BIGINT,
  "for_support" BOOLEAN,
  "form_type_id" BIGINT,
  "import_upload_id" INTEGER,
  "is_exception" BOOLEAN,
  "original_start_date" DATETIME,
  "owner_id" BIGINT,
  "owner_type" VARCHAR(255),
  "response" TEXT,
  "tags" VARCHAR(255),
  "task_recurrence_rule_id" BIGINT,
  "task_template_id" BIGINT,
  "updated_at" DATETIME,
  "user_id" BIGINT
'
INDEX_tasks='
  CREATE INDEX "idx_tasks_document_folder_id" ON "tasks"("document_folder_id");
  CREATE INDEX "idx_tasks_entity_id" ON "tasks"("entity_id");
  CREATE INDEX "idx_tasks_for_entity_id" ON "tasks"("for_entity_id");
  CREATE INDEX "idx_tasks_form_type_id" ON "tasks"("form_type_id");
  CREATE INDEX "idx_tasks_import_upload_id" ON "tasks"("import_upload_id");
  CREATE INDEX "idx_tasks_owner_type_owner_id" ON "tasks"("owner_type", "owner_id");
  CREATE INDEX "idx_tasks_task_recurrence_rule_id" ON "tasks"("task_recurrence_rule_id");
  CREATE INDEX "idx_tasks_task_template_id" ON "tasks"("task_template_id");
  CREATE INDEX "idx_tasks_user_id" ON "tasks"("user_id");
'
COLS_users=("id" "accept_terms" "accepted_terms_on" "access_rights_cache" "access_rights_cached_permissions" "active" "advisor_entity_id" "advisor_entity_roles" "call_code" "confirmation_sent_at" "confirmation_token" "confirmed_at" "created_at" "curr_role" "current_sign_in_at" "current_sign_in_ip" "deleted_at" "dept" "email" "enable_support" "encrypted_password" "entity_id" "entity_type" "extended_permissions" "failed_attempts" "first_name" "form_type_id" "investor_advisor_id" "json_fields" "last_name" "last_sign_in_at" "last_sign_in_ip" "last_synced_at" "last_synced_ccf_hex" "locked_at" "permissions" "phone" "primary_region" "primary_region_id" "regions" "remember_created_at" "reset_password_sent_at" "reset_password_token" "sale_notification" "session_token" "sign_in_count" "signature_data" "system_created" "tag_list" "unlock_token" "updated_at" "whatsapp_enabled")
TEXT_COLS_users=("access_rights_cache" "advisor_entity_roles" "call_code" "confirmation_token" "curr_role" "current_sign_in_ip" "dept" "email" "encrypted_password" "entity_type" "first_name" "json_fields" "last_name" "last_sign_in_ip" "last_synced_ccf_hex" "phone" "primary_region" "regions" "reset_password_token" "session_token" "signature_data" "tag_list" "unlock_token")
SCHEMA_users='
  "id" BIGINT PRIMARY KEY,
  "accept_terms" BOOLEAN,
  "accepted_terms_on" DATETIME,
  "access_rights_cache" TEXT,
  "access_rights_cached_permissions" INTEGER,
  "active" BOOLEAN,
  "advisor_entity_id" BIGINT,
  "advisor_entity_roles" VARCHAR(255),
  "call_code" VARCHAR(255),
  "confirmation_sent_at" DATETIME,
  "confirmation_token" VARCHAR(255),
  "confirmed_at" DATETIME,
  "created_at" DATETIME,
  "curr_role" VARCHAR(255),
  "current_sign_in_at" DATETIME,
  "current_sign_in_ip" VARCHAR(255),
  "deleted_at" DATETIME,
  "dept" VARCHAR(255),
  "email" VARCHAR(255),
  "enable_support" BOOLEAN,
  "encrypted_password" VARCHAR(255),
  "entity_id" INTEGER,
  "entity_type" VARCHAR(255),
  "extended_permissions" INTEGER,
  "failed_attempts" INTEGER,
  "first_name" VARCHAR(255),
  "form_type_id" BIGINT,
  "investor_advisor_id" BIGINT,
  "json_fields" JSON,
  "last_name" VARCHAR(255),
  "last_sign_in_at" DATETIME,
  "last_sign_in_ip" VARCHAR(255),
  "last_synced_at" DATETIME,
  "last_synced_ccf_hex" VARCHAR(255),
  "locked_at" DATETIME,
  "permissions" BIGINT,
  "phone" VARCHAR(255),
  "primary_region" VARCHAR(255),
  "primary_region_id" INTEGER,
  "regions" VARCHAR(255),
  "remember_created_at" DATETIME,
  "reset_password_sent_at" DATETIME,
  "reset_password_token" VARCHAR(255),
  "sale_notification" BOOLEAN,
  "session_token" VARCHAR(255),
  "sign_in_count" INTEGER,
  "signature_data" TEXT,
  "system_created" BOOLEAN,
  "tag_list" VARCHAR(255),
  "unlock_token" VARCHAR(255),
  "updated_at" DATETIME,
  "whatsapp_enabled" BOOLEAN
'
INDEX_users='
  CREATE INDEX "idx_users_confirmation_token" ON "users"("confirmation_token");
  CREATE INDEX "idx_users_deleted_at" ON "users"("deleted_at");
  CREATE INDEX "idx_users_email" ON "users"("email");
  CREATE INDEX "idx_users_entity_id" ON "users"("entity_id");
  CREATE INDEX "idx_users_form_type_id" ON "users"("form_type_id");
  CREATE INDEX "idx_users_last_synced_ccf_hex" ON "users"("last_synced_ccf_hex");
  CREATE INDEX "idx_users_regions" ON "users"("regions");
  CREATE INDEX "idx_users_reset_password_token" ON "users"("reset_password_token");
'
COLS_valuations=("id" "base_amount_cents" "category" "created_at" "deleted_at" "entity_id" "form_type_id" "import_upload_id" "investment_instrument_id" "json_fields" "name" "net_valuation_cents" "owner_id" "owner_type" "per_share_value_cents" "report_data" "sub_category" "synthetic" "updated_at" "valuation_cents" "valuation_date")
TEXT_COLS_valuations=("category" "json_fields" "name" "owner_type" "report_data" "sub_category")
SCHEMA_valuations='
  "id" BIGINT PRIMARY KEY,
  "base_amount_cents" DECIMAL(20,2),
  "category" VARCHAR(255),
  "created_at" DATETIME,
  "deleted_at" DATETIME,
  "entity_id" BIGINT,
  "form_type_id" BIGINT,
  "import_upload_id" BIGINT,
  "investment_instrument_id" BIGINT,
  "json_fields" JSON,
  "name" VARCHAR(255),
  "net_valuation_cents" DECIMAL(20,2),
  "owner_id" BIGINT,
  "owner_type" VARCHAR(255),
  "per_share_value_cents" DECIMAL(20,2),
  "report_data" TEXT,
  "sub_category" VARCHAR(255),
  "synthetic" BOOLEAN,
  "updated_at" DATETIME,
  "valuation_cents" DECIMAL(20,2),
  "valuation_date" DATE
'
INDEX_valuations='
  CREATE INDEX "idx_valuations_deleted_at" ON "valuations"("deleted_at");
  CREATE INDEX "idx_valuations_entity_id" ON "valuations"("entity_id");
  CREATE INDEX "idx_valuations_form_type_id" ON "valuations"("form_type_id");
  CREATE INDEX "idx_valuations_investment_instrument_id_deleted_at_synthetic_valuation_date" ON "valuations"("investment_instrument_id", "deleted_at", "synthetic", "valuation_date");
  CREATE INDEX "idx_valuations_investment_instrument_id" ON "valuations"("investment_instrument_id");
  CREATE INDEX "idx_valuations_owner_id_owner_type_deleted_at" ON "valuations"("owner_id", "owner_type", "deleted_at");
  CREATE INDEX "idx_valuations_owner_type_owner_id" ON "valuations"("owner_type", "owner_id");
  CREATE INDEX "idx_valuations_valuation_date" ON "valuations"("valuation_date");
'

############################################
# MAIN EXECUTION
############################################

rm -f "$SQLITE_DB"

# Initialize SQLite with pragmas
sqlite3 "$SQLITE_DB" <<SQL
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA temp_store = FILE;
PRAGMA cache_size = -100000;
SQL

for table in "${TABLES[@]}"; do
  echo ">>> Processing table: $table"

  # Indirect variable access
  cols_var="COLS_$table[@]"
  text_cols_var="TEXT_COLS_$table[@]"
  schema_var="SCHEMA_$table"
  index_var="INDEX_$table"

  if [[ -z "${!schema_var:-}" ]]; then
    echo "  Warning: No definition for table $table, skipping."
    continue
  fi

  COLS=("${!cols_var}")
  TEXT_COLS=("${!text_cols_var}")
  SCHEMA="${!schema_var}"
  INDEX_SQL="${!index_var}"

  EXPORT_TSV="/tmp/${table}_export_entity_${ENTITY_ID}.tsv"

  ############################################
  # 1) Export Source → TSV
  ############################################
  STEP_START=$(date +%s)

  SELECT_LIST=""
  for c in "${COLS[@]}"; do
    is_text=0
    for tc in "${TEXT_COLS[@]}"; do
      if [[ "$c" == "$tc" ]]; then is_text=1; break; fi
    done

    if [[ $is_text -eq 1 ]]; then
      if [[ "$ADAPTER" == "sqlite3" ]] || [[ -n "$SOURCE_SQLITE_DB" ]]; then
        SELECT_LIST+="REPLACE(REPLACE(REPLACE(REPLACE(IFNULL(\"${c}\",\"\"), \"\"\"\", \"###DQ###\"), CHAR(10), \"###NL###\"), CHAR(13), \"###CR###\"), CHAR(9), \"###TAB###\"),"
      else
        SELECT_LIST+="REPLACE(REPLACE(REPLACE(REPLACE(IFNULL(\`${c}\`,''), '\"', '###DQ###'), CHAR(10), '###NL###'), CHAR(13), '###CR###'), CHAR(9), '###TAB###'),"
      fi
    else
      if [[ "$ADAPTER" == "sqlite3" ]] || [[ -n "$SOURCE_SQLITE_DB" ]]; then
        SELECT_LIST+="IFNULL(\"${c}\",\"\"),"
      else
        SELECT_LIST+="IFNULL(\`${c}\`,''),"
      fi
    fi
  done
  SELECT_LIST="${SELECT_LIST%,}"

  # Filtering by ENTITY_ID
  HAS_ENTITY_ID=0
  for c in "${COLS[@]}"; do
    if [[ "$c" == "entity_id" ]]; then HAS_ENTITY_ID=1; break; fi
  done

  if [[ "$table" == "entities" ]]; then
    if [[ "$ADAPTER" == "sqlite3" ]] || [[ -n "$SOURCE_SQLITE_DB" ]]; then
      WHERE_CLAUSE="WHERE \"id\" = ${ENTITY_ID}"
    else
      WHERE_CLAUSE="WHERE \`id\` = ${ENTITY_ID}"
    fi
  elif [[ $HAS_ENTITY_ID -eq 1 ]]; then
    if [[ "$ADAPTER" == "sqlite3" ]] || [[ -n "$SOURCE_SQLITE_DB" ]]; then
      WHERE_CLAUSE="WHERE \"entity_id\" = ${ENTITY_ID}"
    else
      WHERE_CLAUSE="WHERE \`entity_id\` = ${ENTITY_ID}"
    fi
  else
    WHERE_CLAUSE="WHERE 1=1"
  fi

  # Some tables don't have deleted_at
  HAS_DELETED_AT=0
  for c in "${COLS[@]}"; do
    if [[ "$c" == "deleted_at" ]]; then HAS_DELETED_AT=1; break; fi
  done

  if [[ $HAS_DELETED_AT -eq 1 ]]; then
    if [[ "$ADAPTER" == "sqlite3" ]] || [[ -n "$SOURCE_SQLITE_DB" ]]; then
      WHERE_CLAUSE="${WHERE_CLAUSE} AND \"deleted_at\" IS NULL"
    else
      WHERE_CLAUSE="${WHERE_CLAUSE} AND \`deleted_at\` IS NULL"
    fi
  fi

  echo "  Step 1: Exporting $table (entity_id=$ENTITY_ID) → TSV"
  if [[ "$ADAPTER" == "sqlite3" ]] || [[ -n "$SOURCE_SQLITE_DB" ]]; then
    SQLITE_SOURCE="${SOURCE_SQLITE_DB:-$MYSQL_DB}"
    QUERY="SELECT ${SELECT_LIST} FROM \"${table}\" ${WHERE_CLAUSE};"
    sqlite3 "$SQLITE_SOURCE" <<SQL | pv -l -t -e -r -a > "$EXPORT_TSV"
.mode tabs
.nullvalue \\N
$QUERY
SQL
  else
    QUERY="SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SELECT ${SELECT_LIST} FROM \`${table}\` ${WHERE_CLAUSE};"
    mysql_cmd -e "${QUERY}" | pv -l -t -e -r -a > "$EXPORT_TSV"
  fi
  log_step_time "Export $table" "$STEP_START"

  ############################################
  # 2) Create Table Schema
  ############################################
  STEP_START=$(date +%s)
  echo "  Step 2: Creating schema for $table"
  # Quote column names in SCHEMA by the ruby generator
  sqlite3 "$SQLITE_DB" "CREATE TABLE \"$table\" ($SCHEMA);"
  log_step_time "Schema $table" "$STEP_START"

  ############################################
  # 3) Import TSV → SQLite
  ############################################
  STEP_START=$(date +%s)
  if [ -f "$EXPORT_TSV" ]; then
    FILE_SIZE=$(stat -c%s "$EXPORT_TSV")
    if [ "$FILE_SIZE" -gt 0 ]; then
      echo "  Step 3: Importing $table TSV into SQLite"
      pv -s "$FILE_SIZE" "$EXPORT_TSV" | sqlite3 "$SQLITE_DB" \
        -cmd ".mode tabs" \
        -cmd ".nullvalue \\N" \
        -cmd "BEGIN;" \
        ".import /dev/stdin \"$table\"" \
        "COMMIT;"
    else
      echo "  Step 3: TSV is empty for $table, skipping import."
    fi
  else
    echo "  Step 3: Export file not found for $table."
  fi
  log_step_time "Import $table" "$STEP_START"

  ############################################
  # 4) Post-Import Cleanup & Indexing
  ############################################
  STEP_START=$(date +%s)
  echo "  Step 4: Cleanup & Indexing for $table"

  CLEANUP_SQL=""
  UPDATE_SET=""

  for c in "${COLS[@]}"; do
    if [[ "$c" == "id" ]]; then continue; fi

    is_text=0
    for tc in "${TEXT_COLS[@]}"; do
      if [[ "$c" == "$tc" ]]; then is_text=1; break; fi
    done

    if [[ $is_text -eq 1 ]]; then
      UPDATE_SET+="\"$c\" = NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(IFNULL(\"$c\", ''), '###DQ###', '\"'), '###NL###', CHAR(10)), '###CR###', CHAR(13)), '###TAB###', CHAR(9)), ''), "
    else
      UPDATE_SET+="\"$c\" = NULLIF(\"$c\", ''), "
    fi
  done

  if [[ -n "$UPDATE_SET" ]]; then
    UPDATE_SET="${UPDATE_SET%, }"
    CLEANUP_SQL="UPDATE \"$table\" SET $UPDATE_SET;"
    echo "  Applying character restoration and NULL cleanup for $table..."
    sqlite3 "$SQLITE_DB" "$CLEANUP_SQL"
  fi

  # Index creation with error handling for duplicates
  # Wrap the index sql in double quotes in ruby already, now just pipe it
  echo "$INDEX_SQL" | sqlite3 "$SQLITE_DB" 2>/dev/null || echo "Some indices might already exist, continuing..."
  sqlite3 "$SQLITE_DB" <<SQL
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
ANALYZE $table;
SQL
  log_step_time "Post-process $table" "$STEP_START"

  rm -f "$EXPORT_TSV"
done

# Run global ANALYZE to optimize cross-table join performance
sqlite3 "$SQLITE_DB" "ANALYZE;"

echo ">>> Validating that only data for ENTITY_ID=${ENTITY_ID} was loaded..."
for table in "${TABLES[@]}"; do
  cols_var="COLS_$table[@]"
  COLS=("${!cols_var}")
  HAS_ENTITY_ID=0
  for c in "${COLS[@]}"; do
    if [[ "$c" == "entity_id" ]]; then HAS_ENTITY_ID=1; break; fi
  done

  if [[ "$table" == "entities" ]]; then
    INVALID_COUNT=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM \"entities\" WHERE \"id\" != ${ENTITY_ID};")
    if [[ "$INVALID_COUNT" -gt 0 ]]; then
      echo "Error: Found ${INVALID_COUNT} rows in 'entities' table with id != ${ENTITY_ID}."
      exit 1
    fi
  elif [[ $HAS_ENTITY_ID -eq 1 ]]; then
    INVALID_COUNT=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM \"$table\" WHERE \"entity_id\" != ${ENTITY_ID};")
    if [[ "$INVALID_COUNT" -gt 0 ]]; then
      echo "Error: Found ${INVALID_COUNT} rows in '$table' table with entity_id != ${ENTITY_ID}."
      exit 1
    fi
  fi
done
echo ">>> Validation successful: no other entities' data found."

echo "Done."
echo "SQLite DB: $SQLITE_DB"
for table in "${TABLES[@]}"; do
  if [ -f "$SQLITE_DB" ]; then
    count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM \"$table\";" 2>/dev/null || echo "0")
    if [ "$count" != "0" ]; then
      echo "Table $table: $count records"
    fi
  fi
done
