class Fund < ApplicationRecord
  include WithFolder
  include WithSnapshot
  include WithDataRoom
  include InvestorsGrantedAccess
  include Trackable.new
  include WithApprovals
  include WithExchangeRate
  include FundTrackingCurrencyChange
  include WithIncomingEmail
  include FundShared
  include FundNotifiers
  include EvergreenFund

  include FundEnabled
  include ForInvestor
  include WithCustomField
  include WithCustomNotifications
  include RansackerAmounts.new(fields: %w[collected_amount committed_amount call_amount distribution_amount])

  update_index('fund') do
    self if index_record?
  end

  PORTFOLIO_COST_TYPES = %w[FIFO WTD_AVG].freeze

  belongs_to :entity, touch: true
  belongs_to :fund_signatory, class_name: "User", optional: true
  belongs_to :trustee_signatory, class_name: "User", optional: true

  # If this is a feeder fund, it will have a ref to the master_fund
  belongs_to :master_fund, class_name: "Fund", optional: true
  # If this is a master fund, it may have many feeder funds
  has_many :feeder_funds, class_name: "Fund", foreign_key: :master_fund_id

  # LP portfolio view picks (LpPortfolioView): the allocation formula decides which holdings an LP sees and is
  # "Your cost"; the FMV formula is "Your FMV". FundFormula is soft-deleted, so a deleted pick simply reads
  # back as nil here (E6, E6a) — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
  belongs_to :lp_allocation_fund_formula, class_name: "FundFormula", optional: true
  belongs_to :lp_fmv_fund_formula, class_name: "FundFormula", optional: true

  has_many :fund_ratios, dependent: :destroy
  has_many :ratio_formulas, dependent: :destroy
  has_many :valuations, as: :owner, dependent: :destroy

  has_many :account_entries, dependent: :destroy
  has_many :allocation_runs, dependent: :destroy
  # Saved allocation run parameters for this fund. Restricted: a fund with templates has
  # a close that depends on it, so the templates must be removed deliberately first.
  has_many :allocation_run_templates, dependent: :restrict_with_error
  has_many :fund_reports, dependent: :destroy

  has_many :portfolio_scenarios, dependent: :destroy
  has_many :portfolio_cashflows, dependent: :destroy
  has_many :portfolio_attributions, dependent: :destroy
  has_many :portfolio_investments, dependent: :destroy
  has_many :portfolio_companies, through: :portfolio_investments, source: :portfolio_company
  has_many :stock_conversions, dependent: :destroy
  has_many :aggregate_portfolio_investments, dependent: :destroy
  has_many :investment_instruments, through: :aggregate_portfolio_investments

  has_many :fund_unit_settings, dependent: :destroy
  has_many :fund_units, dependent: :destroy
  has_many :investor_notices, as: :owner, dependent: :destroy

  has_many :capital_remittances, dependent: :destroy
  has_many :capital_remittance_payments, dependent: :destroy
  has_many :capital_distributions, dependent: :destroy
  has_many :capital_distribution_payments, dependent: :destroy
  has_many :capital_calls, dependent: :destroy
  has_many :commitment_adjustments, dependent: :destroy
  has_many :capital_commitments, dependent: :destroy
  has_many :investor_kycs, through: :capital_commitments
  has_many :committed_investors, through: :capital_commitments, source: :investor
  has_many :investor_accesses, through: :committed_investors

  has_many :fund_formulas, dependent: :destroy
  # Per-fund overrides of the entity's Market Data settings (limits) — openspec fund-market-data, card ①
  has_one :market_data_setting, dependent: :destroy
  accepts_nested_attributes_for :market_data_setting, update_only: true
  # Fund financial statements (app/packs/funds/financial_statements): mapping, layout and statement sets
  has_one :financial_statement_setting, dependent: :destroy
  has_many :financial_statements, dependent: :destroy
  has_many :financial_statement_mapping_suggestions, dependent: :destroy
  has_many :financial_statement_mapping_rules, dependent: :destroy
  has_many :financial_statement_definitions, dependent: :destroy
  has_many :financial_statement_accounts, dependent: :destroy
  has_many :shareholder_positions, dependent: :destroy

  has_many :fund_account_entries, ->(_ae) { where(account_entries: { capital_commitment_id: nil }) }, class_name: "AccountEntry", dependent: :destroy

  has_many :access_rights, as: :owner, dependent: :destroy

  validates :name, :currency, presence: true
  normalizes :name, with: ->(name) { name.strip.squeeze(" ") }
  # Unique name for the fund, unless its a snapshot
  validate :name_must_be_unique_for_non_snapshots, unless: :snapshot?

  normalizes :esign_emails, with: ->(v) { v&.gsub(/\s+/, '') }
  validate :esign_emails_must_be_valid, if: -> { esign_emails.present? }

  validates :commitment_doc_list, length: { maximum: 100 }
  validates :name, :tag_list, :unit_types, length: { maximum: 255 }
  validates :category, length: { maximum: 15 }
  validates :portfolio_cost_type, length: { maximum: 10 }, allow_blank: true
  validates :units_allocation_engine, length: { maximum: 50 }, allow_blank: true
  # X1–X5 — the LP portfolio view's formula picks
  validate { LpPortfolioView.validate(self) }

  scope :ordered, lambda {
    order(Arel.sql("
    COALESCE(
      CAST(funds.json_fields->>'$.position' AS DECIMAL(10,2)),
      99999.0
    ) ASC,
    funds.created_at ASC
  "))
  }

  CATEGORIES = ["Category I", "Category II", "Category III"].freeze
  REMITTANCE_GENERATION_BASIS = ["Folio Amount", "Fund Amount"].freeze
  STANDARD_COLUMNS = {
    "Name; text-col" => "name; text-col",
    "Category; text-col" => "category; text-col",
    "Tags; text-col" => "tag_list; text-col"
  }.freeze

  monetize  :tracking_committed_amount_cents, :tracking_call_amount_cents,
            :tracking_collected_amount_cents, :tracking_distribution_amount_cents,
            with_currency: ->(f) { f.tracking_currency.presence || f.currency }

  monetize :call_amount_cents, :committed_amount_cents, :target_committed_amount_cents,
           :collected_amount_cents, :distribution_amount_cents, :total_units_premium_cents,
           with_currency: ->(f) { f.currency }

  # The fund's LP portfolio view (:hidden, :whole_fund, :allocated, :allocated_with_share) — LpPortfolioView
  def lp_portfolio_view
    LpPortfolioView.from_flags(features)
  end

  def lp_portfolio_view=(option)
    LpPortfolioView.apply(self, option)
  end

  # Either allocated view: LPs see only holdings allocated to their folio (H2)
  def lp_folio_portfolio?
    %i[allocated allocated_with_share].include?(lp_portfolio_view)
  end

  # Own share can be shown only when the view asks for it and both picks still exist (E6 — a deleted
  # FMV formula hides the Your columns)
  def lp_own_share_ready?
    lp_portfolio_view == :allocated_with_share && lp_allocation_fund_formula.present? && lp_fmv_fund_formula.present?
  end

  # E1 — warn (never refuse) when the allocation formula has written no folio entries yet. One SELECT 1.
  def lp_folio_allocation_warning?
    return false unless lp_folio_portfolio? && lp_allocation_fund_formula_id.present?

    AccountEntry.where(fund_formula_id: lp_allocation_fund_formula_id).where.not(capital_commitment_id: nil).none?
  end

  def private_folder_names
    ["Reports", "Private Documents"]
  end

  def name_must_be_unique_for_non_snapshots
    errors.add(:name, "must be unique for non-snapshot funds within the same entity") if Fund.where(name: name, entity_id: entity_id, snapshot: false).where.not(id: id).exists?
  end

  def pending_call_amount
    call_amount - collected_amount
  end

  def has_tracking_currency?
    tracking_currency.present? && tracking_currency != currency
  end

  def unit_types_list
    unit_types&.split(",")&.map(&:strip)
  end

  def to_s
    snapshot ? "#{name} [Snapshot: #{snapshot_date}]" : name
  end

  def get_lps_emails
    investors.joins(:investor_accesses).where('investor_accesses.approved = true').pluck('investor_accesses.email')
  end

  TEMPLATE_TAGS = ["Commitment Template", "Call Template", "Investor Statement Template", "Distribution Template"].freeze
  def document_tags
    TEMPLATE_TAGS
  end

  def signature_labels
    ["Investor Signatories", "Fund Signatories", "Other"]
  end

  def fund_signatories
    esign_emails&.split(",")&.map(&:strip)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[call_amount capital_commitments_count category collected_amount committed_amount currency distribution_amount first_close_date last_close_date name start_date tag_list unit_types snapshot_date snapshot tracking_currency currency master_fund_id].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  def generate_fund_ratios(user_id, end_date, generate_for_commitments: false, return_cash_flows: false)
    FundRatiosJob.perform_later(id, nil, end_date, user_id, generate_for_commitments, return_cash_flows:)
  end

  def folder_path
    "/Funds/#{name.delete('/')}"
  end

  def folder_type
    :regular
  end

  def investors
    Investor.owner_access_rights(self, nil)
  end

  def current_fund_ratios(valuation = nil)
    valuation ||= valuations.order(valuation_date: :asc).last
    ratios = valuation ? fund_ratios.where(valuation_id: valuation.id, capital_commitment_id: nil) : fund_ratios.none
    [ratios, valuation]
  end

  # This method is used as sometimes we have setup a fund where two commitments belong to the same investor, but have got setup as 2 commitments under 2 different investors with similar names. WE need to merge all the commitments, remittances and payments and units
  def merge_investors(retained_investor, defunct_investor)
    investor_id = retained_investor.id
    investor_name = retained_investor.investor_name
    defunct_investor.investor_kycs.update_all(investor_id:)
    defunct_investor.capital_commitments.update_all(investor_id:, investor_name:)
    defunct_investor.capital_distribution_payments.update_all(investor_id:, investor_name:)
    defunct_investor.capital_remittances.update_all(investor_id:, investor_name:)
    defunct_investor.fund_units.update_all(investor_id:)
    defunct_investor.account_entries.update_all(investor_id:)

    AccessRight.where(access_to_investor_id: defunct_investor.id).update_all(access_to_investor_id: retained_investor.id)

    # defunct_investor.investor_name += " - Defunct"
    # defunct_investor.save
  end

  def check_access_rights(create_missing: false)
    ccs_wihout_ar = []
    capital_commitments.each do |cc|
      ar = access_rights.where(access_to_investor_id: cc.investor_id).first
      ccs_wihout_ar << cc.id if ar.nil?

      AccessRight.create(entity_id:, owner: self, access_to_investor_id: cc.investor_id, notify: false) if create_missing && ar.nil?
    end
    ccs_wihout_ar
  end

  def update_latest_fund_ratios(end_date)
    FundRatio.update_latest(self, end_date)
  end

  def reports_folder
    get_or_create_folder("Fund Reports")
  end

  # This method is called when an approval responses are created
  # It should return the owner for the approval_response, like commitments for a fund, offer for a sale etc
  def approval_for(investor_id)
    capital_commitments.where(investor_id:)
  end

  # This method is called when an approval is closed
  def post_approval(approval)
    Rails.logger.debug { "#{approval.title}: post approval" }
    # 1. Extract the approved amount from the approval responses
    # 2. Update the commitment capturing the approved amount for a PI
    # 3. Compute the total approved amount ratio for each commitment
    total_approved_amount = 0
    approval.approval_responses.each do |approval_response|
      approved_amount = approval_response.properties["approved_amount"]&.to_d || 0
      total_approved_amount += approved_amount
      approval_response.owner.properties ||= {}
      approval_response.owner.properties["approvals"] ||= {}

      approval_properties = approval_response.owner.properties["approvals"]
      approval_properties[approval.id] ||= {}
      approval_properties[approval.id]["title"] = approval.title
      approval_properties[approval.id]["approved_amount"] = approved_amount
      approval_response.owner.save
    end

    Rails.logger.debug { "Total approved amount: #{total_approved_amount}" }

    capital_commitments.each do |capital_commitment|
      capital_commitment.properties ||= {}
      capital_commitment.properties["approvals"] ||= {}

      approval_properties = capital_commitment.properties["approvals"]
      approval_properties[approval.id] ||= {}
      approval_properties[approval.id]["approved_amount"] ||= 0
      approval_properties[approval.id]["approved_percentage"] = total_approved_amount.positive? ? (approval_properties[approval.id]["approved_amount"].to_d / total_approved_amount) : 0
      capital_commitment.save
    end

    Rails.logger.debug { "Total approved amount: #{total_approved_amount}" }
  end

  def cat3?
    category == "Category III"
  end

  def commitments_in_master
    master_fund.capital_commitments.where(feeder_fund_id: id) if master_fund.present?
  end

  # Get the fund state as of a specific date
  # @param as_of_date [Date] The date to get the fund state as of
  # @return [FundAsOf] Fund state as of the specified date
  def as_of(as_of_date)
    FundAsOf.new(self, as_of_date)
  end

  def resave_portfolio_investments
    # Need to resave the PortfolioInvestments after running all formulas. This is cause some of the PI expenses are computed in the formulas and they change the total expense_cents for a PI see PortfolioInvestment.expense_cents()
    if entity.entity_setting.portflio_expense_account_entry_filter.present?
      PortfolioInvestment.where(fund_id: id).find_each do |portfolio_investment|
        PortfolioInvestmentUpdate.wtf?(portfolio_investment: portfolio_investment)
      end
    end
  end

  def check_percentage_calcs
    incorrect_percentage = []
    capital_commitments.each do |cc|
      incorrect_percentage << cc if cc.percentage.round(4) != (100 * cc.committed_amount_cents / cc.fund.committed_amount_cents).round(4)
    end
    incorrect_percentage
  end

  # Used only in the AccountEntryAllocationJob, which uses Sqlite for performance reasons
  def account_entries_sqlite
    AccountEntrySqlite.where(fund_id: id)
  end

  def portfolio_investment_ids
    @portfolio_investment_ids ||= portfolio_investments.pluck(:id)
    @portfolio_investment_ids
  end

  def kyc_level_data_gen?
    json_fields["call_notice_on"].to_s.strip.downcase == "kyc"
  end
end
