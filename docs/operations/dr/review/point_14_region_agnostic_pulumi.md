# DR Review — Point 14: Region-agnostic Pulumi

**Status:** ✅ Applied — `py_compile` passes; all six stack YAMLs validated to carry exactly the plain key set (`web_server_ami`, `db_server_ami`, `observability_ami`, `key_name`, `region`, `domain_name`); `ruby -c` passes on the generator. Pending your `pulumi preview` per stack to confirm zero diffs.
**Repo affected:** `IRM-Infra` (+ small `IRM` generator change)
**Severity:** Medium — two classes of "works in the regions we've tried, breaks in the next one" hardcoding. Both directly serve the "flexible for other regions tomorrow" goal.

---

## 1. Problem A: hardcoded AZ suffixes

`network.py:22,30,37,44` pin subnets to `{region}a` and `{region}b`. Fails when:

- A region doesn't expose AZs under those letters (some regions/accounts have `b`/`c` but not `a` enabled — e.g. accounts where `us-east-1a` maps differently, or newer regions with non-contiguous AZ names).
- An AZ is disabled for the account (opt-in regions like ap-south-2 can have restricted AZ sets).

**Fix:** ask AWS at deploy time: `aws.get_availability_zones(state="available")` through the stack's provider, take the first two. Same topology (2 public + 2 private across two AZs), zero assumptions about names. In the regions already deployed, the first two available AZs *are* `a`/`b`, so `pulumi preview` shows **no changes** for existing stacks — this is a no-op for live infra.

## 2. Problem B: region-prefixed config keys

Every stack file carries keys like `ap-south-2_web_server_ami`, and `__main__.py` reconstructs the key name from the `region` value at runtime. This indirection is what produced **Point 1's Bug A** (an AMI filed under the wrong region's key → un-deployable DR stack), and it makes every new region a copy-paste-rename exercise.

The prefix adds nothing: each stack file already *is* per-region — a key named `web_server_ami` inside `Pulumi.production-ap-south-2.yaml` is unambiguous.

**Fix (backwards compatible):**

- `__main__.py` reads the **plain key first**, falls back to the legacy region-prefixed key:
  ```python
  def cfg(key):  # plain preferred, legacy fallback
      return config.get(key) or config.require(f"{region}_{key}")
  ```
- All 6 stack files migrate to plain keys (`web_server_ami`, `db_server_ami`, `observability_ami`, `key_name`) in this change.
- The rake generator (`setup_pulumi_config`) and `ensure_pulumi_stack_config` write/check plain keys going forward.
- The fallback means any straggler file (or an old branch) still deploys — nothing breaks mid-transition.

**What this eliminates:** the entire wrong-region-prefix bug class, and one more per-region edit when standing up a new landing zone. After this, a new region's stack config is *identical in shape* to every other region's — only the values differ.

## 3. Out of scope (deliberately)

- **AMI lookup-by-tag inside Pulumi** (resolving "latest AppServer AMI" at deploy time): rejected. Pinned IDs refreshed by `aws:setup_pulumi_config` are *deterministic* — a DR `pulumi up` deploys exactly the AMI the config says, not whatever got baked five minutes ago. The rake task is the controlled refresh point.
- ALB/IAM naming: ALB names are per-region (no collision); the `RailsAppRole` account-global singleton is handled with IAM scope-down in Point 18.

## 4. Files touched

| File | Change |
|---|---|
| `IRM-Infra/network.py` | dynamic AZ lookup, comments |
| `IRM-Infra/__main__.py` | `cfg()` helper with legacy fallback |
| `IRM-Infra/Pulumi.*.yaml` (6) | keys renamed to plain form |
| `IRM/lib/tasks/aws_utils.rb` | generator + ensure write/check plain keys |

## 5. Verification

1. `python3 -m py_compile` on both .py files; YAML parse check on all 6 stack files.
2. `pulumi preview` per stack (needs your login): **expect zero diffs** — same AZs resolved dynamically, same AMIs under new key names.
3. New-region rehearsal is covered by the existing one-command flow (`DOMAIN_NAME=... AWS_KEY_NAME=... rake aws:setup_pulumi_config[...]`) which now emits plain keys.
