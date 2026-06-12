class Favorite < ApplicationRecord
  belongs_to :user

  validates :title, presence: true
  validates :url, presence: true
  validates :url, uniqueness: { scope: :user_id }

  after_commit :touch_user

  def touch_user
    user.touch
  end
end
