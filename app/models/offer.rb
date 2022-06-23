# == Schema Information
#
# Table name: offers
#
#  id                      :integer          not null, primary key
#  user_id                 :integer          not null
#  entity_id               :integer          not null
#  secondary_sale_id       :integer          not null
#  quantity                :integer          default("0")
#  percentage              :decimal(10, )    default("0")
#  notes                   :text(65535)
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  holding_id              :integer          not null
#  approved                :boolean          default("0")
#  granted_by_user_id      :integer
#  investor_id             :integer          not null
#  offer_type              :string(15)
#  first_name              :string(255)
#  middle_name             :string(255)
#  last_name               :string(255)
#  PAN                     :string(15)
#  address                 :text(65535)
#  bank_account_number     :string(40)
#  bank_name               :string(50)
#  bank_routing_info       :text(65535)
#  buyer_confirmation      :string(10)
#  buyer_notes             :text(65535)
#  buyer_id                :integer
#  final_price             :decimal(10, 2)   default("0.00")
#  amount_cents            :decimal(20, 2)   default("0.00")
#  allocation_quantity     :integer          default("0")
#  allocation_amount_cents :decimal(20, 2)   default("0.00")
#  allocation_percentage   :decimal(5, 2)    default("0.00")
#

class Offer < ApplicationRecord
  include WithFolder

  belongs_to :user
  belongs_to :investor
  belongs_to :entity
  belongs_to :secondary_sale

  counter_culture :interest,
                  column_name: proc { |o| o.approved ? 'offer_quantity' : nil },
                  delta_column: 'quantity'

  counter_culture :secondary_sale,
                  column_name: proc { |o| o.approved ? 'total_offered_quantity' : nil },
                  delta_column: 'quantity'

  counter_culture :secondary_sale,
                  column_name: proc { |o| o.approved ? 'total_offered_amount_cents' : nil },
                  delta_column: 'amount_cents'

  # This is the holding owned by the user which is offered out
  belongs_to :holding
  # This is the buyer against which this sellers quantity is matched
  belongs_to :interest, optional: true

  belongs_to :granter, class_name: "User", foreign_key: :granted_by_user_id, optional: true
  belongs_to :buyer, class_name: "Entity", optional: true

  has_many :messages, as: :owner, dependent: :destroy

  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true
  include FileUploader::Attachment(:signature)
  include FileUploader::Attachment(:spa)
  include FileUploader::Attachment(:id_proof)
  include FileUploader::Attachment(:address_proof)

  # Customize form
  belongs_to :form_type, optional: true
  serialize :properties, Hash

  delegate :quantity, to: :holding, prefix: :holding

  scope :approved, -> { where(approved: true) }
  scope :pending_approval, -> { where(approved: false) }
  scope :verified, -> { where(verified: true) }
  scope :pending_verification, -> { where(verified: false) }

  validates :first_name, :last_name, :address, :PAN, :bank_account_number, :bank_name, :bank_routing_info, presence: true, if: proc { |o| o.secondary_sale.finalized }

  validates :address_proof, :id_proof, :signature, presence: true if Rails.env.production?

  validate :check_quantity
  validate :sale_active, on: :create

  monetize :amount_cents, :allocation_amount_cents, with_currency: ->(o) { o.entity.currency }

  BUYER_STATUS = %w[Confirmed Rejected].freeze

  # def already_offered
  #   errors.add(:secondary_sale, ": An existing offer from this user already exists. Pl modify or delete that one.") if secondary_sale.offers.where(user_id:, holding_id:).first.present?
  # end

  def sale_active
    errors.add(:secondary_sale, ": Is not active.") unless secondary_sale.active?
  end

  before_save :set_defaults
  def set_defaults
    self.percentage = (100.0 * quantity) / total_holdings_quantity

    self.investor_id = holding.investor_id
    self.user_id = holding.user_id if holding.user_id
    self.entity_id = holding.entity_id

    self.approved = false if quantity_changed?

    self.amount_cents = quantity * final_price * 100 if final_price.positive?
    self.allocation_amount_cents = allocation_quantity * final_price * 100 if final_price.positive?
  end

  def check_quantity
    # holding users total holding amount
    total_quantity = total_holdings_quantity
    Rails.logger.debug { "total_holdings_quantity: #{total_quantity}" }

    # already offered amount
    already_offered = secondary_sale.offers.where(user_id: holding.user_id).sum(:quantity)
    Rails.logger.debug { "already_offered: #{already_offered}" }

    total_offered_quantity = already_offered + quantity
    total_offered_quantity -= quantity_was unless new_record?
    Rails.logger.debug { "total_offered_quantity: #{total_offered_quantity}" }

    # errors.add(:quantity, "Total offered quantity #{total_offered_quantity} is > allowed_quantity #{allowed_quantity}") if total_offered_quantity > allowed_quantity
    errors.add(:quantity, "Total offered quantity #{total_offered_quantity} is > total holdings #{total_quantity}") if total_offered_quantity > total_quantity
  end

  def total_holdings_quantity
    holding.user ? holding.user.holdings.eq_and_pref.sum(:quantity) : holding.investor.holdings.eq_and_pref.sum(:quantity)
  end

  def allowed_quantity
    # holding users total holding amount
    (total_holdings_quantity * secondary_sale.percent_allowed / 100).round
  end

  include Rails.application.routes.url_helpers
  include ActionView::Helpers::UrlHelper
  include ActionView::Helpers

  def generate_spa_pdf(cleanup: true)
    if secondary_sale.spa_template.present?

      # Build a template out of the SPA template
      offer = self
      template = HTMLEntities.new.decode(secondary_sale.spa_template.body.to_html)
      html = ERB.new(template).result(binding)

      # Create a PDF out of it
      pdf = WickedPdf.new.pdf_from_string(html)
      file_name = "Offer_#{id}_SPA.pdf"
      save_path = Rails.root.join('tmp', file_name)
      File.open(save_path, 'wb') do |file|
        file << pdf
      end

      # Attach it to the offer
      spa.attach(io: File.open("tmp/#{file_name}"), filename: "file_name-#{Time.zone.now.strftime('%F %T')}")

      # Cleanup
      File.delete("tmp/#{file_name}") if File.exist?("tmp/#{file_name}") && cleanup

    end
  end

  def break_offer(allocation_qtys)
    Rails.logger.debug { "breaking offer #{id} into #{allocation_qtys} pieces" }

    # Duplicate the offer
    dup_offers = [self]
    (1..allocation_qtys.length - 1).each do |_i|
      dup_offers << dup
    end

    Offer.transaction do
      # Update the peices with the quantites
      dup_offers.each_with_index do |dup_offer, i|
        diff =  dup_offer.allocation_quantity - allocation_qtys[i]
        dup_offer.allocation_quantity = allocation_qtys[i]
        dup_offer.quantity -= diff
        dup_offer.save!
      end
    end
  end

  def notify_approval
    OfferMailer.with(offer_id: id).notify_approval.deliver_later
  end
end
