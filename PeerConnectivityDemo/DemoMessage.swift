//
//  DemoMessage.swift
//  PeerConnectivityDemo
//
//  Created by Reid Chatham on 9/15/16.
//  Copyright © 2016 Reid Chatham. All rights reserved.
//

import Foundation
import PeerConnectivity

internal struct DemoMessage : PeerMessage {
    internal static let messageType = "demo.text"

    internal let text : String
    internal let sentAt : Date
    internal let senderDisplayName : String

    internal init(text: String, sentAt: Date = Date(), senderDisplayName: String) {
        self.text = text
        self.sentAt = sentAt
        self.senderDisplayName = senderDisplayName
    }
}
