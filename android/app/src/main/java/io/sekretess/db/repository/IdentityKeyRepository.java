package io.sekretess.db.repository;

import android.content.ContentValues;
import android.database.Cursor;
import android.util.Log;

import org.signal.libsignal.protocol.IdentityKey;
import org.signal.libsignal.protocol.IdentityKeyPair;
import org.signal.libsignal.protocol.InvalidKeyException;
import org.signal.libsignal.protocol.SignalProtocolAddress;
import org.signal.libsignal.protocol.state.IdentityKeyStore;

import java.time.Instant;
import java.util.Base64;

import io.sekretess.db.SekretessDatabase;
import io.sekretess.db.dao.IdentityKeyDao;
import io.sekretess.db.dao.IdentityKeyPairDao;
import io.sekretess.db.model.IdentityKeyEntity;
import io.sekretess.db.model.IdentityKeyPairEntity;
import io.sekretess.bridge.FlutterDependencyProvider;

public class IdentityKeyRepository {
    private final String TAG = IdentityKeyRepository.class.getName();
    private final IdentityKeyDao identityKeyDao;
    private final IdentityKeyPairDao identityKeyPairDao;
    private Base64.Decoder base64Decoder = Base64.getDecoder();
    private Base64.Encoder base64Encoder = Base64.getEncoder();


    public IdentityKeyRepository() {
        SekretessDatabase db = SekretessDatabase.getInstance(FlutterDependencyProvider.getApplicationContext());
        this.identityKeyDao = db.identityKeyDao();
        this.identityKeyPairDao = db.identityKeyPairDao();
    }


    public IdentityKeyPair getIdentityKeyPair() {
        IdentityKeyPairEntity identityKeyEntity = identityKeyPairDao.getIdentityKeyPair();
        if (identityKeyEntity != null) {
            String identityKey = identityKeyEntity.getIdentityKeyPair();
            if (identityKey != null) {
                // libsignal 0.86.x: the IdentityKeyPair(byte[]) constructor now throws
                // checked InvalidKeyException, which this IdentityKeyStore override cannot
                // declare, so surface a corrupt stored key as an unchecked failure.
                try {
                    return new IdentityKeyPair(base64Decoder.decode(identityKey));
                } catch (InvalidKeyException e) {
                    Log.e(TAG, "Stored identity key pair is invalid", e);
                    throw new RuntimeException(e);
                }
            }
        }
        return null;
    }

    public void storeIdentityKeyPair(IdentityKeyPair identityKeyPair) {
        IdentityKeyPairEntity identityKeyPairEntity =
                new IdentityKeyPairEntity(base64Encoder.encodeToString(identityKeyPair.serialize()), System.currentTimeMillis());
        identityKeyPairDao.insert(identityKeyPairEntity);
    }

    public IdentityKeyStore.IdentityChange saveIdentity(SignalProtocolAddress address, IdentityKey identityKey) {
        IdentityKeyEntity trustedKey = identityKeyDao.getIdentityKey(address.getDeviceId(), address.getName());
        if (trustedKey == null) {
            identityKeyDao.insert(new IdentityKeyEntity(address.getDeviceId(), address.getName(),
                    base64Encoder.encodeToString(identityKey.serialize()), System.currentTimeMillis()));
            return IdentityKeyStore.IdentityChange.NEW_OR_UNCHANGED;
        } else {
            trustedKey.setIdentityKey(base64Encoder.encodeToString(identityKey.serialize()));
            identityKeyDao.update(trustedKey);
            return IdentityKeyStore.IdentityChange.REPLACED_EXISTING;
        }
    }

    public IdentityKey getIdentity(SignalProtocolAddress address) {
        IdentityKeyEntity identityKey = identityKeyDao.getIdentityKey(address.getDeviceId(), address.getName());

        try {
            if (identityKey != null) {
                return new IdentityKey(base64Decoder.decode(identityKey.getIdentityKey()));
            }
            return null;
        } catch (Exception e) {
            Log.i(TAG, "Error occurred during get IdentityKey", e);
            return null;
        }
    }

    public void clearStorage() {
        identityKeyDao.delete();
        identityKeyPairDao.delete();
    }
}
