/* Copyright 1998 Lars T Hansen.
 *
 * $Id$
 *
 * Interface to the Boehm-Demers-Weiser conservative garbage collector.
 *
 * Allocation:
 *
 * Allocation happens by callout to millicode.  Therefore, the millicode
 * has been hacked to call GC_malloc() to allocate memory.
 *
 * The stack cache:
 *
 * The stack cache must have the same appearance to compiled code as it
 * usually has.  This means setting up the pointers in the globals table
 * and so on.  However, since we have no control over when the collector
 * is called, we cannot count on flushing the stack before gc, so the
 * stack must be visible to the collector.  That means that there might
 * be garbage beyond the stack top that will cause retention!  I don't
 * yet know how to fix this, although it can be fixed by periodically
 * clearing the stack cache above the current point.  Clearing can be
 * triggered by overflow/underflow or other events.
 *
 * The static area (data_load_area, text_load_area):
 *
 * These are allocated in the heap as a two large objects, with
 * private (but gc-visible) anchors that ensure that none of the
 * objects in the loaded heap image will be collected.  This is not
 * ideal, but it's not unreasonable (paging from a file would have
 * the same effect).  
 *
 * It is probably important to use a split heap (where the code vectors
 * are in a separate segment) so that the collector will not get confused
 * about instructions looking like data.  This has yet to be substantiated.
 *
 * The code in this file is reentrant.
 * The code in this file does not rely on word size.
 * The code in this file does not depend on header size.
 */

#define BDW_CLEAR_STACK 1
#define BDW_DEBUG       1

#define GC_INTERNAL

#define STACK_CACHE_SIZE  (1024*64)

#include <string.h>
#include "larceny.h"
#include "gc.h"
#include "gc_t.h"
#include "memmgr.h"
#include "gclib.h"
#include "barrier.h"
#include "heap_stats_t.h"
#include "stack.h"
#include "../bdw-gc/include/gc.h"

#if defined( NO_ATOMIC_ALLOCATION )
const char *larceny_gc_technology = "conservative/noatomic";
#  define GC_malloc_atomic GC_malloc
#  define GC_malloc_atomic_ignore_off_page GC_malloc_ignore_off_page
#else
const char *larceny_gc_technology = "conservative";
#endif

typedef struct {
  word *globals;

  unsigned frames_flushed;
  unsigned stacks_created;
  unsigned bytes_flushed;
} bdw_data_t;

#define DATA( gc )   ((bdw_data_t*)gc->data)

static void init_stack( gc_t *gc );
static void flush_stack( gc_t *gc );
static gc_t *allocate_area( word *globals );

/* You can turn this off to allow multiple collectors in the same process. */
#if BDW_DEBUG
static word *bdw_globals = 0;
#endif

extern double GC_load_factor;
extern void GC_set_min_heap_size( int min_size_bytes );

void bdw_before_gc( void );
void bdw_after_gc( void );
void bdw_before_gc_slowpath( void );
void bdw_after_gc_slowpath( void );

static GC_PTR bdw_out_of_memory_handler( size_t bytes_requested );

gc_t *
create_bdw_gc( gc_param_t *params, int *generations )
{
  gc_t *gc;

  *generations = 1;

  gc = allocate_area( params->globals );
  GC_INIT();
  GC_register_displacement( 0 );
  GC_register_displacement( 1 );
  GC_register_displacement( 3 );
  GC_register_displacement( 5 );
  GC_register_displacement( 7 );
  GC_oom_fn = bdw_out_of_memory_handler;

  if (params->bdw_info.divisor > 0)
    GC_free_space_divisor = params->bdw_info.divisor;
  if (params->bdw_info.dynamic_max > 0) 
    GC_set_max_heap_size( params->bdw_info.dynamic_max );
  if (params->bdw_info.dynamic_min > 0)
    GC_set_min_heap_size( params->bdw_info.dynamic_min );
  if (params->bdw_info.load_factor > 0.0)
    GC_load_factor = params->bdw_info.load_factor;
  if (params->use_incremental_bdw_collector)
    GC_enable_incremental();

  init_stack( gc );
  wb_disable_barrier( params->globals );

  return gc;
}

void gc_parameters( gc_t *gc, int op, int *ans )
{
  if (op == 0) {
    ans[0] = 2;			/* Conservative */
    ans[1] = 1;			/* One generation */
  }
  else {
    ans[0] = 5;			/* Conservative mark/sweep */
    ans[1] = 0;			/* Don't know */
    ans[2] = 1;			/* Expandable */
  }
}

/* Hook run before gc (if gc has been set up to do it). */

/* Fast hooks to run before/after lazy sweep */

#define USE_HR_TIMER 1		/* Nanosecond timer; SunOS 5.6 (at least) */
				/* Experimental */

#if USE_HR_TIMER
static hrtime_t slowpath_timeval;
static hrtime_t slowpath_nsec = 0;
#else
static struct timeval slowpath_timeval;
static long slowpath_usec = 0;
static long slowpath_sec = 0;
#endif
static int slowpath_cancel = 0;

void bdw_before_gc_slowpath( void )
{
#if USE_HR_TIMER
  slowpath_timeval = gethrtime();
#else
  gettimeofday( &slowpath_timeval, 0 );
#endif
}

void bdw_after_gc_slowpath( void )
{
#if USE_HR_TIMER
  hrtime_t t;

  if (slowpath_cancel) { slowpath_cancel=0; return; }
  t = gethrtime();
  slowpath_nsec += (t - slowpath_timeval);
#else
  struct timeval t;
  long s, us;

  if (slowpath_cancel) { slowpath_cancel=0; return; }
  gettimeofday( &t, 0 );
  s = 0;
  us = t.tv_usec - slowpath_timeval.tv_usec;
  if (us < 0) {
    s--;
    us += 1000000;
  }
  s += t.tv_sec - slowpath_timeval.tv_sec;
  slowpath_usec += us;
  slowpath_sec += s;
#endif
}

/* Slow hooks to run before/after actual GC */

void bdw_before_gc( void )
{
#if BDW_DEBUG
  word *p, *lim;
  int n, s;

  if (!bdw_globals) return;

  /* Don't increment the count because it's a nonmoving collector! */
  /* globals[ G_GC_CNT ] += fixnum(1); */

  /* Stack sanity check */
  if (bdw_globals[G_ETOP] != bdw_globals[G_EBOT])
    panic( "Foo!  In-line allocation has taken place!  Aborting." );

# if BDW_CLEAR_STACK
  /* Clear out the unused portion of the stack cache.  Ideally,
   * it would be better to tell the collector to just ignore that
   * region.
   */
  memset( (void*)bdw_globals[G_ETOP], 
 	  0,
	  bdw_globals[G_STKP]-bdw_globals[G_ETOP] );

  /* Clear all the dynamic links and pad words, since they're garbage. */
  p = (word*)bdw_globals[ G_STKP ];
  lim = (word*)bdw_globals[ G_STKBOT ];
  while (p < lim) {
    p[2] = 0;			        /* Clear the dynamic link */
    s = (p[0] >> 2) + 1;
    n = roundup2( s );
    if (n != s) p[s] = 0;	        /* Clear the pad word */
    p += n;
  }

# endif
#endif
#if USE_HR_TIMER
  stats_add_gctime( (long)(slowpath_nsec / 1000000000),
		    (long)((slowpath_nsec / 1000000) % 1000) );
  slowpath_nsec = 0;
#else
  stats_add_gctime( slowpath_sec + slowpath_usec / 1000000, 
		    slowpath_usec / 1000 );
  slowpath_sec = 0;
  slowpath_usec = 0;
#endif
  slowpath_cancel = 1;
  stats_before_gc();
  stats_gc_type( 0, STATS_COLLECT );
}

/* Hook run after gc (if gc has been set up to do it). */

void bdw_after_gc( void )
{
#if BDW_DEBUG
  if (!bdw_globals) return;
#endif
  stats_after_gc();
}

void gclib_stats( word *wheap, word *wremset, word *wrts, word *wmax_heap )
{
  *wremset = *wrts = 0;
  *wheap = GC_get_heap_size() / sizeof( word );
  *wmax_heap = GC_get_max_heap_size() / sizeof( word );
}

static void no_op_warn()
{
  hardconsolemsg( "bdw-heap: call to unsupported operation." );
}

static int initialize( gc_t *gc )
{
#if BDW_DEBUG
  bdw_globals = DATA(gc)->globals;
#endif  
  return 1;
}

static void collect( gc_t *gc, int gen, int nbytes )
{
  GC_gcollect();
}

/* We can ignore no_gc because it's a non-moving collector */
static word *allocate( gc_t *gc, int nbytes, bool no_gc, bool atomic )
{
  void *p;

  /* This can be removed if the check remains on the slow path
     in bdw-gc/malloc.c. */
  if (nbytes > LARGEST_OBJECT) {
    panic( "\nSorry, an object of size %d bytes is too much for me; max is %d."
	   "\nSee you in 64-bit-land...\n",
	   nbytes, LARGEST_OBJECT );
  }
  if (atomic)
    p = GC_malloc_atomic( nbytes );
  else
    p = GC_malloc( nbytes );

  return (word*)p;
}

static word *allocate_nonmoving( gc_t *gc, int nbytes, bool atomic ) 
{
  return allocate( gc, nbytes, 0, atomic );
}

static word *data_load_area( gc_t *gc, int nbytes )
{
  /* The anchor allows the use of GC_malloc_ignore_off_page, which
   * is recommended by the authors (see bdw-gc/gc.h).
   */
  static void *anchor = 0;

  assert( anchor == 0 );
  anchor = GC_malloc_ignore_off_page( nbytes );

  return (word*)anchor;
}

static word *text_load_area( gc_t *gc, int nbytes )
{
  /* The anchor allows the use of GC_malloc_atomic_ignore_off_page, which
   * is recommended by the authors (see bdw-gc/gc.h).
   */
  static void *anchor = 0;

  assert( anchor == 0 );
  anchor = GC_malloc_atomic_ignore_off_page( nbytes );

  return (word*)anchor;
}

static int iflush( gc_t *gc, int generation )
{
  return (int)(DATA(gc)->globals[G_CACHE_FLUSH]);
}

static void stats( gc_t *gc, int generation, heap_stats_t *stats )
{
  bdw_data_t *data = DATA(gc);

  /* The following functions are available:
     GC_word GC_no_gc                 -- # of collections
     size_t GC_get_heap_size()        -- bytes; heap memory (not overhead)
     size_t GC_get_bytes_since_gc()
   */
  stats->live = stats->semispace1 = GC_get_heap_size();
  stats->frames_flushed = data->frames_flushed;
  stats->bytes_flushed = data->bytes_flushed;
  stats->stacks_created = data->stacks_created;
  stats->frames_restored = data->globals[ G_STKUFLOW ];

  data->frames_flushed = 0;
  data->bytes_flushed = 0;
  data->stacks_created = 0;
  data->globals[ G_STKUFLOW ] = 0;
}

static void stack_underflow( gc_t *gc )
{
  if (!stk_restore_frame( DATA(gc)->globals ))
    panic( "stack_underflow" );
}

static void stack_overflow( gc_t *gc )
{
  flush_stack( gc );
  stack_underflow( gc );
}

static word creg_get( gc_t *gc )
{
  word k;

  flush_stack( gc );
  k = DATA(gc)->globals[ G_CONT ];
  stack_underflow( gc );
  return k;
}

static void creg_set( gc_t *gc, word k )
{
  stk_clear( DATA(gc)->globals );
  DATA(gc)->globals[ G_CONT ] = k;
  stack_underflow( gc );
}

/* Internal */

static GC_PTR bdw_out_of_memory_handler( size_t bytes_requested )
{
  memfail( MF_HEAP, "Heap limit exceeded." );
  /* Not reached */
  return (GC_PTR)0;
}

static void init_stack( gc_t *gc )
{
  static void *anchor = 0;
  word *globals = DATA(gc)->globals;

  if (anchor == 0)
    anchor = GC_malloc_ignore_off_page( STACK_CACHE_SIZE );
  if (anchor == 0)
    panic( "init_stack" );

  globals[ G_EBOT ] = globals[ G_ETOP ] = (word)anchor;
  globals[ G_ELIM ] = (word)anchor + STACK_CACHE_SIZE - 8;
  globals[ G_STKP ] = globals[ G_ELIM ];
  globals[ G_STKUFLOW ] = 0;

  if (!stk_create( DATA(gc)->globals ))
    panic( "create_stack" );
  DATA(gc)->stacks_created++;
}

static void flush_stack( gc_t *gc )
{
  bdw_data_t *data = DATA(gc);
  unsigned frames, bytes;
  word k1, k2, first, new, last;

  /* Must flush in-place first, then walk the chain of frames and
   * copy each individually into the heap.  Can't just allocate a
   * single chunk (or we'd retain a lot of garbage, potentially).
   */
  k1 = data->globals[ G_CONT ];                /* already in heap */
  stk_flush( data->globals, &frames, &bytes );
  k2 = data->globals[ G_CONT ];                /* handle to first frame */

  if (k1 != k2) {
    first = last = 0;
    while (k2 != k1) {
      new = copy_object( gc, k2 );
      if (last != 0) {
	*(ptrof(last)+HC_DYNLINK) = new;
	last = new;
      }
      else
	first = last = new;
      k2 = *(ptrof(k2)+HC_DYNLINK);
    }
    *(ptrof(last)+HC_DYNLINK) = k1;
    data->globals[ G_CONT ] = first;

    data->frames_flushed += frames;
    data->bytes_flushed += bytes;
  }
  init_stack( gc );
}

static void clear_stack( gc_t *gc )
{
  stk_clear( DATA(gc)->globals );
}

static gc_t *allocate_area( word *globals )
{
  bdw_data_t *data;

  data = (bdw_data_t*)must_malloc( sizeof( bdw_data_t ) );

  data->globals = globals;
  data->frames_flushed = 0;
  data->bytes_flushed = 0;
  data->stacks_created = 0;

  return create_gc_t("bdw/variable", 
		     data,
		     initialize,
		     allocate,
		     allocate_nonmoving,
		     collect,
		     no_op_warn,     	     /* set_policy */
		     data_load_area,
		     text_load_area,
		     iflush,
		     creg_get,
		     creg_set,
		     stack_overflow,
		     stack_underflow,
		     stats,
		     (int (*)())no_op_warn,  /* compact_all_ssbs */
		     no_op_warn,             /* compact_np_ssb */
		     no_op_warn,             /* np_remset_ptrs */
		     0,                      /* load_heap */
		     0,                      /* dump_heap */
		     no_op_warn,             /* enumerate_roots */
		     no_op_warn              /* enumerate_remsets_older_than */
		     );
}

/* Support for SRO. */

void gclib_memory_range( caddr_t *lowest, caddr_t *highest )
{
  /* These are present at least in v4.12; see bdw-gc/gc_priv.h */
  extern caddr_t GC_least_plausible_heap_addr;
  extern caddr_t GC_greatest_plausible_heap_addr;

  *lowest = GC_least_plausible_heap_addr;
  *highest = GC_greatest_plausible_heap_addr;
}

void *gclib_alloc_rts( int nbytes, unsigned attr )
{
  return GC_malloc_atomic_uncollectable( nbytes );
}

void gclib_free( void *p, int nbytes )
{
  GC_free( p );
}

/* eof */
