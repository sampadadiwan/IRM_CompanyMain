class ReportBuilderDynamicColumn
  attr_reader :key, :data_type

  def initialize(key:, label:, data_type: "Decimal")
    @key       = key
    @_label    = label
    @data_type = data_type
  end

  def label = @_label || key
  def name  = @_label || key

  def pivot? = key.include?("__pivot__")
end
