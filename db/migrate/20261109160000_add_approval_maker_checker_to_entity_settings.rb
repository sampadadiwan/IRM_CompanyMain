# OWASP review 2026-11 M13 (openspec/changes/archive/2026-11-10-capital-call-distribution-maker-checker, design card ①, D6, LLD
# "Schema Detail").
#
# The firm's maker–checker switch: when on, whoever prepared a capital call or distribution cannot approve it.
# Off for every firm, existing and new (the user's decision on open question 1), so nothing changes on deploy.
# NOT NULL so the approval rule never has to treat nil as a third state. entity_settings has one row per firm, so
# MySQL 8 adds the column instantly.
class AddApprovalMakerCheckerToEntitySettings < ActiveRecord::Migration[8.1]
  def change
    add_column :entity_settings, :approval_maker_checker, :boolean, default: false, null: false
  end
end
