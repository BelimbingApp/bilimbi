# Core

## Reference types

A reference-type admin page is a spec on `Bilimbi.Core.Company.Web.ReferenceTypesLive`, not a copied LiveView. The moduledoc owns the contract.

## Address panels

An owner-specific address panel is a parameter on `Bilimbi.Core.Address.Web.AddressesPanel`, not a second LiveComponent. The company and employee pages pass `company_id` or `employee_id`; the panel owns the capability, the noun, and whether creating an address is offered. Location fields on an address form are `Bilimbi.Core.Address.Web.LocationFields`, and the postcode cascade is `Bilimbi.Core.Address.LocationSuggestion`.

## An archived company is final

Archiving a company freezes it and everything it owns for good, user accounts included (`require_writable_company/2`; `apps/core/company/AGENTS.md`). There is no restore, and no moving an account out. A frozen account keeps its email, so a person who moves on needs a different email for a new account. The user page says this and offers no next step (`archived_account_notice/1` in `apps/core/user/lib/user/web/show_live.ex`). Do not add a restore, a transfer, or an email release. The decision is recorded in https://github.com/BelimbingApp/bilimbi/pull/786.

## Maintaining this file

Keep this note short. Point at the component, its comment, or DESIGN.md; do not copy them.
