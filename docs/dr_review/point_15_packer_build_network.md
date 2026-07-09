# DR Review — Point 15: Packer's shadow network — make it explicit, safe, and disposable

**Status:** ✅ Applied (`ruby -c` passes):
- Build network renamed `packer-build-<region>` (VPC/subnet/IGW/rtb/SG) with `Purpose=packer-build` tags; CIDR moved to 10.99.0.0/16 so it can never be confused with the app VPC's 10.0.0.0/16.
- All backtick `aws` CLI provisioning replaced with `Aws::EC2` SDK calls — find-or-create, loud failures, idempotent (caller-IP SSH rule handles `InvalidPermissionDuplicate`).
- Build SG: SSH from the caller's public IP only (`checkip.amazonaws.com`, override `PACKER_SSH_CIDR`); the 0.0.0.0/0 ports 22/80/443 ingress is gone.
- Source-AMI SSM lookup now fails loudly instead of passing empty strings to Packer.
- New `packer:teardown_build_network[region]` deletes only `Purpose=packer-build` resources; legacy `IRM-<region>` build VPCs are untouched (manual removal once confirmed unused).
**Repo affected:** `IRM`
**File:** `lib/tasks/packer.rake` (network provisioning, `fetch_aws_resource_ids`)
**Severity:** Medium — two sources of truth for networking, plus fragile shell-outs and an over-open security group in the AMI build path.

---

## 1. What exists today

`packer.rake:37-156` creates its own VPC (tagged `IRM-<region>`), subnet `10.0.1.0/24`, IGW, route table and SG (`web-sg-<region>-<variant>`) via backtick `aws` CLI calls, so Packer has somewhere to launch build instances. Problems:

1. **It masquerades as app infrastructure.** The VPC tag `IRM-<region>` is exactly what the *real* Pulumi VPC looks like (`network.py` tags `IRM-{region}-{stack}`). An operator listing VPCs cannot tell the build scaffolding from production networking; cleanup tasks (`aws:cleanup_unused_vpcs_and_subnets`) could grab the wrong one.
2. **Backticks with no error handling.** Every call is `` `aws ec2 ...` `` checked against the literal string `"None"` — a network error, credential failure, or CLI change silently produces empty IDs that surface later as a cryptic Packer failure.
3. **SSH open to the world.** The build SG ingress is `0.0.0.0/0:22` (`packer.rake:143`) — every AMI build runs a root-credentialed instance reachable from the entire internet for the duration of the bake.
4. **Nothing is ever torn down** — the build network persists in every region ever baked in.

## 2. Why NOT reuse the Pulumi VPC (the obvious idea, rejected)

Chicken-and-egg: **AMIs must exist before the Pulumi stack can be created** (the stack config requires AMI IDs). In a brand-new region, Packer runs first — there is no Pulumi VPC yet. A dedicated, ephemeral build network is therefore *correct*; the fix is making it honest, robust, and disposable rather than eliminating it.

## 3. Proposed changes

1. **Rename/retag** everything the build path creates: VPC `packer-build-<region>`, SG `packer-build-sg-<region>-<variant>`, subnet/IGW/route table likewise, plus a `Purpose=packer-build` tag on all of it. No more masquerading; cleanup tasks can safely filter it.
2. **Replace backticks with `Aws::EC2` SDK calls** (the repo already depends on `aws-sdk-ec2`): find-by-tag-or-create, raising with a clear message on any failure instead of limping on with empty IDs. Idempotent — re-running converges on the same network.
3. **Close the SSH hole:** ingress restricted to the caller's public IP (resolved at build time), overridable via `PACKER_SSH_CIDR` for CI. The bake instance stops being a world-reachable target.
4. **New `packer:teardown_build_network[region]` task** — deletes the tagged build network when a region is decommissioned (or between rare bakes, if you prefer zero standing scaffolding).
5. **Migration note:** existing legacy-named build VPCs (`IRM-<region>` without a stack suffix) are left alone but no longer used; the teardown task's doc covers removing them manually once confirmed unused.

## 4. Blast radius

- AMI bakes in already-baked regions will create the new `packer-build-*` network on first run (the old one is simply no longer referenced). Weekly bakes continue uninterrupted either way — the fallback creation is idempotent.
- No Pulumi resources touched; no live app infra touched.
- SG tightening only affects build instances (operator/CI must be able to SSH — hence the override).

## 5. Verification

1. `ruby -c`; `rake "packer:check_env[dev,in]"` still validates.
2. First bake in staging: confirm the new network appears with `Purpose=packer-build` tags, SG ingress = caller IP only, and the AMI builds.
3. `packer:teardown_build_network[<region>]` removes it cleanly; re-bake recreates it.
