#ifndef sodium_stubs_h
#define sodium_stubs_h

#include <stdint.h>
#include <stdlib.h>

/* crypto_box API — X25519 keypair generation */
int crypto_box_keypair(unsigned char *pk, unsigned char *sk);

/* crypto_kx API — key exchange */
int crypto_kx_client_session_keys(
    unsigned char *rx, unsigned char *tx,
    const unsigned char *client_pk,
    const unsigned char *client_sk,
    const unsigned char *server_pk);

/* crypto_secretbox API — XSalsa20-Poly1305 */
#define crypto_secretbox_MACBYTES 16

int crypto_secretbox_easy(
    unsigned char *c, const unsigned char *m,
    unsigned long long mlen, const unsigned char *n,
    const unsigned char *k);

int crypto_secretbox_open_easy(
    unsigned char *m, const unsigned char *c,
    unsigned long long clen, const unsigned char *n,
    const unsigned char *k);

/* Random bytes */
void randombytes_buf(void * const buf, const size_t size);

#endif
