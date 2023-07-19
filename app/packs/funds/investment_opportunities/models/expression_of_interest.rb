class ExpressionOfInterest < ApplicationRecord
  include WithFolder
  include ForInvestor

  belongs_to :entity
  belongs_to :user
  belongs_to :investor
  belongs_to :eoi_entity, class_name: "Entity"
  belongs_to :investment_opportunity
  has_rich_text :details
  serialize :properties, Hash

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
    investor.approved_users.each do |user|
      ExpressionOfInterestNotification.with(entity_id:, expression_of_interest_id: id).deliver_later(user) if approved && approved_changed?
    end
  end

  def folder_path
    "#{investment_opportunity.folder_path}/EOI/#{eoi_entity.name.delete('/')}"
  end

  def document_list
    investment_opportunity.buyer_docs_list.split(",") if investment_opportunity.buyer_docs_list.present?
  end

  ################# eSign stuff follows ###################
end
