# ============================================================================
# CSBwin - CMake build (Linux, macOS, Cygwin; MSVC path is untested)
# ============================================================================
# This replaces ROQUEN's "first rough draft", which no longer configured with a
# modern CMake and could not build on macOS at all.  What was wrong with it, and
# why each fix is what it is, is recorded here rather than in a commit message,
# because most of the traps are specific to this source tree.
#
#   1. project() came BEFORE cmake_minimum_required(), and asked for 2.4.0.
#      CMake 3.x warns; CMake 4.x REFUSES outright ("Compatibility with CMake <
#      3.5 has been removed").  The minimum is now 3.10 and the two lines are in
#      the required order.
#
#   2. GLIB WAS NEVER LOOKED FOR.  This was the macOS failure.  The SDL/POSIX
#      flavour of CSBwin is selected by -D_LINUX, and stdafx.h then did
#      "#include <glib.h>" while CSBTypes.h builds the engine's whole typedef
#      set (i8/ui8/.../i64, bool32, HWND, HTIMER) out of GLib's gint16/guint32
#      names and decides endianness from G_BYTE_ORDER.  So GLib was not
#      optional for this configuration - it was load-bearing.  The old file
#      only ever called FIND_PACKAGE(GTK2), whose include directories happen to
#      carry glib.h as a side effect; on a Linux box with GTK 2 installed that
#      accidentally worked, and on a Mac (where GTK 2 is not present and GLib
#      lives under a Homebrew prefix that is not on the default include path) it
#      failed with "glib.h: No such file or directory".
#
#      THERE IS NO GLib DEPENDENCY ANY MORE, on any platform, so there is
#      nothing here to find.  What the 41 compiled sources actually used from
#      GLib is fifteen typedefs, G_BYTE_ORDER, four integer<->pointer casts and
#      six printf wrappers; csbglib.h supplies all of it and stdafx.h includes
#      that instead.  This is the arrangement the OpenVMS port has used since
#      it was made (vmsglib.h, now a one-line alias for the same file) - see
#      csbglib.h's header comment for the inventory and the endianness
#      argument.  A Mac therefore needs SDL and nothing else: no Homebrew glib,
#      no pkg-config for it, no include-path archaeology.  The remaining
#      GLib-and-GTK surface in the tree (GString, g_queue_*, g_signal_connect)
#      is all inside #ifdef USE_OLD_GTK, which stays off - see the GTK 2
#      section at the bottom of this file.
#
#   3. THE APPLE BRANCH SELECTED THE CLASSIC MAC OS SOURCES.  It set
#      PLATFORM_SRC to MacScreen.cpp + CSBMac.cpp while still defining -D_LINUX.
#      MacScreen.cpp includes <DrawSprocket/DrawSprocket.h> and CSBMac.cpp
#      includes <TextUtils.h>, <LowMem.h>, <Timer.h>, <Dialogs.h>,
#      <MacWindows.h>, <QuickDraw.h>, <Fonts.h>, <Menus.h> - the Mac OS 9
#      Toolbox.  None of that has existed since Carbon was dropped; these two
#      files cannot be compiled by any current Apple toolchain.  The branch also
#      omitted LinCSBUI.cpp, so even a miracle compile would have had no UI_*
#      layer.  macOS now goes through exactly the same SDL/POSIX layer as Linux,
#      which is the configuration that actually works: SDL 1.2 has a Cocoa
#      backend.  MacScreen.cpp and CSBMac.cpp are left in the tree for
#      reference and are not built.
#
#   4. LinScreen.cpp AND WinScreen.cpp WERE BOTH IN THE BUILD.  They are
#      ALTERNATIVES - both define BLT*, UI_ScreenSetPixel and the rest of the
#      same symbol set - so the old list was a guaranteed duplicate-symbol link
#      failure on Linux.  The upstream makefile builds WinScreen.cpp and NOT
#      LinScreen.cpp (the name is historical: WinScreen.cpp is the shared
#      blitter, not Windows-specific), and that is what is done here.
#
#   5. SoundMixer.cpp WAS MISSING.  It is in the upstream makefile's object list
#      and it is what provides the Mix_* API the engine calls.  Without it the
#      link fails on Mix_OpenAudio and friends.
#
#   6. FIND_PACKAGE(SDL_mixer) + -DSOUND__SDLMIXER IS REMOVED, and must not come
#      back.  SoundMixer.cpp/h in this directory ARE a private implementation of
#      the Mix_* subset CSBwin uses, written directly on SDL audio.  A real
#      SDL_mixer collides on every Mix_* symbol and its Mix_Chunk layout is
#      different, so anything that did link would misbehave.
#
#   7. THE SDL VARIABLE NAMES WERE WRONG: ${SDL_INCLUDE_DIRS} and
#      ${SDL_LIBRARIES} (plural).  CMake's FindSDL module sets SDL_INCLUDE_DIR
#      and SDL_LIBRARY (singular).  The plural names expanded to nothing, so on
#      any system where SDL was not already on the default paths the build
#      failed even though FIND_PACKAGE had "succeeded".
#
#   8. -DSDL12 / -DSDL20 AND -DRGB655 WERE NOT DEFINED AT ALL.  Both are
#      mandatory.  LinCSBUI.cpp and CSBlinux.cpp are one file each covering both
#      SDL generations with "#ifdef SDL12 ... #elif defined SDL20", so with
#      neither macro set the entire platform layer compiles to almost nothing
#      and the link fails on UI_* and main().  RGB655 selects the 16-bit pixel
#      layout the blitters and the palette code agree on.
#
#   9. NewBugs.cpp, OldBugs.cpp and Stdafx.cpp were in the list and are not in
#      the upstream makefile.  They compile, but they define no external symbol
#      (checked, not assumed), so they are dead weight.  Dropped, which makes
#      this list exactly the 41 translation units the makefile builds.
#
#  10. THE SECOND macOS FAILURE was in stdafx.h and not here: it included
#      <memory.h>, a glibc compatibility header that macOS does not have, and
#      it did so BEFORE <glib.h>, so it was the error you hit first.  It now
#      includes <string.h>, which is where ISO C declares the memcpy/memset
#      that file wanted.  Recorded here because a reader who fixes note 2 and
#      expects a working Mac build should know the pair go together.
#
# The upstream makefile remains the reference for the Linux build; this file is
# kept in agreement with it.  For the OpenVMS build see DESCRIP.MMS,
# CONFIGURE.COM and COMPILER_FIXES.TXT - none of the above applies there,
# because vmsglib.h replaces GLib entirely on that platform.
# ============================================================================

cmake_minimum_required(VERSION 3.10)
project(CSBWin CXX)

set(PACKAGE_NAME    csb)
set(PACKAGE_VERSION 15.7.0)
set(PACKAGE_STRING "${PACKAGE_NAME} ${PACKAGE_VERSION}")

# Do not allow building at the root of the source tree.
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_BINARY_DIR AND NOT MSVC_IDE)
  message(FATAL_ERROR "In-source builds are not allowed.
   CMake would overwrite the files distributed with CSBWin.
   Please create a directory and run cmake from there, passing the path
   to this source directory as the last argument.
   This process created the file `CMakeCache.txt' and the directory
   `CMakeFiles'.  Please delete them.")
endif()

# ----------------------------------------------------------------------------
# Options
# ----------------------------------------------------------------------------
# SDL 1.2 is the default because it is the configuration this tree is best
# tested in and the one the OpenVMS port uses.  SDL 2 is the upstream makefile's
# default target; both arms of the platform layer are here, and exactly one of
# SDL12/SDL20 must be defined.
option(CSB_USE_SDL2 "Build against SDL 2 instead of SDL 1.2" OFF)

# -fsigned-char is NOT cosmetic.  This engine is a transliteration of 68000
# code and stores signed quantities in plain "char" in the on-disk structures;
# on ARM (Raspberry Pi, Apple silicon) char is unsigned by default and the
# comparisons silently change meaning.
if(NOT MSVC)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsigned-char")
endif()

# ----------------------------------------------------------------------------
# Diagnostics that Clang turns on by default and that this tree fires by design
# ----------------------------------------------------------------------------
# GCC needs none of this; Clang (so every Mac) enables the three below without
# being asked, and they account for over two hundred lines of output that say
# nothing about the code.  Each is switched off individually - the flag list is
# deliberately NOT -w or -Wno-everything, so a NEW warning still gets seen.
#
#   -Wno-pragma-pack             CSBTypes.h does "#pragma pack(1)" and never
#                                restores it, on purpose: the structures in
#                                CSB.h and Data.h are overlays on little-endian
#                                Atari-ST disk images and the packing has to
#                                hold for the whole translation unit (see the
#                                long comment at that pragma).  Clang warns once
#                                per include, ~80 times, that an included file
#                                changed the packing - which is the intent.
#
#   -Wno-switch                  The engine is a transliteration of 68000 code
#                                and switches on enums that enumerate every
#                                object, monster, timer and room type in the
#                                game while handling the handful of cases the
#                                original handled.  ~130 warnings, each listing
#                                dozens of enumerators; adding "default: break;"
#                                to that many statements would be a large
#                                diff that changes nothing.
#
#   -Wno-deprecated-declarations Apple's SDK marks sprintf deprecated in favour
#                                of snprintf.  The engine formats through
#                                sprintf throughout, including its own
#                                atari_sprintf() varargs shim, and the buffer
#                                sizes are checked by hand (two were fixed, see
#                                data.cpp and CSBUI.cpp).  macOS only.
#
# What is NOT suppressed, and should not be: -Wtautological-constant-out-of-
# range-compare still reports two comparisons of an unsigned enum against -1
# (CSBCode.cpp:1288, Mouse.cpp:832).  Those are dead tests - NameIndex() and
# DescIndex() signal "nothing" with objNI_NotAnObject, never with -1 - so one
# of them is a guard that never fires.  Silencing that would be hiding a
# question about the game's logic rather than a compiler's taste, and answering
# it changes behaviour, so it is left visible on purpose.
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wno-pragma-pack -Wno-switch)
  if(APPLE)
    add_compile_options(-Wno-deprecated-declarations)
  endif()
endif()

# ----------------------------------------------------------------------------
# Platform selection
# ----------------------------------------------------------------------------
# _LINUX in this tree does not mean "Linux the kernel"; it means "the SDL +
# POSIX platform layer" (CSBlinux.cpp + LinCSBUI.cpp + WinScreen.cpp).  Cygwin
# and macOS use it too - see note 3 above for why macOS in particular.
if(MSVC)
  message(STATUS "CSBwin: platform layer = Win32 (untested in this CMake file)")
  add_definitions(-D_MSVC_INTEL -D_MIDI -D_MOVIE)
  add_definitions(-D_CRT_SECURE_NO_DEPRECATE -D_CRT_SECURE_NO_WARNINGS)
  set(PLATFORM_SRC CSBwin.cpp Win32_SoundMixer.cpp)
elseif(UNIX OR CYGWIN)
  if(APPLE)
    message(STATUS "CSBwin: platform layer = SDL/POSIX on macOS")
  else()
    message(STATUS "CSBwin: platform layer = SDL/POSIX")
  endif()
  add_definitions(-D_LINUX -DRGB655)
  set(PLATFORM_SRC CSBlinux.cpp LinCSBUI.cpp SoundMixer.cpp)
else()
  message(FATAL_ERROR "Unable to determine platform")
endif()

# ----------------------------------------------------------------------------
# Sources - the same 41 translation units the upstream makefile builds
# ----------------------------------------------------------------------------
# WinScreen.cpp is in here for every platform on purpose: it is the shared
# blitter set, despite the name.  LinScreen.cpp and MacScreen.cpp are the
# alternatives to it and are deliberately absent (note 4).
set(ENGINE_SRC
    AsciiDump.cpp
    Attack.cpp
    Bitmaps.cpp
    CSBCode.cpp
    CSBUI.cpp
    Chaos.cpp
    Character.cpp
    Code11f52.cpp
    Code13ea4.cpp
    Code17818.cpp
    Code1f9e6.cpp
    Code222ea.cpp
    Code390e.cpp
    Code51a4.cpp
    Codea59a.cpp
    DSA.cpp
    Graphics.cpp
    Hint.cpp
    Magic.cpp
    Menu.cpp
    Monster.cpp
    Mouse.cpp
    MoveObject.cpp
    RC4.cpp
    Recording.cpp
    SaveGame.cpp
    SmartDiscard.cpp
    Sound.cpp
    Statistics.cpp
    Timer.cpp
    Translation.cpp
    VBL.cpp
    Viewport.cpp
    WinScreen.cpp
    data.cpp
    md5C.cpp
    system.cpp
    utility.cpp
)

# The "WIN32" keyword is ignored on other platforms.
add_executable(CsbWin WIN32 ${PLATFORM_SRC} ${ENGINE_SRC})

# ----------------------------------------------------------------------------
# GLib - deliberately NOT searched for.  See note 2.
# ----------------------------------------------------------------------------
# csbglib.h in this directory is the substitute, included by stdafx.h in place
# of <glib.h> on every platform (OpenVMS has done this all along).  Nothing to
# find, nothing to link, and no pkg-config needed for it - which is what makes
# a plain "brew install sdl12-compat" (or sdl) enough on a Mac.  Do not add a
# find_package/pkg_check_modules for GLib back: with both headers in one
# translation unit csbglib.h stops the build on purpose, because modern GLib
# makes g_error/g_warning/g_critical macros that collide with its functions.

# ----------------------------------------------------------------------------
# SDL
# ----------------------------------------------------------------------------
# Exactly one of SDL12 / SDL20 must be defined - see note 8.
#
# SDL 1.2 is located with CMake's FindSDL, whose variables are SINGULAR
# (SDL_INCLUDE_DIR, SDL_LIBRARY) - note 7.  On macOS FindSDL folds SDLmain and
# the Cocoa framework into SDL_LIBRARY for us, which is what makes an SDL 1.2
# main() link at all there.
#
# SDL 2 is located with pkg-config, matching the upstream makefile's
# Ubuntu_SDL20 target (which just calls sdl2-config).  pkg-config is found
# inside that branch and not at the top of the file on purpose: it is now
# needed ONLY for -DCSB_USE_SDL2=ON, so the default SDL 1.2 build - the one a
# fresh Mac is most likely to attempt - does not require pkg-config to be
# installed at all.
if(NOT MSVC)
  if(CSB_USE_SDL2)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(SDL2 REQUIRED IMPORTED_TARGET sdl2)
    target_compile_definitions(CsbWin PRIVATE SDL20)
    target_link_libraries(CsbWin PRIVATE PkgConfig::SDL2)
    message(STATUS "CSBwin: SDL ${SDL2_VERSION} (SDL20)")
  else()
    find_package(SDL REQUIRED)
    target_compile_definitions(CsbWin PRIVATE SDL12)
    target_include_directories(CsbWin PRIVATE ${SDL_INCLUDE_DIR})
    target_link_libraries(CsbWin PRIVATE ${SDL_LIBRARY})
    message(STATUS "CSBwin: SDL 1.2 at ${SDL_INCLUDE_DIR} (SDL12)")
  endif()
endif()

# ----------------------------------------------------------------------------
# GTK 2 - the optional menu bar, and it stays optional
# ----------------------------------------------------------------------------
# USE_OLD_GTK adds a GTK menu bar above the SDL window.  It is left OFF: the
# code behind it is GTK 2 only, every menu entry is also a command-line switch
# or an in-game key, and GTK 2 is gone from current macOS and being retired on
# Linux.  Enabling it means more than defining the macro - it wants
# GString/g_queue/g_signal surface that the OpenVMS build, for one, does not
# have - so the option is a deliberate dead end here rather than a half-wired
# one.  Kept as a comment because that is more useful than deleting it.
#
#   find_package(GTK2)
#   if(GTK2_FOUND)
#     target_include_directories(CsbWin PRIVATE ${GTK2_INCLUDE_DIRS})
#     target_link_libraries(CsbWin ${GTK2_LIBRARIES})
#     target_compile_definitions(CsbWin PRIVATE USE_OLD_GTK)
#   endif()

if(WIN32 AND NOT CYGWIN)
  target_link_libraries(CsbWin PRIVATE winmm.lib)
endif()
