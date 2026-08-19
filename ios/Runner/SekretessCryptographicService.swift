import Foundation
import LibSignalClient

/// Main Signal Protocol cryptographic service for iOS.
/// Mirrors the functionality of the Android SekretessCryptographicService.
class SekretessCryptographicService {
    private let SIGNAL_KEY_COUNT = 15
    private let signalProtocolStore: SekretessSignalProtocolStore
    private let deviceId: UInt32 = 1
    private let storeContext = SimpleStoreContext()

    init(signalProtocolStore: SekretessSignalProtocolStore) {
        self.signalProtocolStore = signalProtocolStore
    }

    /// Initialize Signal Protocol - generates keys if needed and uploads to server
    func initialize() throws -> Bool {
        if signalProtocolStore.registrationRequired() {
            let keyBundle = try initializeKeyBundle()

            // Call API bridge to upload keys
            let keyBundleMap = KeyBundleConverter.toMap(keyBundle: keyBundle)
            let success = FlutterDependencyProvider.callApi(
                method: "upsertKeyStore",
                arguments: keyBundleMap
            )

            if success {
                storeKyberPreKeyRecords(keyBundle.kyberPreKeyRecords)
                storePreKeyRecords(keyBundle.opk)
                storeSignedPreKey(keyBundle.signedPreKeyRecord)
                return true
            } else {
                print("SekretessCryptographicService: Upsert cryptographic keys failed")
                signalProtocolStore.clearStorage()
                return false
            }
        } else if signalProtocolStore.updateKeysRequired() {
            print("SekretessCryptographicService: Update onetime cryptographic keys")
            try updateOneTimeKeys()
        }
        return true
    }

    /// Decrypt a group chat message
    func decryptGroupChatMessage(sender: String, base64Message: String) throws -> String? {
        guard let messageData = Data(base64Encoded: base64Message) else {
            throw SignalProtocolError.invalidMessage
        }

        let address = try ProtocolAddress(name: sender, deviceId: deviceId)

        do {
            let decryptedData = try groupDecrypt(
                messageData,
                from: address,
                store: signalProtocolStore.senderKeyStore,
                context: storeContext
            )
            guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
                throw SignalProtocolError.invalidMessage
            }
            return decryptedString
        } catch {
            print("Error decrypting group chat message: \(error)")
            throw SignalProtocolError.invalidMessage
        }
    }

    /// Decrypt a private message
    func decryptPrivateMessage(sender: String, base64Message: String) throws -> String? {
        guard let messageData = Data(base64Encoded: base64Message) else {
            throw SignalProtocolError.invalidMessage
        }

        let address = try ProtocolAddress(name: sender, deviceId: deviceId)

        // Try as PreKeySignalMessage first
        do {
            let preKeyMessage = try PreKeySignalMessage(bytes: messageData)
            let decryptedData = try signalDecryptPreKey(
                message: preKeyMessage,
                from: address,
                sessionStore: signalProtocolStore.sessionStore,
                identityStore: signalProtocolStore.identityKeyStore,
                preKeyStore: signalProtocolStore.preKeyStore,
                signedPreKeyStore: signalProtocolStore.signedPreKeyStore,
                kyberPreKeyStore: signalProtocolStore.kyberPreKeyStore,
                context: storeContext
            )
            guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
                throw SignalProtocolError.invalidMessage
            }
            return decryptedString
        } catch {
            // Try as SignalMessage
            do {
                let signalMessage = try SignalMessage(bytes: messageData)
                let decryptedData = try signalDecrypt(
                    message: signalMessage,
                    from: address,
                    sessionStore: signalProtocolStore.sessionStore,
                    identityStore: signalProtocolStore.identityKeyStore,
                    context: storeContext
                )
                guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
                    throw SignalProtocolError.invalidMessage
                }
                return decryptedString
            } catch {
                print("Error decrypting private message: \(error)")
                throw error
            }
        }
    }

    /// Process a key distribution message for group chats
    func processKeyDistributionMessage(name: String, base64Key: String) throws {
        guard let keyData = Data(base64Encoded: base64Key) else {
            throw SignalProtocolError.invalidMessage
        }

        let address = try ProtocolAddress(name: name, deviceId: deviceId)
        let distributionMessage = try SenderKeyDistributionMessage(bytes: keyData)

        do {
            try processSenderKeyDistributionMessage(
                distributionMessage,
                from: address,
                store: signalProtocolStore.senderKeyStore,
                context: storeContext
            )
            print("SekretessCryptographicService: Group chat cipher created and stored: \(name)")
        } catch {
            print("Error processing key distribution message: \(error)")
            throw error
        }
    }

    /// Update one-time keys
    func updateOneTimeKeys() throws {
        let identityKeyPair = try signalProtocolStore.identityKeyStore.identityKeyPair(context: storeContext)
        let preKeyRecords = generatePreKeys()
        let kyberPreKeyRecords = generateKyberPreKeys(privateKey: identityKeyPair.privateKey)

        // Convert to map for API call
        let keysMap = KeyBundleConverter.oneTimeKeysToMap(
            preKeyRecords: preKeyRecords,
            kyberPreKeyRecords: kyberPreKeyRecords
        )

        let success = FlutterDependencyProvider.callApi(
            method: "updateOneTimeKeys",
            arguments: keysMap
        )

        if success {
            storePreKeyRecords(preKeyRecords)
            storeKyberPreKeyRecords(kyberPreKeyRecords)
        } else {
            throw SignalProtocolError.apiCallFailed
        }
    }

    /// Clears all Signal protocol keys from local storage (e.g. on logout).
    /// Call this in parallel with removing auth state when the user logs out.
    func clearSignalKeys() {
        signalProtocolStore.clearStorage()
    }

    /// Initialize key bundle for signup
    func initializeKeyBundle() throws -> KeyBundle {
        signalProtocolStore.clearStorage()

        let signedPreKeyPrivateKey = PrivateKey.generate()
        let identityKeyPair = try signalProtocolStore.identityKeyStore.identityKeyPair(context: storeContext)
        let registrationId = try signalProtocolStore.identityKeyStore.localRegistrationId(context: storeContext)

        let publicKeyData = signedPreKeyPrivateKey.publicKey.serialize()
        let signature = identityKeyPair.privateKey.generateSignature(message: publicKeyData)

        let opk = generatePreKeys()
        let signedPreKeyRecord = try generateSignedPreKey(privateKey: signedPreKeyPrivateKey, signature: signature)
        let kyberPreKeyRecords = generateKyberPreKeys(privateKey: identityKeyPair.privateKey)

        // Persist the bundle locally so the phone can decrypt sessions built from it.
        // The signup path uploads this bundle directly (createUser) and never runs
        // initialize()'s store step, so without this the signed prekey, OPKs and kyber
        // keys would live only on the server and inbound PreKeySignalMessages would fail
        // to decrypt. Identity key + registration id are already persisted as side effects
        // of identityKeyPair()/localRegistrationId(). Safe for the initialize() path too:
        // on upsert failure initialize() calls clearStorage(), which removes these again.
        storePreKeyRecords(opk)
        storeSignedPreKey(signedPreKeyRecord)
        storeKyberPreKeyRecords(kyberPreKeyRecords)

        return KeyBundle(
            registrationId: registrationId,
            opk: opk,
            signedPreKeyRecord: signedPreKeyRecord,
            identityKeyPair: identityKeyPair,
            signature: signature,
            kyberPreKeyRecords: kyberPreKeyRecords
        )
    }

    private func generatePreKeys() -> [PreKeyRecord] {
        var preKeys: [PreKeyRecord] = []
        for _ in 0..<SIGNAL_KEY_COUNT {
            let id = UInt32.random(in: 1..<9999999)
            let privateKey = PrivateKey.generate()
            do {
                let preKey = try PreKeyRecord(id: id, privateKey: privateKey)
                preKeys.append(preKey)
            } catch {
                print("Error generating pre key: \(error)")
                // Continue with next key
            }
        }
        return preKeys
    }

    private func generateKyberPreKeys(privateKey: PrivateKey) -> [KyberPreKeyRecord] {
        var kyberPreKeys: [KyberPreKeyRecord] = []
        // Generate SIGNAL_KEY_COUNT + 1 (last resort key)
        for _ in 0..<(SIGNAL_KEY_COUNT + 1) {
            let id = UInt32.random(in: 1..<9999999)
            let kemKeyPair = KEMKeyPair.generate()
            do {
                let publicKeyData = kemKeyPair.publicKey.serialize()
                let signature = privateKey.generateSignature(message: publicKeyData)
                let timestamp = UInt64(Date().timeIntervalSince1970)
                let kyberPreKey = try KyberPreKeyRecord(
                    id: id,
                    timestamp: timestamp,
                    keyPair: kemKeyPair,
                    signature: signature
                )
                kyberPreKeys.append(kyberPreKey)
            } catch {
                print("Error generating kyber pre key: \(error)")
                // Continue with next key
            }
        }
        return kyberPreKeys
    }

    private func generateSignedPreKey(privateKey: PrivateKey, signature: Data) throws -> SignedPreKeyRecord {
        let id = UInt32.random(in: 1..<9999999)
        let timestamp = UInt64(Date().timeIntervalSince1970)
        return try SignedPreKeyRecord(
            id: id,
            timestamp: timestamp,
            privateKey: privateKey,
            signature: signature
        )
    }

    private func storePreKeyRecords(_ records: [PreKeyRecord]) {
        for record in records {
            do {
                try signalProtocolStore.preKeyStore.storePreKey(record, id: record.id, context: storeContext)
            } catch {
                print("Error storing pre key: \(error)")
            }
        }
    }

    private func storeKyberPreKeyRecords(_ records: [KyberPreKeyRecord]) {
        for record in records {
            do {
                try signalProtocolStore.kyberPreKeyStore.storeKyberPreKey(record, id: record.id, context: storeContext)
            } catch {
                print("Error storing kyber pre key: \(error)")
            }
        }
    }

    private func storeSignedPreKey(_ record: SignedPreKeyRecord) {
        do {
            try signalProtocolStore.signedPreKeyStore.storeSignedPreKey(record, id: record.id, context: storeContext)
        } catch {
            print("Error storing signed pre key: \(error)")
        }
    }
}

enum SignalProtocolError: Error {
    case invalidMessage
    case apiCallFailed
    case initializationFailed
    case invalidKeyId
    case noSession
    case duplicateMessage
    case legacyMessage
    case invalidVersion
    case invalidKey
    case untrustedIdentity
}
