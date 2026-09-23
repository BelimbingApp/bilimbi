# Core

## An archived company is final

Archiving a company freezes its user accounts for good. There is no restore, and no moving an account out. A frozen account keeps its email, so a person who moves on needs a different email for a new account. The user page says this and offers no next step (`archived_account_notice/1` in `apps/core/user/lib/user/web/show_live.ex`). Do not add a restore, a transfer, or an email release. The decision is recorded in https://github.com/BelimbingApp/bilimbi/pull/786.

## Maintaining this file

Keep this note short. Point at the component, its comment, or DESIGN.md; do not copy them.
