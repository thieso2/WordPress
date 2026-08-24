# frozen_string_literal: true

module Importing
  # What one import RUN produced — the same three things lib/seeding/report.rb is judged
  # by (an inventory, a dead-letter queue and notes), plus the one thing a screen needs
  # that a rake task does not: a PER-RECORD line the operator can read.
  #
  # ⚠️ The dead-letter discipline is carried over verbatim: a record that cannot be
  # mapped is REPORTED, never coerced into a default. "A pipeline that quietly coerces
  # bad input into defaults would still fill the database, and would destroy exactly the
  # signal this step exists to produce." An import that silently drops half a WXR and
  # reports success is the failure mode this class exists to prevent.
  class Result
    # `kind` is the source block (author / term / post / page / comment / attachment).
    # `outcome` is one of OUTCOMES. `detail` is the reason, and is what the screen prints
    # next to anything that is not :imported.
    Record = Struct.new(:kind, :label, :outcome, :detail, keyword_init: true)

    OUTCOMES = %i[imported existing skipped failed].freeze

    OUTCOME_LABELS = {
      imported: "Imported",
      existing: "Already exists",
      skipped: "Skipped",
      failed: "Failed"
    }.freeze

    attr_reader :records, :counts, :notes

    def initialize
      @records = []
      @counts = Hash.new(0)
      @notes = []
    end

    def record!(kind:, label:, outcome:, detail: nil)
      raise ArgumentError, "unknown outcome #{outcome.inspect}" unless OUTCOMES.include?(outcome)

      @records << Record.new(kind: kind, label: label, outcome: outcome, detail: detail)
      @counts["#{kind}.#{outcome}"] += 1
      @counts[outcome.to_s] += 1
      self
    end

    def note!(text) = @notes << text

    def imported(kind = nil) = count_for(:imported, kind)
    def failed(kind = nil) = count_for(:failed, kind)
    def existing(kind = nil) = count_for(:existing, kind)
    def skipped(kind = nil) = count_for(:skipped, kind)

    def total = @records.length

    # A run with no failures. NOT "a run that did something": an empty WXR is clean.
    def clean? = failed.zero?

    def records_for(kind) = @records.select { |r| r.kind == kind }

    # The per-record table the screen renders, grouped in the order the WXR itself is
    # walked so the operator reads the run in the order it happened.
    def grouped
      @records.group_by(&:kind)
    end

    private

    def count_for(outcome, kind)
      kind.nil? ? @counts[outcome.to_s] : @counts["#{kind}.#{outcome}"]
    end
  end
end
