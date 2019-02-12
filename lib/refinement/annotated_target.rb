module Refinement
  # A target, annotated with any changes
  class AnnotatedTarget
    # @return [Xcodeproj::Project::AbstactTarget] the target in an Xcode project
    attr_reader :xcode_target
    # @return [String,Nil] the reason why the target has changed, or `nil` if it has not changed
    attr_reader :change_reason

    def initialize(target:, change_reason:, dependencies: [])
      @xcode_target = target
      @change_reason = change_reason
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
    def changed?(level:)
      @changed ||= {}
      return @changed[level] if @changed.key?(level)

      @changed[level] =
        case level
        when :itself
          change_reason
        when :full_transitive
          change_reason || (dependencies.each do |dependency|
            next unless (cr = dependency.changed?(level: level))
            return "dependency #{dependency} changed because #{cr}"
          end && nil)
        when proc { |symbol, int| (symbol == :at_most_n_away) && int.is_a?(Integer) }
          n = level.last
          raise ArgumentError, "level must be positive, not #{n}" if n < 0
          change_reason || ((n > 0) && dependencies.each do |dependency|
            next unless (cr = dependency.changed?(level: [:at_most_n_away, level.last.pred]))
            return "dependency #{dependency} changed because #{cr}"
          end && nil)
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
