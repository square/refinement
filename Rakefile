# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require 'inch_by_inch/rake_task'
require 'open3'

RuboCop::RakeTask.new(:rubocop)
InchByInch::RakeTask.new(:inch)

namespace :spec do
  RSpec::Core::RakeTask.new(:unit) do |t|
    t.rspec_opts = %w[--format progress]
  end
end

task :ensure_clean do
  out, status = Open3.capture2('git', 'status', '--porcelain')
  raise 'running git status failed' unless status.success?
  changed_files = out.each_line.map do |line|
    change, _path = line.chomp.split(/\s+/, 2)
    next if change == '??'
    line
  end.compact

  raise "The repo is dirty!\n\t#{changed_files.join("\t")}" unless changed_files.empty?
end

task spec: %w[spec:unit]

task default: %w[spec rubocop inch ensure_clean]
