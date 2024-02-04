class DealActivity < ApplicationRecord
  include Trackable.new
  include ActivityTrackable
  include WithFolder

  attr_accessor :has_documents_nested_attributes

  acts_as_list scope: %i[deal_id deal_investor_id], column: :sequence

  default_scope { order(sequence: :asc) }

  belongs_to :deal, touch: true
  belongs_to :deal_investor, optional: true
  belongs_to :entity

  delegate :investor_name, to: :deal_investor, allow_nil: true
  delegate :name, to: :entity, prefix: :entity
  delegate :name, to: :deal, prefix: :deal

  has_rich_text :details
  validates :title, :days, presence: true
  validates :status, length: { maximum: 20 }
  validates :completed, length: { maximum: 5 }

  scope :templates, ->(deal) { where(deal_id: deal.id).where(deal_investor_id: nil).order("sequence asc") }
  scope :not_templates, ->(deal) { where(deal_id: deal.id).where.not(deal_investor_id: nil).order("sequence asc") }

  before_save :set_defaults
  after_commit :recreate_activities, unless: :destroyed?

  validate :check_done

  def set_defaults
    self.status = "Template" if deal_investor_id.nil?
  end

  def check_done
    errors.add(:documents, "required for completing the activity") if completed == "Yes" && docs_required_for_completion && !(has_documents_nested_attributes || documents.present?)
    errors.add(:details, "required for marking N/A") if completed == "N/A" && details_required_for_na && details.blank?
  end

  def recreate_activities
    # If the deal has already started && this template for the deal is saved
    if status == "Template"
      # Then we recreate the activities for the deal
      GenerateDealActivitiesJob.perform_later(deal_id, "Deal")
    end
  end

  def completed_status
    completed
  end

  def to_s
    "#{title} : #{investor_name}"
  end

  def folder_path
    "#{deal_investor.folder_path}/Steps/#{title.delete('/')}" if deal_investor
  end

  def folder_type
    :regular
  end
end
