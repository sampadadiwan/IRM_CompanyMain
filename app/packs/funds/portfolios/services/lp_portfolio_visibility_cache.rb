# Per-request memo for LpPortfolioVisibility, so the policy scopes, views and policies of one request share
# a single membership query. Kept out of Current, which by its own rule holds only the acting user; Rails
# clears every CurrentAttributes at the start and end of each request and job.
# openspec/changes/lp-folio-portfolio-dashboard/design.md (card ③)
class LpPortfolioVisibilityCache < ActiveSupport::CurrentAttributes
  attribute :by_user
end
