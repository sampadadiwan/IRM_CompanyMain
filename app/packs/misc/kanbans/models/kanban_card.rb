class KanbanCard < ApplicationRecord
  include Trackable.new

  acts_as_list scope: :kanban_column, column: :sequence
  update_index('kanban_card') { self if index_record? }
  belongs_to :kanban_board
  belongs_to :entity
  belongs_to :kanban_column, class_name: 'KanbanColumn'
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
