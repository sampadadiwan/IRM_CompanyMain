class KanbanBoard < ApplicationRecord
  include Trackable.new

  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :entity
  has_many :kanban_columns, -> { order(:sequence) }, dependent: :destroy
  has_many :kanban_cards, through: :kanban_columns

  after_create :create_columns

  OWNER_TYPES = {
    Blank: "blank",
    InvestorKyc: "investor_name",
    Deal: "name"
  }.freeze

  OWNER_TYPES_FORM_NAMES = {
    None: "KanbanBoard",
    Deal: "Deal"
  }.freeze

  def self_owned?
    owner_id == id
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[kanban_columns kanban_cards]
  end

  def broadcast_data
    {
      item: "boards",
      item_id: id,
      event: "updated"
    }
  end

  def create_columns
    return unless owner

    step_names = owner.entity.entity_setting.kanban_steps[owner_type] || ["Example Step"]
    kanban_columns = []
    step_names.each_with_index do |step_name, index|
      kanban_columns << { name: step_name.strip, sequence: index + 1, entity_id:, kanban_board_id: id }
    end
    # rubocop:disable Rails/SkipsModelValidations
    KanbanColumn.insert_all(kanban_columns)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def to_s
    name
  end
end
