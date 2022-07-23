class InvestmentOpportunity < ApplicationRecord
  include WithFolder

  acts_as_taggable_on :tags

  belongs_to :entity
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

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
end
