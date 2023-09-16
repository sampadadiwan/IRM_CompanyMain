class AddDisplayOnPageToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :display_on_page, :string, limit: 6 # max 6 as `custom` is 6 letters
  end
end
