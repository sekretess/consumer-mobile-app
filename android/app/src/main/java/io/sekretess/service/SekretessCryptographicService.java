package io.sekretess.service;

import android.util.Log;
import android.widget.Toast;

import org.signal.libsignal.protocol.DuplicateMessageException;
import org.signal.libsignal.protocol.IdentityKeyPair;
import org.signal.libsignal.protocol.InvalidKeyException;
import org.signal.libsignal.protocol.InvalidKeyIdException;
import org.signal.libsignal.protocol.InvalidMessageException;
import org.signal.libsignal.protocol.InvalidVersionException;
import org.signal.libsignal.protocol.LegacyMessageException;
import org.signal.libsignal.protocol.NoSessionException;
import org.signal.libsignal.protocol.SessionCipher;
import org.signal.libsignal.protocol.SignalProtocolAddress;
import org.signal.libsignal.protocol.UntrustedIdentityException;
import org.signal.libsignal.protocol.ecc.ECKeyPair;
import org.signal.libsignal.protocol.ecc.ECPrivateKey;
import org.signal.libsignal.protocol.groups.GroupCipher;
import org.signal.libsignal.protocol.groups.GroupSessionBuilder;
import org.signal.libsignal.protocol.kem.KEMKeyPair;
import org.signal.libsignal.protocol.kem.KEMKeyType;
import org.signal.libsignal.protocol.message.PreKeySignalMessage;
import org.signal.libsignal.protocol.message.SenderKeyDistributionMessage;
import org.signal.libsignal.protocol.state.KyberPreKeyRecord;
import org.signal.libsignal.protocol.state.PreKeyRecord;
import org.signal.libsignal.protocol.state.SignedPreKeyRecord;
import org.signal.libsignal.protocol.util.Medium;

import java.security.SecureRandom;
import java.util.Base64;
import java.util.Optional;

import io.sekretess.bridge.FlutterDependencyProvider;
import io.sekretess.bridge.NativeApiClientBridge;
import io.sekretess.dto.KeyBundle;
import io.sekretess.cryptography.storage.SekretessSignalProtocolStore;


public class SekretessCryptographicService {
    private final int SIGNAL_KEY_COUNT = 15;
    private static final Base64.Decoder base64Decoder = Base64.getDecoder();
    private final SekretessSignalProtocolStore sekretessSignalProtocolStore;
    private final String TAG = "SekretessCryptographicService";
    private final int deviceId = 1;
    private NativeApiClientBridge apiClientBridge;


    public SekretessCryptographicService(SekretessSignalProtocolStore sekretessSignalProtocolStore) {
        this.sekretessSignalProtocolStore = sekretessSignalProtocolStore;
    }
    
    public void setApiClientBridge(NativeApiClientBridge apiClientBridge) {
        this.apiClientBridge = apiClientBridge;
    }
    
    public SekretessSignalProtocolStore getSignalProtocolStore() {
        return sekretessSignalProtocolStore;
    }

    public void updateOneTimeKeys() {
        IdentityKeyPair identityKeyPair = sekretessSignalProtocolStore.getIdentityKeyPair();
        PreKeyRecord[] preKeyRecords = generatePreKeys();
        KyberPreKeyRecord[] kyberPreKeyRecords = generateKyberPreKeys(identityKeyPair.getPrivateKey());
        try {
            if (apiClientBridge != null && apiClientBridge.updateOneTimeKeys(preKeyRecords, kyberPreKeyRecords)) {
                storePreKeyRecords(preKeyRecords);
                storeKyberPreKeyRecords(kyberPreKeyRecords);
            }
        } catch (Exception e) {
            Log.e(TAG, "Error during update one time keys", e);
            if (apiClientBridge != null) {
                apiClientBridge.showToast("Error during update one time keys: " + e.getMessage());
            }
        }
    }

    public KyberPreKeyRecord[] generateKyberPreKeys(ECPrivateKey ecPrivateKey) {
        // Generate post quantum resistance keys + 1 last resort key
        KyberPreKeyRecord[] kyberPreKeyRecords = new KyberPreKeyRecord[SIGNAL_KEY_COUNT + 1];

        for (int i = 0; i < kyberPreKeyRecords.length; i++) {
            KyberPreKeyRecord kyberPreKeyRecord = generateKyberPreKey(ecPrivateKey);
            kyberPreKeyRecords[i] = kyberPreKeyRecord;
        }
        // Generated post quantum keys
        return kyberPreKeyRecords;
    }

    public KyberPreKeyRecord generateKyberPreKey(ECPrivateKey ecPrivateKey) {
        int kyberSignedPreKeyId = new SecureRandom().nextInt(Medium.MAX_VALUE - 1);
        KEMKeyPair kemKeyPair = KEMKeyPair.generate(KEMKeyType.KYBER_1024);
        KyberPreKeyRecord kyberPreKeyRecord = new KyberPreKeyRecord(kyberSignedPreKeyId,
                System.currentTimeMillis(), kemKeyPair,
                ecPrivateKey.calculateSignature(kemKeyPair.getPublicKey().serialize()));
        return kyberPreKeyRecord;
    }

    public void processKeyDistributionMessage(String name, String base64Key) {
        try {
            Log.i(TAG, "base64 keyDistributionMessage: " + base64Key);
            SenderKeyDistributionMessage senderKeyDistributionMessage =
                    new SenderKeyDistributionMessage(Base64.getDecoder().decode(base64Key));
            new GroupSessionBuilder(sekretessSignalProtocolStore)
                    .process(new SignalProtocolAddress(name, 1), senderKeyDistributionMessage);
            Log.i(TAG, "Group chat chipper created and stored : " + name);
        } catch (Exception e) {
            Log.e(TAG, "Error during decrypt key distribution message", e);
            if (apiClientBridge != null) {
                apiClientBridge.showToast("Error during decrypt distribution message: " + e.getMessage());
            }
        }
    }

    public void storeKyberPreKeyRecords(KyberPreKeyRecord[] kyberPreKeyRecords) {
        for (KyberPreKeyRecord kyberPreKeyRecord : kyberPreKeyRecords) {
            sekretessSignalProtocolStore.storeKyberPreKey(kyberPreKeyRecord.getId(), kyberPreKeyRecord);
            Log.i(TAG, "Storing KyberPreKEyRecord:" +kyberPreKeyRecord.getId());
        }
    }

    public void storePreKeyRecords(PreKeyRecord[] preKeyRecords) {
        for (PreKeyRecord preKeyRecord : preKeyRecords) {
            Log.i(TAG, "Storing PreKeyRecord:" +preKeyRecord.getId());
            sekretessSignalProtocolStore.storePreKey(preKeyRecord.getId(), preKeyRecord);
        }
    }

    public void storeSignedPreKey(SignedPreKeyRecord signedPreKeyRecord) {
        sekretessSignalProtocolStore.storeSignedPreKey(signedPreKeyRecord.getId(), signedPreKeyRecord);
    }

    public SignedPreKeyRecord generateSignedPreKey(ECKeyPair keyPair, byte[] signature) {
        //Generate signed prekeyRecord
        int signedPreKeyId = new SecureRandom().nextInt(Medium.MAX_VALUE - 1);
        return new SignedPreKeyRecord(signedPreKeyId, System.currentTimeMillis(), keyPair, signature);
    }

    public PreKeyRecord[] generatePreKeys() {
        PreKeyRecord[] preKeyRecords = new PreKeyRecord[SIGNAL_KEY_COUNT];
        SecureRandom preKeyRecordIdGenerator = new SecureRandom();
        for (int i = 0; i < preKeyRecords.length; i++) {
            int id = preKeyRecordIdGenerator.nextInt(Integer.MAX_VALUE);
            ECKeyPair ecKeyPair = ECKeyPair.generate();
            PreKeyRecord preKeyRecord = new PreKeyRecord(id, ecKeyPair);
            preKeyRecords[i] = preKeyRecord;
        }
        return preKeyRecords;
    }

    /**
     * Clears all Signal protocol keys from local storage (e.g. on logout).
     * Call this in parallel with removing auth state when the user logs out.
     */
    public void clearSignalKeys() {
        sekretessSignalProtocolStore.clearStorage();
    }

    public KeyBundle initializeKeyBundle() {
        sekretessSignalProtocolStore.clearStorage();

        ECKeyPair signedPreKeyPair = ECKeyPair.generate();
        IdentityKeyPair identityKeyPair = sekretessSignalProtocolStore.getIdentityKeyPair();
        int registrationId = sekretessSignalProtocolStore.getLocalRegistrationId();

        byte[] signature = identityKeyPair.getPrivateKey().calculateSignature(signedPreKeyPair
                .getPublicKey().serialize());

        //Generate one-time prekeys
        PreKeyRecord[] opk = generatePreKeys();

        SignedPreKeyRecord signedPreKeyRecord = generateSignedPreKey(signedPreKeyPair, signature);
        KyberPreKeyRecord[] kyberPreKeyRecords = generateKyberPreKeys(identityKeyPair.getPrivateKey());

        // Persist the bundle locally so the phone can decrypt sessions built from it.
        // The signup path uploads this bundle directly (createUser) and never runs
        // init()'s store step, so without this the signed prekey, OPKs and kyber keys
        // would live only on the server and inbound PreKeySignalMessages would fail
        // with InvalidKeyIdException. The identity key + registration id are already
        // persisted as side effects of getIdentityKeyPair()/getLocalRegistrationId().
        // Safe for the init() path too: on upsert failure init() calls clearStorage(),
        // which removes these again.
        storePreKeyRecords(opk);
        storeSignedPreKey(signedPreKeyRecord);
        storeKyberPreKeyRecords(kyberPreKeyRecords);

        return new KeyBundle(registrationId, opk, signedPreKeyRecord,
                identityKeyPair, signature,
                kyberPreKeyRecords);
    }


    public boolean init() throws Exception {
        if (sekretessSignalProtocolStore.registrationRequired()) {
            KeyBundle keyBundle = initializeKeyBundle();

            if (apiClientBridge != null && apiClientBridge.upsertKeyStore(keyBundle)) {
                storeKyberPreKeyRecords(keyBundle.getKyberPreKeyRecords());
                storePreKeyRecords(keyBundle.getOpk());
                storeSignedPreKey(keyBundle.getSignedPreKeyRecord());
                return true;
            } else {
                Log.w(TAG, "Upsert cryptographic keys failed");
                sekretessSignalProtocolStore.clearStorage();
                return false;
            }
        } else if (sekretessSignalProtocolStore.updateKeysRequired()) {
            Log.w(TAG, "Update onetime cryptographic keys");
            updateOneTimeKeys();
        }
        return true;
    }

    public Optional<String> decryptGroupChatMessage(String sender, String base64Message) throws NoSessionException, InvalidMessageException, DuplicateMessageException, LegacyMessageException {
        GroupCipher groupCipher = new GroupCipher(sekretessSignalProtocolStore, new SignalProtocolAddress(sender, 1));
        String decryptedMessage = new String(groupCipher.decrypt(base64Decoder.decode(base64Message)));
        return Optional.of(decryptedMessage);
    }

    public Optional<String> decryptPrivateMessage(String sender, String base64Message) throws InvalidMessageException, InvalidVersionException, LegacyMessageException, InvalidKeyException, UntrustedIdentityException, DuplicateMessageException, InvalidKeyIdException {
        PreKeySignalMessage preKeySignalMessage = new PreKeySignalMessage(base64Decoder.decode(base64Message));
        SignalProtocolAddress signalProtocolAddress = new SignalProtocolAddress(sender, 1);
        SessionCipher sessionCipher = new SessionCipher(sekretessSignalProtocolStore, signalProtocolAddress);
        return Optional.of(new String(sessionCipher.decrypt(preKeySignalMessage)));
    }
}
