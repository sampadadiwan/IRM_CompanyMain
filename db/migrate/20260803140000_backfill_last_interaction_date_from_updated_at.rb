# A meaningful edit to a deal investor — completing a step, changing the status or
# the amounts — now counts as an interaction alongside notes' "On" dates and tasks'
# completed_on. AddLastInteractionTracking only seeded from notes and tasks, so
# investors that were only ever worked through their steps came out blank and sank
# to the bottom of the grid. updated_at is the only record of when that happened.
#
# Only where the column is still NULL. Raising rows that already carry a note or
# task date to their updated_at would flatten most of the distinction the sort
# exists to make — bulk edits and data migrations move updated_at, and the client
# wants the dates their notes assert.
class BackfillLastInteractionDateFromUpdatedAt < ActiveRecord::Migration[8.1]
  def up
    # execute <<~SQL.squish
    #   UPDATE deal_investors
    #   SET last_interaction_date = DATE(updated_at)
    #   WHERE last_interaction_date IS NULL
    # SQL
  end

  # Irreversible in the strict sense — the backfilled dates are indistinguishable
  # from ones a note set. Nothing to undo: the column itself is dropped by
  # AddLastInteractionTracking#down.
  def down
    # no-op
  end
end
