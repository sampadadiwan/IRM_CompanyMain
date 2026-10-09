# Starting a check and viewing its results: decided by the record's own policy through the registry
# entry (fund users of the record's entity — never investors), on an entity with the permission on.
# See openspec/changes/document-checks/design.md (card ③ Triggers, card ⑧ Access). Worked examples X6, X7, X10.
class DocCheckRunPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  # record: the DocCheckRun (show / panel) or the record being checked (create)
  def create?
    enabled? && entry.can_edit?(user, target)
  end

  def show?
    enabled? && entry.can_view?(user, target)
  end

  def panel? = show?

  private

  def target
    record.is_a?(DocCheckRun) ? record.record : record
  end

  def entry
    DocChecks::Registry.for(target)
  end

  def enabled?
    user.entity&.enable_doc_llm_validation && !user.curr_role_investor?
  end
end
