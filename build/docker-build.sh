#!/bin/bash
set -ex
export ROOT="$(pwd)"
export PATH="$ROOT/Linux/amd64/bin:$PATH"

# Bootstrap mk
SYSTARG=Linux
OBJTYPE=amd64
PLAT=$ROOT/$SYSTARG/$OBJTYPE
CC="gcc -c -I$PLAT/include -I$ROOT/include -I$ROOT/utils/include"
LD="gcc"
AR="ar crvs"
RANLIB=":"

mkdir -p $PLAT/lib $PLAT/bin

# Build libregexp
cd $ROOT/utils/libregexp
$CC regaux.c regcomp.c regerror.c regexec.c regsub.c rregexec.c rregsub.c
$AR $PLAT/lib/libregexp.a *.o

# Build libbio
cd $ROOT/libbio
$CC bbuffered.c bfildes.c bflush.c bgetc.c bgetd.c bgetrune.c binit.c \
   boffset.c bprint.c bputc.c bputrune.c brdline.c brdstr.c bread.c \
   bseek.c bvprint.c bwrite.c
$AR $PLAT/lib/libbio.a *.o

# Build lib9
cd $ROOT/lib9
$CC argv0.c charstod.c cleanname.c create.c dirstat-posix.c dirwstat.c \
   dofmt.c dorfmt.c errfmt.c errstr-posix.c exits.c fcallfmt.c fltfmt.c \
   fmt.c fmtfd.c fmtlock.c fmtprint.c fmtquote.c fmtrune.c fmtstr.c \
   fmtvprint.c fprint.c getfields.c getuser-posix.c isnan-posix.c \
   mallocz.c nulldir.c pow10.c print.c qsort.c rerrstr.c rune.c \
   runeseprint.c runesmprint.c runesnprint.c runestrlen.c runevseprint.c \
   sbrk-posix.c seprint.c seek.c smprint.c snprint.c sprint.c strdup.c \
   strecpy.c strtoll.c strtoull.c u16.c u32.c u64.c utfecpy.c utflen.c \
   utfnlen.c utfrrune.c utfrune.c vfprint.c vseprint.c vsmprint.c \
   vsnprint.c
$AR $PLAT/lib/lib9.a *.o

# Build mk
cd $ROOT/utils/mk
$CC Posix.c sh.c arc.c archive.c bufblock.c env.c file.c graph.c \
   job.c lex.c main.c match.c mk.c parse.c recipe.c rule.c run.c \
   shprint.c symtab.c var.c varsub.c word.c
$LD -o mk *.o $PLAT/lib/libregexp.a $PLAT/lib/libbio.a $PLAT/lib/lib9.a
cp mk $PLAT/bin/

echo "Bootstrap complete"

# Build TaijiOS
cd $ROOT
export PATH="$ROOT/Linux/amd64/bin:$PATH"
mk mkdirs && mk && mk install
