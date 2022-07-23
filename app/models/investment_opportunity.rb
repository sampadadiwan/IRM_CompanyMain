class InvestmentOpportunity < ApplicationRecord
  include WithFolder

  acts_as_taggable_on :tags

  belongs_to :entity
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  has_many :expression_of_interests, dependent: :destroy

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  has_rich_text :details

  include FileUploader::Attachment(:logo)
  include FileUploader::Attachment(:video)

  monetize :fund_raise_amount_cents, :valuation_cents,
           :min_ticket_size_cents

  before_create :set_currency
  def set_currency
    self.currency ||= entity.currency
  end

  def name
    company_name
  end

  def setup_folder_details
    parent_folder = Folder.where(entity_id:, level: 1, name: self.class.name.pluralize.titleize).first
    setup_folder(parent_folder, company_name, [])
  end

  def self.for_investor(user, entity)
    InvestmentOpportunity
      # Ensure the access rghts for Document
      .joins(:access_rights)
      .merge(AccessRight.access_filter)
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      .where("entities.id=?", entity.id)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  end

  def notify_open_for_interests
    InvestmentOpportunityMailer.with(id:).notify_open_for_interests.deliver_later
  end
end
