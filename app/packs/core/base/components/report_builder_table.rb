class ReportBuilderTable < ViewComponent::Base
  def initialize(report:, columns:, rows:, q:, turbo_frame: "report_builder_view")
    super()
    @report = report
    @columns = columns
    @rows = rows
    @q = q
    @turbo_frame = turbo_frame
  end

  private

  def column_label(col)
    col.respond_to?(:label) ? col.label : col[:label]
  end

  def column_key(col)
    col.respond_to?(:key) ? col.key : col[:key]
  end

  def format_value(val, key)
    if val.is_a?(Date) || val.is_a?(Time) || val.is_a?(DateTime)
      l(val)
    elsif val.is_a?(Numeric) && (key.include?("num-col") || key.include?("amount") || key.include?("formula"))
      number_with_precision(val, precision: 2, delimiter: ",")
    else
      val
    end
  end
end
