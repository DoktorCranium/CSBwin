/* VMSFileName.inl - class FILENAME for OpenVMS.
 * ===========================================================================
 * Included by system.cpp under __VMS, in place of LinuxFileName.inl.  Same
 * class, same six member functions, same MODIFIEDTIME() helper - the ONLY
 * thing that differs is how a folder and a file name are joined into a
 * filespec, and what counts as "already fully specified".
 *
 * WHY A SEPARATE FILE INSTEAD OF #ifdefs IN LinuxFileName.inl
 *
 *   LinuxFileName.inl joins with '/' in createName() and decides a path is
 *   absolute by testing for a leading '/' in createThreeNames().  Both of
 *   those are one-liners, but they are the only two places in the whole engine
 *   that know anything about path syntax, and on OpenVMS both change shape
 *   rather than change a character:
 *
 *     - a directory is not a prefix ending in a separator, it is a bracketed
 *       component list: [.TRACES]TRACE000.TXT, not traces/TRACE000.txt;
 *     - "fully specified" is not "starts with /" but "contains a device
 *       (DKA0:), a rooted logical (CSB$DATA:) or a directory ([...])";
 *     - "up one level" is [-], not "..".
 *
 *   Sprinkling those through the Linux file would leave neither version
 *   readable.  The sibling OpenVMS ports in this tree do the same thing (each
 *   has its own platform file rather than a maze of #ifdefs).
 *
 * WHAT THE ENGINE ACTUALLY ASKS FOR
 *
 *   Every file the game opens goes through this class - OPEN(), CREATE(),
 *   RENAME(), UNLINK() in system.cpp all construct a FILENAME.  The names it
 *   is handed are:
 *
 *     plain names       DUNGEON.DAT, hcsb.dat, hcsb.hct, mini.dat,
 *                       graphics.dat, CSBgraphics.dat, config.txt,
 *                       Translation.txt, annotation.txt, DUNGEON.FTL,
 *                       socko.wav, ASCIIDUMP.TXT, trace.log
 *     folder + name     "traces/TRACE000.txt"  (data.cpp OpenTraceFile)
 *                       "logs/Record00001.log" (Recording.cpp)
 *                       - passed as a separate folder string, and both call
 *                         sites retry with the folder emptied if the folder
 *                         does not exist, so a missing [.TRACES] degrades to
 *                         writing in the current directory rather than failing
 *     user-supplied     whatever --directory / --modules / --root-path /
 *                       --dungeon were given on the command line
 *
 *   The plain names are all valid ODS-2 names as they stand (<=39 characters
 *   of name, one dot, one <=39-character type, no other punctuation), so
 *   nothing has to be mangled.  ODS-2 is case-insensitive and upshifts, so the
 *   mixed-case names the engine uses all resolve to the same file whichever
 *   case it is stored in - which is why hcsb.dat and DUNGEON.DAT can sit side
 *   by side in the same directory here as they do on Windows.
 *
 * THE FOUR CANDIDATES
 *
 *   createThreeNames() builds up to four candidate filespecs and Open() tries
 *   them in order - m_name[1] from folderParentName, m_name[2] from
 *   folderName, m_name[3] from root - which is how --directory and --modules
 *   work: a name is looked for in the module directory, then the parent, then
 *   the root, and the first one that opens wins.  m_name[0] is used only for
 *   the already-fully-specified case.  All three folder variables default to
 *   "." in main(), which this file maps to "no prefix at all", i.e. the
 *   current default directory - so an unswitched run reads its data files out
 *   of SYS$DISK:[], exactly like the Linux build reads them out of ./ .
 * ===========================================================================
 */

#include <string.h>

/* Longest filespec we will build.  RMS accepts 255 for a full spec; 512 gives
 * room for a long user-supplied device+directory plus a name without ever
 * needing to think about it.  Anything longer is rejected (createName returns
 * NULL and that candidate is skipped) rather than truncated - a truncated
 * filespec is how you silently open or, far worse, CREATE the wrong file. */
#define VMS_SPEC_MAX 512

/* Is this already a filespec RMS can use on its own - i.e. does it name a
 * device, a logical or a directory?  ':' catches DKA0: and CSB$DATA:, '[' and
 * '<' catch both directory bracket styles.  This is the OpenVMS equivalent of
 * LinuxFileName.inl's leading-'/' test, and it is used for the same purpose:
 * when the caller has said exactly where the file is, do not prepend any of
 * the search folders to it. */
static bool VMS_IsFullSpec(const char *s)
{
  if (s == NULL) return false;
  return    (strchr(s, ':') != NULL)
         || (strchr(s, '[') != NULL)
         || (strchr(s, '<') != NULL);
}

/* Collect the directory components of a UNIX-style relative path.
 *
 * Fills comp[] with the named components in order and returns their count;
 * *pUp receives the number of leading ".." components ("up one directory",
 * [-] in VMS syntax).  "." components and empty components (from "//" or a
 * trailing '/') are dropped, which is what makes the engine's default folder
 * value of "." come out as "no directory at all".
 *
 * If "path" has no trailing '/' its LAST component is a file name, not a
 * directory, so callers pass wantLast=false to leave it out.
 *
 * A ".." that appears after a named component (a/../b) is NOT handled - it
 * returns -1 and the candidate is skipped.  VMS does allow [.A.-.B] but the
 * engine never generates such a path (folders come from a literal "traces/" or
 * "logs/", or from a command-line switch that a VMS user would give in VMS
 * syntax anyway) and quietly mis-resolving a path is worse than not opening
 * it. */
static i32 VMS_SplitDirs(const char *path,
                         bool        wantLast,
                         char        comp[16][64],
                         i32        *pUp)
{
  i32         n = 0;
  i32         up = 0;
  const char *p;
  const char *start;

  *pUp = 0;
  if (path == NULL) return 0;
  p = path;
  while (*p != '\0')
  {
    size_t len;
    start = p;
    while ((*p != '\0') && (*p != '/')) p++;
    len = (size_t)(p - start);
    if (*p == '/')
    {
      p++;                                  /* this component IS a directory */
    }
    else
    {
      if (!wantLast) break;                 /* trailing component is the file */
    };
    if (len == 0) continue;                                  /* "" from "//" */
    if ((len == 1) && (start[0] == '.')) continue;        /* "." - no effect */
    if ((len == 2) && (start[0] == '.') && (start[1] == '.'))
    {
      if (n != 0) return -1;             /* "a/../b" - see the comment above */
      up++;
      continue;
    };
    if (len >= sizeof(comp[0])) return -1;             /* component too long */
    if (n >= 16) return -1;                             /* too many of them */
    memcpy(comp[n], start, len);
    comp[n][len] = '\0';
    n++;
  };
  *pUp = up;
  return n;
}

/* The file name part of a UNIX-style path: everything after the last '/'. */
static const char *VMS_BaseName(const char *path)
{
  const char *slash = strrchr(path, '/');
  return (slash == NULL) ? path : (slash + 1);
}

class FILENAME			// To avoid malloc and memory leaks
{
private:
  char *m_name[4];
  void createThreeNames (const char *filename);
  const char *createName (const char *folder, const char *file);
public:
  char* m_fName;
  FILE * Open (const char *name, const char *flags);
  FILE *Create (const char *name, const char *flags);
  i32 Rename (const char *oldname, const char *newname);
  i32 Unlink (const char *name);
  FILENAME (void);
  ~FILENAME (void);
};

FILENAME::FILENAME (void)
{
  m_name[0] = NULL;
  m_name[1] = NULL;
  m_name[2] = NULL;
  m_name[3] = NULL;
  m_fName   = NULL;
}

FILENAME::~FILENAME (void)
{
  int i;
  for (i = 0; i < 4; i++)
  {
    if (m_name[i] != NULL)
    {
      UI_free (m_name[i]);
    };
    m_name[i] = NULL;
  };
  if (m_fName != NULL) UI_free(m_fName);
}

/* Join a folder and a file into one OpenVMS filespec.
 *
 * Returns a UI_malloc'd string the caller owns (the destructor frees it), or
 * NULL if there is nothing to build or the result would not fit.  The four
 * shapes it produces:
 *
 *   folder            file              result
 *   ----------------  ----------------  --------------------------------
 *   "" / NULL / "."   DUNGEON.DAT       DUNGEON.DAT
 *   "traces/"         TRACE000.txt      [.TRACES]TRACE000.txt
 *   "DKA0:[CSB]"      DUNGEON.DAT       DKA0:[CSB]DUNGEON.DAT
 *   "CSB$DATA:"       DUNGEON.DAT       CSB$DATA:DUNGEON.DAT
 *
 * plus the same four with extra directory levels carried in the FILE argument
 * ("dungeons/x/foo.dat"), which is folded into the bracket list rather than
 * being left as slashes: [.DUNGEONS.X]foo.dat.  That matters because the RTL's
 * own UNIX-filespec translation is controlled by DECC$ feature logicals that
 * may or may not be set on the user's system, and a filespec this code builds
 * itself works either way.
 */
const char * FILENAME::createName (const char *folder, const char *file)
{
  char  spec[VMS_SPEC_MAX];
  char  comp[16][64];
  i32   nComp;
  i32   nUp;
  char *result;

  if (file == NULL)     return NULL;
  if (strlen (file) == 0) return NULL;

  /* An explicit device / logical / directory in the FILE argument means the
   * caller already knows exactly where the file is - the folder is not ours
   * to add.  (--dungeon DKA0:[GAMES.CSB]DUNGEON.DAT reaches us this way.) */
  if (VMS_IsFullSpec (file))
  {
    if (strlen (file) >= VMS_SPEC_MAX) return NULL;
    result = (char *) UI_malloc (strlen (file) + 1, MALLOC033);
    if (result != NULL) strcpy (result, file);
    return result;
  };

  /* A UNIX absolute path is passed through untouched, exactly as
   * LinuxFileName.inl passes it through: we cannot turn /usr/games/csb into a
   * VMS filespec without knowing how that user's mount points are set up, but
   * the DEC C RTL can translate one when DECC$FILENAME_UNIX_ONLY (or the
   * equivalent feature logical) is enabled, so handing it over unchanged gives
   * that configuration a chance to work while a VMS-syntax spec always
   * works. */
  if (file[strspn (file, " \t")] == '/')
  {
    if (strlen (file) >= VMS_SPEC_MAX) return NULL;
    result = (char *) UI_malloc (strlen (file) + 1, MALLOC033);
    if (result != NULL) strcpy (result, file);
    return result;
  };

  nComp = VMS_SplitDirs (file, false, comp, &nUp);
  if (nComp < 0) return NULL;

  spec[0] = '\0';

  if ((folder != NULL) && (*folder != '\0') && VMS_IsFullSpec (folder))
  {
    /* Native VMS folder.  If it already ends in a directory spec we splice any
     * extra levels from the file argument inside its closing bracket
     * (DKA0:[CSB] + dungeons/x/ -> DKA0:[CSB.DUNGEONS.X]); if it is only a
     * device or logical we open a fresh relative bracket after it. */
    size_t flen = strlen (folder);
    if (flen + 1 >= VMS_SPEC_MAX) return NULL;
    strcpy (spec, folder);
    if ((flen > 0) && ((spec[flen-1] == ']') || (spec[flen-1] == '>')))
    {
      if (nComp > 0)
      {
        char closer[2];
        i32  i;
        closer[0] = spec[flen-1];
        closer[1] = '\0';
        spec[flen-1] = '\0';                          /* reopen the bracket */
        for (i = 0; i < nComp; i++)
        {
          if (strlen (spec) + strlen (comp[i]) + 3 >= VMS_SPEC_MAX) return NULL;
          strcat (spec, ".");
          strcat (spec, comp[i]);
        };
        strcat (spec, closer);
      };
    }
    else
    {
      if (nComp > 0)
      {
        i32 i;
        strcat (spec, "[");
        for (i = 0; i < nComp; i++)
        {
          if (strlen (spec) + strlen (comp[i]) + 3 >= VMS_SPEC_MAX) return NULL;
          strcat (spec, ".");
          strcat (spec, comp[i]);
        };
        strcat (spec, "]");
      };
    };
  }
  else
  {
    /* UNIX-style or empty folder: merge the folder's components and the file's
     * components into a single relative directory spec.  Empty and "."
     * components have already been dropped by VMS_SplitDirs, so the engine's
     * default folder of "." yields no bracket at all and the file is opened in
     * the current default directory. */
    char fcomp[16][64];
    i32  nF;
    i32  nFUp;
    i32  nTotalUp;
    i32  i;

    nF = VMS_SplitDirs (folder, true, fcomp, &nFUp);
    if (nF < 0) return NULL;

    /* A VMS relative directory spec is "[" + N '-' + named components + "]",
     * so every "up" has to come before every name.  Folding the file's leading
     * ".."s in behind the folder's named components would mean cancelling them
     * out - i.e. normalising the path - and this code does not do that; it
     * returns NULL instead and the candidate is skipped.  (Nothing in the
     * engine generates such a combination.) */
    if ((nF != 0) && (nUp != 0)) return NULL;
    nTotalUp = nFUp + nUp;

    if ((nF + nComp + nTotalUp) != 0)
    {
      strcpy (spec, "[");
      for (i = 0; i < nTotalUp; i++) strcat (spec, "-");
      for (i = 0; i < nF; i++)
      {
        if (strlen (spec) + strlen (fcomp[i]) + 3 >= VMS_SPEC_MAX) return NULL;
        strcat (spec, ".");
        strcat (spec, fcomp[i]);
      };
      for (i = 0; i < nComp; i++)
      {
        if (strlen (spec) + strlen (comp[i]) + 3 >= VMS_SPEC_MAX) return NULL;
        strcat (spec, ".");
        strcat (spec, comp[i]);
      };
      strcat (spec, "]");
    };
  };

  {
    const char *base = VMS_BaseName (file);
    if (strlen (spec) + strlen (base) + 1 >= VMS_SPEC_MAX) return NULL;
    strcat (spec, base);
  };

  result = (char *) UI_malloc (strlen (spec) + 1, MALLOC034);
  if (result != NULL)
  {
    strcpy (result, spec);
  };
  return result;
}


void FILENAME::createThreeNames (const char *filename)
{
  if (m_name[0] != NULL)
  {
    UI_free (m_name[0]);
    m_name[0] = NULL;
  };
  if (m_name[1] != NULL)
  {
    UI_free (m_name[1]);
    m_name[1] = NULL;
  };
  if (m_name[2] != NULL)
  {
    UI_free (m_name[2]);
    m_name[2] = NULL;
  };
  if (m_name[3] != NULL)
  {
    UI_free (m_name[3]);
    m_name[3] = NULL;
  };
  /* OpenVMS equivalent of the Linux absolute-path check: a spec that names its
   * own device, logical or directory is used as given and the three search
   * folders are not consulted. */
  if ((filename != NULL) && VMS_IsFullSpec (filename))
  {
    m_name[0] = (char*)createName ("", filename);
    return;
  };
  if ((filename != NULL) && ('/' == *(strspn(filename," \t")+filename)))
  {
    m_name[0] = (char*)createName ("", filename);
    return;
  };
  // Default folders for relative pathways.
  //if (folderSavedGame != NULL)
  //{
  //  m_name[0] = (char*)createName (folderSavedGame, filename);
  //};
  if (folderParentName != NULL)
  {
    m_name[1] = (char*)createName (folderParentName, filename);
  };
  if (folderName != NULL)
  {
    m_name[2] = (char*)createName (folderName, filename);
  };
  m_name[3] = (char*)createName (root, filename);
}

FILE *FILENAME::Open(const char *name, const char *flags)
{
  FILE *result = NULL;
  int i;
  createThreeNames (name);
  for (i = 0; i < 4; i++)
  {
    if (m_name[i] == NULL)
    {
      continue;
    };
    result = UI_fopen (m_name[i], flags);
    if (result != NULL)
    {
      if (TimerTraceActive)
      {
        fprintf (GETFILE (TraceFile), "Opened %s\n",
						 m_name[i]);
      };
      m_fName = (char*)UI_malloc(strlen(m_name[i])+1,MALLOC106	);
      strcpy(m_fName, m_name[i]);
      return result;
    };
  };
  return NULL;
}


FILE *FILENAME::Create (const char *name, const char *flags)
{
  int i;
  createThreeNames (name);
  for (i = 0; i < 4; i++)
  {
    if (m_name[i] == NULL)
    {
      continue;
    };
    return UI_fopen (m_name[i], flags);
  };
  return NULL;
}

i32 FILENAME::Rename (const char *oldname, const char *newname)
{
  FILENAME newfile;
  int i;
  createThreeNames (oldname);
  newfile.createThreeNames (newname);
  for (i = 0; i < 4; i++)
  {
    if (m_name[i] == NULL)
    {
      continue;
    };
    return rename (m_name[i], newfile.m_name[i]);
  };
  return -1;
}

i32 FILENAME::Unlink (const char *name)
{
  int i;
  createThreeNames (name);
  for (i = 0; i < 4; i++)
  {
    if (m_name[i] == NULL)
    {
      continue;
    };
    return UI_DeleteFile (m_name[i]);
  };
  return 0;
}

#include <sys/stat.h>
char *GETFILENAME(i32 f);

/* Last-modified time of an open file, in whatever unit stat() reports (the
 * engine only ever compares two of these against each other - SaveGame.cpp
 * uses it to notice that the dungeon file changed under a saved game).  The
 * OpenVMS CRTL supplies stat() and st_mtime with UNIX epoch semantics, so this
 * is unchanged from the Linux version. */
ui64 MODIFIEDTIME(i32 file)
{
  const  char* fn = GETFILENAME(file);
  struct stat  info;

  if ((fn != NULL) && (stat(fn, &info)==0))
  {
    return info.st_mtime;
  }
  return 0;
}
