# frozen_string_literal: true

class TearSheetPresentation < ApplicationRecord
  belongs_to :portfolio_report_extract
  belongs_to :entity

  validates :content_html, presence: true
end
