class AddThoughtSignatureToToolCall < ActiveRecord::Migration[8.0]
  def change
    add_column :tool_calls, :thought_signature, :text
  end
end
