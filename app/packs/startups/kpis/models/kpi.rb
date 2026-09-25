class Kpi < ApplicationRecord
  include WithCustomField
  include ForInvestor
  include Trackable.new(on: %i[create update], audit_fields: %i[value display_value notes percentage_change])
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
  belongs_to :investor_kpi_mapping, optional: true
  belongs_to :approved_by, class_name: "User", foreign_key: :approved_by_user_id, optional: true

  validates :name, :value, presence: true

  validates :name, length: { maximum: 100 }
  validates :notes, length: { maximum: 255 }
  validates :display_value, length: { maximum: 30 }
  validates :source, length: { maximum: 100 }, allow_blank: true

  validates :status, presence: true
  validates :name, uniqueness: { scope: %i[kpi_report_id portfolio_company_id status deleted_at] }, if: -> { approved? }

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

  def self.recompute_percentage_change(kpis, force: false)
    # Group KPIs by period, name, and tag_list to ensure percentage is only computed between comparable KPIs
    kpis.group_by { |kpi| [kpi.kpi_report.period, kpi.name, kpi.kpi_report.tag_list] }.each_value do |grouped_kpis|
      grouped_kpis.sort_by { |kpi| kpi.kpi_report.as_of }.each_cons(2) do |current_kpi, next_kpi|
        next unless force || next_kpi.percentage_change.nil? || next_kpi.percentage_change.zero?

        next_kpi.percentage_change = if current_kpi.value.zero?
                                       # if the divisor (the current) is 0, the percentage is infinity but we cant store that so keeping it nil
                                       nil
                                     else
                                       ((next_kpi.value - current_kpi.value) / current_kpi.value) * 100
                                     end
        next_kpi.save
      end
    end
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
