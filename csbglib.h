/* csbglib.h - GLib substitute for every CSBwin build that has no GLib.
 * ===========================================================================
 * Used by OpenVMS (via vmsglib.h, which is now a one-line alias for this
 * file) and by the SDL/POSIX build on macOS, Linux and Cygwin.
 *
 * WHY THIS FILE EXISTS
 *
 *   The SDL/POSIX flavour of CSBwin is selected by -D_LINUX, and _LINUX in
 *   this tree does NOT mean "Linux the kernel": it means "the SDL + POSIX
 *   platform layer" (CSBlinux.cpp + LinCSBUI.cpp + WinScreen.cpp).  macOS,
 *   Cygwin and OpenVMS all use that layer too.
 *
 *   The one thing _LINUX used to drag in that only a Linux desktop reliably
 *   has is GLib: stdafx.h did #include <glib.h>, and CSBTypes.h builds the
 *   whole engine's fundamental typedefs (i8/ui8/i16/.../i64/ui64/bool32/
 *   HWND/HTIMER) out of GLib's gint16/guint32/... names, plus it decides
 *   endianness from G_BYTE_ORDER.  So GLib was not optional for this
 *   configuration - it was load-bearing, and a missing glib.h stopped the
 *   build on the first source file.
 *
 *   That is a heavy dependency for what the compiled sources actually use,
 *   which is fifteen typedefs, a byte-order macro, four pointer casts and six
 *   varargs printf wrappers.  On OpenVMS 8.4 there is no GLib to install at
 *   all, which is why this file was first written (as vmsglib.h); on macOS
 *   GLib exists but only as a Homebrew/MacPorts package whose headers are not
 *   on the default include path, so the build failed there with "glib.h: No
 *   such file or directory" until you installed and located it.  Neither
 *   platform needs to: the entire GLib surface this engine touches is below.
 *
 *   The full inventory - all of it verified against the 41 translation units
 *   the build actually compiles, not guessed:
 *
 *     types      gint16 guint16 gint32 guint32 gint64 guint64
 *                gboolean gchar gint gpointer gsize  (CSBTypes.h, LinCSBUI.cpp,
 *                                                     CSBlinux.cpp)
 *     endianness G_BYTE_ORDER, G_LITTLE_ENDIAN, G_BIG_ENDIAN   (CSBTypes.h)
 *     casts      GINT_TO_POINTER, GPOINTER_TO_INT   (CSBlinux.cpp, SDL timer
 *                                                     and user-event codes)
 *     logging    g_print g_warning g_critical g_error g_assert
 *                and the g_log SIGNATURE, because CSBlinux.cpp DEFINES g_log
 *                itself (it stubs it out to die()) and that definition has to
 *                agree with a declaration somewhere.
 *     booleans   TRUE / FALSE
 *
 *   Everything else GLib-ish in the tree (GString, g_string_*, g_queue_*,
 *   g_signal_connect, g_set_application_name, G_OBJECT) sits inside
 *   #ifdef USE_OLD_GTK - the optional GTK 2 menu bar over the SDL window -
 *   and that configuration includes <gtk/gtk.h>, which brings the REAL GLib
 *   with it; see stdafx.h, where the two are mutually exclusive.  Those names
 *   are deliberately NOT provided here: a build that defines USE_OLD_GTK
 *   without GTK present should fail loudly at the first g_string_new rather
 *   than half-work.
 *
 *   This header is therefore never read in the same translation unit as the
 *   real glib.h.  The check below enforces that, because the two would
 *   collide in ways that are tedious to diagnose: modern GLib makes g_error,
 *   g_warning and g_critical MACROS over g_log(), so an inline function of
 *   the same name is a syntax error rather than a redefinition, and its
 *   GINT_TO_POINTER expands to a different token sequence than ours.
 *
 * ENDIANNESS
 *
 *   Decided from the compiler's own macros, with no configure step, because
 *   this is the one thing here that must not be got wrong: DUNGEON.DAT,
 *   HCSB.DAT, HCSB.HCT, GRAPHICS.DAT, the saved games and the recorded
 *   playback files are all little-endian Atari-ST-derived byte images read
 *   through structure overlays (see the packing note in CSBTypes.h), and
 *   CSBTypes.h turns LE16/LE32 into no-ops when _littleEndian is defined.
 *   Guess little-endian on a big-endian machine and every 16-bit field in the
 *   dungeon comes out byte-swapped.
 *
 *   Every platform this engine is built on today is little-endian: x86,
 *   x86-64, ARM and Apple silicon, OpenVMS Alpha and OpenVMS I64.  The
 *   big-endian arm is still resolved properly rather than rejected, because
 *   the engine does carry _bigEndian paths (they date from the Mac OS 9
 *   PowerPC build) and a PowerPC or big-endian-MIPS Linux box would use them.
 *
 * POINTER WIDTH
 *
 *   This engine is a re-implementation of 68000 code and has structures whose
 *   field offsets are commented with their Atari ST addresses (see STRUCT148
 *   in utility.cpp, offsets 0/4/8/12, which only hold if a pointer is 4
 *   bytes).  Nothing in THIS file depends on pointer width - the casts below
 *   go through intptr_t precisely so that they do not - but see the POINTER
 *   WIDTH note that vmsglib.h used to carry and DESCRIP.MMS still does: the
 *   OpenVMS build must use /POINTER_SIZE=32.  64-bit hosts (any current Mac
 *   or Linux box) have the same latent problem and it predates this file.
 *
 * ===========================================================================
 */

#ifndef __CSBGLIB_H__
#define __CSBGLIB_H__

#if defined(__G_LIB_H__) || defined(__GLIBCONFIG_H__)
# error csbglib.h is a substitute for <glib.h> and must not be combined with \
the real one - see the note about USE_OLD_GTK in this file and in stdafx.h
#endif

#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <stddef.h>

/* --------------------------------------------------------------------------
 * intptr_t / uintptr_t
 *
 * The engine uses uintptr_t and intptr_t in interfaces that pass either a
 * pointer or a small integer through the same parameter - UI.h's
 * CSB_UI_MESSAGE::p3, UI_PushMessage(), Chaos.cpp's _CALL3/_CALL4 and the
 * atari_sprintf() varargs shim.  With GLib they arrived via <stdint.h>,
 * pulled in by glib.h, so they have to arrive from somewhere now.
 *
 * <stdint.h> is the C99/C++11 answer and is what every current toolchain
 * wants; OpenVMS 8.4's DEC C RTL predates it and spells the pair in
 * <inttypes.h> instead.
 *
 * ON OPENVMS THE DEFAULT IS TO USE THE HEADER, AND THAT DEFAULT IS NOT A
 * GUESS.  It was measured on a real OpenVMS 8.4 Alpha system: <inttypes.h>
 * there does declare both types -
 *
 *     %CXX-E-BADTYPNAMRED, invalid redeclaration of type name "intptr_t"
 *               (declared at line 74 of "Text library
 *               SYS$COMMON:[SYSLIB]DECC$RTLDEF.TLB;1 module INTTYPES")
 *
 * which is what this file used to PROVOKE by typedef'ing them itself whenever
 * VMS_HAVE_INTPTR_T was absent.  The polarity was backwards: the fallback was
 * the default, so a system that HAD the types got a hard error, and it got it
 * on the very first file of the build.  Note that the clash is unconditional,
 * not merely likely: stdafx.h includes <SDL.h> before this file, SDL_stdinc.h
 * includes <inttypes.h> when HAVE_INTTYPES_H is set, and the OpenVMS
 * SDL_config.h sets it unconditionally.  So <inttypes.h> has ALWAYS been read
 * by the time we get here, and the typedefs below could never have been
 * anything but a redeclaration on a CRTL that declares them.
 *
 * So: the header is used unless you say otherwise, and the escape hatch is an
 * explicit VMS_NO_INTPTR_T for a CRTL old enough not to declare the pair.
 * CONFIGURE.COM still runs the probe - it compiles <inttypes.h> plus a
 * declaration that actually USES intptr_t, which a header that exists but
 * declares nothing would fail - and passes VMS_NO_INTPTR_T only when that
 * probe fails.  A negative macro is the right shape here because it makes the
 * common case need no macro at all, so a build with no CONFIGURE.COM run
 * behind it (plain "$ MMK") does the right thing rather than the rare thing.
 *
 * The fallback types are int/unsigned int, which is pointer-width in the
 * 32-bit-pointer model the OpenVMS build uses.
 *
 * WHY THIS IS NOT SPELLED "HAVE_INTTYPES_H".  That name is already taken and
 * it answers a different question: SDL_config.h defines HAVE_INTTYPES_H
 * unconditionally, i.e. "SDL says the header exists" - not "this CRTL
 * declares intptr_t".  Reusing it would tie our answer to SDL's assumption.
 *
 * CLASSIC UNIX HAS THE SAME PROBLEM AS OPENVMS, one step less severely.
 * <stdint.h> is C99; Tru64 UNIX and its Digital UNIX ancestor are older than
 * that and put the exact-width types and intptr_t in <inttypes.h>, which they
 * have had since Digital UNIX 4.0.  Two negative macros cover it, and the
 * ./configure script probes for both rather than deciding by OS name:
 *
 *   CSB_INT_TYPES_IN_INTTYPES_H   <stdint.h> is missing; read <inttypes.h>
 *                                 instead.  Everything this file needs from
 *                                 the header - int16_t..uint64_t, intptr_t -
 *                                 is in <inttypes.h> on such a system, and on
 *                                 a C99 system <inttypes.h> includes
 *                                 <stdint.h>, so the macro is never wrong,
 *                                 only unnecessary.
 *
 *   CSB_NO_INTPTR_T               neither header declares the pointer-sized
 *                                 pair.  "long" is the right fallback for
 *                                 every Unix ABI: pointer-width on LP64
 *                                 (Alpha/Tru64, any 64-bit Linux, macOS) and
 *                                 on ILP32.  It is wrong only for Windows
 *                                 LLP64, which never reads this arm.
 *
 * Same polarity argument as on OpenVMS: the common case needs no macro, so
 * building without running ./configure first still does the right thing on a
 * current toolchain.
 * -------------------------------------------------------------------------- */
#ifdef __VMS
# ifdef VMS_NO_INTPTR_T
typedef int           intptr_t;
typedef unsigned int  uintptr_t;
# else
#  include <inttypes.h>
# endif
#else
# ifdef CSB_INT_TYPES_IN_INTTYPES_H
#  include <inttypes.h>
# else
#  include <stdint.h>
# endif
# ifdef CSB_NO_INTPTR_T
typedef long           intptr_t;
typedef unsigned long  uintptr_t;
# endif
#endif

/* --------------------------------------------------------------------------
 * Fundamental types.  These are the GLib spellings, with GLib's guarantees:
 * gint16/guint16 are exactly 16 bits, gint32/guint32 exactly 32,
 * gint64/guint64 exactly 64.
 *
 * Off OpenVMS the exact-width types come from <stdint.h> (or from
 * <inttypes.h> on a pre-C99 Unix - see the note above), which is what GLib
 * itself does (its glibconfig.h is generated from the same information), so
 * i16/ui16/i32/ui32/i64/ui64 in CSBTypes.h end up as the identical types they
 * had in a GLib build - not merely types of the same size.  That matters
 * because the structures those typedefs appear in are overlays on the on-disk
 * data files, and because gint64/guint64 have to agree with INT64_FMT
 * ("%lld") in CSBTypes.h: int64_t is "long" on a 64-bit LP64 Unix, and
 * printing a long with %lld is fine on every LP64 target but would be worth
 * knowing about if a build ever turned on -Wformat-pedantic complaints.
 *
 * On OpenVMS the typedefs are spelled out instead of taken from <stdint.h>
 * (which the 8.4 CRTL does not provide): short 16, int 32, long 32, long long
 * 64 there.  "long long" rather than "__int64" because HP C++ accepts it in
 * every dialect the port builds with.
 * -------------------------------------------------------------------------- */
typedef char                 gchar;
typedef unsigned char        guchar;
typedef int                  gint;
typedef unsigned int         guint;
typedef int                  gboolean;
typedef void                *gpointer;
typedef const void          *gconstpointer;
typedef float                gfloat;
typedef double               gdouble;
typedef size_t               gsize;

#ifdef __VMS
typedef short                gint16;
typedef unsigned short       guint16;
typedef int                  gint32;
typedef unsigned int         guint32;
typedef long long            gint64;
typedef unsigned long long   guint64;
#else
typedef int16_t              gint16;
typedef uint16_t             guint16;
typedef int32_t              gint32;
typedef uint32_t             guint32;
typedef int64_t              gint64;
typedef uint64_t             guint64;
#endif

#ifndef FALSE
# define FALSE 0
#endif
#ifndef TRUE
# define TRUE  (!FALSE)
#endif

/* --------------------------------------------------------------------------
 * Byte order.  See the ENDIANNESS note in the file header.  The values are
 * GLib's own (1234 / 4321), so nothing that compares against them needs to
 * change.
 *
 * G_BYTE_ORDER can be defined on the command line to override the whole
 * block, which is the escape hatch for a compiler this does not recognise;
 * the #error at the bottom names it.
 * -------------------------------------------------------------------------- */
#define G_LITTLE_ENDIAN 1234
#define G_BIG_ENDIAN    4321

#ifndef G_BYTE_ORDER
/* GCC 4.6+, clang and Apple clang.  Preferred because it is the compiler
 * stating the fact rather than us inferring it from the target name. */
# if defined(__BYTE_ORDER__) && defined(__ORDER_LITTLE_ENDIAN__) \
                             && defined(__ORDER_BIG_ENDIAN__)
#  if   __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#   define G_BYTE_ORDER G_LITTLE_ENDIAN
#  elif __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#   define G_BYTE_ORDER G_BIG_ENDIAN
#  else
#   error This target is neither little- nor big-endian; CSBwin cannot read \
the Atari-ST data files on it
#  endif
/* Older clang and the Apple headers' spelling. */
# elif defined(__LITTLE_ENDIAN__)
#  define G_BYTE_ORDER G_LITTLE_ENDIAN
# elif defined(__BIG_ENDIAN__)
#  define G_BYTE_ORDER G_BIG_ENDIAN
/* Targets that are little-endian by definition, for compilers that say
 * neither of the above: OpenVMS Alpha and I64, MSVC's x86/x64/ARM. */
# elif defined(__VMS) || defined(__alpha) || defined(__ia64) \
    || defined(_M_IX86) || defined(_M_X64) || defined(_M_AMD64) \
    || defined(_M_ARM) || defined(_M_ARM64)
#  define G_BYTE_ORDER G_LITTLE_ENDIAN
# else
#  error Cannot determine byte order - build with -DG_BYTE_ORDER=1234 for a \
little-endian target or -DG_BYTE_ORDER=4321 for a big-endian one
# endif
#endif

/* --------------------------------------------------------------------------
 * Integer <-> pointer casts.
 *
 * CSBlinux.cpp stuffs a small event code (IDC_Timer, IDC_VIDEOEXPOSE, a
 * window width or height) into the void* user-data slots of SDL_AddTimer and
 * SDL_UserEvent, then pulls it back out.  GLib's macros go through
 * (g)size/(g)intptr precisely so that this round-trip is not a
 * pointer-truncation warning; the same reasoning applies verbatim here.
 * -------------------------------------------------------------------------- */
#define GINT_TO_POINTER(i)      ((gpointer)(intptr_t)(i))
#define GPOINTER_TO_INT(p)      ((gint)(intptr_t)(p))
#define GUINT_TO_POINTER(u)     ((gpointer)(uintptr_t)(u))
#define GPOINTER_TO_UINT(p)     ((guint)(uintptr_t)(p))

/* --------------------------------------------------------------------------
 * Logging.
 *
 * These are the four GLib entry points the compiled sources call, with GLib's
 * semantics preserved where the semantics matter:
 *
 *   g_print    -> stdout, no added newline, no prefix.  Used only in
 *                 commented-out tracing in this tree, but provided so that
 *                 re-enabling any of those lines does not break the build.
 *   g_warning  -> stderr, "** WARNING **: " prefix, newline added.
 *                 Recoverable: LinCSBUI.cpp reports a caught engine
 *                 exception with it and then returns UI_STATUS_TERMINATE.
 *   g_critical -> stderr, "** CRITICAL **: " prefix, newline added.
 *                 CSBlinux.cpp uses it when SDL_Init fails - and then keeps
 *                 going, exactly as the GLib build did, so this must NOT
 *                 abort.
 *   g_error    -> stderr, "** ERROR **: " prefix, newline, then TERMINATES.
 *                 In GLib g_error is documented as fatal and always aborts;
 *                 CSBlinux.cpp relies on that (it calls g_error when
 *                 SDL_CreateRGBSurface or the SDL timer subsystem fails and
 *                 then falls through to code that would dereference the NULL
 *                 surface).  So it exits, and it is declared noreturn where
 *                 the compiler has a spelling for that - which keeps the
 *                 callers' "control reaches end of non-void function"
 *                 warnings quiet exactly as GLib's own noreturn g_error did.
 *                 HP C++ on OpenVMS is not told, which is one reason
 *                 DESCRIP.MMS disables the MISSINGRETURN warning.
 *
 * They are inline in the header rather than in a .cpp so that no extra object
 * has to be added to the build set (in DESCRIP.MMS it is a fixed list of 41).
 * Each is used at most a handful of times, so the duplication is negligible.
 *
 * NOTE the deliberate asymmetry with g_log: g_log is only DECLARED here.
 * CSBlinux.cpp defines it (as a die() stub, since nothing in this tree calls
 * it), and two definitions would be a duplicate-symbol link error.
 * -------------------------------------------------------------------------- */
#if defined(__GNUC__)
# define CSBGLIB_NORETURN __attribute__((noreturn))
#else
# define CSBGLIB_NORETURN
#endif

typedef enum
{
  G_LOG_FLAG_RECURSION = 1 << 0,
  G_LOG_FLAG_FATAL     = 1 << 1,
  G_LOG_LEVEL_ERROR    = 1 << 2,
  G_LOG_LEVEL_CRITICAL = 1 << 3,
  G_LOG_LEVEL_WARNING  = 1 << 4,
  G_LOG_LEVEL_MESSAGE  = 1 << 5,
  G_LOG_LEVEL_INFO     = 1 << 6,
  G_LOG_LEVEL_DEBUG    = 1 << 7
} GLogLevelFlags;

/* Defined by CSBlinux.cpp - see the note above. */
void g_log(const gchar *domain, GLogLevelFlags level, const gchar *format, ...);

inline void g_print(const gchar *format, ...)
{
  va_list ap;
  va_start(ap, format);
  vfprintf(stdout, format, ap);
  va_end(ap);
  fflush(stdout);
}

inline void g_warning(const gchar *format, ...)
{
  va_list ap;
  fputs("\n** WARNING **: ", stderr);
  va_start(ap, format);
  vfprintf(stderr, format, ap);
  va_end(ap);
  fputs("\n", stderr);
  fflush(stderr);
}

inline void g_critical(const gchar *format, ...)
{
  va_list ap;
  fputs("\n** CRITICAL **: ", stderr);
  va_start(ap, format);
  vfprintf(stderr, format, ap);
  va_end(ap);
  fputs("\n", stderr);
  fflush(stderr);
}

CSBGLIB_NORETURN inline void g_error(const gchar *format, ...)
{
  va_list ap;
  fputs("\n** ERROR **: ", stderr);
  va_start(ap, format);
  vfprintf(stderr, format, ap);
  va_end(ap);
  fputs("\n", stderr);
  fflush(stderr);
  exit(EXIT_FAILURE);
}

/* GLib's g_assert is a hard, always-compiled assertion (unlike ASSERT in
 * CSBTypes.h, which compiles away unless _DEBUG).  No file in the build set
 * uses it - only LinCSBUI_orig.cpp, which is not compiled - but it is a
 * two-line macro and its absence would be a mystifying error if that file
 * were ever revived. */
#define g_assert(expr)                                                        \
  do {                                                                        \
    if (!(expr))                                                              \
    {                                                                         \
      fprintf(stderr, "\n** ERROR **: assertion failed: %s (%s:%d)\n",        \
              #expr, __FILE__, __LINE__);                                     \
      exit(EXIT_FAILURE);                                                     \
    };                                                                        \
  } while (0)

#endif /* __CSBGLIB_H__ */
