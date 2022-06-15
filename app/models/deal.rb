# == Schema Information
#
# Table name: deals
#
#  id                :integer          not null, primary key
#  entity_id         :integer          not null
#  name              :string(255)
#  amount_cents      :decimal(20, 2)   default("0.00")
#  status            :string(20)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  activity_list     :text(65535)
#  start_date        :date
#  end_date          :date
#  deleted_at        :datetime
#  impressions_count :integer          default("0")
#  archived          :boolean          default("0")
#  currency          :string(10)
#  units             :string(15)
#

class Deal < ApplicationRecord
  include Trackable
  # include ActivityTrackable
  # include Impressionable

  # encrypts :name
  monetize :amount_cents, with_model_currency: :currency

  # Make all models searchable
  update_index('deal') { self }

  belongs_to :entity
  counter_culture :entity
  delegate :name, to: :entity, prefix: :entity

  has_many :deal_investors, dependent: :destroy
  has_many :investors, through: :deal_investors

  has_many :deal_activities, dependent: :destroy

  has_many :deal_docs, dependent: :destroy
  has_many :access_rights, as: :owner, dependent: :destroy

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  validates :name, :amount_cents, :status, :currency, presence: true

  STATUS = %w[Open Closed].freeze
  ACTIVITIES = Rack::Utils.parse_nested_query(ENV["DEAL_ACTIVITIES"].tr(":", "=").tr(",", "&"))

  def create_activities
    deal_investors.each(&:create_activities)
  end

  def start_deal
    self.start_date = Time.zone.today
    save
    GenerateDealActivitiesJob.perform_later(id, "Deal")
  end

  def started?
    start_date != nil
  end

  def self.for_investor(user)
    Deal
      # Ensure the access rghts for Document
      .joins(:access_rights)
      .merge(AccessRight.access_filter)
      .joins(:investors)
      # Ensure that the user is an investor and tis investor has been given access rights
      .where("investors.investor_entity_id=?", user.entity_id)
      # Ensure this user has investor access
      .joins(entity: :investor_accesses)
      .merge(InvestorAccess.approved_for_user(user))
    # .where("investor_accesses.entity_id = deals.entity_id")
  end

  def to_s
    name
  end

  def activity_names
    DealActivity.templates(self).collect(&:title)
  end
end
