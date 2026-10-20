#!/usr/bin/env bash
# EC2 user-data for a Support Console machine (openspec/changes/support-console/design.md, card ⑤).
# Ubuntu 24.04. `rake "support_console:machine[<env>]"` fills in the values below and launches
# the machine with it; SupportConsoleMachine#instance_policy is the matching IAM policy.
#
# What it sets up:
#   /opt/support-console/<rev>   the relay, hook and db MCP server (machine/<rev>.tar.gz, node_modules included)
#   /code/<rev>, /code/current   the deployed code Claude reads (code/<rev>.tar.gz, no credentials)
#   /clients/<entity_id>         one working folder per client; Claude Code's transcripts sit under
#                                ~support-console/.claude/projects/
#   /etc/support-console/        machine.env and the db password file, readable only by the service user
#   support-console-relay        the relay on the private address, port 4900
#   support-console-sync.timer   every 5 minutes: fetch the published code/machine revision, refresh secrets
set -euo pipefail

SUPPORT_CONSOLE_ENV="CHANGEME"        # e.g. staging.in
SUPPORT_CONSOLE_BUCKET="CHANGEME"     # e.g. irm-support-console-staging-in
SUPPORT_CONSOLE_DB_PARAM="CHANGEME"   # e.g. /irm/support-console/staging.in/replica
SUPPORT_CONSOLE_SECRET_PARAM="CHANGEME" # e.g. /irm/support-console/staging.in/relay-secret
# How Claude Code signs in (E32): "subscription" (a `claude setup-token` token from Parameter Store) or "bedrock".
SUPPORT_CONSOLE_AUTH="CHANGEME"
SUPPORT_CONSOLE_TOKEN_PARAM="CHANGEME"  # e.g. /irm/support-console/staging.in/claude-token (subscription only)
SUPPORT_CONSOLE_MODEL_SONNET="CHANGEME" # model for "Sonnet" (the default in the console): an alias or a Bedrock id
SUPPORT_CONSOLE_MODEL_OPUS="CHANGEME"   # model for "Opus"
SUPPORT_CONSOLE_ALLOW_WRITER="0"      # "1" only on staging (no read replica); ignored for production

TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')
AWS_REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

# Node 22 (for Claude Code and the relay), jq, the AWS CLI, then the Claude Code CLI itself.
apt-get update
apt-get install -y ca-certificates curl gnupg unzip jq
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install && rm -rf /tmp/aws /tmp/awscliv2.zip
npm install -g @anthropic-ai/claude-code

# The service user: no login shell, no sudo. Owns the client folders and Claude Code's state.
useradd --system --create-home --home-dir /var/lib/support-console --shell /usr/sbin/nologin support-console
install -d -o support-console -g support-console -m 0750 /clients
install -d -o root -g root -m 0755 /code /opt/support-console
install -d -o root -g support-console -m 0750 /etc/support-console

cat > /etc/support-console/settings <<EOF
SUPPORT_CONSOLE_ENV="$SUPPORT_CONSOLE_ENV"
SUPPORT_CONSOLE_BUCKET="$SUPPORT_CONSOLE_BUCKET"
SUPPORT_CONSOLE_DB_PARAM="$SUPPORT_CONSOLE_DB_PARAM"
SUPPORT_CONSOLE_SECRET_PARAM="$SUPPORT_CONSOLE_SECRET_PARAM"
SUPPORT_CONSOLE_AUTH="$SUPPORT_CONSOLE_AUTH"
SUPPORT_CONSOLE_TOKEN_PARAM="$SUPPORT_CONSOLE_TOKEN_PARAM"
SUPPORT_CONSOLE_MODEL_SONNET="$SUPPORT_CONSOLE_MODEL_SONNET"
SUPPORT_CONSOLE_MODEL_OPUS="$SUPPORT_CONSOLE_MODEL_OPUS"
SUPPORT_CONSOLE_ALLOW_WRITER="$SUPPORT_CONSOLE_ALLOW_WRITER"
AWS_REGION="$AWS_REGION"
PRIVATE_IP="$PRIVATE_IP"
EOF

# The sync: published revisions in, secrets refreshed, the relay restarted only when something changed.
cat > /usr/local/bin/support-console-sync <<'SYNC'
#!/usr/bin/env bash
set -euo pipefail
. /etc/support-console/settings
export AWS_REGION
changed=0

# One published bundle (code or machine): <prefix>/current names the revision to run.
fetch() {
  local prefix=$1 root=$2
  local rev
  rev=$(aws s3 cp "s3://$SUPPORT_CONSOLE_BUCKET/$prefix/current" - 2>/dev/null | tr -d '[:space:]') || return 0
  [ -n "$rev" ] || return 0
  if [ ! -d "$root/$rev" ]; then
    aws s3 cp "s3://$SUPPORT_CONSOLE_BUCKET/$prefix/$rev.tar.gz" "/tmp/$prefix-$rev.tar.gz"
    mkdir -p "$root/$rev.partial" && tar -xzf "/tmp/$prefix-$rev.tar.gz" -C "$root/$rev.partial"
    mv "$root/$rev.partial" "$root/$rev" && rm -f "/tmp/$prefix-$rev.tar.gz"
  fi
  if [ "$(readlink "$root/current" 2>/dev/null)" != "$root/$rev" ]; then
    # E12 — a turn in flight keeps the revision it resolved; the next turn reads this one.
    ln -sfn "$root/$rev" "$root/current.new" && mv -T "$root/current.new" "$root/current"
    if [ "$prefix" = machine ]; then changed=1; fi
  fi
  return 0
}
fetch code /code
fetch machine /opt/support-console

# Secrets from Parameter Store, written for the service user only.
replica=$(aws ssm get-parameter --name "$SUPPORT_CONSOLE_DB_PARAM" --with-decryption --query Parameter.Value --output text)
secret=$(aws ssm get-parameter --name "$SUPPORT_CONSOLE_SECRET_PARAM" --with-decryption --query Parameter.Value --output text)
# E32 — how Claude Code signs in. A rotated token (support_console:claude_token) lands here within 5 minutes.
if [ "$SUPPORT_CONSOLE_AUTH" = subscription ]; then
  claude_token=$(aws ssm get-parameter --name "$SUPPORT_CONSOLE_TOKEN_PARAM" --with-decryption --query Parameter.Value --output text)
  claude_auth="CLAUDE_CODE_OAUTH_TOKEN=$claude_token"
else
  claude_auth="CLAUDE_CODE_USE_BEDROCK=1"
fi
umask 077
printf '%s' "$(jq -r .SUPPORT_DB_PASSWORD <<<"$replica")" > /etc/support-console/db_password.new
cat > /etc/support-console/machine.env.new <<EOF
SUPPORT_CONSOLE_DEPLOYED=1
SUPPORT_CONSOLE_ENV=$SUPPORT_CONSOLE_ENV
SUPPORT_CONSOLE_ALLOW_WRITER=$SUPPORT_CONSOLE_ALLOW_WRITER
SUPPORT_CONSOLE_RELAY_SECRET=$secret
RELAY_HOST=$PRIVATE_IP
RELAY_PORT=4900
SUPPORT_CONSOLE_CODE_DIR=/code/current
SUPPORT_CONSOLE_CLIENTS_DIR=/clients
# One Claude Code config folder per client (X22), in the relay user's writable home, not under /clients.
SUPPORT_CONSOLE_CLAUDE_DIR=/var/lib/support-console/claude-clients
SUPPORT_DB_HOST=$(jq -r .SUPPORT_DB_HOST <<<"$replica")
SUPPORT_DB_PORT=$(jq -r '.SUPPORT_DB_PORT // "3306"' <<<"$replica")
SUPPORT_DB_NAME=$(jq -r .SUPPORT_DB_NAME <<<"$replica")
SUPPORT_DB_USER=$(jq -r .SUPPORT_DB_USER <<<"$replica")
SUPPORT_DB_PASSWORD_FILE=/etc/support-console/db_password
SUPPORT_CONSOLE_AUTH=$SUPPORT_CONSOLE_AUTH
$claude_auth
AWS_REGION=$AWS_REGION
SUPPORT_CONSOLE_MODEL_SONNET=$SUPPORT_CONSOLE_MODEL_SONNET
SUPPORT_CONSOLE_MODEL_OPUS=$SUPPORT_CONSOLE_MODEL_OPUS
EOF
for f in machine.env db_password; do
  chown root:support-console "/etc/support-console/$f.new" && chmod 0440 "/etc/support-console/$f.new"
  if ! cmp -s "/etc/support-console/$f.new" "/etc/support-console/$f"; then
    mv "/etc/support-console/$f.new" "/etc/support-console/$f"; changed=1
  else
    rm -f "/etc/support-console/$f.new"
  fi
done

if [ "$changed" = 1 ] && [ -e /opt/support-console/current ]; then
  systemctl restart support-console-relay
fi
SYNC
chmod 0755 /usr/local/bin/support-console-sync

cat > /etc/systemd/system/support-console-relay.service <<'UNIT'
[Unit]
Description=Support Console relay (Claude Code headless, read-only replica)
After=network-online.target
Wants=network-online.target

[Service]
User=support-console
Group=support-console
EnvironmentFile=/etc/support-console/machine.env
WorkingDirectory=/opt/support-console/current
ExecStart=/usr/bin/node /opt/support-console/current/relay/server.js
Restart=always
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/clients /var/lib/support-console
ProtectHome=false
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/support-console-sync.service <<'UNIT'
[Unit]
Description=Support Console: fetch the published code and machine revisions, refresh secrets

[Service]
Type=oneshot
ExecStart=/usr/local/bin/support-console-sync
UNIT

cat > /etc/systemd/system/support-console-sync.timer <<'UNIT'
[Unit]
Description=Support Console sync every 5 minutes

[Timer]
OnBootSec=30
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
/usr/local/bin/support-console-sync || true
systemctl enable --now support-console-sync.timer
systemctl enable --now support-console-relay
