//
//  PeerAdvertiserAssisstant.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal enum PeerAdvertiserAssisstantEvent {
    case none
    case didDissmissInvitation
    case willPresentInvitation
}

internal class PeerAdvertiserAssisstantEventProducer: NSObject {
    
    fileprivate let observer : Observable<PeerAdvertiserAssisstantEvent>
    
    internal init(observer: Observable<PeerAdvertiserAssisstantEvent>) {
        self.observer = observer
    }
}

extension PeerAdvertiserAssisstantEventProducer: MCAdvertiserAssistantDelegate {

    internal func advertiserAssistantDidDismissInvitation(_ advertiserAssistant: MCAdvertiserAssistant) {
        
        let event: PeerAdvertiserAssisstantEvent = .didDissmissInvitation
        self.observer.value = event
    }
    
    internal func advertiserAssistantWillPresentInvitation(_ advertiserAssistant: MCAdvertiserAssistant) {
        
        let event: PeerAdvertiserAssisstantEvent = .willPresentInvitation
        self.observer.value = event
    }
}
