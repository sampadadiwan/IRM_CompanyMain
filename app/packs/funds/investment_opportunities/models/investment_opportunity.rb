class InvestmentOpportunity < ApplicationRecord
  include ForInvestor
  include WithFolder
  include WithCustomField
  include InvestorsGrantedAccess

  update_index('investment_opportunity') { self }

  belongs_to :entity, touch: true

  has_many :access_rights, as: :owner, dependent: :destroy

  has_many :expression_of_interests, dependent: :destroy

  has_rich_text :details

  validates :company_name, :fund_raise_amount_cents, :min_ticket_size_cents,
            :currency, :last_date, presence: true

  validates :fund_raise_amount, :min_ticket_size, numericality: { greater_than: 0 }
  validates :company_name, length: { maximum: 100 }
  validates :currency, length: { maximum: 10 }
  validates :tag_list, length: { maximum: 120 }

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
