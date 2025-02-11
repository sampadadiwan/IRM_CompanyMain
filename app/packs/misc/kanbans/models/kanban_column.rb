class KanbanColumn < ApplicationRecord
  include Trackable.new
  acts_as_list scope: %i[kanban_board_id], column: :sequence
  belongs_to :kanban_board
  belongs_to :entity
  has_many :kanban_cards, dependent: :destroy
  validates :name, presence: true

  after_create_commit :broadcast_new_column
  after_update_commit :broadcast_column_changes

  private

  def broadcast_new_column
    kanban_board.broadcast_board_event
  end

  def broadcast_column_changes
    if saved_change_to_name?
      broadcast_update partial: "/kanban_columns/kanban_column_show"
    elsif saved_change_to_sequence?
      kanban_board.broadcast_board_event
    end
  end
end
