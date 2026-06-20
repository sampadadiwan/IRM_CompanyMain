module WorkflowTemplatesHelper
  # Returns ordered User records for the current entity, used to populate
  # actor select menus in template/step forms.
  def entity_users_for_select
    User.where(entity_id: current_user.entity_id).order(:first_name, :last_name)
  end
end
