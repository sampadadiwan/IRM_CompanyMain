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
  validate :valid_match?

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

  counter_culture :secondary_sale, column_name: proc { |r| r.verified ? 'allocation_amount_cents' : nil },
                                   delta_column: 'amount_cents',
                                   column_names: {
                                     ["allocations.verified = ?", true] => 'allocation_amount_cents'
                                   },
                                   execute_after_commit: true

  counter_culture :secondary_sale, column_name: proc { |r| r.verified ? 'allocation_quantity' : nil },
                                   delta_column: 'quantity',
                                   column_names: {
                                     ["allocations.verified = ?", true] => 'allocation_quantity'
                                   },
                                   execute_after_commit: true

  def self.ransackable_attributes(_auth_object = nil)
    %w[amount notes quantity created_at updated_at verified offer_id interest_id].sort.freeze
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[interest offer secondary_sale]
  end

  def folder_path
    "#{secondary_sale.folder_path}/Allocations/#{id_or_random_int}"
  end

  def to_s
    if offer && interest
      "#{offer.full_name} : #{interest.buyer_entity_name}"
    else
      ""
    end
  end

  def valid_match?
    errors.add(:offer, "sell price #{offer.price} must be less than or equal to the interest buy price #{interest.price}") if offer.price > interest.price
  end

  # offer: The offer to allocate to
  # interest: The interest to allocate to
  # allocated_quantity: The quantity to allocate
  # price: The price to allocate at
  def self.build_from(offer, interest, allocated_quantity, price)
    Rails.logger.debug { "Creating allocation between Offer ##{offer.id} and Interest ##{interest.id}" }
    allocation = Allocation.build(
      entity: offer.entity,
      secondary_sale: offer.secondary_sale,
      offer:,
      avail_offer_quantity: offer.quantity - offer.allocation_quantity,
      interest:,
      avail_interest_quantity: interest.quantity - interest.allocation_quantity,
      quantity: allocated_quantity,
      price:,
      amount_cents: allocated_quantity * price * 100
    )
    Rails.logger.debug { "Allocated #{allocated_quantity}  between Offer ##{offer.id} and Interest ##{interest.id}" }
    allocation
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
