! -*- Fundamental -*-
! This is the file Sparc/generic.s.
!
! Larceny run-time system (Sparc) -- Millicode for Generic Arithmetic.
!
! History
!   January 20, 1996 / lth (v0.25)
!     Calling conventions for contagion changed; now takes index rather
!     than procedure.
!
!   April/May 1995 / lth (v0.24)
!     Cases added to quotient and remainder to handle division of nonnegative
!     32-bit bignum by nonnegative fixnum; this vastly simplifies the
!     portable bignum implementation.
!
!   December 6, 1994 / lth (v0.23)
!     Solaris port.
!
!   July 1, 1994 / lth (v0.20)
!     Slightly altered for the new run-time system
!
! Generic arithmetic operations are daisy-chained so as to speed up operations
! of same-representation arithmetic. If representations are not the same, then
! a contagion routine is invoked to coerce operands as necessary, and the
! operation is retried. A compnum with a 0 imaginary part is treated as a
! flonum.
!
! Chain order: flonum, compnum, (fixnum,) bignum, ratnum, rectnum.
!
! For the non-fixnum case, the chain splits: we distinguish between 
! vector-like (rectnum, ratnum) and bytevector-like (flonum, compnum, bignum)
! structures.
!
! Arithmetic for bignums, ratnums, and rectnums are done externally,
! while fixnums, flonums, and compnums are handled in-line in this file.
!
! When a generic arithmetic routine is called, the operands must be in the
! millicode argument registers, and the Scheme return address must be in %o7.
!
! ACKNOWLEDGMENTS
! - Compnum algorithms were taken from Press et al: "Numerical Recipes in C", 
!   Cambridge University Press, 1988.
!
! BUGS
! - Way big. Should have used M4.
!
! - Some of this code depends on TMP0 being a global register (which 
!   is currently the case). Fixed in most places by referring to SAVED_TMP0;
!   the entire file should be checked and the rest fixed.
!
! - Division code (and quotient, remainder, modulus) do not check for 
!   a zero divisor.
!
! - A big win would be to do mixed flonum/fixnum in-line.

#include "asmdefs.h"
#include "asmmacro.h"

	.global	EXTNAME(m_generic_add)		! (+ a b)
	.global	EXTNAME(m_generic_sub)		! (- a b)
	.global	EXTNAME(m_generic_mul)		! (* a b)
	.global	EXTNAME(m_generic_div)		! (/ a b)
	.global	EXTNAME(m_generic_quo)		! (quotient a b)
	.global	EXTNAME(m_generic_rem)		! (remainder a b)
	.global	EXTNAME(m_generic_mod)		! (modulo a b)
	.global	EXTNAME(m_generic_neg)		! (- a)
	.global	EXTNAME(m_generic_abs)		! (abs x)
	.global	EXTNAME(m_generic_zerop)	! (zero? a)
	.global	EXTNAME(m_generic_equalp)	! (= a b)
	.global	EXTNAME(m_generic_lessp)	! (< a b)
	.global	EXTNAME(m_generic_less_or_equalp)! (<= a b)
	.global	EXTNAME(m_generic_greaterp)	! (> a b)
	.global	EXTNAME(m_generic_greater_or_equalp)! (>= a b)
	.global	EXTNAME(m_generic_complexp)	! (complex? a)
	.global	EXTNAME(m_generic_realp)	! (real? a)
	.global	EXTNAME(m_generic_rationalp)	! (rational? a)
	.global	EXTNAME(m_generic_integerp)	! (integer? a)
	.global	EXTNAME(m_generic_exactp)	! (exact? a)
	.global	EXTNAME(m_generic_inexactp)	! (inexact? a)
	.global	EXTNAME(m_generic_exact2inexact)! (exact->inexact a)
	.global	EXTNAME(m_generic_inexact2exact)! (inexact->exact a)
	.global EXTNAME(m_generic_make_rectangular)! (make-rectangular a b)
	.global	EXTNAME(m_generic_real_part)	! (real-part z)
	.global	EXTNAME(m_generic_imag_part)	! (imag-part z)
	.global	EXTNAME(m_generic_sqrt)		! (sqrt z)
	.global	EXTNAME(m_generic_round)	! (round x)
	.global	EXTNAME(m_generic_truncate)	! (truncate x)
	.global	EXTNAME(m_generic_negativep)	! (negative? x)
	.global	EXTNAME(m_generic_positivep)	! (positive? x)

	.seg	"text"

! Addition
! The fixnum case is done in line, so if the operands are fixnums, we had
! an overflow and must box the result in a bignum.

EXTNAME(m_generic_add):
	and	%RESULT, TAGMASK, %TMP0
	and	%ARGREG2, TAGMASK, %TMP1
	cmp	%TMP0, BVEC_TAG
	be,a	Ladd_bvec
	cmp	%TMP1, BVEC_TAG
	or	%RESULT, %ARGREG2, %TMP2
	andcc	%TMP2, 3, %g0
	be,a	Ladd_fix
	nop
	cmp	%TMP0, VEC_TAG
	be,a	Ladd_vec
	cmp	%TMP1, VEC_TAG
	b	_contagion
	mov	MS_GENERIC_ADD, %TMP2
Ladd_bvec:
	be,a	Ladd_bvec2
	ldub	[ %RESULT + 3 - BVEC_TAG ], %TMP0
	b	_contagion
	mov	MS_GENERIC_ADD, %TMP2
Ladd_bvec2:
	ldub	[ %ARGREG2 + 3 - BVEC_TAG ], %TMP1
	cmp	%TMP0, FLONUM_HDR
	be,a	Ladd_flo
	cmp	%TMP1, FLONUM_HDR
	cmp	%TMP0, COMPNUM_HDR
	be,a	Ladd_comp
	cmp	%TMP1, COMPNUM_HDR
	cmp	%TMP0, BIGNUM_HDR
	be,a	Ladd_big
	cmp	%TMP1, BIGNUM_HDR
	b	Lnumeric_error
	mov	EX_ADD, %TMP0
Ladd_flo:
	be,a	Ladd_flo2
	ldd	[ %RESULT + 8 - BVEC_TAG ], %f2
	! Got a flonum and something; check for compnum with 0i.
	cmp	%TMP1, COMPNUM_HDR
	bne	_contagion
	mov	MS_GENERIC_ADD, %TMP2
	ldd	[ %ARGREG2 - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Ladd_flo2
	ldd	[ %RESULT + 8 - BVEC_TAG ], %f2
	b	_contagion
	mov	MS_GENERIC_ADD, %TMP2
Ladd_flo2:
	ldd	[ %ARGREG2 + 8 - BVEC_TAG ], %f4
	b	_box_flonum
	faddd	%f2, %f4, %f2
Ladd_comp:
	be,a	Ladd_comp2
	ldd	[ %RESULT + 8 - BVEC_TAG ], %f2
	! op1 is a compnum, but perhaps op2 is a flonum and op1 has 0i.
	cmp	%TMP1, FLONUM_HDR
	bne	_contagion
	mov	MS_GENERIC_ADD, %TMP2
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Ladd_flo2
	ldd	[ %RESULT + 8 - BVEC_TAG ], %f2
	b	_contagion
	mov	MS_GENERIC_ADD, %TMP2
Ladd_comp2:
	ldd	[ %ARGREG2 + 8 - BVEC_TAG ], %f4
	ldd	[ %RESULT + 16 - BVEC_TAG ], %f6
	faddd	%f2, %f4, %f2
	ldd	[ %ARGREG2 + 16 - BVEC_TAG ], %f8
	b	_box_compnum
	faddd	%f6, %f8, %f4
Ladd_big:
	be,a	Ladd_big2
	mov	2, %TMP1
	b	_contagion
	mov	MS_GENERIC_ADD, %TMP2
Ladd_big2:
	b	internal_scheme_call
	mov	MS_BIGNUM_ADD, %TMP2
Ladd_vec:
	be,a	Ladd_vec2
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	_contagion
	mov	MS_GENERIC_ADD, %TMP2
Ladd_vec2:
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP1
	cmp	%TMP0, RATNUM_HDR
	be,a	Ladd_rat
	cmp	%TMP1, RATNUM_HDR
	cmp	%TMP0, RECTNUM_HDR
	be,a	Ladd_rect
	cmp	%TMP1, RECTNUM_HDR
	b	Lnumeric_error
	mov	EX_ADD, %TMP0
Ladd_rat:
	be,a	Ladd_rat2
	mov	2, %TMP1
	b	_contagion
	mov	MS_GENERIC_ADD, %TMP2
Ladd_rat2:
	b	internal_scheme_call
	mov	MS_RATNUM_ADD, %TMP2
Ladd_rect:
	be,a	Ladd_rect2
	mov	2, %TMP1
	b	_contagion
	mov	MS_GENERIC_ADD, %TMP2
Ladd_rect2:
	b	internal_scheme_call
	mov	MS_RECTNUM_ADD, %TMP2
Ladd_fix:
	sra	%RESULT, 2, %TMP0
	sra	%ARGREG2, 2, %TMP1
	b	_box_single_bignum
	add	%TMP0, %TMP1, %TMP0

! Subtraction.
! The fixnum case is handled in line, so if the operands are fixnums, we
! had an underflow (negative result too large in magnitude) and must box
! the result in a bignum.

EXTNAME(m_generic_sub):
	and	%RESULT, TAGMASK, %TMP0
	and	%ARGREG2, TAGMASK, %TMP1
	cmp	%TMP0, BVEC_TAG
	be,a	Lsub_bvec
	cmp	%TMP1, BVEC_TAG
	or	%RESULT, %ARGREG2, %TMP2
	andcc	%TMP2, 3, %g0
	be,a	Lsub_fix
	nop
	cmp	%TMP0, VEC_TAG
	be,a	Lsub_vec
	cmp	%TMP1, VEC_TAG
	b	_contagion
	mov	MS_GENERIC_SUB, %TMP2
Lsub_bvec:
	be,a	Lsub_bvec2
	ldub	[ %RESULT + 3 - BVEC_TAG ], %TMP0
	b	_contagion
	mov	MS_GENERIC_SUB, %TMP2
Lsub_bvec2:
	ldub	[ %ARGREG2 + 3 - BVEC_TAG ], %TMP1
	cmp	%TMP0, FLONUM_HDR
	be,a	Lsub_flo
	cmp	%TMP1, FLONUM_HDR
	cmp	%TMP0, COMPNUM_HDR
	be,a	Lsub_comp
	cmp	%TMP1, COMPNUM_HDR
	cmp	%TMP0, BIGNUM_HDR
	be,a	Lsub_big
	cmp	%TMP1, BIGNUM_HDR
	b	Lnumeric_error
	mov	EX_SUB, %TMP0
Lsub_flo:
	be,a	Lsub_flo2
	ldd	[ %RESULT + 8 - BVEC_TAG ], %f2
	! op1 is a flonum; maybe op2 is a compnum with 0i.
	cmp	%TMP1, COMPNUM_HDR
	bne	_contagion
	mov	MS_GENERIC_SUB, %TMP2
	ldd	[ %ARGREG2 - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Lsub_flo2
	ldd	[ %RESULT + 8 - BVEC_TAG ], %f2
	b	_contagion
	mov	MS_GENERIC_SUB, %TMP2
Lsub_flo2:
	ldd	[ %ARGREG2 + 8 - BVEC_TAG ], %f4
	b	_box_flonum
	fsubd	%f2, %f4, %f2
Lsub_comp:
	be,a	Lsub_comp2
	ldd	[ %RESULT + 8 - BVEC_TAG ], %f2
	! op1 is a compnum, but perhaps op2 is a flonum and op1 has 0i.
	cmp	%TMP1, FLONUM_HDR
	bne	_contagion
	mov	MS_GENERIC_SUB, %TMP2
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Lsub_flo2
	ldd	[ %RESULT + 8 - BVEC_TAG ], %f2
	b	_contagion
	mov	MS_GENERIC_SUB, %TMP2
Lsub_comp2:
	ldd	[ %ARGREG2 + 8 - BVEC_TAG ], %f4
	ldd	[ %RESULT + 16 - BVEC_TAG ], %f6
	fsubd	%f2, %f4, %f2
	ldd	[ %ARGREG2 + 16 - BVEC_TAG ], %f8
	b	_box_compnum
	fsubd	%f6, %f8, %f4
Lsub_big:
	be,a	Lsub_big2
	mov	2, %TMP1
	b	_contagion
	mov	MS_GENERIC_SUB, %TMP2
Lsub_big2:
	b	internal_scheme_call
	mov	MS_BIGNUM_SUB, %TMP2
Lsub_vec:
	be,a	Lsub_vec2
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	_contagion
	mov	MS_GENERIC_SUB, %TMP2
Lsub_vec2:
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP1
	cmp	%TMP0, RATNUM_HDR
	be,a	Lsub_rat
	cmp	%TMP1, RATNUM_HDR
	cmp	%TMP0, RECTNUM_HDR
	be,a	Lsub_rect
	cmp	%TMP1, RECTNUM_HDR
	b	Lnumeric_error
	mov	EX_SUB, %TMP0
Lsub_rat:
	be,a	Lsub_rat2
	mov	2, %TMP1
	b	_contagion
	mov	MS_GENERIC_SUB, %TMP2
Lsub_rat2:
	b	internal_scheme_call
	mov	MS_RATNUM_SUB, %TMP2
Lsub_rect:
	be,a	Lsub_rect2
	mov	2, %TMP1
	b	_contagion
	mov	MS_GENERIC_SUB, %TMP2
Lsub_rect2:
	b	internal_scheme_call
	mov	MS_RECTNUM_SUB, %TMP2
Lsub_fix:
	sra	%RESULT, 2, %TMP0
	sra	%ARGREG2, 2, %TMP1
	b	_box_single_bignum
	sub	%TMP0, %TMP1, %TMP0

! Multiplication.
! Fixnums may or may not be handled in line (depending on the availablity of
! hardware multiply on the target implementation); either way we must redo the
! operation here and check for the fixnum->bignum case.

EXTNAME(m_generic_mul):
	and	%RESULT, TAGMASK, %TMP0
	and	%ARGREG2, TAGMASK, %TMP1
	cmp	%TMP0, BVEC_TAG
	be,a	Lmul_bvec
	cmp	%TMP1, BVEC_TAG
	or	%RESULT, %ARGREG2, %TMP2
	andcc	%TMP2, 3, %g0
	be	Lmul_fix
	nop
	cmp	%TMP0, VEC_TAG
	be,a	Lmul_vec
	cmp	%TMP1, VEC_TAG
	b	_contagion
	mov	MS_GENERIC_MUL, %TMP2
Lmul_bvec:
	be,a	Lmul_bvec2
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	b	_contagion
	mov	MS_GENERIC_MUL, %TMP2
Lmul_bvec2:
	ldub	[ %ARGREG2 - BVEC_TAG + 3 ], %TMP1
	cmp	%TMP0, FLONUM_HDR
	be,a	Lmul_flo
	cmp	%TMP1, FLONUM_HDR
	cmp	%TMP0, COMPNUM_HDR
	be,a	Lmul_comp
	cmp	%TMP1, COMPNUM_HDR
	cmp	%TMP0, BIGNUM_HDR
	be,a	Lmul_big
	cmp	%TMP1, BIGNUM_HDR
	b	_contagion
	nop
Lmul_flo:
	be,a	Lmul_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	! op1 is flonum; but perhaps op2 is a compnum with 0i.
	cmp	%TMP1, COMPNUM_HDR
	bne,a	_contagion
	mov	MS_GENERIC_MUL, %TMP2
	ldd	[ %ARGREG2 - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Lmul_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	_contagion
	mov	MS_GENERIC_MUL, %TMP2
Lmul_flo2:
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f4
	b	_box_flonum
	fmuld	%f2, %f4, %f2
Lmul_comp:
	be,a	Lmul_comp2
	nop
	! op1 is compnum, but perhaps op2 is a flonum and op1 has 0i.
	cmp	%TMP1, FLONUM_HDR
	bne	_contagion
	mov	MS_GENERIC_MUL, %TMP2
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Lmul_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	_contagion
	mov	MS_GENERIC_MUL, %TMP2
Lmul_comp2:
	! Needs scheduling. 
	! After scheduling, move the first load into the slot above.
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f6
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f8
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f10
	ldd	[ %ARGREG2 - BVEC_TAG + 16 ], %f12
	fmuld	%f6, %f10, %f14
	fmuld	%f8, %f12, %f16
	fsubd	%f14, %f16, %f2
	fmuld	%f8, %f10, %f18
	fmuld	%f16, %f12, %f20
	faddd	%f18, %f20, %f4
	b	_box_compnum
	nop
Lmul_big:
	be,a	Lmul_big2
	mov	2, %TMP1
	b	_contagion
	mov	MS_GENERIC_MUL, %TMP2
Lmul_big2:
	b	internal_scheme_call
	mov	MS_BIGNUM_MUL, %TMP2
Lmul_vec:
	be,a	Lmul_vec2
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	_contagion
	mov	MS_GENERIC_MUL, %TMP2
Lmul_vec2:
	ldub	[ %ARGREG2 - VEC_TAG + 3 ], %TMP1
	cmp	%TMP0, RATNUM_HDR
	be,a	Lmul_rat
	cmp	%TMP1, RATNUM_HDR
	cmp	%TMP0, RECTNUM_HDR
	be,a	Lmul_rect
	cmp	%TMP1, RECTNUM_HDR
	b	Lnumeric_error
	mov	EX_MUL, %TMP0
Lmul_rat:
	be,a	Lmul_rat2
	mov	2, %TMP1
	b	_contagion
	mov	MS_GENERIC_MUL, %TMP2
Lmul_rat2:
	b	internal_scheme_call
	mov	MS_RATNUM_MUL, %TMP2
Lmul_rect:
	be,a	Lmul_rect2
	mov	2, %TMP1
	b	_contagion
	mov	MS_GENERIC_MUL, %TMP2
Lmul_rect2:
	b	internal_scheme_call
	mov	MS_RECTNUM_MUL, %TMP2
Lmul_fix:
	! Have to shift both operands to avoid disasters with signs.
	save	%sp, -104, %sp
	!st	%STKLIM, [ %fp-4 ]
	sra	%SAVED_RESULT, 2, %o0
	call	.mul
	sra	%SAVED_ARGREG2, 2, %o1
	!ld	[ %fp-4 ], %STKLIM

	! Check to see if it will fit in a fixnum (tentatively)
	cmp	%o1, 0
	be	Lmul_fix1
	nop
	cmp	%o1, -1
	be	Lmul_fix4
	nop

Lmul_fixy:
	! Won't fit in a fixnum
	cmp	%o1, 0
	bge	Lmul_fixx
	mov	0, %SAVED_TMP2
	not	%o0, %o0
	not	%o1, %o1
	addcc	%o0, 1, %o0
	addx	%o1, 0, %o1
	mov	1, %SAVED_TMP2
Lmul_fixx:
	cmp	%o1, 0				! fit in a one-word bignum?
	bne	Lmul_fix3			! yes
	nop

	! Fits in one-word bignum. Mush together and box.
	mov	%o0, %SAVED_TMP0
	b	_box_single_positive_bignum
	restore

Lmul_fix3:
	! Fits in two-word bignum. Mush together and box.
	mov	%o1, %SAVED_TMP1
	mov	%o0, %SAVED_TMP0
	b	_box_double_positive_bignum
	restore

Lmul_fix1:
	! Might fit in a fixnum.
	set	0xE0000000, %o2
	andcc	%o0, %o2, %o3
	be,a	Lmul_fix2			! fits in a fixnum.
	sll	%o0, 2, %SAVED_RESULT
	b	Lmul_fixy
	nop
Lmul_fix4:
	set	0xE0000000, %o2
	andcc	%o0, %o2, %o3
	cmp	%o3, %o2
	be,a	Lmul_fix2			! ditto (negative)
	sll	%o0, 2, %SAVED_RESULT
	b	Lmul_fixy			! must box
	nop
Lmul_fix2:
	jmp	%i7+8
	restore

! Division.
! Fixnum case may or may not be handled in line (depending on the availability
! of hardware divide on the target architecture); either way we have to redo
! the operation here and check for the fixnum->bignum case.

EXTNAME(m_generic_div):
	and	%RESULT, TAGMASK, %TMP0
	and	%ARGREG2, TAGMASK, %TMP1
	cmp	%TMP0, BVEC_TAG
	be,a	Ldiv_bvec
	cmp	%TMP1, BVEC_TAG
	or	%RESULT, %ARGREG2, %TMP2
	andcc	%TMP2, 3, %g0
	be	Ldiv_fix
	nop
	cmp	%TMP0, VEC_TAG
	be,a	Ldiv_vec
	cmp	%TMP1, VEC_TAG
	b	_contagion
	mov	MS_GENERIC_DIV, %TMP2
Ldiv_bvec:
	be,a	Ldiv_bvec2
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	b	_contagion
	mov	MS_GENERIC_DIV, %TMP2
Ldiv_bvec2:
	ldub	[ %ARGREG2 - BVEC_TAG + 3 ], %TMP1
	cmp	%TMP0, FLONUM_HDR
	be,a	Ldiv_flo
	cmp	%TMP1, FLONUM_HDR
	cmp	%TMP0, COMPNUM_HDR
	be,a	Ldiv_comp
	cmp	%TMP1, COMPNUM_HDR
	cmp	%TMP0, BIGNUM_HDR
	be,a	Ldiv_big
	cmp	%TMP1, BIGNUM_HDR
	b	_contagion
	mov	MS_GENERIC_DIV, %TMP2
Ldiv_flo:
	be,a	Ldiv_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	! op1 is flonum; but perhaps op2 is a compnum with 0i.
	cmp	%TMP1, COMPNUM_HDR
	bne,a	_contagion
	mov	MS_GENERIC_DIV, %TMP2
	ldd	[ %ARGREG2 - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Ldiv_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	_contagion
	mov	MS_GENERIC_DIV, %TMP2
Ldiv_flo2:
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f4
	b	_box_flonum
	fdivd	%f2, %f4, %f2
Ldiv_comp:
	be,a	Ldiv_comp2
	nop
	! op1 is compnum, but perhaps op2 is a flonum and op1 has 0i.
	cmp	%TMP1, FLONUM_HDR
	bne	_contagion
	mov	MS_GENERIC_DIV, %TMP2
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Ldiv_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	_contagion
	mov	MS_GENERIC_DIV, %TMP2
Ldiv_comp2:
	! needs scheduling badly.
	! when scheduled, move one instruction into the slot above.

	ldd	[ %RESULT - BVEC_TAG + 8 ], %f6
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f8
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f10
	ldd	[ %ARGREG2 - BVEC_TAG + 16 ], %f12
	fabsd	%f10, %f14
	fabsd	%f12, %f16
	fcmpd	%f14, %f16
	nop
	fbl	Ldiv_comp3
	nop

	! case 1: (>= (abs (real-part b)) (abs (imag-part a)))

	fdivd	%f12, %f10, %f14  ! r:   (/ (imag-part b) (real-part b))
	fmuld	%f14, %f12, %f16
	faddd	%f10, %f16, %f16  ! den: (+ (real-part b) (* r (imag-part b)))

	fmuld	%f14, %f8, %f18
	faddd	%f6, %f18, %f2
	fdivd	%f2, %f16, %f2	  ! c.r

	fmuld	%f14, %f6, %f18
	fsubd	%f8, %f18, %f4
	fdivd	%f4, %f16, %f4	  ! c.i
	b	_box_compnum
	nop

Ldiv_comp3:

	! case 2: (< (abs (real-part b)) (abs (imag-part a)))

	fdivd	%f10, %f12, %f14  ! r:   (/ (real-part b) (imag-part b))
	fmuld	%f14, %f10, %f16
	faddd	%f12, %f16, %f16  ! den: (+ (imag-part b) (* r (real-part b)))

	fmuld	%f6, %f16, %f18
	faddd	%f18, %f8, %f2
	fdivd	%f2, %f16, %f2	  ! c.r

	fmuld	%f8, %f16, %f18
	fsubd	%f18, %f6, %f4
	fdivd	%f4, %f16, %f4
	b	_box_compnum
	nop

Ldiv_big:
	be,a	Ldiv_big2
	mov	2, %TMP1
	b	_contagion
	mov	MS_GENERIC_DIV, %TMP2
Ldiv_big2:
	b	internal_scheme_call
	mov	MS_BIGNUM_DIV, %TMP2
Ldiv_vec:
	be,a	Ldiv_vec2
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	_contagion
	mov	MS_GENERIC_DIV, %TMP2
Ldiv_vec2:
	ldub	[ %ARGREG2 - VEC_TAG + 3 ], %TMP1
	cmp	%TMP0, RATNUM_HDR
	be,a	Ldiv_rat
	cmp	%TMP1, RATNUM_HDR
	cmp	%TMP0, RECTNUM_HDR
	be,a	Ldiv_rect
	cmp	%TMP1, RECTNUM_HDR
	b	Lnumeric_error
	mov	EX_DIV, %TMP0
Ldiv_rat:
	be,a	Ldiv_rat2
	mov	2, %TMP1
	b	_contagion
	mov	MS_GENERIC_DIV, %TMP2
Ldiv_rat2:
	b	internal_scheme_call
	mov	MS_RATNUM_DIV, %TMP2
Ldiv_rect:
	be,a	Ldiv_rect2
	mov	2, %TMP1
	b	_contagion
	mov	MS_GENERIC_DIV, %TMP2
Ldiv_rect2:
	b	internal_scheme_call
	mov	MS_RECTNUM_DIV, %TMP2
Ldiv_fix:
	! Oh, joy.
	! If the remainder of the division is 0, then we return a result as
	! expected; otherwise, the operation will generate a ratnum and the
	! whole thing is pushed into Scheme.

#ifdef CHECK_DIVISION_BY_ZERO
	cmp	%ARGREG2, 0
	bne,a	1f
	nop
	b	Lnumeric_error
	mov	EX_DIV, %TMP0
1:
#endif
	save	%sp, -104, %sp
	!st	%STKLIM, [ %fp-4 ]
	sra	%SAVED_RESULT, 2, %o0
	call	.rem
	sra	%SAVED_ARGREG2, 2, %o1
	!ld	[ %fp-4 ], %STKLIM
	cmp	%o0, 0
	bne,a	Ldiv_fix2
	restore
	! no need to store STKLIM again
	sra	%SAVED_RESULT, 2, %o0
	call	.div
	sra	%SAVED_ARGREG2, 2, %o1
	!ld	[ %fp-4 ], %STKLIM
	sll	%o0, 2, %SAVED_RESULT
	jmp	%i7+8
	restore
Ldiv_fix2:
	mov	2, %TMP1
	b	internal_scheme_call
	mov	MS_FIXNUM2RATNUM_DIV, %TMP2

! Quotient.
!
! Quotient must work on all integer operands, including flonums and compnums
! which are representable as integers. In order to preserve the programmer's
! sanity, only two cases are handled in millicode; all other arguments are 
! passed to the "generic-quotient" procedure (in Scheme).
!
! The two cases handled in millicode are:
!  - both operands are fixnums
!  - the lhs is a positive 32-bit bignum and the rhs is a positive fixnum
! The second case complicates the code but makes bignum arithmetic
! more pleasant to implement in Scheme.

EXTNAME(m_generic_quo):
	or	%RESULT, %ARGREG2, %TMP0
	andcc	%TMP0, 3, %g0
	bne	Lquotient1
	nop

	! Case 1: both fixnums
	! Should probably conditionalize this on whether the machine has
	! hardware divide or not; should save us some cycles. In fact,
	! the fixnum case will then be small enough to move in-line.
#ifdef CHECK_DIVISION_BY_ZERO
	cmp	%ARGREG2, 0
	bne,a	1f
	nop
	b	Lnumeric_error
	mov	EX_QUOTIENT, %TMP0
1:
#endif
	save	%sp, -104, %sp
	!st	%STKLIM, [ %fp-4 ]
	sra	%SAVED_RESULT, 2, %o0
	call	.div
	sra	%SAVED_ARGREG2, 2, %o1
	!ld	[ %fp-4 ], %STKLIM
	sll	%o0, 2, %SAVED_RESULT
	jmp	%i7+8
	restore
Lquotient1:
	set	TRUE_CONST, %ARGREG3
	!FALLTHROUGH

! Common code for bignum-by-fixnum division for quotient and remainder.
! ARGREG3 is either #t (quotient) or #f (remainder).

Lquotrem:
	! Test for case 2
	andcc	%ARGREG2, 3, %g0			! fixnum?
	bne	Lquotrem2
	srl	%ARGREG2, 31, %TMP0
	andcc	%TMP0, 1, %g0				! bit set?
	bne	Lquotrem2
	nop
	and	%RESULT, TAGMASK, %TMP0
	cmp	%TMP0, BVEC_TAG				! bytevector-like?
	bne	Lquotrem2
	nop
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	cmp	%TMP0, BIGNUM_HDR			! bignum?
	bne	Lquotrem2
	nop
	lduh	[ %RESULT - BVEC_TAG + 6 ], %TMP0	! get digitcount
	cmp	%TMP0, 1				! 1 digit?
	bne	Lquotrem2
	nop
	lduh	[ %RESULT - BVEC_TAG + 4 ], %TMP0	! get sign
	cmp	%TMP0, 0				! positive?
	bne	Lquotrem2
	nop

	! Finally -- RESULT is a 32-bit bignum, ARGREG2 is a fixnum.
	! Both are nonnegative.

	save	%sp, -104, %sp
	!st	%STKLIM, [ %fp-4 ]
	ld	[ %SAVED_RESULT - BVEC_TAG + 8], %o0

	cmp 	%SAVED_ARGREG3, TRUE_CONST
	bne	1f
	nop
	call	.udiv,2
	sra	%SAVED_ARGREG2, 2, %o1
	b	2f
	nop
1:	call	.urem,2
	sra	%SAVED_ARGREG2, 2, %o1
2:
	!ld	[ %fp-4 ], %STKLIM

	! Will it fit in a fixnum?
	sll	%o0, 2, %o2
	sra	%o2, 2, %o2
	cmp	%o0, %o2
	bne	Lquotrem3
	nop
	! Fixnumize and exit
	sll	%o0, 2, %SAVED_RESULT
	jmp	%i7+8
	restore
Lquotrem3:
	mov	%o0, %SAVED_TMP0
	mov	0, %SAVED_TMP2
	b	_box_single_positive_bignum
	restore

! Other types.

Lquotrem2:
	mov	MS_HEAVY_REMAINDER, %TMP2
	cmp	%ARGREG3, TRUE_CONST
	be,a	1f
	mov	MS_HEAVY_QUOTIENT, %TMP2
1:	b	internal_scheme_call
	mov	2, %TMP1

! Remainder.
! Same treatment of arguments as for quotient, above.
!
! The .rem procedure produces the correct signs and values for "remainder".

EXTNAME(m_generic_rem):
	or	%RESULT, %ARGREG2, %TMP0
	andcc	%TMP0, 3, %g0
	bne	Lremainder1
	nop

#ifdef CHECK_DIVISION_BY_ZERO
	cmp	%ARGREG2, 0
	bne,a	1f
	nop
	b	Lnumeric_error
	mov	EX_REMAINDER, %TMP0
1:
#endif
	! Both fixnums
	save	%sp, -104, %sp
	!st	%STKLIM, [ %fp-4 ]
	sra	%SAVED_RESULT, 2, %o0
	call	.rem
	sra	%SAVED_ARGREG2, 2, %o1
	!ld	[ %fp-4 ], %STKLIM
	sll	%o0, 2, %SAVED_RESULT
	jmp	%i7+8
	restore

Lremainder1:
	b	Lquotrem
	set	FALSE_CONST, %ARGREG3


! Modulus. OBSOLETE

EXTNAME(m_generic_mod):
	call	EXTNAME(abort)
	nop


! Negation
! The fixnum case is always handled in line, except when the number is
! the largest negative fixnum.

EXTNAME(m_generic_neg):
	and	%RESULT, TAGMASK, %TMP0
	cmp	%TMP0, BVEC_TAG
	be,a	Lneg_bvec
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	cmp	%TMP0, VEC_TAG
	be,a	Lneg_vec
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	andcc	%RESULT, 3, %g0
	bne,a	Lnumeric_error
	mov	EX_NEG, %TMP0
	! fixnum: subtract from 0.
	mov	%RESULT, %ARGREG2
	b	EXTNAME(m_generic_sub)
	mov	0, %RESULT
Lneg_bvec:
	cmp	%TMP0, FLONUM_HDR
	be,a	Lneg_flo
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	cmp	%TMP0, COMPNUM_HDR
	be,a	Lneg_comp
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	cmp	%TMP0, BIGNUM_HDR
	be,a	Lneg_big
	mov	1, %TMP1
	b	Lnumeric_error
	mov	EX_NEG, %TMP0
Lneg_flo:
	b	_box_flonum
	fnegd	%f2, %f2
Lneg_comp:
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f4
	fnegd	%f2, %f2
	b	_box_compnum
	fnegd	%f4, %f4
Lneg_big:
	b	internal_scheme_call
	mov	MS_BIGNUM_NEGATE, %TMP2	
Lneg_vec:
	cmp	%TMP0, RATNUM_HDR
	be,a	Lneg_rat
	mov	1, %TMP1
	cmp	%TMP0, RECTNUM_HDR
	be,a	Lneg_rect
	mov	1, %TMP1
	b	Lnumeric_error
	mov	EX_NEG, %TMP0
Lneg_rat:
	b	internal_scheme_call
	mov	MS_RATNUM_NEGATE, %TMP2
Lneg_rect:
	b	internal_scheme_call
	mov	MS_RECTNUM_NEGATE, %TMP2

! Absolute value.
! The fixnum case is always handled in line.
! Probably untested; the compiler expands (abs x) in-line.

EXTNAME(m_generic_abs):
	and	%RESULT, TAGMASK, %TMP0
	cmp	%TMP0, BVEC_TAG
	be,a	Labs_bvec
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	cmp	%TMP0, VEC_TAG
	be,a	Labs_vec
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	Lnumeric_error
	mov	EX_ABS, %TMP0
Labs_bvec:
	cmp	%TMP0, FLONUM_HDR
	be,a	Labs_flo
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	cmp	%TMP0, COMPNUM_HDR
	be,a	Labs_comp
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	cmp	%TMP0, BIGNUM_HDR
	be,a	Labs_big
	mov	1, %TMP1
	b	Lnumeric_error
	mov	EX_ABS, %TMP0
Labs_flo:
	b	_box_flonum
	fabsd	%f2, %f2
Labs_comp:
	b	Lnumeric_error
	mov	EX_ABS, %TMP0
Labs_big:
	b	internal_scheme_call
	mov	MS_BIGNUM_ABS, %TMP2	
Labs_vec:
	cmp	%TMP0, RATNUM_HDR
	be,a	Labs_rat
	mov	1, %TMP1
	b	Lnumeric_error
	mov	EX_ABS, %TMP0
Labs_rat:
	b	internal_scheme_call
	mov	MS_RATNUM_ABS, %TMP2

! Test for zero.
! The fixnum case is always handled in line, but since the ratnum case
! is handled by doing (ZEROP (NUMERATOR x)), we handle fixnums here
! as well.
!
! In principle, there are no  bignums, rectnums, or ratnums which are zero.
! However, parts of the libraries temporarily invalidate this assumption,
! and it's convenient to support that here. Hence some extra complexity.
! However, we do not go all the way; a 0 rectnum has to have 0 fixnums in
! both slots.

EXTNAME(m_generic_zerop):
	and	%RESULT, TAGMASK, %TMP0
	cmp	%TMP0, BVEC_TAG
	be,a	Lzero_bvec
	ldub	[ %RESULT + 3 - BVEC_TAG ], %TMP0
	cmp	%TMP0, VEC_TAG
	be,a	Lzero_vec
	ldub	[ %RESULT + 3 - VEC_TAG ], %TMP0
	andcc	%RESULT, 3, %g0
	bne,a	Lnumeric_error
	mov	EX_ZEROP, %TMP0
	cmp	%RESULT, 0
	mov	TRUE_CONST, %RESULT
	bne,a	.+8
	mov	FALSE_CONST, %RESULT
	jmp	%o7+8
	nop
Lzero_bvec:
	cmp	%TMP0, FLONUM_HDR
	be,a	Lzero_flo
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	cmp	%TMP0, COMPNUM_HDR
	be,a	Lzero_comp
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	cmp	%TMP0, BIGNUM_HDR
	be,a	Lzero_big
	ld	[ %RESULT - BVEC_TAG + 4 ], %TMP0
	b	Lnumeric_error
	mov	EX_ZEROP, %TMP0
Lzero_flo:
	fcmpd	%f0, %f2
	mov	FALSE_CONST, %RESULT
	fbe,a	.+8
	mov	TRUE_CONST, %RESULT
	jmp	%o7+8
	nop
Lzero_comp:
	fcmpd	%f0, %f2
	ldd	[ %RESULT + 16 - BVEC_TAG ], %f4
	.empty
	fbne,a	Lzero_num
	mov	FALSE_CONST, %RESULT
	fcmpd	%f0, %f4
	mov	FALSE_CONST, %RESULT
	fbe,a	.+8
	mov	TRUE_CONST, %RESULT
	jmp	%o7+8
	nop
Lzero_big:
	set	0xFFFF, %TMP1
	andcc	%TMP0, %TMP1, %g0	! get digitcount
	mov	TRUE_CONST, %RESULT
	bne,a	.+8
	mov	FALSE_CONST, %RESULT
	jmp	%o7+8
	nop
Lzero_vec:
	cmp	%TMP0, RATNUM_HDR
	be,a	EXTNAME(m_generic_zerop)
	ld	[ %RESULT - VEC_TAG + 4 ], %RESULT
	cmp	%TMP0, RECTNUM_HDR
	be,a	Lzero_rect
	ld	[ %RESULT - VEC_TAG + 4 ], %RESULT
	b	Lnumeric_error
	mov	EX_ZEROP, %TMP0
Lzero_rect:
	cmp	%TMP0, 0
	bne,a	Lzero_num
	mov	FALSE_CONST, %RESULT
	ld	[ %RESULT - VEC_TAG + 8 ], %TMP0
	cmp	%TMP0, 0
	bne,a	Lzero_num
	mov	FALSE_CONST, %RESULT
	mov	TRUE_CONST, %RESULT	
Lzero_num:
	jmp	%o7+8
	nop

! Equality.
! The fixnum case is handled in line, _but_ may have overflowed, so must
! be handled again.

EXTNAME(m_generic_equalp):
	and	%RESULT, TAGMASK, %TMP0
	and	%ARGREG2, TAGMASK, %TMP1
	cmp	%TMP0, BVEC_TAG
	be,a	Lequal_bvec
	cmp	%TMP1, BVEC_TAG
	cmp	%TMP0, VEC_TAG
	be,a	Lequal_vec
	cmp	%TMP1, VEC_TAG
! fixnum case
	or	%RESULT, %ARGREG2, %TMP0
	andcc	%TMP0, 3, %g0
	bne	Lequal_generic
	subcc	%RESULT, %ARGREG2, %g0
	mov	FALSE_CONST, %RESULT
	be,a	.+8
	mov	TRUE_CONST, %RESULT
	jmp	%o7+8
	nop
! generic
Lequal_generic:
	b	_econtagion
	mov	MS_GENERIC_EQUAL, %TMP2
Lequal_bvec:
	be,a	Lequal_bvec2
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	b	_econtagion
	mov	MS_GENERIC_EQUAL, %TMP2
Lequal_bvec2:
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP1
	cmp	%TMP0, FLONUM_HDR
	be,a	Lequal_flo
	cmp	%TMP1, FLONUM_HDR
	cmp	%TMP0, COMPNUM_HDR
	be,a	Lequal_comp
	cmp	%TMP1, COMPNUM_HDR
	cmp	%TMP0, BIGNUM_HDR
	be,a	Lequal_big
	cmp	%TMP1, BIGNUM_HDR
	b	Lnumeric_error
	mov	EX_EQUALP, %TMP0
Lequal_flo:
	be,a	Lequal_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	cmp	%TMP1, COMPNUM_HDR
	bne,a	_econtagion
	mov	MS_GENERIC_EQUAL, %TMP2
	ldd	[ %ARGREG2 - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Lequal_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	_econtagion
	mov	MS_GENERIC_EQUAL, %TMP2
Lequal_flo2:
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f4
	fcmpd	%f2, %f4
	mov	FALSE_CONST, %RESULT
	fbe,a	.+8
	mov	TRUE_CONST, %RESULT
	jmp	%o7+8
	nop
Lequal_comp:
	be,a	Lequal_comp2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	cmp	%TMP1, FLONUM_HDR
	bne,a	_econtagion
	mov	MS_GENERIC_EQUAL, %TMP2
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Lequal_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	_econtagion
	mov	MS_GENERIC_EQUAL, %TMP2
Lequal_comp2:
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f4
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f6
	fcmpd	%f2, %f4
	ldd	[ %ARGREG2 - BVEC_TAG + 16 ], %f8
	.empty
	fbe,a	Lequal_comp3
	fcmpd	%f6, %f8
	jmp	%o7+8
	.empty				! the next mov goes here
Lequal_comp3:
	mov	FALSE_CONST, %RESULT
	fbe,a	.+8
	mov	TRUE_CONST, %RESULT
	jmp	%o7+8
	nop
Lequal_big:
	be,a	Lequal_big2
	mov	2, %TMP1
	b	_econtagion
	mov	MS_GENERIC_EQUAL, %TMP2
Lequal_big2:
	b	internal_scheme_call
	mov	MS_BIGNUM_EQUAL, %TMP2
Lequal_vec:
	be,a	Lequal_vec2
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	_econtagion
	mov	MS_GENERIC_EQUAL, %TMP2
Lequal_vec2:
	ldub	[ %ARGREG2 - VEC_TAG + 3 ], %TMP1
	cmp	%TMP0, RATNUM_HDR
	be,a	Lequal_rat
	cmp	%TMP1, RATNUM_HDR
	cmp	%TMP0, RECTNUM_HDR
	be,a	Lequal_rect
	cmp	%TMP1, RECTNUM_HDR
	b	Lnumeric_error
	mov	EX_EQUALP, %TMP0
Lequal_rat:
	be,a	Lequal_rat2
	mov	2, %TMP1
	b	_econtagion
	mov	MS_GENERIC_EQUAL, %TMP2
Lequal_rat2:
	b	internal_scheme_call
	mov	MS_RATNUM_EQUAL, %TMP2
Lequal_rect:
	be,a	Lequal_rect2
	mov	2, %TMP1
	b	_econtagion
	mov	MS_GENERIC_EQUAL, %TMP2
Lequal_rect2:
	b	internal_scheme_call
	mov	MS_RECTNUM_EQUAL, %TMP2

! Less-than.
! Fixnums are done in-line.
! Compnums and rectnums are not in the domain of this function, but compnums
! with a 0 imaginary part are and have to be handled specially.

EXTNAME(m_generic_lessp):
	and	%RESULT, TAGMASK, %TMP0
	and	%ARGREG2, TAGMASK, %TMP1
	cmp	%TMP0, BVEC_TAG
	be,a	Lless_bvec
	cmp	%TMP1, BVEC_TAG
	cmp	%TMP0, VEC_TAG
	be,a	Lless_vec
	cmp	%TMP1, VEC_TAG
! fixnum case
	or	%RESULT, %ARGREG2, %TMP0
	andcc	%TMP0, 3, %g0
	bne	Lless_generic
	subcc	%RESULT, %ARGREG2, %g0
	mov	FALSE_CONST, %RESULT
	bl,a	.+8
	mov	TRUE_CONST, %RESULT
	jmp	%o7+8
	nop
! generic
Lless_generic:
	b	_pcontagion
	mov	MS_GENERIC_LESS, %TMP2
Lless_bvec:
	be,a	Lless_bvec2
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	b	_pcontagion
	mov	MS_GENERIC_LESS, %TMP2
Lless_bvec2:
	ldub	[ %ARGREG2 - BVEC_TAG + 3 ], %TMP1
	cmp	%TMP0, FLONUM_HDR
	be,a	Lless_flo
	cmp	%TMP1, FLONUM_HDR
	cmp	%TMP0, COMPNUM_HDR
	be,a	Lless_comp
	cmp	%TMP1, COMPNUM_HDR
	cmp	%TMP0, BIGNUM_HDR
	be,a	Lless_big
	cmp	%TMP1, BIGNUM_HDR
	b	Lnumeric_error
	mov	EX_LESSP, %TMP0
Lless_flo:
	be,a	Lless_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	cmp	%TMP1, COMPNUM_HDR
	bne,a	_pcontagion
	mov	MS_GENERIC_LESS, %TMP2
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Lless_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	_pcontagion
	mov	MS_GENERIC_LESS, %TMP2
Lless_flo2:
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f4
	fcmpd	%f2, %f4
	mov	FALSE_CONST, %RESULT
	fbl,a	.+8
	mov	TRUE_CONST, %RESULT
	jmp	%o7+8
	nop
Lless_comp:
	be,a	Lless_comp2
	nop
	! op1 was a compnum, op2 was not. If op2 is a flonum and op1 has
	! 0i, then we're fine.
	cmp	%TMP1, FLONUM_HDR
	bne,a	_pcontagion
	mov	MS_GENERIC_LESS, %TMP2
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	be,a	Lless_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	Lnumeric_error
	mov	EX_LESSP, %TMP0
Lless_comp2:
	! op1 and op2 were both compnums; if they both have 0i, then
	! we're fine.
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	ldd	[ %ARGREG2 - BVEC_TAG + 16 ], %f4
	fcmpd	%f0, %f2
	nop
	fbne,a	Lnumeric_error
	mov	EX_LESSP, %TMP0
	fcmpd	%f0, %f4
	nop
	fbne,a	Lnumeric_error
	mov	EX_LESSP, %TMP0
	b	Lless_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
Lless_big:
	be,a	Lless_big2
	mov	2, %TMP1
	b	_pcontagion
	mov	MS_GENERIC_LESS, %TMP2
Lless_big2:
	b	internal_scheme_call
	mov	MS_BIGNUM_LESS, %TMP2
Lless_vec:
	be,a	Lless_vec2
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	_pcontagion
	mov	MS_GENERIC_LESS, %TMP2
Lless_vec2:
	ldub	[ %ARGREG2 - VEC_TAG + 3 ], %TMP1
	cmp	%TMP0, RATNUM_HDR
	be,a	Lless_rat
	cmp	%TMP1, RATNUM_HDR
	b	Lnumeric_error
	mov	EX_LESSP, %TMP0
Lless_rat:
	be,a	Lless_rat2
	mov	2, %TMP1
	b	_pcontagion
	mov	MS_GENERIC_LESS, %TMP2
Lless_rat2:
	b	internal_scheme_call
	mov	MS_RATNUM_LESS, %TMP2

! Less-than-or-equal.
! Fixnums are done in-line.
! Compnums and rectnums are not in the domain of this function, but compnums
! with a 0 imaginary part are and have to be handled specially.

EXTNAME(m_generic_less_or_equalp):
	and	%RESULT, TAGMASK, %TMP0
	and	%ARGREG2, TAGMASK, %TMP1
	cmp	%TMP0, BVEC_TAG
	be,a	Llesseq_bvec
	cmp	%TMP1, BVEC_TAG
	cmp	%TMP0, VEC_TAG
	be,a	Llesseq_vec
	cmp	%TMP1, VEC_TAG
! fixnum case
	or	%RESULT, %ARGREG2, %TMP0
	andcc	%TMP0, 3, %g0
	bne	Llesseq_generic
	subcc	%RESULT, %ARGREG2, %g0
	mov	FALSE_CONST, %RESULT
	ble,a	.+8
	mov	TRUE_CONST, %RESULT
	jmp	%o7+8
	nop
! generic
Llesseq_generic:
	b	_pcontagion
	mov	MS_GENERIC_LESSEQ, %TMP2
Llesseq_bvec:
	be,a	Llesseq_bvec2
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	b	_pcontagion
	mov	MS_GENERIC_LESSEQ, %TMP2
Llesseq_bvec2:
	ldub	[ %ARGREG2 - BVEC_TAG + 3 ], %TMP1
	cmp	%TMP0, FLONUM_HDR
	be,a	Llesseq_flo
	cmp	%TMP1, FLONUM_HDR
	cmp	%TMP0, COMPNUM_HDR
	be,a	Llesseq_comp
	cmp	%TMP1, COMPNUM_HDR
	cmp	%TMP0, BIGNUM_HDR
	be,a	Llesseq_big
	cmp	%TMP1, BIGNUM_HDR
	b	Lnumeric_error
	mov	EX_LESSEQP, %TMP0
Llesseq_flo:
	be,a	Llesseq_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	cmp	%TMP1, COMPNUM_HDR
	bne,a	_pcontagion
	mov	MS_GENERIC_LESSEQ, %TMP2
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Llesseq_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	_pcontagion
	mov	MS_GENERIC_LESSEQ, %TMP2
Llesseq_flo2:
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f4
	fcmpd	%f2, %f4
	mov	FALSE_CONST, %RESULT
	fble,a	.+8
	mov	TRUE_CONST, %RESULT
	jmp	%o7+8
	nop
Llesseq_comp:
	be,a	Llesseq_comp2
	nop
	! op1 was a compnum, op2 was not. If op2 is a flonum and op1 has
	! 0i, then we're fine.
	cmp	%TMP1, FLONUM_HDR
	bne,a	_pcontagion
	mov	MS_GENERIC_LESSEQ, %TMP2
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	be,a	Llesseq_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	Lnumeric_error
	mov	EX_LESSEQP, %TMP0
Llesseq_comp2:
	! op1 and op2 were both compnums; if they both have 0i, then
	! we're fine.
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	ldd	[ %ARGREG2 - BVEC_TAG + 16 ], %f4
	fcmpd	%f0, %f2
	nop
	fbne,a	Lnumeric_error
	mov	EX_LESSEQP, %TMP0
	fcmpd	%f0, %f4
	nop
	fbne,a	Lnumeric_error
	mov	EX_LESSEQP, %TMP0
	b	Llesseq_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
Llesseq_big:
	be,a	Llesseq_big2
	mov	2, %TMP1
	b	_pcontagion
	mov	MS_GENERIC_LESSEQ, %TMP2
Llesseq_big2:
	b	internal_scheme_call
	mov	MS_BIGNUM_LESSEQ, %TMP2
Llesseq_vec:
	be,a	Llesseq_vec2
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	_pcontagion
	mov	MS_GENERIC_LESSEQ, %TMP2
Llesseq_vec2:
	ldub	[ %ARGREG2 - VEC_TAG + 3 ], %TMP1
	cmp	%TMP0, RATNUM_HDR
	be,a	Llesseq_rat
	cmp	%TMP1, RATNUM_HDR
	b	Lnumeric_error
	mov	EX_LESSEQP, %TMP0
Llesseq_rat:
	be,a	Llesseq_rat2
	mov	2, %TMP1
	b	_pcontagion
	mov	MS_GENERIC_LESSEQ, %TMP2
Llesseq_rat2:
	b	internal_scheme_call
	mov	MS_RATNUM_LESSEQ, %TMP2

! Greater-than.
! Fixnums are done in-line.
! Compnums and rectnums are not in the domain of this function, but compnums
! with a 0 imaginary part are and have to be handled specially.

EXTNAME(m_generic_greaterp):
	and	%RESULT, TAGMASK, %TMP0
	and	%ARGREG2, TAGMASK, %TMP1
	cmp	%TMP0, BVEC_TAG
	be,a	Lgreater_bvec
	cmp	%TMP1, BVEC_TAG
	cmp	%TMP0, VEC_TAG
	be,a	Lgreater_vec
	cmp	%TMP1, VEC_TAG
! fixnum case
	or	%RESULT, %ARGREG2, %TMP0
	andcc	%TMP0, 3, %g0
	bne	Lgreater_generic
	subcc	%RESULT, %ARGREG2, %g0
	mov	FALSE_CONST, %RESULT
	bg,a	.+8
	mov	TRUE_CONST, %RESULT
	jmp	%o7+8
	nop
! generic
Lgreater_generic:
	b	_pcontagion
	mov	MS_GENERIC_GREATER, %TMP2
Lgreater_bvec:
	be,a	Lgreater_bvec2
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	b	_pcontagion
	mov	MS_GENERIC_GREATER, %TMP2
Lgreater_bvec2:
	ldub	[ %ARGREG2 - BVEC_TAG + 3 ], %TMP1
	cmp	%TMP0, FLONUM_HDR
	be,a	Lgreater_flo
	cmp	%TMP1, FLONUM_HDR
	cmp	%TMP0, COMPNUM_HDR
	be,a	Lgreater_comp
	cmp	%TMP1, COMPNUM_HDR
	cmp	%TMP0, BIGNUM_HDR
	be,a	Lgreater_big
	cmp	%TMP1, BIGNUM_HDR
	b	Lnumeric_error
	mov	EX_GREATERP, %TMP0
Lgreater_flo:
	be,a	Lgreater_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	cmp	%TMP1, COMPNUM_HDR
	bne,a	_pcontagion
	mov	MS_GENERIC_GREATER, %TMP2
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Lgreater_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	_pcontagion
	mov	MS_GENERIC_GREATER, %TMP2
Lgreater_flo2:
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f4
	fcmpd	%f2, %f4
	mov	FALSE_CONST, %RESULT
	fbg,a	.+8
	mov	TRUE_CONST, %RESULT
	jmp	%o7+8
	nop
Lgreater_comp:
	be,a	Lgreater_comp2
	nop
	! op1 was a compnum, op2 was not. If op2 is a flonum and op1 has
	! 0i, then we're fine.
	cmp	%TMP1, FLONUM_HDR
	bne,a	_pcontagion
	mov	MS_GENERIC_GREATER, %TMP2
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	be,a	Lgreater_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	Lnumeric_error
	mov	EX_GREATERP, %TMP0
Lgreater_comp2:
	! op1 and op2 were both compnums; if they both have 0i, then
	! we're fine.
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	ldd	[ %ARGREG2 - BVEC_TAG + 16 ], %f4
	fcmpd	%f0, %f2
	nop
	fbne,a	Lnumeric_error
	mov	EX_GREATERP, %TMP0
	fcmpd	%f0, %f4
	nop
	fbne,a	Lnumeric_error
	mov	EX_GREATERP, %TMP0
	b	Lgreater_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
Lgreater_big:
	be,a	Lgreater_big2
	mov	2, %TMP1
	b	_pcontagion
	mov	MS_GENERIC_GREATER, %TMP2
Lgreater_big2:
	b	internal_scheme_call
	mov	MS_BIGNUM_GREATER, %TMP2
Lgreater_vec:
	be,a	Lgreater_vec2
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	_pcontagion
	mov	MS_GENERIC_GREATER, %TMP2
Lgreater_vec2:
	ldub	[ %ARGREG2 - VEC_TAG + 3 ], %TMP1
	cmp	%TMP0, RATNUM_HDR
	be,a	Lgreater_rat
	cmp	%TMP1, RATNUM_HDR
	b	Lnumeric_error
	mov	EX_GREATERP, %TMP0
Lgreater_rat:
	be,a	Lgreater_rat2
	mov	2, %TMP1
	b	_pcontagion
	mov	MS_GENERIC_GREATER, %TMP2
Lgreater_rat2:
	b	internal_scheme_call
	mov	MS_RATNUM_GREATER, %TMP2

! Greater-than-or-equal
! Fixnums are done in-line.
! Compnums and rectnums are not in the domain of this function, but compnums
! with a 0 imaginary part are and have to be handled specially.

EXTNAME(m_generic_greater_or_equalp):
	and	%RESULT, TAGMASK, %TMP0
	and	%ARGREG2, TAGMASK, %TMP1
	cmp	%TMP0, BVEC_TAG
	be,a	Lgreatereq_bvec
	cmp	%TMP1, BVEC_TAG
	cmp	%TMP0, VEC_TAG
	be,a	Lgreatereq_vec
	cmp	%TMP1, VEC_TAG
! fixnum case
	or	%RESULT, %ARGREG2, %TMP0
	andcc	%TMP0, 3, %g0
	bne	Lgreatereq_generic
	subcc	%RESULT, %ARGREG2, %g0
	mov	FALSE_CONST, %RESULT
	bge,a	.+8
	mov	TRUE_CONST, %RESULT
	jmp	%o7+8
	nop
! generic
Lgreatereq_generic:
	b	_pcontagion
	mov	MS_GENERIC_GREATEREQ, %TMP2
Lgreatereq_bvec:
	be,a	Lgreatereq_bvec2
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	b	_pcontagion
	mov	MS_GENERIC_GREATEREQ, %TMP2
Lgreatereq_bvec2:
	ldub	[ %ARGREG2 - BVEC_TAG + 3 ], %TMP1
	cmp	%TMP0, FLONUM_HDR
	be,a	Lgreatereq_flo
	cmp	%TMP1, FLONUM_HDR
	cmp	%TMP0, COMPNUM_HDR
	be,a	Lgreatereq_comp
	cmp	%TMP1, COMPNUM_HDR
	cmp	%TMP0, BIGNUM_HDR
	be,a	Lgreatereq_big
	cmp	%TMP1, BIGNUM_HDR
	b	Lnumeric_error
	mov	EX_GREATEREQP, %TMP0
Lgreatereq_flo:
	be,a	Lgreatereq_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	cmp	%TMP1, COMPNUM_HDR
	bne,a	_pcontagion
	mov	MS_GENERIC_GREATEREQ, %TMP2
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f2
	fcmpd	%f0, %f2
	nop
	fbe,a	Lgreatereq_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	_pcontagion
	mov	MS_GENERIC_GREATEREQ, %TMP2
Lgreatereq_flo2:
	ldd	[ %ARGREG2 - BVEC_TAG + 8 ], %f4
	fcmpd	%f2, %f4
	mov	FALSE_CONST, %RESULT
	fbge,a	.+8
	mov	TRUE_CONST, %RESULT
	jmp	%o7+8
	nop
Lgreatereq_comp:
	be,a	Lgreatereq_comp2
	nop
	! op1 was a compnum, op2 was not. If op2 is a flonum and op1 has
	! 0i, then we're fine.
	cmp	%TMP1, FLONUM_HDR
	bne,a	_pcontagion
	mov	MS_GENERIC_GREATEREQ, %TMP2
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	be,a	Lgreatereq_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	b	Lnumeric_error
	mov	EX_GREATEREQP, %TMP0
Lgreatereq_comp2:
	! op1 and op2 were both compnums; if they both have 0i, then
	! we're fine.
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	ldd	[ %ARGREG2 - BVEC_TAG + 16 ], %f4
	fcmpd	%f0, %f2
	nop
	fbne,a	Lnumeric_error
	mov	EX_GREATEREQP, %TMP0
	fcmpd	%f0, %f4
	nop
	fbne,a	Lnumeric_error
	mov	EX_GREATEREQP, %TMP0
	b	Lgreatereq_flo2
	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
Lgreatereq_big:
	be,a	Lgreatereq_big2
	mov	2, %TMP1
	b	_pcontagion
	mov	MS_GENERIC_GREATEREQ, %TMP2
Lgreatereq_big2:
	b	internal_scheme_call
	mov	MS_BIGNUM_GREATEREQ, %TMP2
Lgreatereq_vec:
	be,a	Lgreatereq_vec2
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	_pcontagion
	mov	MS_GENERIC_GREATEREQ, %TMP2
Lgreatereq_vec2:
	ldub	[ %ARGREG2 - VEC_TAG + 3 ], %TMP1
	cmp	%TMP0, RATNUM_HDR
	be,a	Lgreatereq_rat
	cmp	%TMP1, RATNUM_HDR
	b	Lnumeric_error
	mov	EX_GREATEREQP, %TMP0
Lgreatereq_rat:
	be,a	Lgreatereq_rat2
	mov	2, %TMP1
	b	_pcontagion
	mov	MS_GENERIC_GREATEREQ, %TMP2
Lgreatereq_rat2:
	b	internal_scheme_call
	mov	MS_RATNUM_GREATEREQ, %TMP2


! The tower of numeric types.
!
! The implementation of the predicates is rather interweaved, as we strive for
! at least some semblance of efficiency while keeping the code small.

! (define (complex? x)
!   (or (compnum? x) (rectnum? x) (real? x)))

EXTNAME(m_generic_complexp):
	and	%RESULT, TAGMASK, %TMP0
	cmp	%TMP0, BVEC_TAG
	be,a	Lcomplexp_bvec
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	cmp	%TMP0, VEC_TAG
	be,a	Lcomplexp_vec
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	Lintegerp_fix
	nop
Lcomplexp_bvec:
	cmp	%TMP0, COMPNUM_HDR
	bne	Lrealp_bvec			! other bytevector-like
	nop
	jmp	%o7+8
	mov	TRUE_CONST, %RESULT
Lcomplexp_vec:
	cmp	%TMP0, RECTNUM_HDR
	bne	Lrationalp_vec			! other vector-like
	nop
	jmp	%o7+8
	mov	TRUE_CONST, %RESULT

! (define (real? x) 
!   (rational? x))
!
! (define (rational? x)
!   (or (and (compnum? x) (= (imag-part x) 0.0))
!       (flonum? x) (rational? x)
!       (ratnum? x)
!       (integer? x)))

EXTNAME(m_generic_realp):
EXTNAME(m_generic_rationalp):
	and	%RESULT, TAGMASK, %TMP0
	cmp	%TMP0, BVEC_TAG
	be,a	Lrealp_bvec
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	cmp	%TMP0, VEC_TAG
	be,a	Lrationalp_vec
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	EXTNAME(m_generic_integerp)
	nop
Lrealp_bvec:
	cmp	%TMP0, FLONUM_HDR
	be,a	Lrealp_exit
	mov	TRUE_CONST, %RESULT
	cmp	%TMP0, COMPNUM_HDR
	bne	Lintegerp_bvec
	nop
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	fcmpd	%f0, %f2
	mov	TRUE_CONST, %RESULT
	fbne,a	.+8
	mov	FALSE_CONST, %RESULT
Lrealp_exit:
	jmp	%o7+8
	nop
Lrationalp_vec:
	cmp	%TMP0, RATNUM_HDR
	mov	TRUE_CONST, %RESULT
	bne,a	.+8
	mov	FALSE_CONST, %RESULT
	jmp	%o7+8
	nop

! (define (integer? x)
!   (or (bignum? x)
!       (fixnum? x)
!       (or (and (flonum? x) (representable-as-int? x))
!           (and (compnum? x) 
!                (= (imag-part x) 0.0)
!                (representable-as-int? (real-part x))))))

EXTNAME(m_generic_integerp):
	and	%RESULT, TAGMASK, %TMP0
	cmp	%TMP0, BVEC_TAG
	be,a	Lintegerp_bvec
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	cmp	%TMP0, VEC_TAG
	be,a	Lintegerp_exit
	mov	FALSE_CONST, %RESULT
	b	Lintegerp_fix
	nop
Lintegerp_bvec:
	cmp	%TMP0, BIGNUM_HDR
	be,a	Lintegerp_exit
	mov	TRUE_CONST, %RESULT

	! It is a bytevector, and it is not a bignum. Ergo, it may be a
	! flonum or a compnum, or not a number at all.

	cmp	%TMP0, FLONUM_HDR
	be,a	Lintegerp_flo
	nop
	cmp	%TMP0, COMPNUM_HDR
	be,a	Lintegerp_comp
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	jmp	%o7+8
	mov	FALSE_CONST, %RESULT

Lintegerp_comp:
	fcmpd	%f0, %f2
	nop
	fbne,a	Lintegerp_exit
	mov	FALSE_CONST, %RESULT

Lintegerp_flo:
	
	! Check to see if the real part is representable as an
	! integer, and if so, return #t. Otherwise return #f.
	!
	! The real part is representible as an integer only if
	! all the bits to the right of the binary point are zero.
	!
	! The algorithm used needs to special case 0.0 and -0.0

	save	%sp, -96, %sp
	ldd	[ %SAVED_RESULT - BVEC_TAG + 8 ], %l0

	! First test special cases.
	set	0x80000000, %l2
	andn	%l0, %l2, %l2				! toss sign bit
	orcc	%l2, %l1, %g0
	be,a	Lintegerp_exit2				! 0.0 or -0.0
	mov	TRUE_CONST, %SAVED_RESULT

	srl	%l0, 20, %l2				! get at expt
	and	%l2, 0x7FF, %l2				! get it
	subcc	%l2, 1023, %l2				! unbias

	! easy cases

	blt,a	Lintegerp_exit2				! e < 0
	mov	FALSE_CONST, %SAVED_RESULT
	cmp	%l2, 52
	bgt,a	Lintegerp_exit2				! e > 52
	mov	TRUE_CONST, %SAVED_RESULT

	! determine which word to play with

	cmp	%l2, 20
	ble,a	Lintegerp_hi				! 0 <= e <= 20: hi word
	nop

	! The low word is the interesting one. However, if the shift count
	! (after subtracting 20) is exactly 32, then the shift will not happen
	! beacuse shift counts are all mod 32. So we have to make this a
	! special case.

	sub	%l2, 20, %l2
	cmp	%l2, 32
	be,a	Lintegerp_exit2
	mov	TRUE_CONST, %SAVED_RESULT
	! %l2 < 32
	sll	%l1, %l2, %l1
	cmp	%l1, 0
	be,a	Lintegerp_exit2
	mov	TRUE_CONST, %SAVED_RESULT
	b	Lintegerp_exit2
	mov	FALSE_CONST, %SAVED_RESULT
Lintegerp_hi:
	! the high word is the interesting one; low word must be 0.

	tst	%l1
	bne,a	Lintegerp_exit2
	mov	FALSE_CONST, %SAVED_RESULT

	sll	%l0, 12, %l0
	sll	%l0, %l2, %l0
	cmp	%l0, 0
	mov	FALSE_CONST, %SAVED_RESULT
	be,a	.+8
	mov	TRUE_CONST, %SAVED_RESULT
Lintegerp_exit2:
	jmp	%i7+8
	restore

Lintegerp_fix:
	andcc	%RESULT, 3, %g0
	mov	TRUE_CONST, %RESULT
	bne,a	.+8
	mov	FALSE_CONST, %RESULT
Lintegerp_exit:
	jmp	%o7+8
	nop

! Exactness maps trivially to representation (or the other way around.)

! (define (exact? x)
!   (cond ((or (fixnum? x) (bignum? x) (ratnum? x) (rectnum? x)) #t)
!         ((or (compnum? x) (flonum? x)) #f)
!         (else (error ...))))

EXTNAME(m_generic_exactp):
	mov	TRUE_CONST, %ARGREG2
	mov	FALSE_CONST, %ARGREG3
EXTNAME(m_generic_exactness_test):
	and	%RESULT, TAGMASK, %TMP0
	cmp	%TMP0, VEC_TAG
	bne	Lexactp1
	nop
	! It's a vector.
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	cmp	%TMP0, RATNUM_HDR
	be	Lexactp99
	cmp	%TMP0, RECTNUM_HDR
	be	Lexactp99
	nop
	b	Lnumeric_error
	mov	EX_EXACTP, %TMP0
Lexactp1:
	cmp	%TMP0, BVEC_TAG
	bne	Lexactp2
	nop
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	cmp	%TMP0, BIGNUM_HDR
	be	Lexactp99
	cmp	%TMP0, FLONUM_HDR
	be	Lexactp98
	cmp	%TMP0, COMPNUM_HDR
	be	Lexactp98
	nop
	b	Lnumeric_error
	mov	EX_EXACTP, %TMP0
Lexactp2:
	andcc	%RESULT, 3, %g0
	bne	Lnumeric_error
	mov	EX_EXACTP, %TMP0
Lexactp99:
	jmp	%o7+8
	mov	%ARGREG2, %RESULT
Lexactp98:
	jmp	%o7+8
	mov	%ARGREG3, %RESULT

! (define (inexact? x)
!   (cond ((or (compnum? x) (flonum? x)) #t)
!         ((or (fixnum? x) (flonum? x) (ratnum? x) (rectnum? x)) #f)
!         (else (error ...))))

EXTNAME(m_generic_inexactp):
	mov	FALSE_CONST, %ARGREG2
	b	EXTNAME(m_generic_exactness_test)
	mov	TRUE_CONST, %ARGREG3


! Fixnum->flonum and identity operations are interesting; everything else
! is not, and should be handled by Scheme.
!
! (define (exact->inexact a)
!   (cond ((inexact? a) a)
!         ((rectnum? a) (rectnum->compnum a))
!         ((ratnum? a)  (ratnum->flonum a))
!         ((bignum? a)  (bignum->flonum a))
!         ((fixnum? a)  (fixnum->flonum a))
!         (else ???)))

EXTNAME(m_generic_exact2inexact):
	andcc	%RESULT, 3, %g0
	be,a	Lfixnum2flonum
	sra	%RESULT, 2, %TMP0
	and	%RESULT, TAGMASK, %TMP0
	cmp	%TMP0, BVEC_TAG
	be,a	Le2i_maybe
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
Le2i_noway:

	! Not fixnum, not identity operation. Drop into scheme.

	mov	1, %TMP1
	b	internal_scheme_call
	mov	MS_GENERIC_EXACT2INEXACT, %TMP2

Le2i_maybe:
	cmp	%TMP0, FLONUM_HDR
	be	Le2i_identity
	nop
	cmp	%TMP0, COMPNUM_HDR
	be	Le2i_identity
	nop
	b	Le2i_noway
	nop
Le2i_identity:
	jmp	%o7+8
	nop

! %TMP0 has the raw bits for the fixnum, shifted to an integer.

Lfixnum2flonum:
	set	Le2itmp, %TMP1
	st	%TMP0, [ %TMP1 ]
	ld	[ %TMP1 ], %f2
	b	_box_flonum
	fitod	%f2, %f2

! Identity operations are handled here. The rest is handled in scheme.
! Really should handle flonum->integer here.
!
! (define (inexact->exact a)
!   (cond ((exact? a) a)
!         ((flonum? a) (flonum->integer a))
!         ((compnum? a) (compnum->rectnum a))
!         (else ???)))

EXTNAME(m_generic_inexact2exact):
	and	%RESULT, TAGMASK, %TMP0
	cmp	%TMP0, BVEC_TAG
	be,a	Li2e_bvec		! vector-like
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	andcc	%RESULT, 3, %g0
	be	Li2e_identity		! fixnum
	nop
	cmp	%TMP0, VEC_TAG
	be,a	Li2e_vec
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	Lnumeric_error
	mov	EX_I2E, %TMP0

! Isa bytevector; header in TMP0
	
Li2e_bvec:
	cmp	%TMP0, BIGNUM_HDR
	be	Li2e_identity		! bignum
	nop

	! Flonum or compnum. Drop into Scheme.
	! It would be desirable to handle flonum->integer here.

	mov	1, %TMP1
	b	internal_scheme_call
	mov	MS_GENERIC_INEXACT2EXACT, %TMP2
Li2e_vec:
	cmp	%TMP0, RATNUM_HDR
	be	Li2e_identity
	nop
	cmp	%TMP0, RECTNUM_HDR
	be	Li2e_identity
	nop
	b	Lnumeric_error
	mov	EX_I2E, %TMP0
Li2e_identity:
	jmp	%o7+8
	nop

! `make-rectangular' is actually a bit hairy. Should it just go into Scheme?
! (Possibly flonum+flonum->compnum case should be in line, for speed).
!
! (define (make-rectangular a b)
!   (if (and (exact? a) (exact? b))
!       (if (not (zero? b))
!           (make-rectnum a b)
!           a)
!       (make-compnum a b)))
!
! (define (make-rectnum a b)
!   (let ((v (make-vector 2)))
!     (vector-like-set! v 0 a)
!     (vector-like-set! v 1 b)
!     (typetag-set! v RECTNUM_TYPETAG)
!     v))
!
! (define (make-compnum a b)
!   (if (or (compnum? a) (compnum? b) (rectnum? a) (rectnum? b))
!       (error ...)
!       (box-compnum (exact->inexact a) (exact->inexact b))))

EXTNAME(m_generic_make_rectangular):
	mov	2, %TMP1
	b	internal_scheme_call
	mov	MS_GENERIC_MAKE_RECTANGULAR, %TMP2


! `real-part' and `imag-part'.
!
! (define (real-part z)
!   (cond ((compnum? z) (compnum-real-part z))
!         ((rectnum? z) (rectnum-real-part z))
!         ((number? z) z)
!         (else (error ...))))

EXTNAME(m_generic_real_part):
	mov	8-BVEC_TAG, %TMP1
	mov	4-VEC_TAG, %TMP2
	set	Lgeneric_realpart2, %ARGREG2
	b	Lreal_imag0
	mov	EX_REALPART, %ARGREG3
Lgeneric_realpart2:
	jmp	%o7+8
	nop

! Given fixnum byte indices into compnums and rectnums in TMP1 and 
! TMP2, and a pointer to a resolution routine for non-complex 
! numbers in ARGREG2, do real_part/imag_part in one piece of code.
! ARGREG3 has the exception code (fixnum) in the low 31 bits, and
! an exactness bit in the high bit: 0=exact, 1=inexact (initially 0).

Lreal_imag0:
	and	%RESULT, TAGMASK, %TMP0
	cmp	%TMP0, BVEC_TAG
	be,a	Lreal_imag_bvec
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	cmp	%TMP0, VEC_TAG
	be,a	Lreal_imag_vec
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	Lreal_imag_others
	nop

	! It is a bytevector. The header tag byte is in %TMP0.
Lreal_imag_bvec:
	cmp	%TMP0, COMPNUM_HDR
	be,a	_box_flonum
	ldd	[ %RESULT + %TMP1 ], %f2
	cmp	%TMP0, BIGNUM_HDR
	be,a	Lreal_imag_resolve
	nop
	cmp	%TMP0, FLONUM_HDR
	sethi   %hi(0x80000000), %TMP0
	be,a	Lreal_imag_resolve
	or	%ARGREG3, %TMP0, %ARGREG3
	b	Lnumeric_error
	mov	%ARGREG3, %TMP0

	! It is a vector. The header tag byte is in %TMP0.
Lreal_imag_vec:
	cmp	%TMP0, RECTNUM_HDR
	be,a	Lreal_imag_return
	ld	[ %RESULT + %TMP2 ], %RESULT
	cmp	%TMP0, RATNUM_HDR
	be,a	Lreal_imag_resolve
	nop
	b	Lnumeric_error
	mov	%ARGREG3, %TMP0
	! It is neither bytevector nor vector.
Lreal_imag_others:
	andcc	%RESULT, 3, %g0
	be,a	Lreal_imag_resolve
	nop
	b	Lnumeric_error
	mov	%ARGREG3, %TMP0
Lreal_imag_resolve:
	jmp	%ARGREG2
	nop
Lreal_imag_return:
	jmp	%o7+8
	nop

! (define (imag-part z)
!   (cond ((compnum? z) (compnum-imag-part z))
!         ((rectnum? z) (rectnum-imag-part z))
!         ((number? z) (if (exact? z) #e0 #i0))
!         (else (error ...))))

EXTNAME(m_generic_imag_part):
	set	Limag_part2, %ARGREG2
	mov	EX_IMAGPART, %ARGREG3
	mov	16-BVEC_TAG, %TMP1
	b	Lreal_imag0
	mov	8-VEC_TAG, %TMP2

Limag_part2:
	! Getting the imag part from a non-complex: return 0, with the
	! correct exactness. Recall that the exactness spec is in the
	! high bit of ARGREG3; if negative, then inexact.

	tst	%ARGREG3
	blt,a	_box_flonum
	fmovd	%f0, %f2
	jmp	%o7+8
	mov	%g0, %RESULT

! These will return the argument in the case of fixnum, bignum, or ratnum;
! will return a new number in the case of a flonum (or compnum with 0i);
! and will give a domain error for compnums with non-0i and rectnums.

EXTNAME(m_generic_round):
	set	Lround, %TMP1
	b	Lgeneric_trund
	mov	EX_ROUND, %TMP2

EXTNAME(m_generic_truncate):
	set	Ltrunc, %TMP1
	b	Lgeneric_trund
	mov	EX_TRUNC, %TMP2

Lround:
	! Flonum is pointed to by %RESULT. Round it, box it, and return.
	! The simple way to round is to add .5 and then truncate.
	! The sign of the .5 must be the same as the sign of the number
	! being rounded!
	! We need to round to even here (which introduces a bit of hair);
	! FIXME.

	ldd	[ %RESULT - BVEC_TAG + 8 ], %f2
	set	Ldhalf, %TMP0 
	ldd	[ %TMP0 ], %f4
	fmovd	%f2, %f6
	fabsd	%f2, %f2
	fcmpd	%f6, %f0
	faddd	%f2, %f4, %f2
	.empty				! shit...
	fbl,a	.+8
	fnegd	%f2, %f2
	std	%f2, [ %TMP0 + 8 ]
	save	%sp, -96, %sp
	b	Ltrunc2
	ldd	[ %SAVED_TMP0 + 8 ], %l0

Ltrunc:
	! flonum is pointed to by %RESULT. Trunc it, box it, and return.

	set	Ldhalf, %TMP0 
	save	%sp, -96, %sp
	ldd	[ %SAVED_RESULT - BVEC_TAG + 8 ], %l0
Ltrunc2:
	srl	%l0, 20, %l2			! get at exponent
	and	%l2, 0x7FF, %l2			! toss sign
	subcc	%l2, 1023, %l2			! unbias
	blt,a	Ltrunc2zero
	mov	%g0, %l1
	cmp	%l2, 52
	bge	Ltrunc_moveback
	nop
	cmp	%l2, 20
	ble,a	Ltrunc_high
	mov	%g0, %l1

	! mask off low word.
	mov	52, %l3
	sub	%l3, %l2, %l2
	srl	%l1, %l2, %l1
	b	Ltrunc_moveback
	sll	%l1, %l2, %l1

Ltrunc_high:
	! zero out lo word, mask off high word
	mov	20, %l3
	sub	%l3, %l2, %l2
	srl	%l0, %l2, %l0
	b	Ltrunc_moveback
	sll	%l0, %l2, %l0

Ltrunc2zero:
	sethi	%hi( 0x80000000 ), %l2
	and	%l0, %l2, %l0			! get sign right

Ltrunc_moveback:
	! move back into fp regs

	std	%l0, [ %SAVED_TMP0 + 8 ]
	ldd	[ %SAVED_TMP0 + 8 ], %f2
	b	_box_flonum
	restore

! Generic code for rounding and truncation. Address of final procedure 
! is in %TMP1, exception code for specific operation is in %TMP2.

Lgeneric_trund:
	and	%RESULT, TAGMASK, %TMP0
	cmp	%TMP0, BVEC_TAG
	be,a	Ltrund_bvec
	ldub	[ %RESULT - BVEC_TAG + 3 ], %TMP0
	andcc	%RESULT, 3, %g0
	be,a	Ltrund_def
	nop
	cmp	%TMP0, VEC_TAG
	be,a	Ltrund_vec
	ldub	[ %RESULT - VEC_TAG + 3 ], %TMP0
	b	Lnumeric_error
	mov	%TMP2, %TMP0
Ltrund_bvec:
	cmp	%TMP0, FLONUM_HDR
	be,a	Ltrund_flo
	nop
	cmp	%TMP0, COMPNUM_HDR
	be,a	Ltrund_comp
	ldd	[ %RESULT - BVEC_TAG + 16 ], %f2
	cmp	%TMP0, BIGNUM_HDR
	be,a	Ltrund_def
	nop
	b	Lnumeric_error
	mov	%TMP2, %TMP0
Ltrund_flo:
	jmp	%TMP1
	nop
Ltrund_comp:
	fcmpd	%f0, %f2
	nop
	fbne,a	Lnumeric_error
	mov	%TMP2, %TMP0
	jmp	%TMP1
	nop
Ltrund_vec:
	cmp	%TMP0, RATNUM_HDR
	bne,a	Lnumeric_error
	mov	%TMP2, %TMP0
	! Ratnums
	set	Ltrunc, %TMP0
	cmp	%TMP0, %TMP1
	mov	1, %TMP1
	bne,a	internal_scheme_call
	mov	MS_RATNUM_ROUND, %TMP2
	b	internal_scheme_call
	mov	MS_RATNUM_TRUNCATE, %TMP2
Ltrund_def:
	jmp	%o7+8
	nop

! Not yet done in millicode.

EXTNAME(m_generic_negativep):
EXTNAME(m_generic_positivep):
EXTNAME(m_generic_sqrt):
	jmp	%MILLICODE + M_EXCEPTION
	mov	EX_UNSUPPORTED, %TMP0


! '_contagion' implements the coercion matrix for arithmetic operations.
! It assumes that the two operands are passed in %RESULT and %ARGREG2 and
! that the scheme return address is in %o7.
! In addition, %TMP2 has the fixnum index into the millicode support vector
! of the procedure which is to be called on to retry the operation.
!
_contagion:
	b	Lcontagion
	mov	MS_CONTAGION, %TMP0
_pcontagion:
	b	Lcontagion
	mov	MS_PCONTAGION, %TMP0
_econtagion:
	mov	MS_ECONTAGION, %TMP0
Lcontagion:
	ld	[ %GLOBALS + G_CALLOUTS ], %TMP1
	ld	[ %TMP1 - GLOBAL_CELL_TAG + CELL_VALUE_OFFSET ], %TMP1
!#ifdef DEBUG
	cmp	%TMP1, UNDEFINED_CONST
	bne	Lcontagion2
	nop
	set	EXTNAME(C_panic), %TMP0
	set	Lnoc, %TMP1
	b	callout_to_C
	nop
!#endif
Lcontagion2:
	add	%TMP1, 4 - VEC_TAG, %TMP1	! bump ptr
	ld	[ %TMP1 + %TMP2 ], %ARGREG3	! scheme proc to retry
	mov	%TMP0, %TMP2			! contagion proc
	b	internal_scheme_call
	mov	3, %TMP1			! argument count

! All errors cause a branch to this point; we jump to the error hander.
! The error code should already be in %TMP0.

Lnumeric_error:
	jmp	%MILLICODE + M_EXCEPTION
	nop

!-----------------------------------------------------------------------------
! Box various numbers.

! Box the double in %f2/f3 as a flonum. Return tagged pointer in RESULT.
! Scheme return address in %o7.

_box_flonum:
	st	%o7, [ %GLOBALS + G_RETADDR ]
	call	EXTNAME(mem_internal_alloc)
	mov	16, %RESULT
	ld	[ %GLOBALS + G_RETADDR ], %o7
	std	%f2, [ %RESULT + 8 ]
	set	(12 << 8) | FLONUM_HDR, %TMP1
	st	%TMP1, [ %RESULT ]
	jmp	%o7 + 8
	add	%RESULT, BVEC_TAG, %RESULT


! Box the two doubles in %f2/%f3 and %f4/%f5 as a compnum.
! Return tagged pointer in RESULT.
! Scheme return address in %o7.

_box_compnum:
	st	%o7, [ %GLOBALS + G_RETADDR ]
	call	EXTNAME(mem_internal_alloc)
	mov	24, %RESULT
	ld	[ %GLOBALS + G_RETADDR ], %o7
	std	%f2, [ %RESULT + 8 ]
	std	%f4, [ %RESULT + 16 ]
	set	(20 << 8) | COMPNUM_HDR, %TMP0
	st	%TMP0, [ %RESULT ]
	jmp	%o7+8
	add	%RESULT, BVEC_TAG, %RESULT

! Box an integer in a bignum with one digit. The integer is passed in %TMP0.
! %o7 has the Scheme return address.

_box_single_bignum:
	cmp	%TMP0, 0
	bge,a	_box_single_positive_bignum
	mov	0, %TMP2
	mov	1, %TMP2
	neg	%TMP0

! Sign (0 or 1) is in %TMP2, untagged, positive number in %TMP0.

_box_single_positive_bignum:
	st	%TMP0, [ %GLOBALS + G_GENERIC_NRTMP1 ]
	st	%TMP2, [ %GLOBALS + G_GENERIC_NRTMP2 ]
	st	%o7, [ %GLOBALS + G_RETADDR ]
	call	EXTNAME(mem_internal_alloc)
	mov	12, %RESULT
	ld	[ %GLOBALS + G_RETADDR ], %o7
	ld	[ %GLOBALS + G_GENERIC_NRTMP1 ], %TMP0
	ld	[ %GLOBALS + G_GENERIC_NRTMP2 ], %TMP2
	sll	%TMP2, 16, %TMP2
	add	%TMP2, 1, %TMP1
	st	%TMP1, [ %RESULT + 4 ]		! store sign, length
	st	%TMP0, [ %RESULT + 8 ]		! store number
	set	(8 << 8) | BIGNUM_HDR, %TMP0
	st	%TMP0, [ %RESULT ]
	jmp	%o7+8
	or	%RESULT, BVEC_TAG, %RESULT

! Box an integer in a bignum with two digits. The integer is passed in
! %TMP0 (low word) and %TMP1 (high word). If the high word has the sign
! bit set, then we have to complement the whole thing and make the sign
! negative before boxing.
! %o7 has the Scheme return address.
! Sign bit is the low bit of %TMP2.

_box_double_positive_bignum:
	st	%TMP0, [ %GLOBALS + G_GENERIC_NRTMP1 ]
	st	%TMP1, [ %GLOBALS + G_GENERIC_NRTMP2 ]
	st	%TMP2, [ %GLOBALS + G_GENERIC_NRTMP3 ]
	st	%o7, [ %GLOBALS + G_RETADDR ]
	call	EXTNAME(mem_internal_alloc)
	mov	16, %RESULT
	ld	[ %GLOBALS + G_RETADDR ], %o7
	ld	[ %GLOBALS + G_GENERIC_NRTMP1 ], %TMP0
	ld	[ %GLOBALS + G_GENERIC_NRTMP2 ], %TMP1
	ld	[ %GLOBALS + G_GENERIC_NRTMP3 ], %TMP2
	sll	%TMP2, 16, %TMP2
	add	%TMP2, 2, %TMP2
	st	%TMP2, [ %RESULT + 4 ]
	st	%TMP0, [ %RESULT + 8 ]
	st	%TMP1, [ %RESULT + 12 ]
	set	(12 << 8) | BIGNUM_HDR, %TMP0
	st	%TMP0, [ %RESULT ]
	jmp	%o7+8
	or	%RESULT, BVEC_TAG, %RESULT

! Interesting data for the generic arithmetic system.

	.seg	"data"
Lnoc:	.asciz 	"No contagion procedure defined."

	.align 8
Ldhalf:
	.double	0r0.5		! 0.5; leave it here.
	.double 0r0.0		! this is a temp and DON'T MOVE IT!!
Le2itmp:
	.word	0		! temporary nonroot

	! end
