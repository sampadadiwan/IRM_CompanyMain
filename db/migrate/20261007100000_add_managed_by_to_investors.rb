# The employee who looks after a portfolio company: gets the KPI report journey's reminders and
# completion email for its reports, ahead of the template's owner and the Kpi-tagged team.
# Worked examples H6, H7 — openspec/changes/kpi-report-journey/design.md#worked-examples
class AddManagedByToInvestors < ActiveRecord::Migration[8.1]
  def change
    add_reference :investors, :managed_by_user, null: true, foreign_key: { to_table: :users }, index: true
  end
end
