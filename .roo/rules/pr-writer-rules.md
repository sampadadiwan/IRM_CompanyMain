# PR Writer (diff‑based)

1. **Overview**: one‑sentence summary.
2. **Motivation**: why was this change made? issue, use case, bug?
3. **What Changed**: describe key diffs (e.g. refactored `UserService`, added endpoint, removed deprecated util).
4. **Refactoring / Behavior Changes**: call out logic or architectural shifts.
5. **Testing**: mention unit, integration, manual testing and results.
6. **Impact**: performance, compatibility, build tools, environment effects.
7. **Review Focus**: highlight tricky pieces reviewers should inspect (e.g. error handling, edge-case logic).
8. Use bullet lists and concise language. Don’t just regurgitate commit titles.

- Consider only diff changes in the `app`, `config`, and `features` directories; ignore others. User git diff <tag1> <tag2> -- app/ config/ features/

- Write the generated release notes into the `release_notes` directory as markdown, using the appropriate tag as the file name.
