#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG
############################################

ADAPTER="${ADAPTER:-mysql2}"
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_PASS:-Root1234$}"
MYSQL_DB="${MYSQL_DB:-IRM_development}"
SOURCE_SQLITE_DB="${SOURCE_SQLITE_DB:-}"
FUND_IDS="${FUND_IDS:-${FUND_ID:-}}"

if [ -n "$FUND_IDS" ]; then
  # Replace commas with underscores for filename if multiple IDs are provided
  SAFE_FUND_IDS=$(echo "$FUND_IDS" | tr ',' '_')
  SQLITE_DB="${SQLITE_DB:-/tmp/irm_data_${SAFE_FUND_IDS}.sqlite3}"
else
  SQLITE_DB="${SQLITE_DB:-/tmp/irm_data.sqlite3}"
fi

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

TABLES=("funds" "account_entries" "capital_commitments" "portfolio_investments" "aggregate_portfolio_investments" "investors" "exchange_rates" "capital_remittances" "capital_distributions" "capital_distribution_payments" "fund_units" "capital_remittance_payments" "fund_unit_settings" "commitment_adjustments" "investor_kycs")

# Define columns for each table
COLS_funds=(
  id name committed_amount_cents details collected_amount_cents entity_id
  tag_list created_at updated_at call_amount_cents form_type_id
  distribution_amount_cents funding_round_id show_valuations
  show_fund_ratios fund_signatory_id trustee_signatory_id currency
  commitment_doc_list deleted_at data_room_folder_id document_folder_id
  unit_types units_allocation_engine total_units_premium_cents
  editable_formulas category start_date target_committed_amount_cents
  capital_fee_cents other_fee_cents json_fields esign_emails
  show_portfolios capital_commitments_count import_upload_id
  first_close_date last_close_date master_fund_id tracking_currency
  tracking_collected_amount_cents tracking_call_amount_cents
  tracking_co_invest_call_amount_cents tracking_distribution_amount_cents
  tracking_committed_amount_cents snapshot_date snapshot orignal_id
  portfolio_cost_type
)

TEXT_COLS_funds=(name details tag_list currency commitment_doc_list unit_types units_allocation_engine category json_fields esign_emails tracking_currency portfolio_cost_type)

SCHEMA_funds="
  id BIGINT PRIMARY KEY,
  name VARCHAR(255),
  committed_amount_cents DECIMAL(20,2) DEFAULT 0.00,
  details TEXT,
  collected_amount_cents DECIMAL(20,2) DEFAULT 0.00,
  entity_id BIGINT NOT NULL,
  tag_list VARCHAR(255),
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  call_amount_cents DECIMAL(20,2) DEFAULT 0.00,
  form_type_id BIGINT,
  distribution_amount_cents DECIMAL(20,2) DEFAULT 0.00,
  funding_round_id BIGINT,
  show_valuations BOOLEAN DEFAULT 0,
  show_fund_ratios BOOLEAN DEFAULT 0,
  fund_signatory_id BIGINT,
  trustee_signatory_id BIGINT,
  currency VARCHAR(5) NOT NULL,
  commitment_doc_list VARCHAR(100),
  deleted_at DATETIME,
  data_room_folder_id BIGINT,
  document_folder_id BIGINT,
  unit_types VARCHAR(255),
  units_allocation_engine VARCHAR(50),
  total_units_premium_cents DECIMAL(20,2) DEFAULT 0.00,
  editable_formulas BOOLEAN DEFAULT 0,
  category VARCHAR(15),
  start_date DATE,
  target_committed_amount_cents DECIMAL(20,2) DEFAULT 0.00,
  capital_fee_cents DECIMAL(20,2) DEFAULT 0.00,
  other_fee_cents DECIMAL(20,2) DEFAULT 0.00,
  json_fields JSON,
  esign_emails VARCHAR(255),
  show_portfolios BOOLEAN DEFAULT 0,
  capital_commitments_count INTEGER DEFAULT 0,
  import_upload_id BIGINT,
  first_close_date DATE,
  last_close_date DATE,
  master_fund_id BIGINT,
  tracking_currency VARCHAR(3),
  tracking_collected_amount_cents DECIMAL(20,4) DEFAULT 0.0000,
  tracking_call_amount_cents DECIMAL(20,4) DEFAULT 0.0000,
  tracking_co_invest_call_amount_cents DECIMAL(20,4) DEFAULT 0.0000,
  tracking_distribution_amount_cents DECIMAL(20,4) DEFAULT 0.0000,
  tracking_committed_amount_cents DECIMAL(20,4) DEFAULT 0.0000,
  snapshot_date DATE,
  snapshot BOOLEAN DEFAULT 0,
  orignal_id BIGINT,
  portfolio_cost_type VARCHAR(10) NOT NULL DEFAULT 'FIFO'
"

INDEX_funds="
  CREATE INDEX index_funds_on_entity_id ON funds(entity_id);
  CREATE INDEX index_funds_on_deleted_at ON funds(deleted_at);
  CREATE INDEX index_funds_on_master_fund_id ON funds(master_fund_id);
"

COLS_fund_unit_settings=(
  id entity_id fund_id name management_fee setup_fee form_type_id
  notes created_at updated_at carry json_fields import_upload_id
  isin gp_units
)

TEXT_COLS_fund_unit_settings=(name notes json_fields isin)

SCHEMA_fund_unit_settings="
  id BIGINT PRIMARY KEY,
  entity_id BIGINT NOT NULL,
  fund_id BIGINT NOT NULL,
  name VARCHAR(40),
  management_fee DECIMAL(24,8) DEFAULT 0.0,
  setup_fee DECIMAL(24,8) DEFAULT 0.0,
  form_type_id BIGINT,
  notes TEXT,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  carry DECIMAL(24,8) DEFAULT 0.0,
  json_fields JSON,
  import_upload_id BIGINT,
  isin VARCHAR(15),
  gp_units BOOLEAN DEFAULT 0
"

INDEX_fund_unit_settings="
  CREATE INDEX index_fund_unit_settings_on_entity_id ON fund_unit_settings(entity_id);
  CREATE INDEX index_fund_unit_settings_on_fund_id ON fund_unit_settings(fund_id);
"

COLS_commitment_adjustments=(
  id entity_id fund_id capital_commitment_id pre_adjustment_cents
  amount_cents folio_amount_cents post_adjustment_cents reason as_of
  created_at updated_at owner_type owner_id adjustment_type deleted_at
  tracking_amount_cents
)

TEXT_COLS_commitment_adjustments=(reason owner_type adjustment_type)

SCHEMA_commitment_adjustments="
  id BIGINT PRIMARY KEY,
  entity_id BIGINT NOT NULL,
  fund_id BIGINT NOT NULL,
  capital_commitment_id BIGINT NOT NULL,
  pre_adjustment_cents DECIMAL(20,2) DEFAULT 0.0,
  amount_cents DECIMAL(20,2) DEFAULT 0.0,
  folio_amount_cents DECIMAL(20,2) DEFAULT 0.0,
  post_adjustment_cents DECIMAL(20,2) DEFAULT 0.0,
  reason TEXT,
  as_of DATE,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  owner_type VARCHAR(255),
  owner_id BIGINT,
  adjustment_type VARCHAR(20),
  deleted_at DATETIME,
  tracking_amount_cents DECIMAL(20,4) DEFAULT 0.0
"

INDEX_commitment_adjustments="
  CREATE INDEX index_commitment_adjustments_on_entity_id ON commitment_adjustments(entity_id);
  CREATE INDEX index_commitment_adjustments_on_fund_id ON commitment_adjustments(fund_id);
  CREATE INDEX index_commitment_adjustments_on_capital_commitment_id ON commitment_adjustments(capital_commitment_id);
  CREATE INDEX index_commitment_adjustments_on_owner ON commitment_adjustments(owner_type, owner_id);
  CREATE INDEX index_commitment_adjustments_on_deleted_at ON commitment_adjustments(deleted_at);
"

COLS_capital_remittance_payments=(
  id fund_id capital_remittance_id entity_id amount_cents payment_date
  payment_proof_data notes created_at updated_at reference_no
  folio_amount_cents exchange_rate_id json_fields import_upload_id
  deleted_at payment_notification_sent tracking_amount_cents
  form_type_id convert_to_fund_currency investor_id
)

TEXT_COLS_capital_remittance_payments=(payment_proof_data notes reference_no json_fields)

SCHEMA_capital_remittance_payments="
  id BIGINT PRIMARY KEY,
  fund_id BIGINT NOT NULL,
  capital_remittance_id BIGINT NOT NULL,
  entity_id BIGINT NOT NULL,
  amount_cents DECIMAL(20,2),
  payment_date DATE,
  payment_proof_data TEXT,
  notes TEXT,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  reference_no VARCHAR(40),
  folio_amount_cents DECIMAL(20,2),
  exchange_rate_id BIGINT,
  json_fields JSON,
  import_upload_id BIGINT,
  deleted_at DATETIME,
  payment_notification_sent BOOLEAN,
  tracking_amount_cents DECIMAL(20,4),
  form_type_id BIGINT,
  convert_to_fund_currency BOOLEAN NOT NULL,
  investor_id BIGINT
"

INDEX_capital_remittance_payments="
  CREATE INDEX index_capital_remittance_payments_on_fund_id ON capital_remittance_payments(fund_id);
  CREATE INDEX index_capital_remittance_payments_on_capital_remittance_id ON capital_remittance_payments(capital_remittance_id);
  CREATE INDEX index_capital_remittance_payments_on_entity_id ON capital_remittance_payments(entity_id);
  CREATE INDEX index_capital_remittance_payments_on_payment_date ON capital_remittance_payments(payment_date);
  CREATE INDEX index_capital_remittance_payments_on_investor_id ON capital_remittance_payments(investor_id);
"

COLS_capital_distribution_payments=(
  id fund_id entity_id capital_distribution_id investor_id form_type_id
  income_cents payment_date created_at updated_at completed percentage
  folio_id capital_commitment_id deleted_at investor_name units_quantity
  document_folder_id cost_of_investment_cents folio_amount_cents
  exchange_rate_id json_fields import_upload_id net_of_account_entries_cents
  net_payable_cents income_with_fees_cents cost_of_investment_with_fees_cents
  reinvestment_cents reinvestment_with_fees_cents gross_payable_cents
  gross_of_account_entries_cents tracking_net_payable_cents
  tracking_gross_payable_cents tracking_reinvestment_with_fees_cents
  notification_sent
)

TEXT_COLS_capital_distribution_payments=(folio_id investor_name json_fields)

SCHEMA_capital_distribution_payments="
  id BIGINT PRIMARY KEY,
  fund_id BIGINT NOT NULL,
  entity_id BIGINT NOT NULL,
  capital_distribution_id BIGINT NOT NULL,
  investor_id BIGINT NOT NULL,
  form_type_id BIGINT,
  income_cents DECIMAL(20,2),
  payment_date DATE,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  completed BOOLEAN,
  percentage DECIMAL(12,8),
  folio_id VARCHAR(40),
  capital_commitment_id BIGINT,
  deleted_at DATETIME,
  investor_name VARCHAR(255) COLLATE NOCASE,
  units_quantity DECIMAL(20,2),
  document_folder_id BIGINT,
  cost_of_investment_cents DECIMAL(20,2),
  folio_amount_cents DECIMAL(20,2),
  exchange_rate_id BIGINT,
  json_fields JSON,
  import_upload_id BIGINT,
  net_of_account_entries_cents DECIMAL(20,2),
  net_payable_cents DECIMAL(20,2),
  income_with_fees_cents DECIMAL(20,2),
  cost_of_investment_with_fees_cents DECIMAL(20,2),
  reinvestment_cents DECIMAL(20,2),
  reinvestment_with_fees_cents DECIMAL(20,2),
  gross_payable_cents DECIMAL(20,2),
  gross_of_account_entries_cents DECIMAL(20,2),
  tracking_net_payable_cents DECIMAL(20,4),
  tracking_gross_payable_cents DECIMAL(20,2),
  tracking_reinvestment_with_fees_cents DECIMAL(20,2),
  notification_sent BOOLEAN NOT NULL
"

INDEX_capital_distribution_payments="
  CREATE INDEX index_capital_distribution_payments_on_fund_id ON capital_distribution_payments(fund_id);
  CREATE INDEX index_capital_distribution_payments_on_entity_id ON capital_distribution_payments(entity_id);
  CREATE INDEX index_capital_distribution_payments_on_capital_distribution_id ON capital_distribution_payments(capital_distribution_id);
  CREATE INDEX index_capital_distribution_payments_on_investor_id ON capital_distribution_payments(investor_id);
  CREATE INDEX index_capital_distribution_payments_on_capital_commitment_id ON capital_distribution_payments(capital_commitment_id);
"

COLS_fund_units=(
  id fund_id capital_commitment_id investor_id unit_type quantity reason
  created_at updated_at entity_id price_old owner_type owner_id premium_old
  total_premium_cents issue_date import_upload_id transfer price_cents
  premium_cents deleted_at amount_cents
)

TEXT_COLS_fund_units=(unit_type reason owner_type transfer)

SCHEMA_fund_units="
  id BIGINT PRIMARY KEY,
  fund_id BIGINT NOT NULL,
  capital_commitment_id BIGINT NOT NULL,
  investor_id BIGINT NOT NULL,
  unit_type VARCHAR(40),
  quantity DECIMAL(26,8) NOT NULL,
  reason TEXT,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  entity_id BIGINT NOT NULL,
  price_old DECIMAL(20,2),
  owner_type VARCHAR(255),
  owner_id BIGINT,
  premium_old DECIMAL(20,2),
  total_premium_cents DECIMAL(20,2),
  issue_date DATE,
  import_upload_id BIGINT,
  transfer VARCHAR(8),
  price_cents DECIMAL(20,2) NOT NULL,
  premium_cents DECIMAL(20,2) NOT NULL,
  deleted_at DATETIME,
  amount_cents DECIMAL(20,2)
"

INDEX_fund_units="
  CREATE INDEX index_fund_units_on_fund_id ON fund_units(fund_id);
  CREATE INDEX index_fund_units_on_capital_commitment_id ON fund_units(capital_commitment_id);
  CREATE INDEX index_fund_units_on_investor_id ON fund_units(investor_id);
  CREATE INDEX index_fund_units_on_entity_id ON fund_units(entity_id);
  CREATE INDEX index_fund_units_on_owner ON fund_units(owner_type, owner_id);
"

COLS_capital_remittances=(
  id entity_id fund_id capital_call_id investor_id status call_amount_cents
  collected_amount_cents notes created_at updated_at capital_commitment_id
  form_type_id verified payment_proof_data folio_id payment_date deleted_at
  investor_name document_folder_id units_quantity notification_sent
  committed_amount_cents folio_call_amount_cents folio_collected_amount_cents
  folio_committed_amount_cents exchange_rate_id created_by capital_fee_cents
  other_fee_cents folio_capital_fee_cents folio_other_fee_cents
  computed_amount_cents percentage remittance_date json_fields import_upload_id
  arrear_folio_amount_cents arrear_amount_cents compliant
  tracking_collected_amount_cents tracking_call_amount_cents
  investment_amount_cents folio_investment_amount_cents
)

TEXT_COLS_capital_remittances=(status notes payment_proof_data folio_id investor_name created_by json_fields)

SCHEMA_capital_remittances="
  id BIGINT PRIMARY KEY,
  entity_id BIGINT NOT NULL,
  fund_id BIGINT NOT NULL,
  capital_call_id BIGINT NOT NULL,
  investor_id BIGINT NOT NULL,
  status VARCHAR(10),
  call_amount_cents DECIMAL(20,2),
  collected_amount_cents DECIMAL(20,2),
  notes TEXT,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  capital_commitment_id BIGINT,
  form_type_id BIGINT,
  verified BOOLEAN,
  payment_proof_data TEXT,
  folio_id VARCHAR(40),
  payment_date DATE,
  deleted_at DATETIME,
  investor_name VARCHAR(255) COLLATE NOCASE,
  document_folder_id BIGINT,
  units_quantity DECIMAL(20,2),
  notification_sent BOOLEAN,
  committed_amount_cents DECIMAL(20,2),
  folio_call_amount_cents DECIMAL(20,2),
  folio_collected_amount_cents DECIMAL(20,2),
  folio_committed_amount_cents DECIMAL(20,2),
  exchange_rate_id BIGINT,
  created_by VARCHAR(10),
  capital_fee_cents DECIMAL(20,2),
  other_fee_cents DECIMAL(20,2),
  folio_capital_fee_cents DECIMAL(20,2),
  folio_other_fee_cents DECIMAL(20,2),
  computed_amount_cents DECIMAL(20,2),
  percentage DECIMAL(12,8),
  remittance_date DATE,
  json_fields JSON,
  import_upload_id BIGINT,
  arrear_folio_amount_cents DECIMAL(20,2),
  arrear_amount_cents DECIMAL(20,2),
  compliant BOOLEAN,
  tracking_collected_amount_cents DECIMAL(20,4),
  tracking_call_amount_cents DECIMAL(20,4),
  investment_amount_cents DECIMAL(20,2),
  folio_investment_amount_cents DECIMAL(20,2)
"

INDEX_capital_remittances="
  CREATE INDEX index_capital_remittances_on_entity_id ON capital_remittances(entity_id);
  CREATE INDEX index_capital_remittances_on_fund_id ON capital_remittances(fund_id);
  CREATE INDEX index_capital_remittances_on_capital_call_id ON capital_remittances(capital_call_id);
  CREATE INDEX index_capital_remittances_on_investor_id ON capital_remittances(investor_id);
  CREATE INDEX index_capital_remittances_on_capital_commitment_id ON capital_remittances(capital_commitment_id);
"

COLS_capital_distributions=(
  id fund_id entity_id form_type_id gross_amount_cents carry_cents
  distribution_date created_at updated_at title completed
  distribution_amount_cents net_amount_cents approved approved_by_user_id
  manual_generation generate_payments generate_payments_paid deleted_at
  fee_cents unit_prices reinvestment_cents document_folder_id
  cost_of_investment_cents capital_commitment_id distribution_on
  json_fields import_upload_id notes compliant income_cents
  send_notification_on_complete completed_distribution_amount_cents
)

TEXT_COLS_capital_distributions=(title unit_prices json_fields notes)

SCHEMA_capital_distributions="
  id BIGINT PRIMARY KEY,
  fund_id BIGINT NOT NULL,
  entity_id BIGINT NOT NULL,
  form_type_id BIGINT,
  gross_amount_cents DECIMAL(20,2),
  carry_cents DECIMAL(20,2),
  distribution_date DATE,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  title VARCHAR(255),
  completed BOOLEAN,
  distribution_amount_cents DECIMAL(20,2),
  net_amount_cents DECIMAL(20,2),
  approved BOOLEAN,
  approved_by_user_id BIGINT,
  manual_generation BOOLEAN,
  generate_payments BOOLEAN,
  generate_payments_paid BOOLEAN,
  deleted_at DATETIME,
  fee_cents DECIMAL(20,2),
  unit_prices TEXT,
  reinvestment_cents DECIMAL(20,2),
  document_folder_id BIGINT,
  cost_of_investment_cents DECIMAL(20,2),
  capital_commitment_id BIGINT,
  distribution_on INTEGER,
  json_fields JSON,
  import_upload_id BIGINT,
  notes TEXT,
  compliant BOOLEAN,
  income_cents DECIMAL(20,2) NOT NULL,
  send_notification_on_complete BOOLEAN,
  completed_distribution_amount_cents DECIMAL(20,2)
"

INDEX_capital_distributions="
  CREATE INDEX index_capital_distributions_on_fund_id ON capital_distributions(fund_id);
  CREATE INDEX index_capital_distributions_on_entity_id ON capital_distributions(entity_id);
  CREATE INDEX index_capital_distributions_on_capital_commitment_id ON capital_distributions(capital_commitment_id);
"

COLS_investors=(
  id entity_id investor_entity_id investor_name category city primary_email pan
  tag_list created_at updated_at last_interaction_date
  investor_access_count unapproved_investor_access_count json_fields
)

TEXT_COLS_investors=(investor_name category city primary_email pan tag_list json_fields)

SCHEMA_investors="
  id BIGINT PRIMARY KEY,
  entity_id BIGINT NOT NULL,
  investor_entity_id BIGINT,
  investor_name VARCHAR(255) COLLATE NOCASE NOT NULL,
  category VARCHAR(100) NOT NULL,
  city VARCHAR(50),
  primary_email VARCHAR(255),
  pan VARCHAR(40),
  tag_list VARCHAR(120),
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  last_interaction_date DATE,
  investor_access_count INTEGER DEFAULT 0,
  unapproved_investor_access_count INTEGER DEFAULT 0,
  json_fields JSON
"

INDEX_investors="
  CREATE INDEX index_investors_on_entity_id ON investors(entity_id);
  CREATE INDEX index_investors_on_investor_entity_id ON investors(investor_entity_id);
  CREATE INDEX index_investors_on_category ON investors(category);
"

COLS_exchange_rates=(
  id as_of created_at decimal document_folder_id entity_id "from"
  import_upload_id latest notes rate "to" updated_at
)

TEXT_COLS_exchange_rates=("from" "to" notes)

SCHEMA_exchange_rates="
  id BIGINT PRIMARY KEY,
  as_of DATE,
  created_at DATETIME NOT NULL,
  decimal DECIMAL(20,8) DEFAULT 0.0,
  document_folder_id BIGINT,
  entity_id BIGINT NOT NULL,
  \`from\` VARCHAR(5),
  import_upload_id BIGINT,
  latest BOOLEAN DEFAULT 1,
  notes TEXT,
  rate DECIMAL(20,8) DEFAULT 0.0,
  \`to\` VARCHAR(5),
  updated_at DATETIME NOT NULL
"

INDEX_exchange_rates="
  CREATE INDEX index_exchange_rates_on_entity_id ON exchange_rates(entity_id);
  CREATE INDEX index_exchange_rates_on_document_folder_id ON exchange_rates(document_folder_id);
  CREATE INDEX index_exchange_rates_on_import_upload_id ON exchange_rates(import_upload_id);
  CREATE INDEX idx_exchange_rates_entity_from_to_as_of ON exchange_rates(entity_id, \`from\`, \`to\`, as_of);
"

COLS_investor_kycs=(
  id investor_id entity_id form_type_id PAN address bank_account_number
  ifsc_code bank_verified bank_verification_response bank_verification_status
  signature_data pan_verified pan_verification_response pan_verification_status
  comments created_at updated_at verified full_name verified_by_id
  deleted_at investor_name document_folder_id expiry_date kyc_type
  residency birth_date corr_address committed_amount_cents
  call_amount_cents collected_amount_cents distribution_amount_cents
  docs_completed send_kyc_form_to_user notification_msg bank_name
  bank_branch bank_account_type type json_fields esign_emails
  due_amount_cents uncalled_amount_cents agreement_committed_amount_cents
  import_upload_id investor_user_id investor_user_updated_at
  other_fee_cents agreement_unit_type slug doc_question_answers
  all_docs_valid compliant aml_status completed_by_investor
  reminder_sent reminder_sent_date
)

TEXT_COLS_investor_kycs=(PAN address bank_account_number bank_verification_response bank_verification_status signature_data pan_verification_response pan_verification_status comments full_name investor_name kyc_type residency corr_address notification_msg bank_name bank_branch bank_account_type type json_fields esign_emails agreement_unit_type slug doc_question_answers aml_status)

SCHEMA_investor_kycs="
  id BIGINT PRIMARY KEY,
  investor_id BIGINT NOT NULL,
  entity_id BIGINT NOT NULL,
  form_type_id BIGINT,
  PAN VARCHAR(15),
  address TEXT,
  bank_account_number VARCHAR(40),
  ifsc_code VARCHAR(20),
  bank_verified BOOLEAN DEFAULT 0,
  bank_verification_response TEXT,
  bank_verification_status VARCHAR(255),
  signature_data TEXT,
  pan_verified BOOLEAN DEFAULT 0,
  pan_verification_response TEXT,
  pan_verification_status VARCHAR(255),
  comments TEXT,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  verified BOOLEAN DEFAULT 0,
  full_name VARCHAR(255),
  verified_by_id BIGINT,
  deleted_at DATETIME,
  investor_name VARCHAR(255),
  document_folder_id BIGINT,
  expiry_date DATE,
  kyc_type VARCHAR(15) DEFAULT 'Individual',
  residency VARCHAR(10),
  birth_date DATETIME,
  corr_address TEXT,
  committed_amount_cents DECIMAL(20,2) DEFAULT 0.0,
  call_amount_cents DECIMAL(20,2) DEFAULT 0.0,
  collected_amount_cents DECIMAL(20,2) DEFAULT 0.0,
  distribution_amount_cents DECIMAL(20,2) DEFAULT 0.0,
  docs_completed BOOLEAN DEFAULT 0,
  send_kyc_form_to_user BOOLEAN DEFAULT 0,
  notification_msg TEXT,
  bank_name VARCHAR(100),
  bank_branch VARCHAR(255),
  bank_account_type VARCHAR(40),
  type VARCHAR(20),
  json_fields JSON,
  esign_emails VARCHAR(255),
  due_amount_cents DECIMAL(20,2) DEFAULT 0.0,
  uncalled_amount_cents DECIMAL(20,2) DEFAULT 0.0,
  agreement_committed_amount_cents DECIMAL(20,2) DEFAULT 0.0,
  import_upload_id BIGINT,
  investor_user_id BIGINT,
  investor_user_updated_at DATETIME,
  other_fee_cents DECIMAL(12,2) DEFAULT 0.0,
  agreement_unit_type VARCHAR(20),
  slug VARCHAR(255),
  doc_question_answers JSON,
  all_docs_valid BOOLEAN DEFAULT 0,
  compliant BOOLEAN DEFAULT 0,
  aml_status VARCHAR(255),
  completed_by_investor BOOLEAN DEFAULT 0,
  reminder_sent BOOLEAN DEFAULT 0,
  reminder_sent_date DATETIME
"

INDEX_investor_kycs="
  CREATE INDEX index_investor_kycs_on_deleted_at ON investor_kycs(deleted_at);
  CREATE INDEX index_investor_kycs_on_document_folder_id ON investor_kycs(document_folder_id);
  CREATE INDEX index_investor_kycs_on_entity_id ON investor_kycs(entity_id);
  CREATE INDEX index_investor_kycs_on_form_type_id ON investor_kycs(form_type_id);
  CREATE INDEX index_investor_kycs_on_investor_id ON investor_kycs(investor_id);
  CREATE INDEX index_investor_kycs_on_investor_user_id ON investor_kycs(investor_user_id);
  CREATE UNIQUE INDEX index_investor_kycs_on_slug ON investor_kycs(slug);
  CREATE INDEX index_investor_kycs_on_verified_by_id ON investor_kycs(verified_by_id);
"

COLS_account_entries=(
  id capital_commitment_id entity_id fund_id investor_id form_type_id folio_id
  reporting_date entry_type name amount_cents notes created_at updated_at
  explanation cumulative period parent_type parent_id generated migrated folio_amount_cents
  exchange_rate_id fund_formula_id rule_for json_fields import_upload_id
  deleted_at generated_deleted tracking_amount_cents allocation_run_id
  parent_name commitment_name ref_id
)

COLS_capital_commitments=(
  id entity_id investor_id fund_id committed_amount_cents collected_amount_cents
  notes created_at updated_at form_type_id percentage ppm_number folio_id
  investor_signatory_id esign_required esign_completed esign_provider esign_link
  call_amount_cents distribution_amount_cents onboarding_completed deleted_at
  investor_kyc_id investor_name document_folder_id unit_type total_fund_units_quantity
  total_allocated_income_cents total_allocated_expense_cents total_units_premium_cents
  fund_close virtual_bank_account folio_currency folio_committed_amount_cents
  folio_collected_amount_cents folio_call_amount_cents adjustment_amount_cents
  adjustment_folio_amount_cents orig_committed_amount_cents
  orig_folio_committed_amount_cents exchange_rate_id is_feeder_fund commitment_date
  json_fields esign_emails import_upload_id other_fee_cents arrear_amount_cents
  arrear_folio_amount_cents slug compliant feeder_fund_id
  tracking_collected_amount_cents tracking_distribution_amount_cents
  tracking_committed_amount_cents tracking_orig_committed_amount_cents
  tracking_adjustment_amount_cents total_units_amount_cents
)

COLS_portfolio_investments=(
  id entity_id fund_id form_type_id portfolio_company_id portfolio_company_name
  investment_date amount_cents quantity notes created_at updated_at fmv_cents
  document_folder_id aggregate_portfolio_investment_id sold_quantity net_quantity
  cost_of_sold_cents gain_cents folio_id capital_commitment_id category sub_category
  sector startup investment_domicile deleted_at json_fields import_upload_id
  investment_instrument_id quantity_as_of_date base_amount_cents exchange_rate_id
  transfer_quantity transfer_amount_cents net_amount_cents net_bought_amount_cents
  net_bought_quantity cost_of_remaining_cents unrealized_gain_cents compliant
  ex_expenses_amount_cents ex_expenses_base_amount_cents conversion_date
  snapshot_date snapshot orignal_id instrument_currency_fmv_cents
  instrument_currency_cost_of_remaining_cents instrument_currency_unrealized_gain_cents
  ref_id capital_distribution_id excused_folio_ids proforma tracking_amount_cents
  tracking_fmv_cents valuation_id
)

COLS_aggregate_portfolio_investments=(
  id entity_id fund_id portfolio_company_id quantity fmv_cents avg_cost_cents
  created_at updated_at portfolio_company_name bought_quantity bought_amount_cents
  sold_quantity sold_amount_cents cost_of_remaining_cents investment_type
  cost_of_sold_cents investment_domicile deleted_at investment_instrument_id
  form_type_id transfer_amount_cents unrealized_gain_cents transfer_quantity
  net_bought_amount_cents document_folder_id show_portfolio portfolio_income_cents
  gain_cents snapshot_date snapshot orignal_id instrument_currency_fmv_cents
  instrument_currency_cost_of_remaining_cents instrument_currency_unrealized_gain_cents
  ex_expenses_amount_cents tracking_fmv_cents tracking_bought_amount_cents
  tracking_sold_amount_cents
)

# Text/JSON columns that need newline/tab escaping
TEXT_COLS_account_entries=(notes explanation json_fields name parent_name commitment_name folio_id entry_type period parent_type rule_for)
TEXT_COLS_capital_commitments=(notes folio_id esign_provider esign_link investor_name unit_type fund_close virtual_bank_account folio_currency json_fields esign_emails slug)
TEXT_COLS_portfolio_investments=(portfolio_company_name notes folio_id category sub_category sector investment_domicile json_fields excused_folio_ids)
TEXT_COLS_aggregate_portfolio_investments=(portfolio_company_name investment_type investment_domicile)
TEXT_COLS_investor_kycs=(PAN address agreement_unit_type aml_status bank_account_number bank_account_type bank_branch bank_name bank_verification_response bank_verification_status birth_date comments completed_by_investor compliant corr_address doc_question_answers esign_emails full_name ifsc_code investor_name json_fields kyc_type notification_msg pan_card_data pan_verification_response pan_verification_status residency signature_data slug type)
TEXT_COLS_investors=(investor_name category city primary_email pan tag_list)
TEXT_COLS_exchange_rates=("from" "to" notes)
TEXT_COLS_capital_remittances=(status notes payment_proof_data folio_id investor_name created_by json_fields)
TEXT_COLS_capital_distributions=(title unit_prices json_fields notes)
TEXT_COLS_capital_distribution_payments=(folio_id investor_name json_fields)
TEXT_COLS_fund_units=(unit_type reason owner_type transfer)
TEXT_COLS_capital_remittance_payments=(payment_proof_data notes reference_no json_fields)
TEXT_COLS_fund_unit_settings=(name notes json_fields isin)
TEXT_COLS_commitment_adjustments=(reason owner_type adjustment_type)
TEXT_COLS_funds=(name details tag_list currency commitment_doc_list unit_types units_allocation_engine category json_fields esign_emails tracking_currency portfolio_cost_type)

# SQLite Schema Definitions
SCHEMA_account_entries="
  id                     INTEGER PRIMARY KEY AUTOINCREMENT,
  capital_commitment_id  BIGINT,
  entity_id              BIGINT NOT NULL,
  fund_id                BIGINT NOT NULL,
  investor_id            BIGINT,
  form_type_id           BIGINT,
  folio_id               VARCHAR(40),
  reporting_date         DATE NOT NULL,
  entry_type             VARCHAR(60) COLLATE NOCASE,
  name                   VARCHAR(125) COLLATE NOCASE,
  amount_cents           DECIMAL(30,8) DEFAULT 0.0,
  notes                  TEXT,
  created_at             DATETIME NOT NULL,
  updated_at             DATETIME NOT NULL,
  explanation            TEXT,
  cumulative             BOOLEAN DEFAULT 0,
  period                 VARCHAR(25),
  parent_type            VARCHAR(255),
  parent_id              BIGINT,
  generated              BOOLEAN DEFAULT 0,
  migrated               BOOLEAN DEFAULT 0,
  folio_amount_cents     DECIMAL(30,8) DEFAULT 0.0,
  exchange_rate_id       BIGINT,
  fund_formula_id        BIGINT,
  rule_for               VARCHAR(10) DEFAULT 'Accounting',
  json_fields            JSON,
  import_upload_id       BIGINT,
  deleted_at             DATETIME,
  generated_deleted      DATETIME,
  tracking_amount_cents  DECIMAL(20,2) DEFAULT 0.0,
  allocation_run_id      BIGINT,
  parent_name            VARCHAR(255),
  commitment_name        VARCHAR(255),
  ref_id                 INTEGER NOT NULL DEFAULT 0
"

SCHEMA_capital_commitments="
  id BIGINT PRIMARY KEY,
  entity_id BIGINT NOT NULL,
  investor_id BIGINT NOT NULL,
  fund_id BIGINT NOT NULL,
  committed_amount_cents DECIMAL(20,2),
  collected_amount_cents DECIMAL(20,2),
  notes TEXT,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  form_type_id BIGINT,
  percentage DECIMAL(11,8),
  ppm_number BIGINT,
  folio_id VARCHAR(40),
  investor_signatory_id BIGINT,
  esign_required BOOLEAN,
  esign_completed BOOLEAN,
  esign_provider VARCHAR(10),
  esign_link VARCHAR(255),
  call_amount_cents DECIMAL(20,2),
  distribution_amount_cents DECIMAL(20,2),
  onboarding_completed BOOLEAN,
  deleted_at DATETIME,
  investor_kyc_id BIGINT,
  investor_name VARCHAR(255) COLLATE NOCASE,
  document_folder_id BIGINT,
  unit_type VARCHAR(40),
  total_fund_units_quantity DECIMAL(20,2),
  total_allocated_income_cents DECIMAL(20,2),
  total_allocated_expense_cents DECIMAL(20,2),
  total_units_premium_cents DECIMAL(20,2),
  fund_close VARCHAR(255),
  virtual_bank_account VARCHAR(20),
  folio_currency VARCHAR(5),
  folio_committed_amount_cents DECIMAL(20,2),
  folio_collected_amount_cents DECIMAL(20,2),
  folio_call_amount_cents DECIMAL(20,2),
  adjustment_amount_cents DECIMAL(20,2),
  adjustment_folio_amount_cents DECIMAL(20,2),
  orig_committed_amount_cents DECIMAL(20,2),
  orig_folio_committed_amount_cents DECIMAL(20,2),
  exchange_rate_id BIGINT,
  is_feeder_fund BOOLEAN,
  commitment_date DATE,
  json_fields JSON,
  esign_emails VARCHAR(255),
  import_upload_id BIGINT,
  other_fee_cents DECIMAL(20,2),
  arrear_amount_cents DECIMAL(20,2),
  arrear_folio_amount_cents DECIMAL(20,2),
  slug VARCHAR(255),
  compliant BOOLEAN,
  feeder_fund_id BIGINT,
  tracking_collected_amount_cents DECIMAL(20,4),
  tracking_distribution_amount_cents DECIMAL(20,4),
  tracking_committed_amount_cents DECIMAL(20,4),
  tracking_orig_committed_amount_cents DECIMAL(20,4),
  tracking_adjustment_amount_cents DECIMAL(20,4),
  total_units_amount_cents DECIMAL(20,2)
"

SCHEMA_portfolio_investments="
  id BIGINT PRIMARY KEY,
  entity_id BIGINT NOT NULL,
  fund_id BIGINT NOT NULL,
  form_type_id BIGINT,
  portfolio_company_id BIGINT NOT NULL,
  portfolio_company_name VARCHAR(100),
  investment_date DATE,
  amount_cents DECIMAL(20,2),
  quantity DECIMAL(24,8),
  notes TEXT,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  fmv_cents DECIMAL(20,2),
  document_folder_id BIGINT,
  aggregate_portfolio_investment_id BIGINT NOT NULL,
  sold_quantity DECIMAL(24,8),
  net_quantity DECIMAL(24,8),
  cost_of_sold_cents DECIMAL(20,2),
  gain_cents DECIMAL(20,2),
  folio_id VARCHAR(40),
  capital_commitment_id BIGINT,
  category VARCHAR(10),
  sub_category VARCHAR(100),
  sector VARCHAR(100),
  startup BOOLEAN,
  investment_domicile VARCHAR(10),
  deleted_at DATETIME,
  json_fields JSON,
  import_upload_id BIGINT,
  investment_instrument_id BIGINT,
  quantity_as_of_date DECIMAL(10,0),
  base_amount_cents DECIMAL(20,2),
  exchange_rate_id BIGINT,
  transfer_quantity DECIMAL(20,2),
  transfer_amount_cents DECIMAL(20,2),
  net_amount_cents DECIMAL(20,2),
  net_bought_amount_cents DECIMAL(20,2),
  net_bought_quantity DECIMAL(20,2),
  cost_of_remaining_cents DECIMAL(20,2),
  unrealized_gain_cents DECIMAL(20,2),
  compliant BOOLEAN,
  ex_expenses_amount_cents DECIMAL(20,2),
  ex_expenses_base_amount_cents DECIMAL(20,2),
  conversion_date DATE,
  snapshot_date DATE,
  snapshot BOOLEAN,
  orignal_id BIGINT,
  instrument_currency_fmv_cents DECIMAL(20,2),
  instrument_currency_cost_of_remaining_cents DECIMAL(20,2),
  instrument_currency_unrealized_gain_cents DECIMAL(20,2),
  ref_id BIGINT NOT NULL,
  capital_distribution_id BIGINT,
  excused_folio_ids JSON,
  proforma BOOLEAN,
  tracking_amount_cents DECIMAL(20,2),
  tracking_fmv_cents DECIMAL(20,2),
  valuation_id BIGINT
"

SCHEMA_aggregate_portfolio_investments="
  id BIGINT PRIMARY KEY,
  entity_id BIGINT NOT NULL,
  fund_id BIGINT NOT NULL,
  portfolio_company_id BIGINT NOT NULL,
  quantity DECIMAL(24,8),
  fmv_cents DECIMAL(20,2),
  avg_cost_cents DECIMAL(20,2),
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  portfolio_company_name VARCHAR(100),
  bought_quantity DECIMAL(20,2),
  bought_amount_cents DECIMAL(20,2),
  sold_quantity DECIMAL(20,2),
  sold_amount_cents DECIMAL(20,2),
  cost_of_remaining_cents DECIMAL(20,2),
  investment_type VARCHAR(255),
  cost_of_sold_cents DECIMAL(20,2),
  investment_domicile VARCHAR(10),
  deleted_at DATETIME,
  investment_instrument_id BIGINT,
  form_type_id BIGINT,
  transfer_amount_cents DECIMAL(20,2),
  unrealized_gain_cents DECIMAL(20,2),
  transfer_quantity DECIMAL(20,2),
  net_bought_amount_cents DECIMAL(20,2),
  document_folder_id BIGINT,
  show_portfolio BOOLEAN,
  portfolio_income_cents DECIMAL(20,2) NOT NULL,
  gain_cents DECIMAL(20,2) NOT NULL,
  snapshot_date DATE,
  snapshot BOOLEAN,
  orignal_id BIGINT,
  instrument_currency_fmv_cents DECIMAL(20,2),
  instrument_currency_cost_of_remaining_cents DECIMAL(20,2),
  instrument_currency_unrealized_gain_cents DECIMAL(20,2),
  ex_expenses_amount_cents DECIMAL(20,2),
  tracking_fmv_cents DECIMAL(20,2) NOT NULL,
  tracking_bought_amount_cents DECIMAL(20,2) NOT NULL,
  tracking_sold_amount_cents DECIMAL(20,2) NOT NULL
"

# Index Definitions
INDEX_account_entries="
  CREATE INDEX idx_ae_cc_name_date ON account_entries(capital_commitment_id, name, reporting_date);
  CREATE INDEX index_account_entries_on_capital_commitment_id ON account_entries(capital_commitment_id);
  CREATE INDEX index_account_entries_on_fund_formula_id ON account_entries(fund_formula_id);
  CREATE INDEX idx_fund_id_and_entry_type_and_reporting_date ON account_entries(fund_id, entry_type, reporting_date);
  CREATE INDEX idx_ae_fund_gen_date_formula ON account_entries(fund_id, generated, reporting_date, fund_formula_id);
  CREATE INDEX idx_fund_id_and_name_and_reporting_date ON account_entries(fund_id, name, reporting_date);
  CREATE INDEX index_account_entries_on_import_upload_id ON account_entries(import_upload_id);
  CREATE INDEX index_account_entries_on_investor_id ON account_entries(investor_id);
  CREATE INDEX idx_ae_parent_fund_name_flags ON account_entries(parent_type, parent_id, fund_id, name, deleted_at, cumulative);
  CREATE INDEX index_account_entries_on_reporting_date ON account_entries(reporting_date);
  CREATE INDEX index_account_entries_on_migrated ON account_entries(migrated);
  CREATE INDEX idx_ae_optimized_sum_query ON account_entries(parent_type, parent_id, entry_type, capital_commitment_id, reporting_date, deleted_at, cumulative);
  CREATE INDEX idx_ae_optimized_load_query ON account_entries(parent_type, parent_id, capital_commitment_id, name, cumulative, deleted_at, reporting_date);
"

INDEX_capital_commitments="
  CREATE INDEX index_capital_commitments_on_slug ON capital_commitments(slug);
  CREATE INDEX idx_unique_commitment ON capital_commitments(fund_id, folio_id);
  CREATE INDEX index_capital_commitments_on_entity_id ON capital_commitments(entity_id);
  CREATE INDEX index_capital_commitments_on_investor_id ON capital_commitments(investor_id);
  CREATE INDEX index_capital_commitments_on_fund_id ON capital_commitments(fund_id);
  CREATE INDEX index_capital_commitments_on_deleted_at ON capital_commitments(deleted_at);
  CREATE INDEX index_capital_commitments_on_commitment_date ON capital_commitments(commitment_date);
"

INDEX_portfolio_investments="
  CREATE INDEX index_portfolio_investments_on_entity_id ON portfolio_investments(entity_id);
  CREATE INDEX index_portfolio_investments_on_fund_id ON portfolio_investments(fund_id);
  CREATE INDEX index_portfolio_investments_on_portfolio_company_id ON portfolio_investments(portfolio_company_id);
  CREATE INDEX index_portfolio_investments_on_aggregate_portfolio_investment_id ON portfolio_investments(aggregate_portfolio_investment_id);
  CREATE INDEX index_portfolio_investments_on_deleted_at ON portfolio_investments(deleted_at);
  CREATE INDEX index_portfolio_investments_on_investment_date ON portfolio_investments(investment_date);
"

INDEX_aggregate_portfolio_investments="
  CREATE INDEX index_aggregate_portfolio_investments_on_entity_id ON aggregate_portfolio_investments(entity_id);
  CREATE INDEX index_aggregate_portfolio_investments_on_fund_id ON aggregate_portfolio_investments(fund_id);
  CREATE INDEX index_aggregate_portfolio_investments_on_portfolio_company_id ON aggregate_portfolio_investments(portfolio_company_id);
  CREATE INDEX index_aggregate_portfolio_investments_on_deleted_at ON aggregate_portfolio_investments(deleted_at);
"

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

  COLS=("${!cols_var}")
  TEXT_COLS=("${!text_cols_var}")
  SCHEMA="${!schema_var}"
  INDEX_SQL="${!index_var}"

  EXPORT_TSV="/tmp/${table}_export.tsv"

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
      # Escape newlines as literal \n so TSV stays on one line
      # We use a unique marker for newlines/tabs to avoid collision with literal \n in data
      # Replace double quotes with a marker, then escape newlines/tabs
      SELECT_LIST+="REPLACE(REPLACE(REPLACE(REPLACE(IFNULL(\`${c}\`,''), '\"', '###DQ###'), CHAR(10), '###NL###'), CHAR(13), '###CR###'), CHAR(9), '###TAB###'),"
    elif [[ "$table" == "account_entries" && "$c" == "migrated" ]]; then
      # migrated field is not in source, default to 0
      SELECT_LIST+="0,"
    else
      SELECT_LIST+="IFNULL(\`${c}\`,''),"
    fi
  done
  SELECT_LIST="${SELECT_LIST%,}"

  # Some tables don't have deleted_at
  WHERE_CLAUSE="WHERE 1=1"
  if [[ "$table" != "fund_unit_settings" ]] && [[ "$table" != "funds" ]] && [[ "$table" != "exchange_rates" ]]; then
    WHERE_CLAUSE="WHERE deleted_at IS NULL"
  fi

  if [ -n "$FUND_IDS" ]; then
    if [[ "$table" == "investors" || "$table" == "exchange_rates" || "$table" == "investor_kycs" ]]; then
      # Investors and exchange_rates don't have fund_id, filter by entity_id of the first fund
      FIRST_FUND_ID=$(echo "$FUND_IDS" | cut -d',' -f1)
      if [[ "$ADAPTER" == "sqlite3" ]] || [[ -n "$SOURCE_SQLITE_DB" ]]; then
        ENTITY_ID=$(sqlite3 "${SOURCE_SQLITE_DB:-$MYSQL_DB}" "SELECT entity_id FROM funds WHERE id = ${FIRST_FUND_ID} LIMIT 1;")
      else
        ENTITY_ID=$(mysql_cmd -e "SELECT entity_id FROM funds WHERE id = ${FIRST_FUND_ID} LIMIT 1;")
      fi
      if [ -n "$ENTITY_ID" ]; then
        WHERE_CLAUSE="${WHERE_CLAUSE} AND entity_id = ${ENTITY_ID}"
      fi
    elif [[ "$table" == "funds" ]]; then
      if [[ "$FUND_IDS" == *","* ]]; then
        WHERE_CLAUSE="${WHERE_CLAUSE} AND id IN (${FUND_IDS})"
      else
        WHERE_CLAUSE="${WHERE_CLAUSE} AND id = ${FUND_IDS}"
      fi
    elif [[ "$FUND_IDS" == *","* ]]; then
      WHERE_CLAUSE="${WHERE_CLAUSE} AND fund_id IN (${FUND_IDS})"
    else
      WHERE_CLAUSE="${WHERE_CLAUSE} AND fund_id = ${FUND_IDS}"
    fi
  fi

  echo "  Step 1: Exporting $table → TSV"
  if [[ "$ADAPTER" == "sqlite3" ]] || [[ -n "$SOURCE_SQLITE_DB" ]]; then
    SQLITE_SOURCE="${SOURCE_SQLITE_DB:-$MYSQL_DB}"
    QUERY="SELECT ${SELECT_LIST} FROM ${table} ${WHERE_CLAUSE};"
    # echo "  Executing Query: $QUERY"
    sqlite3 "$SQLITE_SOURCE" <<SQL | pv -l -t -e -r -a > "$EXPORT_TSV"
.mode tabs
.nullvalue \\N
$QUERY
SQL
  else
    QUERY="SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED; SELECT ${SELECT_LIST} FROM ${table} ${WHERE_CLAUSE};"
    # echo "  Executing Query: $QUERY"
    mysql_cmd -e "${QUERY}" | pv -l -t -e -r -a > "$EXPORT_TSV"
  fi
  log_step_time "Export $table" "$STEP_START"

  ############################################
  # 2) Create Table Schema
  ############################################
  STEP_START=$(date +%s)
  echo "  Step 2: Creating schema for $table"
  sqlite3 "$SQLITE_DB" "CREATE TABLE $table ($SCHEMA);"
  log_step_time "Schema $table" "$STEP_START"

  ############################################
  # 3) Import TSV → SQLite
  ############################################
  STEP_START=$(date +%s)
  FILE_SIZE=$(stat -c%s "$EXPORT_TSV")
  if [ "$FILE_SIZE" -gt 0 ]; then
    echo "  Step 3: Importing $table TSV into SQLite"
    pv -s "$FILE_SIZE" "$EXPORT_TSV" | sqlite3 "$SQLITE_DB" \
      -cmd ".mode tabs" \
      -cmd ".nullvalue \\N" \
      -cmd "BEGIN;" \
      ".import /dev/stdin $table" \
      "COMMIT;"
  else
    echo "  Step 3: TSV is empty for $table, skipping import."
  fi
  log_step_time "Import $table" "$STEP_START"

  ############################################
  # 4) Post-Import Cleanup & Indexing
  ############################################
  STEP_START=$(date +%s)
  echo "  Step 4: Cleanup & Indexing for $table"

  # Cleanup script
  CLEANUP_SQL=""
  UPDATE_SET=""

  for c in "${COLS[@]}"; do
    # Skip ID
    if [[ "$c" == "id" ]]; then continue; fi

    # Check if this is a text column requiring unescaping
    is_text=0
    for tc in "${TEXT_COLS[@]}"; do
      if [[ "$c" == "$tc" ]]; then is_text=1; break; fi
    done

    if [[ $is_text -eq 1 ]]; then
      # Restore double quotes, newlines, carriage returns and tabs from markers, THEN check for empty string
      UPDATE_SET+="\`$c\` = NULLIF(REPLACE(REPLACE(REPLACE(REPLACE(IFNULL(\`$c\`, ''), '###DQ###', '\"'), '###NL###', CHAR(10)), '###CR###', CHAR(13)), '###TAB###', CHAR(9)), ''), "
    else
      # Standard NULL cleanup for non-text columns
      UPDATE_SET+="\`$c\` = NULLIF(\`$c\`, ''), "
    fi
  done

  if [[ -n "$UPDATE_SET" ]]; then
    UPDATE_SET="${UPDATE_SET%, }"
    CLEANUP_SQL="UPDATE $table SET $UPDATE_SET;"

    # Actually run the cleanup as a separate call to ensure it finishes before indexing
    echo "  Applying character restoration and NULL cleanup for $table..."
    sqlite3 "$SQLITE_DB" "$CLEANUP_SQL"
  fi

  sqlite3 "$SQLITE_DB" <<SQL
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
$INDEX_SQL
ANALYZE $table;
SQL
  log_step_time "Post-process $table" "$STEP_START"

  rm -f "$EXPORT_TSV"
done

# Run global ANALYZE to optimize cross-table join performance
sqlite3 "$SQLITE_DB" "ANALYZE;"

echo "Done."
echo "SQLite DB: $SQLITE_DB"
for table in "${TABLES[@]}"; do
  count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM $table;")
  echo "Table $table: $count records"
done
