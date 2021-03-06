/*-
 * Copyright (c) 2014 Andrew Turner
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 */

#include <machine/asm.h>
__FBSDID("$FreeBSD$");

#include "assym.s"

	.text

.macro	save_registers el
	stp	x28, x29, [sp, #-16]!
	stp	x26, x27, [sp, #-16]!
	stp	x24, x25, [sp, #-16]!
	stp	x22, x23, [sp, #-16]!
	stp	x20, x21, [sp, #-16]!
	stp	x18, x19, [sp, #-16]!
	stp	x16, x17, [sp, #-16]!
	stp	x14, x15, [sp, #-16]!
	stp	x12, x13, [sp, #-16]!
	stp	x10, x11, [sp, #-16]!
	stp	x8, x9, [sp, #-16]!
	stp	x6, x7, [sp, #-16]!
	stp	x4, x5, [sp, #-16]!
	stp	x2, x3, [sp, #-16]!
	stp	x0, x1, [sp, #-16]!
	mrs	x10, elr_el1
	mrs	x11, spsr_el1
.if \el == 0
	mrs	x12, sp_el0
.else
	mov	x12, sp
.endif
	stp	x10, x11, [sp, #-16]!
	stp	x12, lr, [sp, #-16]!
	mrs	x18, tpidr_el1
.endm

.macro	restore_registers el
	ldp	x12, lr, [sp], #16
	ldp	x10, x11, [sp], #16
.if \el == 0
	msr	sp_el0, x12
.else
	mov	sp, x12
.endif
	msr	spsr_el1, x11
	msr	elr_el1, x10
	ldp	x0, x1, [sp], #16
	ldp	x2, x3, [sp], #16
	ldp	x4, x5, [sp], #16
	ldp	x6, x7, [sp], #16
	ldp	x8, x9, [sp], #16
	ldp	x10, x11, [sp], #16
	ldp	x12, x13, [sp], #16
	ldp	x14, x15, [sp], #16
	ldp	x16, x17, [sp], #16
.if \el == 0
	ldp	x18, x19, [sp], #16
.else
	ldp	xzr, x19, [sp], #16
.endif
	ldp	x20, x21, [sp], #16
	ldp	x22, x23, [sp], #16
	ldp	x24, x25, [sp], #16
	ldp	x26, x27, [sp], #16
	ldp	x28, x29, [sp], #16
.endm

.macro	do_ast
	/* Disable interrupts */
	mrs	x19, daif
	msr	daifset, #2

	/* Read the current thread flags */
1:	ldr	x1, [x18, #PC_CURTHREAD]	/* Load curthread */
	ldr	x2, [x1, #TD_FLAGS]! /* TODO: No need for the ! but clang fails without it */

	/* Check if we have either bits set */
	mov	x3, #((TDF_ASTPENDING|TDF_NEEDRESCHED) >> 8)
	lsl	x3, x3, #8
	and	x2, x2, x3
	cmp	x2, #0
	b.eq	2f

	/* Restore interrupts */
	msr	daif, x19

	/* handle the ast */
	mov	x0, sp
	bl	_C_LABEL(ast)

	/* Disable interrupts */
	mrs	x19, daif
	msr	daifset, #2

2:
	/* Restore interrupts */
	msr	daif, x19
.endm

handle_el1h_sync:
	save_registers 1
	mov	x0, sp
	bl	do_el1h_sync
	restore_registers 1
	eret

handle_el1h_irq:
	save_registers 1
	mov	x0, sp
	bl	arm_cpu_intr
	restore_registers 1
	eret

handle_el1h_error:
	brk	0xf13

handle_el0_sync:
	save_registers 0
	mov	x0, sp
	bl	do_el0_sync
	do_ast
	restore_registers 0
	eret

handle_el0_irq:
	save_registers 0
	mov	x0, sp
	bl	arm_cpu_intr
	restore_registers 0
	eret

handle_el0_error:
	save_registers 0
	mov	x0, sp
	bl	do_el0_error
	brk	0xf23
	1: b 1b

.macro	vempty
	.align 7
	brk	0xfff
	1: b	1b
.endm

.macro	vector	name
	.align 7
	b	handle_\name
.endm

	.align 11
	.globl exception_vectors
exception_vectors:
	vempty			/* Synchronous EL1t */
	vempty			/* IRQ EL1t */
	vempty			/* FIQ EL1t */
	vempty			/* Error EL1t */

	vector el1h_sync	/* Synchronous EL1h */
	vector el1h_irq		/* IRQ EL1h */
	vempty			/* FIQ EL1h */
	vector el1h_error	/* Error EL1h */

	vector el0_sync		/* Synchronous 64-bit EL0 */
	vector el0_irq		/* IRQ 64-bit EL0 */
	vempty			/* FIQ 64-bit EL0 */
	vector el0_error	/* Error 64-bit EL0 */

	vempty			/* Synchronous 32-bit EL0 */
	vempty			/* IRQ 32-bit EL0 */
	vempty			/* FIQ 32-bit EL0 */
	vempty			/* Error 32-bit EL0 */

