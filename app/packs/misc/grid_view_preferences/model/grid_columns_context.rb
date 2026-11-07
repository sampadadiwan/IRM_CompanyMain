# What a table showed and for whom, carried by the columns icon to the side panel and back as a signed, expiring
# token. Each page picks its own standard columns and column rules in its view, so the panel cannot rebuild them
# in another request, and the browser must not be trusted to name them.
# openspec/changes/grid-columns-inline-settings — design D2, D6; worked examples H3, E2, E3, E11, X5, X9
class GridColumnsContext
  PURPOSE = :grid_columns
  # X5 — an older token is refused; reopening the page renders a fresh icon
  EXPIRY = 12.hours

  attr_reader :model_class, :entity, :report, :shown, :required, :excluded, :explicit_form_type

  # @param model_class [Class] the table's model (defines STANDARD_COLUMNS)
  # @param entity [Entity] the firm whose columns the table read
  # @param report [Report, nil] the open report, only when the table showed the report's own columns
  # @param shown [Array<Array(String, String)>] the columns shown, in order, as [label, key] (with any "; css")
  # @param required [Array<String>] keys the page always adds (E2), cleaned
  # @param excluded [Array<String>] saved keys the page hides (E3), cleaned
  # @param form_type [FormType, nil] D19/E26 — the form type Configure Grids was opened for (a model may have several)
  def initialize(model_class:, entity:, shown:, report: nil, form_type: nil, required: [], excluded: [])
    @model_class = model_class
    @entity = entity
    @report = report
    @explicit_form_type = form_type
    @shown = shown.map { |label, key| [label.to_s, key.to_s] }
    @required = Array(required).map { |key| GridColumnOptions.clean(key) }
    @excluded = Array(excluded).map { |key| GridColumnOptions.clean(key) }
  end

  # The form type the table header reads columns from: the lowest id of that name, so the header and the save
  # always agree when a model allows several form types (D6)
  def self.form_type_for(entity, model_class)
    entity.form_types.where(name: model_class.name).order(:id).first
  end

  def form_type
    @form_type ||= explicit_form_type || self.class.form_type_for(entity, model_class)
  end

  # D19 — Configure Grids for a form type or a report: its saved columns, or the record type's standard ones.
  # nil when the owner's record type has no standard columns.
  def self.for_owner(owner)
    model_class = (owner.is_a?(Report) ? owner.model : owner.name).to_s.safe_constantize
    return unless model_class.is_a?(Class) && model_class < ApplicationRecord && model_class.const_defined?(:STANDARD_COLUMNS)

    report = owner if owner.is_a?(Report)
    form_type = owner if owner.is_a?(FormType)
    new(model_class:, entity: owner.entity, report:, form_type:, shown: model_class::STANDARD_COLUMNS.reject { |k, _| k.blank? }.to_a)
  end

  # Whose columns the panel edits: the open report when it has its own (H5), else the firm's form type, else a
  # new form type created on the first save (H4)
  def owner
    @owner ||= report || form_type || FormType.new(entity:, name: model_class.name)
  end

  # E8/X4 — a key the table showed when the panel opened (so a first save may store the page's standard columns)
  def shown_key?(key)
    clean = GridColumnOptions.clean(key)
    shown.any? { |_label, shown_key| GridColumnOptions.clean(shown_key) == clean }
  end

  # The signed token for the icon's link and the panel's form
  def to_token
    self.class.verifier.generate(payload, purpose: PURPOSE, expires_in: EXPIRY)
  end

  # Rebuilds a context from its token. X5 — an altered or expired token, X9 — a model without standard columns,
  # and a report outside the user's scope (X3) are all "not found". The firm and role are checked by the policy.
  # @raise [ActiveRecord::RecordNotFound]
  def self.from_token(token, user:)
    data = begin
      verifier.verified(token.to_s, purpose: PURPOSE)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
      # A malformed token is treated like an altered one
      nil
    end
    raise ActiveRecord::RecordNotFound, "Columns panel expired or altered" unless data.is_a?(Hash)

    # X9 — only a concrete model of this app with standard columns
    model_class = ApplicationRecord.model_class_from_param(data["m"])
    raise ActiveRecord::RecordNotFound, "Unknown record type" unless model_class&.const_defined?(:STANDARD_COLUMNS)

    entity = Entity.find(data["e"])
    # X3, X7 — the report is loaded through the user's report scope; editing rights are the policy's
    report = (ReportPolicy::Scope.new(user, Report).resolve.find(data["r"]) if data["r"].present?)
    # E26 — the form type Configure Grids was opened for, within the same firm
    form_type = (entity.form_types.find(data["f"]) if data["f"].present?)
    new(model_class:, entity:, report:, form_type:, shown: data["s"], required: data["q"], excluded: data["x"])
  end

  def self.verifier
    Rails.application.message_verifier(PURPOSE)
  end

  private

  # Ids and strings only
  def payload
    { "m" => model_class.name, "e" => entity.id, "r" => report&.id, "f" => explicit_form_type&.id, "s" => shown,
      "q" => required, "x" => excluded }
  end
end
