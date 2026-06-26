# ActionCable / WebSocket Alert Recovery

## Symptom

Real-time alerts (file downloads, background job notifications) stop appearing in the UI after a server restart or unhealthy period. Rails logs show broadcasts completing successfully, but nothing reaches the browser.

```
[ActionCable] Broadcasting to user_alert_171: "<turbo-stream ..."
=> 0
```

The `=> 0` return value from `ActionCable.server.broadcast` is the Redis pub/sub subscriber count — **0 means Puma has no listeners registered**, so the message is lost.

---

## Root Cause

The WebSocket and Turbo were both fine. What broke was ActionCable's internal Redis pub/sub subscriber thread inside Puma.

The full message chain:

```
Browser ──WebSocket──▶ Nginx ──▶ Puma/ActionCable ──▶ Redis pub/sub
                        ✅                ❌
```

After an unclean instance restart or extended unhealthy period, Puma lost its Redis pub/sub subscriptions internally. The browser's WebSocket reconnected at the TCP level (`readyState: 1`, state: `'open'`) and Turbo had a subscription object ready — but ActionCable inside Puma never re-registered as a Redis listener. So when a broadcast arrived via Redis, nobody inside Puma was listening to forward it to the WebSocket clients.

Broken flow:

```
Rails job
  → ActionCable.server.broadcast("user_alert_171", ...)
    → publishes to Redis ✅
      → Puma should receive from Redis and push to WebSocket ❌ (listener dead)
        → browser never gets it
```

Turbo's `turbo-cable-stream-source` element existed in the DOM and had a subscription object ready — it was waiting for ActionCable to confirm the subscription, which never came because Puma's Redis listener was dead.

---

## How to Debug

### 1. Check if the broadcast is reaching subscribers (prod Rails console)

```ruby
ActionCable.server.broadcast(
  "user_alert_<user_id>",
  "<turbo-stream action='replace' target='user_alert'><template><div id='user_alert' class='page_alerts'><div class='alert alert-success'>TEST</div></div></template></turbo-stream>"
)
# => 0  means broken (no Redis subscribers)
# => 1+ means working
```

### 2. Confirm in the browser (DevTools console)

```javascript
// Is the channel subscription confirmed by ActionCable?
document.querySelector("turbo-cable-stream-source").hasAttribute("connected");
// false = broken, true = working

// Is the WebSocket itself open?
const sub = document.querySelector("turbo-cable-stream-source").subscription;
sub.consumer.connection.webSocket; // null = never opened
sub.consumer.connection.getState(); // 'open' / 'closed'
```

### 3. Distinguish the two failure modes

| Symptom                                                                        | Meaning                                                |
| ------------------------------------------------------------------------------ | ------------------------------------------------------ |
| WebSocket `readyState: 3` (closed) + Socket tab empty in DevTools              | WS connection dead — nginx or network issue            |
| WebSocket `readyState: 1` (open) + broadcast returns `0` + no `connected` attr | ActionCable broken inside Puma — phased restart needed |

---

## Fix

Trigger a **phased restart** on each prod server — restarts Puma workers one at a time with no HTTP downtime. WebSocket clients drop for ~2-3 seconds then auto-reconnect.

```bash
# Get the Puma master PID
cat /home/ubuntu/IRM/shared/tmp/pids/puma.pid

# Trigger phased restart
kill -SIGUSR1 <pid>
```

Run on each server, **staggered by ~30 seconds** to maintain full capacity:

```bash
# Server 1
kill -SIGUSR1 19655

# Wait 30 seconds, then Server 2
kill -SIGUSR1 19289
```

Confirm recovery by tailing the log:

```bash
tail -f /home/ubuntu/IRM/shared/log/puma.log
# Look for: "Worker N (pid: XXXX) booted in Xs"
```

After restart, re-run the broadcast test — it should return `1` and `hasAttribute("connected")` should be `true`.

---

## Why Not Restart Puma Fully?

A full Puma restart (`systemctl restart puma`) works but drops all in-flight HTTP requests. SIGUSR1 (phased restart) is safer: old workers finish current requests before stopping, new workers come up fresh. No request is dropped.
