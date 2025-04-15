class FundBase < ApplicationRecord
  self.abstract_class = true
  acts_as_favoritable
  include ForInvestor
  include WithCustomField
  include RansackerAmounts.new(fields: %w[collected_amount committed_amount call_amount distribution_amount])

  CATEGORIES = ["Category I", "Category II", "Category III"].freeze
  REMITTANCE_GENERATION_BASIS = ["Folio Amount", "Fund Amount"].freeze

  monetize  :tracking_committed_amount_cents, :tracking_call_amount_cents,
            :tracking_collected_amount_cents, :tracking_distribution_amount_cents,
            with_currency: ->(f) { f.tracking_currency.presence || f.currency }

  monetize :call_amount_cents, :committed_amount_cents, :target_committed_amount_cents,
           :collected_amount_cents, :distribution_amount_cents, :total_units_premium_cents,
           with_currency: ->(f) { f.currency }

  def pending_call_amount
    call_amount - collected_amount
  end

  def has_tracking_currency?
    tracking_currency.present? && tracking_currency != currency
  end

  def unit_types_list
    unit_types&.split(",")&.map(&:strip)
  end

  def to_s
    name
  end

  def get_lps_emails
    investors.joins(:investor_accesses).where('investor_accesses.approved = true').pluck('investor_accesses.email')
  end

  TEMPLATE_TAGS = ["Commitment Template", "Call Template", "SOA Template", "Distribution Template"].freeze
  def document_tags
    TEMPLATE_TAGS
  end

  def signature_labels
    ["Investor Signatories", "Fund Signatories", "Other"]
  end

  def fund_signatories
    esign_emails&.split(",")&.map(&:strip)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[call_amount capital_commitments_count category collected_amount committed_amount currency distribution_amount first_close_date last_close_date name start_date tag_list unit_types snapshot_date].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
