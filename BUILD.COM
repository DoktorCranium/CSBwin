$! ===========================================================================
$! BUILD.COM - CSBwin 15.7 for OpenVMS, SDL 1.2
$!
$! THIS IS THE CHECKED-IN FALLBACK.  @CONFIGURE.COM OVERWRITES IT with a
$! two-line version that hard-codes what it probed:
$!
$!   $ MMK/IGNORE=WARNING/MACRO=("SDLLIB=...","DEFS_EXTRA=...") 'P1' 'P2'
$!
$! The normal route is therefore
$!
$!   $ @CONFIGURE.COM
$!   $ @BUILD.COM
$!
$! and this file exists for the case where you already know your environment is
$! good and want to go straight to compiling - it builds with the DEFAULTS
$! COMPILED INTO DESCRIP.MMS, i.e. the SHARED SDL (LIBSDL:LIBSDL$SHR/OPT) and
$! no probed defines.  Those defaults are the right ones for an ordinary
$! OpenVMS 8.4 Alpha system; the two things that can differ are:
$!
$!   $ MMK/IGNORE=WARNING/MACRO=("SDLLIB=LIBSDL:LIBSDL/OPT")
$!         ... if your SDL is the static object library, not the shareable;
$!   $ MMK/IGNORE=WARNING/MACRO=("DEFS_EXTRA=VMS_NO_INTPTR_T")
$!         ... if <inttypes.h> on this CRTL does NOT declare intptr_t and
$!         uintptr_t, so that vmsglib.h has to typedef them itself.  8.4 DOES
$!         declare them, which is why this is not the default - see the
$!         DEFS_EXTRA comment in DESCRIP.MMS.  CONFIGURE.COM probes it.
$!
$! Usage:  $ @BUILD          build CSBWIN.EXE
$!         $ @BUILD CLEAN    delete objects, library and image
$!
$! /IGNORE=WARNING IS NOT OPTIONAL.  MMS and MMK both treat a warning-severity
$! status from an action as a build failure, and CXX warns on this tree.  See
$! the WARNDIS macro in DESCRIP.MMS for what those warnings are and why they
$! are left switched on rather than suppressed.
$!
$! Prerequisites, if CONFIGURE.COM has not vetted them for you:
$!   $ DEFINE SDL     <device:[dir]>    ! the directory holding SDL.H
$!   $ DEFINE LIBSDL  <device:[dir]>    ! ... holding LIBSDL$SHR.OPT
$!
$! EVERY COMMAND IN THIS FILE ENDS IN A "!" COMMENT, AND THAT IS DELIBERATE.
$! DCL does not strip a trailing carriage return from a command record (MMS and
$! MMK do), so on a tree copied over in binary mode the CR welds itself to the
$! last token of the line: "SET NOON" becomes the keyword "NOON<CR>", "EXIT"
$! becomes "EXIT<CR>", and a bare "0" becomes an invalid numeric value.  With a
$! trailing comment the CR lands inside the comment and is discarded.  There are
$! also no "-" continuation lines here, because a continuation needs the hyphen
$! to be the LAST character in the record and no comment can rescue it.  This
$! file is shipped with LF-only line endings for the same reason.  The full
$! diagnosis, with the transcript that produced it, is in the header of
$! CONFIGURE.COM.
$! ===========================================================================
$ SET NOON                                      ! report, do not abort
$!
$ IF F$TRNLNM("SDL") .EQS. "" .OR. F$TRNLNM("LIBSDL") .EQS. "" !
$  THEN !
$       WRITE SYS$OUTPUT "" !
$       WRITE SYS$OUTPUT "The SDL and LIBSDL logicals must both be defined:" !
$       WRITE SYS$OUTPUT "   $ DEFINE SDL     DKA0:[SDL.INCLUDE]" !
$       WRITE SYS$OUTPUT "   $ DEFINE LIBSDL  DKA0:[SDL.LIB]" !
$       WRITE SYS$OUTPUT "" !
$       WRITE SYS$OUTPUT "Run @CONFIGURE.COM for a full check of the environment." !
$       WRITE SYS$OUTPUT "" !
$       EXIT                                    ! nothing can be built
$ ENDIF !
$!
$! MMS is a product with a known image; MMK is a foreign command, so the test
$! for it is whether the symbol exists.  The result goes in MMKSYM, not MMK -
$! assigning to MMK would clobber the user's own command definition.
$ MMKSYM = F$TYPE(MMK)                          ! "" if there is no MMK symbol
$ MAKE = ""                                     ! neither found yet
$ IF MMKSYM .NES. "" THEN MAKE = "MMK"
$ IF F$SEARCH("SYS$SYSTEM:MMS.EXE") .NES. "" THEN MAKE = "MMS"
$ IF MAKE .EQS. "" !
$  THEN !
$       WRITE SYS$OUTPUT "" !
$       WRITE SYS$OUTPUT "Neither MMS nor MMK was found.  One of them is needed to read" !
$       WRITE SYS$OUTPUT "DESCRIP.MMS." !
$       WRITE SYS$OUTPUT "" !
$       EXIT                                    ! DESCRIP.MMS is the build
$ ENDIF !
$!
$ WRITE SYS$OUTPUT "Building CSBwin with ''MAKE' ..." !
$ 'MAKE'/IGNORE=WARNING 'P1' 'P2'                ! P1/P2 may both be empty
$ EXIT                                          ! done
