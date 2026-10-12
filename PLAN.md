# rolify_cr — 1:1 port of rolify 6.0.1 (ActiveRecord adapter) to Crystal
# over active_record_cr.

Status / scope (see oracle/ for the source of truth):

- `rolify` macro: HABTM `roles` with rolify's `"#{user_table}_#{role_table}"`
  join-table naming (overridable via `role_join_table_name`), HABTM
  callbacks `before_add`/`after_add`/`before_remove`/`after_remove`
  (pass-through to active_record_cr's CollectionProxy), `add_role`/
  `has_role?`/`remove_role` (+ `grant`/`revoke` aliases), `has_all_roles?`,
  `has_any_role?`, `only_has_role?`, `has_cached_role?`,
  `has_strict_cached_role?`, `roles_name`, strict mode.
- Class finders: `with_role`, `without_role`, `with_all_roles`,
  `with_any_role`, `role_class`.
- Role side: `scopify` macro → `global`, `class_scoped`, `instance_scoped`.
- Resource side: `resourcify` macro → `find_roles`, `with_role` (+
  `with_roles` alias), `without_role`, `applied_roles` (class + instance).

Deviations (documented, oracle cases adjusted accordingly):

- Dynamic shortcuts (`is_admin?`, `is_moderator_of?`, Rolify.dynamic_shortcuts)
  rely on runtime method definition — impossible in Crystal; use `has_role?`.
  Oracle cases never exercised them.
- `roles << role` on an unsaved record (deferred join insert) is not
  supported by active_record_cr's CollectionProxy; `has_role?` on a new
  record therefore always scans empty → false (oracle case kept in this
  reduced form).
- RSpec matchers (`have_role`, `be_the_same_role`) are rspec-specific and
  out of scope.

Oracle: gem 6.0.1 over SQLite in-memory (`oracle/cases.rb`), cases lifted
from the gem's own spec suite; the Crystal spec replays them 1:1 against
PostgreSQL and must reproduce `oracle/expected.yml` exactly.
