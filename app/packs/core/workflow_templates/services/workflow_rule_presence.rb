# Whether an entity has any workflow auto-assignment rule for a record type — remembered only inside a
# `WorkflowRulePresence.remember { ... }` block, so code that creates many records of one entity and type
# in a row (e.g. WithFolder#setup_folder_from_path, one Folder per path level) asks the database once
# instead of once per record.
#
# Outside a block nothing is remembered and #any? is the same single exists? query as before, so the
# memo can never go stale across requests, jobs or test scenarios (which restore the database from a
# snapshot without callbacks). A block is short-lived and creates no rules, so it cannot go stale either.
module WorkflowRulePresence
  KEY = :workflow_rule_presence

  module_function

  # Remember rule presence for the duration of the block. Nested blocks share the outer memo.
  def remember
    return yield if ActiveSupport::IsolatedExecutionState[KEY]

    ActiveSupport::IsolatedExecutionState[KEY] = {}
    begin
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[KEY] = nil
    end
  end

  # Any rule for this entity and workflowable type? Memoised inside #remember, a plain query outside.
  def any?(entity_id, workflowable_type)
    memo = ActiveSupport::IsolatedExecutionState[KEY]
    return query(entity_id, workflowable_type) unless memo

    memo.fetch([entity_id, workflowable_type]) { memo[[entity_id, workflowable_type]] = query(entity_id, workflowable_type) }
  end

  # True only inside #remember when it is already known there are no rules — lets after_create skip the
  # service without adding a query to the common path (outside a block it always returns false)
  def known_none?(entity_id, workflowable_type)
    memo = ActiveSupport::IsolatedExecutionState[KEY]
    return false unless memo

    !any?(entity_id, workflowable_type)
  end

  def query(entity_id, workflowable_type)
    WorkflowAutoAssignmentRule.exists?(entity_id:, workflowable_type:)
  end
end
