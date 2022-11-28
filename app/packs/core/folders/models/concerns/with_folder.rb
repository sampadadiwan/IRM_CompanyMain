module WithFolder
  extend ActiveSupport::Concern

  included do
    # after_create :setup_folder_details
    has_many :folders, as: :owner, dependent: :destroy

    def self.upgrade_folders
      %w[Investor InvestorKyc Fund CapitalCall CapitalCommitment InvestmentOpportunity ExpressionOfInterest Approval SecondarySale Offer Interest Deal DealInvestor DealActivity OptionPool Excercise].each do |model|
        model.constantize.all.each(&:setup_folder_details)
      end
    end
  end

  def document_folder
    # Since the initial docs are created before the parent_folder is created
    # store them in the root folder. Move them to the main_folder post creation
    folder = Folder.where(full_path: folder_path).last
    folder ||= setup_folder_from_path(folder_path)
    folder
  end

  def setup_folder_from_path(path)
    folder = nil
    parent = entity.root_folder
    path_list = path.split("/")
    path_list.each_with_index do |folder_name, idx|
      next if folder_name.blank?

      folder = parent.children.where(name: folder_name).first
      owner = idx == path_list.length - 1 ? self : nil
      folder = parent.children.create(name: folder_name, entity_id:, folder_type: :system, owner:) if folder.nil?
      parent = folder
    end
    folder
  end
end
