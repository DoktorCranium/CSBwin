/* vmsglib.h - the OpenVMS name for CSBwin's GLib substitute.
 * ===========================================================================
 * OpenVMS 8.4 Alpha, HP C++ (CXX), SDL 1.2.
 *
 * THE CONTENT MOVED TO csbglib.h, AND WHY
 *
 *   This file was written for the OpenVMS port, because there is no GLib on
 *   OpenVMS 8.4 and the -D_LINUX platform layer that the port uses cannot
 *   compile without one (stdafx.h included <glib.h>, and CSBTypes.h builds
 *   every fundamental typedef and the endianness decision out of GLib names).
 *
 *   It then turned out that OpenVMS was not the only platform in that
 *   position.  macOS has no GLib either unless you install Homebrew or
 *   MacPorts and then teach the build where the headers went, and Homebrew's
 *   glib pulls in a stack of its own dependencies - all for fifteen typedefs
 *   and six printf wrappers.  Rather than keep two copies of the same
 *   substitute in step with each other, the substance of this file is now
 *   csbglib.h, which is platform-neutral and is what stdafx.h includes on
 *   macOS, Linux and Cygwin as well.  Everything OpenVMS-specific that used to
 *   live here - the VMS_NO_INTPTR_T escape hatch, the hand-written exact-width
 *   typedefs, the little-endian answer for Alpha and I64 - survives there
 *   under #ifdef __VMS, and the reasoning survives with it.
 *
 *   The name is kept, and kept working, because it is what DESCRIP.MMS,
 *   CONFIGURE.COM, BUILD.COM, README.VMS and COMPILER_FIXES.TXT all refer to,
 *   and because "$ MMK" on a VMS machine should not need to be re-taught
 *   anything.  csbglib.h must be present beside it; both are in DESCRIP.MMS's
 *   HDRS list and CONFIGURE.COM checks for both.
 *
 *   Read csbglib.h for the inventory of what is provided, the endianness
 *   argument, the intptr_t history and the pointer-width warning.  There is
 *   nothing else in this file.
 *
 * ===========================================================================
 */

#ifndef __VMSGLIB_H__
#define __VMSGLIB_H__

#ifndef __VMS
#error vmsglib.h is the OpenVMS spelling and is only for __VMS builds - every \
other platform includes csbglib.h directly, which is what stdafx.h does
#endif

#include "csbglib.h"

#endif /* __VMSGLIB_H__ */
