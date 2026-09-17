# frozen_string_literal: true

# FAQ Manager permissions. Any CapHive support user may create, edit, publish and archive
# (docs/ai/guide_faq_search_prd.md §8 D1); only drafts may be deleted.
class FaqEntryPolicy < GuideFaqsStaffPolicy
  def destroy?
    staff? && record.is_a?(FaqEntry) && record.draft?
  end

  def publish?
    staff?
  end

  def archive?
    staff?
  end

  def verify?
    staff?
  end

  def import?
    staff?
  end

  class Scope < GuideFaqsStaffPolicy::Scope
  end
end
