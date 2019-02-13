require 'refinement/cocoapods_post_install_writer'

require 'cocoapods'

RSpec.describe Refinement::CocoaPodsPostInstallWriter do # rubocop:disable RSpec/FilePath
  subject(:post_install_writer) do
    user_project.save
    specifications.each { |s| Pathname(s.name).tap(&:mkpath).join("#{s.name}.podspec.json").open('w') { |f| f << s.to_pretty_json } }

    described_class.new(aggregate_targets, config, options)
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

  let(:tmp_git_source) do
    FileUtils.mkdir_p('tmp_git_source')
    IO.popen(%w[git init .], chdir: 'tmp_git_source', &:read)
    IO.popen(%w[git commit -m InitialCommit --allow-empty -n], chdir: 'tmp_git_source', &:read)
    if RUBY_VERSION >= '2.6'
      "file:#{File.expand_path('tmp_git_source')}"
    else
      "file://#{File.expand_path('tmp_git_source')}"
    end
  end

  let(:podfile) do
    source_url = tmp_git_source
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
      end
    ]
      .each do |s|
        s.version = '1.0'
        s.authors = ['None']
        s.license = 'None'
        s.homepage = 'https://example.com'
        s.source = { git: 'none' }
        s.summary = 'summary'

        s.ios.deployment_target = '11'
        s.watchos.deployment_target = '11'
        s.macos.deployment_target = '10.11'
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

  let(:aggregate_targets) do
    Pod::Installer::Analyzer.new(config.sandbox.tap(&:prepare), podfile)
                            .analyze.targets
  end

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

  describe '#write!' do
    it 'writes the json' do
      post_install_writer.write!
      json = Pathname('Pods/pods_refinement.json')
      expect(json).to exist
      expect(JSON.parse(json.read)).to eq(
        'PodA' => [
          { 'inclusion_reason' => 'CocoaPods lockfile', 'path' => 'Podfile.lock', 'yaml_keypath' => ['SPEC CHECKSUMS', 'PodA'] },
          { 'inclusion_reason' => 'podspec', 'path' => 'PodA/PodA.podspec.json' },
          { 'glob' => 'PodA/Sources/**/*.{h,m}', 'inclusion_reason' => 'source file' },
          { 'glob' => 'PodA/Sources/*.swift', 'inclusion_reason' => 'source file' }
        ],
        'PodA-DemoApp' => [
          { 'inclusion_reason' => 'CocoaPods lockfile', 'path' => 'Podfile.lock', 'yaml_keypath' => ['SPEC CHECKSUMS', 'PodA'] },
          { 'inclusion_reason' => 'podspec', 'path' => 'PodA/PodA.podspec.json' },
          { 'glob' => 'PodA/DemoApp/main.swift', 'inclusion_reason' => 'source file' }
        ],
        'PodB-iOS' => [
          { 'inclusion_reason' => 'CocoaPods lockfile', 'path' => 'Podfile.lock', 'yaml_keypath' => ['SPEC CHECKSUMS', 'PodB'] },
          { 'inclusion_reason' => 'podspec', 'path' => 'PodB/PodB.podspec.json' },
          { 'glob' => 'PodB/Sources/**/*.{h,m}', 'inclusion_reason' => 'source file' },
          { 'glob' => 'PodB/Sources/*.swift', 'inclusion_reason' => 'source file' },
          { 'glob' => 'PodB/Resources/bare/*.png', 'inclusion_reason' => 'resource' },
          { 'glob' => 'PodB/Scripts/*', 'inclusion_reason' => 'preserve path' },
          { 'glob' => 'PodB/Resources/1/**/*', 'inclusion_reason' => 'resource bundle' },
          { 'glob' => 'PodB/Resources/2/**/*', 'inclusion_reason' => 'resource bundle' }
        ],
        'PodB-macOS' => [
          { 'inclusion_reason' => 'CocoaPods lockfile', 'path' => 'Podfile.lock', 'yaml_keypath' => ['SPEC CHECKSUMS', 'PodB'] },
          { 'inclusion_reason' => 'podspec', 'path' => 'PodB/PodB.podspec.json' },
          { 'glob' => 'PodB/Sources/**/*.{h,m}', 'inclusion_reason' => 'source file' },
          { 'glob' => 'PodB/Sources/*.swift', 'inclusion_reason' => 'source file' },
          { 'glob' => 'PodB/Resources/bare/*.png', 'inclusion_reason' => 'resource' },
          { 'glob' => 'PodB/Scripts/*', 'inclusion_reason' => 'preserve path' },
          { 'glob' => 'PodB/Resources/1/**/*', 'inclusion_reason' => 'resource bundle' },
          { 'glob' => 'PodB/Resources/2/**/*', 'inclusion_reason' => 'resource bundle' }
        ],
        'PodC-iOS' => [
          { 'inclusion_reason' => 'CocoaPods lockfile', 'path' => 'Podfile.lock', 'yaml_keypath' => ['SPEC CHECKSUMS', 'PodC'] },
          { 'inclusion_reason' => 'podspec', 'path' => 'PodC/PodC.podspec.json' },
          { 'glob' => 'PodC/Sources/**/*.{h,m}', 'inclusion_reason' => 'source file' },
          { 'glob' => 'PodC/Sources/*.swift', 'inclusion_reason' => 'source file' },
          { 'glob' => 'PodC/SubSpec/Sources/*', 'inclusion_reason' => 'source file' },
          { 'glob' => 'PodC/include/*.h', 'inclusion_reason' => 'public header file' }
        ],
        'PodC-macOS' => [
          { 'inclusion_reason' => 'CocoaPods lockfile', 'path' => 'Podfile.lock', 'yaml_keypath' => ['SPEC CHECKSUMS', 'PodC'] },
          { 'inclusion_reason' => 'podspec', 'path' => 'PodC/PodC.podspec.json' },
          { 'glob' => 'PodC/Sources/**/*.{h,m}', 'inclusion_reason' => 'source file' },
          { 'glob' => 'PodC/Sources/*.swift', 'inclusion_reason' => 'source file' },
          { 'glob' => 'PodC/SubSpec/Sources/*', 'inclusion_reason' => 'source file' }
        ],
        'Pods-A Tests' => [
          { 'inclusion_reason' => 'user project', 'path' => 'UserProject.xcodeproj' }
        ],
        'Pods-A' => [
          { 'inclusion_reason' => 'user project', 'path' => 'UserProject.xcodeproj' }
        ],
        'Pods-B' => [
          { 'inclusion_reason' => 'user project', 'path' => 'UserProject.xcodeproj' }
        ],
        'Pods-B Mac' => [
          { 'inclusion_reason' => 'user project', 'path' => 'UserProject.xcodeproj' }
        ],
        'TestPodA' => [
          { 'inclusion_reason' => 'CocoaPods lockfile', 'path' => 'Podfile.lock', 'yaml_keypath' => ['SPEC CHECKSUMS', 'TestPodA'] },
          { 'inclusion_reason' => 'podspec', 'path' => 'TestPodA/TestPodA.podspec.json' },
          { 'glob' => 'TestPodA/Sources/**/*.{h,m}', 'inclusion_reason' => 'source file' },
          { 'glob' => 'TestPodA/Sources/*.swift', 'inclusion_reason' => 'source file' }
        ],
        'TestPodA-Unit-WhoTestsTheTests' => [
          { 'inclusion_reason' => 'CocoaPods lockfile', 'path' => 'Podfile.lock', 'yaml_keypath' => ['SPEC CHECKSUMS', 'TestPodA'] },
          { 'inclusion_reason' => 'podspec', 'path' => 'TestPodA/TestPodA.podspec.json' }
        ]
      )
    end
  end
end
