# frozen_string_literal: true

module Sq
  module Refinement
    # @visibility private
    VERSION = File.read(File.expand_path('../../../VERSION', __dir__)).strip.freeze
  end
end
