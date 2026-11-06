# Phase 5 (newcomer guidance): when the welcome and the Getting started reminders were sent, so each goes
# out once (H87, E189, E190). Step progress itself is never stored — it is worked out from data (D14, R150).
class AddOnboardingToComplianceEntitySetups < ActiveRecord::Migration[8.1]
  def change
    add_column :compliance_entity_setups, :onboarding, :json
  end
end
