class Fund < ApplicationRecord
  include WithFolder
  include WithSnapshot
  include WithDataRoom
  include InvestorsGrantedAccess
  include Trackable.new
  include WithApprovals
  include WithExchangeRate
  include WithIncomingEmail
  acts_as_favoritable
  include ForInvestor
  include WithCustomField
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

  scope :feeder_funds, -> { where.not(master_fund_id: nil) }
  scope :master_funds, -> { where(master_fund_id: nil) }

  has_many :fund_ratios, dependent: :destroy
  has_many :valuations, as: :owner, dependent: :destroy

  has_many :account_entries, dependent: :destroy
  has_many :allocation_runs, dependent: :destroy
  has_many :fund_reports, dependent: :destroy

  has_many :portfolio_scenarios, dependent: :destroy
  has_many :portfolio_cashflows, dependent: :destroy
  has_many :portfolio_attributions, dependent: :destroy
  has_many :portfolio_investments, dependent: :destroy
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

  has_many :fund_formulas, dependent: :destroy

  has_many :fund_account_entries, ->(_ae) { where(account_entries: { capital_commitment_id: nil }) }, class_name: "AccountEntry", dependent: :destroy

  has_many :access_rights, as: :owner, dependent: :destroy

  validates :name, :currency, presence: true
  normalizes :name, with: ->(name) { name.strip.squeeze(" ") }
  # Unique name for the fund, unless its a snapshot
  validates :name, uniqueness: { scope: :entity_id }, if: -> { !snapshot? }

  validates :commitment_doc_list, length: { maximum: 100 }
  validates :name, :tag_list, :unit_types, length: { maximum: 255 }
  validates :category, length: { maximum: 15 }

  CATEGORIES = ["Category I", "Category II", "Category III"].freeze
  REMITTANCE_GENERATION_BASIS = ["Folio Amount", "Fund Amount"].freeze

  monetize  :tracking_committed_amount_cents, :tracking_call_amount_cents,
            :tracking_collected_amount_cents, :tracking_distribution_amount_cents,
            with_currency: ->(f) { f.tracking_currency.presence || f.currency }

  monetize :call_amount_cents, :committed_amount_cents, :target_committed_amount_cents,
           :collected_amount_cents, :distribution_amount_cents, :total_units_premium_cents,
           with_currency: ->(f) { f.currency }

  def private_folder_names
    ["Reports", "Private Documents"]
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

  TEMPLATE_TAGS = ["Commitment Template", "Call Template", "SOA Template", "Distribution Template"].freeze
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
    %w[call_amount capital_commitments_count category collected_amount committed_amount currency distribution_amount first_close_date last_close_date name start_date tag_list unit_types snapshot_date snapshot].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  def generate_fund_ratios(user_id, end_date, generate_for_commitments: false)
    FundRatiosJob.perform_later(id, nil, end_date, user_id, generate_for_commitments)
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
    last_fund_ratio = fund_ratios.order(end_date: :desc).first
    # Only update the latest flag if the end_date is the latest
    if last_fund_ratio && last_fund_ratio.end_date <= end_date
      fund_ratios.update_all(latest: false)
      fund_ratios.where(end_date:).update_all(latest: true)
    end
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

  def transfer_commitment(capital_commitment, to_commitments)
    # Assume that the commitment adjustment is already created

    to_commitments.each do |commitment_id, percent_transferred|
      to_capital_commitment = capital_commitments.find(commitment_id)
      # copy over the remittances and the payments
      to_capital_commitment.capital_remittances.each do |remittance|
        new_remittance = remittance.dup
        new_remittance.capital_commitment = to_capital_commitment
        new_remittance.investor_id = to_capital_commitment.investor_id
        new_remittance.folio_id = to_capital_commitment.folio_id
        # Adjust the amounts based on the percentage transferred
        new_remittance.call_amount_cents = (remittance.amount * percent_transferred).round(2)
      end
    end

    # Delete the remittances
    capital_commitment.capital_remittances.destroy_all
    # Delete the Distribution payments
    capital_commitment.capital_distribution_payments.destroy_all
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
end
