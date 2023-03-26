class Fund < ApplicationRecord
  include ForInvestor
  include InvestorsGrantedAccess
  include WithFolder
  include WithDataRoom
  include WithCustomField
  include Trackable
  include ActivityTrackable
  tracked owner: proc { |_controller, model| model }, entity_id: proc { |_controller, model| model.entity_id }

  update_index('fund') { self }

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

  has_many :account_entries, dependent: :destroy
  has_many :aggregate_portfolio_investments, dependent: :destroy
  has_many :portfolio_investments, dependent: :destroy
  has_many :fund_formulas, dependent: :destroy
  has_many :fund_unit_settings, dependent: :destroy
  has_many :fund_units, dependent: :destroy

  has_many :fund_account_entries, ->(_ae) { where(account_entries: { capital_commitment_id: nil }) }, class_name: "AccountEntry", dependent: :destroy

  has_many :access_rights, as: :owner, dependent: :destroy

  monetize :call_amount_cents, :committed_amount_cents, :collected_amount_cents, :distribution_amount_cents,
           :co_invest_call_amount_cents, :co_invest_committed_amount_cents, :co_invest_collected_amount_cents, :co_invest_distribution_amount_cents, :total_units_premium_cents, with_currency: ->(i) { i.currency }

  validates :name, :currency, presence: true

  def generate_fund_ratios(user_id, end_date, generate_for_commitments: false)
    FundRatiosJob.perform_later(id, nil, end_date, user_id, generate_for_commitments)
  end

  def to_be_called_amount
    call_amount - collected_amount
  end

  def folder_path
    "/Funds/#{name.delete('/')}"
  end

  def folder_type
    :regular
  end

  def investors
    Investor.owner_access_rights(self, "Investor")
  end

  def to_s
    name
  end

  def mkdirs
    # dirs = ["funds", "capital_calls", "capital_commitments", "capital_distributions", "capital_distribution_payments", "capital_remittances"]

    # dirs = ["access_rights", "documents", "entities", "folders", "notes", "permissions", "reminders", "tasks", "users", "investors", "investor_accesses"]

    subs = %w[models controllers views jobs policies mailers helpers]

    dirs.each do |dir|
      FileUtils.mkdir_p "app/packs/funds/#{dir}"
      subs.each do |sub|
        FileUtils.mkdir_p "app/packs/funds/#{dir}/#{sub}"
      end
    end
  end

  TEMPLATE_TAGS = ["Commitment Template", "Call Template", "SOA Template"].freeze
  def document_tags
    TEMPLATE_TAGS
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
end
