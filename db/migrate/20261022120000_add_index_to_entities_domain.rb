# WithAuthentication#set_current_entity looks up Entity.where(domain: request.domain) on every request
# to a tenant's own mapped domain (anything that isn't BASE_DOMAIN). entities.domain had no index, so
# each of those requests scanned the entities table.
class AddIndexToEntitiesDomain < ActiveRecord::Migration[8.1]
  def change
    add_index :entities, :domain
  end
end
