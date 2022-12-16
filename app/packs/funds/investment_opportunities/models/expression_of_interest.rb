class ExpressionOfInterest < ApplicationRecord
  include WithFolder

  belongs_to :entity
  belongs_to :user
  belongs_to :investor
  belongs_to :eoi_entity, class_name: "Entity"
  belongs_to :investment_opportunity
  has_rich_text :details
  serialize :properties, Hash

  has_many :documents, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :documents, allow_destroy: true

  has_many :adhaar_esigns, as: :owner
  has_many :esigns, -> { order("sequence_no asc") }, as: :owner
  has_many :signature_workflows, as: :owner
  has_many :investor_kycs, through: :investor
  belongs_to :investor_signatory, class_name: "User", optional: true

  validate :check_amount
  counter_culture :investment_opportunity,
                  column_name: proc { |o| o.approved ? 'eoi_amount_cents' : nil },
                  delta_column: 'amount_cents',
                  column_names: {
                    ["expression_of_interests.approved = ?", true] => 'eoi_amount_cents'
                  }

  monetize :amount_cents, :allocation_amount_cents,
           with_currency: ->(s) { s.investment_opportunity.currency }

  scope :approved, -> { where(approved: true) }

  def check_amount
    errors.add(:amount, "Should be greater than #{investment_opportunity.min_ticket_size}") if amount < investment_opportunity.min_ticket_size

    errors.add(:amount, "Should be less than #{investment_opportunity.fund_raise_amount}") if amount > investment_opportunity.fund_raise_amount
  end

  before_save :update_approval
  def update_approval
    self.approved = false if amount_cents_changed?
  end

  before_save :update_percentage
  def update_percentage
    self.allocation_percentage = (100.0 * allocation_amount_cents / amount_cents)
  end

  before_save :notify_approved
  def notify_approved
    ExpressionOfInterestMailer.with(id:).notify_approved.deliver_later if approved && approved_changed?
  end

  def folder_path
    "#{investment_opportunity.folder_path}/EOI/#{eoi_entity.name}-#{id}"
  end

  def document_tags
    investment_opportunity.buyer_docs_list.split(",") if investment_opportunity.buyer_docs_list.present?
  end

  ################# eSign stuff follows ###################

  def investor_signature_types; end

  def signatory_ids(type = nil)
    if @signatory_ids_map.blank?
      @signatory_ids_map = { adhaar: [], dsc: [] }
      @signatory_ids_map[:adhaar] << investor_signatory_id
      @signatory_ids_map[:adhaar].compact!
    end
    type ? @signatory_ids_map[type.to_sym] : @signatory_ids_map
  end

  def signature_link(user, document_id = nil)
    # Substitute the phone number required in the link
    EoiEsignProvider.new(self).signature_link(user, document_id)
  end

  def signature_completed(signature_type, document_id, file)
    EoiEsignProvider.new(self).signature_completed(signature_type, document_id, file)
  end
end
