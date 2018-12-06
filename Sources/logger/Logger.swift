//
//  Logger.swift
//  PeerConnectivity
//
//  Created by Julien Di Marco on 03/12/2018.
//

import Foundation

import Logger
import XCGLogger

// MARK: - PeerConnectivity LoggerDomain Extension -

public extension LoggerDomain {

    // MARK: - Domains

    public static let peerConnectivity = LoggerDomain(identifier: "com.peer-connectivity")

    // MARK: - Destinations

    public var consoleDestination: DestinationProtocol? {
        let destinationIdentifier = [rawValue, "consoleDestination"].joined(separator: ".")
        let consoleDestination = ConsoleDestination(identifier: destinationIdentifier)

        consoleDestination.showLogIdentifier = true
        consoleDestination.showFileName = false
        consoleDestination.showFunctionName = false
        consoleDestination.showLineNumber = false

        return consoleDestination
    }

}

// MARK: - PeerConnectivty Loggers Static Definitions -

/// Framework Main logger, other logger inherit from it's domain and set as container
public let logger: Logger = {
    let logger = Logger(identifier: LoggerDomain.peerConnectivity.rawValue, container: nil)

    logger.add(destination: LoggerDomain.peerConnectivity.fileDestination)
    logger.add(destination: LoggerDomain.peerConnectivity.consoleDestination)

    return logger
}()
