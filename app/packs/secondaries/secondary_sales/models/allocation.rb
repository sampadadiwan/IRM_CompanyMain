class Allocation < ApplicationRecord
  include ForInvestor
  include WithFolder
  include WithCustomField
  include RansackerAmounts.new(fields: %w[amount])

  belongs_to :offer
  belongs_to :interest
  belongs_to :secondary_sale
  belongs_to :entity

  validates :quantity, presence: true

  monetize :amount_cents, with_currency: ->(s) { s.entity.currency }

  scope :verified, -> { where(verified: true) }
  scope :unverified, -> { where(verified: false) }

  counter_culture :offer, column_name: proc { |r| r.verified ? 'allocation_quantity' : nil },
                          delta_column: 'quantity',
                          column_names: {
                            ["allocations.verified = ?", true] => 'allocation_quantity'
                          },
                          execute_after_commit: true

  counter_culture :offer, column_name: proc { |r| r.verified ? 'allocation_amount_cents' : nil },
                          delta_column: 'amount_cents',
                          column_names: {
                            ["allocations.verified = ?", true] => 'allocation_amount_cents'
                          },
                          execute_after_commit: true

  counter_culture :interest, column_name: proc { |r| r.verified ? 'allocation_quantity' : nil },
                             delta_column: 'quantity',
                             column_names: {
                               ["allocations.verified = ?", true] => 'allocation_quantity'
                             },
                             execute_after_commit: true

  counter_culture :interest, column_name: proc { |r| r.verified ? 'allocation_amount_cents' : nil },
                             delta_column: 'amount_cents',
                             column_names: {
                               ["allocations.verified = ?", true] => 'allocation_amount_cents'
                             },
                             execute_after_commit: true

  def self.ransackable_attributes(_auth_object = nil)
    %w[amount notes quantity created_at updated_at verified offer_id interest_id].sort.freeze
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[interest offer secondary_sale]
  end

  def folder_path
    "#{secondary_sale.folder_path}/Allocations/#{id}"
  end

  def to_s
    "#{offer.full_name} : #{interest.buyer_entity_name}"
  end

  after_save :update_verified
  # rubocop:disable Rails/SkipsModelValidations
  def update_verified
    Allocation.transaction do
      interest.update_column(:verified, verified)
      offer.update_column(:verified, verified)
    end
  end
  # rubocop:enable Rails/SkipsModelValidations
end
