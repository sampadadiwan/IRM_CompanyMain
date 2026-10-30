class EsignLog < ApplicationRecord
  belongs_to :entity
  belongs_to :document

  # Columns that hold a time-keyed history written through #append_event. The older columns
  # (webhook_data, manual_update_data) keep their inline code in the callers.
  APPENDABLE_COLUMNS = %i[sdk_events].freeze

  # Adds one entry to a history column, keeping the earlier ones. The row is locked for the read-modify-write
  # so two near-simultaneous reports (a retry click) do not lose an entry. Duplicates are acceptable.
  # Worked example E20, X10 — openspec/changes/embedded-esign-digio/design.md#worked-examples
  # @param column [Symbol] one of APPENDABLE_COLUMNS
  # @param payload [Hash] what to record
  # @return [EsignLog]
  # @raise [ArgumentError] when the column is not appendable
  def append_event(column, payload)
    column = column.to_sym
    raise ArgumentError, "#{column} is not an appendable esign log column" unless APPENDABLE_COLUMNS.include?(column)

    with_lock do
      entries = self[column].is_a?(Hash) ? self[column].dup : {}
      entries[Time.zone.now.iso8601(6)] = payload
      update!(column => entries)
    end
    self
  end
end
