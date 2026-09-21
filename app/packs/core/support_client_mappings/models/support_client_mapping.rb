class SupportClientMapping < ApplicationRecord
  include Trackable.new

  # Each SupportClientMapping links a User (the support person)
  # to an Entity (the client they are mapped to).
  belongs_to :user
  belongs_to :entity

  # String representation of the mapping: "<user> - <entity>"
  def to_s
    "#{user} - #{entity}"
  end

  # Class method to remove/disable mappings where end_date has expired.
  # It checks for mappings still enabled but with past end_date.
  def self.disable_expired
    SupportClientMapping.where('enabled = ? and end_date < ?', true, Time.zone.today).find_each(&:disable_support)
  end

  # After any database commit, trigger enable/disable cascade actions if enabled attribute changed.
  after_commit :enable_disable, if: -> { saved_change_to_enabled? }

  before_destroy :disable_support

  # Ensure the support state of associated entity/users matches this mapping.
  def enable_disable
    if enabled
      enable_support
    else
      disable_support
    end
  end

  # Enables support for the entity and all its employees.
  # - Marks this mapping as enabled.
  # - Sets `:enable_support` permission on the entity.
  # - Updates all associated employees to have support enabled.
  def enable_support
    update_column(:enabled, true)
    entity.permissions.set(:enable_support)
    entity.save
    entity.employees.each do |employee|
      employee.update_column(:enable_support, true)
    end
  end

  # Disables support for the entity and all its employees.
  # - Marks this mapping as disabled.
  # - Removes `:enable_support` permission on the entity.
  # - Updates all associated employees to disable support.
  def disable_support
    # Security fix (Finding 1): If the support user is currently switched into this entity's
    # context, force-revert them BEFORE marking the mapping disabled. Without this, a user who
    # has already called switch() retains their company_admin role and the client entity_id even
    # after the mapping expires (via disable_expired) or is administratively revoked. The public
    # revert() method checks enabled? so we call perform_revert directly to bypass that guard.
    perform_revert if status == 'Switched'

    update_column(:enabled, false)

    # Only disable entity support if no other enabled mappings exist
    other_active = entity.support_client_mappings.where.not(id: id).exists?(enabled: true)
    unless other_active
      entity.permissions.unset(:enable_support)
      entity.save
      entity.employees.each do |employee|
        employee.update_column(:enable_support, false)
      end
    end
  end

  # Switches current user context to mapped entity.
  # - Caches original entity and roles in json_fields.
  # - Changes user entity_id to mapped entity.
  # - Removes :support role, grants :company_admin role.
  # Raises error if mapping is currently disabled.
  def switch
    if enabled && entity.enable_support
      user.json_fields ||= {}
      user.json_fields['orig_entity_id'] ||= user.entity_id
      user.json_fields['orig_roles'] ||= user.roles.pluck(:name)
      user.update_columns(entity_id: entity.id, json_fields: user.json_fields, entity_type: entity.entity_type)
      # REQUIRED BY DESIGN — do NOT uncomment `user.remove_role(:support)`.
      #
      # A switched support user intentionally keeps BOTH :support and :company_admin:
      #   - :company_admin grants full access within the mapped client entity (the switch target),
      #     which is what the support agent needs to actually help the client.
      #   - :support is retained on purpose because support workflows must keep working while
      #     switched — the :support role is what ApplicationPolicy#permissioned_employee? uses (via
      #     its `else support?` fallthrough) to let support act across client entities for
      #     cross-tenant support tasks (e.g. triaging, comparing, moving data between clients).
      #
      # Trade-off accepted: this means a switched support user has cross-entity access beyond the
      # single mapping. That is a deliberate, documented risk-acceptance for support operations —
      # see docs/security/security_review_2026_07.md (finding H1). Access is still gated by the
      # user actually holding the :support role, which is granted only to trusted internal staff.
      # revert() re-adds :support so the switch/revert lifecycle stays symmetric.
      # user.remove_role(:support)
      user.add_role(:company_admin)
    else
      raise 'Cannot switch a disabled mapping'
    end
  end

  # Reverts a user back to their original entity and roles.
  # - Restores previous entity_id from cached json_fields.
  # - Removes :company_admin role, re-adds :support role.
  # Raises error if no previous entity or if mapping is disabled.
  def revert
    raise 'Cannot revert a disabled mapping' unless enabled

    # Security fix (Finding 3): Delegate to perform_revert which does NOT replay orig_roles from
    # json_fields. The original implementation blindly re-added every role stored in the cache at
    # switch time. If an administrator revoked a role from the support user while they were switched
    # (e.g., in response to a security incident), calling revert would silently undo that revocation.
    # perform_revert restores only the :support role and clears the cache so stale data cannot be
    # replayed by a subsequent revert call. Any additional roles must be re-granted by an admin.
    raise 'No previous entity to revert to' unless perform_revert
  end

  def status
    if user.json_fields.present? && user.json_fields['orig_entity_id'].present? && user.json_fields['orig_entity_id'] != user.entity_id
      'Switched'
    else
      'Reverted'
    end
  end

  def allow_login_as(email)
    # Security fix (Finding 5): Use case-insensitive comparison. Email addresses are
    # case-insensitive per RFC 5321, so "User@Example.com" and "user@example.com" must
    # be treated as the same address to prevent whitelist bypass via email casing tricks.
    if user_emails.present?
      enable_user_login && user_emails.split(',').map { |e| e.strip.downcase }.include?(email.to_s.downcase)
    else
      enable_user_login
    end
  end

  private

  # Core revert logic shared between the public revert() method and disable_support().
  # Intentionally skips the enabled? guard so it can be called during forced reverts
  # (e.g., when a mapping expires while the user is already switched).
  #
  # Security fix (Finding 3): Does NOT replay orig_roles from json_fields.
  # Only the :support role is restored; any other roles revoked by an admin while the user
  # was switched remain revoked. The json_fields cache is cleared to prevent stale data
  # from being replayed if this method is ever called again on the same record.
  #
  # Returns true on success, false if no cached orig_entity_id was found.
  def perform_revert
    orig_entity_id = user.json_fields&.dig('orig_entity_id')
    orig_entity    = Entity.find_by(id: orig_entity_id)
    return false unless orig_entity_id.present? && orig_entity.present?

    user.update_columns(entity_id: orig_entity_id, entity_type: orig_entity.entity_type)
    user.remove_role(:company_admin)
    user.add_role(:support)

    # Clear the switch cache so a second revert cannot replay stale entity/role data.
    user.json_fields = (user.json_fields || {}).except('orig_entity_id', 'orig_roles')
    user.update_column(:json_fields, user.json_fields)

    true
  end
end
