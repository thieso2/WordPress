# frozen_string_literal: true

module Access
  # AD-04's static check, and the whole of its subtlety.
  #
  #   "A static check fails the build when a route, policy or endpoint is registered
  #    without an explicit authorization declaration -- INCLUDING A DECLARATION OF
  #    `public`. The check does not change the runtime default -- it removes the way
  #    that default gets reached, which is by someone forgetting."
  #
  # So `declare!(:public)` is legal and `declare!` never called is not. The permissive
  # outcome stays reachable; only the accidental route to it is closed. Under AD-01
  # there is no filter to correct a forgotten declaration afterwards, which is why the
  # build is the place this is caught.
  class Declarations
    class Undeclared < StandardError; end

    MODES = %i[public authenticated policy].freeze

    Entry = Struct.new(:identifier, :mode, :policy, :action, :source, keyword_init: true)

    class << self
      def registry = @registry ||= {}

      def reset! = @registry = {}

      # `mode: :public` is an explicit, auditable choice. That is the point.
      def declare(identifier, mode:, policy: nil, action: nil, source: nil)
        raise ArgumentError, "mode must be one of #{MODES.inspect}" unless MODES.include?(mode)
        raise ArgumentError, "mode :policy requires a policy class" if mode == :policy && policy.nil?

        registry[identifier.to_s] = Entry.new(identifier: identifier.to_s, mode: mode,
                                              policy: policy, action: action,
                                              source: source || caller_locations(1, 1)&.first&.to_s)
      end

      def declared?(identifier) = registry.key?(identifier.to_s)

      def entry(identifier) = registry[identifier.to_s]

      # The build check. `known_identifiers` is everything the surfaces registered.
      def undeclared(known_identifiers)
        Array(known_identifiers).map(&:to_s).reject { |id| declared?(id) }
      end

      # BR-REST-05 / BR-ADM-07, reproduced: at RUNTIME an undeclared route is PUBLIC.
      # The build check is what stops one existing; if one does, it serves.
      def permits?(identifier, actor: nil, record: nil, action: nil)
        found = entry(identifier)
        return true if found.nil?          # BR-REST-05: no policy => public

        case found.mode
        when :public then true
        when :authenticated then actor.present?
        when :policy then found.policy.new(actor, record).permit?(action || found.action)
        end
      end
    end
  end
end
