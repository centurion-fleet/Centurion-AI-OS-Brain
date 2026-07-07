#include "sodium_stubs.h"

/* Stub: generates a deterministic keypair (not secure — for dev only) */
int crypto_box_keypair(unsigned char *pk, unsigned char *sk) {
    if (!pk || !sk) return -1;
    for (int i = 0; i < 32; i++) {
        pk[i] = (unsigned char)(i ^ 0xAA);
        sk[i] = (unsigned char)(i ^ 0x55);
    }
    return 0;
}

/* Stub: returns a deterministic shared key */
int crypto_kx_client_session_keys(
    unsigned char *rx, unsigned char *tx,
    const unsigned char *client_pk,
    const unsigned char *client_sk,
    const unsigned char *server_pk)
{
    (void)client_pk; (void)client_sk; (void)server_pk;
    if (rx) for (int i = 0; i < 32; i++) rx[i] = (unsigned char)(i);
    if (tx) for (int i = 0; i < 32; i++) tx[i] = (unsigned char)(i ^ 0xFF);
    return 0;
}

/* Stub: copies plaintext to ciphertext (no real encryption) */
int crypto_secretbox_easy(
    unsigned char *c, const unsigned char *m,
    unsigned long long mlen, const unsigned char *n,
    const unsigned char *k)
{
    (void)n; (void)k;
    if (c && m) {
        for (unsigned long long i = 0; i < mlen; i++) c[i] = m[i];
    }
    return 0;
}

/* Stub: copies ciphertext to plaintext (no real decryption) */
int crypto_secretbox_open_easy(
    unsigned char *m, const unsigned char *c,
    unsigned long long clen, const unsigned char *n,
    const unsigned char *k)
{
    (void)n; (void)k;
    if (m && c) {
        for (unsigned long long i = 0; i < clen; i++) m[i] = c[i];
    }
    return 0;
}

/* Stub: fills buffer with deterministic bytes (not random!) */
void randombytes_buf(void * const buf, const size_t size) {
    if (!buf) return;
    unsigned char *p = (unsigned char *)buf;
    for (size_t i = 0; i < size; i++) {
        p[i] = (unsigned char)(i * 17 + 42);
    }
}
