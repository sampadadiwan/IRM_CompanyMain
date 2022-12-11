class AddOnboardingToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :onboarding_completed, :boolean, default: false
  end
end
