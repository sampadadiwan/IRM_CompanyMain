class InvestmentOpportunity < ApplicationRecord
  include WithFolder

  update_index('investment_opportunity') { self }

  belongs_to :entity, touch: true

  has_many :access_rights, as: :owner, dependent: :destroy

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

  def name
    company_name
  end

  def folder_path
    "/InvestmentOpportunity/#{company_name.delete('/')}"
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
