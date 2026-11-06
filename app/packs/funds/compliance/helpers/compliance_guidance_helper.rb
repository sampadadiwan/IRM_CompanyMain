# ⑩ Newcomer guidance (Phase 5): the words come from one glossary (config/locales/compliance.en.yml,
# D15) so a tooltip, a page intro and the user guide never say different things. Only existing pieces
# are used — the tooltip icon, the explainer alert, the user-guide button (D16).
# Worked examples H86, H88, H90, H92, E184, E185 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
module ComplianceGuidanceHelper
  GUIDE = "compliance_monitoring_user_guide".freeze

  # Which section bar pill is active, and which guide section the page's guide icon opens (H89, H90)
  PAGE_GUIDE = {
    "compliance_home" => [:home, "compliance-home"], "fund_compliance_packs" => [:home, "fund-packs"],
    "compliance_results" => [:register, "how-to-read-a-result"], "compliance_register_items" => [:register, "the-register"],
    "compliance_duties" => [:duties, "duties"], "document_facts" => [:facts, "facts-to-confirm"],
    "compliance_packs" => [:packs, "packs-and-versions"], "compliance_pack_versions" => [:packs, "packs-and-versions"],
    "compliance_check_drafts" => [:packs, "describe-a-check-in-words"], "compliance_entity_setups" => [:setup, "setup"],
    "compliance_onboarding" => [nil, "getting-started"]
  }.freeze

  # H89: counts on the section bar — open items, duties due or overdue, facts waiting. Memoised per request.
  def compliance_section_counts
    @compliance_section_counts ||= begin
      today = Time.zone.today
      fp_ids = policy_scope(FundCompliancePack).select(:id)
      {
        open: policy_scope(ComplianceRegisterItem).open_items.count,
        due: ComplianceDuty.where(entity_id: current_user.entity_id, fund_compliance_pack_id: fp_ids, done_on: nil)
                           .where(due_on: ..(today + ComplianceDuty::REMINDER_DAYS)).count,
        facts: DocumentFact.where(document_reading_id: policy_scope(DocumentReading).select(:id)).where.not(status: "confirmed").count
      }
    end
  end

  # H88: the info-circle tooltip with the glossary's wording for a term
  def cmp_term(key)
    cmp_tip(t("compliance.glossary.#{key}"))
  end

  # H90: the standard user-guide button (user_guide_info_icon's look), opening the guide at this page's section
  def cmp_guide_icon(anchor)
    return nil if current_user&.curr_role == "investor"

    link_to user_guide_path(GUIDE, anchor:), target: "_blank", rel: "noopener", id: "page_guide_icon",
                                             'data-bs-toggle': "tooltip", title: "User guide — this page",
                                             class: "btn btn-info p-0 rounded-circle d-inline-flex align-items-center justify-content-center",
                                             style: "width: 35px; height: 35px;" do
      tag.i(class: "ti ti-info-circle fs-5", style: "margin: 0 !important;")
    end
  end

  # H92 / R160: "Step by step, from your records as they stood at the 02:00 IST run on 06/11/2026" —
  # nightly runs name the firm's 02:00; Run now names its own start time
  def cmp_how_we_checked_subtitle(run, time_zone)
    return nil unless run

    tz = time_zone.presence || "Asia/Kolkata"
    started = (run.created_at || Time.current).in_time_zone(tz)
    key = run.trigger == "nightly" ? "subtitle_nightly" : "subtitle_manual"
    time = run.trigger == "nightly" ? format("%02d:00", ComplianceScheduleJob::RUN_HOUR) : l(started, format: :time_only)
    t("compliance.how_we_checked.#{key}", time:, zone: started.strftime("%Z"), date: l(run.run_date))
  end

  # H86 / E184 / E185: which run the page's results come from, and when the next one is
  def cmp_timing_banner(setup, last_success:, failed_since: false)
    tz = setup&.time_zone.presence || "Asia/Kolkata"
    now = Time.current.in_time_zone(tz)
    zone = now.strftime("%Z")
    run_time = format("%02d:00", ComplianceScheduleJob::RUN_HOUR)
    if last_success.nil?
      text = t("compliance.timing.none", time: run_time, zone:)
      css = nil
    elsif failed_since || last_success.finished_at.nil? || last_success.finished_at < ComplianceRun::STALE_AFTER.ago
      done = last_success.created_at.in_time_zone(tz)
      text = t("compliance.timing.stale", date: l(done.to_date), time: l(done, format: :time_only), zone:)
      css = "alert-warning"
    else
      next_run = now.hour < ComplianceScheduleJob::RUN_HOUR ? now.to_date : now.to_date + 1
      time = last_success.trigger == "nightly" ? run_time : l(last_success.created_at.in_time_zone(tz), format: :time_only)
      text = t("compliance.timing.latest", time:, zone:, date: l(last_success.run_date), next_date: l(next_run), next_time: run_time)
      css = nil
    end
    # Normal and "no results yet": a small muted line under the intro. Stale (E185): the amber box,
    # because it needs attention.
    if css
      tag.div(class: "alert #{css} d-flex align-items-center gap-2 py-2 small", id: "timing_banner") do
        safe_join([tag.i(class: "ti ti-clock"), text])
      end
    else
      tag.p(class: "text-muted small d-flex align-items-center gap-1 mb-3", id: "timing_banner") do
        safe_join([tag.i(class: "ti ti-clock"), text])
      end
    end
  end

  # R160 / D: results stored before structured steps (R113) only carry text lines. Turn each into the same
  # numbered step the new results show — "Corpus = ₹375.72 cr" → label + value; "Investable funds =
  # A − B = C" → label, calculation, value; "41.91% > 25% → Breach" → the result row. A line that only
  # restates a value ("₹2.00 cr = ₹2.00 cr") is dropped. Nothing is recomputed.
  def cmp_steps_from_lines(lines)
    n = 0
    Array(lines).filter_map do |raw|
      text = raw.to_s.strip.sub(/ · \d+ earlier not checked/, "")
      next if text.empty?

      step = if (m = text.match(/\A(.+?)\s*(?:→|->)\s*(Pass|Breach|Warning.*|Needs review)\z/))
               { "label" => "Result", "calc" => m[1], "value" => m[2].start_with?("Pass") ? "Pass" : m[2], "final" => true }
             elsif (m = text.match(/\A([^=:]+?):\s*(.+?)\s*=\s*([^=]+)\z/)) || (m = text.match(/\A([^=]+?)\s*=\s*(.+)\s*=\s*([^=]+)\z/))
               { "label" => m[1].strip, "calc" => m[2].strip, "value" => m[3].strip }
             elsif (m = text.match(/\A([^=]+?)\s*=\s*([^=]+)\z/))
               next if m[1].strip == m[2].strip

               { "label" => m[1].strip, "value" => m[2].strip }
             else
               { "label" => text }
             end
      n += 1
      step.merge("n" => n)
    end
  end

  # The timing banner for the whole firm (home, register) or one fund (its compliance page)
  def cmp_runs_timing_banner(fund: nil)
    runs = fund ? ComplianceRun.where(fund_id: fund.id) : ComplianceRun.where(entity_id: current_user.entity_id)
    last = runs.where(status: "succeeded").order(:created_at, :id).last
    failed = last.present? && runs.where(status: "failed").exists?(["created_at > ?", last.created_at])
    cmp_timing_banner(ComplianceEntitySetup.for(current_user.entity), last_success: last, failed_since: failed)
  end

  # "tonight at 02:00 IST" for empty states (E188)
  def cmp_next_run_words(setup)
    tz = setup&.time_zone.presence || "Asia/Kolkata"
    { time: format("%02d:00", ComplianceScheduleJob::RUN_HOUR), zone: Time.current.in_time_zone(tz).strftime("%Z") }
  end
end
