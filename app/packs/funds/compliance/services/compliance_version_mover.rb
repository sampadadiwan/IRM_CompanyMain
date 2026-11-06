# ⑤ Moves a fund's attachment forward to the newest effective version, by that version's applicability:
#   all        → every fund moves on the effective date (H46)
#   new_funds  → funds started on/after the applicability date move; older funds stay ("grandfathered") (H47, E80)
#   transition → every fund moves; funds started before the effective date get warnings until the end date (E82–E85)
# Dates are compared in the pack's regime time zone (R18, E116). A missing fund start date when the
# version needs it is "Could not check" — never guessed (R4, E86, X62). Moving keeps / drops / archives
# overrides (E90–E93), closes items of removed checks (E94) and supersedes a corrected version's results (H57).
# Never moves backwards (X58, X59); early adoption is applied by ComplianceRequestDecide.
class ComplianceVersionMover
  State = Struct.new(:status, :version, :transition_until, :grandfathered, :events, keyword_init: true) do
    def checkable?
      status == :ok
    end
  end

  def self.call(fund_pack, run_at: Time.current)
    new(fund_pack, run_at).call
  end

  def initialize(fund_pack, run_at)
    @fp = fund_pack
    @pack = fund_pack.compliance_pack
    @fund = fund_pack.fund
    @date = @pack.regime_date(run_at)
    @events = []
  end

  def call
    # E99: a retired pack is no longer checked from its retirement date
    return state(:retired) if @pack.retired?(@date)

    target = newest_effective_version
    if target
      applies = target.applies_to?(@fund)
      # R4 / E86 / X62: the version needs the start date to decide — do not guess
      return state(:missing_start_date) if applies.nil?

      if applies
        move_to(target)
      else
        @grandfathered = true
      end
    end
    state(:ok)
  end

  private

  def current
    @fp.compliance_pack_version
  end

  # Published, effective by the regime date, and newer than the fund's current version
  def newest_effective_version
    cur_no = current&.version_no || 0
    @pack.versions.select { |v| v.published? && v.effective_from && v.effective_from <= @date && v.version_no > cur_no }
         .max_by(&:version_no)
  end

  def move_to(target)
    previous = current
    ActiveRecord::Base.transaction do
      carry_overrides(target)
      close_removed_checks(target)
      supersede_corrected(previous, target) if previous && target.corrects_version_id == previous.id
      @fp.update!(compliance_pack_version: target)
    end
    @events << { "kind" => "version_moved", "from" => previous&.label, "to" => target.label,
                 "published_late" => target.published_late? }
  end

  # E90 kept (stricter), E91 kept (equal), E92 dropped (new limit stricter), E93 archived (check removed)
  def carry_overrides(target)
    @fp.active_overrides.each_value do |ovr|
      check = target.check(ovr.check_key)
      if check.nil?
        ovr.update!(status: "archived")
        @events << { "kind" => "override_archived", "check" => ovr.check_key }
        next
      end
      new_limit = check.dig("limit", "value")
      next if new_limit.nil?

      value = ovr.payload_hash["limit"].to_d
      cmp = ComplianceCheckEvaluator.compare_direction(check)
      next if value == new_limit.to_d || ComplianceCheckEvaluator.stricter?(value, new_limit.to_d, cmp)

      ovr.update!(status: "dropped")
      @events << { "kind" => "override_dropped", "check" => ovr.check_key, "message" =>
        "Override #{ComplianceFormat.limit(value, 'pct')} dropped — #{target.label} limit #{ComplianceFormat.limit(new_limit, 'pct')} is stricter" }
    end
  end

  # E94: open items on checks the new version removes close as "Check removed"
  def close_removed_checks(target)
    keys = target.checks.pluck("key")
    @fp.compliance_register_items.open_items.where.not(check_key: keys).find_each do |item|
      item.close!("check_removed", on: @date)
    end
  end

  # H57 / X67: results of the faulty version are marked, never deleted
  def supersede_corrected(previous, _target)
    ComplianceResult.where(fund_compliance_pack_id: @fp.id, compliance_pack_version_id: previous.id, superseded_reason: nil)
                    .update_all(superseded_reason: "pack_correction", updated_at: Time.current)
    @corrected_from = previous.id
  end

  def state(status)
    version = current
    until_date = version&.in_transition?(@fund, @date) ? version.transition_ends_on : nil
    State.new(status:, version:, transition_until: until_date, grandfathered: @grandfathered || false,
              events: @events)
  end
end
