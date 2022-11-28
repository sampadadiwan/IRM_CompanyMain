class DealActivity < ApplicationRecord
  include ActivityTrackable
  include WithFolder

  acts_as_list scope: %i[deal_id deal_investor_id], column: :sequence

  default_scope { order(sequence: :asc) }

  belongs_to :deal, touch: true
  belongs_to :deal_investor, optional: true
  belongs_to :entity
  has_many :documents, as: :owner, dependent: :destroy

  delegate :investor_name, to: :deal_investor, allow_nil: true
  delegate :name, to: :entity, prefix: :entity
  delegate :name, to: :deal, prefix: :deal

  has_rich_text :details
  validates :title, :days, presence: true

  scope :templates, ->(deal) { where(deal_id: deal.id).where(deal_investor_id: nil).order("sequence asc") }

  before_save :set_defaults
  after_save :recreate_activities

  def set_defaults
    self.status = "Template" if deal_investor_id.nil?
  end

  def recreate_activities
    # If the deal has already started && this template for the deal is saved
    if status == "Template" && deal.started?
      # Then we recreate the activities for the deal
      GenerateDealActivitiesJob.perform_later(deal_id, "Deal")
    end
  end

  def completed_status
    completed ? "Yes" : "No"
  end

  def summary
    status.presence || completed_status
  end

  def to_s
    "#{title} : #{investor_name}"
  end

  def folder_path
    "#{deal_investor.folder_path}/Steps/#{id}"
  end

  scope :for_advisor, lambda { |user|
    # Ensure the access rghts for Document
    joins(deal_investor: :access_rights).merge(AccessRight.access_filter)
                                        .where("access_rights.metadata=?", "Advisor").joins(entity: :investors)
                                        .where("investors.investor_entity_id=?", user.entity_id)
  }
end
