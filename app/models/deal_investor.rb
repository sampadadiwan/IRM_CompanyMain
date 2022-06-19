# == Schema Information
#
# Table name: deal_investors
#
#  id                         :integer          not null, primary key
#  deal_id                    :integer          not null
#  investor_id                :integer          not null
#  status                     :string(20)
#  primary_amount_cents       :decimal(20, 2)   default("0.00")
#  secondary_investment_cents :decimal(20, 2)   default("0.00")
#  entity_id                  :integer          not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  investor_entity_id         :integer
#  deleted_at                 :datetime
#  impressions_count          :integer
#  unread_messages_investor   :integer          default("0")
#  unread_messages_investee   :integer          default("0")
#  todays_messages_investor   :integer          default("0")
#  todays_messages_investee   :integer          default("0")
#  pre_money_valuation_cents  :decimal(20, 2)   default("0.00")
#  company_advisor            :string(100)
#  investor_advisor           :string(100)
#  investor_name              :string(255)
#

class DealInvestor < ApplicationRecord
  # include Trackable

  monetize :secondary_investment_cents, with_currency: ->(i) { i.deal.currency }
  monetize :primary_amount_cents, with_currency: ->(i) { i.deal.currency }
  monetize :pre_money_valuation_cents, with_currency: ->(i) { i.deal.currency }

  # Make all models searchable
  update_index('deal_investor') { self }

  has_rich_text :notes
  belongs_to :deal # , strict_loading: true
  belongs_to :investor
  belongs_to :entity
  counter_culture :entity

  has_many :deal_activities, -> { order(sequence: :asc) }, dependent: :destroy
  has_many :messages, dependent: :destroy

  has_many :deal_docs, dependent: :destroy

  delegate :name, to: :entity, prefix: :entity
  delegate :name, to: :deal, prefix: :deal

  validates :status, :primary_amount_cents, :pre_money_valuation, presence: true
  validates :investor_id, uniqueness: { scope: :deal_id, message: "already added to this deal. Duplicate Investor." }

  STATUS = %w[Active Pending Declined].freeze

  scope :for, ->(user) { where("investors.investor_entity_id=?", user.entity_id).joins(:investor) }
  scope :not_declined, -> { where("deal_investors.status<>?", "Declined").joins(:investor) }

  before_save :set_investor_entity_id
  def set_investor_entity_id
    self.investor_entity_id = investor.investor_entity_id
    self.investor_name = investor.investor_name
  end

  after_save :create_activities_later, if: proc { |di| di.deal.started? }
  def create_activities_later
    GenerateDealActivitiesJob.perform_later(id, "DealInvestor")
  end

  def to_s
    investor_name
  end

  def short_name
    names = investor_name.split("-")
    %w[Employees Founders].include?(names[1].strip) ? names[1] : names[0]
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

      # Sometimes the activity already exists, so update it
      existing_activity = DealActivity.where(deal_id:, deal_investor_id: id)
                                      .where(template_id: template.id).first

      if existing_activity.present?
        # This happens when the deal is started and activities are added/modified later
        existing_activity.update(sequence: template.sequence, days: template.days, by_date:)
      else
        # Else create it
        DealActivity.create(deal_id:, deal_investor_id: id,
                            entity_id:, title: template.title,
                            sequence: template.sequence, days: template.days,
                            by_date:, template_id: template.id)
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

  def self.for_investor(user)
    DealInvestor
      # Ensure the access rghts for Document
      .joins(deal: :access_rights)
      .merge(AccessRight.access_filter)
      .joins(:investor)
      # Ensure that the user is an investor and tis investor has been given access rights
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
      .where("investor_accesses.entity_id = deals.entity_id")
  end
end
