//
//  PeerNetworkPSKConfiguration.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 8/10/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
#if PEER_CONNECTIVITY_DEMO
import PeerConnectivity
#endif

internal enum PeerNetworkPSKConfiguration {
    /// Maps validated input to TLS-PSK and fails closed for every invalid value.
    internal static func networkSecurity(_ value: String) -> Result<PeerConnectionNetworkSecurity, PeerNetworkPSKBase64Error> {
        return PeerNetworkPSKBase64.decode(value).map(PeerConnectionNetworkSecurity.preSharedKey)
    }
}
