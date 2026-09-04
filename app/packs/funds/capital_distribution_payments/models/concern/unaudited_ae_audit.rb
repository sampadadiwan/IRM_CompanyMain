# json_fields["ae_audit"] is derived data — rebuilt from the commitment's account_entries on
# every setup_distribution_fees — and on a long AE history it runs to hundreds of KB. Auditing
# it wrote roughly twice that payload (old + new) into audits.audited_changes, a MySQL TEXT
# capped at 64KB, so recomputing fees failed with "Data too long for column 'audited_changes'"
# (a destroy, which serialises every attribute, would have failed the same way).
#
# Strip just that key from the audit payload; the rest of json_fields stays audited, and a
# recompute that touched nothing else still records an updated_at row so the trail is unbroken.
# Include this AFTER Trackable so it sits ahead of Audited's instance methods and super resolves
# to them.
module UnauditedAeAudit
  extend ActiveSupport::Concern

  private

  def audited_attributes = strip_ae_audit(super)

  # When ae_audit was the only thing to change, stripping it leaves nothing and Audited skips
  # writing the row altogether — the recompute would vanish from the trail. updated_at is in
  # Audited.ignored_attributes globally, so fall back to it explicitly to keep a dated, attributed
  # row. Touch audits are left alone: a bare timestamp bump is what Audited already declines to record.
  def audited_changes(for_touch: false, **)
    changes = strip_ae_audit(super)
    return changes if for_touch || changes.present?

    changes_to_save.slice("updated_at")
  end

  # Handles both payload shapes: a flat attributes hash (create/destroy) and a [before, after]
  # diff pair (update). If ae_audit was the only thing that changed, drop the key rather than
  # record an identical before and after; audited_changes then supplies the updated_at fallback.
  def strip_ae_audit(payload)
    case (json = payload["json_fields"])
    when Hash
      payload.merge("json_fields" => json.except("ae_audit"))
    when Array
      before, after = json.map { |value| value.is_a?(Hash) ? value.except("ae_audit") : value }
      before == after ? payload.except("json_fields") : payload.merge("json_fields" => [before, after])
    else
      payload
    end
  end
end
