#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#define MY_HAS_PERL(R, V, S) (PERL_REVISION > (R) || (PERL_REVISION == (R) && (PERL_VERSION > (V) || (PERL_VERSION == (V) && (PERL_SUBVERSION >= (S))))))

#define SU_GET_CONTEXT(B, D)            \
	STMT_START {                        \
		if (items > 0) {                \
			SV *csv = ST(B);            \
			if (!SvOK(csv))             \
				goto default_cx;        \
			cxix = SvIV(csv);           \
			if (cxix < 0)               \
				cxix = 0;               \
			else if (cxix > cxstack_ix) \
				goto default_cx;        \
		} else {                        \
			default_cx:                 \
			cxix = (D);                 \
		}                               \
	} STMT_END

#define SU_GET_LEVEL()             \
	STMT_START {                   \
		level = 0;                 \
		if (items > 0) {           \
			SV *lsv = ST(0);       \
			if (SvOK(lsv)) {       \
				level = SvIV(lsv); \
				if (level < 0)     \
					level = 0;     \
			}                      \
		}                          \
	} STMT_END

#define MY_CXT_KEY "Scope::Unwind-" XS_VERSION
typedef struct {
	I32      cxix;
	I32      items;
	SV     **savesp;
	LISTOP   return_op;
	OP       proxy_op;
} my_cxt_t;

START_MY_CXT

static void su_unwind(pTHX_ void *ud_) {
	dMY_CXT;
	I32 cxix  = MY_CXT.cxix;
	I32 items = MY_CXT.items;
	I32 mark;

	PERL_UNUSED_VAR(ud_);

	PL_stack_sp = MY_CXT.savesp;
#if MY_HAS_PERL(5, 19, 4)
	{
		I32 i;
		SV **sp = PL_stack_sp;
		for (i = -items + 1; i <= 0; ++i)
		if (!SvTEMP(sp[i]))
			sv_2mortal(SvREFCNT_inc(sp[i]));
	}
#endif

	if (cxstack_ix > cxix)
		dounwind(cxix);

	mark = PL_markstack[cxstack[cxix].blk_oldmarksp];
	*PL_markstack_ptr = PL_stack_sp - PL_stack_base - items;

/*
	MY_D({
		I32 gimme = GIMME_V;
		su_debug_log("%p: cx=%d gimme=%s items=%d sp=%d oldmark=%d mark=%d\n",
		&MY_CXT, cxix,
		gimme == G_VOID ? "void" : gimme == G_ARRAY ? "list" : "scalar",
		items, PL_stack_sp - PL_stack_base, *PL_markstack_ptr, mark);
	});*/

	PL_op = (OP *) &(MY_CXT.return_op);
	PL_op = PL_op->op_ppaddr(aTHX);

	*PL_markstack_ptr = mark;

	MY_CXT.proxy_op.op_next = PL_op;
	PL_op = &(MY_CXT.proxy_op);
}

#ifndef OP_SIBLING
#	define OP_SIBLING(O) ((O)->op_sibling)
#endif

static I32 su_context_normalize_up(pTHX_ I32 cxix) {
#define su_context_normalize_up(C) su_context_normalize_up(aTHX_ (C))
	PERL_CONTEXT *cx;

	if (cxix <= 0)
		return 0;

	cx = cxstack + cxix;
	if (CxTYPE(cx) == CXt_BLOCK) {
		PERL_CONTEXT *prev = cx - 1;

		switch (CxTYPE(prev)) {
#if MY_HAS_PERL(5, 10, 0)
			case CXt_GIVEN:
			case CXt_WHEN:
#endif
#if MY_HAS_PERL(5, 11, 0)
			/* That's the only subcategory that can cause an extra BLOCK context */
			case CXt_LOOP_PLAIN:
#else
			case CXt_LOOP:
#endif
				if (cx->blk_oldcop == prev->blk_oldcop)
					return cxix - 1;
				break;
			case CXt_SUBST:
				if (cx->blk_oldcop && OP_SIBLING(cx->blk_oldcop) && OP_SIBLING(cx->blk_oldcop)->op_type == OP_SUBST)
					return cxix - 1;
				break;
		}
	}

	return cxix;
}

static I32 su_context_skip_db(pTHX_ I32 cxix) {
#define su_context_skip_db(C) su_context_skip_db(aTHX_ (C))
	I32 i;

	if (!PL_DBsub)
		return cxix;

	for (i = cxix; i > 0; --i) {
		PERL_CONTEXT *cx = cxstack + i;

		switch (CxTYPE(cx)) {
#if MY_HAS_PERL(5, 17, 1)
			case CXt_LOOP_PLAIN:
#endif
			case CXt_BLOCK:
				if (cx->blk_oldcop && CopSTASH(cx->blk_oldcop) == GvSTASH(PL_DBgv))
					continue;
				break;
			case CXt_SUB:
				if (cx->blk_sub.cv == GvCV(PL_DBsub)) {
					cxix = i - 1;
					continue;
				}
				break;
			default:
				break;
		}
		break;
	}

	return cxix;
}

#define su_context_here() su_context_normalize_up(su_context_skip_db(cxstack_ix))

static const char su_stack_smash[]    = "Cannot target a scope outside of the current stack";
static const char su_no_such_target[] = "No targetable %s scope in the current stack";

MODULE = Scope::Unwind  PACKAGE = Scope::Unwind

PROTOTYPES: DISABLE

BOOT:
	MY_CXT_INIT;

	/* NewOp() calls calloc() which just zeroes the memory with memset(). */
	Zero(&MY_CXT.return_op, 1, LISTOP);
	MY_CXT.return_op.op_type   = OP_RETURN;
	MY_CXT.return_op.op_ppaddr = PL_ppaddr[OP_RETURN];

	Zero(&MY_CXT.proxy_op, 1, OP);
	MY_CXT.proxy_op.op_type   = OP_STUB;
	MY_CXT.proxy_op.op_ppaddr = NULL;

	newCONSTSUB(gv_stashpvs("Scope::Unwind", 1), "TOP", newSViv(0));

IV
HERE()
	PREINIT:
	I32 cxix;
	CODE:
		RETVAL = su_context_here();
	OUTPUT:
		RETVAL

void
SUB(...)
	PREINIT:
	I32 cxix;
	PPCODE:
		SU_GET_CONTEXT(0, cxstack_ix);
		EXTEND(SP, 1);
		for (; cxix >= 0; --cxix) {
			PERL_CONTEXT *cx = cxstack + cxix;
			switch (CxTYPE(cx)) {
				default:
					continue;
				case CXt_SUB:
					if (PL_DBsub && cx->blk_sub.cv == GvCV(PL_DBsub))
					continue;
					mPUSHi(cxix);
					XSRETURN(1);
			}
		}
		warn(su_no_such_target, "subroutine");
		XSRETURN_UNDEF;

int
UP(...)
	PREINIT:
	I32 cxix;
	CODE:
		SU_GET_CONTEXT(0, su_context_here());
		if (cxix > 0) {
			--cxix;
			cxix = su_context_skip_db(cxix);
			cxix = su_context_normalize_up(cxix);
		} else {
			warn(su_stack_smash);
		}
		RETVAL = cxix;
	OUTPUT:
		RETVAL

void
EVAL(...)
	PREINIT:
	I32 cxix;
	PPCODE:
		SU_GET_CONTEXT(0, cxstack_ix);
		EXTEND(SP, 1);
		for (; cxix >= 0; --cxix) {
			PERL_CONTEXT *cx = cxstack + cxix;
			switch (CxTYPE(cx)) {
				default:
					continue;
				case CXt_EVAL:
					mPUSHi(cxix);
					XSRETURN(1);
			}
		}
		warn(su_no_such_target, "eval");
		XSRETURN_UNDEF;

int
SCOPE(...)
	PREINIT:
	I32 cxix, level;
	CODE:
		SU_GET_LEVEL();
		cxix = su_context_here();
		while (--level >= 0) {
			if (cxix <= 0) {
				warn(su_stack_smash);
				break;
			}
			--cxix;
			cxix = su_context_skip_db(cxix);
			cxix = su_context_normalize_up(cxix);
		}
		RETVAL = cxix;
	OUTPUT:
		RETVAL

int
CALLER(...)
	PREINIT:
	I32 cxix, level;
	CODE:
		SU_GET_LEVEL();
		for (cxix = cxstack_ix; cxix > 0; --cxix) {
			PERL_CONTEXT *cx = cxstack + cxix;
			switch (CxTYPE(cx)) {
				case CXt_SUB:
					if (PL_DBsub && cx->blk_sub.cv == GvCV(PL_DBsub))
						continue;
				case CXt_EVAL:
				case CXt_FORMAT:
					if (--level < 0)
						goto done;
					break;
			}
		}
		done:
		if (level >= 0)
			warn(su_stack_smash);
		RETVAL = cxix;
	OUTPUT:
		RETVAL

void
unwind(...)
	PREINIT:
	dMY_CXT;
	I32 cxix;
	CODE:
	PERL_UNUSED_VAR(cv); /* -W */
	PERL_UNUSED_VAR(ax); /* -Wall */

	SU_GET_CONTEXT(items - 1, cxstack_ix);
	do {
		PERL_CONTEXT *cx = cxstack + cxix;
		switch (CxTYPE(cx)) {
			case CXt_SUB:
			if (PL_DBsub && cx->blk_sub.cv == GvCV(PL_DBsub))
				continue;
			case CXt_EVAL:
			case CXt_FORMAT:
				MY_CXT.cxix   = cxix;
				MY_CXT.items  = items;
				MY_CXT.savesp = PL_stack_sp;
				if (items > 0) {
					MY_CXT.items--;
					MY_CXT.savesp--;
				}
				/* pp_entersub will want to sanitize the stack after returning from there
				* Screw that, we're insane!
				* dXSARGS calls POPMARK, so we need to match PL_markstack_ptr[1] */
				if (GIMME_V == G_SCALAR)
					PL_stack_sp = PL_stack_base + PL_markstack_ptr[1] + 1;
				SAVEDESTRUCTOR_X(su_unwind, NULL);
				return;
			default:
				break;
		}
	} while (--cxix >= 0);
	croak("Can't return outside a subroutine");
