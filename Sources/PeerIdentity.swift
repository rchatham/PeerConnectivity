//
//  PeerIdentity.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

internal struct PeerIdentity : Codable, Hashable {

    internal let identifier : String
    internal let displayName : String

    internal init(identifier: String, displayName: String) {
        self.identifier = identifier
        self.displayName = displayName
    }
}
