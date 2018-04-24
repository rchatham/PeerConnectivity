Pod::Spec.new do |s|
  s.name         = "PeerConnectivity"
  s.version      = "1.0.0"

  s.summary      = "Functional wrapper for Apple's MultipeerConnectivity framework."
  s.description  = <<-DESC
				A functional wrapper around the MultipeerConnectivity framework that handles the edge cases of
				mesh-networks.
                   DESC

  s.license      = "MIT"
  s.author       = { "Reid Chatham" => "reid.chatham@gmail.com" }
  s.homepage     = "https://github.com/tillersystems/PeerConnectivity"
  
  s.swift_version = '4.0'
  s.ios.deployment_target = '10.1'

  s.source       = { :git => "https://github.com/tillersystems/PeerConnectivity.git", :tag => "#{s.version}" }
  s.source_files = "Sources/*"
  s.framework    = "MultipeerConnectivity"

end
