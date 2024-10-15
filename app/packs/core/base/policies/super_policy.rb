class SuperPolicy < ApplicationPolicy
  # Super has access to everything
  def method_missing(method_name, *args, &)
    return true if user.has_cached_role?(:super) || user.has_cached_role?(:support)

    super
  end

  def respond_to_missing?(method_name, include_private = false)
    return true if user.has_cached_role?(:super) || user.has_cached_role?(:support)

    super
  end
end
