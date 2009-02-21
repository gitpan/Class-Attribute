#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "embed.h"

#define PERL_constant_NOTFOUND    1
#define PERL_constant_NOTDEF    2
#define PERL_constant_ISIV    3
#define PERL_constant_ISNO    4
#define PERL_constant_ISNV    5
#define PERL_constant_ISPV    6
#define PERL_constant_ISPVN    7
#define PERL_constant_ISSV    8
#define PERL_constant_ISUNDEF    9
#define PERL_constant_ISUV    10
#define PERL_constant_ISYES    11

#ifndef NVTYPE
typedef double NV; /* 5.6 and later define NVTYPE, and typedef NV to it.  */
#endif
#ifndef aTHX_
#define aTHX_ /* 5.6 or later define this for threading support.  */
#endif
#ifndef pTHX_
#define pTHX_ /* 5.6 or later define this for threading support.  */
#endif

int matches_regex (SV *re, char *str_start) {
    MAGIC *mg = NULL;

    SV *sv = SvRV(re);
    if (SvMAGICAL(sv))
        mg = mg_find(sv, PERL_MAGIC_qr);
    if (!mg)
        croak("regex is not a qr// entity");

    REGEXP *rx = (REGEXP *)mg->mg_obj;

    int str_len = strlen((char*)str_start);
    char *str_end = str_start + str_len;

    SV *wrapper = sv_newmortal();
    sv_upgrade(wrapper, SVt_PV);
    SvREADONLY_on(wrapper);
    SvLEN(wrapper) = 0;
    SvUTF8_on(wrapper); 
    SvPVX(wrapper) = (char*)str_start;
    SvCUR_set(wrapper, str_len);
    SvPOK_on(wrapper);

    SV *rv = (SV *)pregexec(rx, str_start, str_end, str_start, 1, wrapper, 1);
    return sv_iv(rv);
}

STATIC I32
__dopoptosub_at(const PERL_CONTEXT *cxstk, I32 startingblock) {
    I32 i;
    for (i = startingblock; i >= 0; i--) {
        if(CxTYPE((PERL_CONTEXT*)(&cxstk[i])) == CXt_SUB) return i;
    }
    return i;
}

CV* _subroutine_cv (void) {
    PERL_SI     *si;
    for (si = PL_curstackinfo; si; si = si->si_prev) {
        I32 ix;
        for (ix = si->si_cxix; ix >= 0; ix--) {
            const PERL_CONTEXT *cx = &(si->si_cxstack[ix]);
            if (CxTYPE(cx) == CXt_SUB || CxTYPE(cx) == CXt_FORMAT) {
                CV * const cv = cx->blk_sub.cv;
                return cv;
            }
            else if (CxTYPE(cx) == CXt_EVAL && !CxTRYBLOCK(cx))
                return PL_compcv;
        }
    }
    return PL_main_cv;
}

SV* _subroutine_name (void) {
    register I32 cxix = 1;
    register const PERL_CONTEXT *ccstack = cxstack;
    register const PERL_CONTEXT *cx = &ccstack[cxix];
    if (CxTYPE(cx) == CXt_SUB || CxTYPE(cx) == CXt_FORMAT) {
        GV * const cvgv = CvGV(ccstack[cxix].blk_sub.cv);
        if (isGV(cvgv)) {
            SV * const subroutine = newSV(0);
            gv_efullname(subroutine, cvgv);
            return subroutine;
        }
    }
    return newSVpvs("(unknown)");
}

char* _xs_method_owner (char *class, int idx, int type) {
    dSP;
    I32 ax;

    int count;
    SV *owner = NULL;
    SV *method = newSVpv(class, strlen(class));
    sv_catpv(method, "::_method_owner");

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    mXPUSHp(class, strlen(class));
    mXPUSHi(idx);
    mXPUSHi(type);
    PUTBACK;

    count = call_method(sv_pv(method), G_ARRAY);

    SPAGAIN;
    owner = POPs;
    PUTBACK;

    if (owner != NULL)
        return sv_pv(owner);
    else
        return NULL;
}


MODULE = Class::Attribute        PACKAGE = Class::Attribute        

SV*
_read_attribute (self)
    SV *self;
  ALIAS:
  PPCODE:
    AV *stash = (AV*)SvRV(self);
    SV **value = av_fetch(stash, (int)ix, 0);
    if (value != NULL)
        PUSHs(*value);

IV
_attribute_predicate (self)
    SV *self;
  ALIAS:
  PPCODE:
    AV *stash = (AV*)SvRV(self);
    SV **value = av_fetch(stash, (int)ix, 0);
    if (value == NULL || !*value)
        PUSHi(0);
    else
        PUSHi(1);

SV*
_read_protected_attribute (self)
    SV *self;
  ALIAS:
  PPCODE:
#ifdef USE_ITHREADS
    char *caller = PL_curcop->cop_stashpv;
#else
    char *caller = HvNAME(CopSTASH(PL_curcop));
#endif
    char *class  = (char *)sv_reftype(SvRV(self), 1);
    if (!sv_derived_from(newSVpv(caller, strlen(caller)), class))
        croak("Called a protected accessor defined in %s from %s", class, caller);
    AV *stash = (AV*)SvRV(self);
    SV **value = av_fetch(stash, (int)ix, 0);
    if (value != NULL)
        PUSHs(*value);

SV*
_read_private_attribute (self)
    SV *self;
  ALIAS:
  PPCODE:
    char *caller = HvNAME(CopSTASH(PL_curcop));
    char *class  = (char *)sv_reftype(SvRV(self), 1);

    HV *classmap = NULL;
    char *ixstr = sv_pv(newSViv(ix));
    HV *ownermap = get_hv("Class::Attribute::owner", 0);
    SV **cmap_ptr = hv_fetch(ownermap, caller, strlen(caller), 0);
    if (cmap_ptr && *cmap_ptr != NULL)
        classmap = (HV *)SvRV(*cmap_ptr);
    if (!classmap || !hv_exists(classmap, ixstr, 1)) {
        char *owner = _xs_method_owner(class, (int)ix, 0);
        croak("Called a private accessor '%s' from %s", owner, caller);
    }

    AV *stash = (AV*)SvRV(self);
    SV **value = av_fetch(stash, (int)ix, 0);
    if (value != NULL)
        PUSHs(*value);

int
_write_attribute (self, ... )
    SV *self;
  ALIAS:
  PPCODE:
    if (items != 2)
        croak("mutator expects a value");
    AV *stash = (AV*)SvRV(self);
    av_store(stash, (int)ix, newSVsv(ST(1)));
    XPUSHi(1);

int
_write_protected_attribute (self, ... )
    SV *self;
  ALIAS:
  PPCODE:
#ifdef USE_ITHREADS
    char *caller = PL_curcop->cop_stashpv;
#else
    char *caller = HvNAME(CopSTASH(PL_curcop));
#endif
    char *class  = (char *)sv_reftype(SvRV(self), 1);
    if (!sv_derived_from(newSVpv(caller, strlen(caller)), class))
        croak("Called a protected mutator defined in %s from %s", class, caller);
    if (items != 2)
        croak("mutator expects a value");
    AV *stash = (AV*)SvRV(self);
    av_store(stash, (int)ix, newSVsv(ST(1)));
    XPUSHi(1);

int
_write_private_attribute (self, ... )
    SV *self;
  ALIAS:
  PPCODE:
    int i;
    char *caller = HvNAME(CopSTASH(PL_curcop));
    char *class  = (char *)sv_reftype(SvRV(self), 1);

    HV *classmap = NULL;
    char *ixstr = sv_pv(newSViv(ix));
    HV *ownermap = get_hv("Class::Attribute::owner", 0);
    SV **cmap_ptr = hv_fetch(ownermap, caller, strlen(caller), 0);
    if (cmap_ptr && *cmap_ptr != NULL)
        classmap = (HV *)SvRV(*cmap_ptr);

    //printf("classmap: %p\n", classmap);

    if (!classmap || !hv_exists(classmap, ixstr, 1)) {
        char *owner = _xs_method_owner(class, (int)ix, 1);
        croak("Called a private mutator '%s' from %s", owner, caller);
    }

    if (items != 2)
        croak("mutator expects a value");
    AV *stash = (AV*)SvRV(self);
    av_store(stash, (int)ix, newSVsv(ST(1)));
    XPUSHi(1);

void
_make_accessor(class, name, index)
    char *class;
    char* name;
    int index;
  PPCODE:
    char* file = __FILE__;
    CV * cv;
    cv = newXS(name, XS_Class__Attribute__read_attribute, file);
    XSANY.any_i32 = index;
    if (cv == NULL)
        croak("failed to create an accessor!");

void
_make_protected_accessor(class, name, index)
    char *class;
    char* name;
    int index;
  PPCODE:
    char* file = __FILE__;
    CV * cv;
    cv = newXS(name, XS_Class__Attribute__read_protected_attribute, file);
    XSANY.any_i32 = index;
    if (cv == NULL)
        croak("failed to create an accessor!");

void
_make_private_accessor(class, name, index)
    char *class;
    char* name;
    int index;
  PPCODE:
    char* file = __FILE__;
    CV * cv;
    cv = newXS(name, XS_Class__Attribute__read_private_attribute, file);
    XSANY.any_i32 = index;
    if (cv == NULL)
        croak("failed to create an accessor!");

void
_make_mutator(class, name, index)
    char *class;
    char* name;
    int index;
  PPCODE:
    char* file = __FILE__;
    CV * cv;
    cv = newXS(name, XS_Class__Attribute__write_attribute, file);
    XSANY.any_i32 = index;
    if (cv == NULL)
        croak("failed to create a mutator!");

void
_make_protected_mutator(class, name, index)
    char *class;
    char* name;
    int index;
  PPCODE:
    char* file = __FILE__;
    CV * cv;
    cv = newXS(name, XS_Class__Attribute__write_protected_attribute, file);
    XSANY.any_i32 = index;
    if (cv == NULL)
        croak("failed to create a mutator!");

void
_make_private_mutator(class, name, index)
    char *class;
    char* name;
    int index;
  PPCODE:
    char* file = __FILE__;
    CV * cv;
    cv = newXS(name, XS_Class__Attribute__write_private_attribute, file);
    XSANY.any_i32 = index;
    if (cv == NULL)
        croak("failed to create a mutator!");

void
_make_predicate(class, name, index)
    char *class;
    char* name;
    int index;
  PPCODE:
    char* file = __FILE__;
    CV * cv;
    cv = newXS(name, XS_Class__Attribute__attribute_predicate, file);
    XSANY.any_i32 = index;
    if (cv == NULL)
        croak("failed to create a predicate!");

