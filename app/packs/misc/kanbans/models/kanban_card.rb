class KanbanCard < ApplicationRecord
  include Trackable.new

  acts_as_list scope: :kanban_column, column: :sequence
  update_index('kanban_card') { self if index_record? }
  belongs_to :kanban_board
  attr_readonly :kanban_board_id # never moves to another board (funds_api_security_policy_plan.md, B)
  belongs_to :entity
  belongs_to :kanban_column, class_name: 'KanbanColumn'
  # A card can be dragged to another column of its own board, never to another board's (C)
  validate do
    board_id = kanban_board_id_in_database || kanban_board_id
    errors.add(:kanban_column, "must be on this card's board") if kanban_column && kanban_column.kanban_board_id != board_id
  end
  belongs_to :data_source, polymorphic: true, optional: true
  has_many :documents, as: :documentable

  scope :sequenced, -> { order(:sequence) }

  before_save :set_data_source
  after_commit :broadcast_card
  delegate :broadcast_board_event, to: :kanban_board

  def set_data_source
    self.data_source = self if data_source_id.nil?
  end

  def broadcast_card
    broadcast_update partial: "/kanban_cards/kanban_card_show" unless saved_change_to_deleted_at?
    kanban_board.broadcast_board_event if saved_change_to_sequence? || saved_change_to_kanban_column_id? || deleted? || destroyed? || saved_change_to_deleted_at?
  end

  def get_data_from_source
    owner.get_data
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[title tags info_field]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[kanban_board kanban_column]
  end
end
