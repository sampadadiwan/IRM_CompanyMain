class QuickLinkStep < ApplicationRecord
  belongs_to :quick_link
  acts_as_list scope: :quick_link
end
