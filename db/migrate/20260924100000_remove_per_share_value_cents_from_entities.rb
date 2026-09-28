# `entities.per_share_value_cents` was a denormalised copy of a Valuation's per-share value,
# maintained by a `Valuation#update_entity` after_save hook. The hook only fired for valuations
# with a blank `owner_type` — 15 of 3,793 rows in production — and used a silent `save`, so the
# column never held a real figure: it is 0.0 for every one of the 7,544 entity rows.
#
# It was lossy as well as unpopulated. This column is scale: 2 while
# `valuations.per_share_value_cents` is scale: 8, the precision ValuationsController goes out of
# its way to preserve (see the comment at valuations_controller.rb:124).
#
# The one screen that read it (entities/_investor_dashboard_stats, the "Valuation (Share Price)"
# card) now reads `Entity#latest_valuation` directly, and the hook is gone, so nothing in the
# app references the column any more.
class RemovePerShareValueCentsFromEntities < ActiveRecord::Migration[8.1]
  def up
    remove_column :entities, :per_share_value_cents
  end

  def down
    add_column :entities, :per_share_value_cents, :decimal, precision: 15, scale: 2, default: "0.0"
  end
end
