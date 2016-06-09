//
//  PeerAdvertiserAssisstant.swift
//  GameController
//
//  Created by Reid Chatham on 12/23/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation
import MultipeerConnectivity

internal enum PeerAdvertiserAssisstantEvent {
    case None
    case DidDissmissInvitation
    case WillPresentInvitation
}

internal class PeerAdvertiserAssisstantEventProducer: NSObject {
    
    private let observer : Observable<PeerAdvertiserAssisstantEvent>
    
    internal init(observer: Observable<PeerAdvertiserAssisstantEvent>) {
        self.observer = observer
    }
}

extension PeerAdvertiserAssisstantEventProducer: MCAdvertiserAssistantDelegate {

    internal func advertiserAssistantDidDismissInvitation(advertiserAssistant: MCAdvertiserAssistant) {
        
        let event: PeerAdvertiserAssisstantEvent = .DidDissmissInvitation
        self.observer.value = event
    }
    
    internal func advertiserAssistantWillPresentInvitation(advertiserAssistant: MCAdvertiserAssistant) {
        
        let event: PeerAdvertiserAssisstantEvent = .WillPresentInvitation
        self.observer.value = event
    }
}
