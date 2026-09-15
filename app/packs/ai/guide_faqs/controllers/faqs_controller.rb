# frozen_string_literal: true

# All FAQs from every user guide on one searchable page, for anyone who can read the guides.
class FaqsController < ApplicationController
  # Same website-styled shell as the user guide pages.
  layout "guide"

  def index
    authorize :user_guide, :index?
    # The page lists guide content (Markdown files and published FAQ entries), not tenant records.
    skip_policy_scope
    @title = "FAQs"
    @guides = FaqCatalog.new.guides
    @faq_count = @guides.sum { |guide| guide.items.size }
  end
end
