# frozen_string_literal: true

module Tenancy
  # A pending signup — the legacy `wp_signups` (BR-MS-08 neighbours it; wpmu_signup_blog()/
  # wpmu_signup_user() wrote it, wpmu_activate() consumed it). Global table: a signup exists
  # before any site does, so it cannot be tenant-scoped.
  #
  # The two-step flow the five screens implement (target_screens.md Part 6):
  #   1. /signup (+ /signup/site) writes a Signup with an activation_key and shows
  #      /signup/confirm — "check your email".
  #   2. /activate consumes the key: it creates the Identity::User (if new) and, for a blog
  #      signup, the Tenancy::Site + its PostgreSQL schema (Provisioner), then shows
  #      /activate/done with the result.
  #
  # ⚠️ No email is actually sent here (Action Mailer is the framework equivalent and out of
  # this track's scope); the activation_key is returned to the caller so the flow is
  # testable end-to-end. Recorded as a deferred wiring point.
  class Signup < ApplicationRecord
    self.table_name = "signups"

    belongs_to :site, class_name: "Tenancy::Site", optional: true, inverse_of: :signups

    # A user-only signup (just an account) vs a blog signup (account + site). The legacy
    # distinguished them by an empty domain (wpmu_signup_user stored domain='').
    enum :kind, { user: "user", blog: "blog" }, prefix: true

    validates :user_login, presence: true
    validates :user_email, presence: true
    validates :activation_key, presence: true, uniqueness: true
    validates :domain, :path, :title, presence: true, if: :kind_blog?

    before_validation :assign_activation_key, on: :create

    scope :pending, -> { where(activated_at: nil) }

    def activated? = activated_at.present?

    # wpmu_activate(). Idempotent: activating an already-active key returns the existing
    # result rather than double-provisioning. Wrapped in a transaction so a failure to
    # provision the schema does not leave an orphan user or site.
    #
    # Returns a Result with the created user and (for a blog signup) the site — the data the
    # /activate/done screen renders ("message + credentials").
    Result = Struct.new(:user, :site, :password, keyword_init: true)

    def activate!
      return Result.new(user: existing_user, site: site, password: nil) if activated?

      raise Tenancy::NotEnabled, "activation requires config.x.multisite.enabled" unless Tenancy.enabled?

      password = SecureRandom.base58(12)

      ActiveRecord::Base.transaction do
        user = Tenancy.without_tenant do
          Identity::User.find_by(login: user_login) ||
            Identity::User.create!(
              login: user_login, email: user_email, nicename: user_login.downcase,
              display_name: user_login, password: password
            )
        end

        created_site = nil
        if kind_blog?
          created_site = Tenancy.without_tenant do
            Tenancy::Site.create!(domain: domain, path: path, name: title)
          end
          Tenancy::Provisioner.provision!(created_site)
          # First member of a new site is its administrator (BR-MS-04: roles are per-site;
          # role_assignments.site_id already exists — the assignment is scoped to the new
          # site, not global).
          created_site.switch do
            user.assign_role("administrator", site_id: created_site.id)
          end
          update!(site: created_site)
        end

        update!(activated_at: Time.current)
        Result.new(user: user, site: created_site, password: password)
      end
    end

    private

    def existing_user
      Tenancy.without_tenant { Identity::User.find_by(login: user_login) }
    end

    def assign_activation_key
      self.activation_key ||= SecureRandom.hex(16)
    end
  end
end
