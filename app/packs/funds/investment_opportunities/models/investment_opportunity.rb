class InvestmentOpportunity < ApplicationRecord
  include ForInvestor
  include WithFolder
  include WithCustomField
  include InvestorsGrantedAccess

  update_index('investment_opportunity') { self if index_record? }

  belongs_to :entity, touch: true
  has_many :access_rights, as: :owner, dependent: :destroy
  has_many :expression_of_interests, dependent: :destroy

  has_many :ci_track_records, as: :owner, dependent: :destroy
  has_many :ci_widgets, as: :owner, dependent: :destroy

  has_many :noticed_events, as: :record, dependent: :destroy, class_name: "Noticed::Event"

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

  def document_list
    nil
  end

  def investors
    Investor.owner_access_rights(self, nil)
  end

  def notify_open_for_interests
    investors.each do |investor|
      investor.notification_users.each do |user|
        InvestmentOpportunityNotifier.with(record: self, entity_id:, email_method: :notify_open_for_interests, msg: "New Investment Opportunity: #{name}").deliver_later(user)
      end
    end
  end

  def notify_allocation
    investors.each do |investor|
      investor.notification_users.each do |user|
        InvestmentOpportunityNotifier.with(record: self, entity_id:, email_method: :notify_allocation, msg: "Allocation completed for Investment Opportunity: #{name}").deliver_later(user)
      end
    end
  end

  def percentage_raised
    ((eoi_amount_cents * 100.0) / fund_raise_amount_cents).round(2)
  end

  def to_s
    company_name
  end

  after_commit :update_investor_entity
  # rubocop:disable Rails/SkipsModelValidations
  # This is to bust any cached dashboards showing the commitments
  def update_investor_entity
    investors.each do |i|
      i.investor_entity&.touch
    end
  end
  # rubocop:enable Rails/SkipsModelValidations

  def default_currency_units
    currency == "INR" ? "Crores" : "Million"
  end
end
