# Overrides date_field to render a locale-formatted display input + calendar icon.
# The actual form submission uses a hidden ISO-format input so ActiveRecord and
# Date.local_parse both receive "YYYY-MM-DD" regardless of the user's locale.
class LocaleDateFormBuilder < ActionView::Helpers::FormBuilder
  def date_field(method, options = {})
    raw_value   = options.key?(:value) ? options.delete(:value) : object&.public_send(method)
    date        = coerce_to_date(raw_value)
    css_class   = options.delete(:class) || "form-control"
    # Derive id using the same sanitization Rails applies: delete ']', replace non-word chars with '_'.
    # This handles nested builders where object_name is e.g. "individual_kyc[properties]".
    sanitized_name = object_name.to_s.delete("]").gsub(/[^a-zA-Z0-9_:.-]/, "_").gsub(/_+/, "_").gsub(/_\z/, "")
    field_id       = options.delete(:id) || (sanitized_name.blank? ? method.to_s : "#{sanitized_name}_#{method}")
    i18n_format  = I18n.t("date.formats.default")
    # Human-readable version of the strftime format, used as placeholder and tooltip
    format_hint  = i18n_format.gsub("%d", "dd").gsub("%m", "mm").gsub("%Y", "yyyy")
    locale_val   = date ? @template.l(date) : ""
    iso_val      = date ? date.iso8601 : ""

    # Extract interactive/constraint attributes — they belong on the visible and picker inputs.
    # required/disabled on a type="hidden" input are ignored by browsers; min/max have no
    # meaning there either. We apply them to the display input and the native picker instead.
    disabled = options.delete(:disabled)
    required = options.delete(:required)
    readonly = options.delete(:readonly)
    min_val  = options.delete(:min)
    max_val  = options.delete(:max)
    # Deep-merge so the caller's data attributes survive alongside our Stimulus target marker
    caller_data = options.delete(:data) || {}
    hidden_data = caller_data.deep_merge({ "locale-date-target": "hidden" })

    @template.content_tag(:div, class: "input-group",
      data: { controller: "locale-date tooltip", "locale-date-format-value": i18n_format }
    ) do
      # Display-only text input — has the id so Capybara/tests can find it; no name, never submitted
      display = @template.tag.input(
        type:                "text",
        id:                  field_id,
        value:               locale_val,
        placeholder:         format_hint,
        title:               "Enter date in #{format_hint} format",
        "data-bs-toggle":    "tooltip",
        "data-bs-placement": "top",
        class:               css_class,
        autocomplete:        "off",
        disabled:            disabled,
        required:            required,
        readonly:            readonly,
        data:                {
          "locale-date-target": "display",
          action: "input->locale-date#inputChanged blur->locale-date#inputBlurred"
        }
      )

      # Hidden ISO input — carries the actual value for form submission; id suppressed (lives on display)
      hidden = hidden_field(method, options.merge(
        id:    nil,
        value: iso_val,
        data:  hidden_data
      ))

      # Calendar icon — clicking calls openPicker() which calls showPicker() on the hidden date input
      icon_span = @template.content_tag(:span, class: "input-group-text",
        style: "cursor:pointer;",
        data:  { action: "click->locale-date#openPicker" }
      ) do
        @template.concat @template.tag.i(class: "fas fa-calendar", style: "pointer-events:none;")
        # Zero-size invisible input — only purpose is to receive showPicker() and fire change events
        @template.concat @template.tag.input(
          type:     "date",
          value:    iso_val,
          min:      min_val,
          max:      max_val,
          disabled: disabled,
          style:    "position:absolute; width:0; height:0; opacity:0; overflow:hidden;",
          data:     { "locale-date-target": "picker", action: "change->locale-date#pickerChanged" }
        )
      end

      display + hidden + icon_span
    end
  end

  private

  def coerce_to_date(value)
    return nil if value.blank?
    return value.to_date if value.is_a?(Date) || value.is_a?(Time)
    Date.local_parse(value.to_s)
  rescue StandardError
    nil
  end
end
