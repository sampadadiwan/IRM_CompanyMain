class AddDefaultFoldersToFund < ActiveRecord::Migration[8.0]
  FOLDERS = ["Reports", "Private Documents"].freeze
  def up
    Fund.all.each do |fund|
      puts "Creating default folders for fund: #{fund.name}"
      # Create default folders for each fund
      FOLDERS.each do |name|
        fund.document_folder.children.create!(name:, entity_id: fund.entity_id, private: true) if fund.document_folder.children.where(name:, entity_id: fund.entity_id).empty?
      end
    end
  end

  def down
    Fund.all.each do |fund|
      puts "Removing default folders for fund: #{fund.name}"
      # Remove default folders for each fund
      FOLDERS.each do |name|
        fund.document_folder.children.where(name:, entity_id: fund.entity_id).destroy_all
      end
    end
  end
end
