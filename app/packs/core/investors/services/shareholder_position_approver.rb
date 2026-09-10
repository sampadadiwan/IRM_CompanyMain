class ShareholderPositionApprover
  # Mirrors KpiApprover: approving a staged Fully Diluted Quantity/% update overwrites the
  # matching already-approved position with the new value and discards the staging row, rather
  # than leaving two rows (one approved, one unapproved) around for the same holding.
  #
  # Each staged update is approved/rejected purely on its own merits - exactly like Quantity
  # Fully Dilluted/Quantity Actual updates - regardless of whether its Portfolio Company + Round
  # currently totals 100% for Fully Dilluted % once combined with the rest of that round's
  # positions. A round's %s only reach 100% once every pending update in it has been approved, so
  # blocking approval on that total would make it impossible to approve staged updates one at a
  # time (see ShareholderPosition.round_percentage_total for the informational total, still
  # surfaced after upload - see ImportShareholderPosition#round_percentage_total_errors_for_upload
  # - but never enforced here).
  def self.call(shareholder_position_id, user_id)
    pending = ShareholderPosition.find(shareholder_position_id)
    raise "ShareholderPosition is already approved" if pending.approved?

    existing_approved = ShareholderPosition.find_matching_approved(
      portfolio_company_id: pending.portfolio_company_id,
      investor_label: pending.investor_label,
      investor_id: pending.investor_id,
      instrument: pending.instrument,
      round_name: pending.round_name,
      position_date: pending.position_date,
      exclude_id: pending.id
    )

    result = nil

    ShareholderPosition.transaction do
      if existing_approved
        # The staged row carries both the new Fully Diluted Quantity/% and the new Quantity
        # Actuals (each defaulting to the existing approved value when that particular field
        # wasn't part of the upload that created this staging row - see
        # ImportShareholderPosition#save_row), so both apply together here, atomically, only
        # once explicitly accepted.
        existing_approved.update!(
          position_amount: pending.position_amount,
          quantity_actual: pending.quantity_actual,
          fully_diluted_percentage: pending.fully_diluted_percentage,
          category: pending.category,
          subgroup: pending.subgroup,
          approved_by_user_id: user_id,
          approved_at: Time.zone.now
        )
        pending.destroy!
        result = existing_approved
      else
        # The approved sibling this was staged against no longer exists (e.g. deleted since
        # upload) - nothing to overwrite, so just promote this row directly.
        pending.update!(status: :approved, approved_by_user_id: user_id, approved_at: Time.zone.now)
        result = pending
      end
    end

    result
  end
end
