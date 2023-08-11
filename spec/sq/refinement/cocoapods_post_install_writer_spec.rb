# frozen_string_literal: true

require 'sq/refinement/cocoapods_post_install_writer'
require 'cocoapods'

RSpec.describe Sq::Refinement::CocoaPodsPostInstallWriter do # rubocop:disable RSpec/FilePath
  subject(:post_install_writer) do
    user_project.save
    specifications.each { |s| Pathname(s.name).tap(&:mkpath).join("#{s.name}.podspec.json").open('w') { |f| f << s.to_pretty_json } }

    described_class.new(aggregate_targets, pod_targets, config, options)
  end

  before :all do
    @pod_json_fixture = Pathname("#{File.expand_path(__dir__)}/../../fixtures/pod.json").read
  end

  around do |example|
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        Pod::Config.instance = nil
        Pod::Config.instance.with_changes(silent: true, home_dir: Pathname(tmpdir).join('.cocoapods')) do
          example.run
        end
      end
    end
  end

  let(:pod_json_fixture) { JSON.parse(@pod_json_fixture) }

  let(:tmp_git_source) do
    FileUtils.mkdir_p('tmp_git_source')
    Dir.chdir('tmp_git_source') do
      IO.popen(%w[git init .], &:read)
      IO.popen(%w[git commit -m InitialCommit --allow-empty --no-verify], &:read)
    end
    "file://#{File.expand_path('tmp_git_source')}"
  end

  let(:podspec) do
    Pod::Specification.new do |s|
      s.name = 'PodGit'
      s.source_files = 'Sources/**/*.m'
      s.watchos.deployment_target = '10'
    end
  end

  let(:tmp_git_pod_source) do
    FileUtils.mkdir_p('tmp_git_pod_source')
    pod_source_path = File.expand_path('tmp_git_pod_source')
    Dir.chdir('tmp_git_pod_source') do
      IO.popen(%w[git init .], &:read)

      podspec.tap { |s| add_podspec_values(s) }
      podfile_name = File.join(pod_source_path, "#{podspec.name}.podspec.json")

      File.open(podfile_name, 'w') { |f| f << podspec.to_pretty_json }
      IO.popen(%w[git add .], &:read)
      IO.popen(%w[git commit -m InitialCommit --allow-empty -n], &:read)
    end
    "file://#{pod_source_path}"
  end

  let(:podfile) do
    source_url = tmp_git_source
    git_pod_url = tmp_git_pod_source
    Pod::Podfile.new do
      source source_url

      target 'A' do
        pod 'PodA', path: 'PodA/PodA.podspec.json', appspecs: %w[DemoApp]
        pod 'PodC', path: 'PodC/PodC.podspec.json'

        target 'A Tests' do
          inherit! :search_paths
          pod 'TestPodA', path: 'TestPodA/TestPodA.podspec.json', testspecs: %w[WhoTestsTheTests]
        end
      end

      target 'B' do
        pod 'PodB', path: 'PodB/PodB.podspec.json'
        pod 'PodC', path: 'PodC/PodC.podspec.json'
      end
      target 'B Mac' do
        pod 'PodB', path: 'PodB/PodB.podspec.json'
        pod 'PodC', path: 'PodC/PodC.podspec.json'
      end

      abstract_target 'C' do
        platform :tvos, '11'
        pod 'PodTV', path: 'PodTV/PodTV.podspec.json'
      end

      abstract_target 'D' do
        platform :watchos, '11'
        pod 'PodGit', git: git_pod_url
      end
    end
  end

  let(:specifications) do
    [
      Pod::Specification.new do |s|
        s.name = 'PodA'
        s.source_files = ['Sources/**/*.{h,m}', 'Sources/*.swift']

        s.app_spec 'DemoApp' do |app_spec|
          app_spec.source_files = 'DemoApp/main.swift'
        end
      end,
      Pod::Specification.new do |s|
        s.name = 'PodB'
        s.source_files = ['Sources/**/*.{h,m}', 'Sources/*.swift']
        s.resources = 'Resources/bare/*.png'
        s.resource_bundles = { 'PodBResources1' => 'Resources/1/**/*', 'PodBResources2' => 'Resources/2/**/*' }
        s.preserve_path = 'Scripts/*'
        s.exclude_files = 'IGNORE_ME'
      end,
      Pod::Specification.new do |s|
        s.name = 'PodC'
        s.source_files = ['Sources/**/*.{h,m}', 'Sources/*.swift']

        s.watchos.public_header_files = 'include/*.h'
        s.ios.public_header_files = 'include/*.h'

        s.subspec 'SubSpec' do |ss|
          ss.source_files = 'SubSpec/Sources/*'
        end

        s.test_spec 'Unused' do |test_spec|
          test_spec.source_files = 'Tests/Unused/*.m'
        end
      end,
      Pod::Specification.new do |s|
        s.name = 'TestPodA'
        s.source_files = ['Sources/**/*.{h,m}', 'Sources/*.swift']
        s.dependency 'PodA'

        s.test_spec 'WhoTestsTheTests' do |test_spec|
          test_spec.dependency 'PodC'
        end
      end,
      Pod::Specification.new do |s|
        s.name = 'PodTV'
        s.source_files = 'Sources/**/*.m'
        s.tvos.deployment_target = '10'
      end
    ]
      .each do |s|
        add_podspec_values(s)
      end
  end

  let(:user_project) do
    Xcodeproj::Project.new('UserProject.xcodeproj').instance_eval do
      new_target(:application, 'A', :ios, '11')
      new_target(:unit_test_bundle, 'A Tests', :ios, '11')
      new_target(:application, 'B', :ios, '11')
      new_target(:application, 'B Mac', :osx, '10.11')
      self
    end
  end

  let(:analysis_result) do
    Pod::Installer::Analyzer.new(config.sandbox.tap(&:prepare), podfile).analyze
  end

  let(:aggregate_targets) { analysis_result.targets }
  let(:pod_targets) { analysis_result.pod_targets }

  let(:config) do
    Pod::Config.instance.tap do |config|
      config.podfile = podfile
      config.silent = true
      config.installation_root = Pathname.pwd
    end
  end

  let(:options) do
    { 'pretty_print_json' => true }
  end

  def add_podspec_values(spec)
    spec.version = '1.0'
    spec.authors = ['None']
    spec.license = 'None'
    spec.homepage = 'https://example.com'
    spec.source = { git: 'none' }
    spec.summary = 'summary'

    spec.ios.deployment_target = '11'
    spec.watchos.deployment_target = '11'
    spec.macos.deployment_target = '10.11'
  end

  describe '#write!' do
    it 'writes the json' do
      post_install_writer.write!
      json = Pathname('Pods/pods_refinement.json')
      expect(json).to exist
      expect(JSON.parse(json.read)).to eq(pod_json_fixture)
    end
  end
end
