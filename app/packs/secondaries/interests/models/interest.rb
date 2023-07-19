class Interest < ApplicationRecord
  include Trackable
  include WithFolder
  include SaleChildrenScopes
  include WithCustomField
  include ForInvestor

  belongs_to :user
  belongs_to :investor
  belongs_to :final_agreement_user, class_name: "User", optional: true
  belongs_to :secondary_sale, touch: true
  belongs_to :interest_entity, class_name: "Entity"
  belongs_to :entity, touch: true

  has_many :offers, dependent: :destroy
  has_many :tasks, as: :owner, dependent: :destroy
  has_many :messages, as: :owner, dependent: :destroy

  include FileUploader::Attachment(:spa)
  include FileUploader::Attachment(:signature)

  has_rich_text :details

  validates :quantity, comparison: { less_than_or_equal_to: :display_quantity }
  validates :price, comparison: { less_than_or_equal_to: :max_price }, if: -> { secondary_sale.price_type == 'Price Range' }
  validates :price, comparison: { greater_than_or_equal_to: :min_price }, if: -> { secondary_sale.price_type == 'Price Range' }

  validates :price, comparison: { equal_to: :final_price }, if: -> { secondary_sale.price_type == 'Fixed Price' }

  validates :buyer_entity_name, length: { maximum: 100 }
  validates :contact_name, length: { maximum: 50 }
  validates :email, length: { maximum: 100 }
  validates :PAN, length: { maximum: 15 }
  validates :demat, :city, :ifsc_code, length: { maximum: 20 }
  validates :bank_account_number, length: { maximum: 15 }

  delegate :display_quantity, to: :secondary_sale
  delegate :min_price, to: :secondary_sale
  delegate :max_price, to: :secondary_sale
  delegate :final_price, to: :secondary_sale
  delegate :email, to: :user, prefix: true

  scope :cmv, ->(val) { where(custom_matching_vals: val) }
  scope :short_listed, -> { where(short_listed: true) }
  scope :not_final_agreement, -> { where(final_agreement: false) }
  scope :escrow_deposited, -> { where(escrow_deposited: true) }
  scope :priced_above, ->(price) { where("price >= ?", price) }
  scope :eligible, ->(secondary_sale) { short_listed.priced_above(secondary_sale.final_price) }

  before_validation :set_defaults

  validates :quantity, :price, presence: true
  validates :buyer_entity_name, :address, :city, :PAN, :contact_name, :email, presence: true, if: proc { |i| i.secondary_sale.finalized }

  after_create_commit :notify_interest
  after_save :notify_shortlist, if: :short_listed
  after_save :notify_finalized, if: :finalized

  monetize :amount_cents, :allocation_amount_cents, with_currency: ->(i) { i.entity.currency }

  counter_culture :secondary_sale,
                  column_name: proc { |o| o.short_listed ? 'total_interest_quantity' : nil },
                  delta_column: 'quantity'

  counter_culture :secondary_sale,
                  column_name: proc { |o| o.short_listed ? 'total_interest_amount_cents' : nil },
                  delta_column: 'amount_cents'

  def notify_interest
    unless secondary_sale.no_interest_emails
      investor.approved_users.each do |user|
        InterestNotification.with(entity_id:, interest_id: id, email_method: :notify_interest, msg: "Interest received for #{secondary_sale.name}").deliver_later(user)
      end
    end
  end

  def notify_shortlist
    if short_listed && saved_change_to_short_listed? && !secondary_sale.no_interest_emails
      investor.approved_users.each do |user|
        InterestNotification.with(entity_id:, interest_id: id, email_method: :notify_shortlist, msg: "Interest shortlisted for #{secondary_sale.name}").deliver_later(user)
      end
    end
  end

  after_save :notify_accept_spa, if: proc { |o| o.final_agreement && o.saved_change_to_final_agreement? }
  def notify_accept_spa
    unless secondary_sale.no_interest_emails
      investor.approved_users.each do |user|
        InterestNotification.with(entity_id:, interest_id: id, email_method: :notify_accept_spa, msg: "SPA confirmation received for #{secondary_sale.name}").deliver_later(user)
      end
    end
  end

  def notify_finalized
    if finalized && saved_change_to_finalized? && !secondary_sale.no_interest_emails
      investor.approved_users.each do |user|
        InterestNotification.with(entity_id:, interest_id: id, email_method: :notify_finalized, msg: "Interest finalized for #{secondary_sale.name}").deliver_later(user)
      end
    end
  end

  def to_s
    "#{investor.investor_name} - #{quantity} shares @ #{price}"
  end

  def set_defaults
    self.entity_id ||= secondary_sale.entity_id
    self.investor ||= entity.investors.where(investor_entity_id: user.entity_id).first
    self.interest_entity_id ||= investor.investor_entity_id

    self.amount_cents = quantity * final_price * 100 if final_price.positive?
    self.allocation_amount_cents = allocation_quantity * final_price * 100 if final_price.positive?

    self.custom_matching_vals = ""
    if secondary_sale.custom_matching_fields.present?
      secondary_sale.custom_matching_fields.split(",").each do |cmf|
        # For each custom matching field, we extract the value from the offers
        val = eval <<-RUBY, binding, __FILE__, __LINE__ + 1
              self.#{cmf} # Evaluate the custom_matching_fields
        RUBY
        self.custom_matching_vals += "#{val}_"
      end
    else
      self.custom_matching_vals = ""
    end
  end

  def allocation_delta
    allocation_quantity - offer_quantity
  end

  def folder_path
    "#{secondary_sale.folder_path}/Interests/#{interest_entity.name.delete('/')}-#{id}"
  end

  def offer_amount
    Money.new(offer_quantity * final_price * 100, entity.currency)
  end

  def document_list
    secondary_sale.buyer_doc_list&.split(",")
  end

  def aquirer_name
    buyer_entity_name.presence || interest_entity.name
  end

  def notification_emails
    # Check if this is by an investor - if so send to all in investor access
    @investor ||= Investor.where(entity_id:, investor_entity_id: interest_entity_id).first
    if @investor
      @investor.emails
    else
      # Else send it to the interest user only
      [user.email]
    end
  end
end
