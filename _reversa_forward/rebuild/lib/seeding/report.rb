# frozen_string_literal: true

module Seeding
  # The dead-letter queue, the quarantine, and the inventory — the three things
  # data_migration_plan.md says the run is judged by.
  #
  # ⚠️ "The dead-letter queue must fail the run. A pipeline that quietly coerces bad
  #    input into defaults would still fill the database, and would destroy exactly the
  #    signal this step exists to produce." (handoff.md, next step 9)
  class Report
    Entry = Struct.new(:source, :legacy_id, :reason, :payload, keyword_init: true)

    attr_reader :dead_letters, :quarantine, :counts, :notes

    def initialize
      @dead_letters = []
      @quarantine = []
      @counts = Hash.new(0)
      @notes = []
    end

    # A row that cannot be mapped. NEVER coerced to a default.
    def dead_letter!(source:, legacy_id:, reason:, payload: nil)
      @dead_letters << Entry.new(source: source, legacy_id: legacy_id, reason: reason,
                                 payload: truncate(payload))
    end

    # T-02: an O: payload or an unparseable one. Raw bytes preserved; never discarded,
    # never guessed at.
    def quarantine!(source:, legacy_id:, reason:, payload: nil)
      @quarantine << Entry.new(source: source, legacy_id: legacy_id, reason: reason,
                               payload: truncate(payload))
    end

    def count!(key, by = 1) = @counts[key] += by
    def note!(text) = @notes << text

    def clean? = dead_letters.empty?

    def truncate(payload)
      return nil if payload.nil?

      s = payload.to_s
      s.bytesize > 400 ? "#{s.byteslice(0, 400)}… (#{s.bytesize} bytes)" : s
    end

    def render(io = $stdout)
      io.puts
      io.puts "── seeding report ────────────────────────────────────────────────"
      counts.keys.sort.each { |k| io.printf("  %-42s %d\n", k, counts[k]) }

      unless notes.empty?
        io.puts
        io.puts "  notes:"
        notes.each { |n| io.puts "    · #{n}" }
      end

      unless quarantine.empty?
        io.puts
        io.puts "  ⚠️  QUARANTINE — #{quarantine.length} payload(s) with no automatic mapping."
        io.puts "      T-02: each distinct class is a human decision, not a pipeline bug."
        quarantine.first(20).each do |e|
          io.puts "      #{e.source}##{e.legacy_id}: #{e.reason}"
          io.puts "        #{e.payload}" if e.payload
        end
        io.puts "      … #{quarantine.length - 20} more" if quarantine.length > 20
      end

      if dead_letters.empty?
        io.puts
        io.puts "  dead-letter queue: EMPTY — the corpus round-tripped."
      else
        io.puts
        io.puts "  ❌ DEAD-LETTER QUEUE — #{dead_letters.length} row(s) rejected. THE RUN FAILS."
        dead_letters.first(40).each do |e|
          io.puts "      #{e.source}##{e.legacy_id}: #{e.reason}"
          io.puts "        #{e.payload}" if e.payload
        end
        io.puts "      … #{dead_letters.length - 40} more" if dead_letters.length > 40
      end
      io.puts
    end
  end
end
