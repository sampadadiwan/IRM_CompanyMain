# frozen_string_literal: true

# Concurrency fix: serialise concurrent actor submissions and launches at the DB level
# by locking the workflow_instance row. No schema change needed for actor responses
# because a unique index on (instance, step, actor) would block legitimate re-votes
# after a revert/restart archives the prior response.
# This migration is intentionally a no-op migration — the real fix is in the service
# and controller (SELECT FOR UPDATE via instance.lock!).
class AddUniqueConstraintsToWorkflowTables < ActiveRecord::Migration[7.1]
  def change
    # no-op — concurrency is handled via row-level locking (instance.lock!) in the
    # WorkflowActorResponsesController and WorkflowInstanceService#launch
  end
end
