class InvestmentOpportunity < ApplicationRecord
  include WithFolder

  update_index('investment_opportunity') { self }

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
            :currency, :last_date, presence: true

  validates :fund_raise_amount, :min_ticket_size, numericality: { greater_than: 0 }

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
    "/InvestmentOpportunity/#{company_name}-#{id}"
  end

  def document_tags
    %w[Template Document]
  end

  def investors
    investor_list = []
    access_rights.not_user.includes(:investor).find_each do |ar|
      investor_list += ar.investors
    end
    investor_list.uniq
  end

  scope :for_investor, lambda { |user|
    joins(:access_rights)
      .merge(AccessRight.access_filter)
      .joins(entity: :investors)
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
  }

  def notify_open_for_interests
    InvestmentOpportunityMailer.with(id:).notify_open_for_interests.deliver_later
  end

  def notify_allocation
    InvestmentOpportunityMailer.with(id:).notify_allocation.deliver_later
  end

  def percentage_raised
    ((eoi_amount_cents * 100.0) / fund_raise_amount_cents).round(2)
  end

  def investor_users(metadata = nil)
    User.joins(investor_accesses: :investor).where("investor_accesses.approved=? and investor_accesses.entity_id=?", true, entity_id).merge(Investor.owner_access_rights(self, metadata))
  end
end
