//
//  PeerSecurityConfiguration.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 6/3/26.
//  Copyright © 2026 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

/**
 Policy used to decide whether a peer certificate should be accepted during session establishment.

 Certificate data is supplied by MultipeerConnectivity and should be treated as unauthenticated until
 your policy validates it. The default `.acceptAll` policy preserves PeerConnectivity's historical
 behavior.
 */
public enum PeerCertificatePolicy {
    /**
     Accept every peer certificate, including missing certificates.

     This preserves PeerConnectivity's historical behavior and is convenient for local discovery, but
     it does not authenticate peers.
     */
    case acceptAll
    /**
     Reject every peer certificate.
     */
    case rejectAll
    /**
     Accept only peers that provide a non-empty certificate chain.
     */
    case requireCertificate
    /**
     Delegate certificate handling to caller-provided logic.

     The custom handler must call the supplied completion exactly once with the acceptance decision.

     - parameter peer: The peer presenting the certificate.
     - parameter certificate: The certificate chain supplied by MultipeerConnectivity.
     - parameter handler: Completion that accepts or rejects the certificate.
     */
    case custom((Peer, [Any]?, @escaping (Bool) -> Void) -> Void)
}

/**
 Policy used to decide whether incoming invitations should be accepted.

 Invitation context is received before session establishment and should be treated as
 public, unauthenticated metadata. Do not include raw secrets in invitation context.
 */
public enum PeerInvitationPolicy {
    /**
     Surface invitations through `.receivedInvitation` for caller-managed decisions.
     */
    case manual
    /**
     Accept every incoming invitation.

     This preserves PeerConnectivity's historical `.automatic` behavior.
     */
    case acceptAll
    /**
     Reject every incoming invitation.
     */
    case rejectAll
    /**
     Delegate invitation decisions to caller-provided logic.

     - parameter peer: The peer sending the invitation.
     - parameter context: Optional invitation context supplied by the inviting peer.
     */
    case custom((Peer, Data?) -> Bool)
}

/**
 Security settings used when creating the underlying `MCSession`.

 The default configuration intentionally preserves the library's previous behavior:
 optional encryption, no local security identity, and accepting all peer certificates.
 For stronger transport protection, use `.encrypted` or provide a custom configuration.
 */
public struct PeerSecurityConfiguration {
    /**
     Encryption preference passed to `MCSession`.
     */
    public var encryptionPreference : MCEncryptionPreference
    /**
     Optional identity passed to `MCSession`.
     */
    public var securityIdentity : [Any]?
    /**
     Certificate policy applied when `MCSessionDelegate` receives a peer certificate.
     */
    public var certificatePolicy : PeerCertificatePolicy

    /**
     Creates a security configuration.

     - parameter encryptionPreference: Encryption preference passed to `MCSession`.
     - parameter securityIdentity: Optional identity passed to `MCSession`.
     - parameter certificatePolicy: Policy applied to incoming peer certificates.
     */
    public init(encryptionPreference: MCEncryptionPreference,
                securityIdentity: [Any]?,
                certificatePolicy: PeerCertificatePolicy) {
        self.encryptionPreference = encryptionPreference
        self.securityIdentity = securityIdentity
        self.certificatePolicy = certificatePolicy
    }

    /**
     Backward-compatible default configuration.
     */
    public static let `default` = PeerSecurityConfiguration(
        encryptionPreference: .optional,
        securityIdentity: nil,
        certificatePolicy: .acceptAll
    )

    /**
     Convenience configuration requiring encrypted sessions while preserving certificate behavior.
     */
    public static let encrypted = PeerSecurityConfiguration(
        encryptionPreference: .required,
        securityIdentity: nil,
        certificatePolicy: .acceptAll
    )
}
