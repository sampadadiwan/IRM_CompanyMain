class TaskTemplate < ApplicationRecord
  belongs_to :entity, optional: true
  acts_as_list scope: %i[for_class entity_id]

  validates :details, :for_class, presence: true
  validates :due_in_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  FOR_CLASS = %w[CapitalCommitment CapitalCall CapitalRemittance CapitalDistribution IndividualKyc NonIndividualKyc Offer Interest].freeze

  STANDARD_COLUMNS = { "For; text-col" => "for_class; text-col",
                       "Tags; text-col" => "tag_list; text-col",
                       "Details; text-col" => "details; text-col",
                       "#; num-col" => "position; num-col",
                       "Due In Days; num-col" => "due_in_days; num-col",
                       "Action; text-col" => "action_link; text-col",
                       "Help; text-col" => "help_link; text-col" }.freeze

  def to_s
    "#{for_class} - #{details&.truncate(20)}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[action_link details due_in_days for_class help_link tag_list].sort
  end
end
