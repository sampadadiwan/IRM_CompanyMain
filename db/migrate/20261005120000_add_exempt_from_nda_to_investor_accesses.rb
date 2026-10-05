# frozen_string_literal: true

# Adds exempt_from_nda boolean to investor_accesses for stakeholder-level NDA exemption.
# When a GP grants investor access, they can check "Exempt from NDA" to bypass the
# NDA gate for all users under that investor. Defaults to false so existing records
# are unaffected.
#
# Changed: Replaces the user-level nda_exemptions table approach.
# Why: Per product decision (2026-10-05) — exemption is stakeholder-level, matching
#   how NDA acceptance works (one user signs on behalf of the investor, all unlock).
#
# @see InvestorAccess
# @see DocumentsController#ensure_nda_accepted
class AddExemptFromNdaToInvestorAccesses < ActiveRecord::Migration[8.0]
  def change
    add_column :investor_accesses, :exempt_from_nda, :boolean, default: false, null: false
  end
end
