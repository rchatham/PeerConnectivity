Pod::Spec.new do |s|
  s.name         = "PeerConnectivity"
  s.version      = "2.2.0-beta"

  s.summary      = "Functional wrapper for Apple's MultipeerConnectivity framework."
  s.description  = <<-DESC
				A functional wrapper around the MultipeerConnectivity framework that handles the edge cases of
				mesh-networks.
                   DESC

  s.license      = "MIT"
  s.author       = { "Reid Chatham" => "reid.chatham@gmail.com" }
  s.homepage     = "https://github.com/tillersystems/PeerConnectivity"

  s.swift_version = '4.2'
  s.ios.deployment_target = '11.0'

  s.source       = { :git => "https://github.com/tillersystems/PeerConnectivity.git", :tag => "#{s.version}" }
  s.source_files = "Sources/**/*.swift"

  ## Dependencies
  s.framework    = "MultipeerConnectivity"

  ## Required Tiller Dependencies
  s.dependency 'Logger'

end
