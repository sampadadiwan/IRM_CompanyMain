# frozen_string_literal: true

require 'action_mailer'

module CucumberDashboard
  # Sends email notifications for parallel Cucumber runs.
  class CompletionMailer < ActionMailer::Base
    default from: 'cucumber-dashboard@caphive.com'

    def run_complete(to, summary)
      @passed = summary['passed'] || 0
      @failed = summary['failed'] || 0
      @skipped = summary['skipped'] || 0
      @total = @passed + @failed + @skipped
      @duration = summary['duration'] || '—'
      @failures = summary['failures'] || []

      status = @failed > 0 ? "#{@failed} FAILED" : 'ALL PASSED'

      mail(to: to, subject: "Cucumber Run Complete — #{status} (#{@total} scenarios, #{@duration})") do |format|
        format.html { render inline: completion_html }
        format.text { render inline: completion_text }
      end
    end

    def scenario_failed(to, failure)
      @feature = failure['feature'] || ''
      @scenario = failure['scenario'] || ''
      @line = failure['line'] || ''
      @error = failure['error'] || ''
      @worker = failure['worker'] || ''
      @location = "#{@feature}:#{@line}"

      mail(to: to, subject: "FAILED — #{@scenario} (#{short_path(@feature)}:#{@line})") do |format|
        format.html { render inline: failure_html }
        format.text { render inline: failure_text }
      end
    end

    private

    def short_path(p)
      p.to_s.sub(%r{^features/}, '').sub(/\.feature$/, '')
    end

    def completion_html
      <<~HTML
        <div style="font-family: system-ui, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
          <h2 style="margin: 0 0 16px;">Cucumber Parallel Run Complete</h2>

          <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">
            <tr>
              <td style="padding: 12px; background: #f0faf9; border: 1px solid #d0e8e6; text-align: center;">
                <div style="font-size: 11px; color: #666; text-transform: uppercase;">Passed</div>
                <div style="font-size: 24px; font-weight: 700; color: #1a9e92;"><%= @passed %></div>
              </td>
              <td style="padding: 12px; background: #fdf2f2; border: 1px solid #f0d0d0; text-align: center;">
                <div style="font-size: 11px; color: #666; text-transform: uppercase;">Failed</div>
                <div style="font-size: 24px; font-weight: 700; color: #c5303d;"><%= @failed %></div>
              </td>
              <td style="padding: 12px; background: #f5f5f5; border: 1px solid #ddd; text-align: center;">
                <div style="font-size: 11px; color: #666; text-transform: uppercase;">Skipped</div>
                <div style="font-size: 24px; font-weight: 700; color: #888;"><%= @skipped %></div>
              </td>
              <td style="padding: 12px; background: #f5f5f5; border: 1px solid #ddd; text-align: center;">
                <div style="font-size: 11px; color: #666; text-transform: uppercase;">Duration</div>
                <div style="font-size: 24px; font-weight: 700;"><%= @duration %></div>
              </td>
            </tr>
          </table>

          <% if @failures.any? %>
            <h3 style="color: #c5303d; margin: 0 0 8px;">Failed Scenarios</h3>
            <table style="width: 100%; border-collapse: collapse; font-size: 13px;">
              <% @failures.each do |f| %>
                <tr style="border-bottom: 1px solid #eee;">
                  <td style="padding: 6px 8px; font-family: monospace; font-weight: 600;"><%= f['location'] %></td>
                  <td style="padding: 6px 8px; color: #555;"><%= f['scenario'] %></td>
                  <td style="padding: 6px 8px; color: #555; font-size: 11px;">W<%= f['worker'] %></td>
                </tr>
                <% if f['error'] %>
                  <tr style="border-bottom: 1px solid #eee;">
                    <td colspan="3" style="padding: 2px 8px 6px; font-family: monospace; font-size: 11px; color: #c5303d;"><%= f['error'] %></td>
                  </tr>
                <% end %>
              <% end %>
            </table>
          <% end %>

          <p style="margin-top: 20px; font-size: 12px; color: #999;">Sent by Cucumber Dashboard</p>
        </div>
      HTML
    end

    def completion_text
      <<~TEXT
        Cucumber Parallel Run Complete
        ==============================
        Passed:  <%= @passed %>
        Failed:  <%= @failed %>
        Skipped: <%= @skipped %>
        Duration: <%= @duration %>

        <% if @failures.any? %>
        Failed Scenarios:
        <% @failures.each do |f| %>
        - <%= f['location'] %> — <%= f['scenario'] %> (W<%= f['worker'] %>)
          <% if f['error'] %><%= f['error'] %><% end %>
        <% end %>
        <% end %>
      TEXT
    end

    def failure_html
      <<~HTML
        <div style="font-family: system-ui, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
          <div style="background: #fdf2f2; border: 1px solid #f0d0d0; border-radius: 6px; padding: 16px; margin-bottom: 16px;">
            <div style="font-size: 11px; color: #c5303d; text-transform: uppercase; font-weight: 600; margin-bottom: 4px;">Scenario Failed</div>
            <div style="font-size: 16px; font-weight: 700; color: #1a1a2e; margin-bottom: 8px;"><%= @scenario %></div>
            <div style="font-family: monospace; font-size: 13px; color: #555; margin-bottom: 4px;"><%= @location %></div>
            <div style="font-size: 12px; color: #888;">Worker <%= @worker %></div>
          </div>

          <% if @error.present? %>
            <div style="background: #f9f9f9; border: 1px solid #eee; border-radius: 4px; padding: 12px; font-family: monospace; font-size: 12px; color: #c5303d; word-break: break-word;">
              <%= @error %>
            </div>
          <% end %>

          <p style="margin-top: 16px; font-size: 12px; color: #999;">Sent by Cucumber Dashboard</p>
        </div>
      HTML
    end

    def failure_text
      <<~TEXT
        SCENARIO FAILED
        ===============
        Scenario: <%= @scenario %>
        Location: <%= @location %>
        Worker:   <%= @worker %>

        <% if @error.present? %>
        Error:
        <%= @error %>
        <% end %>
      TEXT
    end
  end
end
