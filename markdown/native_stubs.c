/* Feature-local ownership/budget adapter. No dependency on the OCaml binding's
 * private custom-block layout; the linked tree-sitter runtime is shared. */
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "tree_sitter/api.h"

extern const TSLanguage *tree_sitter_markdown(void);
extern const TSLanguage *tree_sitter_markdown_inline(void);

#define MAX_SOURCE (256 * 1024)
#define MAX_OPERATIONS 4096
#define MAX_RANGES 4097
#define MAX_NODES 65536
#define MAX_DEPTH 1024
#define MAX_INLINE_PARSES 4096
#define MAX_TOTAL_RANGES 8192
#define BUDGET_MICROS 100000

typedef struct {
  uint32_t role, start, stop;
} Capture;

typedef struct {
  Capture captures[MAX_OPERATIONS];
  TSRange ranges[MAX_RANGES];
  uint32_t capture_count, range_count, total_ranges, visited, inline_parses;
  uint32_t source_length;
  uint64_t deadline;
  const char *error;
} Work;

typedef struct {
  TSParser *block_parser, *inline_parser;
  TSTree *block_tree, *inline_tree;
  Work *work;
  intnat block_count, inline_count;
  bool closed;
} Session;

#define Session_val(v) ((Session *)Data_custom_val(v))

static void clear_work(Session *s) {
  if (s->inline_tree) ts_tree_delete(s->inline_tree);
  if (s->block_tree) ts_tree_delete(s->block_tree);
  s->inline_tree = s->block_tree = NULL;
  free(s->work);
  s->work = NULL;
}

static void close_session(Session *s) {
  clear_work(s);
  if (s->block_parser) ts_parser_delete(s->block_parser);
  if (s->inline_parser) ts_parser_delete(s->inline_parser);
  s->block_parser = s->inline_parser = NULL;
  s->closed = true;
}

static void finalize_session(value v) { close_session(Session_val(v)); }

static struct custom_operations session_ops = {
  .identifier = "cobalt.markdown.session.v1",
  .finalize = finalize_session,
  .compare = custom_compare_default,
  .hash = custom_hash_default,
  .serialize = custom_serialize_default,
  .deserialize = custom_deserialize_default,
  .compare_ext = custom_compare_ext_default,
  .fixed_length = custom_fixed_length_default,
};

static bool fail(Work *w, const char *message) {
  if (!w->error) w->error = message;
  return false;
}

static uint64_t micros(void) {
  struct timespec time;
  if (clock_gettime(CLOCK_MONOTONIC, &time) != 0) return 0;
  return (uint64_t)time.tv_sec * 1000000 + time.tv_nsec / 1000;
}

static bool within_deadline(Work *w) {
  uint64_t now = micros();
  return (now && now < w->deadline) || fail(w, "native parsing deadline exceeded");
}

static bool emit(Work *w, uint32_t role, uint32_t start, uint32_t stop) {
  if (start >= stop) return true;
  if (stop > w->source_length) return fail(w, "native range outside source");
  if (w->capture_count == MAX_OPERATIONS)
    return fail(w, "style operation limit exceeded");
  w->captures[w->capture_count++] = (Capture){role, start, stop};
  return true;
}

static bool emit_node(Work *w, uint32_t role, TSNode node) {
  return emit(w, role, ts_node_start_byte(node), ts_node_end_byte(node));
}

/* Inline nodes spanning multiple included ranges must not style the excluded
 * quote/list continuation prefixes in the gaps between those ranges. */
static bool emit_inline(Work *w, uint32_t role, TSNode node) {
  uint32_t start = ts_node_start_byte(node), stop = ts_node_end_byte(node);
  for (uint32_t i = 0; i < w->range_count; ++i) {
    TSRange range = w->ranges[i];
    if (range.start_byte >= stop) break;
    uint32_t a = start > range.start_byte ? start : range.start_byte;
    uint32_t b = stop < range.end_byte ? stop : range.end_byte;
    if (!emit(w, role, a, b)) return false;
  }
  return true;
}

static bool same(const char *a, const char *b) { return strcmp(a, b) == 0; }

static bool count_node(Work *w) {
  if (++w->visited > MAX_NODES) return fail(w, "syntax node limit exceeded");
  return within_deadline(w);
}

static bool advance(TSTreeCursor *cursor, bool descend) {
  if (descend && ts_tree_cursor_goto_first_child(cursor)) return true;
  do {
    if (ts_tree_cursor_goto_next_sibling(cursor)) return true;
  } while (ts_tree_cursor_goto_parent(cursor));
  return false;
}

static bool walk_inline(Session *s) {
  Work *w = s->work;
  TSTreeCursor cursor = ts_tree_cursor_new(ts_tree_root_node(s->inline_tree));
  bool more = true;
  while (more && !w->error) {
    TSNode node = ts_tree_cursor_current_node(&cursor);
    if (!count_node(w)) break;
    if (ts_tree_cursor_current_depth(&cursor) > MAX_DEPTH) {
      fail(w, "syntax depth limit exceeded");
      break;
    }
    const char *kind = ts_node_type(node);
    bool descend = !ts_node_is_error(node) && !ts_node_is_missing(node);
    uint32_t role = 0;
    if (descend) {
      if (same(kind, "emphasis")) role = 7;
      else if (same(kind, "strong_emphasis")) role = 8;
      else if (same(kind, "code_span")) { role = 9; descend = false; }
      else if (same(kind, "uri_autolink") || same(kind, "email_autolink"))
        role = 12;
      else if (same(kind, "link_text") || same(kind, "link_destination")) {
        TSNode parent = ts_node_parent(node);
        /* Do not invent resolution for shortcut/reference links, or treat
         * image syntax as a request for resources. Inline links are explicit. */
        if (!ts_node_is_null(parent) && same(ts_node_type(parent), "inline_link"))
          role = same(kind, "link_text") ? 11 : 12;
      } else if (same(kind, "html_tag")) {
        descend = false;
      }
    }
    if (role && !emit_inline(w, role, node)) break;
    more = advance(&cursor, descend);
  }
  ts_tree_cursor_delete(&cursor);
  return !w->error;
}

static bool add_range(Work *w, TSRange range) {
  if (range.start_byte >= range.end_byte) return true;
  if (range.end_byte > w->source_length)
    return fail(w, "included range outside source");
  if (w->range_count == MAX_RANGES)
    return fail(w, "included range limit exceeded");
  if (w->total_ranges == MAX_TOTAL_RANGES)
    return fail(w, "document included range limit exceeded");
  ++w->total_ranges;
  w->ranges[w->range_count++] = range;
  return true;
}

static TSRange node_range(TSNode node) {
  TSRange range = {
    .start_point = ts_node_start_point(node),
    .end_point = ts_node_end_point(node),
    .start_byte = ts_node_start_byte(node),
    .end_byte = ts_node_end_byte(node),
  };
  return range;
}

static bool parse_inline(Session *s, TSNode node, const char *source) {
  Work *w = s->work;
  w->range_count = 0;
  TSRange range = node_range(node);
  uint32_t children = ts_node_named_child_count(node);
  if (children > MAX_RANGES) return fail(w, "included range limit exceeded");
  for (uint32_t i = 0; i < children; ++i) {
    TSNode child = ts_node_named_child(node, i);
    if (!same(ts_node_type(child), "block_continuation")) continue;
    TSRange excluded = node_range(child);
    if (excluded.start_byte < range.start_byte ||
        excluded.end_byte > range.end_byte)
      return fail(w, "invalid block continuation range");
    TSRange before = range;
    before.end_byte = excluded.start_byte;
    before.end_point = excluded.start_point;
    if (!add_range(w, before)) return false;
    range.start_byte = excluded.end_byte;
    range.start_point = excluded.end_point;
  }
  if (!add_range(w, range)) return false;
  if (!w->range_count) return true;
  if (w->inline_parses == MAX_INLINE_PARSES)
    return fail(w, "inline parse limit exceeded");
  if (!within_deadline(w)) return false;
  ts_parser_reset(s->inline_parser);
  if (!ts_parser_set_included_ranges(s->inline_parser, w->ranges, w->range_count))
    return fail(w, "invalid included ranges");
  uint64_t now = micros();
  if (!now || now >= w->deadline)
    return fail(w, "native parsing deadline exceeded");
  ts_parser_set_timeout_micros(s->inline_parser, w->deadline - now);
  ++w->inline_parses;
  if (s->inline_count < Max_long) ++s->inline_count;
  s->inline_tree = ts_parser_parse_string(
    s->inline_parser, NULL, source, w->source_length);
  if (!s->inline_tree) return fail(w, "inline parse timed out or failed");
  bool success = walk_inline(s);
  ts_tree_delete(s->inline_tree);
  s->inline_tree = NULL;
  return success;
}

static uint32_t heading_role(TSNode node) {
  uint32_t children = ts_node_named_child_count(node);
  for (uint32_t i = 0; i < children; ++i) {
    const char *kind = ts_node_type(ts_node_named_child(node, i));
    if (same(kind, "atx_h1_marker") || same(kind, "setext_h1_underline")) return 1;
    if (same(kind, "atx_h2_marker") || same(kind, "setext_h2_underline")) return 2;
    if (same(kind, "atx_h3_marker")) return 3;
    if (same(kind, "atx_h4_marker")) return 4;
    if (same(kind, "atx_h5_marker")) return 5;
    if (same(kind, "atx_h6_marker")) return 6;
  }
  return 0;
}

static bool walk_blocks(Session *s, const char *source) {
  Work *w = s->work;
  TSTreeCursor cursor = ts_tree_cursor_new(ts_tree_root_node(s->block_tree));
  bool more = true;
  while (more && !w->error) {
    TSNode node = ts_tree_cursor_current_node(&cursor);
    if (!count_node(w)) break;
    if (ts_tree_cursor_current_depth(&cursor) > MAX_DEPTH) {
      fail(w, "syntax depth limit exceeded");
      break;
    }
    const char *kind = ts_node_type(node);
    bool descend = !ts_node_is_error(node) && !ts_node_is_missing(node);
    uint32_t role = 0;
    if (descend) {
      if (same(kind, "atx_heading") || same(kind, "setext_heading"))
        role = heading_role(node);
      else if (same(kind, "fenced_code_block") || same(kind, "indented_code_block")) {
        role = 10;
        descend = false;
      } else if (same(kind, "block_quote")) role = 13;
      else if (same(kind, "list_marker_minus") || same(kind, "list_marker_plus") ||
               same(kind, "list_marker_star") || same(kind, "list_marker_dot") ||
               same(kind, "list_marker_parenthesis")) role = 14;
      else if (same(kind, "task_list_marker_checked") ||
               same(kind, "task_list_marker_unchecked")) role = 15;
      else if (same(kind, "link_destination")) role = 12;
      else if (same(kind, "html_block")) descend = false;
      else if (same(kind, "inline") || same(kind, "pipe_table_cell")) {
        if (!parse_inline(s, node, source)) break;
        descend = false;
      }
    }
    if (role && !emit_node(w, role, node)) break;
    more = advance(&cursor, descend);
  }
  ts_tree_cursor_delete(&cursor);
  return !w->error;
}

CAMLprim value cobalt_markdown_native_create(value unit) {
  CAMLparam1(unit);
  CAMLlocal1(v);
  v = caml_alloc_custom(&session_ops, sizeof(Session), 0, 1);
  memset(Session_val(v), 0, sizeof(Session));
  CAMLreturn(v);
}

CAMLprim value cobalt_markdown_native_close(value v) {
  CAMLparam1(v);
  close_session(Session_val(v));
  CAMLreturn(Val_unit);
}

CAMLprim value cobalt_markdown_native_counts(value v) {
  CAMLparam1(v);
  CAMLlocal1(pair);
  intnat block_count = Session_val(v)->block_count;
  intnat inline_count = Session_val(v)->inline_count;
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, Val_long(block_count));
  Store_field(pair, 1, Val_long(inline_count));
  CAMLreturn(pair);
}

CAMLprim value cobalt_markdown_native_parse(value v, value source) {
  CAMLparam2(v, source);
  CAMLlocal2(result, capture);
  Session *s = Session_val(v);
  if (s->closed) caml_invalid_argument("Markdown native session is closed");
  if (caml_string_length(source) > MAX_SOURCE)
    caml_invalid_argument("Markdown source byte limit exceeded");
  /* Clear any work abandoned by an OCaml allocation exception on a prior call. */
  clear_work(s);
  if (!s->block_parser) s->block_parser = ts_parser_new();
  if (!s->inline_parser) s->inline_parser = ts_parser_new();
  if (!s->block_parser || !s->inline_parser) caml_raise_out_of_memory();
  if (!ts_parser_set_language(s->block_parser, tree_sitter_markdown()) ||
      !ts_parser_set_language(s->inline_parser, tree_sitter_markdown_inline()))
    caml_failwith("Markdown grammar/runtime ABI mismatch");
  s->work = calloc(1, sizeof(Work));
  if (!s->work) caml_raise_out_of_memory();
  Work *w = s->work;
  uint64_t start = micros();
  if (!start) {
    clear_work(s);
    caml_failwith("Markdown monotonic clock unavailable");
  }
  w->deadline = start + BUDGET_MICROS;
  w->source_length = (uint32_t)caml_string_length(source);
  ts_parser_reset(s->block_parser);
  ts_parser_set_included_ranges(s->block_parser, NULL, 0);
  ts_parser_set_timeout_micros(s->block_parser, BUDGET_MICROS);
  if (s->block_count < Max_long) ++s->block_count;
  s->block_tree = ts_parser_parse_string(
    s->block_parser, NULL, String_val(source), w->source_length);
  if (!s->block_tree) fail(w, "block parse timed out or failed");
  else walk_blocks(s, String_val(source));
  if (!w->error) within_deadline(w);
  if (w->error) {
    const char *message = w->error; /* All error strings have static lifetime. */
    ts_parser_reset(s->block_parser);
    ts_parser_reset(s->inline_parser);
    clear_work(s);
    caml_failwith(message);
  }
  /* Allocate only after releasing native trees. Work remains owned by the
   * session until the OCaml result is complete, including on allocation failure. */
  ts_tree_delete(s->block_tree);
  s->block_tree = NULL;
  result = caml_alloc(w->capture_count, 0);
  for (uint32_t i = 0; i < w->capture_count; ++i) {
    Capture c = w->captures[i];
    capture = caml_alloc_tuple(3);
    Store_field(capture, 0, Val_long(c.role));
    Store_field(capture, 1, Val_long(c.start));
    Store_field(capture, 2, Val_long(c.stop));
    Store_field(result, i, capture);
  }
  clear_work(Session_val(v));
  CAMLreturn(result);
}
