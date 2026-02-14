"""Envelope encryption service with swappable KMS backend.

MVP uses a local key from environment variable.
Production: swap LocalKMSProvider for AWSKMSProvider / GCPKMSProvider.
"""

import base64
import os
from abc import ABC, abstractmethod

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.core.config import settings


class KMSProvider(ABC):
    """Interface for key management. Swap implementations for production."""

    @abstractmethod
    def get_data_encryption_key(self) -> bytes:
        ...

    @abstractmethod
    def encrypt_dek(self, dek: bytes) -> bytes:
        ...

    @abstractmethod
    def decrypt_dek(self, encrypted_dek: bytes) -> bytes:
        ...


class LocalKMSProvider(KMSProvider):
    """MVP: uses a static master key from env for wrapping DEKs."""

    def __init__(self) -> None:
        key_b64 = settings.encryption_key
        # Pad or derive a 32-byte key
        raw = key_b64.encode("utf-8")
        self._master_key = raw.ljust(32, b"\0")[:32]

    def get_data_encryption_key(self) -> bytes:
        return os.urandom(32)

    def encrypt_dek(self, dek: bytes) -> bytes:
        nonce = os.urandom(12)
        aesgcm = AESGCM(self._master_key)
        ct = aesgcm.encrypt(nonce, dek, None)
        return nonce + ct

    def decrypt_dek(self, encrypted_dek: bytes) -> bytes:
        nonce = encrypted_dek[:12]
        ct = encrypted_dek[12:]
        aesgcm = AESGCM(self._master_key)
        return aesgcm.decrypt(nonce, ct, None)


class EncryptionService:
    def __init__(self, kms: KMSProvider | None = None) -> None:
        self._kms = kms or LocalKMSProvider()

    def encrypt(self, plaintext: str) -> str:
        """Encrypt plaintext. Returns base64-encoded envelope (encrypted_dek + nonce + ciphertext)."""
        dek = self._kms.get_data_encryption_key()
        encrypted_dek = self._kms.encrypt_dek(dek)

        nonce = os.urandom(12)
        aesgcm = AESGCM(dek)
        ct = aesgcm.encrypt(nonce, plaintext.encode("utf-8"), None)

        # Format: [2 bytes dek_len][encrypted_dek][nonce][ciphertext]
        dek_len = len(encrypted_dek).to_bytes(2, "big")
        envelope = dek_len + encrypted_dek + nonce + ct
        return base64.b64encode(envelope).decode("ascii")

    def decrypt(self, envelope_b64: str) -> str:
        """Decrypt an envelope-encrypted value."""
        envelope = base64.b64decode(envelope_b64)
        dek_len = int.from_bytes(envelope[:2], "big")
        encrypted_dek = envelope[2 : 2 + dek_len]
        nonce = envelope[2 + dek_len : 2 + dek_len + 12]
        ct = envelope[2 + dek_len + 12 :]

        dek = self._kms.decrypt_dek(encrypted_dek)
        aesgcm = AESGCM(dek)
        plaintext = aesgcm.decrypt(nonce, ct, None)
        return plaintext.decode("utf-8")


# Singleton for the app
encryption_service = EncryptionService()
