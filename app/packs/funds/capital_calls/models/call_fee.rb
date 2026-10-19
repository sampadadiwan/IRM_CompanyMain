class CallFee < ApplicationRecord
  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :capital_call
  attr_readonly :capital_call_id # never moves to another call (funds_api_security_policy_plan.md, B)
  validates :name, :start_date, :end_date, :fee_type, presence: true
  validates :name, length: { maximum: 50 }
  validates :fee_type, length: { maximum: 20 }

  # `notes` holds a Ruby fee formula that is eval-ed in #calculate_formula. Reject any
  # code-execution constructs at write time (execution-time is guarded again via safe_eval!).
  validate :notes_kosher?
  def notes_kosher?
    errors.add(:notes, "You cannot do CRUD or system operations in a fee formula") if notes.present? && notes.downcase.match?(SAFE_EVAL_REGEX)
  end

  NESTED_ATTRIBUTES = %i[id name start_date end_date fee_type notes _destroy].freeze
  NESTED_ATTRIBUTES_WITH_FORMULA = %i[id name start_date end_date fee_type notes _destroy formula].freeze

  before_validation :setup_entity

  scope :formulas, -> { where(formula: true) }

  def setup_entity
    self.entity_id = capital_call.entity_id
    self.fund_id = capital_call.fund_id
  end

  # Raised when a fee formula blows up while being evaluated for a remittance. Wraps the
  # original error (kept as #cause) with the fee and folio, so whoever runs the call knows
  # which record to fix, e.g. a commitment with no unit type hitting fund_unit_setting.setup_fee.
  class FormulaError < StandardError; end

  # This is used to calculate the fee based on the formula in the notes
  # Should return the amount in cents
  def calculate_formula(capital_remittance)
    capital_call = self.capital_call
    capital_commitment = capital_remittance.capital_commitment
    # Guard at the eval boundary so bypasses of the notes_kosher? validation (update_column,
    # imports, seeds) still cannot execute arbitrary code.
    eval(ApplicationRecord.safe_eval!(notes, context: "CallFee##{id} notes"), binding)
  rescue ApplicationRecord::UnsafeEvalError
    # A blocked formula is a security refusal, not a data problem - let it through unchanged
    raise
  rescue StandardError, SyntaxError => e
    # SyntaxError is not a StandardError, so list it explicitly to cover a mistyped formula.
    # Re-raising inside rescue sets the original error as #cause, keeping the eval backtrace.
    raise FormulaError, "Fee formula '#{name}' (CallFee##{id}) failed for commitment " \
                        "#{capital_commitment&.id} (#{capital_commitment&.investor_name}, folio " \
                        "#{capital_commitment&.folio_id}): #{e.class}: #{e.message}"
  end

  def label
    "#{name} (#{fee_type}): #{start_date} to #{end_date}"
  end
end
