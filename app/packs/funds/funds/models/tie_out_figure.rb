# The fund's own figure for one number, typed in while reviewing an allocation run, so it can
# be compared with what the allocation engine produced. See
# docs/modules/allocation/allocation_run_review_proposals.md (proposals 2 and 3).
#
# Funds keep their books in a spreadsheet outside CapHive and review a run by tying our numbers
# back to theirs: first the fund totals, then a few folios. A figure records their side of that
# comparison and who entered it, which is what makes the review evidence of a sign-off rather
# than a glance.
#
# Keyed to (fund, as_of_date, folio, name) and deliberately NOT to the allocation run: a re-run
# of the same period creates a new AllocationRun and hard-deletes the previous attempt's
# entries, so a figure tied to a run would have to be retyped after every re-run. The fund's
# own number belongs to the period, not to our attempt at it.
class TieOutFigure < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :user
  # nil means the fund total for this name; set means one folio's figure.
  belongs_to :capital_commitment, optional: true

  monetize :amount_cents, with_currency: ->(figure) { figure.fund.currency }

  validates :name, presence: true, length: { maximum: 125 }
  validates :entry_type, length: { maximum: 60 }
  validates :as_of_date, presence: true
  validates :amount_cents, presence: true, numericality: true
  # One figure per number per date. Enforced here rather than by a unique index because MySQL
  # treats NULL capital_commitment_ids as distinct from each other, so an index would not hold
  # for fund totals — which are exactly the rows the totals sheet writes.
  validates :name, uniqueness: { scope: %i[fund_id as_of_date capital_commitment_id entry_type],
                                 message: "already has a figure for this date" }

  # Fund totals for one run's date — what the totals sheet reads.
  scope :fund_totals, -> { where(capital_commitment_id: nil) }
  scope :as_of, ->(date) { where(as_of_date: date) }

  # Key a figure is looked up and indexed by, so the totals sheet can match figures to rows
  # without a query per row. Entry type is part of the key because two entries may share a name
  # and differ only by type.
  # @return [Array(String, String)]
  def row_key = [name, entry_type.to_s]

  def self.row_key(name, entry_type) = [name.to_s, entry_type.to_s]

  # Amounts are typed by a person in major units, the way their spreadsheet shows them —
  # "8,10,000" or "810000.50" or "(3,500)" for a negative. Returns nil when the text holds no
  # number at all, which the caller treats as "clear this figure" rather than as zero.
  # @param text [String, nil]
  # @return [BigDecimal, nil] cents
  def self.parse_amount_cents(text)
    cleaned = text.to_s.strip
    return nil if cleaned.blank?

    negative = cleaned.start_with?("(") && cleaned.end_with?(")")
    cleaned = cleaned.tr("()", "") if negative
    # Currency symbols, spaces and thousands separators — whatever their sheet pasted in.
    cleaned = cleaned.gsub(/[^\d.-]/, "")
    return nil if cleaned.blank? || cleaned == "-" || cleaned == "."

    amount = BigDecimal(cleaned)
    amount = -amount if negative
    (amount * 100).round(8)
  rescue ArgumentError
    nil
  end
end
