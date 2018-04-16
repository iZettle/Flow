Pod::Spec.new do |s|
  s.name         = "FlowFramework"
  s.version      = "1.0.0"
  s.module_name  = "Flow"
  s.summary      = "Working with asynchronous flows"
  s.description  = <<-DESC
                   Flow is a Swift library for working with event handling, asynchronous operations and life time management.
                   DESC
  s.homepage     = "https://github.com/iZettle/Flow"
  s.license      = { :type => "MIT", :file => "LICENSE.md" }
  s.author       = { 'iZettle AB' => 'hello@izettle.com' }

  s.osx.deployment_target = "10.9"
  s.ios.deployment_target = "9.0"

  s.source       = { :git => "https://github.com/iZettle/Flow.git", :tag => "#{s.version}" }
  s.source_files = "Flow/*.{swift}"
end
