# frozen_string_literal: true

# @description Concern for models that can have an NDA configuration attached.
#   Provides the polymorphic has_one :nda_config association and the nda_required?
#   predicate. Include in any model that should support NDA gating.
#
# @example
#   class Folder < ApplicationRecord
#     include WithNda
#   end
#
# @see NdaConfig
# @see WithDataRoom — similar pattern for Data Room folder creation
module WithNda
  extend ActiveSupport::Concern

  included do
    # Changed: Polymorphic NDA config association via concern.
    # Why: Decouples NDA from Folder — any model (Folder, InvestmentOpportunity, etc.)
    # can include WithNda to gain NDA support without duplicating the association.
    has_one :nda_config, as: :owner, class_name: "NdaConfig", dependent: :destroy
  end

  # @return [Boolean] Whether this record requires NDA acceptance for access.
  def nda_required?
    nda_config&.enabled? || false
  end
end
