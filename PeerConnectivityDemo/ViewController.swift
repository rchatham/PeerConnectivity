//
//  ViewController.swift
//  PeerConnectivityDemo
//
//  Created by Reid Chatham on 9/15/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import Foundation
import UIKit
import PeerConnectivity

class ViewController: UIViewController {

    fileprivate enum ConnectionMode : String {
        case advertisingAndBrowsing = "Advertising + Browsing"
        case advertisingOnly = "Advertising Only"
        case browsingOnly = "Browsing Only"

        fileprivate var isAdvertising : Bool {
            switch self {
            case .advertisingAndBrowsing, .advertisingOnly: return true
            case .browsingOnly: return false
            }
        }

        fileprivate var isBrowsing : Bool {
            switch self {
            case .advertisingAndBrowsing, .browsingOnly: return true
            case .advertisingOnly: return false
            }
        }
    }

    fileprivate enum ConnectionBehavior : String {
        case automatic = "Automatic"
        case requireInvitation = "Require Invitation"

        fileprivate var connectionType : PeerConnectionType {
            switch self {
            case .automatic: return .automatic
            case .requireInvitation: return .custom
            }
        }
    }

    fileprivate var pcm : PeerConnectionManager!
    fileprivate var browserModel : PeerBrowserModel!
    fileprivate var isNetworking = false
    fileprivate var mode : ConnectionMode = .advertisingAndBrowsing
    fileprivate var multipeerConnectionBehavior : ConnectionBehavior = .automatic
    fileprivate var networkConnectionBehavior : ConnectionBehavior = .requireInvitation
    fileprivate var discoveredPeers : [Peer] = []
    fileprivate var connectedPeers : [Peer] = []
    fileprivate var selectedTargetPeer : Peer?
    fileprivate var activeLogCategories = Set(LogCategory.allCases)
    fileprivate var messageHistory : [MessageHistoryEntry] = []
    fileprivate var checkedItems : Set<DemoChecklistItem> = []
    fileprivate let logStore = LogStore()
    fileprivate let historyDateFormatter : DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    fileprivate let scrollView = UIScrollView()
    fileprivate let contentStack = UIStackView()
    fileprivate let statusBadgeLabel = UILabel()
    fileprivate let advertisingBadgeLabel = UILabel()
    fileprivate let browsingBadgeLabel = UILabel()
    fileprivate let connectedBadgeLabel = UILabel()
    fileprivate let localPeerLabel = UILabel()
    fileprivate let backendControl = UISegmentedControl(items: ["Multipeer", "Network"])
    fileprivate let connectionBehaviorControl = UISegmentedControl(items: ["Automatic", "Require Invitation"])
    fileprivate let backendDetailLabel = UILabel()
    fileprivate let modeButton = UIButton(type: .system)
    fileprivate let startStopButton = UIButton(type: .system)
    fileprivate let refreshButton = UIButton(type: .system)
    fileprivate let resetButton = UIButton(type: .system)
    fileprivate let discoveredPeersLabel = UILabel()
    fileprivate let inviteButtonsStack = UIStackView()
    fileprivate let connectedPeersLabel = UILabel()
    fileprivate let targetButton = UIButton(type: .system)
    fileprivate let messageTextField = UITextField()
    fileprivate let sendButton = UIButton(type: .system)
    fileprivate let messageHistoryTextView = UITextView()
    fileprivate let rawDataButton = UIButton(type: .system)
    fileprivate let resourceButton = UIButton(type: .system)
    fileprivate let logFilterButton = UIButton(type: .system)
    fileprivate let copyLogsButton = UIButton(type: .system)
    fileprivate let shareButton = UIButton(type: .system)
    fileprivate let clearLogButton = UIButton(type: .system)
    fileprivate let eventLogTextView = UITextView()
    fileprivate let troubleshootingLabel = UILabel()
    fileprivate let checklistStack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Peer Demo"
        backendControl.selectedSegmentIndex = ProcessInfo.processInfo.arguments.contains("PCNetworkBackend") ? 1 : 0
        configureLayout()
        configureActions()
        configureManager()
        refreshUI()
        appendLog(kind: "app.ready", detail: "Local peer: \(pcm.peer.displayName); backend: \(backendName)")
        if ProcessInfo.processInfo.arguments.contains("PCAutoStart") {
            startNetworking()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed {
            browserModel.stopObserving()
            pcm.stop()
        }
    }
}

extension ViewController : UITextFieldDelegate {
    internal func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendMessage()
        return true
    }
}

private extension ViewController {
    static func argumentValue(for key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    var selectedBackend : PeerConnectionBackend {
        return backendControl.selectedSegmentIndex == 1 ? .networkFramework : .multipeerConnectivity
    }

    var isNetworkBackend : Bool {
        return selectedBackend == .networkFramework
    }

    var backendName : String {
        return isNetworkBackend ? "Network.framework" : "MultipeerConnectivity"
    }

    var selectedConnectionBehavior : ConnectionBehavior {
        get {
            return isNetworkBackend ? networkConnectionBehavior : multipeerConnectionBehavior
        }
        set {
            if isNetworkBackend {
                networkConnectionBehavior = newValue
            } else {
                multipeerConnectionBehavior = newValue
            }
        }
    }

    func configureManager() {
        browserModel?.stopObserving()
        pcm?.stop()
        pcm?.removeAllListeners()

        let requestedDisplayName = ViewController.argumentValue(for: "PCDisplayName") ?? ProcessInfo.processInfo.hostName
        let displayName = Peer.sanitizedDisplayName(requestedDisplayName)
        pcm = PeerConnectionManager(
            serviceType: "local",
            connectionType: selectedConnectionBehavior.connectionType,
            displayName: displayName,
            securityConfiguration: .default,
            invitationPolicy: .acceptAll,
            backend: selectedBackend,
            networkSecurity: .unauthenticated
        )
        pcm.listenOn({ [weak self] event in
            self?.handlePeerConnectionEvent(event)
        }, withKey: "demo.events")
        pcm.observeMessages(ofType: DemoMessage.self, forKey: "demo.messages") { [weak self] message, peer in
            self?.handleDemoMessage(message, from: peer)
        }

        browserModel = PeerBrowserModel(manager: pcm) { [weak self] peers in
            self?.discoveredPeers = peers
            self?.refreshUI()
        }
        if selectedConnectionBehavior == .requireInvitation {
            browserModel.startObserving()
        }
    }

    func configureLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        contentStack.isLayoutMarginsRelativeArrangement = true

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        [localPeerLabel, backendDetailLabel, discoveredPeersLabel, connectedPeersLabel, troubleshootingLabel].forEach { $0.numberOfLines = 0 }
        backendDetailLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        backendDetailLabel.textColor = .secondaryLabel
        inviteButtonsStack.axis = .vertical
        inviteButtonsStack.spacing = 8
        configureMenuButton(modeButton)
        configureMenuButton(targetButton)
        configureMenuButton(logFilterButton)
        configurePrimaryButton(startStopButton, title: "Start")
        configureSecondaryButton(refreshButton, title: "Refresh")
        configureSecondaryButton(resetButton, title: "Reset Demo")
        configurePrimaryButton(sendButton, title: "Send Typed Message")
        configureSecondaryButton(rawDataButton, title: "Send Raw Data Ping")
        configureSecondaryButton(resourceButton, title: "Send Demo Resource")
        configureSecondaryButton(copyLogsButton, title: "Copy Logs")
        configureSecondaryButton(shareButton, title: "Share Logs")
        configureSecondaryButton(clearLogButton, title: "Clear Logs")

        messageTextField.borderStyle = .roundedRect
        messageTextField.placeholder = "Typed message or ping to selected target"
        messageTextField.returnKeyType = .send
        messageTextField.delegate = self

        configureTextView(messageHistoryTextView)
        configureTextView(eventLogTextView)

        checklistStack.axis = .vertical
        checklistStack.spacing = 8

        contentStack.addArrangedSubview(sectionTitle("Session"))
        contentStack.addArrangedSubview(localPeerLabel)
        contentStack.addArrangedSubview(backendControl)
        contentStack.addArrangedSubview(connectionBehaviorControl)
        contentStack.addArrangedSubview(backendDetailLabel)
        contentStack.addArrangedSubview(statusCardRow())
        contentStack.addArrangedSubview(modeButton)
        contentStack.addArrangedSubview(buttonRow([startStopButton, refreshButton]))
        contentStack.addArrangedSubview(resetButton)

        contentStack.addArrangedSubview(sectionTitle("Peers"))
        contentStack.addArrangedSubview(discoveredPeersLabel)
        contentStack.addArrangedSubview(inviteButtonsStack)
        contentStack.addArrangedSubview(connectedPeersLabel)

        contentStack.addArrangedSubview(sectionTitle("Messages"))
        contentStack.addArrangedSubview(targetButton)
        contentStack.addArrangedSubview(messageTextField)
        contentStack.addArrangedSubview(sendButton)
        contentStack.addArrangedSubview(messageHistoryTextView)

        contentStack.addArrangedSubview(sectionTitle("API Demos"))
        contentStack.addArrangedSubview(buttonRow([rawDataButton, resourceButton]))

        contentStack.addArrangedSubview(sectionTitle("Logs"))
        contentStack.addArrangedSubview(logFilterButton)
        contentStack.addArrangedSubview(buttonRow([copyLogsButton, shareButton]))
        contentStack.addArrangedSubview(clearLogButton)
        contentStack.addArrangedSubview(eventLogTextView)

        contentStack.addArrangedSubview(sectionTitle("Troubleshooting"))
        contentStack.addArrangedSubview(troubleshootingLabel)

        contentStack.addArrangedSubview(sectionTitle("Physical Test Checklist"))
        contentStack.addArrangedSubview(checklistStack)
    }

    func configureActions() {
        backendControl.addTarget(self, action: #selector(changedBackend(_:)), for: .valueChanged)
        connectionBehaviorControl.addTarget(self, action: #selector(changedConnectionBehavior(_:)), for: .valueChanged)
        backendControl.accessibilityLabel = "Networking backend"
        backendControl.accessibilityHint = "Selects the transport backend while networking is stopped"
        connectionBehaviorControl.accessibilityLabel = "Connection behavior"
        connectionBehaviorControl.accessibilityHint = "Choose automatic connections or explicit peer invitations while networking is stopped"
        startStopButton.accessibilityHint = "Starts or stops peer advertising and browsing"
        startStopButton.addTarget(self, action: #selector(tappedStartStop(_:)), for: .touchUpInside)
        refreshButton.addTarget(self, action: #selector(tappedRefresh(_:)), for: .touchUpInside)
        resetButton.addTarget(self, action: #selector(tappedReset(_:)), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(tappedSend(_:)), for: .touchUpInside)
        rawDataButton.addTarget(self, action: #selector(tappedRawData(_:)), for: .touchUpInside)
        resourceButton.addTarget(self, action: #selector(tappedResource(_:)), for: .touchUpInside)
        copyLogsButton.addTarget(self, action: #selector(tappedCopyLogs(_:)), for: .touchUpInside)
        shareButton.addTarget(self, action: #selector(tappedShare(_:)), for: .touchUpInside)
        clearLogButton.addTarget(self, action: #selector(tappedClearLog(_:)), for: .touchUpInside)
    }

    func configurePrimaryButton(_ button: UIButton, title: String) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        button.configuration = configuration
    }

    func configureSecondaryButton(_ button: UIButton, title: String) {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        button.configuration = configuration
    }

    func configureMenuButton(_ button: UIButton) {
        var configuration = UIButton.Configuration.gray()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        configuration.titleAlignment = .leading
        button.configuration = configuration
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = false
    }

    func configureTextView(_ textView: UITextView) {
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
    }

    func sectionTitle(_ title: String) -> UILabel {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.text = title
        return label
    }

    func statusCardRow() -> UIStackView {
        [statusBadgeLabel, advertisingBadgeLabel, browsingBadgeLabel, connectedBadgeLabel].forEach(configureBadgeLabel(_:))
        let stack = UIStackView(arrangedSubviews: [statusBadgeLabel, advertisingBadgeLabel, browsingBadgeLabel, connectedBadgeLabel])
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 8
        return stack
    }

    func configureBadgeLabel(_ label: UILabel) {
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.backgroundColor = .secondarySystemBackground
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
    }

    func buttonRow(_ buttons: [UIButton]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12
        return stack
    }

    func refreshUI() {
        if let targetPeer = selectedTargetPeer, !connectedPeers.contains(targetPeer) {
            selectedTargetPeer = nil
        }

        localPeerLabel.text = "Local: \(pcm.peer.displayName)"
        connectionBehaviorControl.selectedSegmentIndex = selectedConnectionBehavior == .automatic ? 0 : 1
        if selectedConnectionBehavior == .automatic {
            backendDetailLabel.text = "\(backendName) · automatic discovery and connections\(isNetworkBackend ? " · unauthenticated demo transport" : " · default optional encryption and certificate policy")"
        } else {
            backendDetailLabel.text = "\(backendName) · app-owned discovery and explicit invitations via PeerBrowserModel\(isNetworkBackend ? " · unauthenticated demo transport" : "")"
        }
        backendControl.isEnabled = !isNetworking
        connectionBehaviorControl.isEnabled = !isNetworking
        statusBadgeLabel.text = isNetworking ? "Running" : "Stopped"
        advertisingBadgeLabel.text = isNetworking && mode.isAdvertising ? "Advertising" : "Not Advertising"
        browsingBadgeLabel.text = isNetworking && mode.isBrowsing ? "Browsing" : "Not Browsing"
        connectedBadgeLabel.text = "Connected\n\(connectedPeers.count)"
        discoveredPeersLabel.text = peerList(title: "Discovered", peers: discoveredPeers)
        rebuildInviteButtons()
        connectedPeersLabel.text = peerList(title: "Connected", peers: connectedPeers)
        startStopButton.configuration?.title = isNetworking ? "Stop" : "Start"
        refreshButton.isEnabled = isNetworking
        sendButton.isEnabled = !connectedPeers.isEmpty
        rawDataButton.isEnabled = !connectedPeers.isEmpty
        resourceButton.isEnabled = !connectedPeers.isEmpty
        messageHistoryTextView.text = messageHistorySummary()
        eventLogTextView.text = logStore.textSummary(categories: activeLogCategories)
        troubleshootingLabel.text = troubleshootingText()
        updateModeMenu()
        updateTargetMenu()
        updateLogFilterMenu()
        rebuildChecklist()
    }

    func peerList(title: String, peers: [Peer]) -> String {
        guard !peers.isEmpty else { return "\(title): none" }
        return peers.map { "• \($0.displayName) [\(statusText($0.status))]" }.reduce("\(title):") { $0 + "\n" + $1 }
    }

    func statusText(_ status: Peer.Status) -> String {
        switch status {
        case .currentUser: return "current"
        case .connected: return "connected"
        case .connecting: return "connecting"
        case .notConnected: return "not connected"
        }
    }

    func messageHistorySummary() -> String {
        guard !messageHistory.isEmpty else { return "No messages sent or received yet." }
        return messageHistory.map { $0.textLine(dateFormatter: historyDateFormatter) }.joined(separator: "\n\n")
    }

    func troubleshootingText() -> String {
        var hints : [String] = []
        if !isNetworking {
            hints.append("Start networking to advertise, browse, and connect to nearby devices.")
        }
        if selectedConnectionBehavior == .requireInvitation {
            hints.append("Require Invitation waits for an explicit Invite action on a discovered peer before messages can be sent.")
        } else {
            hints.append("Automatic connects to discovered peers without an app-owned Invite action.")
        }
        if isNetworkBackend {
            hints.append("Network demo traffic is unauthenticated; do not send sensitive data.")
        } else {
            hints.append("Multipeer remains the default backend.")
        }
        if isNetworking && discoveredPeers.isEmpty && connectedPeers.isEmpty {
            hints.append("No peers yet. Confirm both devices use the same service type, are on the same Wi‑Fi or have Bluetooth enabled, and accepted Local Network permission.")
        }
        if isNetworking && !mode.isAdvertising {
            hints.append("Advertising is disabled. Another device cannot discover this one unless it is already connected or this mode changes.")
        }
        if isNetworking && !mode.isBrowsing {
            hints.append("Browsing is disabled. This device will wait for invitations instead of searching for peers.")
        }
        if connectedPeers.isEmpty {
            hints.append("Connect at least one peer before sending messages, raw data, or resources.")
        }
        hints.append("For a focused two-device test, put one device in Advertising Only and the other in Browsing Only, then use Refresh if state looks stale.")
        return hints.map { "• \($0)" }.joined(separator: "\n")
    }

    func startNetworking() {
        switch mode {
        case .advertisingAndBrowsing:
            pcm.startAdvertisingAndBrowsing()
        case .advertisingOnly:
            pcm.startAdvertisingOnly()
        case .browsingOnly:
            pcm.startBrowsingOnly()
        }
        isNetworking = true
        if mode.isAdvertising { checkedItems.insert(.deviceAAdvertising) }
        if mode.isBrowsing { checkedItems.insert(.deviceBBrowsing) }
        appendLog(kind: "session.start.requested", detail: "\(backendName), \(selectedConnectionBehavior.rawValue), \(mode.rawValue)")
        refreshUI()
    }

    func stopNetworking() {
        pcm.stop()
        isNetworking = false
        discoveredPeers = []
        connectedPeers = []
        selectedTargetPeer = nil
        appendLog(kind: "session.stop.requested", detail: "Stopped by user")
        refreshUI()
    }

    func sendMessage() {
        let text = messageTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }
        guard !connectedPeers.isEmpty else {
            appendLog(kind: "message.send.failed", detail: "No connected peers", direction: .outbound)
            return
        }

        guard validateTargetSelection(kind: "message.send.failed") else { return }
        let peers = selectedTargetPeers()
        let targetNames = selectedTargetNames()
        let message = DemoMessage(text: text, senderDisplayName: pcm.peer.displayName)
        pcm.sendMessage(message, toPeers: peers)
        messageHistory.append(MessageHistoryEntry(
            direction: .outbound,
            sender: pcm.peer.displayName,
            targets: targetNames,
            text: text
        ))
        checkedItems.insert(.messageSent)
        appendLog(kind: "message.sent", detail: "\(text) → \(targetSummary())", peers: peers.isEmpty ? connectedPeers : peers, direction: .outbound)
        messageTextField.text = ""
        messageTextField.resignFirstResponder()
        refreshUI()
    }

    func sendRawDataPing() {
        guard !connectedPeers.isEmpty else {
            appendLog(kind: "data.send.failed", detail: "No connected peers", direction: .outbound)
            return
        }
        let payload = "raw-ping:\(Date().timeIntervalSince1970)"
        guard let data = payload.data(using: .utf8) else { return }
        guard validateTargetSelection(kind: "data.send.failed") else { return }
        let peers = selectedTargetPeers()
        pcm.sendData(data, toPeers: peers)
        appendLog(kind: "data.sent", detail: "\(data.count) bytes → \(targetSummary())", peers: peers.isEmpty ? connectedPeers : peers, direction: .outbound)
        refreshUI()
    }

    func sendDemoResource() {
        guard !connectedPeers.isEmpty else {
            appendLog(kind: "resource.send.failed", detail: "No connected peers", direction: .outbound)
            return
        }
        do {
            guard validateTargetSelection(kind: "resource.send.failed") else { return }
            let url = try writeTemporaryDemoResource()
            let peers = selectedTargetPeers()
            let progressByPeer = pcm.sendResourceAtURL(url, withName: url.lastPathComponent, toPeers: peers) { [weak self] error in
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async {
                    if let error = error {
                        self?.appendLog(kind: "resource.send.error", detail: error.localizedDescription, direction: .outbound)
                    } else {
                        self?.appendLog(kind: "resource.send.finished", detail: url.lastPathComponent, direction: .outbound)
                    }
                }
            }
            let progressSummary = progressByPeer.map { "\($0.key.displayName): \($0.value == nil ? "no progress" : "tracking")" }.joined(separator: ", ")
            appendLog(kind: "resource.send.started", detail: "\(url.lastPathComponent) → \(targetSummary()) (\(progressSummary))", peers: peers.isEmpty ? connectedPeers : peers, direction: .outbound)
        } catch let error {
            appendLog(kind: "resource.send.error", detail: error.localizedDescription, direction: .outbound)
        }
        refreshUI()
    }

    func writeTemporaryDemoResource() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("peerconnectivity-demo-\(Int(Date().timeIntervalSince1970)).json")
        let payload = """
        {
          "kind": "peerconnectivity-demo-resource",
          "sender": "\(pcm.peer.displayName)",
          "createdAt": "\(ISO8601DateFormatter().string(from: Date()))"
        }
        """
        try payload.data(using: .utf8)?.write(to: url)
        return url
    }

    func selectedTargetPeers() -> [Peer] {
        guard let selectedTargetPeer = selectedTargetPeer else { return [] }
        return [selectedTargetPeer]
    }

    func validateTargetSelection(kind: String) -> Bool {
        guard let selectedTargetPeer = selectedTargetPeer else { return true }
        guard connectedPeers.contains(selectedTargetPeer) else {
            appendLog(kind: kind, detail: "Selected target is no longer connected", direction: .outbound)
            self.selectedTargetPeer = nil
            return false
        }
        return true
    }

    func selectedTargetNames() -> [String] {
        guard let selectedTargetPeer = selectedTargetPeer else { return [] }
        return [selectedTargetPeer.displayName]
    }

    func targetSummary() -> String {
        guard let selectedTargetPeer = selectedTargetPeer else { return "Broadcast" }
        return selectedTargetPeer.displayName
    }

    func handleDemoMessage(_ message: DemoMessage, from peer: Peer) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.messageHistory.append(MessageHistoryEntry(
                direction: .inbound,
                sender: peer.displayName,
                targets: [self.pcm.peer.displayName],
                text: message.text
            ))
            self.checkedItems.insert(.messageReceived)
            self.appendLog(
                kind: "message.received",
                detail: "\(peer.displayName): \(message.text)",
                peers: [peer],
                direction: .inbound
            )
        }
    }

    func appendLog(kind: String, detail: String, peers: [Peer] = [], direction: LogEntry.Direction = .local) {
        logStore.append(LogEntry(
            kind: kind,
            detail: detail,
            peerDisplayNames: peers.map { $0.displayName },
            direction: direction
        ))
        refreshUI()
    }

    func handlePeerConnectionEvent(_ event: PeerConnectionEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.handleEventOnMain(event)
        }
    }

    func handleEventOnMain(_ event: PeerConnectionEvent) {
        switch event {
        case .ready:
            appendLog(kind: "session.ready", detail: "Manager ready")
        case .started:
            print("PeerConnectivityDemo started networking")
            appendLog(kind: "session.started", detail: mode.rawValue)
        case .ended:
            appendLog(kind: "session.ended", detail: "Manager stopped")
        case .devicesChanged(let peer, let peers):
            print("PeerConnectivityDemo devices changed: \(peer.displayName) \(peer.status) connected: \(peers.map { $0.displayName })")
            connectedPeers = peers
            if !peers.isEmpty { checkedItems.insert(.peerConnected) }
            appendLog(kind: "peers.connected.changed", detail: "Changed: \(peer.displayName) [\(statusText(peer.status))]", peers: peers)
        case .foundPeer(let peer):
            print("PeerConnectivityDemo found peer: \(peer.displayName)")
            checkedItems.insert(.peerDiscovered)
            appendLog(kind: "peer.found", detail: peer.displayName, peers: [peer])
        case .foundPeerWithDiscoveryInfo(let peer, let discoveryInfo):
            checkedItems.insert(.peerDiscovered)
            appendLog(kind: "peer.found.metadata", detail: "\(peer.displayName): \(discoveryInfo ?? [:])", peers: [peer])
        case .lostPeer(let peer):
            appendLog(kind: "peer.lost", detail: peer.displayName, peers: [peer])
        case .nearbyPeersChanged(let peers):
            if selectedConnectionBehavior == .automatic {
                discoveredPeers = peers
            }
            if !peers.isEmpty { checkedItems.insert(.peerDiscovered) }
            appendLog(kind: "peers.nearby.changed", detail: "\(peers.count) nearby", peers: peers)
        case .receivedData(let peer, let data):
            appendLog(kind: "data.received", detail: "\(data.count) bytes", peers: [peer], direction: .inbound)
        case .receivedEvent(let peer, let eventInfo):
            appendLog(kind: "legacy.event.received", detail: "Keys: \(eventInfo.keys.sorted().joined(separator: ", "))", peers: [peer], direction: .inbound)
        case .receivedMessage(let peer, let messageType, let data):
            appendLog(kind: "message.envelope.received", detail: "\(messageType), \(data.count) bytes", peers: [peer], direction: .inbound)
        case .receivedStream(let peer, _, let name):
            appendLog(kind: "stream.received", detail: name, peers: [peer], direction: .inbound)
        case .startedReceivingResource(let peer, let name, _):
            appendLog(kind: "resource.started", detail: name, peers: [peer], direction: .inbound)
        case .finishedReceivingResource(let peer, let name, let url, let error):
            let detail = error?.localizedDescription ?? url?.lastPathComponent ?? "Finished \(name)"
            appendLog(kind: "resource.finished", detail: detail, peers: [peer], direction: .inbound)
        case .receivedCertificate(let peer, _, _):
            checkedItems.insert(.localNetworkPermission)
            appendLog(kind: "certificate.received", detail: "Certificate received; framework default handler accepts it", peers: [peer], direction: .inbound)
        case .receivedInvitation(let peer, _, let invitationHandler):
            switch pcm.connectionType {
            case .automatic:
                appendLog(kind: "invitation.received", detail: "Framework automatic mode handles invitation from \(peer.displayName)", peers: [peer], direction: .inbound)
            case .inviteOnly, .custom:
                appendLog(kind: "invitation.received", detail: "Accepted invitation from \(peer.displayName)", peers: [peer], direction: .inbound)
                invitationHandler(true)
            }
        case .error(let error):
            appendLog(kind: "error", detail: error.localizedDescription)
        }
        refreshUI()
    }

    func updateModeMenu() {
        modeButton.configuration?.title = "Mode: \(mode.rawValue) ▾"
        modeButton.menu = UIMenu(title: "Connection Mode", children: [
            modeAction(.advertisingAndBrowsing),
            modeAction(.advertisingOnly),
            modeAction(.browsingOnly),
        ])
    }

    func modeAction(_ connectionMode: ConnectionMode) -> UIAction {
        let state : UIMenuElement.State = mode == connectionMode ? .on : .off
        return UIAction(title: connectionMode.rawValue, state: state) { [weak self] _ in
            self?.changeMode(to: connectionMode)
        }
    }

    func changeMode(to connectionMode: ConnectionMode) {
        guard mode != connectionMode else { return }
        mode = connectionMode
        appendLog(kind: "session.mode.changed", detail: mode.rawValue)
        if isNetworking {
            pcm.stop()
            discoveredPeers = []
            connectedPeers = []
            selectedTargetPeer = nil
            startNetworking()
        }
        refreshUI()
    }

    func rebuildInviteButtons() {
        inviteButtonsStack.arrangedSubviews.forEach { view in
            inviteButtonsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        inviteButtonsStack.isHidden = selectedConnectionBehavior != .requireInvitation
        guard selectedConnectionBehavior == .requireInvitation else { return }

        if discoveredPeers.isEmpty {
            let label = UILabel()
            label.text = "Start browsing to discover peers available for manual invitation."
            label.numberOfLines = 0
            label.font = UIFont.preferredFont(forTextStyle: .footnote)
            label.textColor = .secondaryLabel
            inviteButtonsStack.addArrangedSubview(label)
            return
        }

        discoveredPeers.forEach { peer in
            let button = UIButton(type: .system)
            configureSecondaryButton(button, title: "Invite \(peer.displayName) — \(statusText(peer.status))")
            button.contentHorizontalAlignment = .leading
            button.isEnabled = isNetworking && peer.status == .notConnected
            button.accessibilityLabel = "Invite \(peer.displayName)"
            button.accessibilityHint = button.isEnabled
                ? "Sends an explicit \(backendName) invitation"
                : "This peer is not currently available for invitation"
            button.addAction(UIAction { [weak self] _ in
                self?.invite(peer)
            }, for: .touchUpInside)
            inviteButtonsStack.addArrangedSubview(button)
        }
    }

    func invite(_ peer: Peer) {
        guard isNetworking, selectedConnectionBehavior == .requireInvitation, peer.status == .notConnected else { return }
        browserModel.invitePeer(peer)
        appendLog(kind: "invitation.sent", detail: "Invited \(peer.displayName)", peers: [peer], direction: .outbound)
    }

    func updateTargetMenu() {
        targetButton.configuration?.title = "Target: \(targetSummary()) ▾"
        let broadcastState : UIMenuElement.State = selectedTargetPeer == nil ? .on : .off
        var actions : [UIMenuElement] = [
            UIAction(title: "Broadcast", state: broadcastState) { [weak self] _ in
                self?.selectedTargetPeer = nil
                self?.refreshUI()
            },
        ]
        actions += connectedPeers.map { peer in
            let state : UIMenuElement.State = selectedTargetPeer == peer ? .on : .off
            return UIAction(title: peer.displayName, state: state) { [weak self] _ in
                self?.selectedTargetPeer = peer
                self?.refreshUI()
            }
        }
        targetButton.menu = UIMenu(title: "Message Target", children: actions)
        targetButton.isEnabled = !connectedPeers.isEmpty
    }

    func updateLogFilterMenu() {
        logFilterButton.configuration?.title = "Log Filters: \(activeLogCategories.count)/\(LogCategory.allCases.count) ▾"
        let allState : UIMenuElement.State = activeLogCategories.count == LogCategory.allCases.count ? .on : .off
        var actions : [UIMenuElement] = [
            UIAction(title: "Show All", state: allState) { [weak self] _ in
                self?.activeLogCategories = Set(LogCategory.allCases)
                self?.refreshUI()
            },
        ]
        actions += LogCategory.allCases.map { category in
            let state : UIMenuElement.State = activeLogCategories.contains(category) ? .on : .off
            return UIAction(title: category.rawValue, state: state) { [weak self] _ in
                guard let self = self else { return }
                if self.activeLogCategories.contains(category) {
                    self.activeLogCategories.remove(category)
                } else {
                    self.activeLogCategories.insert(category)
                }
                self.refreshUI()
            }
        }
        logFilterButton.menu = UIMenu(title: "Visible Log Categories", children: actions)
    }

    func rebuildChecklist() {
        checklistStack.arrangedSubviews.forEach { view in
            checklistStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        DemoChecklistItem.allCases.forEach { item in
            let button = UIButton(type: .system)
            button.contentHorizontalAlignment = .leading
            button.setTitle("\(checkedItems.contains(item) ? "☑" : "☐") \(item.title)", for: .normal)
            button.addAction(UIAction { [weak self] _ in
                self?.toggleChecklistItem(item)
            }, for: .touchUpInside)
            checklistStack.addArrangedSubview(button)
        }
    }

    func toggleChecklistItem(_ item: DemoChecklistItem) {
        if checkedItems.contains(item) {
            checkedItems.remove(item)
        } else {
            checkedItems.insert(item)
        }
        refreshUI()
    }

    func resetDemo() {
        pcm.stop()
        isNetworking = false
        discoveredPeers = []
        connectedPeers = []
        selectedTargetPeer = nil
        activeLogCategories = Set(LogCategory.allCases)
        messageHistory = []
        checkedItems = []
        messageTextField.text = ""
        logStore.clear()
        appendLog(kind: "demo.reset", detail: "Demo reset; local peer: \(pcm.peer.displayName)")
        appendLog(kind: "app.ready", detail: "Local peer: \(pcm.peer.displayName)")
    }

    @objc func changedBackend(_ sender: UISegmentedControl) {
        guard !isNetworking else { return }
        discoveredPeers = []
        connectedPeers = []
        selectedTargetPeer = nil
        configureManager()
        appendLog(kind: "session.backend.changed", detail: "\(backendName), \(selectedConnectionBehavior.rawValue)")
    }

    @objc func changedConnectionBehavior(_ sender: UISegmentedControl) {
        guard !isNetworking else { return }
        selectedConnectionBehavior = sender.selectedSegmentIndex == 0 ? .automatic : .requireInvitation
        discoveredPeers = []
        connectedPeers = []
        selectedTargetPeer = nil
        configureManager()
        appendLog(kind: "session.connection.behavior.changed", detail: "\(backendName), \(selectedConnectionBehavior.rawValue)")
    }

    @objc func tappedStartStop(_ sender: UIButton) {
        isNetworking ? stopNetworking() : startNetworking()
    }

    @objc func tappedRefresh(_ sender: UIButton) {
        pcm.refresh()
        appendLog(kind: "session.refresh.requested", detail: mode.rawValue)
    }

    @objc func tappedReset(_ sender: UIButton) {
        resetDemo()
    }

    @objc func tappedSend(_ sender: UIButton) {
        sendMessage()
    }

    @objc func tappedRawData(_ sender: UIButton) {
        sendRawDataPing()
    }

    @objc func tappedResource(_ sender: UIButton) {
        sendDemoResource()
    }

    @objc func tappedCopyLogs(_ sender: UIButton) {
        UIPasteboard.general.string = logStore.shareText()
        checkedItems.insert(.logsExported)
        appendLog(kind: "log.copied", detail: "Copied full log export to pasteboard")
    }

    @objc func tappedShare(_ sender: UIButton) {
        checkedItems.insert(.logsExported)
        appendLog(kind: "log.share.requested", detail: "Sharing full unfiltered log export")
        let activity = UIActivityViewController(activityItems: [logStore.shareText()], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        present(activity, animated: true)
    }

    @objc func tappedClearLog(_ sender: UIButton) {
        logStore.clear()
        appendLog(kind: "log.cleared", detail: "Cleared by user")
    }
}
