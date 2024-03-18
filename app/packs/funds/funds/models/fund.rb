class Fund < ApplicationRecord
  acts_as_favoritable
  include ForInvestor
  include InvestorsGrantedAccess
  include WithFolder
  include WithDataRoom
  include WithCustomField
  include Trackable.new
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model }, entity_id: proc { |_controller, model| model.entity_id }

  update_index('fund') do
    self if index_record?
  end

  CATEGORIES = ["Category I", "Category II", "Category III"].freeze

  belongs_to :entity, touch: true
  belongs_to :fund_signatory, class_name: "User", optional: true
  belongs_to :trustee_signatory, class_name: "User", optional: true

  has_many :fund_ratios, dependent: :destroy
  has_many :valuations, as: :owner, dependent: :destroy
  has_many :capital_remittances, dependent: :destroy
  has_many :capital_remittance_payments, dependent: :destroy
  has_many :capital_commitments, dependent: :destroy
  has_many :capital_distributions, dependent: :destroy
  has_many :capital_distribution_payments, dependent: :destroy
  has_many :capital_calls, dependent: :destroy
  has_many :fund_reports, dependent: :destroy
  has_many :allocation_runs, dependent: :destroy

  has_many :account_entries, dependent: :destroy
  has_many :aggregate_portfolio_investments, dependent: :destroy
  has_many :portfolio_investments, dependent: :destroy
  has_many :portfolio_attributions, dependent: :destroy
  has_many :portfolio_cashflows, dependent: :destroy
  has_many :fund_formulas, dependent: :destroy
  has_many :fund_unit_settings, dependent: :destroy
  has_many :fund_units, dependent: :destroy
  has_many :investor_notices, as: :owner, dependent: :destroy

  has_many :fund_account_entries, ->(_ae) { where(account_entries: { capital_commitment_id: nil }) }, class_name: "AccountEntry", dependent: :destroy

  has_many :access_rights, as: :owner, dependent: :destroy

  monetize :call_amount_cents, :committed_amount_cents, :target_committed_amount_cents,
           :collected_amount_cents, :distribution_amount_cents,
           :co_invest_call_amount_cents, :co_invest_committed_amount_cents, :co_invest_collected_amount_cents, :co_invest_distribution_amount_cents, :total_units_premium_cents, with_currency: ->(i) { i.currency }

  validates :name, :currency, presence: true
  normalizes :name, with: ->(name) { name.strip.squeeze(" ") }

  validates :unit_types, :commitment_doc_list, :sponsor_name, :manager_name, :trustee_name, :contact_name, :contact_email, length: { maximum: 100 }
  validates :name, :tag_list, length: { maximum: 255 }
  validates :registration_number, length: { maximum: 20 }
  validates :category, length: { maximum: 15 }
  validates :sub_category, length: { maximum: 40 }

  def generate_fund_ratios(user_id, end_date, generate_for_commitments: false)
    FundRatiosJob.perform_later(id, nil, end_date, user_id, generate_for_commitments)
  end

  def pending_call_amount
    call_amount - collected_amount
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

  def to_s
    name
  end

  def get_lps_emails
    investors.joins(:investor_accesses).where('investor_accesses.approved = true').pluck('investor_accesses.email')
  end

  TEMPLATE_TAGS = ["Commitment Template", "Call Template", "SOA Template"].freeze
  def document_tags
    TEMPLATE_TAGS
  end

  def signature_labels
    ["Investor Signatories", "Fund Signatories", "Other"]
  end

  def fund_signatories
    esign_emails&.split(",")&.map(&:strip)
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

  def self.ransackable_attributes(_auth_object = nil)
    %w[name]
  end

  after_update_commit :name_change, if: :saved_change_to_name?
  def name_change
    document_folder.update_columns(name:, full_path: folder_path)
  end

  def default_currency_units
    currency == "INR" ? "Crores" : "Million"
  end
end
