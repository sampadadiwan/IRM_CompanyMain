namespace :website do
  # The ../caphive.com repo is the SOURCE OF TRUTH for the static website.
  # public/website/ is a read-only mirror shipped with each release — never
  # hand-edit it; change the source repo, re-run this task, and commit.
  desc "Mirror the static website repo (default ../caphive.com, override with WEBSITE_SRC) into public/website"
  task :sync do
    src = ENV.fetch("WEBSITE_SRC", "../caphive.com")
    # --delete keeps public/website an exact mirror: pages removed upstream
    # disappear here too. Repo metadata and source-only docs stay out of the
    # deployable. Multi-arg sh bypasses the shell, so a WEBSITE_SRC with
    # spaces stays one argument instead of splitting into a wrong --delete
    # source.
    sh "rsync", "-av", "--delete",
       "--exclude=.git", "--exclude=.claude", "--exclude=SITE.md",
       "#{src}/", "public/website/"
  end
end
