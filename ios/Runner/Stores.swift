import Foundation
import SwiftData
import LibSignalClient

/// Simple StoreContext implementation
@available(iOS 17.0, *)
struct SimpleStoreContext: StoreContext {}

// MARK: - Identity Key Store
@available(iOS 17.0, *)
class SekretessIdentityKeyStore: IdentityKeyStore {
    private let identityKeyRepository: IdentityKeyRepository
    private let registrationRepository: RegistrationRepository
    
    init(identityKeyRepository: IdentityKeyRepository, registrationRepository: RegistrationRepository) {
        self.identityKeyRepository = identityKeyRepository
        self.registrationRepository = registrationRepository
    }
    
    func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair {
        if let keyPair = identityKeyRepository.getIdentityKeyPair() {
            return keyPair
        }
        // Generate new identity key pair if none exists
        let newKeyPair = IdentityKeyPair.generate()
        identityKeyRepository.storeIdentityKeyPair(newKeyPair)
        return newKeyPair
    }
    
    func localRegistrationId(context: StoreContext) throws -> UInt32 {
        if let id = registrationRepository.getRegistrationId() {
            return id
        }
        // Generate new registration ID if none exists or if existing one is invalid
        // Registration ID must be between 1 and 255
        let newId = UInt32.random(in: 1...255)
        registrationRepository.storeRegistrationId(newId)
        return newId
    }
    
    func getIdentityKeyPair() -> IdentityKeyPair {
        return try! identityKeyPair(context: SimpleStoreContext())
    }
    
    func getLocalRegistrationId() -> UInt32 {
        return try! localRegistrationId(context: SimpleStoreContext())
    }
    
    func registrationRequired() -> Bool {
        return identityKeyRepository.getIdentityKeyPair() == nil
    }
    
    func saveIdentity(_ identity: IdentityKey, for address: ProtocolAddress, context: StoreContext) throws -> IdentityChange {
        return identityKeyRepository.saveIdentity(
            deviceId: Int32(address.deviceId),
            name: address.name,
            identityKey: identity
        )
    }
    
    func isTrustedIdentity(_ identity: IdentityKey, for address: ProtocolAddress, direction: Direction, context: StoreContext) throws -> Bool {
        if direction == .receiving {
            return true
        } else {
            if let trustedIdentity = getIdentity(address) {
                // Compare identity keys
                do {
                    let trustedData = try trustedIdentity.serialize()
                    let newData = try identity.serialize()
                    return trustedData == newData
                } catch {
                    return false
                }
            }
            return true // Trust if no existing identity
        }
    }
    
    func identity(for address: ProtocolAddress, context: StoreContext) throws -> IdentityKey? {
        return identityKeyRepository.getIdentity(
            deviceId: Int32(address.deviceId),
            name: address.name
        )
    }
    
    func saveIdentity(_ address: ProtocolAddress, _ identity: IdentityKey) -> IdentityChange {
        return try! saveIdentity(identity, for: address, context: SimpleStoreContext())
    }
    
    func isTrustedIdentity(_ address: ProtocolAddress, _ identity: IdentityKey, _ direction: Direction) -> Bool {
        return try! isTrustedIdentity(identity, for: address, direction: direction, context: SimpleStoreContext())
    }
    
    func getIdentity(_ address: ProtocolAddress) -> IdentityKey? {
        return try! identity(for: address, context: SimpleStoreContext())
    }
    
    func clearStorage() {
        identityKeyRepository.clearStorage()
        registrationRepository.storeRegistrationId(0)
    }
}

// MARK: - Pre Key Store
@available(iOS 17.0, *)
class SekretessPreKeyStore: PreKeyStore {
    private let preKeyRepository: PreKeyRepository
    
    init(preKeyRepository: PreKeyRepository) {
        self.preKeyRepository = preKeyRepository
    }
    
    func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
        guard let record = preKeyRepository.getPreKey(id: id) else {
            throw SignalProtocolError.invalidKeyId
        }
        return record
    }
    
    func storePreKey(_ record: PreKeyRecord, id: UInt32, context: StoreContext) throws {
        preKeyRepository.storePreKey(id, record)
    }
    
    func removePreKey(id: UInt32, context: StoreContext) throws {
        preKeyRepository.removePreKey(id)
    }
    
    func loadPreKey(id: UInt32) throws -> PreKeyRecord {
        return try loadPreKey(id: id, context: SimpleStoreContext())
    }
    
    func storePreKey(_ id: UInt32, _ record: PreKeyRecord) {
        try! storePreKey(record, id: id, context: SimpleStoreContext())
    }
    
    func removePreKey(_ id: UInt32) {
        try! removePreKey(id: id, context: SimpleStoreContext())
    }
    
    func containsPreKey(_ id: UInt32) -> Bool {
        return preKeyRepository.getPreKey(id: id) != nil
    }
    
    func count() -> Int {
        return preKeyRepository.count()
    }
    
    func clearStorage() {
        preKeyRepository.clearStorage()
    }
}

// MARK: - Signed Pre Key Store
@available(iOS 17.0, *)
class SekretessSignedPreKeyStore: SignedPreKeyStore {
    private let preKeyRepository: PreKeyRepository
    private let signedPreKeyRepository: SignedPreKeyRepository
    
    init(preKeyRepository: PreKeyRepository, signedPreKeyRepository: SignedPreKeyRepository) {
        self.preKeyRepository = preKeyRepository
        self.signedPreKeyRepository = signedPreKeyRepository
    }
    
    func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
        guard let record = signedPreKeyRepository.getSignedPreKey(id: id) else {
            throw SignalProtocolError.invalidKeyId
        }
        return record
    }
    
    func storeSignedPreKey(_ record: SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
        signedPreKeyRepository.storeSignedPreKey(id, record)
    }
    
    func loadSignedPreKey(id: UInt32) throws -> SignedPreKeyRecord {
        return try loadSignedPreKey(id: id, context: SimpleStoreContext())
    }
    
    func storeSignedPreKey(_ id: UInt32, _ record: SignedPreKeyRecord) {
        try! storeSignedPreKey(record, id: id, context: SimpleStoreContext())
    }
        
    func removeSignedPreKey(_ id: UInt32) {
        signedPreKeyRepository.removeSignedPreKey(id)
    }
    
    func loadSignedPreKeys() -> [SignedPreKeyRecord] {
        let context = signedPreKeyRepository.database.viewContext
        let descriptor = FetchDescriptor<SignedPreKeyRecordEntity>()
        
        do {
            let entities: [SignedPreKeyRecordEntity] = try context.fetch(descriptor)
            return entities.compactMap { entity in
                guard let keyData = Data(base64Encoded: entity.spkRecord) else {
                    return nil
                }
                do {
                    return try SignedPreKeyRecord(bytes: keyData)
                } catch {
                    print("Error deserializing signed pre key: \(error)")
                    return nil
                }
            }
        } catch {
            print("Error loading signed pre keys: \(error)")
            return []
        }
    }
    
    func containsSignedPreKey(_ id: UInt32) -> Bool {
        return signedPreKeyRepository.getSignedPreKey(id: id) != nil
    }
    
    func clearStorage() {
        preKeyRepository.clearStorage()
        // Clear signed prekeys - remove all
        let context = signedPreKeyRepository.database.viewContext
        let descriptor = FetchDescriptor<SignedPreKeyRecordEntity>()
        
        do {
            let results: [SignedPreKeyRecordEntity] = try context.fetch(descriptor)
            for entity in results {
                context.delete(entity)
            }
            try context.save()
        } catch {
            print("Error clearing signed prekey storage: \(error)")
        }
    }
}

// MARK: - Kyber Pre Key Store
@available(iOS 17.0, *)
class SekretessKyberPreKeyStore: KyberPreKeyStore {
    private let kyberPreKeyRepository: KyberPreKeyRepository
    
    init(kyberPreKeyRepository: KyberPreKeyRepository) {
        self.kyberPreKeyRepository = kyberPreKeyRepository
    }
    
    func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
        guard let record = kyberPreKeyRepository.getKyberPreKey(id: id) else {
            throw SignalProtocolError.invalidKeyId
        }
        return record
    }
    
    func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
        kyberPreKeyRepository.storeKyberPreKey(id, record)
    }
    
    // libsignal 0.86 added signedPreKeyId/baseKey so a store can record which
    // session consumed the key. This store only tracks used/unused, so they are
    // ignored — same behaviour as the pre-0.86 two-argument signature.
    func markKyberPreKeyUsed(
        id: UInt32,
        signedPreKeyId: UInt32,
        baseKey: PublicKey,
        context: StoreContext
    ) throws {
        markKyberPreKeyUsed(id)
    }
    
    func loadKyberPreKey(id: UInt32) throws -> KyberPreKeyRecord {
        return try loadKyberPreKey(id: id, context: SimpleStoreContext())
    }
    
    func storeKyberPreKey(_ id: UInt32, _ record: KyberPreKeyRecord) {
        try! storeKyberPreKey(record, id: id, context: SimpleStoreContext())
    }
    
    func removeKyberPreKey(_ id: UInt32) {
        kyberPreKeyRepository.removeKyberPreKey(id)
    }
    
    func loadKyberPreKeys() -> [KyberPreKeyRecord] {
        // Load all unused kyber prekeys
        let context = kyberPreKeyRepository.database.viewContext
        let descriptor = FetchDescriptor<KyberPreKeyEntity>(
            predicate: #Predicate { entity in
                entity.used == false
            }
        )
        
        do {
            let entities: [KyberPreKeyEntity] = try context.fetch(descriptor)
            return entities.compactMap { entity in
                guard let keyData = Data(base64Encoded: entity.kpkRecord) else {
                    return nil
                }
                do {
                    return try KyberPreKeyRecord(bytes: keyData)
                } catch {
                    print("Error deserializing kyber pre key: \(error)")
                    return nil
                }
            }
        } catch {
            print("Error loading kyber pre keys: \(error)")
            return []
        }
    }
    
    func containsKyberPreKey(_ id: UInt32) -> Bool {
        return kyberPreKeyRepository.getKyberPreKey(id: id) != nil
    }
    
    func markKyberPreKeyUsed(_ id: UInt32) {
        let context = kyberPreKeyRepository.database.viewContext
        let idValue = Int64(id)
        let descriptor = FetchDescriptor<KyberPreKeyEntity>(
            predicate: #Predicate { entity in
                entity.prekeyId == idValue
            }
        )
        
        do {
            let results: [KyberPreKeyEntity] = try context.fetch(descriptor)
            for entity in results {
                entity.used = true
            }
            try context.save()
        } catch {
            print("Error marking kyber pre key as used: \(error)")
        }
    }
    
    func clearStorage() {
        kyberPreKeyRepository.clearStorage()
    }
}

// MARK: - Session Store
@available(iOS 17.0, *)
class SekretessSessionStore: SessionStore {
    private let sessionRepository: SessionRepository
    
    init(sessionRepository: SessionRepository) {
        self.sessionRepository = sessionRepository
    }
    
    func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
        return sessionRepository.getSession(name: address.name, deviceId: address.deviceId)
    }
    
    func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [SessionRecord] {
        var sessions: [SessionRecord] = []
        for address in addresses {
            if let session = try loadSession(for: address, context: context) {
                sessions.append(session)
            }
        }
        if sessions.isEmpty && !addresses.isEmpty {
            throw SignalProtocolError.noSession
        }
        return sessions
    }
    
    func storeSession(_ record: SessionRecord, for address: ProtocolAddress, context: StoreContext) throws {
        sessionRepository.storeSession(address.name, address.deviceId, record)
    }
    
    func loadSession(for address: ProtocolAddress) -> SessionRecord? {
        return try! loadSession(for: address, context: SimpleStoreContext())
    }
    
    func storeSession(_ address: ProtocolAddress, _ record: SessionRecord) {
        try! storeSession(record, for: address, context: SimpleStoreContext())
    }
    
    func removeSession(for address: ProtocolAddress) {
        sessionRepository.removeSession(address.name, address.deviceId)
    }
    
    func getSubDeviceSessions(name: String) -> [UInt32] {
        let context = sessionRepository.database.viewContext
        let nameValue = name
        let descriptor = FetchDescriptor<SessionEntity>(
            predicate: #Predicate { entity in
                entity.addressName == nameValue
            }
        )
        
        do {
            let entities: [SessionEntity] = try context.fetch(descriptor)
            return entities.map { UInt32($0.deviceId) }
        } catch {
            print("Error getting sub device sessions: \(error)")
            return []
        }
    }
    
    func containsSession(_ address: ProtocolAddress) -> Bool {
        return loadSession(for: address) != nil
    }
    
    func deleteAllSessions(name: String) {
        let context = sessionRepository.database.viewContext
        let nameValue = name
        let descriptor = FetchDescriptor<SessionEntity>(
            predicate: #Predicate { entity in
                entity.addressName == nameValue
            }
        )
        
        do {
            let results: [SessionEntity] = try context.fetch(descriptor)
            for entity in results {
                context.delete(entity)
            }
            try context.save()
        } catch {
            print("Error deleting all sessions: \(error)")
        }
    }
    
    func clearStorage() {
        sessionRepository.clearStorage()
    }
}

// MARK: - Sender Key Store
@available(iOS 17.0, *)
class SekretessSenderKeyStore: SenderKeyStore {
    private let senderKeyRepository: SenderKeyRepository
    
    init(senderKeyRepository: SenderKeyRepository) {
        self.senderKeyRepository = senderKeyRepository
    }
    
    func loadSenderKey(from sender: ProtocolAddress, distributionId: UUID, context: StoreContext) throws -> SenderKeyRecord? {
        return senderKeyRepository.getSenderKey(
            distributionId: distributionId,
            name: sender.name,
            deviceId: sender.deviceId
        )
    }
    
    func storeSenderKey(from sender: ProtocolAddress, distributionId: UUID, record: SenderKeyRecord, context: StoreContext) throws {
        senderKeyRepository.storeSenderKey(distributionId, sender.name, sender.deviceId, record)
    }
    
    func loadSenderKey(for distributionId: UUID, address: ProtocolAddress) -> SenderKeyRecord? {
        return try! loadSenderKey(from: address, distributionId: distributionId, context: SimpleStoreContext())
    }
    
    func storeSenderKey(_ distributionId: UUID, _ address: ProtocolAddress, _ record: SenderKeyRecord) {
        try! storeSenderKey(from: address, distributionId: distributionId, record: record, context: SimpleStoreContext())
    }
    
    func clearStorage() {
        senderKeyRepository.clearStorage()
    }
}
