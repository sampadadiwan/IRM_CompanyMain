# The attention list and resolving an item: the list needs the permission and a fund role; resolving
# needs permission to edit the item's record. Always the user's own entity.
# See openspec/changes/document-checks/design.md (card ⑧ Access). Worked examples X6, X8, X10.
class DocCheckResultPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def index?
    enabled?
  end

  def check_again? = index?

  # Use document value / Mark as OK / Undo
  def resolve?
    enabled? && user.entity_id == record.entity_id &&
      DocChecks::Registry.for(record.doc_check_run.record_type).can_edit?(user, record.record)
  end

  def use_document_value? = resolve?
  def mark_ok? = resolve?
  def undo? = resolve?

  private

  def enabled?
    user.entity&.enable_doc_llm_validation && !user.curr_role_investor?
  end
end
