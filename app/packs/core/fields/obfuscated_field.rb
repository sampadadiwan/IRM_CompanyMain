require "administrate/field/base"

class ObfuscatedField < Administrate::Field::Base
  def to_s
    data
  end
end
