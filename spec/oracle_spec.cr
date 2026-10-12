# Oracle spec: the Crystal port must reproduce oracle/expected.yml exactly
# (captured from rolify 6.0.1 over SQLite in-memory). Same case IDs, no
# edits; values use the same \n/\t escape protocol.

require "spec"
require "../src/rolify_cr"

EXPECTED = begin
  hash = {} of String => String
  File.read("#{__DIR__}/../oracle/expected.yml").each_line do |line|
    if line.includes?('\t')
      id, value = line.split('\t', 2)
      hash[id] = value.chomp
    end
  end
  hash
end

def escape(s) : String
  s = s.to_s
  s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
end

TEST_URL = ENV["ROLIFY_TEST_URL"]? ||
           "postgres://root@/crails_rolify_test?host=/var/run/postgresql"

ActiveRecord::Base.establish_connection(TEST_URL)
conn = ActiveRecord::Base.__session
conn.exec(%(CREATE TABLE IF NOT EXISTS roles (
  id bigserial PRIMARY KEY,
  name varchar,
  resource_type varchar,
  resource_id bigint,
  created_at timestamp,
  updated_at timestamp
)))
conn.exec(%(CREATE TABLE IF NOT EXISTS users (id bigserial PRIMARY KEY, login varchar)))
conn.exec(%(CREATE TABLE IF NOT EXISTS strict_users (id bigserial PRIMARY KEY, login varchar)))
conn.exec(%(CREATE TABLE IF NOT EXISTS custom_users (id bigserial PRIMARY KEY, login varchar)))
conn.exec(%(CREATE TABLE IF NOT EXISTS callback_users (id bigserial PRIMARY KEY, login varchar)))
conn.exec(%(CREATE TABLE IF NOT EXISTS forums (id bigserial PRIMARY KEY, name varchar)))
conn.exec(%(CREATE TABLE IF NOT EXISTS groups (id bigserial PRIMARY KEY, name varchar)))
conn.exec(%(CREATE TABLE IF NOT EXISTS users_roles (user_id bigint, role_id bigint)))
conn.exec(%(CREATE TABLE IF NOT EXISTS strict_users_roles (strict_user_id bigint, role_id bigint)))
conn.exec(%(CREATE TABLE IF NOT EXISTS custom_users_and_roles (custom_user_id bigint, role_id bigint)))
conn.exec(%(CREATE TABLE IF NOT EXISTS callback_users_roles (callback_user_id bigint, role_id bigint)))
conn.exec(%(TRUNCATE roles, users, strict_users, custom_users, callback_users, forums, groups, users_roles, strict_users_roles, custom_users_and_roles, callback_users_roles RESTART IDENTITY))

class User < ActiveRecord::Base
  rolify
end

class StrictUser < ActiveRecord::Base
  rolify strict: true
end

class CustomUser < ActiveRecord::Base
  rolify role_join_table_name: "custom_users_and_roles"
end

CB_LOG = [] of String

class CallbackUser < ActiveRecord::Base
  rolify before_add: :log_before_add, after_add: :log_after_add,
         before_remove: :log_before_remove, after_remove: :log_after_remove

  def log_before_add(role : Role)
    CB_LOG << "before_add:#{role.name.not_nil!}"
  end

  def log_after_add(role : Role)
    CB_LOG << "after_add:#{role.name.not_nil!}"
  end

  def log_before_remove(role : Role)
    CB_LOG << "before_remove:#{role.name.not_nil!}"
  end

  def log_after_remove(role : Role)
    CB_LOG << "after_remove:#{role.name.not_nil!}"
  end
end

class Role < ActiveRecord::Base
  scopify
  belongs_to :resource, polymorphic: true
end

class Forum < ActiveRecord::Base
  resourcify
end

class Group < ActiveRecord::Base
  resourcify
end

def logins(users)
  users.map { |u| u.login.to_s }.sort
end

# --- data (mirror of oracle/cases.rb) --------------------------------------
User.create({"login" => "admin"})
User.create({"login" => "moderator"})
User.create({"login" => "god"})
3.times { |i| Forum.create({"name" => "forum #{i + 1}"}) }
2.times { |i| Group.create({"name" => "group #{i + 1}"}) }

ADMIN     = User.where(login: "admin").first.not_nil!
MODERATOR = User.where(login: "moderator").first.not_nil!
GOD       = User.where(login: "god").first.not_nil!
FORUMS    = Forum.order("id").to_a
GROUPS    = Group.order("id").to_a

ADMIN.add_role(:admin)
ADMIN.add_role(:staff)
ADMIN.add_role(:manager, Group)
ADMIN.add_role(:player, Forum)
ADMIN.add_role(:moderator, FORUMS.last)
ADMIN.add_role(:moderator, GROUPS.last)
ADMIN.add_role(:anonymous, FORUMS.first)

GOD.add_role(:moderator, Forum)
GOD.add_role(:player, Forum)

CASES = {} of String => Proc(String)

# --- add_role / global roles ------------------------------------------------
CASES["add_global_role_returns_role"] = -> { ADMIN.add_role(:admin).class.name }
CASES["add_global_role_name"]         = -> { ADMIN.add_role(:admin).name.to_s }
CASES["add_global_role_no_resource"]  = -> { ADMIN.add_role(:admin).resource.nil?.to_s }
CASES["add_role_returns_existing"]    = -> { (ADMIN.add_role(:admin).id == Role.where(name: "admin").first.not_nil!.id).to_s }
CASES["role_count_admin"]             = -> { ADMIN.roles.size.as(Int64).to_s }
CASES["role_count_god"]               = -> { GOD.roles.size.as(Int64).to_s }

# --- has_role? ---------------------------------------------------------------
CASES["has_global_true"]     = -> { ADMIN.has_role?(:admin).to_s }
CASES["has_global_false"]    = -> { ADMIN.has_role?(:warlock).to_s }
CASES["has_class_true"]      = -> { ADMIN.has_role?(:manager, Group).to_s }
CASES["has_class_false"]     = -> { ADMIN.has_role?(:manager, Forum).to_s }
CASES["has_instance_true"]   = -> { ADMIN.has_role?(:moderator, FORUMS.last).to_s }
CASES["has_instance_false"]  = -> { ADMIN.has_role?(:moderator, FORUMS.first).to_s }
CASES["has_any_resource"]    = -> { ADMIN.has_role?(:moderator, :any).to_s }
CASES["has_any_no_resource"] = -> { ADMIN.has_role?(:manager, :any).to_s }
CASES["has_role_string_name"] = -> { ADMIN.has_role?("admin").to_s }
CASES["has_all_true"]        = -> { GOD.has_all_roles?({name: :moderator, resource: Forum}, {name: :player, resource: Forum}).to_s }
CASES["has_all_one_missing"] = -> { GOD.has_all_roles?({name: :moderator, resource: Forum}, :warlock).to_s }
CASES["has_all_mixed_args"]  = -> { ADMIN.has_all_roles?({name: :admin}, "staff").to_s }
CASES["has_any_true"]        = -> { ADMIN.has_any_role?(:warlock, :staff).to_s }
CASES["has_any_false"]       = -> { ADMIN.has_any_role?(:warlock, {name: :wizard}).to_s }
CASES["only_has_true"]       = -> {
  u = User.create({"login" => "solo"})
  u.add_role(:solo)
  u.only_has_role?(:solo).to_s
}
CASES["only_has_false"]      = -> { GOD.only_has_role?(:moderator, Forum).to_s }
CASES["roles_name"]          = -> { GOD.roles_name.sort.inspect }

# --- new-record behavior ------------------------------------------------------
CASES["new_record_has_role"] = -> { User.new({"login" => "ghost"}).has_role?(:admin).to_s }

# --- remove_role --------------------------------------------------------------
CASES["remove_global"] = -> {
  u = User.create({"login" => "r1"}); u.add_role(:admin)
  u.remove_role(:admin)
  u.has_role?(:admin).to_s
}
CASES["remove_instance"] = -> {
  u = User.create({"login" => "r2"}); u.add_role(:moderator, FORUMS.first)
  u.remove_role(:moderator, FORUMS.first)
  u.has_role?(:moderator, FORUMS.first).to_s
}
CASES["remove_class_keeps_instance"] = -> {
  u = User.create({"login" => "r3"}); u.add_role(:moderator, Forum); u.add_role(:moderator, FORUMS.first)
  u.remove_role(:moderator, Forum)
  [u.has_role?(:moderator, Forum), u.has_role?(:moderator, FORUMS.first)].inspect
}
CASES["remove_returns_roles"] = -> {
  u = User.create({"login" => "r4"}); u.add_role(:admin)
  u.remove_role(:admin).map(&.name.to_s).inspect
}
CASES["remove_missing_role"] = -> {
  u = User.create({"login" => "r5"})
  u.remove_role(:nonexistent).map(&.name.to_s).inspect
}

# --- class finders on user ----------------------------------------------------
CASES["with_role_global"]     = -> { logins(User.with_role(:admin)).inspect }
CASES["with_role_class"]      = -> { logins(User.with_role(:player, Forum)).inspect }
CASES["with_role_instance"]   = -> { logins(User.with_role(:moderator, FORUMS.last)).inspect }
CASES["with_role_none"]       = -> { logins(User.with_role(:warlock)).inspect }
CASES["without_role_global"]  = -> { logins(User.without_role(:admin)).inspect }
CASES["without_role_class"]   = -> { logins(User.without_role(:player, Forum)).inspect }
CASES["with_all_roles"]       = -> { logins(User.with_all_roles({name: :moderator, resource: Forum}, {name: :player, resource: Forum})).inspect }
CASES["with_any_role"]        = -> { logins(User.with_any_role(:staff, {name: :player, resource: Group})).inspect }
CASES["with_any_role_sym_str"] = -> { logins(User.with_any_role("admin", :player)).inspect }

# --- role class scopes ---------------------------------------------------------
CASES["scope_global"]            = -> { Role.global.map { |r| r.name.to_s }.sort.inspect }
CASES["scope_class_scoped"]      = -> { Role.class_scoped.map { |r| "#{r.name}:#{r.resource_type}" }.sort.inspect }
CASES["scope_class_scoped_type"] = -> { Role.class_scoped(Group).map { |r| r.name.to_s }.sort.inspect }
CASES["scope_instance_scoped"]   = -> { Role.instance_scoped.map { |r| "#{r.name}:#{r.resource_id}" }.sort.inspect }
CASES["scope_instance_scoped_type"] = -> { Role.instance_scoped(Forum).map { |r| r.name.to_s }.sort.inspect }
CASES["scope_instance_scoped_obj"]  = -> { Role.instance_scoped(FORUMS.last).map { |r| r.name.to_s }.sort.inspect }

# --- resource side --------------------------------------------------------------
CASES["resource_find_roles"] = -> {
  Forum.find_roles(:moderator).map { |r| "#{r.name}:#{r.resource_type}:#{r.resource_id}" }.sort.inspect
}
CASES["resource_find_roles_user"] = -> {
  Forum.find_roles(:player, GOD).map(&.name.to_s).inspect
}
CASES["resource_with_role"] = -> { Forum.with_role(:moderator).map(&.name.to_s).sort.inspect }
CASES["resource_with_role_user"] = -> { Forum.with_role(:player, GOD).map(&.name.to_s).sort.inspect }
CASES["resource_without_role"] = -> { Forum.without_role(:player).map(&.name.to_s).sort.inspect }
CASES["resource_applied_roles_class"] = -> { Forum.applied_roles.map(&.name.to_s).sort.inspect }
CASES["resource_applied_roles_instance"] = -> {
  FORUMS.first.applied_roles.map(&.name.to_s).sort.inspect
}

# --- strict rolify ---------------------------------------------------------------
CASES["strict_class_role_instance_false"] = -> {
  u = StrictUser.create({"login" => "s1"}); u.add_role(:manager, Group)
  [u.has_role?(:manager, Group), u.has_role?(:manager, GROUPS.first)].inspect
}
CASES["strict_instance_role_class_false"] = -> {
  u = StrictUser.create({"login" => "s2"}); u.add_role(:moderator, FORUMS.first)
  [u.has_role?(:moderator, FORUMS.first), u.has_role?(:moderator, Forum)].inspect
}
CASES["strict_with_role_scope"] = -> {
  u = StrictUser.create({"login" => "s3"}); u.add_role(:moderator, FORUMS.last)
  StrictUser.with_role(:moderator, FORUMS.first).map(&.login.to_s).inspect
}

# --- has_strict_cached_role? ----------------------------------------------------
CASES["strict_cached_role"] = -> {
  u = StrictUser.create({"login" => "s4"}); u.add_role(:manager, Group)
  [u.has_strict_cached_role?(:manager, Group), u.has_strict_cached_role?(:manager, GROUPS.first)].inspect
}

# --- custom role_join_table_name ------------------------------------------------
CASES["custom_join_add_and_has"] = -> {
  u = CustomUser.create({"login" => "cu1"}); u.add_role(:czar)
  [u.has_role?(:czar), u.roles_name.sort].inspect
}
CASES["custom_join_with_role"] = -> { CustomUser.with_role(:czar).map(&.login.to_s).inspect }
CASES["custom_join_remove_destroys_role"] = -> {
  u = CustomUser.where(login: "cu1").first.not_nil!
  u.remove_role(:czar)
  [u.has_role?(:czar), !Role.where(name: "czar").to_a.empty?].inspect
}

# --- rolify association callbacks ------------------------------------------
CASES["rolify_assoc_callbacks"] = -> {
  u = CallbackUser.create({"login" => "cbu1"})
  u.add_role(:boss)
  u.remove_role(:boss)
  "#{CB_LOG.join(",")} #{u.has_role?(:boss)} #{!Role.where(name: "boss").to_a.empty?}"
}

EXPECTED.each do |id, expected|
  it id do
    escape(CASES[id].call).should eq expected
  end
end
