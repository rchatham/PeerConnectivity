//
//  DemoChecklistItem.swift
//  PeerConnectivityDemo
//
//  Created by Reid Chatham on 9/15/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import Foundation

internal enum DemoChecklistItem : String, CaseIterable {
    case localNetworkPermission
    case deviceAAdvertising
    case deviceBBrowsing
    case peerDiscovered
    case peerConnected
    case messageSent
    case messageReceived
    case logsExported
    case screenshotCaptured

    internal var title : String {
        switch self {
        case .localNetworkPermission: return "Local Network permission observed"
        case .deviceAAdvertising: return "Device A started advertising"
        case .deviceBBrowsing: return "Device B started browsing"
        case .peerDiscovered: return "Peer discovered"
        case .peerConnected: return "Peer connected"
        case .messageSent: return "Message A → B sent"
        case .messageReceived: return "Message B → A received"
        case .logsExported: return "Logs exported"
        case .screenshotCaptured: return "Screenshot/recording captured"
        }
    }
}
