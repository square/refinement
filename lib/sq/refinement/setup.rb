# frozen_string_literal: true

module Sq
  # Generates a list of Xcode targets to build & test as a result of a git diff.
  module Refinement
    class Error < StandardError; end

    # @visibility private
    # @param enum [Enumerable]
    # Enumerates through `enum`, and applied the given block to each element.
    # If the result of calling the block is truthy, the first such result is returned.
    # If no such result is found, `nil` is returned.
    def self.map_find(enum)
      enum.each do |elem|
        transformed = yield elem
        return transformed if transformed
      end

      nil
    end
  end
end
