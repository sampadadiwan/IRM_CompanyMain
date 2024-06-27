class KanbanCard < ApplicationRecord
  include Trackable.new

  acts_as_list scope: :kanban_column, column: :sequence
  update_index('kanban_card') { self if index_record? }
  belongs_to :kanban_board
  belongs_to :entity
  belongs_to :kanban_column, class_name: 'KanbanColumn'
  belongs_to :data_source, polymorphic: true, optional: true
  has_many :documents, as: :documentable

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
