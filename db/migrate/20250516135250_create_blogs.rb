class CreateBlogs < ActiveRecord::Migration[8.0]
  def change
    create_table :blogs do |t|
      t.string :title
      t.string :tag_list, limit: 100

      t.timestamps
    end
  end
end
