# Core

## Reference types

A reference-type admin page is a spec on `Bilimbi.Core.Company.Web.ReferenceTypesLive`, not a copied LiveView. The moduledoc owns the contract.

## Address panels

An owner-specific address panel is a parameter on `Bilimbi.Core.Address.Web.AddressesPanel`, not a second LiveComponent. The company and employee pages pass `company_id` or `employee_id`; the panel owns the capability, the noun, and whether creating an address is offered. Location fields on an address form are `Bilimbi.Core.Address.Web.LocationFields`, and the postcode cascade is `Bilimbi.Core.Address.LocationSuggestion`.

## An archived company is final

Archiving a company freezes it and everything it owns for good, user accounts included (`require_writable_company/2`; `apps/core/company/AGENTS.md`). There is no restore, and no moving an account out. A frozen account keeps its email, so a person who moves on needs a different email for a new account. The user page says this and offers no next step (`archived_account_notice/1` in `apps/core/user/lib/user/web/show_live.ex`). Do not add a restore, a transfer, or an email release. The decision is recorded in https://github.com/BelimbingApp/bilimbi/pull/786.

## Employment facts belong to their registered owner

A module that owns employment facts (People) hears Core's HR writes through `Bilimbi.Core.Employee.register_employment_owner/1` and reads Core's rows through `person_identities/2` and `hr_handoff_page/3`, not through a descriptor edge from Core, a copy of Core's queries, or one `person_identity/2` call per row. Core must behave the same with no owner registered. The contract is the moduledoc of `Bilimbi.Core.Employee.EmploymentOwner` and `apps/core/employee/docs/README.md` "Employment owner and HR handoff".

## Maintaining this file

Keep this note short. Point at the component, its comment, or DESIGN.md; do not copy them.
