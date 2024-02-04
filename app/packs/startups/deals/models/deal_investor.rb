class DealInvestor < ApplicationRecord
  include Trackable.new
  include WithFolder
  include ForInvestor

  monetize  :fee_cents, :pre_money_valuation_cents, :secondary_investment_cents,
            :primary_amount_cents, with_currency: ->(i) { i.deal.currency }
  # Make all models searchable
  update_index('deal_investor') { self if index_record? }

  has_rich_text :notes
  belongs_to :deal, touch: true
  belongs_to :investor
  belongs_to :entity
  counter_culture :entity

  has_many :deal_activities, -> { order(sequence: :asc) }, dependent: :destroy
  has_many :messages, as: :owner, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy

  delegate :name, to: :entity, prefix: :entity
  delegate :name, to: :deal, prefix: :deal

  validates :status, :primary_amount_cents, :pre_money_valuation, presence: true
  validates :investor_id, uniqueness: { scope: :deal_id, message: "already added to this deal. Duplicate Investor." }
  validates :status, :tier, length: { maximum: 20 }
  validates :company_advisor, :investor_advisor, length: { maximum: 100 }

  STATUS = %w[Active Pending Declined].freeze

  scope :for, ->(user) { where("investors.investor_entity_id=?", user.entity_id).joins(:investor) }
  scope :not_declined, -> { where("deal_investors.status<>?", "Declined").joins(:investor) }

  before_save :set_investor_entity_id
  def set_investor_entity_id
    self.investor_entity_id = investor.investor_entity_id
    self.investor_name = investor.investor_name
  end

  after_commit :create_activities_later, unless: :destroyed?

  def create_activities_later
    GenerateDealActivitiesJob.perform_later(id, "DealInvestor")
  end

  def name
    investor_name
  end

  def to_s
    investor_name
  end

  def main_folder_name
    investor_name
  end

  def parent_folder_name
    "Deals"
  end

  def short_name
    names = investor_name.split("-")
    %w[Employees Founders].include?(names[1].strip) ? names[1] : names[0]
  end

  def total
    primary_amount + secondary_investment + fee
  end

  def create_activities
    start_date = deal.start_date
    by_date = nil
    seq = 1
    days_to_completion = 0

    DealActivity.templates(deal).each do |template|
      if start_date
        days_to_completion += template.days
        by_date = start_date + days_to_completion.days
      end

      existing = DealActivity.where(deal_id:, deal_investor_id: id, entity_id:, template_id: template.id).first

      if existing
        existing.update(title: template.title, sequence: template.sequence, days: template.days, by_date:, template_id: template.id, docs_required_for_completion: entity.activity_docs_required_for_completion, details_required_for_na: entity.activity_details_required_for_na)
      else
        DealActivity.create(deal_id:, deal_investor_id: id, entity_id:, template_id: template.id, title: template.title, sequence: template.sequence, days: template.days, by_date:, docs_required_for_completion: entity.activity_docs_required_for_completion, details_required_for_na: entity.activity_details_required_for_na)
      end

      seq += 1
    end
  end

  def messages_viewed(current_user)
    if current_user.entity_id == investor_entity_id
      self.unread_messages_investor = 0
    else
      self.unread_messages_investee = 0
    end

    save
  end

  def folder_path
    "#{deal.folder_path}/Deal Investors/#{investor_name.delete('/')}"
  end

  def folder_type
    :regular
  end

  def access_rights_changed(access_right)
    # Add the advisor name for easy access
    self.investor_advisor = Investor.owner_access_rights(self, "Advisor").pluck(:investor_name).join(",")
    save

    ar = AccessRight.where(id: access_right.id).first
    if ar
      # Ensure the advisor is also added to the deal
      deal_access_right = ar.dup
      deal_access_right.owner = deal
      deal_access_right.access_type = "Deal"
      deal_access_right.permissions = 0
      deal_access_right.permissions.set(:read)
      deal_access_right.save
    else
      deal.access_rights.where(access_to_investor_id: access_right.access_to_investor_id, access_to_category: access_right.access_to_category, user_id: access_right.user_id).find_each(&:destroy)
    end
  end
end
