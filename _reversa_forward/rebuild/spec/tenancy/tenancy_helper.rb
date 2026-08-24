# frozen_string_literal: true

# Shared helpers for the Wave 5 tenancy specs. Multisite is OFF by default (the acceptance
# gate), so a spec that needs it on flips the flag inside a block and ALWAYS restores it —
# a leak would turn multisite on for unrelated specs and break single-site parity.
module TenancyHelper
  def with_multisite(global_schema: "public")
    previous = Rails.application.config.x.multisite.enabled
    previous_schema = Rails.application.config.x.multisite.global_schema
    Rails.application.config.x.multisite.enabled = true
    Rails.application.config.x.multisite.global_schema = global_schema
    yield
  ensure
    Rails.application.config.x.multisite.enabled = previous
    Rails.application.config.x.multisite.global_schema = previous_schema
    # Never leave a tenant on the held (transactional-fixtures) connection.
    Tenancy::Current.site = nil
    ActiveRecord::Base.connection.execute(%(SET search_path TO "$user", public))
  end

  # The live search_path on the connection in hand.
  def current_search_path
    ActiveRecord::Base.connection.select_value("SHOW search_path")
  end

  # Provision a tenant with an explicit, readable schema name and return the Site.
  def provision_site(domain:, schema_name:, name: domain)
    site = Tenancy::Site.create!(domain: domain, path: "/", name: name, schema_name: schema_name)
    Tenancy::Provisioner.provision!(site)
    site
  end

  # Row count in the `settings` table AS THE CURRENT search_path RESOLVES IT — i.e. in
  # whichever schema is active. Raw SQL so no model cache blurs which schema answered.
  def settings_count
    ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM settings").to_i
  end

  def insert_setting(name)
    ActiveRecord::Base.connection.execute(
      "INSERT INTO settings (name, value) VALUES (#{ActiveRecord::Base.connection.quote(name)}, '\"x\"'::jsonb)"
    )
  end
end

RSpec.configure do |config|
  config.include TenancyHelper, :tenancy
end
