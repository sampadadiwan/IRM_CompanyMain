class RatioFormula < ApplicationRecord
  extend Enumerize
  include ForInvestor

  acts_as_paranoid

  # In MySQL JSON columns are returned as arrays/hashes directly
  # But we can still ensure they are treated as arrays in the app
  # serialize :ratios, type: Array
  # serialize :account_entry_names, type: Array

  belongs_to :entity
  belongs_to :fund
  belongs_to :import_upload, optional: true

  delegate :entity_id, to: :fund, allow_nil: true

  enumerize :level, in: %w[Fund Folio PortfolioCompany], default: 'Fund'
  enumerize :action, in: %w[add_cashflow reduce_cashflow add_numerator reduce_numerator add_denominator reduce_denominator], default: 'add_cashflow'
  enumerize :period, in: %w[as_on all], default: 'as_on'

  validates :level, :action, :period, presence: true
  validates :ratios, presence: true
  validates :account_entry_names, presence: true

  # Ensure ratios and account_entry_names are handled as arrays if they are strings
  before_validation :normalize_arrays

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

  def normalize_arrays
    self.ratios = if ratios.is_a?(String)
                    ratios.split(',').map(&:strip).reject(&:blank?)
                  else
                    Array(ratios).reject(&:blank?)
                  end

    self.account_entry_names = if account_entry_names.is_a?(String)
                                 account_entry_names.split(',').map(&:strip).reject(&:blank?)
                               else
                                 Array(account_entry_names).reject(&:blank?)
                               end
  end
end
