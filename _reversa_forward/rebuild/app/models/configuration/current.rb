# frozen_string_literal: true

module Configuration
  # Per-request memo for setting READS. Mirror of Tenancy::Current and
  # Localization::Current — same mechanism, same lifetime, same reason to exist:
  # `ActiveSupport::CurrentAttributes` is reset by Rails at the start of every request and
  # every job, so nothing here is a process-wide global and nothing leaks between requests.
  #
  # WHY IT EXISTS (bin/benchmark, performance baseline):
  # `Setting.[]` is the most-called method in the system — a single front-end screen reads
  # settings 180+ times, because almost every renderer asks for date_format, blogname,
  # permalink_structure or posts_per_page as it goes. Each call was a fresh `find_by`.
  # ActiveRecord's query cache already stopped those from reaching PostgreSQL (147 of 189
  # were cache hits on web.category), so this was never a DATABASE problem — but a cached
  # query still builds a relation, generates SQL, hashes a cache key and instantiates a
  # model. A sampling profile put 53% of the total CPU of a category page inside
  # `Setting.[]`, with 9ms of actual SQL underneath it.
  #
  # So the memo is not a database cache. It is the layer above one: resolve a setting name
  # to its value at most once per request.
  #
  # ⚠️ COHERENCE. A read cache is only safe if every write invalidates it. Setting flushes
  # this on `after_save` and `after_destroy` (deliberately NOT `after_commit`: under
  # transactional tests after_commit never fires, and a flush that is too eager costs a
  # query while a flush that is too late is a wrong answer). That covers `Setting.set` and
  # `Setting.unset`, which are the only writers in app code.
  #
  # It does NOT cover writes that bypass Active Record — `upsert_all`, raw INSERT, and the
  # global TRUNCATE the parity suite runs between scenarios. Those exist only in the test
  # suites, which reset this explicitly (spec/rails_helper.rb, spec/parity/features/
  # support/env.rb). If a future caller writes settings with raw SQL on a live request
  # path, it must call `Configuration::Current.reset` — or, better, go through Setting.set.
  class Current < ActiveSupport::CurrentAttributes
    # [Tenancy::Current.site&.id, name] => value as Setting.[] returns it, INCLUDING
    # `false` for "no such setting". Two things about that key:
    #
    #   * The TENANT is part of it. Under multisite each site's settings live in its own
    #     PostgreSQL schema, so the same name is a different row per tenant; a name-only
    #     key leaks values across a Tenancy.switch. The spec suite caught that on the first
    #     attempt, which is the only reason this note is written from experience.
    #   * MISSES are cached too. `page_on_front` and `page_for_posts` are absent on a
    #     default install and were being looked up, and missed, on every screen.
    attribute :settings

    def self.flush_settings
      self.settings = nil
    end
  end
end
