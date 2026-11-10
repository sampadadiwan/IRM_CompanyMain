# frozen_string_literal: true

# ④ The approval rule (OWASP review 2026-11 M13, openspec/changes/archive/2026-11-10-capital-call-distribution-maker-checker, design
# card ④, D5, D7, D9; LLD "Method Contracts").
#
# Included in CapitalCallPolicy and CapitalDistributionPolicy (like WorkflowablePolicyMethods). approve? gains one
# clause, maker_checker_allows?, so every path that already asks approve? — the button, a direct URL, the JSON API,
# the bulk jobs — refuses a preparer once the firm's setting is on, with no check of its own. Reads only.
module MakerCheckerPolicyMethods
  # true unless the setting is on and this person (or the CapHive support person acting as them) prepared the record.
  # Setting off (the default for every firm): always true, so approve? is exactly as before (E1, H14, E20).
  # D7 — no single-approver fallback: with the setting on, a preparer is refused even when nobody else can approve.
  def maker_checker_allows?
    # H14 / E20 / E44 — setting off: today's rule
    return true unless record.maker_checker_on?
    # E27 / E31 — open-ended settlements are approved by the system, never by a person
    return true if record.maker_checker_exempt?

    # H13 / E15 / E17 / E26 — a preparer is refused; X10 — so is support who prepared it, acting as anyone
    !actor_ids.intersect?(record.preparer_ids)
  end

  # ④ → ⑥ — the page shows Approve disabled with the reason (H13, E28), and bulk approve names the reason (X7, X8):
  # this person could approve it, but for having prepared it
  def awaiting_second_approver?
    !record.approved && update? && user.has_cached_role?(:approver) && !maker_checker_allows?
  end

  # ④ → ⑥ — "Request approval" is offered only to someone who can't approve the record themselves (a checker simply
  # approves, E56), on an unapproved record (E38), with the setting on (E37 — open question 2), never for an
  # open-ended settlement. update? keeps out other firms, investors and read-only users (X13–X15).
  def request_approval?
    !record.approved && update? && record.maker_checker_on? && !record.maker_checker_exempt? && !approve?
  end

  private

  # D9 — the policy user, and the CapHive support person behind an impersonated session
  def actor_ids
    [user.id, user.support_user_id].compact.map(&:to_i)
  end
end
