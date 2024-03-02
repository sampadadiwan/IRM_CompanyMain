class ImportUpload < ApplicationRecord
  SAMPLES = { "INVESTOR_ACCESS_SAMPLE" => "/sample_uploads/investor_access.xlsx",
              "INVESTORS_SAMPLE" => "/sample_uploads/investors.xlsx",
              "FUND_INVESTORS_SAMPLE" => "/sample_uploads/fund_investors.xlsx",
              "HOLDINGS_SAMPLE" => "/sample_uploads/holdings.xlsx",
              "OFFERS_SAMPLE" => "/sample_uploads/offers.xlsx",
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
              "OPTIONS_CUSTOM_DATA_SAMPLE" => "/sample_uploads/options_custom_data.xlsx",
              "FUND_UNIT_SETTING_SAMPLE" => "/sample_uploads/fund_unit_setting.xlsx",
              "FUND_UNIT_SAMPLE" => "/sample_uploads/fund_units.xlsx",
              "ACCOUNT_ENTRY_SAMPLE" => "/sample_uploads/account_entries.xlsx",
              "KPIS_SAMPLE" => "/sample_uploads/kpis.xlsx" }.freeze

  TYPES = %w[InvestorAccess Investor CapitalCommitment CapitalCall CapitalRemittance CapitalRemittancePayment CapitalDistribution CapitalDistributionPayment Documents PortfolioInvestment PortfolioIncome Valuation FundDocs FundUnitSetting FundUnit AccountEntry InvestorKyc InvestorAdvisor Holding Offer OfferDocs OptionsCustomData Kpi KycDocs].sort.freeze

  DOC_TYPES = %w[Documents FundDocs KycDocs OfferDocs].freeze

  belongs_to :entity
  belongs_to :owner, polymorphic: true
  belongs_to :user

  validates :import_file_data, :name, presence: true
  validates :import_type, length: { maximum: 50 }

  include FileUploader::Attachment(:import_file)
  include FileUploader::Attachment(:import_results)

  after_create_commit :run_import_job
  def run_import_job
    ImportUploadJob.set(wait_until: 2.seconds).perform_later(id) unless Rails.env.test?
  end

  after_save_commit :broadcast_iu, on: [:update]

  def broadcast_iu
    broadcast_update partial: "/import_uploads/show"
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
end
