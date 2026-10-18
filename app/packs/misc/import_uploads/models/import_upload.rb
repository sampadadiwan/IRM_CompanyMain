class ImportUpload < ApplicationRecord
  SAMPLES = { "INVESTOR_ACCESS_SAMPLE" => "/sample_uploads/investor_access.xlsx",
              "INVESTORS_SAMPLE" => "/sample_uploads/investors.xlsx",
              "FUND_INVESTORS_SAMPLE" => "/sample_uploads/fund_investors.xlsx",
              "FUNDS_SAMPLE" => "/sample_uploads/funds.xlsx",
              "FORM_CUSTOM_FIELD_SAMPLE" => "/sample_uploads/form_custom_fields.xlsx",
              "OFFERS_SAMPLE" => "/sample_uploads/offers.xlsx",
              "INTERESTS_SAMPLE" => "/sample_uploads/interests.xlsx",
              "CAPITAL_CALL_SAMPLE" => "/sample_uploads/capital_calls.xlsx",
              "CAPITAL_REMITTANCE_SAMPLE" => "/sample_uploads/capital_remittances.xlsx",
              "CAPITAL_REMITTANCE_PAYMENT_SAMPLE" => "/sample_uploads/capital_remittance_payments.xlsx",
              "CAPITAL_DISTRIBUTION_SAMPLE" => "/sample_uploads/capital_distributions.xlsx",
              "INVESTOR_KYCS_SAMPLE" => "/sample_uploads/investor_kycs.xlsx",
              "CAPITAL_DISTRIBUTION_PAYMENT_SAMPLE" => "/sample_uploads/capital_distribution_payments.xlsx",
              "CAPITAL_COMMITMENT_SAMPLE" => "/sample_uploads/capital_commitments.xlsx",
              "FUND_DOCS_SAMPLE" => "/sample_uploads/import_fund_docs.zip",
              "FUND_INVESTOR_ADVISORS_SAMPLE" => "/sample_uploads/investor_advisors.xlsx",
              "PORTFOLIO_SAMPLE" => "/sample_uploads/portfolio_investments.xlsx",
              "PORTFOLIO_INCOME_SAMPLE" => "/sample_uploads/portfolio_income.xlsx",
              "VALUATION_SAMPLE" => "/sample_uploads/valuations.xlsx",
              "INVESTOR_KYCS_DOCS_SAMPLE" => "/sample_uploads/import_kyc_docs.zip",
              "DOCS_SAMPLE" => "/sample_uploads/documents_upload.zip",
              "OFFERS_DOCS_SAMPLE" => "/sample_uploads/offer_docs.zip",
              "FUND_UNIT_SETTING_SAMPLE" => "/sample_uploads/fund_unit_setting.xlsx",
              "FUND_UNIT_SAMPLE" => "/sample_uploads/fund_units.xlsx",
              "FUND_FORMULA_SAMPLE" => "/sample_uploads/fund_formulas.xlsx",
              "ACCOUNT_ENTRY_SAMPLE" => "/sample_uploads/account_entries.xlsx",
              "KPIS_SAMPLE" => "/sample_uploads/kpis.xlsx",
              "EXCHANGE_RATE" => "/sample_uploads/exchange_rates.xlsx",
              "ALLOCATION" => "/sample_uploads/allocations.xlsx",
              "Fund_RATIO_SAMPLE" => "/sample_uploads/fund_ratios.xlsx",
              "INVESTMENT_INSTRUMENT_SAMPLE" => "/sample_uploads/investment_instruments.xlsx",
              "INVESTMENT_SAMPLE" => "/sample_uploads/investments.xlsx",
              "INVESTOR_KPI_MAPPING_SAMPLE" => "/sample_uploads/investor_kpi_mappings.xlsx",
              "AGENT_CHART_SAMPLE" => "/sample_uploads/agent_charts.xlsx",
              "TASK_SAMPLE" => "/sample_uploads/tasks.xlsx",
              "DASHBOARD_WIDGET_SAMPLE" => "/sample_uploads/dashboard_widgets.xlsx",
              "DEAL_INVESTORS_SAMPLE" => "/sample_uploads/deal_investors.xlsx",
              "RATIO_FORMULA_SAMPLE" => "/sample_uploads/ratio_formulas.xlsx",
              "DEAL_ACTIVITY_TEMPLATES_SAMPLE" => "/sample_uploads/deal_activity_templates.xlsx",
              "SHAREHOLDER_POSITION_SAMPLE" => "/sample_uploads/shareholder_positions.xlsx",
              "DOC_CHECK_SAMPLE" => "/sample_uploads/doc_checks.xlsx" }.freeze

  TYPES = %w[InvestorAccess Investor CapitalCommitment CapitalCall CapitalRemittance CapitalRemittancePayment CapitalDistribution CapitalDistributionPayment Documents PortfolioInvestment PortfolioIncome Valuation FundDocs FundUnitSetting FundUnit AccountEntry InvestorKyc InvestorAdvisor Offer OfferDocs Kpi KycDocs Fund ExchangeRate Allocation FundRatio InvestmentInstrument Investment InvestorKpiMapping FormCustomField DashboardWidget AgentChart Task DealInvestor RatioFormula DealActivityTemplate ShareholderPosition DocCheck].sort.freeze

  DOC_TYPES = %w[Documents FundDocs KycDocs OfferDocs].freeze

  belongs_to :entity
  belongs_to :owner, -> { with_deleted }, polymorphic: true
  belongs_to :user

  validates :import_file_data, :name, presence: true
  validates :import_type, length: { maximum: 50 }
  validate :owner_must_be_valid, on: :create

  include FileUploader::Attachment(:import_file)
  include FileUploader::Attachment(:import_results)

  after_create_commit :run_import_job
  def run_import_job
    ImportUploadJob.set(wait: 2.seconds).perform_later(id) unless Rails.env.test?
  end

  after_save_commit :broadcast_iu, on: [:update]

  def broadcast_iu
    broadcast_update partial: "/import_uploads/show"
  end

  def owner_must_be_valid
    errors.add(:owner, "Owner must be present and not deleted.") if owner.blank? || (owner.respond_to?(:deleted?) && owner.deleted?)
  end

  def percent_completed
    return 0 if total_rows_count.zero?

    (processed_row_count.to_f / total_rows_count * 100).round(2)
  end

  # Failure is decided by the rows, not the status text: importers also write
  # "imported, but ..." warnings into status after every row has saved.
  def failed?
    # The job writes "Failed" when the import service itself returns failure
    return true if status == "Failed" || failed_row_count.positive?
    # A crash or a job killed mid-run leaves rows unprocessed
    return true if processed_row_count < total_rows_count
    # A crash after every row saved (eg in post_process): ImportUploadJob stores the backtrace
    # in error_text, which importer warnings never contain
    return true if error_text.to_s.match?(/\.rb:\d+:in /)

    # A crash before the rows were counted (eg an unreadable file) leaves only its message
    total_rows_count.zero? && status.present? && status != "Completed"
  end

  # Every row imported, but an importer left a message in status (eg remittances not verified)
  def success_with_warnings?
    !failed? && status.present? && status != "Completed"
  end

  # ImportUploadJob always sets a status when it finishes (Completed, Failed or the error),
  # so a recent upload with no status is still queued or running. The 1 day window keeps
  # historical nil-status uploads, and jobs killed mid-run, from showing as in progress forever.
  def in_progress?
    status.blank? && created_at > 1.day.ago
  end

  # What happened, for API clients (H20 H21 E25 E33), from the same rules the import screens use
  # (failed?, success_with_warnings?, in_progress?). `status` is left exactly as it was ("Completed" even
  # when rows failed), because journeys and existing clients read it.
  #   running          — still queued or running
  #   succeeded        — every row imported (a status message is then a warning, see #warning)
  #   partially_failed — some rows imported, some failed
  #   failed           — nothing imported (every row failed, or the file was refused)
  def outcome
    return "running" if in_progress?
    return "succeeded" unless failed?

    processed_row_count.to_i.positive? ? "partially_failed" : "failed"
  end

  # The status message of an upload whose rows all imported — a warning, not a failure (E33)
  def warning
    status if success_with_warnings?
  end

  IMPORTED_DATA_INCLUDES = {
    "InvestmentInstrument" => [:portfolio_company]
  }.freeze

  def imported_data
    # A retired type (DocQuestion) has no model any more: its old uploads still open, with nothing to list
    return ImportUpload.none if model_class.nil?

    records = model_class.where(import_upload_id: id)
    assocs = IMPORTED_DATA_INCLUDES[import_type]
    assocs ? records.includes(*assocs) : records
  end

  def model_class
    # DealActivityTemplate is not a model class; templates are stored as DealActivity records.
    return DealActivity if import_type == "DealActivityTemplate"

    DOC_TYPES.include?(import_type) ? Document : import_type.safe_constantize
  end

  def to_s
    "#{name} : #{import_type}"
  end

  def form_type_names
    case import_type
    when "InvestorKyc" then %w[IndividualKyc NonIndividualKyc]
    when "DealActivityTemplate" then %w[DealActivity]
    else [import_type]
    end
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at failed_row_count import_type name processed_row_count status total_rows_count updated_at user_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    ["user"]
  end

  def headers
    return [] if import_type.blank?

    importer = "Import#{import_type}".safe_constantize&.new
    # The columns a sheet must have — the browser preview checks the same set the server does (P8)
    return importer.required_headers if importer.respond_to?(:required_headers) && importer.respond_to?(:standard_headers)

    importer.respond_to?(:standard_headers) ? importer.standard_headers : []
  end

  def xlsx_upload?
    import_type.present? && DOC_TYPES.exclude?(import_type)
  end
end
