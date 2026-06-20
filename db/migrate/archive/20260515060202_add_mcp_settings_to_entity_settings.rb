# frozen_string_literal: true

# Adds MCP (AI Client Integration) governance fields to entity_settings.
class AddMcpSettingsToEntitySettings < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:entity_settings, :mcp_enabled)
      add_column :entity_settings, :mcp_enabled, :boolean, default: false, null: false
    end
    unless column_exists?(:entity_settings, :mcp_allowed_roles)
      add_column :entity_settings, :mcp_allowed_roles, :string, default: '["employee"]'
    end
    unless column_exists?(:entity_settings, :mcp_allowed_clients)
      add_column :entity_settings, :mcp_allowed_clients, :string, default: '[]'
    end
  end
end
