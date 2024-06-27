class KanbanColumn < ApplicationRecord
  include Trackable.new
  acts_as_list scope: %i[kanban_board_id], column: :sequence
  belongs_to :kanban_board
  belongs_to :entity
  has_many :kanban_cards, -> { order(:sequence) }, dependent: :destroy

  validates :name, presence: true
end
