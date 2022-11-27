class InvestmentOpportunity < ApplicationRecord
  include WithFolder

  update_index('investment_opportunity') { self }

  acts_as_taggable_on :tags

  belongs_to :entity, touch: true
  belongs_to :funding_round

  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  has_many :expression_of_interests, dependent: :destroy

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  has_rich_text :details

  validates :company_name, :fund_raise_amount_cents, :min_ticket_size_cents,
            :valuation_cents, :currency, :last_date, presence: true

  validates :fund_raise_amount, :min_ticket_size, :valuation, numericality: { greater_than: 0 }

  include FileUploader::Attachment(:logo)
  include FileUploader::Attachment(:video)

  before_validation :set_currency
  def set_currency
    self.currency ||= entity.currency
  end

  monetize :fund_raise_amount_cents, :valuation_cents,
           :min_ticket_size_cents, :eoi_amount_cents, with_model_currency: :currency

  before_validation :setup_funding_round
  def setup_funding_round
    self.funding_round = FundingRound.new(name:, entity_id:, status: "Open", currency: entity.currency)
  end

  def name
    company_name
  end

  def folder_path
    "/InvestmentOpportunity/#{company_name}"
  end

  def setup_folder_details
    setup_folder_from_path(folder_path)
  end

  def self.for_investor(user)
    InvestmentOpportunity
      # Ensure the access rghts for Document
      .joins(:access_rights)
      .merge(AccessRight.access_filter)
      .joins(entity: :investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      # .where("entities.id=?", entity.id)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  end

  def notify_open_for_interests
    InvestmentOpportunityMailer.with(id:).notify_open_for_interests.deliver_later
  end

  def notify_allocation
    InvestmentOpportunityMailer.with(id:).notify_allocation.deliver_later
  end

  def percentage_raised
    ((eoi_amount_cents * 100.0) / fund_raise_amount_cents).round(2)
  end
end
