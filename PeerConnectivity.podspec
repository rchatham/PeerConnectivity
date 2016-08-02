Pod::Spec.new do |s|
  s.name         = "PeerConnectivity"
  s.version      = "0.2.1"
  s.summary      = "Functional wrapper for Apple's MultipeerConnectivity framework."
  s.description  = <<-DESC
				A functional wrapper around the MultipeerConnectivity framework that handles edge cases of
				mesh-networks for multiple configurations and allowing access to the delegate callback using
				a '.listenOn { event in }' syntax. All you have to configure is initialize your PeerConnectionManager
				and configure your event handling and you are ready to go.
                   DESC
  s.homepage     = "https://github.com/rchatham/PeerConnectivity"
  s.license      = "MIT"
  s.author             = { "Reid Chatham" => "email@address.com" }
  s.platform     = :ios, "8.0"
  s.source       = { :git => "https://github.com/rchatham/PeerConnectivity.git", :tag => "#{s.version}" }
  s.source_files  = "PeerConnectivity/*"
  s.framework  = "MultipeerConnectivity"
end
