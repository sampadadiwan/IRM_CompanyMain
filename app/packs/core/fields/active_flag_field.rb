require "administrate/field/base"

class ActiveFlagField < Administrate::Field::Base
  def to_s
    data
  end
end
