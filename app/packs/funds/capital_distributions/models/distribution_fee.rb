class DistributionFee < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :capital_distribution
  attr_readonly :capital_distribution_id # never moves to another distribution (funds_api_security_policy_plan.md, B)
  # M13 (OWASP 2026-11) K8 — a fee line decides which account entries are deducted from or added to payments, so
  # changing, adding or deleting one is a figure change of the distribution (design card ②; columns confirmed from
  # db/schema.rb — notes is no longer evaluated, so it is not a figure)
  include ApprovalFigureWatch

  APPROVAL_FIGURES = %w[name start_date end_date fee_type formula cumulative entry_type parent_type parent_ids audit_name].freeze
  watches_approval_figures APPROVAL_FIGURES, parent: :capital_distribution
  validates :start_date, :end_date, presence: true
  # if name is blank we need entry type to filter
  # we need either name or audit name to create audit
  validates :audit_name, :entry_type, presence: true, if: ->(fee) { fee.name.blank? }
  validates :name, :audit_name, length: { maximum: 65 }, allow_blank: true
  validates :fee_type, length: { maximum: 20 }, allow_blank: true

  # `notes` may hold a fee formula. It is no longer evaluated anywhere (C2: the dead
  # #calculate_formula was removed, and no stored formula exists); the write-time check stays so a
  # formula never enters the table.
  validate :notes_kosher?
  def notes_kosher?
    errors.add(:notes, "You cannot do CRUD or system operations in a fee formula") if notes.present? && notes.downcase.match?(SAFE_EVAL_REGEX)
  end

  TYPES = ["FV For Redemption", "Income", "Expense", "Tax", "Reinvestment", "Display Only"].freeze

  # Maps each fee type label to the context key suffix used when storing breakdowns.
  # Used in CapitalDistributionPaymentDocGenerator
  KYC_FEE_TYPE_KEYS = {
    "FV For Redemption" => :fvr,
    "Income" => :income,
    "Expense" => :expense,
    "Tax" => :tax,
    "Reinvestment" => :reinvestment,
    "Display Only" => :disp
  }.freeze

  NESTED_ATTRIBUTES = %i[id name start_date end_date fee_type notes _destroy].freeze
  NESTED_ATTRIBUTES_WITH_FORMULA = %i[id name start_date end_date fee_type notes _destroy formula].freeze

  before_validation :setup_entity

  scope :formulas, -> { where(formula: true) }
  scope :income, -> { where(fee_type: "Income") }
  scope :expense, -> { where(fee_type: "Expense") }
  scope :tax, -> { where(fee_type: "Tax") }
  scope :reinvestment, -> { where(fee_type: "Reinvestment") }
  scope :display_only, -> { where(fee_type: "Display Only") }
  scope :fv_for_redemption, -> { where(fee_type: "FV For Redemption") }

  def setup_entity
    self.entity_id = capital_distribution.entity_id
    self.fund_id = capital_distribution.fund_id
  end
end
