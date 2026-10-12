# Oracle cases for rolify 6.0.1 (ActiveRecord adapter). Cases are lifted
# from the gem's own spec suite (spec/rolify/shared_examples/**, mirrored
# in oracle/src/spec) minus mongoid/dynamic-shortcut/RSpec-matcher bits.
#
# Run against the ORIGINAL gem:
#   ruby oracle/cases.rb > oracle/expected.yml
#
# Each line: "<case_id>\t<value>" (control chars escaped). Mirrored 1:1
# in spec/oracle_spec.cr.

gem "rolify", "= 6.0.1"
gem "activerecord", "= 8.1.4"
gem "activesupport", "= 8.1.4"
gem "sqlite3", ">= 2.1"
require "active_record"
require "rolify"

ActiveRecord::Base.extend Rolify

ActiveRecord::Migration.verbose = false
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.define do
  create_table :roles do |t|
    t.string :name
    t.references :resource, polymorphic: true
    t.timestamps null: false
  end
  create_table :users do |t|
    t.string :login
  end
  create_table :users_roles, id: false do |t|
    t.references :user
    t.references :role
  end
  create_table :strict_users do |t|
    t.string :login
  end
  create_table :strict_users_roles, id: false do |t|
    t.references :strict_user
    t.references :role
  end
  create_table :callback_users do |t|
    t.string :login
  end
  create_table :callback_users_roles, id: false do |t|
    t.references :callback_user
    t.references :role
  end
  create_table :custom_users do |t|
    t.string :login
  end
  create_table :custom_users_and_roles, id: false do |t|
    t.references :custom_user
    t.references :role
  end
  create_table :forums do |t|
    t.string :name
  end
  create_table :groups do |t|
    t.string :name
  end
end

class User < ActiveRecord::Base
  rolify
end

class StrictUser < ActiveRecord::Base
  rolify strict: true
end

class CustomUser < ActiveRecord::Base
  rolify role_join_table_name: :custom_users_and_roles
end

class CallbackUser < ActiveRecord::Base
  rolify before_add: :log_before_add, after_add: :log_after_add,
         before_remove: :log_before_remove, after_remove: :log_after_remove

  def log_before_add(role)
    $cb_log << "before_add:#{role.name}"
  end

  def log_after_add(role)
    $cb_log << "after_add:#{role.name}"
  end

  def log_before_remove(role)
    $cb_log << "before_remove:#{role.name}"
  end

  def log_after_remove(role)
    $cb_log << "after_remove:#{role.name}"
  end
end

class Role < ActiveRecord::Base
  has_and_belongs_to_many :users, join_table: :users_roles
  has_and_belongs_to_many :strict_users, join_table: :strict_users_roles
  has_and_belongs_to_many :custom_users, join_table: :custom_users_and_roles
  has_and_belongs_to_many :callback_users, join_table: :callback_users_roles
  belongs_to :resource, polymorphic: true, optional: true
  extend Rolify::Adapter::Scopes
end

class Forum < ActiveRecord::Base
  resourcify
end

class Group < ActiveRecord::Base
  resourcify
end

def render(v)
  s = v.is_a?(String) ? v : v.inspect
  s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

def logins(users)
  users.map(&:login).sort
end

# --- data (mirrors spec/support/data.rb + shared_contexts) ----------------
User.create(login: "admin")
User.create(login: "moderator")
User.create(login: "god")
Forum.create(name: "forum 1")
Forum.create(name: "forum 2")
Forum.create(name: "forum 3")
Group.create(name: "group 1")
Group.create(name: "group 2")

ADMIN     = User.find_by!(login: "admin")
MODERATOR = User.find_by!(login: "moderator")
GOD       = User.find_by!(login: "god")
FORUMS    = Forum.all.to_a
GROUPS    = Group.all.to_a

ADMIN.add_role :admin
ADMIN.add_role :staff
ADMIN.add_role :manager, Group
ADMIN.add_role :player, Forum
ADMIN.add_role :moderator, FORUMS.last
ADMIN.add_role :moderator, GROUPS.last
ADMIN.add_role :anonymous, FORUMS.first

GOD.add_role :moderator, Forum
GOD.add_role :player, Forum

# --- add_role / global roles (shared_examples_for_add_role, :global) ------
case_run("add_global_role_returns_role") { ADMIN.add_role(:admin).class.name }
case_run("add_global_role_name")         { ADMIN.add_role(:admin).name }
case_run("add_global_role_no_resource")  { ADMIN.add_role(:admin).resource.nil? }
case_run("add_role_returns_existing")    { ADMIN.add_role(:admin).id == Role.find_by(name: "admin").id }
case_run("role_count_admin")             { ADMIN.roles.length }
case_run("role_count_god")               { GOD.roles.length }

# --- has_role? (shared_examples_for_has_role, all scopes) -----------------
case_run("has_global_true")     { ADMIN.has_role?(:admin) }
case_run("has_global_false")    { ADMIN.has_role?(:warlock) }
case_run("has_class_true")      { ADMIN.has_role?(:manager, Group) }
case_run("has_class_false")     { ADMIN.has_role?(:manager, Forum) }
case_run("has_instance_true")   { ADMIN.has_role?(:moderator, FORUMS.last) }
case_run("has_instance_false")  { ADMIN.has_role?(:moderator, FORUMS.first) }
case_run("has_any_resource")    { ADMIN.has_role?(:moderator, :any) }
case_run("has_any_no_resource") { ADMIN.has_role?(:manager, :any) }
case_run("has_role_string_name") { ADMIN.has_role?("admin") }
case_run("has_all_true")        { GOD.has_all_roles?({ name: :moderator, resource: Forum }, { name: :player, resource: Forum }) }
case_run("has_all_one_missing") { GOD.has_all_roles?({ name: :moderator, resource: Forum }, :warlock) }
case_run("has_all_mixed_args")  { ADMIN.has_all_roles?({ name: :admin }, "staff") }
case_run("has_any_true")        { ADMIN.has_any_role?(:warlock, :staff) }
case_run("has_any_false")       { ADMIN.has_any_role?(:warlock, { name: :wizard }) }
case_run("only_has_true")       { User.create(login: "solo").tap { |u| u.add_role(:solo) }.only_has_role?(:solo) }
case_run("only_has_false")      { GOD.only_has_role?(:moderator, Forum) }
case_run("roles_name")          { GOD.roles_name.sort }

# --- new-record behavior (before save, from shared examples) --------------
case_run("new_record_has_role") do
  u = User.new(login: "ghost")
  u.has_role?(:admin)
end

# --- remove_role (shared_examples_for_remove_role) ------------------------
case_run("remove_global") do
  u = User.create(login: "r1"); u.add_role(:admin)
  u.remove_role(:admin)
  u.has_role?(:admin)
end
case_run("remove_instance") do
  u = User.create(login: "r2"); u.add_role(:moderator, FORUMS.first)
  u.remove_role(:moderator, FORUMS.first)
  u.has_role?(:moderator, FORUMS.first)
end
case_run("remove_class_keeps_instance") do
  u = User.create(login: "r3"); u.add_role(:moderator, Forum); u.add_role(:moderator, FORUMS.first)
  u.remove_role(:moderator, Forum)
  [u.has_role?(:moderator, Forum), u.has_role?(:moderator, FORUMS.first)]
end
case_run("remove_returns_roles") do
  u = User.create(login: "r4"); u.add_role(:admin)
  u.remove_role(:admin).map(&:name)
end
case_run("remove_missing_role") do
  u = User.create(login: "r5")
  u.remove_role(:nonexistent).map(&:name)
end

# --- class finders on user (shared_examples_for_finders) ------------------
case_run("with_role_global")     { logins(User.with_role(:admin)) }
case_run("with_role_class")      { logins(User.with_role(:player, Forum)) }
case_run("with_role_instance")   { logins(User.with_role(:moderator, FORUMS.last)) }
case_run("with_role_none")       { logins(User.with_role(:warlock)) }
case_run("without_role_global")  { logins(User.without_role(:admin)) }
case_run("without_role_class")   { logins(User.without_role(:player, Forum)) }
case_run("with_all_roles")       { logins(User.with_all_roles({ name: :moderator, resource: Forum }, { name: :player, resource: Forum })) }
case_run("with_any_role")        { logins(User.with_any_role(:staff, { name: :player, resource: Group })) }
case_run("with_any_role_sym_str") { logins(User.with_any_role("admin", :player)) }

# --- role class scopes (shared_examples_for_scopes) -----------------------
case_run("scope_global")            { Role.global.map(&:name).sort }
case_run("scope_class_scoped")      { Role.class_scoped.map { |r| "#{r.name}:#{r.resource_type}" }.sort }
case_run("scope_class_scoped_type") { Role.class_scoped(Group).map(&:name).sort }
case_run("scope_instance_scoped")   { Role.instance_scoped.map { |r| "#{r.name}:#{r.resource_id}" }.sort }
case_run("scope_instance_scoped_type") { Role.instance_scoped(Forum).map(&:name).sort }
case_run("scope_instance_scoped_obj")  { Role.instance_scoped(FORUMS.last).map(&:name).sort }

# --- resource side (resourcify, from resource_spec) -----------------------
case_run("resource_find_roles") do
  Forum.find_roles(:moderator).map { |r| "#{r.name}:#{r.resource_type}:#{r.resource_id}" }.sort
end
case_run("resource_find_roles_user") do
  Forum.find_roles(:player, GOD).map(&:name)
end
case_run("resource_with_role") { Forum.with_role(:moderator).map(&:name).sort }
case_run("resource_with_role_user") { Forum.with_role(:player, GOD).map(&:name).sort }
case_run("resource_without_role") { Forum.without_role(:player).map(&:name).sort }
case_run("resource_applied_roles_class") { Forum.applied_roles.map(&:name).sort }
case_run("resource_applied_roles_instance") do
  FORUMS.first.applied_roles.map(&:name).sort
end

# --- strict rolify (strict_spec / shared examples) ------------------------
case_run("strict_class_role_instance_false") do
  u = StrictUser.create(login: "s1"); u.add_role(:manager, Group)
  [u.has_role?(:manager, Group), u.has_role?(:manager, GROUPS.first)]
end
case_run("strict_instance_role_class_false") do
  u = StrictUser.create(login: "s2"); u.add_role(:moderator, FORUMS.first)
  [u.has_role?(:moderator, FORUMS.first), u.has_role?(:moderator, Forum)]
end
case_run("strict_with_role_scope") do
  u = StrictUser.create(login: "s3"); u.add_role(:moderator, FORUMS.last)
  StrictUser.with_role(:moderator, FORUMS.first).map(&:login)
end

# --- has_strict_cached_role? (role.rb, cached strict lookup) ---------------
case_run("strict_cached_role") do
  u = StrictUser.create(login: "s4"); u.add_role(:manager, Group)
  [u.has_strict_cached_role?(:manager, Group), u.has_strict_cached_role?(:manager, GROUPS.first)]
end

# --- custom role_join_table_name (rolify option) ---------------------------
case_run("custom_join_add_and_has") do
  u = CustomUser.create(login: "cu1"); u.add_role(:czar)
  [u.has_role?(:czar), u.roles_name.sort]
end
case_run("custom_join_with_role") { CustomUser.with_role(:czar).map(&:login) }
case_run("custom_join_remove_destroys_role") do
  u = CustomUser.find_by!(login: "cu1")
  u.remove_role(:czar)
  [u.has_role?(:czar), Role.where(name: "czar").exists?]
end

# --- rolify association callbacks (before_add/after_add/before_remove/...) --
$cb_log = []
case_run("rolify_assoc_callbacks") do
  u = CallbackUser.create(login: "cbu1")
  u.add_role(:boss)
  u.remove_role(:boss)
  "#{$cb_log.join(',')} #{u.has_role?(:boss)} #{Role.where(name: 'boss').exists?}"
end
