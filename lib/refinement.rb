require 'xcodeproj'

# Generates a list of Xcode targets to build & test as a result of a git diff.
module Refinement
  class Error < StandardError; end

  require 'refinement/version'

  require 'refinement/analyzer'
  require 'refinement/annotated_target'
  require 'refinement/changeset'
  require 'refinement/used_path'
end
