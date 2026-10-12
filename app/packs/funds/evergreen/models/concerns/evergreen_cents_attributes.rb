# Major-unit accessors over *_cents decimal columns, for forms and uploads
# (e.g. min_holding <-> min_holding_cents). Blank input stays nil, so class overrides can be cleared.
module EvergreenCentsAttributes
  extend ActiveSupport::Concern

  class_methods do
    def cents_attribute(*names)
      names.each do |name|
        define_method(name) do
          cents = self["#{name}_cents"]
          cents && (cents.to_d / 100)
        end

        define_method("#{name}=") do |value|
          self["#{name}_cents"] = value.blank? ? nil : (value.to_s.delete(",").to_d * 100)
        end
      end
    end
  end
end
