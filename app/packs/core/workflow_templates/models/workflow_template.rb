class WorkflowTemplate < ApplicationRecord
  belongs_to :entity

  has_many :workflow_steps, -> { order(:position) }, dependent: :destroy, inverse_of: :workflow_template
  has_many :workflow_step_actors, through: :workflow_steps
  has_many :folders, dependent: :nullify

  accepts_nested_attributes_for :workflow_steps, allow_destroy: true

  validates :name, presence: true
  validates :name, uniqueness: { scope: :entity_id, message: "must be unique within your organisation" }

  def to_s
    name
  end

  # Number of folders currently using this template
  def active_folder_count
    folders.count
  end
end
