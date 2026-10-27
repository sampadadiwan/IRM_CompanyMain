# Terminal output for the onboarding tools — icons, colours, progress lines and hints in one place, so every tool looks
# the same. Two audiences:
#   ops in their own terminal  a progress line that redraws in place, with colours and emoji
#   Claude (output captured)   one plain line at each 10% or every minute, so the captured log stays readable
# Plain symbols (✔ ▶ ✖) instead of emoji with ONBOARDING_PLAIN=1, TERM=dumb, a console that is not UTF-8, or Windows
# outside Windows Terminal (the old console draws emoji as boxes and prints escape codes as text, so plain output has
# no colours and no redrawn line — one line per milestone instead). ONBOARDING_PLAIN=0 forces emoji (e.g. VS Code's
# terminal on Windows, which handles them but is not detected). NO_COLOR turns colours off.
# onboard.rb runs the other tools through a pipe, so it passes ONBOARDING_TTY=1/0 to say whether ops is watching.
# Sounds (UI.chime): tools/sounds/*.wav — a chime when a step is done, a doorbell when it needs ops, a low alert when it
# fails — played on the machine running the tools, in the background. ONBOARDING_SOUND=0 turns them off.
require "yaml"

# Tool output goes through a pipe (onboard.rb, Claude's shell): without sync Ruby holds it back until the tool exits
$stdout.sync = true

module Onboarding
  module UI
    module_function

    # name → [emoji, plain symbol]
    ICONS = {
      fund: ["🏦", "·"], track: ["🧭", "·"], plan: ["📋", "▶"], checks: ["🔒", "·"], sent: ["📤", "▶"],
      watch: ["👀", "▶"], wait: ["⏳", "…"], tip: ["☕", "·"], ok: ["✅", "✔"], done: ["🎉", "✔"], next: ["👉", "→"],
      warn: ["⚠️", "⚠"], stall: ["🐢", "⚠"], fail: ["🛑", "✖"], hint: ["💡", "→"], token: ["🔑", "✖"], todo: ["⬜", "·"]
    }.freeze
    COLORS = { green: 32, red: 31, yellow: 33, dim: 2 }.freeze
    HINTS_PATH = File.join(__dir__, "hints.yml")

    # Why output is plain, or nil when emoji are fine (doctor.rb shows the reason)
    def plain_reason
      return nil if ENV["ONBOARDING_PLAIN"] == "0"
      return "ONBOARDING_PLAIN=1" if ENV["ONBOARDING_PLAIN"] == "1"
      return "TERM=dumb" if ENV["TERM"] == "dumb"
      return "the console is not UTF-8 (#{Encoding.default_external})" unless Encoding.default_external == Encoding::UTF_8
      return "Windows console outside Windows Terminal" if Gem.win_platform? && ENV["WT_SESSION"].to_s.empty?

      nil
    end

    def plain? = !plain_reason.nil?
    # Ops is watching a real terminal (onboard.rb says so for the tools it runs through a pipe)
    def tty? = ENV.key?("ONBOARDING_TTY") ? ENV["ONBOARDING_TTY"] == "1" : $stdout.tty?
    # Escape codes (colours, the redrawn progress line) only where they render: a terminal that is not in plain mode
    def ansi? = tty? && !plain?
    def color? = ansi? && ENV["NO_COLOR"].to_s.empty?
    def icon(name) = ICONS.fetch(name)[plain? ? 1 : 0]
    def paint(text, color) = color && color? ? "\e[#{COLORS.fetch(color)}m#{text}\e[0m" : text

    # The step sounds ship with the tools (tools/sounds/*.wav, built by sounds/make_sounds.rb), so every machine plays the
    # same ones; chosen by ear with ops (2026-10-27) after the system sounds proved too subtle and differed per OS
    SOUND_DIR = File.join(__dir__, "sounds")
    SOUNDS = {
      done: "done.wav",           # chime — a step finished and was confirmed (the system's "complete" when installed, below)
      attention: "attention.wav", # doorbell, twice — a step stopped for ops: review, the report, investor access
      fail: "fail.wav"            # low falling pair, twice — a step failed, stalled, or the token expired
    }.freeze
    # Ops preferred the freedesktop theme's "complete" for done (2026-10-27). It is played from where the theme installs it,
    # never copied into the repo — the theme mixes CC-BY, CC-BY-SA and GPL files — so machines without it get done.wav
    SYSTEM_SOUNDS = { done: "/usr/share/sounds/freedesktop/stereo/complete.oga" }.freeze

    # The command that plays a WAV here, or nil (doctor.rb shows it); the first player found wins
    def sound_player
      return @sound_player if defined?(@sound_player)

      on_path = ->(cmd) { ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? { File.executable?(File.join(_1, cmd)) || File.executable?(File.join(_1, "#{cmd}.exe")) } }
      @sound_player = if Gem.win_platform? then on_path.("powershell") ? "powershell" : nil
                      elsif RUBY_PLATFORM.include?("darwin") then on_path.("afplay") ? "afplay" : nil
                      else %w[pw-play paplay aplay].find { on_path.(_1) }
                      end
    end

    # Plays the sound for `kind` without waiting for it, so a step never slows down for it. No player: a terminal bell
    # when ops is watching one, else silence. Never raises — a missing sound must not fail a step
    def chime(kind)
      return if ENV["ONBOARDING_SOUND"] == "0"

      system_file = SYSTEM_SOUNDS[kind]
      # .oga needs pw-play or paplay (aplay and the macOS / Windows players take WAV only)
      file = if system_file && File.exist?(system_file) && %w[pw-play paplay].include?(sound_player) then system_file
             else File.join(SOUND_DIR, SOUNDS.fetch(kind))
             end
      cmd = case sound_player
            # PowerShell single-quoted string: an apostrophe in the path (C:\Users\O'Neil) is written twice
            when "powershell" then ["powershell", "-NoProfile", "-Command", "(New-Object Media.SoundPlayer '#{file.gsub("'", "''")}').PlaySync()"]
            when "aplay" then ["aplay", "-q", file]
            when String then [sound_player, file]
            end
      if cmd && File.exist?(file)
        Process.detach(Process.spawn(*cmd, %i[out err] => File::NULL))
      elsif tty?
        print "\a"
      end
    rescue StandardError
      nil
    end

    # One labelled line, e.g. "📋 Plan         upload CapitalRemittancePayment …"
    def say(name, label, text = nil, color: nil)
      puts paint(text ? "#{icon(name)} #{label.ljust(12)} #{text}" : "#{icon(name)} #{label}", color)
    end

    # An indented "what to do" line under a result
    def hint(text) = puts(paint("   #{icon(:hint)} #{text}", :dim))

    # Advice for the known errors in text (hints.yml: an error pattern → what to do), each once
    def hints_for(text)
      @hints ||= YAML.safe_load_file(HINTS_PATH)
      @hints.select { text.to_s.match?(Regexp.new(_1["match"], Regexp::IGNORECASE)) }.map { _1["hint"] }.uniq
    end

    # 4109 → "4,109", -12 → "-12", unknown → "?" (counts, so Western grouping — money in the recons uses lakhs)
    def num(n)
      return "?" if n.nil?
      return n.round(4).to_s if n.is_a?(Float)

      "#{'-' if n.to_i.negative?}#{n.to_i.abs.to_s.reverse.scan(/\d{1,3}/).join(',').reverse}"
    end

    # Seconds → "42 s", "17 min 29 s", "1 h 05 min"
    def duration(secs)
      s = secs.to_i
      return "#{s} s" if s < 60
      return "#{s / 60} min #{s % 60} s" if s < 3600

      format("%d h %02d min", s / 3600, s % 3600 / 60)
    end

    def bar(done, total, width = 20)
      filled = total.to_i.positive? ? (done.to_f / total * width).floor.clamp(0, width) : 0
      ("▓" * filled) + ("░" * (width - filled))
    end

    # A progress line for a wait: redraws in place for ops, prints milestones when captured. With a total it shows a
    # bar, a percentage and the time left (from the rate seen so far); without one, the value and the time so far.
    class Progress
      attr_reader :last_change

      def initialize(label, total: nil, unit: "rows")
        # A total of 0 (nothing to do, or not counted yet) is no total — no bar, no percentage, no estimate
        @label, @unit = label, unit
        @total = total if total.to_i.positive?
        @started = @last_change = Time.now
        @done = @extra = @first = @last_print = @last_decile = nil
      end

      # A new reading: done so far (nil while nothing is known yet), an optional server total and a note
      def update(done, total: nil, extra: nil)
        @total = total if total.to_i.positive?
        @last_change = Time.now if done != @done
        @done, @extra = done, extra
        # The rate is measured from the first reading with rows, so time spent queued does not skew the estimate
        @first ||= [Time.now, done] if done.is_a?(Numeric) && done.positive?
        UI.ansi? ? redraw : milestone
      end

      # Waits between readings; ops' line keeps ticking every second, so a long wait never looks frozen
      def sleep(secs)
        return Kernel.sleep(secs) unless UI.ansi?

        secs.to_i.times do
          Kernel.sleep 1
          redraw
        end
      end

      # Ends the redrawn line so the next output starts on a clean one
      def finish
        puts if @open
        @open = false
      end

      def stalled_for = Time.now - @last_change

      private

      def redraw
        print "\r\e[2K#{line}"
        @open = true
      end

      # Captured output: the first reading, each new 10%, and at least one line a minute
      def milestone
        decile = @total && @done.is_a?(Integer) ? @done * 10 / @total : nil
        return unless @last_print.nil? || (decile && decile != @last_decile) || Time.now - @last_print >= 60

        puts line
        @last_print, @last_decile = Time.now, decile
      end

      def line
        parts = [counts, @extra].compact
        left = eta
        parts << (left ? "~#{left} left" : "#{UI.duration(Time.now - @started)} so far")
        "#{UI.icon(:wait)} #{@label.ljust(12)} #{parts.join(' · ')}"
      end

      def counts
        return "waiting for the first figures" if @done.nil?
        return "#{UI.num(@done)} #{@unit}".strip unless @total && @done.is_a?(Integer)

        shown = "#{UI.num(@done)} / #{UI.num(@total)} #{@unit}".strip
        UI.ansi? ? "#{UI.bar(@done, @total)}  #{shown}" : "#{shown} (#{@done * 100 / @total}%)"
      end

      def eta
        return nil unless @first && @total && @done.is_a?(Integer) && @done < @total

        t0, d0 = @first
        elapsed = Time.now - t0
        rate = (@done - d0) / elapsed
        # Too early or no movement yet: no estimate rather than a wild one
        return nil unless elapsed >= 15 && rate.positive?

        UI.duration((@total - @done) / rate)
      end
    end
  end
end
