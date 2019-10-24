## Cocoapods Spec Repositories
source 'https://cdn.cocoapods.org/'

# Uncomment the next line to define a global platform for your project
workspace 'PeerConnectivity'
project 'PeerConnectivity'
platform :ios, '11.0'

use_frameworks!
inhibit_all_warnings!

## Fix issue with new build system on `xcode-10` and cocoapods developments pods w/ input/output files.
## see https://github.com/CocoaPods/CocoaPods/issues/8073, https://github.com/CocoaPods/CocoaPods/issues/8151
## fix below found here: https://www.ralfebert.de/ios/blog/cocoapods-clean-input-output-files/
install! 'cocoapods', :disable_input_output_paths => true

### Define Targets && Associated Pod Components

target 'PeerConnectivity' do

    pod 'Logger', :git => "git@github.com:tillersystems/logger-ios.git", :tag => "0.3.0"

end
