# frozen_string_literal: true

module Configuration
  # AGG-Setting — target_domain_model.md § AGG-Setting.
  #
  # AD-06: three of `options`' four responsibilities leave. This table holds SETTINGS
  # ONLY. The compiled routing table moved to Routing as derived, cached state; the
  # scheduled-event queue moved to Scheduling as a real job store; transients moved to
  # Rails.cache (see Configuration::Transient). That separation deletes a coupling, not
  # just a symptom: the legacy's 150 KB autoload heuristic could silently de-autoload the
  # routing table or the cron queue (BR-OPT-06, F-RW-02, F-CRON-03), a failure mode that
  # exists ONLY because unrelated things shared a table with a size heuristic.
  class Setting < ApplicationRecord
    self.table_name = "settings"

    # BR-MIGRATE-010 (BR-OPT-03): 'alloptions' and 'notoptions' are protected names;
    # the legacy calls wp_die() on a write to either. Here they are simply invalid.
    PROTECTED_NAMES = %w[alloptions notoptions].freeze

    # AD-06 again, as a structural rule rather than a convention
    # (target_domain_model.md § AGG-Setting): the routing table and the job queue may
    # not be stored here.
    BARRED_NAMES = %w[rewrite_rules cron].freeze

    # BR-OPT-08: in the legacy, transients shared the options table behind these
    # prefixes, which is how a cached value with an expiry ended up under the same
    # unique index as the site title.
    TRANSIENT_PREFIXES = %w[_transient_ _transient_timeout_
                            _site_transient_ _site_transient_timeout_].freeze

    validates :name, presence: true, uniqueness: true
    validate :name_is_writable
    validate :not_a_transient

    scope :autoloaded, -> { where(autoload: true) }

    class ProtectedName < StandardError; end

    # ⚠️ DEVIATION BR-OPT-04, approved (target_domain_model.md § AGG-Setting).
    # The legacy `update_option()` returns `false` for an UNCHANGED write and `false`
    # for a FAILED write; a caller cannot tell the two apart. A write here answers with
    # one of these outcomes, so "nothing to do" and "it did not happen" are different
    # observable facts.
    class Result
      OUTCOMES = %i[created updated unchanged failed].freeze

      attr_reader :setting, :outcome

      def initialize(setting, outcome)
        raise ArgumentError, "unknown outcome #{outcome}" unless OUTCOMES.include?(outcome)

        @setting = setting
        @outcome = outcome
      end

      def success?   = outcome != :failed
      def failed?    = outcome == :failed
      def created?   = outcome == :created
      def updated?   = outcome == :updated
      def changed?   = created? || updated?
      def unchanged? = outcome == :unchanged
      def errors     = setting.errors
      def value      = setting.value
      def name       = setting.name
    end

    # BR-MIGRATE-008 (BR-OPT-01): option names are trimmed; an empty name returns false.
    def self.normalize_name(name) = name.to_s.strip

    # BR-MIGRATE-009 (BR-OPT-02): blacklist_keys and comment_whitelist are transparently
    # remapped. The legacy also emits a deprecation notice; under AD-01 the remap is
    # simply what the name means, and there is no notice channel to emit on.
    ALIASES = { "blacklist_keys" => "disallowed_keys",
                "comment_whitelist" => "comment_previously_approved" }.freeze

    def self.resolve_name(name)
      n = normalize_name(name)
      ALIASES.fetch(n, n)
    end

    def self.[](name)
      n = resolve_name(name)
      return false if n.empty?

      row = find_by(name: n)
      value = row&.value
      # BR-MIGRATE-012 (BR-OPT-12): get_option('home') returning an empty string falls
      # back to get_option('siteurl').
      return self["siteurl"] if n == "home" && (value.nil? || value == "")

      value.nil? ? false : value
    end

    # BR-MIGRATE-011 (BR-OPT-05): updating an option that does not exist delegates to
    # add_option(). Active Record expresses that as an upsert.
    #
    # Returns a Result — see the BR-OPT-04 deviation above.
    def self.set(name, value, autoload: nil)
      n = resolve_name(name)
      # BR-MIGRATE-010: wp_die() in the legacy — a hard stop, not a return value.
      raise ProtectedName, "#{n} is a protected option name" if PROTECTED_NAMES.include?(n)

      row = find_or_initialize_by(name: n)
      # BR-MIGRATE-013 (BR-OPT-13): values are cloned before storage so later caller
      # mutation cannot alter what was saved.
      row.value = value.duplicable? ? value.deep_dup : value
      # AD-06 / BR-OPT-06: load policy is an EXPLICIT attribute, never a byte-size
      # heuristic. The legacy de-autoloads anything over 150 KB; nothing here does, at
      # any size, in either direction.
      row.autoload = autoload unless autoload.nil?

      return Result.new(row, :unchanged) if row.persisted? && !row.changed?

      created = row.new_record?
      return Result.new(row, :failed) unless row.save

      Result.new(row, created ? :created : :updated)
    end

    # Accepted command `set_load_policy` (target_domain_model.md § AGG-Setting). The
    # policy is set because someone said so, never because of how big the value got.
    def self.set_load_policy(name, autoload)
      row = find_by(name: resolve_name(name))
      return Result.new(new(name: resolve_name(name)), :failed) if row.nil?

      row.autoload = autoload
      return Result.new(row, :unchanged) unless row.changed?

      row.save ? Result.new(row, :updated) : Result.new(row, :failed)
    end

    def self.unset(name) = where(name: resolve_name(name)).destroy_all

    # ⚠️ BR-MIGRATE-014 (BR-OPT-15): "Every option write passes through
    # sanitize_option($option, $value)." For these names sanitize_option applies
    # esc_html, so the value is ALREADY HTML-ESCAPED AT REST -- the oracle's own
    # `blogname` row literally contains `Reversa Oracle &quot;7.2&quot;`.
    #
    # WordPress then prints it raw, because escaping it again would show the entities to
    # the reader. The rebuild has to make the same distinction or the site title renders
    # as `&quot;` on screen -- which is exactly what the first visual diff against the
    # oracle showed.
    #
    # This is the narrow, named exception, not a blanket `raw`: only the option names
    # WordPress itself escapes on write are marked safe, and only because the `sanitizing`
    # pack produced that escaping. It is the practical stand-in for the `SafeHtml` value
    # object in target_domain_model.md -- "produced only by sanitizing, cannot be
    # constructed directly" -- until that type is wired through the surfaces.
    SANITIZED_ON_WRITE = %w[blogname blogdescription].freeze

    def self.display(name)
      resolved = resolve_name(name)
      value = self[resolved]
      return value unless SANITIZED_ON_WRITE.include?(resolved)

      value.to_s.html_safe # rubocop:disable Rails/OutputSafety -- see the note above
    end

    private

    def name_is_writable
      errors.add(:name, "is a protected option name") if PROTECTED_NAMES.include?(name)
      errors.add(:name, "is derived state and may not be stored as a setting (AD-06)") if BARRED_NAMES.include?(name)
    end

    def not_a_transient
      return unless name.to_s.start_with?(*TRANSIENT_PREFIXES)

      errors.add(:name, "transients live in Rails.cache, not in settings (AD-06)")
    end
  end
end
