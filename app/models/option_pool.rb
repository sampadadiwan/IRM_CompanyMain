# == Schema Information
#
# Table name: option_pools
#
#  id                      :integer          not null, primary key
#  name                    :string(255)
#  start_date              :date
#  number_of_options       :integer          default("0")
#  excercise_price_cents   :decimal(20, 2)   default("0.00")
#  excercise_period_months :integer          default("0")
#  entity_id               :integer          not null
#  funding_round_id        :integer
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  allocated_quantity      :integer          default("0")
#  excercised_quantity     :integer          default("0")
#  vested_quantity         :integer          default("0")
#  lapsed_quantity         :integer          default("0")
#  approved                :boolean          default("0")
#

class OptionPool < ApplicationRecord
  include WithFolder
  audited

  belongs_to :entity
  belongs_to :funding_round, optional: true
  has_many :holdings, inverse_of: :option_pool, dependent: :destroy
  has_many :excercises, dependent: :destroy

  has_many :vesting_schedules, inverse_of: :option_pool, dependent: :destroy
  accepts_nested_attributes_for :vesting_schedules, reject_if: :all_blank, allow_destroy: true

  has_many :folders, as: :owner, dependent: :destroy
  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true
  include FileUploader::Attachment(:certificate_signature)

  has_rich_text :details

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  validates :name, :start_date, :number_of_options, :excercise_price, presence: true
  validates :number_of_options, :excercise_price, numericality: { greater_than: 0 }

  validate :check_vesting_schedules

  monetize :excercise_price_cents, with_currency: ->(i) { i.entity.currency }

  scope :approved, -> { where(approved: true) }
  scope :manual_vesting, -> { where(manual_vesting: true) }
  scope :not_manual_vesting, -> { where(manual_vesting: false) }

  def check_vesting_schedules
    unless manual_vesting
      total_percent = vesting_schedules.inject(0) { |sum, e| sum + e.vesting_percent }
      logger.debug vesting_schedules.to_json
      errors.add(:vesting_schedules, "Total percentage should be 100%") if total_percent != 100
    end
  end

  def get_allowed_percentage(grant_date)
    Rails.logger.debug "called get_allowed_percentage"
    # Find the percentage that can be excercised
    schedules = vesting_schedules.order(months_from_grant: :asc)
    allowed_percentage = 0

    schedules.each do |sched|
      Rails.logger.debug { "Grant date: #{grant_date}, Schedule months_from_grant: #{sched.months_from_grant}" }
      allowed_percentage += sched.vesting_percent if grant_date + sched.months_from_grant.months <= Time.zone.now
    end

    logger.debug "Option Pool allowed_percentage: #{allowed_percentage}"
    allowed_percentage
  end

  def available_quantity
    number_of_options - allocated_quantity
  end

  def trust_quantity
    number_of_options - excercised_quantity
  end

  def setup_folder_details
    parent_folder = Folder.where(entity_id:, level: 1, name: self.class.name.pluralize.titleize).first
    setup_folder(parent_folder, name, ["Excerices"])
  end
end
