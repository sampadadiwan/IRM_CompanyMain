class RansackerAmounts < Module
  extend ActiveSupport::Concern

  def initialize(fields: {})
    super()
    @fields = fields
  end

  def included(base)
    fields = @fields
    base.class_eval do
      # This creates a ransacker for each field in the fields hash, typically for amounts
      fields.each do |field|
        ransacker field.to_sym, formatter: proc { |v| v.to_d } do |_parent|
          Arel.sql("#{table_name}.#{field}_cents / 100.0")
        end
      end
    end
  end
end
