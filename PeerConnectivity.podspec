Pod::Spec.new do |s|
  s.name         = "PeerConnectivity"
  s.version      = "0.5.4"
  s.summary      = "Functional wrapper for Apple's MultipeerConnectivity framework."
  s.description  = <<-DESC
				A functional wrapper around the MultipeerConnectivity framework that handles the edge cases of
				mesh-networks.
                   DESC
  s.homepage     = "https://github.com/rchatham/PeerConnectivity"
  s.license      = "MIT"
  s.author       = { "Reid Chatham" => "reid.chatham@gmail.com" }
  s.ios.deployment_target = "13.0"
  s.osx.deployment_target = "10.15"
  s.source       = { :git => "https://github.com/rchatham/PeerConnectivity.git", :tag => "#{s.version}" }
  s.source_files = "Sources/*.{swift,h}"
  s.frameworks   = "MultipeerConnectivity", "Network"
  s.swift_version = "5.0"
  # s.documentation_url = "http://reidchatham.com/docs/PeerConnectivity/Classes/PeerConnectionManager.html"
end
