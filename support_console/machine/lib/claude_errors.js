// Sorts a failed Claude Code run into the reasons Rails tells apart (design X28, X29). Claude Code
// reports these as text — the result's message or stderr — so this reads the text; anything it does
// not recognise stays the generic claude_failed.
//   auth_failed  — X29: the subscription token expired or was revoked (or Bedrock refused the role)
//   usage_limit  — X28: the subscription's usage limit was reached; answers resume when it resets

// Checked first: an expired token can also mention limits in the same message.
const AUTH = /oauth token|invalid api key|authentication|unauthori[sz]ed|\b401\b|please run \/login|not logged in|credit balance/i
const USAGE = /usage limit|hit your limit|limit reached|limit will reset|resets? at|rate.?limit|\b429\b/i

// @returns {"auth_failed"|"usage_limit"|"claude_failed"}
export function classifyClaudeError(text) {
  const message = String(text || "")
  if (AUTH.test(message)) return "auth_failed"
  if (USAGE.test(message)) return "usage_limit"
  return "claude_failed"
}
