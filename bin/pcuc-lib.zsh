# pcuc-lib.zsh - progress reporter shared by the `cuc` and `pcuc` scripts beside it (sourced, not run).
#
# Progress (cuc and pcuc): every 30 s prints `pcuc: 412/1530 scenarios (27%) · 3 failed ·
# 12:03 elapsed · ETA ~33m` and puts the same text in the terminal title. Each cucumber process
# appends a line per finished scenario to $PCUC_PROGRESS_DIR/worker_N
# (features/support/pcuc_progress.rb); the total comes from a dry run that loads no support
# code, so it never boots Rails (~4 s, run alongside).

# Runs a cucumber command with the progress reporter around it.
#   _cuc_with_progress <label> <dry-run selection args...> -- <command...>
# The selection args (--tags/--name/paths) must pick the same scenarios as the command.
_cuc_with_progress() {
  local label=$1; shift
  local -a dryargs
  # Everything up to `--` is for the dry-run count; the rest is the command to run.
  while (( $# )) && [[ "$1" != "--" ]]; do dryargs+=("$1"); shift; done
  shift

  # Progress dir: cucumber processes write worker_N files here, the dry run writes `total`.
  local progress_dir start=$SECONDS ticker
  progress_dir=$(mktemp -d "${TMPDIR:-/tmp}/pcuc_progress.XXXXXX")
  mkdir -p "$progress_dir/no_support"

  # Total scenario count. `-r` an empty dir = load no step/support code, so Rails never boots;
  # every step is "undefined", but outlines are expanded and --tags applied, so the scenario
  # count matches the real run. -P skips cucumber.yml (whose default profile adds `features`).
  # Written via a temp file + mv so the reporter never reads a half-written number.
  ( RUBYOPT="-W0" bundle exec cucumber -P --publish-quiet --dry-run -r "$progress_dir/no_support" \
      --format summary "${dryargs[@]}" 2>/dev/null \
    | sed -nE 's/^([0-9]+) scenarios? .*/\1/p' > "$progress_dir/total.tmp" \
    && mv "$progress_dir/total.tmp" "$progress_dir/total" ) &!

  # Ticker: report every 30 s. It also stops by itself once the dir is gone, in case the kill
  # below is ever missed.
  ( while sleep 30 && [[ -d "$progress_dir" ]]; do _pcuc_report $label "$progress_dir" $start; done ) &!
  ticker=$!

  # try/always: the cleanup runs on normal exit AND on Ctrl-C; the command's exit status is kept.
  # In a script (not an interactive shell) an untrapped SIGINT kills zsh before `always` runs,
  # so catch it here: cucumber, in the same process group, still gets the Ctrl-C and stops, and
  # zsh then falls through to the cleanup.
  setopt localtraps
  trap 'print -u2 -- "\n(interrupted)"' INT
  {
    PCUC_PROGRESS_DIR="$progress_dir" "$@"
  } always {
    kill $ticker 2>/dev/null
    _pcuc_report $label "$progress_dir" $start final
    # Lets the calling script read the feed before it is deleted - pcuc records scenario timings
    # from it (_pcuc_record_times). Runs on Ctrl-C too, so a stopped run still contributes.
    (( $+functions[_pcuc_after_run] )) && _pcuc_after_run "$progress_dir"
    # Only ever a mktemp dir of ours: never rm with an empty or unexpected path.
    [[ "$progress_dir" == */pcuc_progress.* && -d "$progress_dir" ]] && rm -rf -- "$progress_dir"
  }
}

# Prints one progress line (stderr) and sets the terminal title. $1 = label (cuc/pcuc),
# $2 = progress dir, $3 = start time in $SECONDS, $4 = "final" for the closing summary.
_pcuc_report() {
  local label=$1 dir=$2 start=$3 final=$4
  local done_n=0 failed_n=0 total elapsed pct="" eta="" line
  local -a wfiles
  # (N): no worker has finished a scenario yet -> empty list, not a "no matches" error (and a
  # bare `cat` with no files would block reading stdin).
  wfiles=($dir/worker_*(N))
  # Finished scenarios = lines across all worker files; failures are the `failed` lines.
  if (( ${#wfiles} )); then
    done_n=$(cat $wfiles | wc -l)
    failed_n=$(cat $wfiles | grep -c '^failed')
  fi
  # The dry-run total lands a few seconds in; until then show `?`.
  total=$(cat $dir/total 2>/dev/null)
  elapsed=$(( SECONDS - start ))
  if [[ -n "$total" ]] && (( total > 0 )); then
    pct=" ($(( done_n * 100 / total ))%)"
    # Straight-line ETA from the rate so far - rough: one slow file at the end skews it.
    (( done_n > 0 && done_n < total && ! ${#final} )) && \
      eta=" · ETA ~$(( (elapsed * (total - done_n) / done_n + 59) / 60 ))m"
  fi
  line="${done_n}/${total:-?} scenarios${pct} · ${failed_n} failed · $(printf '%d:%02d' $((elapsed / 60)) $((elapsed % 60))) elapsed${eta}"
  # The newest failure, so one can be opened while the run carries on. Feed lines are
  # "failed<TAB>location<TAB>name<TAB>epoch"; sort on the epoch across all workers. (Older support
  # code wrote a bare "failed" with no location - then there is nothing to name.) The full list:
  # `pcuc-status`.
  if (( failed_n > 0 )); then
    local last
    last=$(grep -h '^failed' $wfiles | sort -t$'\t' -k4,4n | tail -1 | cut -s -f2)
    [[ -n "$last" ]] && line+=" · last fail ${last:t}"
  fi
  # Leading newline: progress-format dots never end their line, so the report would glue onto them.
  print -u2 -- "\n${label}: ${final:+done }${line}"
  # OSC 0 = window/tab title; written to the tty so it works even if stderr is redirected.
  # Braces so the 2>/dev/null also swallows a failed open of /dev/tty (no terminal attached).
  { print -n -- "\e]0;${label} ${final:+done }${line}\a" > /dev/tty } 2>/dev/null
}
