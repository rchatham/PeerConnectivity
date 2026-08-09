//
//  ViewController.swift
//  PeerConnectivityDemo
//
//  Created by Reid Chatham on 9/15/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import UIKit
import PeerConnectivity

private struct DemoPing : PeerMessage {
    internal let text : String
    internal let sentAt : Date
}

class ViewController: UIViewController {

    fileprivate var pcm : PeerConnectionManager!
    fileprivate var browserModel : PeerBrowserModel!
    fileprivate var discoveredPeers : [Peer] = []
    fileprivate var isConnecting = false

    fileprivate let backendControl = UISegmentedControl(items: ["Multipeer", "Network"])
    fileprivate let backendLabel = UILabel()
    fileprivate let connectionButton = UIButton(type: .system)
    fileprivate let userStatusLabel = UILabel()
    fileprivate let peersTableView = UITableView(frame: .zero, style: .insetGrouped)
    fileprivate let inviteButton = UIButton(type: .system)
    fileprivate let sendButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()

        configureInterface()
        backendControl.selectedSegmentIndex = ProcessInfo.processInfo.arguments.contains("PCNetworkBackend") ? 1 : 0
        configureManager()

        if ProcessInfo.processInfo.arguments.contains("PCAutoStart") {
            tappedConnectionButton(sender: connectionButton)
        }
    }

    private var selectedBackend : PeerConnectionBackend {
        return backendControl.selectedSegmentIndex == 1 ? .networkFramework : .multipeerConnectivity
    }

    private var selectedPeer : Peer? {
        guard let indexPath = peersTableView.indexPathForSelectedRow,
            discoveredPeers.indices.contains(indexPath.row) else { return nil }
        return discoveredPeers[indexPath.row]
    }

    private static func argumentValue(for key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private func configureInterface() {
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.text = "PeerConnectivity Demo"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true

        backendControl.addTarget(self, action: #selector(changedBackend(sender:)), for: .valueChanged)

        backendLabel.font = .preferredFont(forTextStyle: .footnote)
        backendLabel.textColor = .secondaryLabel
        backendLabel.numberOfLines = 0

        connectionButton.setTitle("Start networking", for: .normal)
        connectionButton.addTarget(self, action: #selector(tappedConnectionButton(sender:)), for: .touchUpInside)

        userStatusLabel.font = .preferredFont(forTextStyle: .body)
        userStatusLabel.numberOfLines = 0

        let peersLabel = UILabel()
        peersLabel.text = "Discovered peers"
        peersLabel.font = .preferredFont(forTextStyle: .headline)

        peersTableView.dataSource = self
        peersTableView.delegate = self
        peersTableView.register(UITableViewCell.self, forCellReuseIdentifier: "PeerCell")
        peersTableView.layer.borderColor = UIColor.separator.cgColor
        peersTableView.layer.borderWidth = 0.5
        peersTableView.layer.cornerRadius = 10

        inviteButton.setTitle("Invite selected peer", for: .normal)
        inviteButton.addTarget(self, action: #selector(inviteSelectedPeer), for: .touchUpInside)

        sendButton.setTitle("Send typed ping", for: .normal)
        sendButton.addTarget(self, action: #selector(sendPing), for: .touchUpInside)

        let actions = UIStackView(arrangedSubviews: [inviteButton, sendButton])
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        actions.spacing = 12

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            backendControl,
            backendLabel,
            connectionButton,
            userStatusLabel,
            peersLabel,
            peersTableView,
            actions,
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            peersTableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])

        updateControls()
    }

    private func configureManager() {
        browserModel?.stopObserving()
        pcm?.removeAllListeners()

        let displayName = ViewController.argumentValue(for: "PCDisplayName") ?? ProcessInfo.processInfo.hostName
        let connectionType : PeerConnectionType = selectedBackend == .networkFramework ? .custom : .automatic
        pcm = PeerConnectionManager(serviceType: "local",
            connectionType: connectionType,
            displayName: displayName,
            backend: selectedBackend)

        pcm.listenOn({ [weak self] event in
            self?.handle(event)
        }, withKey: "demo-status")
        pcm.observeMessages(ofType: DemoPing.self, forKey: "demo-ping") { [weak self] message, peer in
            self?.userStatusLabel.text = "Received ‘\(message.text)’ from \(peer.displayName)"
        }

        browserModel = PeerBrowserModel(manager: pcm) { [weak self] peers in
            self?.display(peers: peers)
        }
        browserModel.startObserving()
        discoveredPeers = []
        peersTableView.reloadData()
        userStatusLabel.text = "Stopped — no connected peers"
        updateControls()
    }

    private func handle(_ event: PeerConnectionEvent) {
        switch event {
        case .devicesChanged(_, let connectedPeers):
            if connectedPeers.isEmpty {
                userStatusLabel.text = "Running — no connected peers"
            } else {
                userStatusLabel.text = "Connected to: " + connectedPeers.map { $0.displayName }.joined(separator: ", ")
            }
            updateControls()
        case .started:
            userStatusLabel.text = "Running — searching for peers"
        case .error(let error):
            userStatusLabel.text = "Networking error: \(error.localizedDescription)"
        default:
            break
        }
    }

    private func display(peers: [Peer]) {
        let selected = selectedPeer
        discoveredPeers = peers
        peersTableView.reloadData()
        if let selected = selected,
            let row = discoveredPeers.firstIndex(of: selected) {
            peersTableView.selectRow(at: IndexPath(row: row, section: 0), animated: false, scrollPosition: .none)
        }
        updateControls()
    }

    private func updateControls() {
        let isNetwork = selectedBackend == .networkFramework
        backendLabel.text = isNetwork
            ? "Backend: Network.framework · manual invites · unauthenticated demo traffic"
            : "Backend: MultipeerConnectivity · automatic connections"
        backendControl.isEnabled = !isConnecting
        connectionButton.setTitle(isConnecting ? "Stop networking" : "Start networking", for: .normal)
        connectionButton.tintColor = isConnecting ? .systemRed : .systemBlue
        inviteButton.isEnabled = isConnecting && isNetwork && selectedPeer?.status == .notConnected
        sendButton.isEnabled = isConnecting && selectedPeer?.status == .connected
    }

    @objc internal func changedBackend(sender: UISegmentedControl) {
        guard !isConnecting else { return }
        configureManager()
    }

    @objc internal func tappedConnectionButton(sender: UIButton) {
        if isConnecting {
            pcm.stop()
            isConnecting = false
            userStatusLabel.text = "Stopped — no connected peers"
        } else {
            pcm.start()
            isConnecting = true
        }
        updateControls()
    }

    @objc internal func inviteSelectedPeer() {
        guard let peer = selectedPeer else { return }
        browserModel.invitePeer(peer)
        userStatusLabel.text = "Inviting \(peer.displayName)…"
    }

    @objc internal func sendPing() {
        guard let peer = selectedPeer, peer.status == .connected else { return }
        pcm.sendMessage(DemoPing(text: "Hello from \(pcm.peer.displayName)", sentAt: Date()), toPeers: [peer])
        userStatusLabel.text = "Sent typed ping to \(peer.displayName)"
    }
}

extension ViewController : UITableViewDataSource, UITableViewDelegate {

    internal func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return discoveredPeers.count
    }

    internal func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PeerCell", for: indexPath)
        let peer = discoveredPeers[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = peer.displayName
        content.secondaryText = peer.status.demoDescription
        cell.contentConfiguration = content
        return cell
    }

    internal func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        updateControls()
    }
}

private extension Peer.Status {
    var demoDescription : String {
        switch self {
        case .currentUser:
            return "Current device"
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .notConnected:
            return "Available"
        }
    }
}
