/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * aesce-ccm-core.S - AES-CCM transform for ARMv8 with Crypto Extensions
 *
 * Copyright (C) 2013 - 2017 Linaro Ltd <ard.biesheuvel@linaro.org>
 */

#include <linux/linkage.h>
#include <asm/assembler.h>

	.text
	.arch	armv8-a+crypto

	/*
	 * u32 ce_aes_ccm_auth_data(u8 mac[], u8 const in[], u32 abytes,
	 *			    u32 macp, u8 const rk[], u32 rounds);
	 */
ENTRY(ce_aes_ccm_auth_data)
	ld1	{v0.16b}, [x0]			/* load mac */
	cbz	w3, 1f
	sub	w3, w3, #16
	eor	v1.16b, v1.16b, v1.16b
0:	ldrb	w7, [x1], #1			/* get 1 byte of input */
	subs	w2, w2, #1
	add	w3, w3, #1
	ins	v1.b[0], w7
	ext	v1.16b, v1.16b, v1.16b, #1	/* rotate in the input bytes */
	beq	8f				/* out of input? */
	cbnz	w3, 0b
	eor	v0.16b, v0.16b, v1.16b
1:	ld1	{v3.4s}, [x4]			/* load first round key */
	prfm	pldl1strm, [x1]
	cmp	w5, #12				/* which key size? */
	add	x6, x4, #16
	sub	w7, w5, #2			/* modified # of rounds */
	bmi	2f
	bne	5f
	mov	v5.16b, v3.16b
	b	4f
2:	mov	v4.16b, v3.16b
	ld1	{v5.4s}, [x6], #16		/* load 2nd round key */
3:	aese	v0.16b, v4.16b
	aesmc	v0.16b, v0.16b
4:	ld1	{v3.4s}, [x6], #16		/* load next round key */
	aese	v0.16b, v5.16b
	aesmc	v0.16b, v0.16b
5:	ld1	{v4.4s}, [x6], #16		/* load next round key */
	subs	w7, w7, #3
	aese	v0.16b, v3.16b
	aesmc	v0.16b, v0.16b
	ld1	{v5.4s}, [x6], #16		/* load next round key */
	bpl	3b
	aese	v0.16b, v4.16b
	subs	w2, w2, #16			/* last data? */
	eor	v0.16b, v0.16b, v5.16b		/* final round */
	bmi	6f
	ld1	{v1.16b}, [x1], #16		/* load next input block */
	eor	v0.16b, v0.16b, v1.16b		/* xor with mac */
	bne	1b
6:	st1	{v0.16b}, [x0]			/* store mac */
	beq	10f
	adds	w2, w2, #16
	beq	10f
	mov	w3, w2
7:	ldrb	w7, [x1], #1
	umov	w6, v0.b[0]
	eor	w6, w6, w7
	strb	w6, [x0], #1
	subs	w2, w2, #1
	beq	10f
	ext	v0.16b, v0.16b, v0.16b, #1	/* rotate out the mac bytes */
	b	7b
8:	cbz	w3, 91f
	mov	w7, w3
	add	w3, w3, #16
9:	ext	v1.16b, v1.16b, v1.16b, #1
	adds	w7, w7, #1
	bne	9b
91:	eor	v0.16b, v0.16b, v1.16b
	st1	{v0.16b}, [x0]
10:	mov	w0, w3
	ret
ENDPROC(ce_aes_ccm_auth_data)

	/*
	 * void ce_aes_ccm_final(u8 mac[], u8 const ctr[], u8 const rk[],
	 * 			 u32 rounds);
	 */
ENTRY(ce_aes_ccm_final)
	ld1	{v3.4s}, [x2], #16		/* load first round key */
	ld1	{v0.16b}, [x0]			/* load mac */
	cmp	w3, #12				/* which key size? */
	sub	w3, w3, #2			/* modified # of rounds */
	ld1	{v1.16b}, [x1]			/* load 1st ctriv */
	bmi	0f
	bne	3f
	mov	v5.16b, v3.16b
	b	2f
0:	mov	v4.16b, v3.16b
1:	ld1	{v5.4s}, [x2], #16		/* load next round key */
	aese	v0.16b, v4.16b
	aesmc	v0.16b, v0.16b
	aese	v1.16b, v4.16b
	aesmc	v1.16b, v1.16b
2:	ld1	{v3.4s}, [x2], #16		/* load next round key */
	aese	v0.16b, v5.16b
	aesmc	v0.16b, v0.16b
	aese	v1.16b, v5.16b
	aesmc	v1.16b, v1.16b
3:	ld1	{v4.4s}, [x2], #16		/* load next round key */
	subs	w3, w3, #3
	aese	v0.16b, v3.16b
	aesmc	v0.16b, v0.16b
	aese	v1.16b, v3.16b
	aesmc	v1.16b, v1.16b
	bpl	1b
	aese	v0.16b, v4.16b
	aese	v1.16b, v4.16b
	/* final round key cancels out */
	eor	v0.16b, v0.16b, v1.16b		/* en-/decrypt the mac */
	st1	{v0.16b}, [x0]			/* store result */
	ret
ENDPROC(ce_aes_ccm_final)

	.macro	aes_ccm_do_crypt,enc
	cbz	x2, 5f
	ldr	x8, [x6, #8]			/* load lower ctr */
	ld1	{v0.16b}, [x5]			/* load mac */
CPU_LE(	rev	x8, x8			)	/* keep swabbed ctr in reg */
0:	/* outer loop */
	ld1	{v1.8b}, [x6]			/* load upper ctr */
	prfm	pldl1strm, [x1]
	add	x8, x8, #1
	rev	x9, x8
	cmp	w4, #12				/* which key size? */
	sub	w7, w4, #2			/* get modified # of rounds */
	ins	v1.d[1], x9			/* no carry in lower ctr */
	ld1	{v3.4s}, [x3]			/* load first round key */
	add	x10, x3, #16
	bmi	1f
	bne	4f
	mov	v5.16b, v3.16b
	b	3f
1:	mov	v4.16b, v3.16b
	ld1	{v5.4s}, [x10], #16		/* load 2nd round key */
2:	/* inner loop: 3 rounds, 2x interleaved */
	aese	v0.16b, v4.16b
	aesmc	v0.16b, v0.16b
	aese	v1.16b, v4.16b
	aesmc	v1.16b, v1.16b
3:	ld1	{v3.4s}, [x10], #16		/* load next round key */
	aese	v0.16b, v5.16b
	aesmc	v0.16b, v0.16b
	aese	v1.16b, v5.16b
	aesmc	v1.16b, v1.16b
4:	ld1	{v4.4s}, [x10], #16		/* load next round key */
	subs	w7, w7, #3
	aese	v0.16b, v3.16b
	aesmc	v0.16b, v0.16b
	aese	v1.16b, v3.16b
	aesmc	v1.16b, v1.16b
	ld1	{v5.4s}, [x10], #16		/* load next round key */
	bpl	2b
	aese	v0.16b, v4.16b
	aese	v1.16b, v4.16b
	subs	w2, w2, #16
	bmi	6f				/* partial block? */
	ld1	{v2.16b}, [x1], #16		/* load next input block */
	.if	\enc == 1
	eor	v2.16b, v2.16b, v5.16b		/* final round enc+mac */
	eor	v1.16b, v1.16b, v2.16b		/* xor with crypted ctr */
	.else
	eor	v2.16b, v2.16b, v1.16b		/* xor with crypted ctr */
	eor	v1.16b, v2.16b, v5.16b		/* final round enc */
	.endif
	eor	v0.16b, v0.16b, v2.16b		/* xor mac with pt ^ rk[last] */
	st1	{v1.16b}, [x0], #16		/* write output block */
	bne	0b
CPU_LE(	rev	x8, x8			)
	st1	{v0.16b}, [x5]			/* store mac */
	str	x8, [x6, #8]			/* store lsb end of ctr (BE) */
5:	ret

6:	eor	v0.16b, v0.16b, v5.16b		/* final round mac */
	eor	v1.16b, v1.16b, v5.16b		/* final round enc */
	st1	{v0.16b}, [x5]			/* store mac */
	add	w2, w2, #16			/* process partial tail block */
7:	ldrb	w9, [x1], #1			/* get 1 byte of input */
	umov	w6, v1.b[0]			/* get top crypted ctr byte */
	umov	w7, v0.b[0]			/* get top mac byte */
	.if	\enc == 1
	eor	w7, w7, w9
	eor	w9, w9, w6
	.else
	eor	w9, w9, w6
	eor	w7, w7, w9
	.endif
	strb	w9, [x0], #1			/* store out byte */
	strb	w7, [x5], #1			/* store mac byte */
	subs	w2, w2, #1
	beq	5b
	ext	v0.16b, v0.16b, v0.16b, #1	/* shift out mac byte */
	ext	v1.16b, v1.16b, v1.16b, #1	/* shift out ctr byte */
	b	7b
	.endm

	/*
	 * void ce_aes_ccm_encrypt(u8 out[], u8 const in[], u32 cbytes,
	 * 			   u8 const rk[], u32 rounds, u8 mac[],
	 * 			   u8 ctr[]);
	 * void ce_aes_ccm_decrypt(u8 out[], u8 const in[], u32 cbytes,
	 * 			   u8 const rk[], u32 rounds, u8 mac[],
	 * 			   u8 ctr[]);
	 */
ENTRY(ce_aes_ccm_encrypt)
	aes_ccm_do_crypt	1
ENDPROC(ce_aes_ccm_encrypt)

ENTRY(ce_aes_ccm_decrypt)
	aes_ccm_do_crypt	0
ENDPROC(ce_aes_ccm_decrypt)
