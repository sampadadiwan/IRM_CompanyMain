# The Users list's rich cells, called by the column keys of User::LIST_COLUMNS / GRID_COLUMNS through
# RansackTableRow (openspec/changes/grid-columns-inline-settings — D21). Same output the hand-built row had.
class UserDecorator < ApplicationDecorator
  # The first name, linking to the user's page when the viewer may open it. An advisor switched in from another
  # company is listed, but their page belongs to their own firm (R5).
  def first_name_link
    h.policy(object).show? ? h.link_to(object.first_name, h.user_path(object.id)) : object.first_name
  end

  # The role names, printed as the list printed them (e.g. ["company_admin", "employee"])
  def role_names
    object.roles.collect(&:name)
  end
end
