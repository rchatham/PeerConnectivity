//
//  ViewController.swift
//  PeerConnectivityDemo
//
//  Created by Reid Chatham on 9/15/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import UIKit
import PeerConnectivity

class ViewController: UIViewController {
    
    fileprivate lazy var pcm: PeerConnectionManager = {
        var pcm = PeerConnectionManager(serviceType: "local", securityIdentity: nil, encryptionPreference: .optional)

        pcm.listenOn({ [weak self] (event) in
            switch event {
            case .devicesChanged(let session, let peer, let connectedPeers):
                _ = connectedPeers.map { print($0.displayName) }

                defer {
                    if let origin = self?.userStatusLabel?.frame.origin,
                        let size = self?.userStatusLabel?.intrinsicContentSize {
                        self?.userStatusLabel?.frame = CGRect(origin: origin, size: size)
                    }
                }

                guard !connectedPeers.isEmpty else {
                    self?.userStatusLabel?.text = "Not Connected!"
                    return
                }

                if peer.status == .connected || peer.status == .notConnected {
                    self?.userStatusLabel?.text = connectedPeers.map { $0.displayName }.reduce("Connected to:") { $0 + "\n" + $1 }
                }

            default: break
            }
        }, withKey: "configurationKey")

        return pcm
    }()
    
    fileprivate var isConnecting = false
    
    fileprivate var connectionButton: UIButton!
    fileprivate var userStatusLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        connectionButton = UIButton(type: UIButton.ButtonType.system)
        connectionButton.setTitle("Start networking!", for: .normal)
        connectionButton.setTitleColor(.blue, for: .normal)
        connectionButton.sizeToFit()
        connectionButton.center = view.center
        connectionButton.addTarget(self, action: #selector(tappedConnectionButton(sender:)), for: UIControl.Event.touchUpInside)
        view.addSubview(connectionButton)
        
        userStatusLabel = UILabel()
        userStatusLabel.numberOfLines = 0
        userStatusLabel.text = "Not Connected!"
        userStatusLabel.sizeToFit()
        userStatusLabel.center = view.center
        let frame = userStatusLabel.frame
        userStatusLabel.frame = frame.offsetBy(dx: 0, dy: frame.size.height*2)
        view.addSubview(userStatusLabel)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @objc internal func tappedConnectionButton(sender: UIButton) {
        switch isConnecting {
        case false:
            try? pcm.start()
            isConnecting = true
            
            connectionButton.setTitle("Stop networking!", for: .normal)
            connectionButton.setTitleColor(.red, for: .normal)
            
        case true:
            pcm.stop()
            isConnecting = false
            
            connectionButton.setTitle("Start networking!", for: .normal)
            connectionButton.setTitleColor(.blue, for: .normal)
            
            userStatusLabel.text = "Not Connected!"
        }
    }
}

