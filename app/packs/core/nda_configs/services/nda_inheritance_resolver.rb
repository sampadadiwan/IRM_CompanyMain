# frozen_string_literal: true

# Module 5 — NDA Inheritance: Batch resolver for folder tree rendering.
#
# Takes a collection of pre-loaded folders (with :nda_config eager-loaded) and
# resolves every folder's effective NDA config in a single in-memory pass —
# no additional DB queries. Used by the Documents page tree view to avoid N+1
# when rendering lock icons on 20-50+ folders.
#
# Single-folder contexts (Turbo Stream caret updates, modal) use the model's
# own effective_nda_config method instead — only 1-2 ancestor hops there.
#
# Changed: Moved from core/folders/services/ to core/nda_configs/services/.
# Why: NDA inheritance resolution is NDA-domain logic, not folder-domain.
#
# @example Usage in DocumentHelper#get_tree_view_folders
#   folders = Folder.where(entity: entity).includes(:nda_config).arrange
#   resolver = NdaInheritanceResolver.new(folders)
#   resolver.effective_config_for(folder) # => NdaConfig or nil
#   resolver.source_folder_for(folder)    # => Folder or nil
#
# @see Folder#effective_nda_config
class NdaInheritanceResolver
  # @param arranged_folders [Hash] Nested hash from Folder.arrange (ancestry gem format)
  #   where keys are Folder instances and values are hashes of children.
  #   Folders must have :nda_config association pre-loaded.
  def initialize(arranged_folders)
    @results = {}
    resolve_tree(arranged_folders, nil, nil)
  end

  # @param folder [Folder] A folder from the resolved tree.
  # @return [NdaConfig, nil] The effective NDA config for this folder.
  def effective_config_for(folder)
    @results.dig(folder.id, :config)
  end

  # @param folder [Folder] A folder from the resolved tree.
  # @return [Folder, nil] The folder that owns the effective NDA config.
  def source_folder_for(folder)
    @results.dig(folder.id, :source)
  end

  private

  # Recursively walks the arranged tree top-down, passing the inherited config
  # and source folder down to children. Each folder's mode determines whether
  # it uses its own config, inherits, or opts out.
  #
  # @param arranged [Hash] Current level of the arranged tree.
  # @param inherited_config [NdaConfig, nil] Config inherited from parent.
  # @param inherited_source [Folder, nil] Folder that owns the inherited config.
  def resolve_tree(arranged, inherited_config, inherited_source)
    arranged.each do |folder, children|
      config, source = resolve_single(folder, inherited_config, inherited_source)
      @results[folder.id] = { config: config, source: source }

      resolve_tree(children, config, source) if children.present?
    end
  end

  # Resolves a single folder's effective NDA based on its inheritance mode.
  #
  # @param folder [Folder] The folder to resolve.
  # @param inherited_config [NdaConfig, nil] Config from the nearest ancestor with mode "own".
  # @param inherited_source [Folder, nil] The ancestor that owns inherited_config.
  # @return [Array<(NdaConfig, Folder), (nil, nil)>]
  def resolve_single(folder, inherited_config, inherited_source)
    case folder.nda_inheritance_mode
    when "own"
      [folder.nda_config, folder]
    when "opt_out"
      [nil, nil]
    else
      [inherited_config, inherited_source]
    end
  end
end
