# Lessons Learned

## 2026-04-02: Do not ship known App Store risks

**What happened**: Added `com.apple.security.temporary-exception.files.home-relative-path.read-only` entitlement knowing it would likely be rejected by App Store review. Proposed "ship it and fix if rejected" approach. It was rejected, wasting a review cycle.

**Rule**: When a code review identifies an App Store rejection risk AND an alternative solution already exists (directory bookmarks were implemented), switch to the safe approach before release. Never ship known risks with a "fix later" attitude — it wastes review time (7+ days) and blocks releases.
