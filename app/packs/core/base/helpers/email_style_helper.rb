# frozen_string_literal: true

# Shared HTML building blocks for rich transactional email — the banner, stat tiles,
# section headings, tables, callouts and footer that give every outgoing report and
# digest the same look.
#
# Lives in core because three packs need it: the support agent mailers (ai), the fund
# stats and data quality mailers (funds), and the weekly task digest (core). It used to
# live in ai/support_agents as SupportAgentEmailHelper, which meant funds and core both
# had to reach across a pack boundary for it; that module now just includes this one.
#
# The sa_ prefix is a leftover from that origin. Kept deliberately: renaming would touch
# ~200 call sites across a dozen mailer views for no behaviour change.
#
# Usage in a mailer:   helper EmailStyleHelper
# Usage in a template: <%= sa_banner(title: "Weekly Tasks", label: "7 delayed", tone: :danger) %>
#
# Everything here is inline-styled and table-based on purpose — mail clients strip
# <style> blocks unpredictably and Outlook has no flexbox or grid.
module EmailStyleHelper
  # ── Colour palette ──────────────────────────────────────────────────────
  SA_COLORS = {
    success: { text: "#2e7d32", bg: "#e8f5e9", border: "#2e7d32" },
    warning: { text: "#e65100", bg: "#fff3e0", border: "#fb8c00" },
    danger: { text: "#c62828", bg: "#ffebee", border: "#ef9a9a" },
    info: { text: "#1565c0", bg: "#e3f2fd", border: "#90caf9" },
    muted: { text: "#757575", bg: "#f5f5f5", border: "#bdbdbd" }
  }.freeze

  # ── Light variant ────────────────────────────────────────────────────────
  # The same hues at lower saturation, plus barely-there tints. Used by the
  # sa_light_* builders below, where colour marks meaning and the neutral scale
  # carries the layout — instead of every block being a filled box.
  #
  # Opt-in: the sa_* builders above keep their solid look, so adding this changed
  # no existing mailer. New reports should prefer the light set.
  SA_LIGHT = {
    success: { text: "#2f855a", tint: "#f0f9f4" },
    info: { text: "#2b6cb0", tint: "#eff6fd" },
    danger: { text: "#c53030", tint: "#fdf2f2" },
    warning: { text: "#b7791f", tint: "#fffaf0" },
    muted: { text: "#718096", tint: "#f7f9fa" }
  }.freeze

  # Neutral scale. ink/body/muted/faint are a type hierarchy, not five greys picked
  # at random — headings, values, labels, and metadata in that order.
  SA_NEUTRAL = {
    ink: "#1f2933",
    body: "#52606d",
    muted: "#7b8794",
    faint: "#9aa5b1",
    rule: "#dfe3e8",
    hairline: "#edf0f2"
  }.freeze

  # ── Banner ───────────────────────────────────────────────────────────────
  # Large coloured header block at the top of the email.
  # title:    small uppercase label above the main label
  # label:    large bold display text (e.g. "All Clear", "100%")
  # subtitle: small text below the label
  # tone:     :success | :warning | :danger | :info | :muted
  def sa_banner(title:, label: nil, subtitle: nil, tone: :muted)
    c = SA_COLORS[tone]
    parts = []
    parts << %(<div style="font-size:11px;font-weight:700;color:#{c[:text]};text-transform:uppercase;letter-spacing:1px;margin-bottom:4px">#{h title}</div>)
    parts << %(<div style="font-size:28px;font-weight:700;color:#{c[:text]};line-height:1">#{h label}</div>) if label
    parts << %(<div style="font-size:12px;color:#555;margin-top:6px">#{subtitle}</div>) if subtitle
    wrap = <<~HTML
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-bottom:28px">
        <tr><td style="background:#{c[:bg]};border-left:4px solid #{c[:text]};border-radius:4px;padding:16px 20px">
          #{parts.join}
        </td></tr>
      </table>
    HTML
    wrap.html_safe
  end

  # ── Status badge / pill ──────────────────────────────────────────────────
  def sa_badge(label:, tone: :muted)
    c = SA_COLORS[tone]
    %(<span style="background:#{c[:bg]};color:#{c[:text]};padding:3px 9px;border-radius:12px;font-size:11px;font-weight:700;white-space:nowrap">#{h label}</span>).html_safe
  end

  # ── Section heading ──────────────────────────────────────────────────────
  # Bold title with an optional right-aligned "Action →" link.
  def sa_section(title:, link_text: nil, link_url: nil, top_margin: true)
    link_html = link_text && link_url ? %(<a href="#{link_url}" style="font-size:12px;color:#1565c0;text-decoration:none;font-weight:600">#{h link_text} &rarr;</a>) : ""
    mt = top_margin ? "margin-top:28px;" : ""
    <<~HTML.html_safe
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="#{mt}margin-bottom:10px">
        <tr><td style="padding-bottom:6px;border-bottom:1px solid #e0e0e0">
          <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%">
            <tr>
              <td style="font-size:14px;font-weight:700;color:#333">#{h title}</td>
              <td style="text-align:right">#{link_html}</td>
            </tr>
          </table>
        </td></tr>
      </table>
    HTML
  end

  # ── Callout / alert box ──────────────────────────────────────────────────
  # Left-bordered info / warning / error block.
  # body may contain pre-escaped HTML (mark it html_safe before passing).
  def sa_callout(body:, tone: :info, heading: nil)
    c = SA_COLORS[tone]
    heading_html = heading ? %(<div style="font-size:12px;font-weight:700;color:#{c[:text]};margin-bottom:6px">#{h heading}</div>) : ""
    <<~HTML.html_safe
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-bottom:16px">
        <tr><td style="padding:12px 14px;background:#{c[:bg]};border-left:3px solid #{c[:border]};border-radius:2px">
          #{heading_html}
          <span style="font-size:12px;color:#555;line-height:1.6">#{body}</span>
        </td></tr>
      </table>
    HTML
  end

  # ── Table helpers ────────────────────────────────────────────────────────
  # sa_table_header("Fund", "Status", ["Net Position", align: :right]) → thead HTML
  def sa_th(*cols)
    cells = cols.map do |col|
      text, align = col.is_a?(Array) ? [col[0], col[1]&.dig(:align)] : [col, :left]
      %(<th style="padding:9px 12px;text-align:#{align || :left};border:1px solid #e0e0e0;font-size:11px;font-weight:700;color:#555;text-transform:uppercase;letter-spacing:0.5px">#{h text}</th>)
    end
    %(<thead><tr style="background:#f5f5f5">#{cells.join}</tr></thead>).html_safe
  end

  def sa_td(text, align: :left, color: nil, bold: false, nowrap: false)
    styles = ["padding:9px 12px", "border:1px solid #e0e0e0", "text-align:#{align}"]
    styles << "color:#{color}" if color
    styles << "font-weight:700" if bold
    styles << "white-space:nowrap" if nowrap
    %(<td style="#{styles.join(';')}">#{text}</td>).html_safe
  end

  # Key-value detail table (two-column)
  def sa_kv_table(rows:)
    cells = rows.map do |label, value, opts|
      tone  = opts&.dig(:tone)
      color = tone ? SA_COLORS[tone][:text] : nil
      bold  = opts&.dig(:bold)
      border_style = bold ? "border-top:2px solid #333;" : ""
      <<~ROW
        <tr style="#{'font-weight:700;' if bold}#{border_style}">
          <td style="padding:7px 12px;border:1px solid #e0e0e0;color:#555;#{'font-weight:700;' if bold}">#{h label.to_s}</td>
          <td style="padding:7px 12px;border:1px solid #e0e0e0;text-align:right;#{"color:#{color};" if color}#{'font-weight:700;' if bold}">#{value}</td>
        </tr>
      ROW
    end
    <<~HTML.html_safe
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="border-collapse:collapse;margin-bottom:8px">
        #{cells.join}
      </table>
    HTML
  end

  # ── CTA button ───────────────────────────────────────────────────────────
  def sa_cta(label:, url:)
    <<~HTML.html_safe
      <table role="presentation" class="btn btn-outline-primary" style="margin-top:28px">
        <tbody><tr><td>
          <table role="presentation" border="0" cellpadding="0" cellspacing="0">
            <tbody><tr><td>
              <a href="#{url}" target="_blank">#{h label}</a>
            </td></tr></tbody>
          </table>
        </td></tr></tbody>
      </table>
    HTML
  end

  # ── Footer ────────────────────────────────────────────────────────────────
  def sa_footer(text)
    %(<p style="font-size:11px;color:#aaa;margin-top:36px;padding-top:16px;border-top:1px solid #eee;line-height:1.5">#{text}</p>).html_safe
  end

  # ── Intro paragraph ───────────────────────────────────────────────────────
  def sa_intro(text)
    %(<p style="margin:0 0 20px;font-size:14px;line-height:1.6;color:#334155;">#{text}</p>).html_safe
  end

  # ═══════════════════════════════════════════════════════════════════════
  # Light variant builders
  #
  # Everything below draws with hairlines and white space instead of filled
  # panels and full-grid borders. Same table-based, inline-styled mechanics as
  # the solid set above — Outlook renders HTML through Word, so no flexbox, no
  # grid, and no <style> block survives the trip.
  # ═══════════════════════════════════════════════════════════════════════

  # Page header. A colour-coded headline over a hairline, rather than a filled
  # banner: the tone still reads at a glance without a block of saturated colour
  # dominating the message.
  def sa_light_banner(title:, label: nil, subtitle: nil, tone: :muted)
    c = SA_LIGHT[tone] || SA_LIGHT[:muted]
    parts = []
    parts << %(<div style="font-size:10px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;color:#{SA_NEUTRAL[:faint]};margin-bottom:9px">#{h title}</div>)
    parts << %(<div style="font-size:26px;font-weight:600;color:#{c[:text]};line-height:1.15">#{h label}</div>) if label
    parts << %(<div style="font-size:12px;color:#{SA_NEUTRAL[:muted]};margin-top:9px;line-height:1.5">#{subtitle}</div>) if subtitle

    <<~HTML.html_safe
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-bottom:26px">
        <tr><td style="padding-bottom:20px;border-bottom:1px solid #{SA_NEUTRAL[:hairline]}">
          #{parts.join}
        </td></tr>
      </table>
    HTML
  end

  # A row of big-number tiles — the summary band at the top of a report.
  #
  # White with a hairline, so the numbers carry the colour and the band stays
  # quiet. Built as a table with one <td> per tile, NOT flexbox or grid: Outlook
  # would stack them into a column and the band would lose its whole point.
  #
  # tiles: array of { value:, label:, tone: } — tone defaults to :muted.
  def sa_stat_tiles(tiles)
    tiles = Array(tiles).compact
    return "".html_safe if tiles.empty?

    width = (100.0 / tiles.size).round(4)
    cells = tiles.each_with_index.map do |tile, index|
      c = SA_LIGHT[tile[:tone] || :muted] || SA_LIGHT[:muted]
      # Gutters between tiles but none on the outside, so the band lines up with the
      # rest of the message rather than sitting inset from it.
      padding = if index.zero?
                  "0 4px 0 0"
                elsif index == tiles.size - 1
                  "0 0 0 4px"
                else
                  "0 4px"
                end
      <<~CELL
        <td width="#{width}%" style="padding:#{padding};vertical-align:top">
          <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%">
            <tr><td style="background:#ffffff;border:1px solid #{SA_NEUTRAL[:hairline]};border-radius:6px;padding:16px 6px;text-align:center">
              <div style="font-size:24px;font-weight:600;color:#{c[:text]};line-height:1">#{h tile[:value].to_s}</div>
              <div style="font-size:10px;font-weight:600;letter-spacing:0.7px;text-transform:uppercase;color:#{SA_NEUTRAL[:faint]};margin-top:9px;line-height:1.35">#{h tile[:label].to_s}</div>
            </td></tr>
          </table>
        </td>
      CELL
    end

    <<~HTML.html_safe
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-bottom:12px">
        <tr>#{cells.join}</tr>
      </table>
    HTML
  end

  # Small centred grey line, e.g. the derived stats printed under sa_stat_tiles.
  # body may contain pre-escaped HTML (mark it html_safe before passing).
  def sa_note(body)
    %(<p style="margin:2px 0 0;font-size:11.5px;color:#{SA_NEUTRAL[:faint]};line-height:1.6;text-align:center">#{body}</p>).html_safe
  end

  # Section heading: title, a de-emphasised count, and an optional right-aligned
  # link. No rule of its own — sa_light_th underneath supplies the only line, so
  # a heading and its table read as one object.
  def sa_light_section(title:, count: nil, link_text: nil, link_url: nil, top_margin: true)
    count_html = count ? %( <span style="font-weight:500;color:#{SA_NEUTRAL[:faint]}">#{h count.to_s}</span>) : ""
    link_html = link_text && link_url ? %(<a href="#{link_url}" style="font-size:11.5px;color:#{SA_LIGHT[:info][:text]};text-decoration:none;font-weight:500">#{h link_text} &rarr;</a>) : ""

    <<~HTML.html_safe
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="#{'margin-top:34px;' if top_margin}margin-bottom:11px">
        <tr>
          <td style="font-size:13px;font-weight:600;color:#{SA_NEUTRAL[:ink]}">#{h title}#{count_html}</td>
          <td style="text-align:right;vertical-align:bottom">#{link_html}</td>
        </tr>
      </table>
    HTML
  end

  # Table header row: no fill, no vertical rules, one line underneath.
  # sa_light_th("Task", ["Due", { align: :right, width: "110" }])
  def sa_light_th(*cols)
    cells = cols.map do |col|
      text, opts = col.is_a?(Array) ? [col[0], col[1] || {}] : [col, {}]
      width = opts[:width] ? %( width="#{opts[:width]}") : ""
      %(<th#{width} style="padding:0 10px 7px 0;text-align:#{opts[:align] || :left};border-bottom:1px solid #{SA_NEUTRAL[:rule]};font-size:10px;font-weight:600;color:#{SA_NEUTRAL[:faint]};text-transform:uppercase;letter-spacing:0.7px">#{h text}</th>)
    end
    %(<thead><tr>#{cells.join}</tr></thead>).html_safe
  end

  # Table body cell. Hairline underneath only — no box around every value.
  def sa_light_td(text, align: :left, color: nil, size: "12px", nowrap: false, top: false)
    styles = [
      "padding:11px 10px 11px 0",
      "border-bottom:1px solid #{SA_NEUTRAL[:hairline]}",
      "text-align:#{align}",
      "font-size:#{size}",
      "color:#{color || SA_NEUTRAL[:body]}",
      "vertical-align:#{top ? 'top' : 'middle'}"
    ]
    styles << "white-space:nowrap" if nowrap
    %(<td style="#{styles.join(';')}">#{text}</td>).html_safe
  end

  # Pill with a barely-there tint instead of a border — a quiet status marker.
  def sa_soft_badge(label:, tone: :muted)
    c = SA_LIGHT[tone] || SA_LIGHT[:muted]
    %(<span style="background:#{c[:tint]};color:#{c[:text]};padding:3px 9px;border-radius:10px;font-size:10.5px;font-weight:600;white-space:nowrap">#{h label}</span>).html_safe
  end

  # Outlined call to action. The solid sa_cta leans on the mailer layout's .btn
  # classes; this one is self-contained and quieter.
  def sa_light_cta(label:, url:)
    <<~HTML.html_safe
      <table role="presentation" border="0" cellpadding="0" cellspacing="0" style="margin-top:34px">
        <tr><td style="border:1px solid #{SA_NEUTRAL[:rule]};border-radius:6px;padding:11px 20px;background:#ffffff">
          <a href="#{url}" target="_blank" style="font-size:12.5px;font-weight:600;color:#{SA_LIGHT[:info][:text]};text-decoration:none">#{h label} &rarr;</a>
        </td></tr>
      </table>
    HTML
  end

  # Quiet closing line.
  def sa_light_footer(text)
    %(<p style="font-size:11px;color:#{SA_NEUTRAL[:faint]};margin-top:34px;padding-top:16px;border-top:1px solid #{SA_NEUTRAL[:hairline]};line-height:1.6">#{text}</p>).html_safe
  end
end
