class Kpi < ApplicationRecord
  include WithCustomField
  include ForInvestor
  include KpiCumulative

  enum :status, { unapproved: 'unapproved', approved: 'approved' }, default: :approved

  STANDARD_COLUMNS = {
    "Name; text-col" => "name; text-col",
    "Value; num-col" => "value; num-col",
    "Display Value; text-col" => "display_value; text-col",
    "Percentage Change; num-col" => "percentage_change; num-col",
    "Notes; text-col" => "notes; text-col"
  }.freeze

  ADDITIONAL_COLUMNS_FROM = %i[kpi_report investor_kpi_mapping].freeze

  belongs_to :entity
  belongs_to :owner, class_name: "Entity", optional: true
  belongs_to :portfolio_company, class_name: "Investor", optional: true
  # These are the investees, who will probably have investor_kpi_mappings for the kpis by this entity.
  has_many :investees, through: :entity

  belongs_to :kpi_report
  attr_readonly :kpi_report_id # never moves to another KPI report (funds_api_security_policy_plan.md, B)
  belongs_to :investor_kpi_mapping, optional: true
  belongs_to :approved_by, class_name: "User", foreign_key: :approved_by_user_id, optional: true

  validates :name, :value, presence: true

  validates :name, length: { maximum: 100 }
  validates :notes, length: { maximum: 255 }
  validates :display_value, length: { maximum: 30 }
  validates :source, length: { maximum: 100 }, allow_blank: true

  validates :status, presence: true
  validates :name, uniqueness: { scope: %i[kpi_report_id portfolio_company_id status] }, if: -> { approved? }

  # KPIs created before this date predate mapping-id assignment (backfilled by the workbook job),
  # so they're exempt. Everything created on or after it must carry an investor_kpi_mapping_id.
  # A fixed cutoff (not Date.current) so a record's exemption never flips as days pass.
  MAPPING_ID_REQUIRED_FROM = Date.new(2026, 7, 24)
  validates :investor_kpi_mapping_id, presence: true, if: :require_mapping_id?

  scope :no_tag_list, -> { joins(:kpi_report).where('kpi_reports.tag_list': nil) }
  # --- Generic filters -------------------------------------------------
  scope :for_metric,  ->(name)  { where(name:) }
  scope :for_company, ->(pc_id) { where(portfolio_company_id: pc_id) }
  scope :approved,   -> { where(status: :approved) }
  scope :unapproved, -> { where(status: :unapproved) }
  scope :actuals,    -> { joins(:kpi_report).where('kpi_reports.tag_list': 'Actual') }
  scope :budgets,    -> { joins(:kpi_report).where('kpi_reports.tag_list': 'Budget') }
  scope :ics,        -> { joins(:kpi_report).where('kpi_reports.tag_list': 'IC') }
  scope :as_of,      ->(date) { joins(:kpi_report).where('kpi_reports.as_of': date) }
  scope :show_in_report, -> { joins(:investor_kpi_mapping).where(investor_kpi_mappings: { show_in_report: true }) }

  # `source` says who wrote a row. Only the cumulation writes AUTO_CUMULATION_SOURCE; an import writes
  # UPLOAD_SOURCE and the Kpi form writes MANUAL_SOURCE. Blank, upload and manual all mean a person wrote it,
  # and cumulation never overwrites or removes such a Quarter, YTD or Year row.
  AUTO_CUMULATION_SOURCE = "auto_cumulation".freeze
  UPLOAD_SOURCE = "upload".freeze
  MANUAL_SOURCE = "manual".freeze
  # Rows written before `source` existed carry no marker, only this note prefix (see process_cumulative_kpi)
  LEGACY_CALCULATED_NOTE_PREFIX = "Auto-generated".freeze
  CUMULATIVE_PERIODS = %w[Quarter YTD Year].freeze

  # Calculated Quarter, YTD and Year rows. Always combine with entity_id and portfolio_company_id.
  scope :calculated_cumulative, lambda {
    joins(:kpi_report)
      .where(kpi_reports: { period: CUMULATIVE_PERIODS })
      .where("kpis.source = :marker OR ((kpis.source IS NULL OR kpis.source = '') AND kpis.notes LIKE :legacy)",
             marker: AUTO_CUMULATION_SOURCE, legacy: "#{LEGACY_CALCULATED_NOTE_PREFIX}%")
  }

  scope :monthly, -> { joins(:kpi_report).where(kpi_reports: { period: 'month' }) }
  scope :quarterly, -> { joins(:kpi_report).where(kpi_reports: { period: 'quarter' }) }
  scope :yearly, -> { joins(:kpi_report).where(kpi_reports: { period: 'year' }) }
  scope :ytd, -> { joins(:kpi_report).where(kpi_reports: { period: 'ytd' }) }

  # --- Scopes needing joins -------------------------------------------
  # Attach the parent report so date filters hit SQL, not Ruby.
  scope :with_report, -> { joins(:kpi_report) }

  scope :cumulate, -> { joins(:investor_kpi_mapping).where(investor_kpi_mappings: { autofill: :cumulate }) }
  scope :forward_fill, -> { joins(:investor_kpi_mapping).where(investor_kpi_mappings: { autofill: :forward_fill }) }
  scope :compute, -> { joins(:investor_kpi_mapping).where(investor_kpi_mappings: { autofill: :compute }) }

  # --- Time helpers ----------------------------------------------------
  scope :for_date, lambda { |date|
    with_report.where(kpi_reports: { as_of: date })
  }

  scope :in_date_range, lambda { |range|
    with_report.where(kpi_reports: { as_of: range })
  }

  def custom_form_field
    field = nil
    if kpi_report.form_type
      sanitized_name = name.downcase.strip
      field = kpi_report.form_type.form_custom_fields.where(name: sanitized_name).first
      if field.nil?
        kpi_report.form_type.form_custom_fields.where("meta_data like '%#{sanitized_name}%'").find_each do |fcf|
          field = fcf if fcf.meta_data.downcase.split(",").include?(sanitized_name)
        end
      end
    end
    field ||= FormCustomField.new(field_type: "TextField", name:)
    field
  end

  def to_s
    "#{name}: #{value}"
  end

  # In-memory twin of the calculated_cumulative scope, for rows already loaded with their report.
  def calculated_cumulative?
    return false unless CUMULATIVE_PERIODS.any? { |period| period.casecmp?(kpi_report&.period.to_s) }

    source == AUTO_CUMULATION_SOURCE || (source.blank? && notes.to_s.start_with?(LEGACY_CALCULATED_NOTE_PREFIX))
  end

  # New records (created_at nil until saved) and anything created on/after the cutoff must have a
  # mapping id; legacy KPIs created before it are grandfathered in.
  def require_mapping_id?
    (created_at || Time.current) >= MAPPING_ID_REQUIRED_FROM.beginning_of_day
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[name value notes percentage_change portfolio_company_id status updated_at].sort.freeze
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[kpi_report entity investor_kpi_mapping portfolio_company]
  end

  def kpis_for_entity
    entity.kpis.joins(:kpi_report).where(name:).where("kpi_reports.period=?", kpi_report.period).order("kpi_reports.as_of asc")
  end

  # percentage_change is decimal(6,2), so a change beyond this cannot be stored
  PERCENTAGE_CHANGE_LIMIT = BigDecimal("9999.99")

  # Month, Quarter and Year rows change against the previous row of their series. A YTD row is a running total, so
  # against the previous YTD row it would only show the latest month's contribution; it changes against the YTD one
  # year earlier instead (H9). Nothing a year earlier, or zero, gives nil - never an older row (E15, E17).
  def self.recompute_percentage_change(kpis)
    # Group KPIs by period, name, owner and tag_list so a change is only computed between comparable KPIs
    kpis.group_by { |kpi| [kpi.kpi_report.period, kpi.name, kpi.owner_id, kpi.kpi_report.tag_list] }.each do |(period, *), grouped_kpis|
      ordered = grouped_kpis.sort_by { |kpi| kpi.kpi_report.as_of }
      pairs = if period.to_s.casecmp?("YTD")
                by_date = ordered.index_by { |kpi| kpi.kpi_report.as_of }
                ordered.map { |kpi| [by_date[year_earlier(kpi.kpi_report.as_of)], kpi] }
              else
                ordered.each_cons(2).to_a
              end

      pairs.each do |comparator, kpi|
        kpi.percentage_change = period.to_s.casecmp?("YTD") ? year_over_year_change(comparator, kpi) : change_against(comparator, kpi)
        kpi.save
      end
    end
  end

  # The date one year before as_of. A month end stays a month end, so 28 Feb 2025 matches 29 Feb 2024 (E18)
  def self.year_earlier(as_of)
    as_of.end_of_month == as_of ? as_of.prev_year.end_of_month : as_of.prev_year
  end

  # How far kpi is from the figure it is compared with (H7-H14, E11-E16, E22-E24, E33).
  # The change is relative to the size of the comparison figure, so a loss that shrinks is a rise and a loss that grows is a
  # fall; dividing by the signed figure would flip both. A percentage KPI (EBITDA %) follows the same rule: a margin that goes
  # from -63.2% to -55.7% is up 11.87%.
  def self.change_against(comparator, kpi)
    # if the divisor (the comparator) is 0, the percentage is infinity but we cant store that so keeping it nil
    return nil if comparator.value.zero?

    ((kpi.value - comparator.value) / comparator.value.abs) * 100
  end

  # Rounded to the stored 2 decimals first, then checked: 9,999.995 rounds to 10,000.00 and would overflow the
  # column, so a change that cannot be stored is nil rather than an error that stops the rest of the group (E27)
  def self.year_over_year_change(comparator, kpi)
    return nil if comparator.nil?

    change = change_against(comparator, kpi)&.round(2)
    change unless change.nil? || change.abs > PERCENTAGE_CHANGE_LIMIT
  end

  # Method to find the tagged KPI (comparator KPI on the same date, e.g. Budget/PriorYear).
  # Scoped to approved KPIs only — an unreviewed staging figure (still awaiting approval) isn't
  # a trustworthy thing to judge another KPI against, mirroring KpiWorkbookReader's approved_index
  # (the upload-time RAG warning has always been approved-only; this brings the live path in line).
  def find_tagged_kpi(tag_list)
    Kpi.approved.joins(:kpi_report)
       .where(
         name: name,
         portfolio_company_id: portfolio_company_id,
         'kpi_reports.as_of': kpi_report.as_of,
         'kpi_reports.tag_list': tag_list # Match by tag_list
       )
       .first
  end

  # The immediately-preceding report for this same KPI series — same name, same tag_list (so an
  # Actual is judged against a prior Actual, never a Budget row), same period cadence, most
  # recent as_of strictly before this one. No period arithmetic (no "1 month back" / "1 year
  # back" math) — whatever the previous row in the DB actually is, is "the prior period"; the
  # fund's own reporting cadence decides what dates exist, same philosophy as the tag-based
  # comparators. Approved-only, for the same reason as find_tagged_kpi above. See "Addendum:
  # prior-period comparator" in docs/modules/portfolio/kpis/kpi_rag_rules_redesign.md.
  #
  # This (and find_next_period_kpi/find_tagged_kpi below) filters by portfolio_company_id + name
  # without entity_id, which the index_kpis_on_pc_name_status composite covers (see
  # 20260924160000_add_sort_memory_fix_indexes.rb), narrowing the row count that ORDER BY
  # kpi_reports.as_of then has to filesort over - the ORDER BY itself can't be satisfied by any
  # index on kpis (as_of lives on the joined table), so this doesn't eliminate the filesort, only
  # shrinks it, same as the fetch_related_*_kpis case in kpi_cumulative.rb. Unlike that case and
  # find_or_create_kpi_report (kpi_workbook_reader.rb), no staging backtrace has actually landed on
  # this specific method - this composite is preventative hardening against the same query shape,
  # not a confirmed fix for an observed failure here.
  def find_prior_period_kpi
    Kpi.approved.joins(:kpi_report)
       .where(
         name: name,
         portfolio_company_id: portfolio_company_id,
         'kpi_reports.tag_list': kpi_report.tag_list,
         'kpi_reports.period': kpi_report.period
       )
       .where(kpi_reports: { as_of: ...kpi_report.as_of })
       .order('kpi_reports.as_of desc')
       .first
  end

  # The immediately-following report for this same KPI series — the mirror of
  # find_prior_period_kpi. Used only by recompute_dependent_rag_statuses! below: when a KPI's
  # value is saved, it may be the "prior period" that some later, already-saved KPI has been
  # missing, so that later one needs recomputing too. Deliberately NOT approved-scoped — unlike
  # find_prior_period_kpi/find_tagged_kpi this isn't looking up a comparator value, it's finding
  # the dependent KPI whose own status (approved or not — see recompute_rag_status!'s own guard)
  # needs re-evaluating now that its comparator may have changed.
  def find_next_period_kpi
    Kpi.joins(:kpi_report)
       .where(
         name: name,
         portfolio_company_id: portfolio_company_id,
         'kpi_reports.tag_list': kpi_report.tag_list,
         'kpi_reports.period': kpi_report.period
       )
       .where('kpi_reports.as_of > ?', kpi_report.as_of)
       .order('kpi_reports.as_of asc')
       .first
  end

  # Live RAG computation — see docs/modules/portfolio/kpis/kpi_rag_rules_redesign.md (Phase 3) and its
  # "Addendum: prior-period comparator". Recomputes whenever a value is saved, and cascades to
  # dependent KPIs so a comparator entered after the KPI it judges still triggers a status update:
  # a same-as_of sibling (e.g. Budget) for the tag-based comparators, or the next chronological
  # report for the prior-period comparator. RAG rules apply only to approved KPIs — an unapproved
  # (staging) row never gets a status of its own, and is never used as anyone else's comparator
  # (find_tagged_kpi/find_prior_period_kpi are approved-scoped) — a figure still pending review
  # shouldn't drive a flag anyone might act on before it's confirmed.
  #
  # Triggers on a value change (the normal case) OR on the status flip to approved: KpiApprover
  # approves a KPI by changing `status`, not `value` (unless it's overwriting an existing approved
  # record, which does change value) — without the status leg, a freshly-approved KPI would sit
  # with no RAG status until its value happened to change again, and approving a comparator (e.g.
  # Budget) wouldn't retroactively unlock the status of whatever it judges.
  #
  # Gated on `approved?` up front (not left to the callee) so an unapproved KPI's value being
  # entered or edited — the common case during import/staging, and every row of a bulk upload —
  # never even calls into recompute; it can't produce a status (see recompute_rag_status!'s own
  # belt-and-suspenders check) or affect anyone else's (recompute_dependent_rag_statuses!'s), so
  # there's nothing for either method to do until this row is approved.
  after_save :recompute_rag_status!, if: :rag_recompute_trigger?
  after_save :recompute_dependent_rag_statuses!, if: :rag_recompute_trigger?

  def rag_recompute_trigger?
    # approved? here reads the CURRENT (post-save) status, so this only ever fires while heading
    # into/staying in approved — there is deliberately no "revert to unapproved" leg here. That
    # transition now exists (see unapprove! below), but it clears/cascades rag_status itself
    # rather than relying on this after_save, so it doesn't need to trigger this leg too.
    approved? && (saved_change_to_value? || saved_change_to_status?)
  end

  def recompute_rag_status!
    # Unlike recompute_dependent_rag_statuses!'s approved? check below, this one is load-bearing,
    # not redundant with the after_save trigger: the cascade in that method calls this on OTHER
    # Kpi records (siblings/dependents), which the trigger's approved?-gating on self never saw.
    mapping = investor_kpi_mapping
    return unless approved? && mapping&.rag_configured?

    comparator_value = nil
    if mapping.rag_comparator_prior_period?
      comparator_value = find_prior_period_kpi&.value # nil (no prior report yet) => RagStatusEvaluator returns no status
    elsif mapping.rag_comparator_tag.present?
      comparator = find_tagged_kpi(mapping.rag_comparator_tag)
      comparator = nil if comparator&.id == id # comparing a value to itself isn't meaningful
      comparator_value = comparator&.value
    end

    new_status = RagStatusEvaluator.call(value: value, comparator_value: comparator_value, mapping: mapping)[:status]
    update_column(:rag_status, new_status) if new_status != rag_status
  end

  def recompute_dependent_rag_statuses!
    # Redundant with rag_recompute_trigger? above (only called via that after_save, on self) —
    # kept as a cheap, self-documenting guard against this method being called some other way in
    # the future without that gating already applied.
    return unless approved?

    cascade_dependent_rag_recompute!
  end

  # The actual dependent-recompute cascade, factored out of recompute_dependent_rag_statuses! so
  # unapprove! (below) can also trigger it without tripping that method's approved? guard — by
  # the time unapprove! calls this, self is already unapproved, which is exactly the case that
  # needs the cascade (siblings/next-period KPIs that were judging themselves against this KPI as
  # a comparator can no longer find it via find_tagged_kpi/find_prior_period_kpi, both of which
  # are approved-scoped, so they need to re-evaluate now that their comparator has disappeared).
  #
  # Both cascade shapes run unconditionally, rather than branching on this KPI's own
  # investor_kpi_mapping to pick one — same-as_of siblings (tag-based comparators, e.g. a
  # Budget row saved after its Actual) and the next chronological report (the PriorPeriod
  # comparator) are independent dependency shapes, and nothing guarantees every same-name KPI
  # row shares one InvestorKpiMapping (no DB uniqueness constraint enforces that). Each
  # dependent's own recompute_rag_status! call resolves correctness against ITS OWN mapping
  # regardless of why it got re-checked, so cascading broadly here is always safe — at worst,
  # one extra cheap query when a leg doesn't apply.
  def cascade_dependent_rag_recompute!
    Kpi.joins(:kpi_report)
       .where(name: name, portfolio_company_id: portfolio_company_id, 'kpi_reports.as_of': kpi_report.as_of)
       .where.not(id: id)
       .preload(:investor_kpi_mapping, :kpi_report) # what each sibling's recompute_rag_status! reads first
       .find_each(&:recompute_rag_status!)
    find_next_period_kpi&.recompute_rag_status!
  end

  # Reverts an approved KPI back to unapproved (e.g. an approver spots a mistake after the fact).
  # Clears rag_status on self — an unapproved figure isn't confirmed, so it shouldn't keep
  # showing a flag someone might act on (mirrors the reasoning in recompute_rag_status!'s
  # approved?-gating) — and cascades to dependents, since this KPI may have been serving as
  # someone else's approved comparator and now no longer qualifies.
  def unapprove!
    raise "KPI is not approved" unless approved?

    transaction do
      update!(status: :unapproved, rag_status: nil, approved_by_user_id: nil, approved_at: nil)
      cascade_dependent_rag_recompute!
    end
  end
end
