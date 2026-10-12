# rolify.cr

A 1:1 Crystal port of **rolify 6.0.1** (ActiveRecord adapter) on top of
`active_record.cr` — role management with HABTM roles, class/instance
scoped roles and strict mode.

> ⚠️ EXPERIMENTAL — DO NOT USE IN PRODUCTION YET.

## Installation

```yaml
dependencies:
  rolify_cr:
    github: OrelSokolov/rolify.cr
```

```sh
shards install
```

Depends on `active_record.cr`.

## Usage

```crystal
class User < ActiveRecord::Base
  rolify role_join_table_name: "users_roles"   # optional override
end

class Role < ActiveRecord::Base
  scopify
end

class Forum < ActiveRecord::Base
  resourcify
end

user.add_role(:admin)
user.add_role(:moderator, forum)
user.has_role?(:admin)                # => true
user.has_role?(:moderator, forum)     # => true, scoped

User.with_role(:moderator, forum)
User.without_role(:admin)
forum.find_roles(:moderator, user)
```

## Feature comparison vs rolify 6.0.1

### User side (`rolify` macro)

| Feature | Original (rolify) | Port (rolify.cr) | Status |
|---|---|---|---|
| HABTM `roles` with rolify's `"#{user_table}_#{role_table}"` join naming (overridable via `role_join_table_name`) | ✅ | Same | ✅ |
| HABTM callbacks `before_add`/`after_add`/`before_remove`/`after_remove` | ✅ | Pass-through to active_record_cr's CollectionProxy | ✅ |
| `add_role` / `has_role?` / `remove_role` (+ `grant`/`revoke` aliases) | ✅ | Same | ✅ |
| `has_all_roles?`, `has_any_role?`, `only_has_role?` | ✅ | Same | ✅ |
| `has_cached_role?`, `has_strict_cached_role?`, `roles_name`, strict mode | ✅ | Same | ✅ |
| Class finders: `with_role`, `without_role`, `with_all_roles`, `with_any_role`, `role_class` | ✅ | Same | ✅ |
| Dynamic shortcuts (`is_admin?`, `is_moderator_of?`, `Rolify.dynamic_shortcuts`) | ✅ | Runtime method definition is impossible in Crystal — use `has_role?` (oracle cases never exercised them) | ❌ (equivalent: `has_role?`) |
| `roles << role` on an unsaved record (deferred join insert) | ✅ | Not supported by active_record_cr's CollectionProxy; `has_role?` on a new record scans empty → false (oracle case kept in this reduced form) | ❌ |

### Role side (`scopify`) and resource side (`resourcify`)

| Feature | Original | Port | Status |
|---|---|---|---|
| `scopify` → `global`, `class_scoped`, `instance_scoped` | ✅ | Same | ✅ |
| `resourcify` → `find_roles`, `with_role` (+ `with_roles`), `without_role`, `applied_roles` (class + instance) | ✅ | Same | ✅ |
| RSpec matchers (`have_role`, `be_the_same_role`) | ✅ | rspec-specific, out of scope | ❌ |

## Deviations & Crystal-specific notes

- Deviations are documented and the oracle cases were adjusted
  accordingly (see `PLAN.md`); everything else replays the gem 1:1.

## Testing

```sh
crystal spec
```

Oracle: gem 6.0.1 over SQLite in-memory (`oracle/cases.rb`), cases lifted
from the gem's own spec suite; the Crystal spec replays them 1:1 against
PostgreSQL and must reproduce `oracle/expected.yml` exactly.
