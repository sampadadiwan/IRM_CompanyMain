module EntityTouch
  extend ActiveSupport::Concern

  included do
    after_commit :touch_entity
  end

  def touch_entity
    entity.touch
  end
  # rubocop:enable Rails/SkipsModelValidations
end
