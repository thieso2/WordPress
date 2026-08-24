# frozen_string_literal: true

module Retrieval
  # A single page of a list, with the two counting strategies P-LIST declares per screen
  # (target_screens.md § Part 1, DEV-003).
  #
  # ── Why two strategies ────────────────────────────────────────────────────────────
  # The legacy runs `SQL_CALC_FOUND_ROWS` on every WP_List_Table query (TD-06,
  # F-QUERY-03) so the pager can print an exact total on every screen. RISK-013 records
  # that this exact count is entangled with observable behaviour, so it is reproduced —
  # but only where a screen's spec asks for it. `Retrieval::PostQuery#total` already does
  # this for the front-end read path; this object is its console sibling, over an
  # arbitrary relation and with the estimated strategy the six `estimated` screens want.
  #
  #   :exact     — a second `COUNT(*)` over the same relation. MySQL's SELECT
  #                FOUND_ROWS() has no PostgreSQL equivalent, so the count is a real
  #                query — the same information, honestly priced (BR-MIGRATE-047).
  #   :estimated — the query planner's row estimate (PostgreSQL EXPLAIN). DEV-003 puts
  #                the estimated total OUT OF PARITY SCOPE, so what matters is that it is
  #                a real, cheap estimate rather than a full scan; page CONTENTS stay
  #                exact either way, because the page itself is always a real LIMIT/OFFSET
  #                slice of the relation.
  #
  # `per_page` is P-LIST's per-screen page size (a Configuration value scoped to the user
  # in the full spec; the caller passes the resolved integer here).
  class Page
    STRATEGIES = %i[exact estimated].freeze
    DEFAULT_PER_PAGE = 20

    attr_reader :relation, :number, :per_page, :strategy

    def initialize(relation, page: 1, per_page: DEFAULT_PER_PAGE, strategy: :exact)
      raise ArgumentError, "strategy must be one of #{STRATEGIES.inspect}" unless STRATEGIES.include?(strategy)

      @relation = relation
      @per_page = normalize_per_page(per_page)
      @number = normalize_page(page)
      @strategy = strategy
    end

    def offset = (number - 1) * per_page

    # The page's rows — always a real slice, never estimated. `reorder(nil)`-free: the
    # caller's ORDER BY is preserved so the console's sortable columns work.
    def records = @records ||= relation.offset(offset).limit(per_page).to_a

    # The total row count, by the declared strategy.
    def total
      @total ||= strategy == :exact ? exact_total : estimated_total
    end

    def total_pages
      return 0 if per_page <= 0

      [(total.to_f / per_page).ceil, 1].max
    end

    # BR-MIGRATE-047 second half (class-wp-query.php:3699): a page past the end reports
    # itself empty, which is what suppresses pager links past the last page.
    def out_of_range? = number > 1 && records.empty?

    def first? = number <= 1
    def last? = number >= total_pages
    def previous_number = [number - 1, 1].max
    def next_number = number + 1
    def empty? = records.empty?

    # 1-based inclusive index of the first row on this page, for "N–M of T" displays.
    def first_index = empty? ? 0 : offset + 1
    def last_index = offset + records.length

    private

    # `SQL_CALC_FOUND_ROWS`, reproduced as a COUNT over the relation with its ordering,
    # limit and offset stripped (`count` does this).
    def exact_total = relation.count

    # The PostgreSQL planner's row estimate for the relation. Costs a plan, not a scan.
    # Any failure — an unusual relation the planner cannot estimate, a driver quirk —
    # falls back to a bounded exact count so the pager still renders. DEV-003 keeps the
    # value itself out of parity scope.
    def estimated_total
      sql = relation.reorder(nil).to_sql
      plan = relation.klass.connection.select_all("EXPLAIN (FORMAT JSON) #{sql}").rows.first&.first
      rows = plan && JSON.parse(plan).dig(0, "Plan", "Plan Rows")
      rows ? rows.to_i : exact_total
    rescue StandardError
      exact_total
    end

    def normalize_per_page(value)
      n = value.to_i
      n.positive? ? n : DEFAULT_PER_PAGE
    end

    def normalize_page(value)
      [value.to_i, 1].max
    end
  end
end
