class CiWidget < ApplicationRecord
  belongs_to :owner, polymorphic: true
  belongs_to :investment_opportunity, optional: true
  belongs_to :entity

  validates :title, presence: true
  # L13 — the embed is a video player, never markup: one https iframe from an allowed host's /embed/ path
  validate :embed_script_is_allowed_embed

  include FileUploader::Attachment(:image)

  # L13 — hosts whose /embed/ player may be shown in a widget (YouTube only, by decision)
  EMBED_HOSTS = %w[www.youtube.com youtube.com www.youtube-nocookie.com youtube-nocookie.com].freeze

  # L13 — the player URL parsed out of the stored embed code, or nil when the stored code is not exactly
  # one allowed iframe. Views rebuild the iframe from this (CiWidgetHelper#ci_widget_embed) and never
  # echo the stored HTML, so a row saved before this validation still cannot run script (L13-X1..X4).
  def embed_src
    self.class.allowed_embed_src(embed_script)
  end

  # Parses embed code and returns its iframe src when it is one https iframe on EMBED_HOSTS under /embed/
  def self.allowed_embed_src(code)
    return nil if code.blank?

    # Exactly one element, and it is an iframe (no script, no second tag, no wrapper)
    elements = Nokogiri::HTML5.fragment(code.to_s.strip).children.reject { |node| node.text? && node.text.strip.empty? }
    return nil unless elements.size == 1 && elements.first.element? && elements.first.name == "iframe"

    # Its src is an https URL on an allowed host, pointing at the player (/embed/...)
    uri = URI.parse(elements.first["src"].to_s.strip)
    return nil unless uri.is_a?(URI::HTTPS) && EMBED_HOSTS.include?(uri.host&.downcase) && uri.path.to_s.start_with?("/embed/")

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  private

  # L13 — blank is fine; anything else must be a single allowed player iframe (L13-X1, L13-X2, L13-H1)
  def embed_script_is_allowed_embed
    return if embed_script.blank? || embed_src

    errors.add(:embed_script, "must be a single YouTube embed iframe (https://www.youtube.com/embed/...)")
  end
end
