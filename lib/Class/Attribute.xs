#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "embed.h"

#define PERL_constant_NOTFOUND	1
#define PERL_constant_NOTDEF	2
#define PERL_constant_ISIV	3
#define PERL_constant_ISNO	4
#define PERL_constant_ISNV	5
#define PERL_constant_ISPV	6
#define PERL_constant_ISPVN	7
#define PERL_constant_ISSV	8
#define PERL_constant_ISUNDEF	9
#define PERL_constant_ISUV	10
#define PERL_constant_ISYES	11

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

MODULE = Class::Attribute		PACKAGE = Class::Attribute		

SV*
_read_attribute (self)
    SV *self;
  ALIAS:
  PPCODE:
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

