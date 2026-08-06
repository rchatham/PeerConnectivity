//
//  ViewController.swift
//  PeerConnectivityDemo
//
//  Created by Reid Chatham on 9/15/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import UIKit
import PeerConnectivity
import PeerConnectivityUI

class ViewController: UIViewController {

    fileprivate enum DemoMode: Int, CaseIterable {
        case open
        case encrypted
        case manualInvitation
        case filteredBrowser
        case rejectCertificate

        fileprivate var title : String {
            switch self {
            case .open: return "Open"
            case .encrypted: return "Encrypted"
            case .manualInvitation: return "Manual Invite"
            case .filteredBrowser: return "Filtered Browser"
            case .rejectCertificate: return "Reject Cert"
            }
        }

        fileprivate var instructions : String {
            switch self {
            case .open:
                return "Backward-compatible automatic mode: optional encryption, accept-all certificates, accept-all invitations."
            case .encrypted:
                return "Requires encrypted MCSession transport and uses a custom certificate policy that logs and accepts."
            case .manualInvitation:
                return "Automatic discovery, but incoming invitations show an accept/reject alert before joining."
            case .filteredBrowser:
                return "Invite-only mode with discoveryInfo protocol=2. Tap Open Browser to test peerFilter."
            case .rejectCertificate:
                return "Rejects all peer certificates. Use this to verify failed session establishment."
            }
        }

        fileprivate var discoveryInfo : PeerDiscoveryInfo {
            switch self {
            case .filteredBrowser:
                return ["protocol": "2", "mode": "filtered"]
            case .encrypted:
                return ["protocol": "2", "mode": "encrypted"]
            case .manualInvitation:
                return ["protocol": "1", "mode": "manual"]
            case .rejectCertificate:
                return ["protocol": "1", "mode": "reject"]
            case .open:
                return ["protocol": "1", "mode": "open"]
            }
        }
    }

    fileprivate let serviceType : ServiceType = "local"
    fileprivate var currentMode : DemoMode = .open
    fileprivate var pcm : PeerConnectionManager!
    fileprivate var isConnecting = false

    fileprivate var modeControl : UISegmentedControl!
    fileprivate var connectionButton : UIButton!
    fileprivate var browserButton : UIButton!
    fileprivate var userStatusLabel : UILabel!
    fileprivate var logTextView : UITextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        configureControls()
        rebuildManager()
        updateInterfaceForCurrentMode()
        appendLog("Service type valid: \(PeerConnectionManager.isValidServiceType(serviceType))")
        appendLog("Display name valid: \(Peer.isValidDisplayName(UIDevice.current.name))")
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    fileprivate func configureControls() {
        modeControl = UISegmentedControl(items: DemoMode.allCases.map { $0.title })
        modeControl.selectedSegmentIndex = currentMode.rawValue
        modeControl.addTarget(self, action: #selector(changedMode(sender:)), for: .valueChanged)
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modeControl)

        connectionButton = UIButton(type: UIButton.ButtonType.system)
        connectionButton.setTitle("Start networking", for: .normal)
        connectionButton.setTitleColor(.blue, for: .normal)
        connectionButton.addTarget(self, action: #selector(tappedConnectionButton(sender:)), for: UIControl.Event.touchUpInside)
        connectionButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(connectionButton)

        browserButton = UIButton(type: UIButton.ButtonType.system)
        browserButton.setTitle("Open Filtered Browser", for: .normal)
        browserButton.addTarget(self, action: #selector(tappedBrowserButton(sender:)), for: UIControl.Event.touchUpInside)
        browserButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(browserButton)

        userStatusLabel = UILabel()
        userStatusLabel.numberOfLines = 0
        userStatusLabel.textAlignment = .center
        userStatusLabel.text = "Not Connected!"
        userStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(userStatusLabel)

        logTextView = UITextView()
        logTextView.isEditable = false
        logTextView.font = UIFont.preferredFont(forTextStyle: .footnote)
        logTextView.layer.borderColor = UIColor.lightGray.cgColor
        logTextView.layer.borderWidth = 1
        logTextView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logTextView)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            modeControl.topAnchor.constraint(equalTo: guide.topAnchor, constant: 20),
            modeControl.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            modeControl.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),

            connectionButton.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 20),
            connectionButton.centerXAnchor.constraint(equalTo: guide.centerXAnchor),

            browserButton.topAnchor.constraint(equalTo: connectionButton.bottomAnchor, constant: 12),
            browserButton.centerXAnchor.constraint(equalTo: guide.centerXAnchor),

            userStatusLabel.topAnchor.constraint(equalTo: browserButton.bottomAnchor, constant: 20),
            userStatusLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            userStatusLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),

            logTextView.topAnchor.constraint(equalTo: userStatusLabel.bottomAnchor, constant: 20),
            logTextView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            logTextView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            logTextView.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
        ])
    }

    fileprivate func rebuildManager() {
        pcm?.stop()
        pcm?.removeAllListeners()
        pcm = makeManager(mode: currentMode)
        configureListeners(for: pcm)
    }

    fileprivate func makeManager(mode: DemoMode) -> PeerConnectionManager {
        switch mode {
        case .open:
            return PeerConnectionManager(
                serviceType: serviceType,
                connectionType: .automatic,
                displayName: UIDevice.current.name,
                discoveryInfo: mode.discoveryInfo
            )
        case .encrypted:
            let configuration = PeerSecurityConfiguration(
                encryptionPreference: .required,
                securityIdentity: nil,
                certificatePolicy: .custom { [weak self] peer, certificate, handler in
                    self?.appendLog("Custom certificate policy for \(peer.displayName); certificate count: \(certificate?.count ?? 0)")
                    handler(true)
                }
            )
            return PeerConnectionManager(
                serviceType: serviceType,
                connectionType: .automatic,
                displayName: UIDevice.current.name,
                securityConfiguration: configuration,
                discoveryInfo: mode.discoveryInfo,
                invitationPolicy: .acceptAll
            )
        case .manualInvitation:
            return PeerConnectionManager(
                serviceType: serviceType,
                connectionType: .automatic,
                displayName: UIDevice.current.name,
                discoveryInfo: mode.discoveryInfo,
                invitationPolicy: .manual
            )
        case .filteredBrowser:
            return PeerConnectionManager(
                serviceType: serviceType,
                connectionType: .inviteOnly,
                displayName: UIDevice.current.name,
                securityConfiguration: .encrypted,
                discoveryInfo: mode.discoveryInfo,
                invitationPolicy: .acceptAll
            )
        case .rejectCertificate:
            let configuration = PeerSecurityConfiguration(
                encryptionPreference: .optional,
                securityIdentity: nil,
                certificatePolicy: .rejectAll
            )
            return PeerConnectionManager(
                serviceType: serviceType,
                connectionType: .automatic,
                displayName: UIDevice.current.name,
                securityConfiguration: configuration,
                discoveryInfo: mode.discoveryInfo,
                invitationPolicy: .acceptAll
            )
        }
    }

    fileprivate func configureListeners(for manager: PeerConnectionManager) {
        manager.listenOn({ [weak self] event in
            switch event {
            case .started:
                self?.appendLog("Started \(self?.currentMode.title ?? "mode")")
            case .devicesChanged(let peer, let connectedPeers):
                self?.appendLog("Device changed: \(peer.displayName) -> \(peer.status)")
                self?.updateConnectedPeers(connectedPeers)
            case .foundPeer(let peer):
                self?.appendLog("Found peer: \(peer.displayName)")
            case .foundPeerWithDiscoveryInfo(let peer, let discoveryInfo):
                self?.appendLog("Found metadata for \(peer.displayName): \(discoveryInfo ?? [:])")
            case .receivedInvitation(let peer, let context, let invitationHandler):
                self?.presentInvitationPrompt(peer: peer, context: context, invitationHandler: invitationHandler)
            case .receivedCertificate(let peer, let certificate, _):
                self?.appendLog("Observed certificate from \(peer.displayName); count: \(certificate?.count ?? 0)")
            case .error(let error):
                self?.appendLog("Error: \(error.localizedDescription)")
            default: break
            }
        }, withKey: "demo-listener")
    }

    fileprivate func updateInterfaceForCurrentMode() {
        browserButton.isHidden = currentMode != .filteredBrowser
        userStatusLabel.text = "Not Connected!\n\n\(currentMode.instructions)"
        connectionButton.setTitle(isConnecting ? "Stop networking" : "Start networking", for: .normal)
        connectionButton.setTitleColor(isConnecting ? .red : .blue, for: .normal)
    }

    fileprivate func updateConnectedPeers(_ connectedPeers: [Peer]) {
        guard !connectedPeers.isEmpty else {
            userStatusLabel.text = "Not Connected!\n\n\(currentMode.instructions)"
            return
        }
        userStatusLabel.text = connectedPeers.map { $0.displayName }.reduce("Connected to:") { $0 + "\n" + $1 }
    }

    fileprivate func presentInvitationPrompt(peer: Peer, context: Data?, invitationHandler: @escaping (Bool)->Void) {
        let contextText: String
        if let context = context, let string = String(data: context, encoding: .utf8) {
            contextText = string
        } else {
            contextText = "No context"
        }

        let alert = UIAlertController(
            title: "Invitation from \(peer.displayName)",
            message: "Context: \(contextText)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Reject", style: .destructive) { _ in
            self.appendLog("Rejected invitation from \(peer.displayName)")
            invitationHandler(false)
        })
        alert.addAction(UIAlertAction(title: "Accept", style: .default) { _ in
            self.appendLog("Accepted invitation from \(peer.displayName)")
            invitationHandler(true)
        })
        present(alert, animated: true)
    }

    fileprivate func appendLog(_ message: String) {
        DispatchQueue.main.async {
            let existing = self.logTextView.text ?? ""
            let line = "• \(message)"
            self.logTextView.text = existing.isEmpty ? line : existing + "\n" + line
            let bottom = NSRange(location: max(self.logTextView.text.count - 1, 0), length: 1)
            self.logTextView.scrollRangeToVisible(bottom)
        }
    }

    @objc internal func changedMode(sender: UISegmentedControl) {
        guard let mode = DemoMode(rawValue: sender.selectedSegmentIndex) else { return }
        if isConnecting {
            pcm.stop()
            isConnecting = false
        }
        currentMode = mode
        rebuildManager()
        appendLog("Selected mode: \(mode.title)")
        updateInterfaceForCurrentMode()
    }

    @objc internal func tappedConnectionButton(sender: UIButton) {
        switch isConnecting {
        case false:
            pcm.start()
            isConnecting = true
        case true:
            pcm.stop()
            isConnecting = false
            userStatusLabel.text = "Not Connected!\n\n\(currentMode.instructions)"
            appendLog("Stopped networking")
        }
        updateInterfaceForCurrentMode()
    }

    @objc internal func tappedBrowserButton(sender: UIButton) {
        if !isConnecting {
            pcm.startAdvertisingOnly()
            isConnecting = true
            updateInterfaceForCurrentMode()
            appendLog("Started advertising for filtered browser")
        }

        guard let browserViewController = pcm.browserViewController({ [weak self] event in
            switch event {
            case .didFinish:
                self?.appendLog("Browser finished")
            case .wasCancelled:
                self?.appendLog("Browser cancelled")
            default: break
            }
        }, peerFilter: { [weak self] peer, discoveryInfo in
            let allowed = discoveryInfo?["protocol"] == "2"
            self?.appendLog("Filter \(allowed ? "allowed" : "blocked") \(peer.displayName): \(discoveryInfo ?? [:])")
            return allowed
        }) else {
            appendLog("Browser is only available in Filtered Browser mode")
            return
        }
        guard presentedViewController == nil else {
            appendLog("Browser is already open")
            return
        }
        present(browserViewController, animated: true)
    }
}
