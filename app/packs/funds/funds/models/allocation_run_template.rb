# One fund plus the parameters it is always run with on the allocation screen — everything
# except the period, which is supplied when the template (or a group containing it) is run.
#
# A template is usually created with "Save as allocation run template" from a past
# AllocationRun (see .from_allocation_run), or from scratch with the same form fields.
# It may belong to any number of AllocationRunTemplateGroups; it cannot be deleted while
# it is still a member of one (decision 17 in docs/modules/allocation/allocation_run_sequences.md).
class AllocationRunTemplate < ApplicationRecord
  # nil rule_for means "Both" — same convention as AllocationRun / the allocation screen.
  RULE_FOR_OPTIONS = %w[Accounting Reporting].freeze
  STATEMENT_FOR_OPTIONS = ["Commitment", "Investing Entity"].freeze
  # Document owner tags that count as investor statement documents on a fund.
  STATEMENT_DOCUMENT_TAGS = ["SOA Template", "Investor Statement Template"].freeze

  belongs_to :entity
  belongs_to :user
  belongs_to :fund
  # A reference to the document itself, not its name (decision 15). Document is soft-deleted,
  # so a deleted or renamed-away document simply reads back as nil and the pre-run check blocks.
  belongs_to :statement_document, class_name: "Document", optional: true

  # restrict_with_error: a template inside a group must be removed from the group first.
  has_many :group_items, class_name: "AllocationRunTemplateGroupItem", dependent: :restrict_with_error,
                         inverse_of: :allocation_run_template
  has_many :allocation_run_template_groups, through: :group_items
  # History outlives the template — items keep the template name and fund as a snapshot.
  has_many :allocation_group_run_items, dependent: :nullify

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :entity_id }
  validates :rule_for, inclusion: { in: RULE_FOR_OPTIONS }, allow_blank: true
  validates :statement_for, inclusion: { in: STATEMENT_FOR_OPTIONS }, allow_blank: true
  validates :statement_for, presence: true, if: :generate_soa?
  validate :fund_belongs_to_entity
  validate :statement_document_belongs_to_fund
  validate :does_something

  scope :ordered, -> { order(:name) }

  # Builds an unsaved template pre-filled from a past run. The run only stores the statement
  # document's name, so the document is resolved on the fund's current templates by name;
  # the caller (the "Save as template" form) then only has to supply a name.
  def self.from_allocation_run(run)
    template = new(
      entity_id: run.entity_id, fund_id: run.fund_id,
      rule_for: run.rule_for.presence, tag_list: run.tag_list,
      # allocation_runs.run_allocations/generate_soa/fund_ratios are nullable columns (a run
      # created directly without those keys, old or new, stores NULL there), but the
      # corresponding template columns are NOT NULL — copying a nil through as-is would fail
      # the insert. Default nil the same way the allocation screen's own checkboxes do:
      # unchecked, i.e. false, except run_allocations which defaults on like the column itself.
      # rubocop:disable Style/RedundantCondition -- `run.run_allocations || true` would turn an
      # explicit false into true, which is exactly the bug being avoided; only nil should map
      # to the default. generate_soa/fund_ratios default to false, where that rewrite happens
      # to be safe, but the ternary form is kept for all three so they read the same way.
      run_allocations: run.run_allocations.nil? ? true : run.run_allocations,
      generate_soa: run.generate_soa.nil? ? false : run.generate_soa,
      statement_for: run.statement_for, fund_ratios: run.fund_ratios.nil? ? false : run.fund_ratios
      # rubocop:enable Style/RedundantCondition
    )
    if run.template_name.present?
      template.statement_document = run.fund.documents.templates
                                       .where(owner_tag: STATEMENT_DOCUMENT_TAGS, name: run.template_name)
                                       .order(id: :desc).first
    end
    template
  end

  # Formula tags as an array — the column is comma-separated to match allocation_runs.tag_list.
  def tags
    tag_list.to_s.split(",").map(&:strip).compact_blank
  end

  def tags=(values)
    self.tag_list = Array(values).map(&:strip).compact_blank.uniq.join(",").presence
  end

  # Tags on this template that no longer exist in the entity's formula tag list. A removed
  # tag would make the run silently execute fewer formulas, so the pre-run check treats
  # any unknown tag as a blocker (decision 16).
  def unknown_tags
    known = entity.entity_setting&.formula_tag_list.to_s.split(",").map(&:strip).compact_blank
    tags - known
  end

  # Human label for the formula scope, as the allocation screen shows it.
  def scope_label
    rule_for.presence || "Both"
  end

  # Statement documents currently available on the fund, for the form's select.
  def available_statement_documents
    fund.documents.templates.where(owner_tag: STATEMENT_DOCUMENT_TAGS).order(:name)
  end

  # Keyword arguments for AccountEntryAllocationJob / AccountEntryAllocation::Engine, exactly as
  # FundsController#allocate builds them for a manual run.
  def engine_options(user_id:, allocation_run_id:)
    {
      rule_for: rule_for.presence, tag_list: tag_list.presence, run_allocations:, explain:, user_id:,
      generate_soa:, statement_for: (statement_for if generate_soa), template_id: (statement_document_id if generate_soa),
      fund_ratios:, sample:, allocation_run_id:
    }
  end

  # Attributes for the AllocationRun record a run of this template creates — one new record
  # per run, exactly as a manual run does today.
  def allocation_run_attributes(start_date:, end_date:, user_id:)
    {
      entity_id:, fund_id:, start_date:, end_date:, user_id:,
      run_allocations:, generate_soa:, statement_for: (statement_for if generate_soa),
      template_name: (statement_document&.name if generate_soa), fund_ratios:,
      rule_for: rule_for.presence, tag_list: tag_list.presence
    }
  end

  def to_s
    name
  end

  private

  def fund_belongs_to_entity
    return if fund.blank? || fund.entity_id == entity_id

    errors.add(:fund_id, "must belong to the same entity as the template")
  end

  # Only a statement template that lives on this fund may be selected.
  def statement_document_belongs_to_fund
    return if statement_document.blank?
    return if statement_document.owner_type == "Fund" && statement_document.owner_id == fund_id &&
              statement_document.template? && STATEMENT_DOCUMENT_TAGS.include?(statement_document.owner_tag)

    errors.add(:statement_document_id, "must be an investor statement document on the selected fund")
  end

  # A template that neither runs formulas nor generates statements would do nothing.
  def does_something
    return if run_allocations? || generate_soa?

    errors.add(:base, "Select at least one of Run allocation formulas or Generate investor statements")
  end
end
