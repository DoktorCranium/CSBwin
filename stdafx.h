// stdafx.h : include file for standard system include files,
//  or project specific include files that are used frequently, but
//      are changed infrequently
//


#if !defined(AFX_STDAFX_H__A9DB83DB_A9FD_11D0_BFD1_444553540000__INCLUDED_)
#define AFX_STDAFX_H__A9DB83DB_A9FD_11D0_BFD1_444553540000__INCLUDED_

#if _MSC_VER > 1000
#pragma once
#endif // _MSC_VER > 1000

#define WIN32_LEAN_AND_MEAN		// Exclude rarely-used stuff from Windows headers


#define SEQUENCED_TIMERS

// Windows Header Files:
#if defined _MSVC_INTEL || defined _MSVC_CE2002ARM
#include <windows.h>
#pragma warning (disable:4996) // sprintf, etc deprecated
#endif

// C RunTime Header Files
#if defined _MSVC_INTEL || defined _MSVC_CE2002ARM
#include <stdlib.h>
#include <memory.h>
#include <tchar.h>
#else
#ifdef _LINUX
#  ifdef __VMS
/* ==========================================================================
 * OpenVMS.  Two differences from the Linux prologue, and the ORDER matters.
 *
 * 1. EVERY SYSTEM HEADER THE BUILD USES IS INCLUDED HERE, BEFORE <SDL.h>.
 *
 *    This is not tidiness.  The OpenVMS SDL 1.2 distribution's SDL_config.h
 *    opens with an UNBALANCED "#pragma pack (1)" (see the DO-NOT-REMOVE
 *    comment at the top of LIBSDL:[include]SDL_config.h, and section 15 of
 *    [-.ROTT]COMPILER_FIXES.TXT).  It has to be there - LIBSDL$SHR is a
 *    prebuilt shared library whose own sources were compiled with it, so its
 *    SDL_Surface really is byte-packed (74 bytes, ->pixels at offset 22) and
 *    an application that resets the packing reads ->pixels and ->pitch from
 *    the wrong offsets.  begin_code.h does not save you either: its
 *    "#pragma pack(push,4)" is guarded by _MSC_VER/__MWERKS__/__BORLANDC__
 *    and DEC C++ is none of those.
 *
 *    The consequence is that #include <SDL.h> leaves the REST of the
 *    translation unit byte-packed.  For this engine that is harmless where
 *    its own structures are concerned - CSBTypes.h asks for byte packing on
 *    the very next line anyway, deliberately, because the structures are
 *    overlays on little-endian Atari ST disk images - and all 41 sources in
 *    the build get the same treatment, so there is no possibility of two
 *    objects disagreeing about a shared layout (the trap that corrupted
 *    ROTT's fonts).
 *
 *    What is NOT harmless is a SYSTEM header being read with packing in
 *    force: struct stat, struct timeval and FILE are laid out by the C RTL,
 *    which was compiled naturally aligned, and stat()/gettimeofday()/getc()
 *    would then read and write the wrong offsets of a struct the RTL owns.
 *    The DEC C headers do defend themselves against this (they bracket their
 *    declarations in #pragma __member_alignment __save/__restore), which is
 *    why the sibling ports survive even a global /NOMEMBER_ALIGNMENT - but
 *    depending on that is depending on an implementation detail of someone
 *    else's header, for no gain.  Including them first costs two dozen lines
 *    and makes the question moot.  Include guards make the per-file
 *    #include <unistd.h> / <sys/time.h> / <signal.h> / <fcntl.h> / <ctype.h>
 *    in LinCSBUI.cpp and friends no-ops.
 *
 * 2. THERE IS NO GLib AND NO <memory.h>.  memcpy/memset live in <string.h>,
 *    and vmsglib.h - now a one-line alias for csbglib.h, which the other
 *    platforms use too - supplies the GLib typedefs, G_BYTE_ORDER, the
 *    integer<->pointer casts and the logging entry points that the
 *    _LINUX-flavoured sources use.  Read csbglib.h's header comment for the
 *    full inventory and the reasoning.  GTK is never available, so USE_OLD_GTK
 *    must stay undefined: the OpenVMS UI is the SDL window and nothing else.
 * ========================================================================== */
#    include <stdlib.h>
#    include <stdio.h>
#    include <string.h>
#    include <time.h>
#    include <ctype.h>
#    include <unistd.h>
#    include <fcntl.h>
#    include <signal.h>
#    include <sys/types.h>
#    include <sys/stat.h>
#    include <sys/time.h>
#    include <SDL.h>
#    include "vmsglib.h"
#  else
/* ==========================================================================
 * macOS, Linux, Cygwin - the same SDL/POSIX layer, and two notes.
 *
 * 1. <string.h>, NOT <memory.h>.  memory.h is a glibc compatibility header
 *    for pre-standard code; it does not exist on macOS, so this line alone
 *    stopped the build there before <glib.h> ever got a chance to.  memcpy,
 *    memset and memcmp - all this file wanted from it - are declared by
 *    <string.h>, which is where ISO C puts them and which every platform has.
 *
 * 2. csbglib.h, NOT <glib.h>.  GLib was load-bearing for this configuration
 *    (CSBTypes.h builds i8/ui8/.../ui64/bool32/HWND/HTIMER out of GLib's
 *    gint16/guint32/... and decides endianness from G_BYTE_ORDER), and it was
 *    a dependency that a Mac does not satisfy out of the box: no GTK 2, and a
 *    Homebrew or MacPorts glib whose headers are not on the default include
 *    path.  csbglib.h provides the whole of what the compiled sources use -
 *    read its header comment - so no GLib needs to be installed or located on
 *    any platform.  The OpenVMS branch above has done exactly this since the
 *    port was made; this is the same file.
 *
 * USE_OLD_GTK is the one configuration that still wants the real thing: the
 * optional GTK 2 menu bar over the SDL window needs GString, g_queue_*,
 * g_signal_connect and G_OBJECT, which csbglib.h deliberately does not
 * provide.  <gtk/gtk.h> brings the real <glib.h> with it, so the two are
 * alternatives and csbglib.h refuses to be included alongside it.  Note that
 * defining USE_OLD_GTK is not a supported configuration here (see the GTK 2
 * section of CMakeLists.txt) - this arm just keeps it honest.
 * ========================================================================== */
#    include <SDL.h>
#    include <stdlib.h>
#    include <stdio.h>
#    include <string.h>
#    include <sys/stat.h>
/* ==========================================================================
 * TARGET_OS_MAC MUST NOT BE DEFINED IN THIS CONFIGURATION.  This is the third
 * macOS build failure and the least obvious, because the macro is not ours.
 *
 * In THIS TREE, TARGET_OS_MAC means "the classic Mac OS 9 Toolbox build, made
 * with Metrowerks CodeWarrior from csb.mcp" - see Prefix.h, which is that
 * build's prefix file.  Every one of its arms is Toolbox code: MacShowCursor()
 * in CSBCode.cpp, the Toolbox Sleep() and InvalidateRect() and the SND_SYNC
 * PlaySound in CSBUI.cpp, "#pragma reverse_bitfields on" and #define
 * _bigEndian in CSBTypes.h.
 *
 * On Apple's MODERN SDK the same name means something completely different:
 * <TargetConditionals.h> defines TARGET_OS_MAC as 1 on every Apple platform,
 * including Apple silicon macOS, and <SDL.h> above pulls that header in.  So a
 * Mac build of the SDL/POSIX layer silently switched on all of the above:
 *
 *   - CSBTypes.h stopped the compile outright with "#error All bitfields must
 *     be reversed in order to run!" (its inner test is for __MWERKS__, and
 *     clang is not CodeWarrior).  That is the error you see first.
 *   - had it got past that, CSBTypes.h would have defined _bigEndian on a
 *     little-endian machine, byte-swapping every 16-bit field read from
 *     DUNGEON.DAT.
 *   - CSBUI.cpp defines a static _strupr under TARGET_OS_MAC (//009) AND under
 *     "TARGET_OS_MAC || __VMS" (//007): both arms at once is a redefinition.
 *   - the rest would fail to link against a Toolbox that has not existed since
 *     Mac OS 9.
 *
 * Undefining it here puts macOS in exactly the state the Linux build of this
 * layer is in and is tested in - TARGET_OS_MAC not defined at all - which is
 * what the _LINUX arms of CSBUI.cpp and CSBCode.cpp are written for.  It is
 * done AFTER the system headers on purpose: <TargetConditionals.h> has already
 * been read by then, so nothing later re-defines it, and no Apple header we
 * include afterwards tests it.
 *
 * The alternative - renaming the macro to something like CSB_MACOS9 in all
 * fifteen places it is used - was rejected: it edits the untouched Mac OS 9
 * sources for no gain, and it would leave a reader wondering whether Apple's
 * TARGET_OS_MAC was meant to have an effect somewhere.  Here the answer is in
 * one place: it is not.  (CSBTypes.h now keys its arm on the CodeWarrior
 * macros instead, so it cannot fire even if this line is ever lost.)
 * ========================================================================== */
#    ifdef TARGET_OS_MAC
#      undef TARGET_OS_MAC
#    endif
#    ifdef USE_OLD_GTK
#      include <gtk/gtk.h>
#    else
#      include "csbglib.h"
#    endif
#  endif
#  if defined USE_OLD_GTK && defined __VMS
#    error USE_OLD_GTK is not supported on OpenVMS - there is no GTK 2
#  endif
# else
#  include <stdlib.h>
#  include <stdio.h>
#  include "Transition.h"
# endif
#endif

// Local Header Files

// TODO: reference additional headers your program requires here

#include "Objects.h"
#include "CSBTypes.h"

#ifdef _MSVC_INTEL
#pragma warning(disable:4710)
#endif

#ifdef _MSVC_CE2002ARM
void ec(void);
#define EC ec();
#define CEtry _try {
#define CEexception(n) } _except(per=GetExceptionInformation(),CaptureExceptionInfo(), 1){PrintExceptionInfo();PostQuitMessage(1); };
#else
#define EC
#define CEtry
#define CEexception(n)
#endif

//{{AFX_INSERT_LOCATION}}
// Microsoft Visual C++ will insert additional declarations immediately before the previous line.

#endif // !defined(AFX_STDAFX_H__A9DB83DB_A9FD_11D0_BFD1_444553540000__INCLUDED_)

