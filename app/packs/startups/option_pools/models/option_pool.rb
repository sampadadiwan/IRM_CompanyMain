class OptionPool < ApplicationRecord
  include Trackable
  include WithFolder
  audited

  belongs_to :entity
  belongs_to :funding_round, optional: true
  has_many :holdings, inverse_of: :option_pool, dependent: :destroy
  has_many :excercises, dependent: :destroy

  has_many :vesting_schedules, inverse_of: :option_pool, dependent: :destroy
  accepts_nested_attributes_for :vesting_schedules, reject_if: :all_blank, allow_destroy: true

  include FileUploader::Attachment(:certificate_signature)
  include FileUploader::Attachment(:grant_letter)

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

  def folder_path
    "/OptionPools/#{name.delete('/')}"
  end
end
