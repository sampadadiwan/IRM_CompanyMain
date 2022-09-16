# == Schema Information
#
# Table name: interests
#
#  id                      :integer          not null, primary key
#  entity_id               :integer
#  quantity                :integer
#  price                   :decimal(10, )
#  user_id                 :integer          not null
#  interest_entity_id      :integer
#  secondary_sale_id       :integer          not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  short_listed            :boolean          default("0")
#  escrow_deposited        :boolean          default("0")
#  final_price             :decimal(10, 2)   default("0.00")
#  amount_cents            :decimal(20, 2)   default("0.00")
#  allocation_quantity     :integer          default("0")
#  allocation_amount_cents :decimal(20, 2)   default("0.00")
#  allocation_percentage   :decimal(5, 2)    default("0.00")
#  finalized               :boolean          default("0")
#  buyer_entity_name       :string(100)
#  address                 :text(65535)
#  contact_name            :string(50)
#  email                   :string(40)
#  PAN                     :string(15)
#  final_agreement         :boolean          default("0")
#  properties              :text(65535)
#  form_type_id            :integer
#  offer_quantity          :integer          default("0")
#  verified                :boolean          default("0")
#  comments                :text(65535)
#  spa_data                :text(65535)
#

class Interest < ApplicationRecord
  include WithFolder

  belongs_to :user
  belongs_to :secondary_sale, touch: true
  belongs_to :interest_entity, class_name: "Entity"
  belongs_to :entity, touch: true

  has_many :offers, dependent: :destroy
  has_many :tasks, as: :owner, dependent: :destroy
  has_many :messages, as: :owner, dependent: :destroy

  include FileUploader::Attachment(:spa)
  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  has_rich_text :details

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  validates :quantity, comparison: { less_than_or_equal_to: :display_quantity }
  validates :price, comparison: { less_than_or_equal_to: :max_price }, if: -> { secondary_sale.price_type == 'Price Range' }
  validates :price, comparison: { greater_than_or_equal_to: :min_price }, if: -> { secondary_sale.price_type == 'Price Range' }

  validates :price, comparison: { equal_to: :final_price }, if: -> { secondary_sale.price_type == 'Fixed Price' }

  delegate :display_quantity, to: :secondary_sale
  delegate :min_price, to: :secondary_sale
  delegate :max_price, to: :secondary_sale
  delegate :final_price, to: :secondary_sale
  delegate :email, to: :user, prefix: true

  scope :short_listed, -> { where(short_listed: true) }
  scope :escrow_deposited, -> { where(escrow_deposited: true) }
  scope :priced_above, ->(price) { where("price >= ?", price) }
  scope :eligible, ->(secondary_sale) { short_listed.priced_above(secondary_sale.final_price) }

  before_validation :set_defaults

  validates :quantity, :price, presence: true
  validates :buyer_entity_name, :address, :PAN, :contact_name, :email, presence: true, if: proc { |i| i.secondary_sale.finalized }

  after_create :notify_interest
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
    InterestMailer.with(interest_id: id).notify_interest.deliver_later unless secondary_sale.no_interest_emails
  end

  def notify_shortlist
    InterestMailer.with(interest_id: id).notify_shortlist.deliver_later if short_listed && saved_change_to_short_listed? && !secondary_sale.no_interest_emails
  end

  def notify_finalized
    InterestMailer.with(interest_id: id).notify_finalized.deliver_later if finalized && saved_change_to_finalized? && !secondary_sale.no_interest_emails
  end

  def set_defaults
    self.interest_entity_id ||= user.entity_id
    self.entity_id ||= secondary_sale.entity_id
    self.amount_cents = quantity * final_price * 100 if final_price.positive?
    self.allocation_amount_cents = allocation_quantity * final_price * 100 if final_price.positive?
  end

  def allocation_delta
    allocation_quantity - offer_quantity
  end

  def setup_folder_details
    parent_folder = secondary_sale.document_folder.folders.where(name: "Interests").first
    setup_folder(parent_folder, interest_entity.name, [])
  end

  def offer_amount
    Money.new(offer_quantity * final_price * 100, entity.currency)
  end

  def document_list
    secondary_sale.buyer_doc_list&.split(",")
  end
end
