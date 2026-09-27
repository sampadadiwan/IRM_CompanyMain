# Refuses to destroy a record while fund units are allocated against it: the units must be
# deleted first. The including model defines #allocated_fund_units (a FundUnit relation).
#
# The check is prepended so it runs before the has_many dependent: :destroy callbacks —
# otherwise the cascade could already have removed (or tripped over) the units it guards.
# It is skipped when the record is itself destroyed through a parent association: the parent
# (stakeholder, commitment, call, distribution) runs the same check over a superset of these
# units, and a Fund/Entity teardown is meant to take everything with it.
module BlocksDestroyWithFundUnits
  extend ActiveSupport::Concern

  included do
    before_destroy :ensure_no_fund_units_allocated, prepend: true
  end

  def ensure_no_fund_units_allocated
    return if destroyed_by_association
    return unless allocated_fund_units.exists?

    errors.add(:base, "Cannot delete this #{fund_units_block_label} as fund units have been allocated against it. Please delete those fund units first.")
    throw(:abort)
  end

  # Name used in the refusal message; override where the UI calls the model something else.
  def fund_units_block_label
    model_name.human.downcase
  end
end
