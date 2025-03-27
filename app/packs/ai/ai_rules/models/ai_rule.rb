class AiRule < ApplicationRecord
  belongs_to :entity

  enum :rule_type, { 'compliance' => "Compliance", 'investor_relations' => "Investor Relations", 'investment_analyst' => "Investment Analyst" }
  enum :schedule, { 'end_of_day' => "End of Day", 'end_of_month' => "End of Month", 'end_of_quarter' => "End of Quarter", 'end_of_year' => "End of Year" }

  FOR_CLASSES = %w[AggregatePortfolioInvestment PortfolioInvestment IndividualKyc NonIndividualKyc CapitalCommitment CapitalRemittance CapitalDistribution Fund].sort

  scope :for_class, ->(klass) { where(for_class: klass) }
  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :for_schedule, ->(schedule) { where(schedule:) }
  scope :compliance, -> { where(rule_type: "compliance") }
  scope :investor_relations, -> { where(rule_type: "investor_relations") }
  scope :investment_analyst, -> { where(rule_type: "investment_analyst") }

  validates :for_class, presence: true
  validates :rule, presence: true
  validates :for_class, length: { maximum: 20 }
  validates :schedule, length: { maximum: 40 }
  validates :rule_type, length: { maximum: 15 }

  def to_s
    "#{for_class} - #{rule&.truncate(50)}"
  end

  def rule_type_label
    self.class.rule_types[rule_type]
  end

  def schedule_label
    self.class.schedules[schedule]
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[created_at enabled for_class rule rule_type schedule tags updated_at].sort
  end
end
