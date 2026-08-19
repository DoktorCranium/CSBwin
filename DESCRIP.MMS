# ============================================================================
# DESCRIP.MMS - CSBwin 15.7 (Dungeon Master / Chaos Strikes Back)
#               for OpenVMS 8.4 Alpha (AXP), SDL 1.2, HP C++ (CXX)
#
# Produces CSBWIN.EXE in this directory.
#
# CSBwin is Paul R. Stevens' re-implementation of the Atari ST Dungeon Master
# and Chaos Strikes Back engines.  The SDL/POSIX platform layer this port
# builds on (CSBlinux.cpp + LinCSBUI.cpp) is Erik and Rebecka Svanberg's Linux
# client.  Nothing in the engine proper is platform specific; see README.VMS
# for what the port changed and COMPILER_FIXES.TXT for why.
#
# The image name is short and uppercase on purpose: ODS-2 volumes fold case and
# allow only A-Z 0-9 $ _ - in a name.  A foreign command symbol to run it:
#
#   $ CSBWIN == "$DISK$USER:[GAMES.CSBWIN]CSBWIN.EXE"
#   $ CSBWIN                            ! plays DUNGEON.DAT from SYS$DISK:[]
#   $ CSBWIN "--directory" "DKA0:[CSB]"  ! switches pass through to _argv
#
# The "$" prefix is what makes it a foreign command, so DCL hands the rest of
# the line to LinCSBUI.cpp's UI_ProcessOption() instead of parsing it itself.
# QUOTE THE SWITCHES, or read the DCL note in README.VMS: DCL upcases an
# unquoted foreign-command argument, and UI_ProcessOption() compares switch
# names with strcmp.  (The port also case-folds the switch name itself - see
# LinCSBUI.cpp //017c - so an unquoted "--directory" now works too.  The
# argument AFTER it is a file specification and is NOT folded, which is why
# quoting is still the recommended habit on a case-sensitive ODS-5 volume.)
#
# Modelled on the sibling OpenVMS ports in this tree - [-.ROTT]DESCRIP.MMS,
# [-.KYRA-VMS.SRC]DESCRIP.MMS, [-.CHOCOLATE_DUKE]DESCRIP.MMS and
# [-.HEXEN]DESCRIP.MMS: one suffix rule for the bulk, everything into one
# object library, then a LINK whose main()-bearing object stays on the command
# line.
#
# BUILD:   $ @CONFIGURE.COM        ! checks CXX/MMS/SDL, writes BUILD.COM
#          $ @BUILD.COM
#     or   $ MMK/IGNORE=WARNING    ! (or MMS/IGNORE=WARNING) straight in
#
# PREREQUISITE - SDL 1.2 ONLY, defined the way the sibling ports expect:
#   $ DEFINE LIBSDL  <device:[dir]>   ! dir holding LIBSDL$SHR.OPT / LIBSDL.OPT
#   $ DEFINE SDL     <device:[dir]>   ! dir holding SDL.H
# CONFIGURE.COM verifies both by compiling, linking and RUNNING a probe, and
# refuses anything that reports itself as other than 1.2.
#
# /IGNORE=WARNING IS REQUIRED, NOT COSMETIC.  A warning-severity compile aborts
# MMS/MMK by default, and this is 1990s C++ transliterated from 68000 assembler:
# it truncates constants into i16, shifts by variable amounts, casts freely
# between pointer and integer, and has unreachable tails after die().  The
# $(WARNDIS) list below silences the noisiest of those; /IGNORE=WARNING covers
# the rest.  Real ERRORS still stop the build.
#
# ----------------------------------------------------------------------------
# SDL_MIXER IS NOT NEEDED - AND MUST NOT BE ADDED
# ----------------------------------------------------------------------------
# SoundMixer.cpp / SoundMixer.h in this directory are a self-contained subset of
# SDL_mixer written against plain SDL 1.2 audio: Mix_OpenAudio, Mix_QuickLoad_RAW,
# Mix_PlayChannel, Mix_Volume and the mix_channels() callback, 8 channels.  They
# are part of the build set (SoundMixer.obj below), so the only SDL component
# this port needs is stock SDL 1.2 itself - which is exactly what Alexey
# Chupahin's OpenVMS SDL port ships.  Do NOT put a real SDL_mixer on the
# include path: its SDL_mixer.h would collide with SoundMixer.h's Mix_* names
# and its Mix_Chunk has a different layout.
#
# ----------------------------------------------------------------------------
# POINTER SIZE - LOAD BEARING, UNLIKE THE SIBLING PORTS
# ----------------------------------------------------------------------------
# There is deliberately no /POINTER_SIZE qualifier below, so HP C++ uses its
# OpenVMS Alpha default of 32-BIT POINTERS with 32-bit int/long and 64-bit long
# long.  That is the same data model as the original Win32 build and the
# original 32-bit Linux build.
#
# DO NOT BUILD THIS WITH /POINTER_SIZE=64.  This engine is a transliteration of
# 68000 code and is full of structures whose field offsets are commented with
# their Atari ST addresses and are asserted against the on-disk images - e.g.
# STRUCT148 in utility.cpp (offsets 0/4/8/12, which only hold if a pointer is 4
# bytes), the DSA/heap structures in Hint.cpp, and every "pnt" field in Data.h.
# vmsglib.h's intptr_t fallback (int / unsigned int) is 32-bit for the same
# reason.  See the POINTER WIDTH note in vmsglib.h.
#
# ----------------------------------------------------------------------------
# STRUCTURE PACKING - DO NOT ADD /NOMEMBER_ALIGNMENT
# ----------------------------------------------------------------------------
# The engine's own structures ARE byte-packed, and they get that way from
# "#pragma nomember_alignment" in CSBTypes.h, CSB.h, Data.h, Chaos.cpp, Hint.cpp
# and utility.cpp (the __VMS spelling of the #pragma pack(1) the other platforms
# use).  The pragmas in the sources are the whole mechanism; the command line
# must stay out of it.
#
# Reason, from the sibling port's autopsy in [-.ROTT]COMPILER_FIXES.TXT section
# 16: /NOMEMBER (= /NOMEMBER_ALIGNMENT) byte-packs EVERY struct in the whole
# build, including the ones the C RTL and SDL own.  In ROTT that shifted a WAD
# lump structure's interior offset by one byte and drew the menu font as
# garbage.  Here it would additionally repack "struct stat", "struct timeval"
# and FILE, which the RTL laid out naturally aligned - see the long note at the
# top of stdafx.h's __VMS branch for the include-order rule that keeps those
# safe, and section 15 of the same file for why <SDL.h> leaks pack(1) into the
# rest of every translation unit on this platform.  That leak is harmless HERE
# only because it is uniform across all 41 objects and agrees with what the
# engine already asked for; a command-line qualifier is not needed to get it and
# would break the RTL structures that stdafx.h protects.
#
# ----------------------------------------------------------------------------
# GAME DATA
# ----------------------------------------------------------------------------
# CSBWIN.EXE reads its data from the CURRENT DEFAULT DIRECTORY unless told
# otherwise with --directory / --module / --root-path:
#   DUNGEON.DAT   the dungeon (Dungeon Master); required
#   GRAPHICS.DAT  the graphics; required
#   HCSB.DAT / HCSB.HCT  Chaos Strikes Back dungeon and hint files
#   MINI.DAT      the CSB utility dungeon
# Saved games, TRACE*.TXT and the recorded-session logs are WRITTEN there too
# (VMSFileName.inl turns the engine's embedded "traces/" and "logs/" prefixes
# into [.TRACES] and [.LOGS]), so that directory needs write access - it is not
# necessarily the one holding the image.
# ============================================================================

CXX = CXX

# CXXLINK, not LINK.  CXXLINK is the C++ driver: it adds the C++ RTL and the
# template repository to the link.  Plain LINK on a C++ image gets you
# %LINK-W-USRTFR and/or undefined C++ RTL symbols.  Learned on the sibling
# Kyra/ScummVM port.
LINK = CXXLINK

LINKFLAGS = /THREAD=UP
# /THREAD=UP is what the OpenVMS SDL port's own readme prescribes for linking
# against LIBSDL$SHR - see [-.SDL]README.VMS.
# For crash analysis:  LINKFLAGS = /THREAD=UP/MAP=CSBWIN.MAP/FULL/CROSS_REFERENCE

# ----------------------------------------------------------------------------
# Include path
# ----------------------------------------------------------------------------
#   []    this directory - every source, header and .INL of the build set.
#   SDL   the SDL 1.2 header logical.
#
# That is all.  Unlike the sibling Duke port there is not one cross-directory or
# slash-bearing #include anywhere in the build set: every include is a bare
# basename, so DEC C++'s inability to stack a relative base directory onto a
# quoted include never comes up.  GLib is NOT on this path and must not be -
# vmsglib.h replaces it (stdafx.h includes it instead of <glib.h> under __VMS).
#
# NOTE ON THE NAME, which applies to every mention of vmsglib.h in this file:
# the substitute's content now lives in csbglib.h and vmsglib.h is a one-line
# alias that includes it under __VMS.  The move happened because the macOS
# build turned out to need the identical substitute - GLib there means Homebrew
# or MacPorts headers that are not on the default include path - and one copy
# is easier to keep right than two.  Nothing about the OpenVMS build changed:
# same includes, same typedefs, same little-endian answer, same VMS_NO_INTPTR_T
# escape hatch, all of it still under #ifdef __VMS.  Where a comment below says
# "see the ... note in vmsglib.h", the note is now in csbglib.h.
INCS = ([],SDL)

# ----------------------------------------------------------------------------
# Preprocessor defines
# ----------------------------------------------------------------------------
# _LINUX       selects the SDL + POSIX platform layer.  In THIS tree _LINUX does
#              not mean "Linux the kernel"; it means CSBlinux.cpp + LinCSBUI.cpp
#              + WinScreen.cpp + the POSIX bits of system.cpp, which is exactly
#              the layer OpenVMS wants.  The port therefore KEEPS _LINUX defined
#              and adds its divergences under "#ifdef __VMS" inside it, rather
#              than inventing a fourth platform macro that every one of the 41
#              files would have to learn.  __VMS is predefined by the compiler;
#              it is never spelled on this line.
#
# SDL12        selects the SDL 1.2 API in LinCSBUI.cpp and CSBlinux.cpp
#              (SDL_SetVideoMode, SDL_Surface flags, the SDLK_* keysyms,
#              SDL_LockSurface/SDL_UpdateRects).  SDL20 is the alternative and
#              is NOT usable here: the OpenVMS SDL is 1.2 and the SDL 2 arm
#              wants SDL_CreateWindow/SDL_CreateTexture.
#
# RGB655       the 16-bit pixel layout WinScreen.cpp's blitters assemble
#              (5 red, 6 green, 5 blue - the name is upstream's, and it is off by
#              one letter, not by a bit).  It must agree with the 16bpp video
#              surface CSBlinux.cpp asks SDL_SetVideoMode for.  This is what
#              upstream's own Ubuntu_SDL12 makefile target passes.
#
# DECLSPEC=    neutralise the Win32-isms in the SDL 1.2 headers.  Every SDL
# SDLCALL=     prototype begins "extern DECLSPEC type SDLCALL SDL_Foo(...)", and
#              [-.SDL.INCLUDE]BEGIN_CODE.H only defines DECLSPEC when the macro
#              "VMS" (not "__VMS") is set - which HP C++ does not predefine in
#              its default dialect.  Without these two the very first SDL
#              prototype is a syntax error on an undeclared identifier.  Same
#              fix as the sibling FreeSCI and Kyra ports.
#
# NOT DEFINED, deliberately:
#   USE_OLD_GTK  there is no GTK 2 on OpenVMS.  stdafx.h turns it into an
#                #error under __VMS rather than letting the build half-work; the
#                GTK menu bar was only ever an optional extra over the SDL
#                window, and all of the GString/g_queue/g_signal surface it
#                needs is absent from vmsglib.h on purpose.
#   _DEBUG       switches on the ASSERT() in CSBTypes.h and a large amount of
#                tracing.  Add it with /MACRO if you are chasing a bug.
#   SOUND__ESOUND, _DYN_WINSIZE   EsounD and Hermes; neither exists here.
#
# $(DEFS_EXTRA) is what CONFIGURE.COM feeds in after probing the system.  Today
# there is exactly one macro it can put there, and it is a NEGATIVE one:
#
#   VMS_NO_INTPTR_T    <inttypes.h> on this CRTL does NOT declare intptr_t and
#                      uintptr_t, so vmsglib.h has to typedef them itself.  The
#                      engine uses both heavily (UI.h's CSB_UI_MESSAGE::p3,
#                      Dispatch.h, Hint.cpp, system.cpp, Chaos.cpp) for slots
#                      that carry either a pointer or a small integer.
#
# WHY THE MACRO IS NEGATIVE, i.e. why the default is to TRUST the header.  It
# used to be positive (VMS_HAVE_INTPTR_T, "the header has them"), and that was
# wrong in a way that only a real machine could show.  OpenVMS 8.4 Alpha DOES
# declare the pair, in DECC$RTLDEF.TLB module INTTYPES at its lines 74/75, so
# vmsglib.h's own typedefs were a redeclaration and the very first file of the
# build died with %CXX-E-BADTYPNAMRED.  With a positive macro the fallback is
# what you get by default, and the default was the rare case.  Worse, it made
# a plain "$ MMK" - no CONFIGURE.COM run behind it - guaranteed to fail on a
# normal system, which is precisely the invocation someone tries first.
#
# Inverting it means: the common system needs no macro at all, a bare MMK works,
# and the probe only has to speak up when it finds something unusual.  The probe
# itself is unchanged in substance - CONFIGURE.COM compiles <inttypes.h> plus a
# declaration that USES intptr_t, so a header that exists but declares nothing
# still fails it - only the polarity of what it emits has flipped.  See the long
# note in vmsglib.h, including why this is not called HAVE_INTTYPES_H (SDL
# defines that one unconditionally, and it answers a different question).
#
# The default is a harmless unused marker macro rather than nothing, because an
# empty expansion would leave "/DEFINE=(...,)" with a trailing comma.
DEFS_EXTRA = CSBWIN_VMS_BUILD
DEFS = _LINUX,SDL12,RGB655,"DECLSPEC=","SDLCALL=",$(DEFS_EXTRA)

# ----------------------------------------------------------------------------
# Warnings to disable
# ----------------------------------------------------------------------------
# THESE ARE HP C++ (CXX) MESSAGE NAMES - NOT DEC C (CC) NAMES, AND THE TWO SETS
# ARE NOT INTERCHANGEABLE.  The sibling Kyra port learned this the expensive
# way: it started from the FreeSCI port's CC tags (PTRMISMATCH, EMPTYFILE,
# QUESTCOMPARE, ...), CXX did not know them, and it emitted one
# %CXX-W-UNKMSGID per unknown tag - which is itself warning severity and so
# aborted the target.  DO NOT ADD A TAG HERE THAT YOU HAVE NOT SEEN CXX ACCEPT.
# The five below are the set the working Kyra and DOSBox CXX ports use.
#
#   INTOVERFLOW     "integer overflow in expression".  This engine is full of
#                   Atari ST constants written as-is - 0x8000 into an i16,
#                   0xffff into a signed field, the littleEndian(0x4ef9) jump
#                   opcode in utility.cpp - which is intentional and defined by
#                   the on-disk format, not by C++.
#   SHIFTCNTBIG     "shift count is too large".  The dead arms of the i64
#                   shifting in CSBTypes.h's LE32/LE16 and md5C.cpp.
#   CODEUNREACHABLE Everything after a die() call.  die() never returns but is
#                   not declared noreturn (C++03 has no portable spelling), so
#                   CXX flags the tail of ~40 functions.
#   UNRECPRAGMA     Insurance.  Every Microsoft "#pragma warning(...)" in the
#                   tree is inside "#ifdef _MSVC_INTEL" (verified: Chaos.cpp,
#                   Hint.cpp, CSBUI.cpp, Sound.cpp, Timer.cpp, utility.cpp,
#                   WinScreen.cpp) and "#pragma once" is inside "#if _MSC_VER >
#                   1000", so no foreign pragma is KNOWN to reach CXX.  Kept
#                   because the packing pragmas are the load-bearing part of
#                   this port and a single unrecognised-pragma warning would
#                   abort the build.
#   MISSINGRETURN   Two real sites: LinCSBUI.cpp's "static bool
#                   LIN_PlaySound(...)" simply has no return statement (upstream
#                   bug, harmless - UI_PlaySound's caller ignores the value),
#                   and vmsglib.h's g_error() ends in exit().
#
# NOT HERE, and worth knowing why:
#   FOUNDCR         Every source and header in this tree has CRLF line endings,
#                   so if CXX diagnoses stray carriage returns it will do so
#                   thousands of times.  The fix is at TRANSFER time, not here:
#                   copy the tree to OpenVMS in TEXT mode (UNZIP -a, or FTP in
#                   ASCII mode), which converts CRLF into VMS variable-length
#                   records and leaves no CR in the file at all.  If you
#                   transferred in binary and want to build anyway:
#                     $ MMK/IGN=WAR/MACRO=("WARNDIS=...,FOUNDCR")
#                   It is left out of the default because it is a DEC C tag and
#                   an unknown tag is worse than the warning it suppresses - it
#                   costs a %CXX-W-UNKMSGID per compilation, which is itself
#                   warning severity and so aborts the target.  Which is why you
#                   should not need to type that: CONFIGURE.COM detects a
#                   CR-terminated tree, PROBES whether this CXX accepts the tag,
#                   and if it does, writes the whole list with FOUNDCR appended
#                   into the BUILD.COM it generates.  Getting the same CRs into
#                   CONFIGURE.COM itself is a much worse problem than a warning
#                   - DCL does not strip them the way MMS and MMK do - and
#                   section 14 of COMPILER_FIXES.TXT is about that.
WARNDIS = INTOVERFLOW,SHIFTCNTBIG,CODEUNREACHABLE,UNRECPRAGMA,MISSINGRETURN

# ----------------------------------------------------------------------------
# Compiler flags
# ----------------------------------------------------------------------------
#  /NAME=(AS_IS,SHORTENED)
#       AS_IS preserves the case of external names - SDL's API is mixed case
#       (SDL_SetVideoMode) and so is the engine's own (UI_PushMessage, CSBUI).
#       SHORTENED, NOT SHORT: C++ mangled names routinely exceed the 31-character
#       limit of the Alpha object format, and /NAME=SHORT TRUNCATES them, which
#       silently merges distinct overloads and then fails at link time with
#       undefined or multiply-defined symbols.  SHORTENED hashes the tail
#       instead and keeps them distinct.  Learned on the Kyra port.
#  /FLOAT=IEEE
#       Match SDL and DECwindows.  The engine's own arithmetic is integer, but
#       Viewport.cpp and Graphics.cpp use doubles for the perspective tables.
#  /OPTIMIZE=(LEVEL=3,TUNE=HOST)
#       The Kyra port's level, and known to work with this compiler on C++ of
#       this vintage.  See the %GEM-F-ASSERTION section further down before
#       lowering it.
#  Note what is ABSENT: no /POINTER_SIZE (32-bit is required - see the header),
#  no /MEMBER_ALIGNMENT or /NOMEMBER_ALIGNMENT (the source pragmas own that -
#  see the header), no /NOEXCEPTIONS (CSBUI.cpp:917 and LinCSBUI.cpp:106 use
#  try/catch and CSBUI.cpp:1416 throws; exception support is on by default and
#  must stay on), and no /STANDARD (the default relaxed dialect is what accepts
#  "long long", the old-style casts and the K&R-ish parameter lists here; this
#  is C++03 code and /STANDARD=STRICT_ANSI rejects it).
CXXFLAGS = /NAME=(AS_IS,SHORTENED)/FLOAT=IEEE-
/OPTIMIZE=(LEVEL=3,TUNE=HOST)/INCLUDE=$(INCS)/DEFINE=($(DEFS))-
/WARNINGS=(DISABLE=($(WARNDIS)))

# Same, unoptimised.  Not used by default - this is the macro to swap a file's
# rule over to if it dies with %GEM-F-ASSERTION or an ACCVIO inside
# CXX$COMPILER.  See the escape-hatch section below.
CXXFLAGS_NOOPT = /NAME=(AS_IS,SHORTENED)/FLOAT=IEEE-
/NOOPTIMIZE/INCLUDE=$(INCS)/DEFINE=($(DEFS))-
/WARNINGS=(DISABLE=($(WARNDIS)))

# Same, /OPTIMIZE=LEVEL=1.  A DIFFERENT escape hatch from NOOPT: it keeps local
# optimisation but skips the LEVEL=3 dataflow and loop passes, which are the
# ones that both crash and (on the Kyra port) grind for tens of minutes on huge
# functions.  Try this BEFORE /NOOPTIMIZE - some back-end crashes are in the
# code expander, which runs at every level, and /NOOPTIMIZE can provoke them.
CXXFLAGS_OPT1 = /NAME=(AS_IS,SHORTENED)/FLOAT=IEEE-
/OPTIMIZE=(LEVEL=1,TUNE=HOST)/INCLUDE=$(INCS)/DEFINE=($(DEFS))-
/WARNINGS=(DISABLE=($(WARNDIS)))

# Same, with debug-symbol generation off as well as the optimiser.  The Kyra
# port hit a fifth crash class that is not in a codegen pass at all - CXX dying
# in me_generate_debug_information while growing its debug-symbol hash table -
# and neither /NOOPTIMIZE nor /OPTIMIZE=LEVEL=1 alone cleared it.  We never ask
# for /DEBUG, but CXX emits traceback DST records by default, which is enough to
# run that pass.  Cost of using this on a file: that one module has no symbolic
# traceback in a crash dump.  Nothing else changes.
CXXFLAGS_NODBG = /NAME=(AS_IS,SHORTENED)/FLOAT=IEEE-
/NOOPTIMIZE/NODEBUG/NOTRACEBACK-
/INCLUDE=$(INCS)/DEFINE=($(DEFS))-
/WARNINGS=(DISABLE=($(WARNDIS)))

# ----------------------------------------------------------------------------
# THE POST-DECREMENT-IN-A-COMPARISON COMPILER BUG - READ THIS BEFORE EDITING ANY
# SOURCE
# ----------------------------------------------------------------------------
# DEC C / HP C++ on OpenVMS 8.4 Alpha is known to die with
#     %GEM-F-ASSERTION, Compiler internal error - please submit problem report
# with GEM_LU_MAIN (the loop unroller/peeler) in the traceback, on the idiom
#     while (var-- != 0)   /   if (var-- > 2)
# i.e. a POST-DECREMENT INSIDE A COMPARISON.  The sibling Hexen port had to
# rewrite 8 such sites and the Duke port 18; see their COMPILER_FIXES.TXT.
#
# THIS TREE IS FULL OF THEM.  A scan of the 41 sources in the build set finds 34
# sites where a SCALAR variable is post-decremented (or post-incremented) inside
# a comparison, spread over 14 files:
#
#     CSBCode.cpp     7   Hint.cpp        7   Chaos.cpp       3
#     Code11f52.cpp   3   Monster.cpp     3   Character.cpp   2
#     Graphics.cpp    2   Attack.cpp      1   Code51a4.cpp    1
#     DSA.cpp         1   LinCSBUI.cpp    1   Magic.cpp       1
#     SaveGame.cpp    1   SoundMixer.cpp  1
#
# A representative one from each shape:
#     Monster.cpp:548      while (D5W-- != 0)
#     Code11f52.cpp:4394   while (index-- != 1)
#     CSBCode.cpp:7324     for (D4W=2; (D4W--)!=0; pwA3++)
#     Character.cpp:3256   if (w_2-- > 2)
#     Hint.cpp:8305        if ((w_18--) <= 0)
#     Graphics.cpp:1330    if ((D7W--) != 0) goto tag008d86;
#     Magic.cpp:1222       for (w_6=sw(D4W - D6W); w_6--!=0; )
#     LinCSBUI.cpp:668     while (_argc-- > 0)
#     SoundMixer.cpp:525   if (music_playing->fade_step++ < ...->fade_steps)
#     Graphics.cpp:1794    if ((d.Word23244++) == 0)
#
# That is not a surprise and it is not sloppiness: this engine is a
# transliteration of 68000 code, "D5W" and "A3" are machine registers, and
# "DBRA D5,loop" IS "while (D5W-- != 0)".  There are roughly twenty MORE sites of
# the neighbouring form "while (*(A3++) != 0)" - a POINTER post-increment in a
# comparison - which are not counted above: that idiom is ordinary C found in
# every string scan ever written, so a compiler that could not handle it could
# not build anything at all.  It is the scalar loop counter that the peeler
# rewrites, and that is what the sibling ports tripped over.
#
# THE FLAG ROUTE IS THEREFORE THE ONLY PRACTICAL RESPONSE, AND THAT IS WHAT THIS
# MACRO IS FOR.  Hand-rewriting 34 sites in a re-implementation this exact would
# be its own source of bugs.  All 14 files above compile with $(CXXFLAGS_PDEC),
# which is $(CXXFLAGS) by default.  If any of them dies with %GEM-F-ASSERTION,
# change THIS ONE LINE to
#     CXXFLAGS_PDEC = $(CXXFLAGS_OPT1)
# and rebuild: the unroller only runs above LEVEL=1, so LEVEL=1 removes the
# trigger without touching a line of engine source.  If only ONE file crashes,
# give that file its own rule at LEVEL=1 rather than slowing the other 13 down.
#
# DO NOT "FIX" THESE SITES BY HAND WITHOUT READING THIS.  The obvious rewrite
#     while (D5W != 0) { D5W--; ... }
# IS NOT EQUIVALENT.  A post-decrement runs on the FAILING test too, so the
# original leaves D5W at -1 after the loop, not 0 - and this is transliterated
# 68000 code in which the "register" variables D0W..D7W and A0..A6 are read
# again after the loop.  If you must change the source, use a form that keeps
# the extra decrement:
#     for (;;) { i16 t = D5W; D5W = (i16)(D5W - 1); if (t == 0) break; ... }
# and check the surrounding function for later uses of the variable first.
CXXFLAGS_PDEC = $(CXXFLAGS)

# ----------------------------------------------------------------------------
# SDL link fragment.  Default is the shared SDL, as in the sibling ports.
# ----------------------------------------------------------------------------
# If your SDL 1.2 is a static build, either edit this line to
#     SDLLIB = LIBSDL:LIBSDL/OPT
# or leave it alone and let CONFIGURE.COM detect it - the BUILD.COM it writes
# then passes /MACRO=("SDLLIB=LIBSDL:LIBSDL/OPT") to override it here.
# Both option files pull in the DECwindows X11 shareables themselves, so unlike
# the Kyra port there is no x11_link.opt to generate.
SDLLIB = LIBSDL:LIBSDL$SHR/OPT

# ----------------------------------------------------------------------------
# Objects - 40 of the 41 sources in the build set
# ----------------------------------------------------------------------------
# This is upstream's MAKEFILE object list for the Ubuntu_SDL12 target, verbatim.
#
# CSBlinux.obj is deliberately absent from this list: it carries main()
# (CSBlinux.cpp:1348) and must stay on the LINK command line.  See the
# CSBWIN.EXE rule.
#
# EXCLUDED ON PURPOSE - other platforms' copies of the same layers.  Do not
# "restore" any of these; several define the SAME functions as files that ARE in
# the list, so adding one gives you multiply-defined symbols, not more features:
#   CSBwin.cpp            the Win32 WinMain and message pump.
#   CSBMac.cpp            the Classic Mac OS platform layer.
#   CSBraspian.cpp        a Raspberry Pi variant of CSBlinux.cpp.
#   CSBWinCE2002.cpp,     the Pocket PC / ARM port (CSBUICE2002.cpp, HintCE.cpp,
#   WinScreenCE2002.cpp   WinScreenCE2002.cpp) - all _MSVC_CE2002ARM.
#   LinScreen.cpp         an ALTERNATIVE to WinScreen.cpp.  Upstream's Linux
#                         makefile builds WinScreen.cpp, not this, and so do we
#                         - the two define the same BLT*/UI_Screen* entry
#                         points.  This is why SCRAP is nearly dead code in the
#                         SDL 1.2 build; see the note in CSBlinux.cpp.
#   MacScreen.cpp         same, for Mac OS.
#   LinCSBUI_orig.cpp,    an older LinCSBUI.cpp and an editor backup.
#   LinCSBUI.cpp.bak      LinCSBUI_orig.cpp is the only file in the tree that
#                         uses g_assert; vmsglib.h provides it anyway.
#   Win32_SoundMixer.cpp  the DirectSound mixer; SoundMixer.cpp replaces it.
#   Stdafx.cpp            the MSVC precompiled-header stub.  Empty otherwise.
#   Recording_OldAnimation.cpp, NewBugs.cpp, OldBugs.cpp, Teleport.cpp
#                         orphans - in no platform's makefile, and nothing
#                         #includes them (verified).
#   Swoosh.c, Transition.c  the Mac transition effects, reached only through
#                         Prefix.h/Transition.h on Mac OS.
OBJ = AsciiDump.obj,Attack.obj,Bitmaps.obj,Chaos.obj,Character.obj,-
Code11f52.obj,Code13ea4.obj,Code17818.obj,Code1f9e6.obj,Code222ea.obj,-
Code390e.obj,Code51a4.obj,Codea59a.obj,CSBCode.obj,CSBUI.obj,data.obj,-
DSA.obj,Graphics.obj,Hint.obj,LinCSBUI.obj,Magic.obj,md5C.obj,Menu.obj,-
Monster.obj,Mouse.obj,MoveObject.obj,RC4.obj,Recording.obj,SaveGame.obj,-
SmartDiscard.obj,Sound.obj,SoundMixer.obj,Statistics.obj,system.obj,-
Timer.obj,Translation.obj,utility.obj,VBL.obj,Viewport.obj,WinScreen.obj

# Headers every object depends on.  stdafx.h is the umbrella (it pulls in
# Objects.h, CSBTypes.h, the system headers and, under __VMS, vmsglib.h in place
# of <glib.h>); UI.h, Dispatch.h, Data.h and CSB.h are included by all but a
# couple of files, and getting a rebuild after touching one of them matters far
# more than the handful of extra compiles.
#
# csbglib.h is in the list because it is where the GLib substitute now lives:
# the macOS build needs exactly the same substitute this port needed, so rather
# than keep two copies in step the content moved there and vmsglib.h became a
# one-line "#include ""csbglib.h""" for __VMS.  Both files must be present, and
# a change to either has to rebuild everything - hence both names here.
HDRS = stdafx.h,Objects.h,CSBTypes.h,vmsglib.h,csbglib.h,UI.h,Dispatch.h,-
Data.h,CSB.h

# ----------------------------------------------------------------------------
# Targets
# ----------------------------------------------------------------------------
ALL : CSBWIN.EXE
	@ WRITE SYS$OUTPUT "CSBWIN.EXE build complete."

# WHY CSBlinux.obj IS ON THE COMMAND LINE AND EVERYTHING ELSE IS IN A LIBRARY.
# Both halves of this were learned the hard way on the sibling ports:
#   * The object defining main() must be named directly on the LINK command
#     line.  The OpenVMS linker does not promote a transfer address out of a
#     library or an /OPTIONS file, so burying CSBlinux.obj yields
#     %LINK-W-USRTFR, "no user transfer address" - the image links but cannot be
#     run.
#   * Yet a bare command-line object's own references are NOT resolved against
#     an /OPTIONS file, which gives the opposite failure, %LINK-W-NUDFSYMS.
# An object library satisfies both at once: CSBlinux.obj keeps the transfer
# address and its references (CSBUI, UI_PushMessage, WinScreen's blitters, the
# SoundMixer channels) pull the defining modules out of CSBWIN.OLB into the same
# cluster.
#
# The library also keeps us clear of the ~1024-character MMS/MMK line-element
# limit and DCL's 4095-character command-line limit.
#
# EVERY FILESPEC AFTER THE FIRST NEEDS AN EXPLICIT SYS$DISK:[] - DO NOT REMOVE IT.
# DCL filespecs on one command line inherit the device and directory from the
# PRECEDING filespec, not from the current default directory.  It happens that
# every object here lives in the current default directory, so this port would
# survive without it - but the moment anything acquires a [.subdir] prefix the
# next filespec silently follows it there and the link dies with
# %LINK-F-OPENIN / -RMS-E-FNF on a file that was just created correctly.  The
# sibling ports all carry it; keep it.
#
# The two lines after the LINK report what was produced.  DIRECTORY/SIZE/DATE is
# listed as well as the banner because the useful thing to see at the end of a
# long emulated build is that the image is REALLY there and freshly dated: MMK
# prints nothing of its own on success, and a stale CSBWIN.EXE left over from an
# earlier run looks exactly like a new one otherwise.
#
# NO "@" PREFIX ON THOSE TWO LINES.  In make an @ suppresses command echoing, and
# MMS/MMK accept it - but if it were ever passed through to DCL instead of being
# consumed, "@ DIRECTORY" means "execute the command procedure DIRECTORY.COM" and
# the build would die on its very last step.
CSBWIN.EXE : CSBlinux.obj,CSBWIN.OLB
	$(LINK)$(LINKFLAGS)/EXE=SYS$DISK:[]CSBWIN.EXE CSBlinux.obj,SYS$DISK:[]CSBWIN.OLB/LIBRARY,$(SDLLIB)
	DIRECTORY/SIZE=ALL/DATE SYS$DISK:[]CSBWIN.EXE
	WRITE SYS$OUTPUT "Build done"

# Safe as a single flat library because no two COMPILED sources share a
# basename: an OpenVMS .OLB namespace is FLAT and keyed on the module name (the
# basename), IGNORING the directory, so same-named files in different
# directories silently overwrite each other.  Everything here is in one
# directory, so a collision is impossible by construction - but note that
# data.obj becomes module DATA and system.obj becomes module SYSTEM.  Those are
# module names only; the linker resolves SYMBOLS, and nothing in the DEC C++ RTL
# is disturbed by them.  (Checked for the collision class that bit the ROTT
# port: no source here defines a global function or type that shadows a C RTL
# name.  The one candidate, "ui32 time(void *)" at CSBCode.cpp:5, is inside
# "#ifdef _MSVC_CE2002ARM".)
#
# THE LIBRARY IS BUILT UNDER A TEMP NAME AND RENAMED.  DO NOT "SIMPLIFY" THIS.
# If LIBRARY/CREATE dies part way through, MMK stops but does NOT delete the
# half-written target - and that partial .OLB is NEWER than all 40 objects, so
# the next MMK considers it up to date, skips this rule silently, and hands the
# linker a library missing modules.  On the Kyra port that produced 629
# undefined symbols that all began at one chunk boundary.  Building to
# CSBWIN_TMP.OLB and renaming only on success makes the target atomic: a failed
# run leaves either no .OLB or the previous good one, never a newer partial.
#
# The index is presized, for the same reason Kyra's is: the librarian's defaults
# (BLOCKS:100, MODULES:256, GLOBALS:1000) are documented, GLOBALS is the binding
# limit for C++ (every non-inline method, vtable and typeinfo is a global), and
# when it runs out the LIBRARIAN faults with an ACCVIO instead of extending the
# index.  40 modules of this size are nowhere near Kyra's 358, but an
# over-allocated index costs only disk.
CSBWIN.OLB : $(OBJ)
	@ WRITE SYS$OUTPUT "Building object library CSBWIN.OLB ..."
	IF F$SEARCH("CSBWIN_TMP.OLB") .NES. "" THEN DELETE/NOLOG/NOCONFIRM CSBWIN_TMP.OLB;*
	LIBRARY/CREATE=(BLOCKS:2000,MODULES:200,GLOBALS:20000)/OBJECT CSBWIN_TMP.OLB $(OBJ)
	IF F$SEARCH("CSBWIN.OLB") .NES. "" THEN DELETE/NOLOG/NOCONFIRM CSBWIN.OLB;*
	RENAME CSBWIN_TMP.OLB CSBWIN.OLB

# ----------------------------------------------------------------------------
# IF THE COMPILER CRASHES - which flag to reach for
# ----------------------------------------------------------------------------
# Read the failing PASS NAME in the traceback before you touch a source file.
# The pass name says which flag will clear it:
#   GEM_LU_* / PEEL_LOOP   loop unroller; runs only above LEVEL=1
#                                                    -> give it $(CXXFLAGS_OPT1)
#   GEM_DF_* / CSE         LEVEL=3 dataflow          -> give it $(CXXFLAGS_OPT1)
#   GEM_CX_*               code EXPANDER; runs at EVERY level, so /NOOPTIMIZE
#                          can CAUSE it              -> try OPT1, not NOOPT
#   GEM_TN_*               register allocation       -> try $(CXXFLAGS_OPT1)
#   ME_DEBUGGEN            debug-symbol emission     -> $(CXXFLAGS_NODBG)
# Also read WHICH IMAGE faulted: if the PC is not in CXX$COMPILER and there is
# no GEM_* frame, it is not the compiler.  A fault in LIBRARIAN with every
# object already compiled is the presizing problem described above.
#
# The likeliest files to provoke a compiler bug here are simply the biggest:
# CSBCode.cpp (316K, one enormous opcode dispatcher), Viewport.cpp (235K),
# Monster.cpp (229K), Hint.cpp (220K), Chaos.cpp (188K), Character.cpp (153K),
# DSA.cpp (150K), Code11f52.cpp (131K).  Note the overlap with the
# post-decrement list above: CSBCode.cpp, Monster.cpp, Hint.cpp, Chaos.cpp,
# Character.cpp, DSA.cpp and Code11f52.cpp are in both, and $(CXXFLAGS_PDEC)
# already covers all seven.  Viewport.cpp is the one big file it does NOT cover.
# To move some OTHER file to LEVEL=1, give it its own rule - do not change
# $(CXXFLAGS) for the whole build.
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# Compilation rules
# ----------------------------------------------------------------------------
# All 41 sources are in this one directory and take identical flags, so the
# suffix rule does the work (the sibling Kyra port's shape) and only the
# exceptions get an explicit rule.
# ----------------------------------------------------------------------------
.SUFFIXES
.SUFFIXES .OBJ .CPP

.CPP.OBJ :
	$(CXX) $(CXXFLAGS) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

# Header dependencies.  A dependency line with no action ADDS prerequisites to
# the suffix rule above; it does not replace it.
$(OBJ) : $(HDRS)
CSBlinux.obj : $(HDRS)

# Extra per-file prerequisites, from upstream's MAKEFILE.
CSBlinux.obj : resource.h
CSBUI.obj : resource.h
LinCSBUI.obj : SoundMixer.h
SoundMixer.obj : SoundMixer.h
Recording.obj : Recording.h
# system.cpp is the file that #includes the FILENAME class implementation, and
# which .inl it picks up is decided by "#if defined __VMS" at system.cpp:21:
# VMSFileName.inl here, LinuxFileName.inl on Linux and the Mac.  Both are listed
# so that editing either one rebuilds this object; VMSFileName.inl is the new
# file this port adds and the only place in the engine that knows VMS path
# syntax.
system.obj : VMSFileName.inl,LinuxFileName.inl

# The 14 files carrying the post-decrement-in-a-comparison idiom.  Flags come
# from $(CXXFLAGS_PDEC) - one line to change if the unroller crashes.  See the
# long note above.  Listed alphabetically; the count next to each is how many
# sites that file has, so that if you do end up chasing a crash you know which
# ones are worth looking at first.
Attack.obj : Attack.cpp							# 1 site
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

Chaos.obj : Chaos.cpp							# 3 sites
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

Character.obj : Character.cpp						# 2 sites
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

Code11f52.obj : Code11f52.cpp						# 3 sites
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

Code51a4.obj : Code51a4.cpp						# 1 site
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

CSBCode.obj : CSBCode.cpp						# 7 sites
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

DSA.obj : DSA.cpp							# 1 site
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

Graphics.obj : Graphics.cpp						# 2 sites
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

Hint.obj : Hint.cpp							# 7 sites
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

LinCSBUI.obj : LinCSBUI.cpp						# 1 site
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

Magic.obj : Magic.cpp							# 1 site
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

Monster.obj : Monster.cpp						# 3 sites
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

SaveGame.obj : SaveGame.cpp						# 1 site
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

SoundMixer.obj : SoundMixer.cpp						# 1 site
	$(CXX) $(CXXFLAGS_PDEC) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

# CSBlinux.cpp holds main() (and the SDL event loop, the SDL timer callback and
# the g_log stub).  Compiled exactly like the rest; only its LINK placement
# differs - see the CSBWIN.EXE rule.
CSBlinux.obj : CSBlinux.cpp
	$(CXX) $(CXXFLAGS) /OBJECT=$(MMS$TARGET) $(MMS$SOURCE)

# ----------------------------------------------------------------------------
# $ MMK CLEAN     (F$SEARCH guards rather than a "-" prefix, so this behaves
#                  the same under MMS and MMK on an already-clean tree)
# ----------------------------------------------------------------------------
# [.CXX_REPOSITORY] is created by CXX itself for template instantiation
# bookkeeping.  This tree uses no templates, so it may not appear at all - hence
# the guard rather than an unconditional delete.
CLEAN :
	IF F$SEARCH("*.OBJ") .NES. "" THEN DELETE/NOLOG/NOCONFIRM *.OBJ;*
	IF F$SEARCH("CSBWIN.OLB") .NES. "" THEN DELETE/NOLOG/NOCONFIRM CSBWIN.OLB;*
	IF F$SEARCH("CSBWIN_TMP.OLB") .NES. "" THEN DELETE/NOLOG/NOCONFIRM CSBWIN_TMP.OLB;*
	IF F$SEARCH("CSBWIN.MAP") .NES. "" THEN DELETE/NOLOG/NOCONFIRM CSBWIN.MAP;*
	IF F$SEARCH("CSBWIN.EXE") .NES. "" THEN DELETE/NOLOG/NOCONFIRM CSBWIN.EXE;*
	IF F$SEARCH("[.CXX_REPOSITORY]*.*") .NES. "" THEN DELETE/NOLOG/NOCONFIRM [.CXX_REPOSITORY]*.*;*
