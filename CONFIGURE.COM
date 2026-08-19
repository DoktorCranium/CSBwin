$! ===========================================================================
$! CONFIGURE.COM - CSBwin 15.7 (Dungeon Master / Chaos Strikes Back)
$!                 for OpenVMS 8.4 Alpha, SDL 1.2, HP C++ (CXX)
$!
$! Modelled on the sibling OpenVMS ports' CONFIGURE.COM - [-.ROTT]'s, Hexen's
$! (by Alexey Chupahin) and Chocolate Duke's - with the same deliberate
$! difference the ROTT port makes:
$!
$!   Hexen's CONFIGURE.COM *generates* DESCRIP.MMS inline with COPY/APPEND
$!   SYS$INPUT.  Here DESCRIP.MMS is a real, hand-maintained, commented file,
$!   and this script only VERIFIES the environment and writes BUILD.COM.  There
$!   is nothing to configure into the makefile: the 41-file build set is fixed
$!   and SDL 1.2 is a stated prerequisite, not an option.
$!
$! What is actually worth probing:
$!
$!   * that the line endings survived the transfer - see the next comment
$!     block, this is the one that bit first on real hardware;
$!   * that a C++ compiler and a build utility exist at all;
$!   * that this is not VAX;
$!   * that the three files this port ADDS to the upstream tree are present -
$!     the commonest transfer accident;
$!   * whether SDL is really 1.2, and whether the SHARED or the STATIC library
$!     is the one that links.  That changes the linker options file, so
$!     BUILD.COM overrides DESCRIP.MMS's SDLLIB macro with whichever worked;
$!   * whether <inttypes.h> on THIS CRTL declares intptr_t/uintptr_t.  The
$!     engine passes either a pointer or a small integer through single
$!     parameter slots (UI.h's CSB_UI_MESSAGE::p3, Chaos.cpp's _CALL3/_CALL4,
$!     atari_sprintf), and vmsglib.h either includes the header or typedefs the
$!     pair itself.  The answer is fed back into the build, and ONLY IF THE
$!     PROBE FAILS, as /MACRO=("DEFS_EXTRA=VMS_NO_INTPTR_T").  The macro is
$!     negative on purpose - OpenVMS 8.4 DOES declare the pair, so trusting the
$!     header is the common case and needs no macro at all.  See csbglib.h,
$!     which is where the substitute lives now - vmsglib.h is its __VMS alias,
$!     kept because the macOS build needs the same substitute and one copy is
$!     easier to keep right than two.
$!
$! ---------------------------------------------------------------------------
$! WHY THIS PROCEDURE LOOKS OVER-COMMENTED: EVERY COMMAND ENDS IN A "!"
$!
$! Read that literally - every executable line below ends with a "!" comment,
$! even where the comment says nothing useful.  That is not a style choice, it
$! is a bug fix, and it is worth understanding before you "tidy" it away.
$!
$! DCL DOES NOT STRIP A TRAILING CARRIAGE RETURN FROM A COMMAND RECORD.  MMS and
$! MMK do.  So a tree copied to OpenVMS in BINARY mode - CRLF text arriving as
$! stream records that each end in a CR - builds happily under MMK and then
$! makes this procedure fall apart, because DCL parses the CR as the last
$! character of the last token on the line.  The failure is spectacular and
$! completely misleading; this is the real transcript from an 8.4 Alpha system:
$!
$!    $ SET NOON             ->  %DCL-W-IVKEYW, unrecognized keyword \NOON
$!    $ CPU = "unknown"          (worked - see below)
$!    $ WRITE SYS$OUTPUT ..., CPU
$!                           ->  %DCL-W-UNDSYM, undefined symbol \CPU
$!    $ MMKSYM = F$TYPE(MMK) ->  %DCL-W-UNDSYM, undefined symbol \
$!    $ OK = 1               ->  %DCL-W-IVCHAR, invalid numeric value \1
$!    $ DEFINE SYS$ERROR  _NLA0:
$!                           ->  error opening _NLA0:, %RMS-F-SYN
$!
$! Note the diagnostics with a MISSING CLOSING BACKSLASH ("\NOON", "\CPU").
$! That is the tell: the CR is inside the quoted name and has overprinted the
$! delimiter.  "NOON<CR>" is not a keyword, "CPU<CR>" is not a symbol, and
$! "_NLA0:<CR>" is not a file specification.  And because SET NOON was itself
$! one of the casualties, the default ON ERROR was still armed, so the first
$! command of ERROR severity (the DEFINE) silently abandoned the procedure -
$! which is why the transcript simply stops with no explanation.
$!
$! The one construct that SURVIVES a trailing CR is a command whose last token
$! is a QUOTED STRING: the CR falls outside the closing quote and DCL ignores
$! it as trailing whitespace.  That is exactly why 'CPU = "unknown"' worked
$! while 'OK = 1' did not, and it is the pattern the two fixes are built on:
$!
$!   1. Every command here ends either in a quoted string or in a "!" comment,
$!      so a trailing CR always lands somewhere DCL discards.  Where a value
$!      would otherwise be bare it is quoted anyway - DEFINE SYS$ERROR
$!      "_NLA0:", not DEFINE SYS$ERROR _NLA0:.
$!   2. There are NO "-" continuation lines.  A continuation needs the "-" to
$!      be the last character in the record, and a CR after it is not a comment
$!      and cannot be commented away.  Long commands are written out in full,
$!      and long strings are built up with "+" into a symbol first.
$!
$! Labels get the same treatment ("$FAILED: !"), because a CR would otherwise
$! make the label FAILED:<CR> and every GOTO to it fail.
$!
$! Belt and braces: this file, and BUILD.COM, are shipped with LF-only line
$! endings even though the rest of the tree is CRLF, so a binary-mode transfer
$! produces clean records with no CR in the first place.  The hardening above is
$! for the copy that arrives some other way.  And the LINE ENDINGS check below
$! reports the situation instead of leaving you to deduce it.
$! ---------------------------------------------------------------------------
$!
$! USAGE
$!
$!   $ DEFINE SDL     <device:[dir]>    ! the directory holding SDL.H
$!   $ DEFINE LIBSDL  <device:[dir]>    ! ... holding LIBSDL$SHR.OPT / LIBSDL.OPT
$!   $ @CONFIGURE.COM
$!   $ @BUILD.COM
$!
$! SDL_mixer is NOT required and MUST NOT be added: SoundMixer.cpp in this
$! directory implements the Mix_* subset the engine uses directly over SDL 1.2
$! audio, and an external SDL_mixer would collide with it.  See DESCRIP.MMS.
$! ===========================================================================
$!
$! SET NOON: several steps below are EXPECTED to fail (that is what a probe is),
$! and DCL would otherwise abandon the script on the first one.  Each is
$! followed by an explicit $SEVERITY test.
$ SET NOON                                      ! probes are allowed to fail
$ WRITE SYS$OUTPUT " " !
$ WRITE SYS$OUTPUT "Configuring CSBwin 15.7 (Dungeon Master / Chaos Strikes Back)" !
$ WRITE SYS$OUTPUT "  for OpenVMS, SDL 1.2" !
$ WRITE SYS$OUTPUT " " !
$!
$! --- Line endings ------------------------------------------------------------
$! Read the first record of this very file and look for a carriage return.  If
$! there is one here there is one in all 200-odd files, because they all came
$! over the same way - and knowing that NOW explains both the thousands of
$! %CXX-W-FOUNDCR diagnostics you are about to see and any DCL oddity that gets
$! past the hardening described in the header.
$!
$! The test is on the LAST character of the record, because that is precisely
$! the one that hurts: a CR anywhere else would be a curiosity, a CR at the end
$! is what welds itself onto the final token of a command.  F$CVUI pulls an
$! unsigned bit field straight out of a string, so we can ask for the character
$! code without having to construct a carriage return first - which would mean
$! embedding a literal control character in a file that has to survive the very
$! transfer we are trying to diagnose.
$ HAVE_CR = 0                                   ! assume a clean text transfer
$ OPEN/READ/ERROR=CR_DONE CFG CONFIGURE.COM     ! cannot open: skip the check
$ READ/END_OF_FILE=CR_SHUT/ERROR=CR_SHUT CFG REC ! first record is enough
$ RECLEN = F$LENGTH(REC)                        ! 0 would break F$EXTRACT below
$ IF RECLEN .EQ. 0 THEN GOTO CR_SHUT            ! empty first record: give up
$ LASTCH = F$EXTRACT(RECLEN - 1, 1, REC)        ! the suspect character
$ IF F$CVUI(0, 8, LASTCH) .EQ. 13 THEN HAVE_CR = 1 ! 13 = ASCII CR
$CR_SHUT: !
$ CLOSE CFG                                     ! never leave a channel open
$CR_DONE: !
$ IF HAVE_CR .EQ. 0                             ! nothing to report
$  THEN !
$       WRITE SYS$OUTPUT "Checking line endings         ...  VMS records (text mode transfer)" !
$  ELSE !
$       WRITE SYS$OUTPUT "Checking line endings         ...  CR-terminated (binary transfer)" !
$ ENDIF !
$!
$! --- Architecture and OS -----------------------------------------------------
$ CPU = "unknown"                               ! F$GETSYI ARCH_TYPE 1/2/3
$ IF F$GETSYI("ARCH_TYPE") .EQ. 1 THEN CPU = "VAX" !
$ IF F$GETSYI("ARCH_TYPE") .EQ. 2 THEN CPU = "Alpha" !
$ IF F$GETSYI("ARCH_TYPE") .EQ. 3 THEN CPU = "I64" !
$ WRITE SYS$OUTPUT "Checking architecture         ...  ''CPU'" !
$ VMSVER = F$GETSYI("VERSION")                  ! e.g. "V8.4"
$ WRITE SYS$OUTPUT "Checking OS                   ...  OpenVMS ''VMSVER'" !
$ IF CPU .EQS. "VAX"                            ! no 64-bit integer type
$  THEN !
$       WRITE SYS$OUTPUT " " !
$       WRITE SYS$OUTPUT "VAX is not supported.  CSBTypes.h builds the engine's i64/ui64" !
$       WRITE SYS$OUTPUT "out of a 64-bit integer type and prints them with INT64_FMT; the" !
$       WRITE SYS$OUTPUT "recorded-playback timestamps and UI_GetSystemTime depend on it," !
$       WRITE SYS$OUTPUT "and VAX C++ has no 'long long'.  Alpha or I64 is required." !
$       GOTO FAILED                             ! not a fixable condition
$ ENDIF !
$!
$! --- Compiler ----------------------------------------------------------------
$! It is the C++ compiler that has to be here.  This is 41 .cpp files with
$! classes, virtual methods and try/catch - DEC C on its own cannot build it.
$ IF F$SEARCH("SYS$SYSTEM:CXX$COMPILER.EXE") .EQS. "" !
$  THEN !
$       WRITE SYS$OUTPUT "Checking compiler             ...  not found" !
$       WRITE SYS$OUTPUT " " !
$       WRITE SYS$OUTPUT "HP C++ for OpenVMS (SYS$SYSTEM:CXX$COMPILER.EXE) is required." !
$       GOTO FAILED                             ! nothing else can be probed
$ ENDIF !
$ WRITE SYS$OUTPUT "Checking compiler             ...  HP C++ (CXX)" !
$!
$! --- Build utility -----------------------------------------------------------
$! MMS is a product with a known image; MMK is a foreign command, so the test is
$! whether the SYMBOL exists.  Note the result goes in MMKSYM, not MMK: writing
$! to MMK would clobber the user's own command definition for the rest of the
$! process.
$ HAVE_MMS = F$SEARCH("SYS$SYSTEM:MMS.EXE") .NES. "" !
$ MMKSYM   = F$TYPE(MMK)                        ! "" if there is no MMK symbol
$ MAKE     = "" !
$ IF MMKSYM .NES. "" THEN MAKE = "MMK" !
$ IF HAVE_MMS .EQ. 1 THEN MAKE = "MMS" !
$ IF MAKE .EQS. "" !
$  THEN !
$       WRITE SYS$OUTPUT "Checking build utility        ...  none" !
$       WRITE SYS$OUTPUT " " !
$       WRITE SYS$OUTPUT "Either MMS or MMK is required to read DESCRIP.MMS." !
$       GOTO FAILED                             ! DESCRIP.MMS is the build
$ ENDIF !
$ WRITE SYS$OUTPUT "Checking build utility        ...  ''MAKE'" !
$!
$! --- The files this port adds ------------------------------------------------
$! Cheap, and it catches copying the upstream tree without the port.  Without
$! VMSFileName.inl, system.cpp's "#if defined __VMS" arm has nothing to include
$! and every name the engine builds stays a POSIX path.
$! csbglib.h is checked as well as vmsglib.h: the GLib substitute's content
$! lives in csbglib.h now (the macOS build needs the same substitute, so there
$! is one copy instead of two) and vmsglib.h is the one-line __VMS alias for it.
$! Either one missing is the same incomplete copy.
$ OK = 1                                        ! 1 = all four present
$ IF F$SEARCH("VMSFileName.inl") .EQS. "" THEN OK = 0 !
$ IF F$SEARCH("vmsglib.h")       .EQS. "" THEN OK = 0 !
$ IF F$SEARCH("csbglib.h")       .EQS. "" THEN OK = 0 !
$ IF F$SEARCH("DESCRIP.MMS")     .EQS. "" THEN OK = 0 !
$ IF OK .EQ. 0 !
$  THEN !
$       WRITE SYS$OUTPUT "Checking port files           ...  MISSING" !
$       WRITE SYS$OUTPUT " " !
$       WRITE SYS$OUTPUT "VMSFileName.inl, vmsglib.h, csbglib.h and DESCRIP.MMS must all be" !
$       WRITE SYS$OUTPUT "in this directory.  See README.VMS." !
$       GOTO FAILED                             ! an incomplete copy
$ ENDIF !
$ WRITE SYS$OUTPUT "Checking port files           ...  Yes" !
$!
$! --- SDL logicals ------------------------------------------------------------
$! Translated into symbols first: a lexical function as the last item of a WRITE
$! list is one of the constructs a trailing CR destroys, and WRITE evaluates its
$! whole list before printing anything, so one bad item loses the entire line.
$ SDLDIR = F$TRNLNM("SDL")                      ! "" if not defined
$ IF SDLDIR .EQS. "" !
$  THEN !
$       WRITE SYS$OUTPUT "Checking logical SDL          ...  not defined" !
$       WRITE SYS$OUTPUT " " !
$       WRITE SYS$OUTPUT "Define it to the directory holding SDL.H, e.g." !
$       WRITE SYS$OUTPUT "   $ DEFINE SDL  DKA0:[SDL.INCLUDE]" !
$       GOTO FAILED                             ! /INCLUDE=(SDL) needs it
$ ENDIF !
$ WRITE SYS$OUTPUT "Checking logical SDL          ...  ''SDLDIR'" !
$ LIBDIR = F$TRNLNM("LIBSDL")                   ! "" if not defined
$ IF LIBDIR .EQS. "" !
$  THEN !
$       WRITE SYS$OUTPUT "Checking logical LIBSDL       ...  not defined" !
$       WRITE SYS$OUTPUT " " !
$       WRITE SYS$OUTPUT "Define it to the directory holding the SDL linker options" !
$       WRITE SYS$OUTPUT "files, e.g." !
$       WRITE SYS$OUTPUT "   $ DEFINE LIBSDL  DKA0:[SDL.LIB]" !
$       GOTO FAILED                             ! the link needs it
$ ENDIF !
$ WRITE SYS$OUTPUT "Checking logical LIBSDL       ...  ''LIBDIR'" !
$!
$! --- Compile, link and RUN an SDL 1.2 probe ----------------------------------
$! The three-stage check the sibling ports use, with two differences:
$!
$!   * CXX, not CC, because that is the compiler this port builds with;
$!   * /DEFINE=("DECLSPEC=","SDLCALL=") - BEGIN_CODE.H only defines DECLSPEC
$!     when the macro "VMS" is set, and HP C++ predefines "__VMS", not "VMS",
$!     so without these two the first SDL prototype is a syntax error.  The
$!     real build passes them too; see DESCRIP.MMS.
$!
$! Compiling is not enough: it is the LINK that tells us shared versus static,
$! and only RUNning proves the shared image actually activates and that this
$! really is 1.2 rather than a 2.x header set behind a 1.2-named logical.
$!
$! The severity test accepts 1 (success) and 0 (warning) and rejects 2 (error)
$! and 4 (fatal).  Warnings are tolerated on purpose - the byte-packed SDL
$! headers can produce them, and so can the FOUNDCR flood if this tree was
$! transferred in binary - and anything genuinely broken fails at the next
$! stage anyway.
$!
$! The CXX command is one long line because a "-" continuation cannot be made
$! CR-proof.  See the header.
$ HAVE_LIBSDL   = 0                             ! 1 once the probe has RUN
$ LIBSDL_STATIC = 0                             ! 1 if only LIBSDL.OPT links
$ DEFINE SYS$ERROR  "_NLA0:"                    ! quoted: CR-proof, see header
$ DEFINE SYS$OUTPUT "_NLA0:"                    ! hide the probe's diagnostics
$ CXX/NAME=(AS_IS,SHORTENED)/FLOAT=IEEE/OBJECT=TEST.OBJ/DEFINE=("DECLSPEC=","SDLCALL=")/INCLUDE=(SDL) SYS$INPUT !
#include <stdio.h>
#include <stdlib.h>
#include <SDL.h>

int main(int argc, char *argv[])
{
    const SDL_version *v;

    /* SDL_Init(0) rather than SDL_INIT_VIDEO: this probe must succeed on a
       machine with no X display, because the BUILD does not need one - only
       playing the game does. */
    if (SDL_Init(0) < 0)
    {
        fprintf(stderr, "Couldn't initialize SDL: %s\n", SDL_GetError());
        exit(2);
    }

    v = SDL_Linked_Version();
    printf("Checking version libSDL       ...  %d.%d.%d\n",
           v->major, v->minor, v->patch);

    /* The -DSDL12 platform layer IS the SDL 1.2 API: SDL_SetVideoMode, the
       SDL_Surface flags, SDL_LockSurface/SDL_UpdateRects, the SDLK_* keysyms,
       SDL_EnableUNICODE, SDL_AddTimer, and SDL_OpenAudio with a callback.  SDL
       2 renamed or removed all of it, and the SDL20 arm of LinCSBUI.cpp wants
       SDL_CreateWindow/SDL_CreateTexture instead.  So refuse anything else
       here rather than after forty-one failed compilations. */
    if (v->major != 1 || v->minor != 2)
    {
        printf("This port needs SDL 1.2, not %d.%d.\n", v->major, v->minor);
        SDL_Quit();
        exit(2);
    }

    /* Report the packing of SDL_Surface.  On the OpenVMS SDL this is 74 and
       not 88, because SDL_config.h opens with an unbalanced "#pragma pack (1)"
       and LIBSDL$SHR was itself built that way - so a byte-packed SDL_Surface
       here means the headers AGREE with the prebuilt library, which is the
       thing that matters: WinScreen.cpp reads ->pixels and ->pitch straight
       out of the struct.  88 is not automatically wrong either (an unpatched
       header set plus a library built from it is equally self-consistent),
       which is why this is REPORTED and not enforced.  See stdafx.h and
       COMPILER_FIXES.TXT. */
    printf("Checking sizeof(SDL_Surface)  ...  %d %s\n",
           (int)sizeof(SDL_Surface),
           (sizeof(SDL_Surface) == 74) ? "(byte-packed, as expected)"
                                       : "(not byte-packed - see README.VMS)");

    SDL_Quit();
    return(0);
}

$ TMP = $SEVERITY                               ! 1 ok, 0 warning, 2/4 bad
$ DEASSIGN SYS$OUTPUT                           ! restore before printing
$ DEASSIGN SYS$ERROR                            ! ... anything ourselves
$ IF (TMP .EQ. 2) .OR. (TMP .EQ. 4) THEN GOTO SDL_DONE ! nothing to link
$!
$! Link: shared first, since that is what DESCRIP.MMS defaults to.
$ DEFINE SYS$ERROR  "_NLA0:"                    ! see header re quoting
$ DEFINE SYS$OUTPUT "_NLA0:" !
$ CXXLINK/THREAD=UP/EXE=TEST.EXE TEST.OBJ,LIBSDL:LIBSDL$SHR/OPT !
$ TMP = $SEVERITY                               ! did the shareable link?
$ DEASSIGN SYS$OUTPUT !
$ DEASSIGN SYS$ERROR !
$ IF (TMP .EQ. 2) .OR. (TMP .EQ. 4)             ! no - try the object library
$  THEN !
$       DEFINE SYS$ERROR  "_NLA0:" !
$       DEFINE SYS$OUTPUT "_NLA0:" !
$       CXXLINK/THREAD=UP/EXE=TEST.EXE TEST.OBJ,LIBSDL:LIBSDL/OPT !
$       TMP = $SEVERITY                         ! did the static one link?
$       DEASSIGN SYS$OUTPUT !
$       DEASSIGN SYS$ERROR !
$       IF (TMP .EQ. 2) .OR. (TMP .EQ. 4) THEN GOTO SDL_DONE ! neither works
$       LIBSDL_STATIC = 1                       ! remember for SDLLIB below
$ ENDIF !
$!
$! Run it.  SYS$OUTPUT is deliberately NOT redirected - the probe prints the
$! two "Checking ..." lines above itself, in the same format as the rest of
$! this script.  SYS$ERROR is, so that a failed image activation is reported
$! by us rather than as a raw %DCL-W-ACTIMAGE.
$ DEFINE SYS$ERROR "_NLA0:"                     ! hide %DCL-W-ACTIMAGE
$ RUN TEST.EXE                                  ! prints two Checking... lines
$ TMP = $SEVERITY                               ! exit(2) from the probe = 2
$ DEASSIGN SYS$ERROR !
$ IF TMP .EQ. 1 THEN HAVE_LIBSDL = 1            ! compiled, linked AND ran
$!
$SDL_DONE: !
$ IF HAVE_LIBSDL .EQ. 0 !
$  THEN !
$       WRITE SYS$OUTPUT "Checking for correct libSDL   ...  No" !
$       WRITE SYS$OUTPUT " " !
$       WRITE SYS$OUTPUT "SDL 1.2 could not be compiled, linked and run.  Check the SDL" !
$       WRITE SYS$OUTPUT "and LIBSDL logicals reported above.  To see the diagnostics that" !
$       WRITE SYS$OUTPUT "were suppressed, run the probe by hand:" !
$       WRITE SYS$OUTPUT " " !
$       WRITE SYS$OUTPUT "   $ CXX/DEFINE=(""DECLSPEC="",""SDLCALL="")/INCLUDE=(SDL) x.cxx" !
$       WRITE SYS$OUTPUT "   $ CXXLINK/THREAD=UP x,LIBSDL:LIBSDL$SHR/OPT" !
$       WRITE SYS$OUTPUT " " !
$       WRITE SYS$OUTPUT "for a file x.CXX containing #include <SDL.h> and a main()." !
$       GOTO FAILED                             ! SDL 1.2 is not optional
$ ENDIF !
$ IF LIBSDL_STATIC .EQ. 1 !
$  THEN !
$       WRITE SYS$OUTPUT "Checking for correct libSDL   ...  Yes (static)" !
$       SDLLIB = "LIBSDL:LIBSDL/OPT" !
$  ELSE !
$       WRITE SYS$OUTPUT "Checking for correct libSDL   ...  Yes (shared)" !
$       SDLLIB = "LIBSDL:LIBSDL$SHR/OPT" !
$ ENDIF !
$!
$! --- intptr_t ----------------------------------------------------------------
$! The one probe whose answer changes the build.  It does not merely INCLUDE
$! <inttypes.h> - a header that exists but does not declare intptr_t would then
$! pass - it DECLARES SOMETHING THAT USES the type.
$!
$! THE POLARITY MATTERS AND IT USED TO BE WRONG.  This once emitted a positive
$! VMS_HAVE_INTPTR_T, which meant the DEFAULT was for vmsglib.h to typedef the
$! two types itself.  On a real 8.4 Alpha system that is a hard error on the
$! first file of the build - <inttypes.h> there DOES declare them, in
$! DECC$RTLDEF.TLB module INTTYPES, and stdafx.h has already pulled the header
$! in via SDL_stdinc.h before vmsglib.h is read:
$!
$!    %CXX-E-BADTYPNAMRED, invalid redeclaration of type name "intptr_t"
$!
$! So the macro is now NEGATIVE.  Trusting the header is the default and needs
$! no macro at all, which also means a bare "$ MMK" with no CONFIGURE.COM run
$! behind it does the right thing; VMS_NO_INTPTR_T is emitted only when the
$! probe below actually fails, for a CRTL old enough not to declare the pair.
$!
$! It is not spelled HAVE_INTTYPES_H on purpose: the OpenVMS SDL's SDL_config.h
$! defines that unconditionally, so it answers "SDL says the header exists",
$! which is precisely the assumption this probe replaces.  See csbglib.h.
$ DEFINE SYS$ERROR  "_NLA0:" !
$ DEFINE SYS$OUTPUT "_NLA0:" !
$ CXX/NAME=(AS_IS,SHORTENED)/FLOAT=IEEE/OBJECT=TEST2.OBJ SYS$INPUT !
#include <inttypes.h>

intptr_t  probe_signed(void *p)   { return (intptr_t)p;  }
uintptr_t probe_unsigned(void *p) { return (uintptr_t)p; }

int main(int argc, char *argv[])
{
    return (int)(probe_signed(0) + probe_unsigned(0));
}

$ TMP = $SEVERITY                               ! 2 or 4 = no such type
$ DEASSIGN SYS$OUTPUT !
$ DEASSIGN SYS$ERROR !
$ IF (TMP .EQ. 2) .OR. (TMP .EQ. 4) !
$  THEN !
$       WRITE SYS$OUTPUT "Checking for intptr_t         ...  No (vmsglib.h supplies it)" !
$       DEFS_EXTRA = "VMS_NO_INTPTR_T"          ! take vmsglib.h's typedefs
$  ELSE !
$       WRITE SYS$OUTPUT "Checking for intptr_t         ...  Yes (<inttypes.h>)" !
$       DEFS_EXTRA = "CSBWIN_VMS_BUILD"         ! inert marker, see DESCRIP.MMS
$ ENDIF !
$!
$! --- The FOUNDCR warning tag -------------------------------------------------
$! Only worth asking if this tree really does have CR-terminated records, and
$! then it is worth a lot: CXX will otherwise diagnose a stray carriage return
$! on every line of a 3.5MB source tree and bury every real message.
$!
$! FOUNDCR is a DEC C (CC) message name and this port compiles with CXX, whose
$! message set is NOT the same - an unknown tag produces one %CXX-W-UNKMSGID
$! per compilation, which is itself warning severity and so would abort the
$! target under MMS.  That is why DESCRIP.MMS leaves it out of WARNDIS.  So do
$! not guess: compile something trivial with the tag disabled and see whether
$! CXX complains.  A clean compile is severity 1; UNKMSGID drags it to 0.
$!
$! The skip is a GOTO round the whole thing rather than an IF/THEN block, so
$! that the SYS$INPUT data lines below sit at the top level of the procedure
$! like the other two probes.  Feeding an image from SYS$INPUT inside a block IF
$! ought to work, but "ought to" is not a good enough reason to be the only
$! place in this file that relies on it.
$ WARNDIS_ALL = ""                              ! "" = leave DESCRIP.MMS alone
$ IF HAVE_CR .EQ. 0 THEN GOTO CR_TAG_DONE       ! no CRs: no need to ask
$ DEFINE SYS$ERROR  "_NLA0:" !
$ DEFINE SYS$OUTPUT "_NLA0:" !
$ CXX/NAME=(AS_IS,SHORTENED)/FLOAT=IEEE/OBJECT=TEST3.OBJ/WARNINGS=(DISABLE=(FOUNDCR)) SYS$INPUT !
int main(int argc, char *argv[])
{
    return 0;
}

$ TMP = $SEVERITY                               ! 1 = tag accepted and clean
$ DEASSIGN SYS$OUTPUT !
$ DEASSIGN SYS$ERROR !
$ IF TMP .EQ. 1 !
$  THEN !
$       WRITE SYS$OUTPUT "Checking FOUNDCR warning tag  ...  accepted (will be disabled)" !
$       WARNDIS_ALL = "INTOVERFLOW,SHIFTCNTBIG,CODEUNREACHABLE,UNRECPRAGMA,MISSINGRETURN,FOUNDCR" !
$  ELSE !
$       WRITE SYS$OUTPUT "Checking FOUNDCR warning tag  ...  not known to CXX" !
$ ENDIF !
$CR_TAG_DONE: !
$!
$! --- Sound -------------------------------------------------------------------
$! Nothing to probe.  SoundMixer.cpp is part of the build set and needs nothing
$! beyond the SDL audio the probe above already linked against; there is no
$! SDL_mixer, no ESound and no /DEFINE=SOUND__ESOUND in this port.  If the
$! OpenVMS SDL cannot open an audio device at run time, LinCSBUI.cpp says so
$! and the game plays silently.
$ WRITE SYS$OUTPUT "Checking sound                ...  bundled SoundMixer (SDL audio)" !
$!
$! --- The game data -----------------------------------------------------------
$! Not fatal at build time - the data need only be present when you PLAY - but
$! a missing DUNGEON.DAT is the commonest reason a correctly built CSBWIN.EXE
$! exits at once, and it is friendlier to say so now than after 41
$! compilations.  The engine opens these by plain name in the current default
$! directory unless --directory / --module / --root-path says otherwise, and
$! VMSFileName.inl turns whatever it builds into a real VMS file spec.
$ HAVE_DATA = 1                                 ! 0 if DM's two files are absent
$ IF F$SEARCH("DUNGEON.DAT") .NES. "" !
$  THEN !
$       WRITE SYS$OUTPUT "Checking for DUNGEON.DAT      ...  Yes" !
$  ELSE !
$       WRITE SYS$OUTPUT "Checking for DUNGEON.DAT      ...  not in this directory" !
$       HAVE_DATA = 0 !
$ ENDIF !
$ IF F$SEARCH("GRAPHICS.DAT") .NES. "" !
$  THEN !
$       WRITE SYS$OUTPUT "Checking for GRAPHICS.DAT     ...  Yes" !
$  ELSE !
$       WRITE SYS$OUTPUT "Checking for GRAPHICS.DAT     ...  not in this directory" !
$       HAVE_DATA = 0 !
$ ENDIF !
$! One IF per line, no THEN continuation: see the header.
$ IF F$SEARCH("HCSB.DAT") .NES. "" THEN WRITE SYS$OUTPUT "Checking for HCSB.DAT         ...  Yes (Chaos Strikes Back)" !
$ IF F$SEARCH("HCSB.HCT") .NES. "" THEN WRITE SYS$OUTPUT "Checking for HCSB.HCT         ...  Yes (CSB hint text)" !
$ IF F$SEARCH("MINI.DAT") .NES. "" THEN WRITE SYS$OUTPUT "Checking for MINI.DAT         ...  Yes (CSB utility dungeon)" !
$!
$! --- Write BUILD.COM ---------------------------------------------------------
$! /IGN=WAR is not optional: MMS and MMK both treat a warning-severity status
$! from an action as a failure and abandon the build, and CXX warns on this
$! tree.  DESCRIP.MMS explains which warnings and why they are left enabled.
$!
$! The command is assembled into a symbol with "+" rather than written as one
$! long WRITE list, for two reasons: a WRITE list ending in a symbol is exactly
$! the construct a trailing CR ruins, and it lets the WARNDIS override be
$! appended conditionally without duplicating the whole line.
$!
$! Q holds one double-quote character.  """" is DCL for a string containing a
$! single quote, and building the quotes this way keeps every line here short
$! enough to read - the alternative is a thicket of doubled quotes.
$!
$! 'P1' and 'P2' are written LITERALLY, for BUILD.COM to substitute when IT
$! runs.  Inside a quoted string DCL only substitutes on a DOUBLED apostrophe
$! (''MAKE' above), so a single one passes straight through.  They let you say
$! "@BUILD CLEAN" or "@BUILD CSBWIN.EXE".
$!
$! Note that BUILD.COM itself is created here by OPEN/WRITE, so its records are
$! real VMS records and it can never have the trailing-CR problem this file was
$! hardened against - whatever the line endings of the tree around it.
$ WRITE SYS$OUTPUT " " !
$ WRITE SYS$OUTPUT "Generating BUILD.COM" !
$ Q = """"                                      ! one double-quote character
$ MACROS = Q + "SDLLIB=" + SDLLIB + Q !
$ MACROS = MACROS + "," + Q + "DEFS_EXTRA=" + DEFS_EXTRA + Q !
$ IF WARNDIS_ALL .NES. "" THEN MACROS = MACROS + "," + Q + "WARNDIS=" + WARNDIS_ALL + Q !
$ CMD = "$ " + MAKE + "/IGNORE=WARNING/MACRO=(" + MACROS + ") 'P1' 'P2'" !
$ OPEN/WRITE OUT BUILD.COM                      ! overwrites the shipped one
$ WRITE OUT "$! BUILD.COM - written by CONFIGURE.COM.  Do not edit: re-run" !
$ WRITE OUT "$! @CONFIGURE.COM instead.  Build options live in DESCRIP.MMS." !
$ WRITE OUT "$!" !
$ WRITE OUT "$!   $ @BUILD          ! build CSBWIN.EXE" !
$ WRITE OUT "$!   $ @BUILD CLEAN    ! remove objects, library, image" !
$ WRITE OUT "$ SET NOON" !
$ WRITE OUT CMD                                 ! the line assembled above
$ CLOSE OUT                                     ! flush it to disk
$!
$! --- What to do next ---------------------------------------------------------
$ WRITE SYS$OUTPUT " " !
$ WRITE SYS$OUTPUT "Now you can type @BUILD" !
$ WRITE SYS$OUTPUT " " !
$ WRITE SYS$OUTPUT "That produces CSBWIN.EXE in this directory.  To run it, define" !
$ WRITE SYS$OUTPUT "a FOREIGN COMMAND - the leading ""$"" is what matters, because it" !
$ WRITE SYS$OUTPUT "hands the command line to the game instead of letting DCL parse" !
$ WRITE SYS$OUTPUT "switches such as --small as its own:" !
$ WRITE SYS$OUTPUT " " !
$ HERE = F$ENVIRONMENT("DEFAULT")               ! device:[directory]
$ WRITE SYS$OUTPUT "   $ CSBWIN == ""$''HERE'CSBWIN.EXE""" !
$ WRITE SYS$OUTPUT "   $ CSBWIN" !
$ WRITE SYS$OUTPUT " " !
$ WRITE SYS$OUTPUT "QUOTE ANY ARGUMENT THAT IS A FILE SPECIFICATION.  DCL upcases" !
$ WRITE SYS$OUTPUT "unquoted foreign-command arguments, and while this port folds the" !
$ WRITE SYS$OUTPUT "SWITCH NAMES back to lower case itself, it cannot fold a path -" !
$ WRITE SYS$OUTPUT "that would be wrong on an ODS-5 disk:" !
$ WRITE SYS$OUTPUT " " !
$ WRITE SYS$OUTPUT "   $ CSBWIN --small ""--directory"" ""DKA0:[CSB]""" !
$ WRITE SYS$OUTPUT " " !
$ IF HAVE_DATA .EQ. 0 !
$  THEN !
$       WRITE SYS$OUTPUT "DUNGEON.DAT and GRAPHICS.DAT must be reachable when you RUN the" !
$       WRITE SYS$OUTPUT "game - in the current default directory, or in the one named by" !
$       WRITE SYS$OUTPUT "--directory.  The engine reports the missing file and exits." !
$       WRITE SYS$OUTPUT " " !
$ ENDIF !
$ WRITE SYS$OUTPUT "Saved games are WRITTEN to that same directory, and the traces and" !
$ WRITE SYS$OUTPUT "session logs into [.TRACES] and [.LOGS] below it, so it needs write" !
$ WRITE SYS$OUTPUT "access - it need not be the directory holding CSBWIN.EXE." !
$ WRITE SYS$OUTPUT " " !
$ WRITE SYS$OUTPUT "An X display is required to PLAY: SDL 1.2 on OpenVMS draws through" !
$ WRITE SYS$OUTPUT "its X11 video driver, so DECW$DISPLAY must be defined - a local" !
$ WRITE SYS$OUTPUT "DECwindows session, or SET DISPLAY/CREATE to an X server elsewhere." !
$ WRITE SYS$OUTPUT " " !
$ IF HAVE_CR .EQ. 1 !
$  THEN !
$       WRITE SYS$OUTPUT "ONE MORE THING: THIS TREE WAS TRANSFERRED IN BINARY MODE.  Every" !
$       WRITE SYS$OUTPUT "record still ends in a carriage return, which is why the line" !
$       WRITE SYS$OUTPUT "endings check above says so.  Nothing is broken - this procedure" !
$       WRITE SYS$OUTPUT "and BUILD.COM are written to survive it, and DESCRIP.MMS is read" !
$       WRITE SYS$OUTPUT "by MMS/MMK, which strips the CR - but CXX may diagnose a stray" !
$       WRITE SYS$OUTPUT "carriage return on every line of every source file.  The clean" !
$       WRITE SYS$OUTPUT "fix is to re-copy the sources in TEXT mode:" !
$       WRITE SYS$OUTPUT " " !
$       WRITE SYS$OUTPUT "   $ UNZIP -a csbwin.zip          (or FTP in ASCII mode)" !
$       WRITE SYS$OUTPUT " " !
$       WRITE SYS$OUTPUT "and transfer the GAME DATA files in BINARY mode, separately." !
$       WRITE SYS$OUTPUT " " !
$ ENDIF !
$ GOTO CLEANUP                                  ! skip the failure banner
$!
$FAILED: !
$ WRITE SYS$OUTPUT " " !
$ WRITE SYS$OUTPUT "Configuration failed.  BUILD.COM was NOT written." !
$ WRITE SYS$OUTPUT " " !
$!
$CLEANUP: !
$! The probes leave objects, an image and a CXX repository behind.  Deletes are
$! F$SEARCH-guarded because we may arrive here from any of the failure exits,
$! with any subset of them created.
$ DEFINE SYS$ERROR  "_NLA0:" !
$ DEFINE SYS$OUTPUT "_NLA0:" !
$ IF F$SEARCH("TEST.OBJ")  .NES. "" THEN DELETE/NOLOG/NOCONFIRM TEST.OBJ;* !
$ IF F$SEARCH("TEST.EXE")  .NES. "" THEN DELETE/NOLOG/NOCONFIRM TEST.EXE;* !
$ IF F$SEARCH("TEST2.OBJ") .NES. "" THEN DELETE/NOLOG/NOCONFIRM TEST2.OBJ;* !
$ IF F$SEARCH("TEST3.OBJ") .NES. "" THEN DELETE/NOLOG/NOCONFIRM TEST3.OBJ;* !
$ IF F$SEARCH("[.CXX_REPOSITORY]*.*") .NES. "" THEN DELETE/NOLOG/NOCONFIRM [.CXX_REPOSITORY]*.*;* !
$ DEASSIGN SYS$OUTPUT !
$ DEASSIGN SYS$ERROR !
$ EXIT                                          ! done
