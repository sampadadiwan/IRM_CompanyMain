# ⑥ Creates manual-duty occurrences for one fund pack on a run date:
#   scheduled — one per period of the pack's basis, starting with the period containing the attach date (E120, E121)
#   event     — "for each new investor": one per investor whose commitment date is on/after the duty's "from" date (H28, E106, E107)
# Due dates count calendar days (R19, E117). Owner defaults to the compliance owner (R13, E122).
# Bulk creation uses insert_all; the unique key makes re-runs harmless (E44).
class ComplianceDutyScheduler
  def self.call(fund_pack, version:, run_date:, setup:)
    new(fund_pack, version, run_date, setup).call
  end

  def initialize(fund_pack, version, run_date, setup)
    @fp = fund_pack
    @version = version
    @date = run_date
    @setup = setup
  end

  def call
    created = 0
    @version.duties.each do |duty|
      next unless applies?(duty)

      trig = duty["trigger"] || {}
      created += if trig["schedule"].present?
                   schedule_period(duty, trig["schedule"])
                 elsif trig["event"] == "new_investor"
                   schedule_new_investors(duty, Date.parse(trig["from"].to_s))
                 else
                   0
                 end
    end
    created
  end

  private

  def applies?(duty)
    applies = duty["applies_to"]
    applies.nil? || applies == "all" || Array(applies).include?(@fp.classification)
  end

  def due_days(duty)
    duty.dig("due", "n").to_i
  end

  # The period containing the run date; never one that ended before the pack was attached (E120)
  def schedule_period(duty, schedule)
    key, period_end = CompliancePeriod.for([@date, @fp.attached_on || @date].max, schedule, @version.period_basis)
    rows = [row(duty, key, period_end, period_end + due_days(duty).days)]
    insert(rows)
  end

  # One duty per investor whose first commitment in the fund is on/after the "from" date (E106, E107)
  def schedule_new_investors(duty, from)
    firsts = CapitalCommitment.where(entity_id: @fp.entity_id, fund_id: @fp.fund_id)
                              .where.not(investor_id: nil)
                              .group(:investor_id).minimum(:commitment_date)
    rows = firsts.filter_map do |investor_id, date|
      next if date.nil? || date < from || date > @date

      row(duty, "", nil, date + due_days(duty).days, subject_type: "Investor", subject_id: investor_id)
    end
    insert(rows)
  end

  def row(duty, period_key, period_end, due_on, subject_type: "", subject_id: 0)
    now = Time.current
    { entity_id: @fp.entity_id, fund_compliance_pack_id: @fp.id, duty_key: duty["key"], period_key:,
      period_end:, due_on:, subject_type:, subject_id:, owner_id: @setup&.owner_id, created_at: now, updated_at: now }
  end

  # insert_all skips rows already present (unique key) — re-runs and double clicks create nothing (E44)
  def insert(rows)
    return 0 if rows.empty?

    before = ComplianceDuty.where(fund_compliance_pack_id: @fp.id).count
    rows.each_slice(500) { |slice| ComplianceDuty.insert_all(slice, unique_by: :idx_cduty_unique) }
    ComplianceDuty.where(fund_compliance_pack_id: @fp.id).count - before
  end
end
