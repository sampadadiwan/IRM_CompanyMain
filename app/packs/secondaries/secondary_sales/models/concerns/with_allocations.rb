module WithAllocations
  extend ActiveSupport::Concern

  included do
    has_many :allocations, dependent: :destroy
  end

  def transaction_documents
    Document.where(owner_id: allocations.verified.pluck(:id), owner_type: 'Allocation')
  end
end
