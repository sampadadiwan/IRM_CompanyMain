class RatioFormula < ApplicationRecord
  extend Enumerize
  include ForInvestor

  acts_as_paranoid

  # account_entry_names is a JSON array; ratio is a single string value
  # serialize :account_entry_names, type: Array

  belongs_to :entity
  belongs_to :fund
  belongs_to :import_upload, optional: true

  delegate :entity_id, to: :fund, allow_nil: true

  enumerize :level, in: %w[Fund Folio PortfolioCompany], default: 'Fund'
  enumerize :action, in: %w[add_cashflow reduce_cashflow add_numerator reduce_numerator add_denominator reduce_denominator], default: 'add_cashflow'
  enumerize :period, in: %w[as_on all], default: 'as_on'

  validates :level, :action, :period, presence: true
  validates :ratio, presence: true
  validates :account_entry_names, presence: true

  before_validation :normalize_account_entry_names

  def to_s
    "#{level} #{action} for #{account_entry_names.join(', ')}"
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[level action period created_at updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund entity]
  end

  private

  def normalize_account_entry_names
    self.account_entry_names = if account_entry_names.is_a?(String)
                                 account_entry_names.split(',').map(&:strip).compact_blank
                               else
                                 Array(account_entry_names).compact_blank
                               end
  end
end
