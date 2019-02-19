require 'cocoapods'

Pod::Installer
  .prepend(Module.new do
             def perform_post_install_actions
               super

               return unless plugins.key?('refinement')

               unless Gem::Version.create(Pod::VERSION) >= Gem::Version.create('1.6.0')
                 raise Pod::Informative, 'Refinement requires a CocoaPods version >= 1.6.0'
               end

               require 'refinement/cocoapods_post_install_writer'
               Pod::UI.message 'Writing refinement file' do
                 Refinement::CocoaPodsPostInstallWriter.new(aggregate_targets, config, plugins['refinement']).write!
               end
             end
           end)
