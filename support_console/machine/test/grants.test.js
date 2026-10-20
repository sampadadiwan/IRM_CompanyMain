// X21 — the grants check run when the data tool connects (lib/db.js).
import { test } from "node:test"
import assert from "node:assert/strict"
import { onlyReadGrants } from "../lib/db.js"

// X21 — Error case: support_ro holding anything beyond SELECT, SHOW VIEW or REPLICATION CLIENT is refused
test("X21 — only USAGE, SELECT, SHOW VIEW and REPLICATION CLIENT pass", () => {
  assert.equal(onlyReadGrants([
    "GRANT USAGE ON *.* TO `support_ro`@`%`",
    "GRANT REPLICATION CLIENT ON *.* TO `support_ro`@`10.0.3.9`",
    "GRANT SELECT, SHOW VIEW ON `IRM_production`.* TO `support_ro`@`10.0.3.9`",
    "GRANT SELECT (id, name) ON `IRM_production`.`funds` TO `support_ro`@`10.0.3.9`",
  ]), true)
  assert.equal(onlyReadGrants(["GRANT SELECT, INSERT ON `IRM_production`.* TO `support_ro`@`%`"]), false)
  assert.equal(onlyReadGrants(["GRANT FILE ON *.* TO `support_ro`@`%`"]), false)
  assert.equal(onlyReadGrants(["GRANT PROCESS ON *.* TO `support_ro`@`%`"]), false)
  assert.equal(onlyReadGrants(["GRANT ALL PRIVILEGES ON *.* TO `support_ro`@`%`"]), false)
  // A role's rights are not listed here, so a role grant is refused.
  assert.equal(onlyReadGrants(["GRANT `reporting`@`%` TO `support_ro`@`%`"]), false)
})
