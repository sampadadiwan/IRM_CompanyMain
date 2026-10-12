# Overrides one line of a draft NAV with a value and a reason (max 255), then recomputes NAV and
# NAV per unit. The override is kept across re-drafts.
# Worked examples H4, X6 — openspec/changes/open-ended-funds/design.md#worked-examples
class FundNavOverride < Trailblazer::Operation
  step :validate
  step :apply

  def validate(ctx, fund_nav:, line:, reason:, **)
    ctx[:errors] = if !fund_nav.draft? then "Only a draft NAV can be edited"
                   # An uploaded NAV has totals only; recomputing from lines would wipe it (review finding)
                   elsif fund_nav.source == "uploaded" then "An uploaded NAV has no lines to override — upload a corrected NAV instead"
                   elsif FundNav::LINES.exclude?(line.to_s) then "Unknown NAV line"
                   elsif reason.blank? then "Reason can't be blank"
                   elsif reason.length > 255 then "Reason is too long (maximum is 255 characters)"
                   end
    ctx[:errors].nil?
  end

  def apply(ctx, fund_nav:, line:, value:, reason:, current_user:, **)
    value_cents = value.to_s.delete(",").to_d * 100
    fund_nav.overrides = fund_nav.overrides_hash.merge(line.to_s => { "value_cents" => value_cents.to_s, "reason" => reason,
                                                                      "user_id" => current_user&.id, "at" => Time.current.iso8601 })
    fund_nav["#{line}_cents"] = value_cents
    # Audited: who changed which line, from what to what, and why (approvers may still approve)
    fund_nav.audit_comment = "Overrode #{line.to_s.humanize.downcase}: #{reason}"
    term = fund_nav.fund.evergreen_fund_setting.terms_for(fund_nav.unit_type)
    fund_nav.recompute_totals!(initial_price_cents: term.initial_price_cents)
    fund_nav.save!
  rescue ActiveRecord::RecordInvalid => e
    # X117: an override that would make the NAV negative is refused
    ctx[:errors] = e.record.errors.full_messages.to_sentence
    false
  end
end
