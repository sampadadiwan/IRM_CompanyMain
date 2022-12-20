class AddTagListToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :tag_list, :string, limit: 60
  end

  Document.all.each do |doc|
    doc.tag_list = doc.tags.map{|tag| tag.name}.join(", ")
    doc.save
  end
end
