class TaskTemplate < ApplicationRecord
  belongs_to :entity, optional: true
  acts_as_list scope: %i[for_class entity_id]

  validates :details, :for_class, presence: true
  validates :due_in_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  STANDARD_COLUMNS = { "For" => "for_class",
                       "Tags" => "tag_list",
                       "Details" => "details",
                       "#" => "position",
                       "Due In Days" => "due_in_days",
                       "Action" => "action_link",
                       "Help" => "help_link" }.freeze

  def to_s
    "#{for_class} - #{details&.truncate(20)}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[action_link details due_in_days for_class help_link tag_list].sort
  end
end
