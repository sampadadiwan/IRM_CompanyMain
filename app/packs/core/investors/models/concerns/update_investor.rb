module UpdateInvestor
  extend ActiveSupport::Concern

  included do
    after_commit :update_association_name, only: :update?
    before_validation :reassign_entity_on_email_change, if: :persisted?
    # Primary email is the stakeholder's identity anchor: once users are linked
    # (via investor_accesses), changing it would repoint the investor_entity and
    # strand those users on the old entity. Block the change instead.
    validate :primary_email_locked_when_users_exist, if: :persisted?

    # Be very careful using this method, it is used to move all investors associations to a new investor
    def self.merge(old_investor, new_investor, allow_cross_entity: false)
      raise "Cannot merge investors from different entities" if !allow_cross_entity && old_investor.entity_id != new_investor.entity_id

      # Fund related stuff
      old_investor.investor_kycs.update_all(investor_name: new_investor.investor_name, investor_id: new_investor.id)
      old_investor.capital_commitments.update_all(investor_name: new_investor.investor_name, investor_id: new_investor.id)
      old_investor.expression_of_interests.update_all(investor_id: new_investor.id)

      old_investor.capital_distribution_payments.update_all(investor_name: new_investor.investor_name, investor_id: new_investor.id)
      old_investor.capital_remittances.update_all(investor_name: new_investor.investor_name, investor_id: new_investor.id)
      old_investor.aggregate_portfolio_investments.update_all(portfolio_company_name: new_investor.investor_name, portfolio_company_id: new_investor.id)
      old_investor.portfolio_investments.update_all(portfolio_company_name: new_investor.investor_name, portfolio_company_id: new_investor.id)

      old_investor.fund_units.update_all(investor_id: new_investor.id)
      old_investor.aml_reports.update_all(investor_id: new_investor.id)
      old_investor.approval_responses.update_all(investor_id: new_investor.id)

      # Startup
      old_investor.investments.update_all(portfolio_company_id: new_investor.id)
      old_investor.offers.update_all(investor_id: new_investor.id)

      # Other stuff
      # old_investor.messages.update_all(investor_id: new_investor.id)
      old_investor.notes.update_all(investor_id: new_investor.id)
      old_investor.deal_investors.update_all(investor_name: new_investor.investor_name, investor_id: new_investor.id, investor_entity_id: new_investor.investor_entity_id)

      # Folder names need to be updates
      new_investor.update_folder_names

      # Also move the access, rights and users
      old_investor.investor_accesses.update_all(investor_id: new_investor.id, investor_entity_id: new_investor.investor_entity_id)

      # We need to be careful about access rights, cannot blindly update
      old_investor.access_rights.each do |old_ar|
        if old_ar.owner.access_rights.where(access_to_investor_id: new_investor.id).any?
          # The new investor already has access, so we can delete the old one
          old_ar.destroy
        else
          # The new investor does not have access, so we can update the old one
          old_ar.update_column(:access_to_investor_id, new_investor.id)
        end
      end

      users = old_investor.investor_entity&.employees
      user_ids = users&.pluck(:id) || []
      Rails.logger.debug { "Found Users to update: #{user_ids} for old investor entity_id: #{old_investor.investor_entity_id}." }
      if user_ids.present?
        # Update entity_id for all users
        users.update_all(entity_id: new_investor.investor_entity_id)
        # reset_access_rights_cache loop removed: live DB queries make per-user cache
        # invalidation unnecessary after a merge.
      end

      old_investor.update_column(:investor_name, "#{old_investor.investor_name} - Defunct/Inactive")
    end
  end

  # Some associations cache the investor_name, so update that if the name changes here.

  def update_association_name
    # If the investor name changes, we need to update all the associations
    if saved_change_to_investor_name?
      investor_kycs.update_all(investor_name:)
      capital_commitments.update_all(investor_name:)
      capital_distribution_payments.update_all(investor_name:)
      capital_remittances.update_all(investor_name:)
      aggregate_portfolio_investments.update_all(portfolio_company_name: investor_name)
      portfolio_investments.update_all(portfolio_company_name: investor_name)
      deal_investors.update_all(investor_name:)
      update_folder_names

      # Check if investor entity has only one investor, and we changed its name
      if sole_investor?
        # If so also update the entity name
        # investor_entity.update(name: investor_name)
      end
    end

    # After email-based entity reassignment (reassign_entity_on_email_change) the
    # new entity already carries the matching email, so this update_column is a
    # no-op (setting the same value). Kept for the edge case where the entity's
    # email was blank and the investor is the sole stakeholder for that entity.
    # If the primary email changes, we need to update the investor_entity as well
    investor_entity.update_column(:primary_email, primary_email) if saved_change_to_primary_email? && (sole_investor? || investor_entity.primary_email.blank?)
  end

  # Some folder names have the investor name in it, so if that changes, we need to change folder names
  def update_folder_names
    capital_commitments.each do |cc|
      next unless cc.document_folder

      cc.document_folder.name = cc.folder_path.split("/")[-1]
      cc.document_folder.set_defaults
      cc.document_folder.save
    end
    capital_remittances.each do |cc|
      next unless cc.document_folder

      cc.document_folder.name = cc.folder_path.split("/")[-1]
      cc.document_folder.set_defaults
      cc.document_folder.save
    end
    capital_distribution_payments.each do |cc|
      next unless cc.document_folder

      cc.document_folder.name = cc.folder_path.split("/")[-1]
      cc.document_folder.set_defaults
      cc.document_folder.save
    end
    investor_kycs.each do |kyc|
      next unless kyc.document_folder

      kyc.document_folder.name = kyc.folder_path.split("/")[-1]
      kyc.document_folder.set_defaults
      kyc.document_folder.save
    end
  end

  # When primary_email changes on an existing investor, find or create an Entity
  # with the new email and reassign investor_entity_id.
  #
  # Mirrors the new-record behavior in #update_name (investor.rb)
  # which does the same lookup/creation during initial investor creation.
  #
  # The reassignment triggers the existing after_commit :change_investor_entity
  # callback which cascades to deal_investors, investor_accesses, and
  # investor_notice_entries that reference the old entity.
  #
  # Edge cases:
  # - No entity with the new email → creates one with entity_type: "Investor",
  #   copies permissions from the fund via setup_permissions
  # - New email matches same entity already assigned → early return, no-op
  # - New email matches entity already used by another investor in same fund
  #   → caught by validates :investor_entity_id, uniqueness: { scope: :entity_id }
  #   on the Investor model
  # - Email cleared to blank → early return, no reassignment
  # - Stakeholder has users → early return; primary_email_locked_when_users_exist
  #   rejects the save with a validation error
  def reassign_entity_on_email_change
    return if primary_email.blank? || !primary_email_changed?
    # Blocked by primary_email_locked_when_users_exist — bail out before the
    # entity lookup so a doomed save doesn't create an orphan Entity as a side
    # effect (this callback runs before validations get a chance to fail).
    return if primary_email_locked?

    new_entity = with_entity_email_lock(primary_email.strip) { find_or_build_investor_entity }

    unless new_entity.persisted?
      setup_permissions(new_entity)

      unless new_entity.save
        errors.add(:primary_email, "could not save entity: #{new_entity.errors.full_messages.join(', ')}")
        return
      end
    end

    return if new_entity.id == investor_entity_id

    self.investor_entity = new_entity
  end

  # Single source of truth for the email-edit lock, shared by the entity
  # reassignment guard, the validation below, and the edit form (which hides
  # the "Edit Email" affordance for locked stakeholders).
  def primary_email_locked?
    persisted? && users.exists?
  end

  # Editing the primary email is only allowed while the stakeholder has no
  # users. Users hang off investor_accesses and are keyed to the identity
  # entity that the email resolves to, so an email change under them would
  # orphan their access. This validation is the authoritative server-side
  # guard (also covers CSV "Update Only" imports and any direct model updates).
  def primary_email_locked_when_users_exist
    return unless primary_email_changed? && primary_email_locked?

    errors.add(:primary_email, "cannot be changed because this stakeholder has users linked to it. Please remove the stakeholder's users before changing the primary email.")
  end

  # Find (by email, falling back to pan) or build an Entity to use as this
  # investor's investor_entity. Shared by #update_name (new-record creation, in
  # investor.rb) and #reassign_entity_on_email_change (existing-record email
  # change) so the two paths can't drift on what counts as "the same" entity.
  def find_or_build_investor_entity
    email = primary_email.presence&.strip
    e = email ? Entity.where(primary_email: email).first : nil
    e ||= pan.present? ? Entity.where(pan: pan.strip).first : nil
    e ||= Entity.new(name: investor_name.strip, entity_type: "Investor", pan:, primary_email: email)
    e
  end

  private

  # MySQL session-level advisory lock keyed by email, to close the TOCTOU window
  # between "look up Entity by email" and "create Entity with that email" — there
  # is no unique index on entities.primary_email, so without this, two concurrent
  # requests reassigning different investors to the same new email could each
  # create their own duplicate Entity.
  #
  # GET_LOCK/RELEASE_LOCK are MySQL-specific (production uses mysql2; test envs
  # may run sqlite3, which has no equivalent and doesn't need one — it has no
  # real cross-connection concurrency).
  def with_entity_email_lock(email)
    return yield unless mysql_adapter?

    lock_name = "investor_entity_email:#{email}"
    ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql(["SELECT GET_LOCK(?, 10)", lock_name]))
    begin
      yield
    ensure
      ActiveRecord::Base.connection.execute(ActiveRecord::Base.sanitize_sql(["SELECT RELEASE_LOCK(?)", lock_name]))
    end
  end

  def mysql_adapter?
    ActiveRecord::Base.connection.adapter_name.casecmp?("mysql2")
  end

  def sole_investor?
    exclude_category = %w[Trust Founder Employee].include?(category)
    Investor.where(investor_entity_id:).one? && !exclude_category
  end

  # Cascade an investor_entity_id change to records that reference the old entity.
  # Runs via after_commit after the investor's own investor_entity_id is persisted.
  #
  # Covers: entity.investor_accesses, entity.deal_investors, InvestorNoticeEntry
  # (all scoped by entity_id to this fund). Users never need moving here:
  # primary_email_locked_when_users_exist guarantees email-driven reassignments
  # only happen for stakeholders with no users, and the manual "Investor Entity
  # Update" admin flow intentionally moves only the investor's own entity link.
  #
  # NOTE: This is an after_commit callback — if the cascading updates fail, the
  # investor's investor_entity_id is already committed and cannot be rolled back.
  # This is a pre-existing architectural constraint.
  #
  # NOTE: update_column / update_all bypass model callbacks (Chewy index updates,
  # Audited logging, etc). Ensure that models receiving these updates do not
  # require callback-triggered side effects for entity_id changes.
  def change_investor_entity
    ActiveRecord::Base.transaction do
      # update_column(:investor_entity_id, investor_entity.id)
      old_entity_id = saved_change_to_investor_entity_id&.first
      return unless old_entity_id

      Rails.logger.debug { "Updating investor entity from #{old_entity_id} to #{investor_entity_id}" }
      entity.investor_accesses.where(investor_entity_id: old_entity_id).update_all(investor_entity_id: investor_entity_id)
      entity.deal_investors.where(investor_entity_id: old_entity_id).update_all(investor_entity_id: investor_entity_id)
      InvestorNoticeEntry.where(entity_id:, investor_entity_id: old_entity_id).update_all(investor_entity_id: investor_entity_id)
    end
  rescue StandardError => e
    Rails.logger.error "Error updating investor entity: #{e.message}"
    Rails.error.report(
      e,
      context: {
        investor_id: id,
        investor_entity_id:,
        source: "update_investor.change_investor_entity"
      }
    )
  end
end
