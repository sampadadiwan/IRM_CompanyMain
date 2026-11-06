# ⑥⑨ Morning housekeeping before the digest.
# Worked examples E36, E87, E112, E113 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
module ComplianceMaintenance
  module_function

  # R12 / E112 / E113: items and pending approvals of deactivated users return to the compliance owner;
  # the digest says so once
  def reassign_deactivated(setup)
    owner = setup.owner
    return if owner.nil?

    inactive_ids = User.where(entity_id: setup.entity_id, active: false).pluck(:id)
    return if inactive_ids.empty?

    items = ComplianceRegisterItem.open_items.where(entity_id: setup.entity_id, assignee_id: inactive_ids)
    n_items = items.count
    items.find_each { |i| i.update!(assignee: owner) }
    n_duties = ComplianceDuty.not_done.where(entity_id: setup.entity_id, owner_id: inactive_ids).update_all(owner_id: owner.id)
    notes = []
    notes << "#{n_items} item#{'s' if n_items != 1} of a deactivated user returned to #{owner.full_name}" if n_items.positive?
    notes << "#{n_duties} dut#{n_duties == 1 ? 'y' : 'ies'} of a deactivated user returned to #{owner.full_name}" if n_duties.positive?
    notes.concat(pending_approval_notes(setup, inactive_ids, owner))
    add_notes(setup, notes)
  end

  # E112: pending approvals that a now-deactivated approver could have decided are flagged to the owner —
  # once per deactivated approver (remembered in the setup so the digest does not repeat it)
  def pending_approval_notes(setup, inactive_ids, owner)
    handled = Array(setup.ai_settings_hash["handled_inactive_user_ids"])
    new_ids = User.where(id: inactive_ids - handled).select { |u| u.has_cached_role?(:company_admin) || u.get_extended_permissions.set?(:compliance_approve) }.map(&:id)
    pending = ComplianceRequest.pending.where(entity_id: setup.entity_id).count
    setup.ai_settings = setup.ai_settings_hash.merge("handled_inactive_user_ids" => (handled + inactive_ids).uniq)
    return [] if new_ids.empty? || pending.zero?

    ["#{pending} pending approval#{'s' if pending != 1} of a deactivated approver returned to #{owner.full_name}"]
  end

  # E35/E36/E38: overdue on the day after fix-by; escalate once
  def escalate_overdue(entity, date)
    ComplianceRegisterItem.open_items.where(entity_id: entity.id, escalated_on: nil).where(fix_by: ...date).includes(:fund).find_each do |item|
      ComplianceNotices.escalation(item)
      item.update_columns(escalated_on: date)
    end
  end

  # E87: owners told exactly 7 days before a version takes effect (publish-day notice is sent at publish, H49)
  def version_reminders(entity, date)
    pack_ids = FundCompliancePack.active.where(entity_id: entity.id).distinct.pluck(:compliance_pack_id)
    CompliancePackVersion.where(compliance_pack_id: pack_ids, status: "published", effective_from: date + 7.days).includes(:compliance_pack).find_each do |v|
      ComplianceNotices.version_notice(entity, "#{v.compliance_pack.name} #{v.label} takes effect on #{I18n.l(v.effective_from)}")
    end
  end

  def add_notes(setup, notes)
    setup.digest_notes = Array(setup.digest_notes) + notes if notes.any?
    setup.save! if setup.changed?
  end
end
