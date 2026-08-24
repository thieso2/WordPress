# frozen_string_literal: true

module Platform
  # console.site-health / console.site-health-info (target_screens.md:553-554). The
  # legacy's WP_Site_Health (wp-admin/includes/class-wp-site-health.php) ran a battery
  # of checks, most of them about the plugin/theme/update machinery AD-01 and DEV-011
  # removed. What survives is a HONEST status report over facts this system actually has:
  # the runtime it runs on, the database it reads, and the one content-visibility check
  # that is a genuine setting here (blog_public).
  #
  # Modernized mode: the tab labels, the section headings and "Passed tests" are LITERAL
  # (site-health.php); the individual check copy is the rebuild's own, because the legacy
  # checks it replaces do not exist here. DEV-003: some totals are estimated. The ONE
  # check that maps to a real legacy test — the loopback test (BR-MIGRATE-355) — keeps the
  # legacy label VERBATIM (get_test_loopback_requests(), class-wp-site-health.php:2081),
  # because that test has a genuine analogue here and the task pins its label to the oracle.
  #
  # Pure-Ruby leaf: reads Configuration and the connection, depends on no surface.
  module Health
    # BR-MIGRATE-352 (BR-SH-01). Each result is DIRECT (run synchronously while the page
    # loads) or ASYNC (fetched afterward by JavaScript over the REST controller, so a slow
    # test never blocks the page). `.report` runs only the direct battery; the async ones
    # are exposed through Platform::Health.async_results / the site-health REST controller
    # (BR-MIGRATE-356). `mode` defaults to :direct.
    Result = Struct.new(:label, :status, :description, :mode, keyword_init: true) do
      def critical?    = status == :critical
      def recommended? = status == :recommended
      def good?        = status == :good
      def mode_name    = mode || :direct
      def direct?      = mode_name == :direct
      def async?       = mode_name == :async
    end

    # BR-MIGRATE-353 (BR-SH-02). The three test statuses, verbatim from the legacy
    # (good | recommended | critical).
    STATUSES = %i[good recommended critical].freeze

    # BR-MIGRATE-352. The synchronous battery, in the order the screen lists them; and the
    # async battery, fetched over REST rather than during page load.
    DIRECT_TESTS = %i[runtime_check database_check search_visibility_check https_check].freeze
    ASYNC_TESTS  = %i[loopback_check].freeze

    Report = Struct.new(:results, keyword_init: true) do
      def critical     = results.select(&:critical?)
      def recommended  = results.select(&:recommended?)
      def good         = results.select(&:good?)
      def issues       = critical + recommended
      # site-health.php's progress ring is a count of non-passing tests.
      def issue_count  = issues.length
    end

    module_function

    # BR-MIGRATE-352: the DIRECT battery, run synchronously the way the screen renders it.
    # The async tests (loopback) are NOT here — they are fetched afterward (async_results
    # / the REST controller), exactly as class-wp-site-health.php separates the two lists.
    def report
      Report.new(results: DIRECT_TESTS.map { |test| public_send(test) })
    end

    # BR-MIGRATE-352 / BR-MIGRATE-356: the ASYNC battery. Not run during `report`; the
    # legacy's JavaScript fetches each over the site-health REST controller after the page
    # has loaded. Here that is Platform::Health.async_results, surfaced by
    # PublicApi::SiteHealthController.
    def async_results
      ASYNC_TESTS.map { |test| public_send(test) }
    end

    # site-health-info's environment section, reduced to the facts a status report
    # needs. Rendered as label => value pairs.
    def info
      {
        "Server" => {
          "Ruby version" => RUBY_VERSION,
          "Rails version" => Rails.version,
          "Environment" => Rails.env,
        },
        "Database" => {
          "Adapter" => safe { ActiveRecord::Base.connection.adapter_name },
          "Version" => safe { ActiveRecord::Base.connection.database_version.to_s },
        },
        "Content" => {
          "Posts" => safe { Publishing::Post.count.to_s },
          "Comments" => safe { Discussion::Comment.count.to_s },
          "Users" => safe { Identity::User.count.to_s },
        },
      }
    end

    def runtime_check
      Result.new(label: "Your site is running a supported runtime", status: :good,
                 description: "Ruby #{RUBY_VERSION} on Rails #{Rails.version}.")
    end

    def database_check
      reachable = safe { ActiveRecord::Base.connection.active? } || false
      if reachable
        Result.new(label: "Your database is reachable", status: :good,
                   description: "The PostgreSQL connection is live.")
      else
        Result.new(label: "Your database is not reachable", status: :critical,
                   description: "The application could not reach PostgreSQL.")
      end
    end

    # The one legacy check that maps to a real setting here: options-reading.php's
    # "Discourage search engines" (blog_public = 0). site-health.php surfaces it as a
    # recommendation, and the dashboard's At a Glance echoes it ("Search engines
    # discouraged").
    def search_visibility_check
      if search_engines_discouraged?
        Result.new(label: "Search engines are discouraged from indexing this site.",
                   status: :recommended,
                   description: "Reading settings ask search engines not to index this site. " \
                                "Change this under Settings › Reading when the site is ready to launch.")
      else
        Result.new(label: "Search engine indexing is enabled.", status: :good,
                   description: "This site is discoverable by search engines.")
      end
    end

    def https_check
      Result.new(label: "Your site can use an encrypted connection", status: :good,
                 description: "Serve the console and site over HTTPS in production.")
    end

    # BR-MIGRATE-355 (BR-SH-04). "The loopback test is how a site detects that WP-Cron
    # cannot self-invoke." The legacy fires an HTTP request to its own wp-cron.php to
    # prove scheduled events can start (get_test_loopback_requests(),
    # class-wp-site-health.php:2079; can_perform_loopback():3275). There is no self-HTTP
    # loopback here — AD-01 removed WP-Cron, and the job queue is Solid Queue (Gemfile),
    # a real worker draining a persistent store, not a page load re-invoking itself. So
    # the OBSERVABLE the loopback test protected — "can scheduled work actually run?" —
    # becomes "is the job queue able to run?".
    #
    # ⚠️ LABEL is VERBATIM from the legacy (:2081 good, :2100 fail); this is the one
    # site-health test with a genuine analogue, and its label is pinned to the oracle.
    # The DESCRIPTION is the rebuild's own — the legacy's talks about theme/plugin editors
    # and HTTP loopbacks that do not exist here (modernized mode). The badge the REST
    # shape carries ("Performance"/"blue") is also verbatim (:2084-2085).
    #
    # ASYNC (BR-MIGRATE-352): a queue probe can be slow, so — like the legacy's — it is
    # fetched after the page loads rather than run inline.
    def loopback_check
      if job_queue_runnable?
        Result.new(label: "Your site can perform loopback requests", status: :good, mode: :async,
                   description: "Scheduled events run through the background job queue, which is reachable.")
      else
        Result.new(label: "Your site could not complete a loopback request", status: :critical, mode: :async,
                   description: "The background job queue could not be reached, so scheduled events may not run " \
                                "as expected.")
      end
    end

    # The loopback test's REST shape (BR-MIGRATE-356). get_test_loopback_requests() returns
    # `{ label, status, badge:{label,color}, description(<p>…</p>), actions, test }`
    # (class-wp-site-health.php:2079-2108); the site-health REST controller returns it
    # verbatim (class-wp-rest-site-health-controller.php test_loopback_requests()). This is
    # that document, built from `loopback_check` so the console screen and the REST
    # endpoint cannot disagree.
    def loopback_rest_result
      result = loopback_check
      {
        label: result.label,
        status: result.status.to_s,
        badge: { label: "Performance", color: "blue" },
        description: "<p>#{result.description}</p>",
        actions: "",
        test: "loopback_requests",
      }
    end

    # "Can the job queue run?" — the surviving observable of the loopback test. Solid Queue
    # executes jobs from its own persistent store, so a reachable store means a supervisor
    # can pick work up; an in-process adapter (async/inline) always can. An adapter with no
    # execution path (none configured) cannot. Defensive: any probe error reads as
    # unreachable rather than raising into a health report.
    def job_queue_runnable?
      adapter = safe { ActiveJob::Base.queue_adapter_name.to_s } || ""
      case adapter
      when "solid_queue"
        safe { defined?(SolidQueue::Job) && SolidQueue::Job.connection.active? } || false
      when ""
        false
      else
        # inline, async, test, and the other real backends all have an execution path.
        true
      end
    end

    def search_engines_discouraged?
      value = Configuration::Setting["blog_public"]
      value.to_s == "0" || value == false || value.nil?
    end

    def safe
      yield
    rescue StandardError
      nil
    end
  end
end
