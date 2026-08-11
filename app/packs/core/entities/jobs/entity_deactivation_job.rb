# Cascades the effects of deactivating an entity (entities.active = false).
#
# Triggered by Entity#cascade_deactivation whenever `active` flips to false — from the support
# Deactivate button on the entity page, from /admin/entities, or from the console.
#
# Two things are revoked:
#   1. Employee logins  — every User of the entity is set inactive and can no longer sign in.
#   2. Investor access  — every approved InvestorAccess granted by the entity is un-approved,
#                         which removes LP portal access and stops all LP notifications.
# Nothing is deleted; both are plain flag flips that a support user can undo record by record.
class EntityDeactivationJob < ApplicationJob
  queue_as :low

  # @param entity_id [Integer] the entity that was deactivated
  # @param user_id [Integer, nil] the support user to alert when the cascade finishes
  def perform(entity_id:, user_id: nil)
    entity = Entity.find_by(id: entity_id)
    return if entity.blank?

    # The entity may have been re-activated between the commit and this job running — in that
    # case there is nothing to revoke and we must not touch existing access.
    if entity.active?
      Rails.logger.info "Entity #{entity_id} is active again; skipping deactivation cascade"
      return
    end

    employees_count = entity.employees.where(active: true).update_all(active: false)
    accesses_count = revoke_investor_accesses(entity)

    Rails.logger.info "Entity #{entity.id} - #{entity.name}: deactivated #{employees_count} employees, revoked #{accesses_count} investor accesses"
    send_notification("#{entity.name} deactivated: #{employees_count} employee login(s) disabled and #{accesses_count} investor access(es) revoked.", user_id)
  end

  private

  # counter_culture maintains investors.investor_access_count / unapproved_investor_access_count /
  # will_receive_email from InvestorAccess callbacks, so update_all would leave those counters
  # stale. update_attribute skips validations (legacy rows may no longer validate) while still
  # running the callbacks the counters depend on. find_each keeps memory flat on large clients.
  def revoke_investor_accesses(entity)
    count = 0
    entity.investor_accesses.approved.find_each do |investor_access|
      investor_access.update_attribute(:approved, false)
      count += 1
    end
    count
  end
end
