/* Rts/Sys/unix-alloc.c 
 * Larceny Run-Time System  --  low-level memory allocator (Unix).
 *
 * $Id: unix-alloc.c,v 1.8 1997/05/15 00:58:49 lth Exp lth $
 *
 * This allocator handles memory allocation for Larceny and manages the
 * memory descriptor tables that are used by the collector and the write
 * barrier.  All allocation is done in page-sized chunks on page
 * boundaries, and other allocators (e.g. malloc) can co-exist with 
 * this one, as long as those allocators can cope with code that manipulates
 * the program break independently of the allocators.
 *
 * It is expected that requests for memory will be large and infrequent; 
 * this allocator is not intended to be a replacement for malloc and friends.
 *
 * There are two descriptor tables: gclib_desc_g maps page numbers to
 * generation numbers, and gclib_desc_b maps page numbers to attribute bits.
 * The "page number" of an address is defined by the pageof() macro in 
 * gclib.h; it is the address minus the value of the global gclib_pagebase, 
 * all shifted right to throw away the low-order bits.
 *
 * There are two separate tables rather than one table of records in
 * order to simplify manipulation from assembly language (i.e., in the
 * write barrier).
 *
 * The low 16 bits of the attribute bits are reserved by the allocator;
 * the rest of the RTS can use the high bits.
 *
 * This code is not reentrant.
 */  

#define GC_INTERNAL

#include <errno.h>
#include "larceny.h"
#include "gclib.h"
#include "assert.h"

caddr_t sbrk( int incr );

typedef struct freelist freelist_t;
struct freelist {
  unsigned   size;
  freelist_t *next;
};


/* Public globals */

unsigned *gclib_desc_g;              /* generation owner */
unsigned *gclib_desc_b;              /* attribute bits */
caddr_t  gclib_pagebase;             /* page address of lowest known word */


/* Private globals */

static unsigned   descriptor_slots;  /* number of allocated slots */
static caddr_t    memtop;            /* address of highest known word */
static freelist_t *freelist;         /* linear list of chunks */
static unsigned   heap_bytes;        /* bytes allocated to heap */
static unsigned   remset_bytes;      /* bytes allocated to remset */
static unsigned   rts_bytes;         /* bytes allocated to RTS "other" */

static void *gclib_alloc( unsigned bytes );
static void dump_freelist( void );


/* Initialize descriptor tables and memory allocation pointers. */

void 
gclib_init( void ) 
{
  caddr_t ptr;
  int i, diff;

  ptr = sbrk( 0 );
  if ((int)ptr == -1) goto failure;

  diff = roundup_page( ptr )-(word)ptr;
  if (diff > 0) {
    if ((int)sbrk( diff ) == -1) goto failure;
  }
  gclib_pagebase = memtop = sbrk( 0 );
  if ((int)gclib_pagebase == -1) goto failure;

  assert( (word)gclib_pagebase == roundup_page( gclib_pagebase ) );

  descriptor_slots = 32*1024*1024 / PAGESIZE;   /* Slots to handle 32 MB */

  /* It's OK to be using malloc() here */
  gclib_desc_g =
    (unsigned*)must_malloc( sizeof( unsigned ) * descriptor_slots );
  gclib_desc_b =
    (unsigned*)must_malloc( sizeof( unsigned ) * descriptor_slots );

  for ( i = 0 ; i < descriptor_slots ; i++ )
    gclib_desc_g[i] = gclib_desc_b[i] = 0;

  freelist = 0;
  return;

 failure:
  panic( "Fatal sbrk() failure: no memory." );
}


/* Allocate memory for the garbage-collected heap.
 *
 * Allocate the requested number of bytes, rounded up to an integral
 * number of pages, and return a pointer to the memory.  Set the
 * heap ownership and generation ownership as indicated.  Pointer is
 * aligned to the beginning of a page.
 */
void *gclib_alloc_heap( unsigned bytes, unsigned heap_no, unsigned gen_no )
{
  void *ptr;
  int i;
  caddr_t oldtop;

  bytes = roundup_page( bytes );
  oldtop = memtop;
  ptr = gclib_alloc( bytes );

  for ( i = pageof( ptr ) ; i < pageof( ptr+bytes ); i++ ) {
    assert( ptr >= (void*)oldtop || (gclib_desc_b[i] & MB_FREE) );
    gclib_desc_g[i] = gen_no;
    gclib_desc_b[i] = MB_ALLOCATED | MB_HEAP_MEMORY;
  }
  heap_bytes += bytes;
  return ptr;
}


/* Allocate memory for the run-time system */
void *gclib_alloc_rts( unsigned bytes, unsigned attribute )
{
  void *ptr;
  int i;
  caddr_t oldtop;

  bytes = roundup_page( bytes );
  oldtop = memtop;
  ptr = gclib_alloc( bytes );

  for ( i = pageof( ptr ) ; i < pageof( ptr+bytes ); i++ ) {
    assert( ptr >= (void*)oldtop || (gclib_desc_b[i] & MB_FREE) );
    gclib_desc_g[i] = RTS_OWNED_PAGE;
    gclib_desc_b[i] = MB_ALLOCATED | MB_RTS_MEMORY | attribute;
  }
  if (attribute & MB_REMSET)
    remset_bytes += bytes;
  else
    rts_bytes += bytes;
  return ptr;
}


/*
 * This allocator is first-fit, which is probably not very good, but
 * not a major problem at this time.
 */
static void *gclib_alloc( unsigned bytes )
{
  int i, diff;
  caddr_t newtop, ptr, top;
  freelist_t *f, *prev;

  if (bytes == 0) return 0;

  bytes = roundup_page( bytes );
  for ( f = freelist, prev=0; f != 0 && f->size < bytes ; prev=f, f=f->next )
    ;
  if (f != 0) {
    freelist_t *n;

    if (f->size > bytes) {
      n = (freelist_t*)((char*)f+bytes);
      n->next = f->next;
      n->size = f->size - bytes;
    }
    else
      n = f->next;
    if (prev != 0)
      prev->next = n;
    else
      freelist = n;

#ifdef GCLIB_DEBUG
    consolemsg( "  *** (allocated %p %u from-free-list)", f, bytes );
    dump_freelist();
#endif
    return (void*)f;
  }

  newtop = sbrk( 0 );
  if ((int)newtop == -1) return 0;

  assert( newtop >= memtop );

  /* Round up the break to page boundary if necessary; another allocator
   * may have visited while we were out.
   */
  if (newtop != memtop) {
    diff = roundup_page( newtop ) - (word)newtop;
    if (diff != 0) {
      if ((int)sbrk( diff ) == -1) return 0;
    }
  }

  ptr = sbrk( bytes );
  if ((int)ptr == -1) return 0;
  top = ptr+bytes;

 again:
  if (pageof( top ) - pageof( gclib_pagebase ) > descriptor_slots) {
    unsigned slots = descriptor_slots * 2;
    unsigned *desc_g, *desc_b;

    annoyingmsg( "Growing page tables; new slots=%u.", slots );

    desc_g = (unsigned*)realloc( gclib_desc_g, sizeof( unsigned ) * slots );
    desc_b = (unsigned*)realloc( gclib_desc_b, sizeof( unsigned ) * slots );

    if (desc_g == 0 || desc_b == 0) {
      /* FIXME: should handle memory allocation failure, but this
	 does not allow us to use realloc (because a non-grown table
	 must not be freed).
       */
      panic( "gclib_allocate: unable to grow page tables." );
    }
    descriptor_slots = slots;
    for ( i=descriptor_slots ; i < slots ; i++ )
      desc_b[i] = desc_g[i] = 0;

    gclib_desc_g = desc_g;
    gclib_desc_b = desc_b;
    wb_re_setup( gclib_desc_g );  /* HACK! UGLY! FIXME! */
                                  /* (would be method on "arena" object?) */
    goto again;
  }

  for ( i = pageof( memtop ) ; i < pageof( ptr ) ; i++ ) {
    gclib_desc_g[i] = FOREIGN_PAGE;
    gclib_desc_b[i] = MB_ALLOCATED | MB_FOREIGN;
  }

  memtop = top;

#ifdef GCLIB_DEBUG
  consolemsg( "  *** (allocated %p %u fresh)", ptr, bytes );
#endif
  return (void *)ptr;
}


/*
 * Free the memory (rounded up to an integral number of bytes), and
 * clear the ownership bits.
 */
void gclib_free( void *addr, unsigned bytes )
{
  freelist_t *fl, *f, *p;
  unsigned pages;
  unsigned pageno;

  assert(((word)addr & PAGEMASK) == 0);

  bytes = roundup_page( bytes );
#ifdef GCLIB_DEBUG
  consolemsg( "  *** (free %p %u)", addr, bytes );
#endif
  pages = bytes/PAGESIZE;
  pageno = pageof( addr );

  /* This assumes that all pages being freed have the same major attributes.
   * That is a reasonable assumption.
   */
  if (pages > 0) {
    if (gclib_desc_g[pageno] & MB_HEAP_MEMORY)
      heap_bytes -= bytes;
    else if (gclib_desc_g[pageno] & MB_REMSET)
      remset_bytes -= bytes;
    else
      rts_bytes -= bytes;
  }
  while (pages > 0) {
    assert( (gclib_desc_b[pageno] & MB_ALLOCATED ) &&
	    !(gclib_desc_b[pageno] & MB_FOREIGN ) );
    gclib_desc_g[pageno] = UNALLOCATED_PAGE;
    gclib_desc_b[pageno] = MB_FREE;
    pageno++;
    pages--;
  }

  f = (freelist_t*)addr;
  f->size = bytes;
  f->next = 0;

  for ( fl = freelist, p = 0 ; fl != 0 ; p = fl, fl = fl->next ) {
    if ((char*)fl+fl->size == (char*)f) {
      fl->size += bytes;
#ifdef GCLIB_DEBUG
      debugmsg( "      trailing existing at %p", fl );
#endif
      break;
    }
    else if ((char*)f+f->size == (char*)fl) {
      f->size += fl->size;
      f->next = fl->next;
#ifdef GCLIB_DEBUG
      debugmsg( "      preceding existing at %p", fl );
#endif
      if (p == 0)
	freelist = f;
      else
	p->next = f;
      break;
    }
  }

  if (fl == 0) {
    f->next = freelist;
    freelist = f;
  }
#ifdef GCLIB_DEBUG
  dump_freelist();
#endif
}


/* Given a semispace, set the generation number for all memory allocated
 * to the semispace to the given generation number.
 */
void gclib_set_gen_no( semispace_t *s, int gen_no )
{
  int i;
  word *bot, *lim;

  s->gen_no = gen_no;
  for ( i = 0 ; i < s->n ; i++ ) {
    if (s->chunks[i].bytes == 0) continue;
    bot = s->chunks[i].bot;
    lim = s->chunks[i].lim;
    while (bot < lim) {
      gclib_desc_g[pageof(bot)] = gen_no;
      bot += PAGESIZE/sizeof(word);
    }
  }
}


/* Return information about memory use */
void gclib_stats( word *wheap, word *wremset, word *wrts )
{
  *wheap = heap_bytes;
  *wremset = remset_bytes;
  *wrts = rts_bytes;
}


void dump_freelist( void )
{
  freelist_t *f = freelist;

  consolemsg( "   FREELIST" );
  while (f != 0) {
    consolemsg( "       %p %p (%d)",
	        (void*)f, (void*)((char*)f+f->size), f->size );
    f = f->next;
  }
}

/* eof */
