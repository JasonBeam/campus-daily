package com.beamjason.xiaorichang.security

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** AES-GCM data encryption using a non-exportable Android Keystore key. */
class SecureStore(context: Context) {
    private val prefs = context.getSharedPreferences("private_state_v1", Context.MODE_PRIVATE)
    private val alias = "com.beamjason.xiaorichang.local.v1"

    @Synchronized fun put(name: String, clearText: ByteArray) {
        require(name.matches(Regex("[A-Za-z0-9_.-]{1,100}")) && clearText.size <= 1_048_576)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = cipher.doFinal(clearText)
        val value = cipher.iv + encrypted
        check(prefs.edit().putString(name, Base64.encodeToString(value, Base64.NO_WRAP)).commit())
    }

    @Synchronized fun get(name: String): ByteArray? {
        val encoded = prefs.getString(name, null) ?: return null
        val packed = Base64.decode(encoded, Base64.NO_WRAP)
        require(packed.size in 29..1_048_640)
        val iv = packed.copyOfRange(0, 12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, iv))
        return cipher.doFinal(packed.copyOfRange(12, packed.size))
    }

    @Synchronized fun remove(name: String) { check(prefs.edit().remove(name).commit()) }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build())
        return generator.generateKey()
    }
}
