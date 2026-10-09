# A typed statement account ("Professional fees", expense, movement). Mapping rules feed account
# entries into it; layout rows place it on statements.
#
# Figures are kept in the account's natural sign: assets, liabilities, partners' capital, income and
# expenses are positive amounts; a distribution is a negative capital amount; a loss is a negative
# gain. flip_sign turns raw entry sums into that sign for funds that store an account the other way
# round (e.g. expenses uploaded as negatives, distributions as positives).
# Worked examples H1, X5, X6, E24 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementAccount < ApplicationRecord
  ACCOUNT_TYPES = %w[asset liability capital income expense gain_loss].freeze
  BEHAVIOURS = %w[balance movement].freeze
  # Profit and loss types: their since-inception result closes into partners' capital
  PNL_TYPES = %w[income expense gain_loss].freeze
  # Shown in brackets on statements (a cost or an amount owed)
  NEGATIVE_DISPLAY_TYPES = %w[expense liability].freeze

  TYPE_LABELS = { "asset" => "Asset", "liability" => "Liability", "capital" => "Partners' capital",
                  "income" => "Income", "expense" => "Expense", "gain_loss" => "Gain / Loss" }.freeze
  BEHAVIOUR_LABELS = { "balance" => "Balance (value at the date)", "movement" => "Movement (change over the period)" }.freeze

  belongs_to :entity
  belongs_to :fund
  has_many :mapping_rules, class_name: "FinancialStatementMappingRule", inverse_of: :account
  has_many :layout_rows, class_name: "FinancialStatementLayoutRow", inverse_of: :account

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :fund_id }
  validates :account_type, inclusion: { in: ACCOUNT_TYPES }
  validates :behaviour, inclusion: { in: BEHAVIOURS }
  normalizes :name, with: ->(name) { name.strip.squeeze(" ") }
  validate :name_without_statement_prefix
  before_validation :default_behaviour
  # X6: an account still used by a rule or a statement row cannot be deleted
  before_destroy :refuse_destroy_in_use

  scope :ordered, -> { order(:name) }

  def pnl?
    PNL_TYPES.include?(account_type)
  end

  def capital?
    account_type == "capital"
  end

  def type_label
    TYPE_LABELS[account_type]
  end

  def to_s
    name
  end

  # Asset, liability and capital accounts are values at a date; the rest change over a period
  def self.default_behaviour_for(account_type)
    %w[asset liability capital].include?(account_type) ? "balance" : "movement"
  end

  private

  # The "FS · " prefix is added to the stored statement lines automatically; an account name that
  # already starts with it would print fine but store as "FS · FS · …"
  def name_without_statement_prefix
    # X19: refused, with the reason
    return unless name.to_s.downcase.start_with?(FinancialStatementCalculator::FS_NAME_PREFIX.strip.downcase)

    errors.add(:name, "can't start with \"#{FinancialStatementCalculator::FS_NAME_PREFIX.strip}\" — CapHive adds that to the stored statement lines itself")
  end

  def default_behaviour
    self.behaviour = self.class.default_behaviour_for(account_type) if behaviour.blank? && account_type.present?
  end

  def refuse_destroy_in_use
    # Deleting the fund removes everything; its rules and rows are already gone by then
    return if destroyed_by_association

    rules = mapping_rules.to_a
    # X6: refused while a rule uses it, naming the rule(s)
    if rules.any?
      errors.add(:base, "#{name} is used by #{rules.size == 1 ? 'rule' : 'rules'} #{rules.map(&:key_label).to_sentence}. Change or remove #{rules.size == 1 ? 'it' : 'them'} first.")
      throw(:abort)
    end
    return unless layout_rows.exists?

    errors.add(:base, "#{name} is placed on a statement. Remove it from the layout first.")
    throw(:abort)
  end
end
