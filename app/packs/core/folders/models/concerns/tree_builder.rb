module TreeBuilder
  extend ActiveSupport::Concern

  def self.included(object)
    object.extend(ClassMethods)
  end

  module ClassMethods
    def build_tree(folders, tree = {}, map = {})
      parent = nil

      # puts "########### #{tree}"

      folders.each do |f|
        next unless map[f.id].nil?

        node = { details: f, children: {} }
        map[f.id] = node
        if map[f.parent_folder_id].nil?
          tree[f.id] = node
          parent = node
        else
          parent = map[f.parent_folder_id]
          parent[:children][f.id] = node
        end
      end

      # Rails.logger.debug { "########### #{tree}" }
      [tree, map]
    end

    def build_full_tree(folders)
      Rails.logger.debug folders.collect(&:id)
      tree, map = all_parents(folders)
      build_tree(folders, tree, map)
    end

    def all_parents(folders)
      path_ids = folders.collect(&:path_ids).flatten
      parent_folders = Folder.where(id: path_ids).distinct.order(level: :asc)
      build_tree(parent_folders)
    end
  end
end
