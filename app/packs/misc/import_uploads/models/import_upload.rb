class ImportUpload < ApplicationRecord
  SAMPLES = { "INVESTOR_ACCESS_SAMPLE" => "/sample_uploads/investor_access.xlsx",
              "INVESTORS_SAMPLE" => "/sample_uploads/investors.xlsx",
              "FUND_INVESTORS_SAMPLE" => "/sample_uploads/fund_investors.xlsx",
              "FUNDS_SAMPLE" => "/sample_uploads/funds.xlsx",
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
              "INVESTMENT_INSTRUMENT_SAMPLE" => "/sample_uploads/investment_instruments.xlsx" }.freeze

  TYPES = %w[InvestorAccess Investor CapitalCommitment CapitalCall CapitalRemittance CapitalRemittancePayment CapitalDistribution CapitalDistributionPayment Documents PortfolioInvestment PortfolioIncome Valuation FundDocs FundUnitSetting FundUnit AccountEntry InvestorKyc InvestorAdvisor Offer OfferDocs Kpi KycDocs Fund ExchangeRate Allocation FundRatio InvestmentInstrument].sort.freeze

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
    errors.add(:owner, "Owner must be present and not deleted.") if owner.blank? || owner.deleted?
  end

  def percent_completed
    return 0 if total_rows_count.zero?

    (processed_row_count.to_f / total_rows_count * 100).round(2)
  end

  def success?
    status.nil? && total_rows_count == processed_row_count
  end

  def imported_data
    model_class.where(import_upload_id: id)
  end

  def model_class
    DOC_TYPES.include?(import_type) ? Document : import_type.constantize
  end

  def to_s
    "#{name} : #{import_type}"
  end

  def form_type_names
    import_type == "InvestorKyc" ? %w[IndividualKyc NonIndividualKyc] : [import_type]
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at failed_row_count import_type name processed_row_count status total_rows_count updated_at user_id]
  end

  def self.ransackable_associations(_auth_object = nil)
    ["user"]
  end
end
