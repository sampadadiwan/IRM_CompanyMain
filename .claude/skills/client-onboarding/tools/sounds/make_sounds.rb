# Builds the onboarding step sounds (tools/sounds/*.wav) — run it again after changing a note:
#   ruby tools/sounds/make_sounds.rb
# Chosen by ear with ops on 2026-10-27, replacing the per-OS system sounds (too subtle, and different on every OS):
#   done.wav       rising C6 E6 G6 chime — a step finished (fallback: where the freedesktop theme is installed, ui.rb
#                  plays its "complete" sound instead, ops' pick; it is not copied here because of its licence)
#   attention.wav  E6 → C6 doorbell, twice — a step stopped for ops (review, the report, investor access)
#   fail.wav       falling A4 → F4, low, twice — a step failed, stalled, or the token expired
# Generated (plain sine tones), so there is no licence to track; 16-bit mono WAV plays on Linux, macOS and Windows.
RATE = 44_100
def tone(freq, secs, vol: 0.8, decay: 4.0)
  n = (RATE * secs).to_i
  (0...n).map do |i|
    t = i.to_f / RATE
    env = [t / 0.008, 1.0].min * Math.exp(-decay * t)
    vol * env * (Math.sin(2 * Math::PI * freq * t) + 0.25 * Math.sin(4 * Math::PI * freq * t)) / 1.25
  end
end
def gap(secs) = Array.new((RATE * secs).to_i, 0.0)
def wav(path, samples)
  data = samples.map { (_1.clamp(-1, 1) * 32_767).round }.pack("s<*")
  File.binwrite(path, ["RIFF", 36 + data.bytesize, "WAVE", "fmt ", 16, 1, 1, RATE, RATE * 2, 2, 16, "data", data.bytesize].pack("A4VA4A4VvvVVvvA4V") + data)
end
dir = ARGV[0] || __dir__
# done: a bright rising major third → fifth (C6 E6 G6), quick and happy
wav "#{dir}/done.wav", tone(1047, 0.12, decay: 6) + tone(1319, 0.12, decay: 6) + tone(1568, 0.55, decay: 4)
# needs you: a two-note doorbell (E6 → C6), twice — asks for attention without sounding wrong
wav "#{dir}/attention.wav", tone(1319, 0.28, decay: 5) + tone(1047, 0.45, decay: 4) + gap(0.18) + tone(1319, 0.28, decay: 5) + tone(1047, 0.45, decay: 4)
# failed: a falling minor pair, low and longer (A4 → F4), twice — unmistakably "something is wrong"
wav "#{dir}/fail.wav", tone(440, 0.30, vol: 0.9, decay: 2.5) + tone(349, 0.55, vol: 0.9, decay: 2.5) + gap(0.15) + tone(440, 0.30, vol: 0.9, decay: 2.5) + tone(349, 0.55, vol: 0.9, decay: 2.5)
puts Dir["#{dir}/*.wav"].map { "#{File.basename(_1)} #{File.size(_1) / 1024} KB" }.join(" · ")
