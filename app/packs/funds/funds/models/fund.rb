class Fund < ApplicationRecord
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

  has_many :fund_account_entries, ->(_ae) { where(account_entries: { capital_commitment_id: nil }) }, class_name: "AccountEntry", dependent: :destroy

  has_many :access_rights, as: :owner, dependent: :destroy

  monetize :call_amount_cents, :committed_amount_cents, :collected_amount_cents, :distribution_amount_cents, :total_units_premium_cents, with_currency: ->(i) { i.currency }

  validates :name, :currency, presence: true

  def generate_calcs(user_id)
    FundCalcJob.perform_later(id, user_id)
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

  scope :for_employee, lambda { |user|
    includes(:access_rights).joins(:access_rights).where("funds.entity_id=? and access_rights.user_id=?", user.entity_id, user.id)
  }

  scope :for_advisor, lambda { |user|
    # Ensure the access rghts for Document
    includes(:access_rights).joins(:access_rights).merge(AccessRight.access_filter(user))
                            .where("access_rights.metadata=?", "Advisor").joins(entity: :investors)
                            .where("investors.investor_entity_id=?", user.entity_id)
  }

  scope :for_investor, lambda { |user|
    # Ensure the access rghts for Document
    joins(:access_rights)
      .merge(AccessRight.access_filter(user))
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      # .where("entities.id=?", entity.id)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  }

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

  def advisor_users
    investor_users("Advisor")
  end

  def investor_users(metadata = nil)
    User.joins(investor_accesses: :investor).where("investor_accesses.approved=? and investor_accesses.entity_id=?", true, entity_id).merge(Investor.owner_access_rights(self, metadata))
  end

  def current_fund_ratios(valuation = nil)
    valuation ||= valuations.order(valuation_date: :asc).last
    ratios = valuation ? fund_ratios.where(valuation_id: valuation.id) : fund_ratios.none
    [ratios, valuation]
  end
end
