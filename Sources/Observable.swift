//
//  Observable.swift
//  PeerConnectivity
//
//  Created by Reid Chatham on 12/21/15.
//  Copyright © 2015 Reid Chatham. All rights reserved.
//

import Foundation

/// Limits only the separately opted-in updates, not the legacy operation stream.
fileprivate final class BoundedPermits: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity : Int
    private var inUse = 0
    private var closed = false
    private var waiters : [(UUID, CheckedContinuation<Bool, Never>)] = []

    init(capacity: Int) {
        self.capacity = capacity
    }

    var counts : (admitted: Int, waiting: Int) {
        lock.lock()
        let counts = (inUse, waiters.count)
        lock.unlock()
        return counts
    }

    func acquire() async -> Bool {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if closed || Task.isCancelled {
                    lock.unlock()
                    continuation.resume(returning: false)
                } else if inUse < capacity && waiters.isEmpty {
                    inUse += 1
                    lock.unlock()
                    continuation.resume(returning: true)
                } else {
                    waiters.append((id, continuation))
                    lock.unlock()
                }
            }
        } onCancel: {
            cancel(id)
        }
    }

    /// Serializes the bounded stream admission decision with close().
    /// No observer or completion handler runs synchronously from yield().
    func enqueueIfOpen(_ enqueue: () -> Bool) -> Bool {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return false
        }
        let accepted = enqueue()
        lock.unlock()
        return accepted
    }

    func release() {
        lock.lock()
        if !closed && !waiters.isEmpty {
            let waiter = waiters.removeFirst().1
            lock.unlock()
            waiter.resume(returning: true) // Transfer the reserved permit.
        } else {
            inUse -= 1
            lock.unlock()
        }
    }

    @discardableResult
    func close() -> Bool {
        lock.lock()
        let wasOpen = !closed
        closed = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        for (_, waiter) in pending {
            waiter.resume(returning: false)
        }
        return wasOpen
    }

    private func cancel(_ id: UUID) {
        lock.lock()
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else {
            lock.unlock()
            return
        }
        let waiter = waiters.remove(at: index).1
        lock.unlock()
        waiter.resume(returning: false)
    }
}

/// Completes dropped operations as failure and releases their reserved permit.
fileprivate final class BoundedSubmission {
    private let permits : BoundedPermits
    private var result : CheckedContinuation<Bool, Never>?

    init(_ result: CheckedContinuation<Bool, Never>, permits: BoundedPermits) {
        self.result = result
        self.permits = permits
    }

    func complete(_ processed: Bool) {
        guard let result = result else { return }
        self.result = nil
        permits.release()
        result.resume(returning: processed)
    }

    deinit {
        complete(false)
    }
}

internal actor Observable<T> {
    internal typealias Observer = (T) -> Void

    fileprivate enum Operation {
        case addObserver(Observer, key: String, replayCurrentValue: Bool, completion: CheckedContinuation<Void, Never>?)
        case removeObserver(key: String, completion: CheckedContinuation<Void, Never>?)
        case removeAllObservers(completion: CheckedContinuation<Void, Never>?)
        case update(T, completion: CheckedContinuation<Void, Never>?)
        case boundedUpdate(T, BoundedSubmission)
        case barrier(CheckedContinuation<Void, Never>)
    }

    internal private(set) var value : T {
        didSet {
            observers.values.forEach { observer in
                observer(value)
            }
        }
    }

    fileprivate var observers : [String:Observer] = [:]
    nonisolated fileprivate let operationContinuation : AsyncStream<Operation>.Continuation
    nonisolated fileprivate let boundedPermits : BoundedPermits
    nonisolated fileprivate let beforeBoundedEnqueue : (@Sendable () -> Void)?
    nonisolated fileprivate let afterBoundedClose : (@Sendable () -> Void)?
    nonisolated(unsafe) fileprivate var eventPump : Task<Void, Never>?

    internal var observerCount : Int {
        return observers.count
    }

    /// Number of reserved opt-in slots (including an update currently being processed).
    nonisolated internal var boundedSubmissionCounts : (admitted: Int, waiting: Int) {
        return boundedPermits.counts
    }

    internal init(
        _ v: T,
        boundedCapacity: Int = 16,
        beforeBoundedEnqueue: (@Sendable () -> Void)? = nil,
        afterBoundedClose: (@Sendable () -> Void)? = nil
    ) {
        precondition(boundedCapacity > 0, "Bounded Observable capacity must be positive")
        let (operations, continuation) = AsyncStream.makeStream(of: Operation.self)

        value = v
        operationContinuation = continuation
        boundedPermits = BoundedPermits(capacity: boundedCapacity)
        self.beforeBoundedEnqueue = beforeBoundedEnqueue
        self.afterBoundedClose = afterBoundedClose
        eventPump = nil
        eventPump = Task { [weak self] in
            for await operation in operations {
                guard let self = self else { break }
                await self.perform(operation)
            }
        }
    }

    deinit {
        finish()
        eventPump?.cancel()
    }

    /// Atomically closes bounded admission and lets the pump drain without waiting for it.
    /// Call explicitly to wake suspended producers; their tasks can retain the Observable until they finish.
    nonisolated internal func finish() {
        let didClose = boundedPermits.close()
        // Internal test seam; the gate lock is released before this callback.
        if didClose { afterBoundedClose?() }
        operationContinuation.finish()
    }

    /// Closes submissions and waits for the event pump to process all buffered operations.
    /// Unlike flush(), this remains a drain barrier after finish().
    /// Do not await this from an observer callback running on the event pump.
    nonisolated internal func finishAndWait() async {
        finish()
        await eventPump?.value
    }

    /// Schedules observer registration from synchronous callers.
    ///
    /// Synchronous submissions enter the actor's operation stream so observer
    /// lifecycle changes and updates are applied in call order without blocking.
    @discardableResult
    nonisolated internal func addObserver(
        _ observer: @escaping Observer,
        replayCurrentValue: Bool = true
    ) -> String {
        let key = UUID().uuidString
        addObserver(observer, key: key, replayCurrentValue: replayCurrentValue)
        return key
    }

    nonisolated internal func addObserver(
        _ observer: @escaping Observer,
        key: String,
        replayCurrentValue: Bool = true
    ) {
        operationContinuation.yield(.addObserver(
            observer,
            key: key,
            replayCurrentValue: replayCurrentValue,
            completion: nil
        ))
    }

    nonisolated internal func removeObserver(forKey key: String) {
        operationContinuation.yield(.removeObserver(key: key, completion: nil))
    }

    nonisolated internal func removeAllObservers() {
        operationContinuation.yield(.removeAllObservers(completion: nil))
    }

    nonisolated internal func update(_ newValue: T) {
        operationContinuation.yield(.update(newValue, completion: nil))
    }

    @discardableResult
    nonisolated internal func addObserverAsync(
        _ observer: @escaping Observer,
        replayCurrentValue: Bool = true
    ) async -> String {
        let key = UUID().uuidString
        await addObserverAsync(observer, key: key, replayCurrentValue: replayCurrentValue)
        return key
    }

    nonisolated internal func addObserverAsync(
        _ observer: @escaping Observer,
        key: String,
        replayCurrentValue: Bool = true
    ) async {
        await enqueueAndWait { completion in
            .addObserver(
                observer,
                key: key,
                replayCurrentValue: replayCurrentValue,
                completion: completion
            )
        }
    }

    nonisolated internal func removeObserverAsync(forKey key: String) async {
        await enqueueAndWait { completion in
            .removeObserver(key: key, completion: completion)
        }
    }

    nonisolated internal func removeAllObserversAsync() async {
        await enqueueAndWait { completion in
            .removeAllObservers(completion: completion)
        }
    }

    nonisolated internal func updateAsync(_ newValue: T) async {
        await enqueueAndWait { completion in
            .update(newValue, completion: completion)
        }
    }

    /// Opt-in backpressure for updates. Returns true only after the update and its observers run.
    /// Cancellation observed before stream enqueue returns false; enqueued updates still run if cancelled.
    nonisolated internal func updateBoundedAsync(_ newValue: T) async -> Bool {
        return await Self.submitBounded(
            newValue, to: operationContinuation, using: boundedPermits, beforeEnqueue: beforeBoundedEnqueue
        )
    }

    nonisolated private static func submitBounded(
        _ newValue: T,
        to continuation: AsyncStream<Operation>.Continuation,
        using permits: BoundedPermits,
        beforeEnqueue: (@Sendable () -> Void)?
    ) async -> Bool {
        guard await permits.acquire() else { return false }
        // Internal test seam; always runs outside the permit lock.
        beforeEnqueue?()
        if Task.isCancelled {
            permits.release()
            return false
        }
        return await withCheckedContinuation { result in
            let submission = BoundedSubmission(result, permits: permits)
            let accepted = permits.enqueueIfOpen {
                switch continuation.yield(.boundedUpdate(newValue, submission)) {
                case .enqueued:
                    return true
                case .dropped, .terminated:
                    return false
                @unknown default:
                    return false
                }
            }
            if !accepted {
                submission.complete(false)
            }
        }
    }

    /// Waits for earlier operations only while the stream is open; after finish(), yield terminates immediately.
    nonisolated internal func flush() async {
        await enqueueAndWait { completion in
            .barrier(completion)
        }
    }

    nonisolated fileprivate func enqueueAndWait(
        _ makeOperation: (CheckedContinuation<Void, Never>) -> Operation
    ) async {
        await withCheckedContinuation { completion in
            switch operationContinuation.yield(makeOperation(completion)) {
            case .enqueued:
                break
            case .dropped, .terminated:
                completion.resume()
            @unknown default:
                completion.resume()
            }
        }
    }

    fileprivate func perform(_ operation: Operation) {
        switch operation {
        case let .addObserver(observer, key, replayCurrentValue, completion):
            storeObserver(observer, key: key, replayCurrentValue: replayCurrentValue)
            completion?.resume()
        case let .removeObserver(key, completion):
            removeStoredObserver(forKey: key)
            completion?.resume()
        case let .removeAllObservers(completion):
            removeStoredObservers()
            completion?.resume()
        case let .update(newValue, completion):
            setValue(newValue)
            completion?.resume()
        case let .boundedUpdate(newValue, submission):
            setValue(newValue)
            submission.complete(true)
        case let .barrier(completion):
            completion.resume()
        }
    }

    fileprivate func storeObserver(
        _ observer: @escaping Observer,
        key: String,
        replayCurrentValue: Bool
    ) {
        observers[key] = observer
        if replayCurrentValue {
            observer(value)
        }
    }

    fileprivate func removeStoredObserver(forKey key: String) {
        observers.removeValue(forKey: key)
    }

    fileprivate func removeStoredObservers() {
        observers.removeAll()
    }

    fileprivate func setValue(_ newValue: T) {
        value = newValue
    }
}
