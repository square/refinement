# frozen_string_literal: true

require 'xcodeproj'

module Sq
  module Refinement
    # A target, annotated with any changes
    class AnnotatedTarget
      # @return [Xcodeproj::Project::AbstactTarget] the target in an Xcode project
      attr_reader :xcode_target

      # @return [String,Nil] the reason why the target has changed, or `nil` if it has not changed
      attr_reader :direct_change_reason
      private :direct_change_reason

      def initialize(target:, change_reason:, dependencies: [])
        @xcode_target = target
        @direct_change_reason = change_reason
        @dependencies = dependencies
        dependencies.each do |dependency|
          dependency.depended_upon_by << self
        end
        @depended_upon_by = []
      end

      # @visibility private
      def to_s
        xcode_target.to_s
      end

      CHANGE_LEVELS = %i[
        itself
        at_most_n_away
        full_transitive
      ].freeze
      private_constant :CHANGE_LEVELS

      # @return [Boolean] whether the target has changed, at the given change level
      # @param level [Symbol,(:at_most_n_away,Integer)] change level, e.g. :itself, :at_most_n_away, :full_transitive
      def change_reason(level:)
        @change_reason ||= {}
        # need to use this form for memoization, as opposed to ||=,
        # since this will (often) be nil and it makes a significant performance difference
        return @change_reason[level] if @change_reason.key?(level)

        @change_reason[level] =
          case level
          when :itself
            direct_change_reason
          when :full_transitive
            direct_change_reason || Sq::Refinement.map_find(dependencies) do |dependency|
              next unless (dependency_change_reason = dependency.change_reason(level:))

              "dependency #{dependency} changed because #{dependency_change_reason}"
            end
          when proc { |symbol, int| (symbol == :at_most_n_away) && int.is_a?(Integer) }
            distance_from_target = level.last
            raise ArgumentError, "level must be positive, not #{distance_from_target}" if distance_from_target.negative?

            change_reason = direct_change_reason
            if distance_from_target.positive?
              change_reason ||= Sq::Refinement.map_find(dependencies) do |dependency|
                unless (dependency_change_reason = dependency.change_reason(level: [:at_most_n_away, level.last.pred]))
                  next
                end

                "dependency #{dependency} changed because #{dependency_change_reason}"
              end
            end
            change_reason
          else
            raise Error, "No known change level #{level.inspect}, only #{CHANGE_LEVELS.inspect} are known"
          end
      end

      # @return [Array<AnnotatedTarget>] the list of annotated targets this target depends upon
      attr_reader :dependencies
      # @return [Array<AnnotatedTarget>] the list of annotated targets that depend upon this target
      attr_reader :depended_upon_by
    end
  end
end
