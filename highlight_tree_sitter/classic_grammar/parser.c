#include <tree_sitter/parser.h>

#if defined(__GNUC__) || defined(__clang__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#endif

#define LANGUAGE_VERSION 14
#define STATE_COUNT 20
#define LARGE_STATE_COUNT 12
#define SYMBOL_COUNT 69
#define ALIAS_COUNT 1
#define TOKEN_COUNT 60
#define EXTERNAL_TOKEN_COUNT 0
#define FIELD_COUNT 0
#define MAX_ALIAS_SEQUENCE_LENGTH 3
#define PRODUCTION_ID_COUNT 2

enum {
  sym_identifier = 1,
  anon_sym_package = 2,
  anon_sym_import = 3,
  anon_sym_qualified = 4,
  anon_sym_action = 5,
  anon_sym_case = 6,
  anon_sym_class = 7,
  anon_sym_data = 8,
  anon_sym_deriving = 9,
  anon_sym_do = 10,
  anon_sym_else = 11,
  anon_sym_foreign = 12,
  anon_sym_if = 13,
  anon_sym_in = 14,
  anon_sym_coherent = 15,
  anon_sym_incoherent = 16,
  anon_sym_infix = 17,
  anon_sym_infixl = 18,
  anon_sym_infixr = 19,
  anon_sym_interface = 20,
  anon_sym_instance = 21,
  anon_sym_let = 22,
  anon_sym_letseq = 23,
  anon_sym_of = 24,
  anon_sym_primitive = 25,
  anon_sym_rules = 26,
  anon_sym_signature = 27,
  anon_sym_struct = 28,
  anon_sym_module = 29,
  anon_sym_then = 30,
  anon_sym_type = 31,
  anon_sym_valueOf = 32,
  anon_sym_stringOf = 33,
  anon_sym_verilog = 34,
  anon_sym_synthesize = 35,
  anon_sym_when = 36,
  anon_sym_where = 37,
  sym_capitalized = 38,
  sym_system_task = 39,
  sym_signature_op = 40,
  sym_operator = 41,
  sym_punctuation = 42,
  anon_sym_LBRACE_DASH_POUND = 43,
  anon_sym_POUND_DASH_RBRACE = 44,
  aux_sym_number_token1 = 45,
  aux_sym_number_token2 = 46,
  aux_sym_number_token3 = 47,
  aux_sym_number_token4 = 48,
  aux_sym_number_token5 = 49,
  aux_sym_number_token6 = 50,
  sym_string = 51,
  sym_character = 52,
  sym_line_comment = 53,
  anon_sym_LBRACE_DASH = 54,
  aux_sym_block_comment_token1 = 55,
  anon_sym_LBRACE = 56,
  anon_sym_RBRACE = 57,
  anon_sym_DASH = 58,
  anon_sym_DASH_RBRACE = 59,
  sym_source_file = 60,
  sym_package_ref = 61,
  sym_package_keyword = 62,
  sym_keyword = 63,
  sym_pragma_delimiter = 64,
  sym_number = 65,
  sym_block_comment = 66,
  aux_sym_source_file_repeat1 = 67,
  aux_sym_block_comment_repeat1 = 68,
  alias_sym_package_name = 69,
};

static const char * const ts_symbol_names[] = {
  [ts_builtin_sym_end] = "end",
  [sym_identifier] = "identifier",
  [anon_sym_package] = "package",
  [anon_sym_import] = "import",
  [anon_sym_qualified] = "qualified",
  [anon_sym_action] = "action",
  [anon_sym_case] = "case",
  [anon_sym_class] = "class",
  [anon_sym_data] = "data",
  [anon_sym_deriving] = "deriving",
  [anon_sym_do] = "do",
  [anon_sym_else] = "else",
  [anon_sym_foreign] = "foreign",
  [anon_sym_if] = "if",
  [anon_sym_in] = "in",
  [anon_sym_coherent] = "coherent",
  [anon_sym_incoherent] = "incoherent",
  [anon_sym_infix] = "infix",
  [anon_sym_infixl] = "infixl",
  [anon_sym_infixr] = "infixr",
  [anon_sym_interface] = "interface",
  [anon_sym_instance] = "instance",
  [anon_sym_let] = "let",
  [anon_sym_letseq] = "letseq",
  [anon_sym_of] = "of",
  [anon_sym_primitive] = "primitive",
  [anon_sym_rules] = "rules",
  [anon_sym_signature] = "signature",
  [anon_sym_struct] = "struct",
  [anon_sym_module] = "module",
  [anon_sym_then] = "then",
  [anon_sym_type] = "type",
  [anon_sym_valueOf] = "valueOf",
  [anon_sym_stringOf] = "stringOf",
  [anon_sym_verilog] = "verilog",
  [anon_sym_synthesize] = "synthesize",
  [anon_sym_when] = "when",
  [anon_sym_where] = "where",
  [sym_capitalized] = "capitalized",
  [sym_system_task] = "system_task",
  [sym_signature_op] = "signature_op",
  [sym_operator] = "operator",
  [sym_punctuation] = "punctuation",
  [anon_sym_LBRACE_DASH_POUND] = "{-#",
  [anon_sym_POUND_DASH_RBRACE] = "#-}",
  [aux_sym_number_token1] = "number_token1",
  [aux_sym_number_token2] = "number_token2",
  [aux_sym_number_token3] = "number_token3",
  [aux_sym_number_token4] = "number_token4",
  [aux_sym_number_token5] = "number_token5",
  [aux_sym_number_token6] = "number_token6",
  [sym_string] = "string",
  [sym_character] = "character",
  [sym_line_comment] = "line_comment",
  [anon_sym_LBRACE_DASH] = "{-",
  [aux_sym_block_comment_token1] = "block_comment_token1",
  [anon_sym_LBRACE] = "{",
  [anon_sym_RBRACE] = "}",
  [anon_sym_DASH] = "-",
  [anon_sym_DASH_RBRACE] = "-}",
  [sym_source_file] = "source_file",
  [sym_package_ref] = "package_ref",
  [sym_package_keyword] = "package_keyword",
  [sym_keyword] = "keyword",
  [sym_pragma_delimiter] = "pragma_delimiter",
  [sym_number] = "number",
  [sym_block_comment] = "block_comment",
  [aux_sym_source_file_repeat1] = "source_file_repeat1",
  [aux_sym_block_comment_repeat1] = "block_comment_repeat1",
  [alias_sym_package_name] = "package_name",
};

static const TSSymbol ts_symbol_map[] = {
  [ts_builtin_sym_end] = ts_builtin_sym_end,
  [sym_identifier] = sym_identifier,
  [anon_sym_package] = anon_sym_package,
  [anon_sym_import] = anon_sym_import,
  [anon_sym_qualified] = anon_sym_qualified,
  [anon_sym_action] = anon_sym_action,
  [anon_sym_case] = anon_sym_case,
  [anon_sym_class] = anon_sym_class,
  [anon_sym_data] = anon_sym_data,
  [anon_sym_deriving] = anon_sym_deriving,
  [anon_sym_do] = anon_sym_do,
  [anon_sym_else] = anon_sym_else,
  [anon_sym_foreign] = anon_sym_foreign,
  [anon_sym_if] = anon_sym_if,
  [anon_sym_in] = anon_sym_in,
  [anon_sym_coherent] = anon_sym_coherent,
  [anon_sym_incoherent] = anon_sym_incoherent,
  [anon_sym_infix] = anon_sym_infix,
  [anon_sym_infixl] = anon_sym_infixl,
  [anon_sym_infixr] = anon_sym_infixr,
  [anon_sym_interface] = anon_sym_interface,
  [anon_sym_instance] = anon_sym_instance,
  [anon_sym_let] = anon_sym_let,
  [anon_sym_letseq] = anon_sym_letseq,
  [anon_sym_of] = anon_sym_of,
  [anon_sym_primitive] = anon_sym_primitive,
  [anon_sym_rules] = anon_sym_rules,
  [anon_sym_signature] = anon_sym_signature,
  [anon_sym_struct] = anon_sym_struct,
  [anon_sym_module] = anon_sym_module,
  [anon_sym_then] = anon_sym_then,
  [anon_sym_type] = anon_sym_type,
  [anon_sym_valueOf] = anon_sym_valueOf,
  [anon_sym_stringOf] = anon_sym_stringOf,
  [anon_sym_verilog] = anon_sym_verilog,
  [anon_sym_synthesize] = anon_sym_synthesize,
  [anon_sym_when] = anon_sym_when,
  [anon_sym_where] = anon_sym_where,
  [sym_capitalized] = sym_capitalized,
  [sym_system_task] = sym_system_task,
  [sym_signature_op] = sym_signature_op,
  [sym_operator] = sym_operator,
  [sym_punctuation] = sym_punctuation,
  [anon_sym_LBRACE_DASH_POUND] = anon_sym_LBRACE_DASH_POUND,
  [anon_sym_POUND_DASH_RBRACE] = anon_sym_POUND_DASH_RBRACE,
  [aux_sym_number_token1] = aux_sym_number_token1,
  [aux_sym_number_token2] = aux_sym_number_token2,
  [aux_sym_number_token3] = aux_sym_number_token3,
  [aux_sym_number_token4] = aux_sym_number_token4,
  [aux_sym_number_token5] = aux_sym_number_token5,
  [aux_sym_number_token6] = aux_sym_number_token6,
  [sym_string] = sym_string,
  [sym_character] = sym_character,
  [sym_line_comment] = sym_line_comment,
  [anon_sym_LBRACE_DASH] = anon_sym_LBRACE_DASH,
  [aux_sym_block_comment_token1] = aux_sym_block_comment_token1,
  [anon_sym_LBRACE] = anon_sym_LBRACE,
  [anon_sym_RBRACE] = anon_sym_RBRACE,
  [anon_sym_DASH] = anon_sym_DASH,
  [anon_sym_DASH_RBRACE] = anon_sym_DASH_RBRACE,
  [sym_source_file] = sym_source_file,
  [sym_package_ref] = sym_package_ref,
  [sym_package_keyword] = sym_package_keyword,
  [sym_keyword] = sym_keyword,
  [sym_pragma_delimiter] = sym_pragma_delimiter,
  [sym_number] = sym_number,
  [sym_block_comment] = sym_block_comment,
  [aux_sym_source_file_repeat1] = aux_sym_source_file_repeat1,
  [aux_sym_block_comment_repeat1] = aux_sym_block_comment_repeat1,
  [alias_sym_package_name] = alias_sym_package_name,
};

static const TSSymbolMetadata ts_symbol_metadata[] = {
  [ts_builtin_sym_end] = {
    .visible = false,
    .named = true,
  },
  [sym_identifier] = {
    .visible = true,
    .named = true,
  },
  [anon_sym_package] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_import] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_qualified] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_action] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_case] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_class] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_data] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_deriving] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_do] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_else] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_foreign] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_if] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_in] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_coherent] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_incoherent] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_infix] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_infixl] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_infixr] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_interface] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_instance] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_let] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_letseq] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_of] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_primitive] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_rules] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_signature] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_struct] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_module] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_then] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_type] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_valueOf] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_stringOf] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_verilog] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_synthesize] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_when] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_where] = {
    .visible = true,
    .named = false,
  },
  [sym_capitalized] = {
    .visible = true,
    .named = true,
  },
  [sym_system_task] = {
    .visible = true,
    .named = true,
  },
  [sym_signature_op] = {
    .visible = true,
    .named = true,
  },
  [sym_operator] = {
    .visible = true,
    .named = true,
  },
  [sym_punctuation] = {
    .visible = true,
    .named = true,
  },
  [anon_sym_LBRACE_DASH_POUND] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_POUND_DASH_RBRACE] = {
    .visible = true,
    .named = false,
  },
  [aux_sym_number_token1] = {
    .visible = false,
    .named = false,
  },
  [aux_sym_number_token2] = {
    .visible = false,
    .named = false,
  },
  [aux_sym_number_token3] = {
    .visible = false,
    .named = false,
  },
  [aux_sym_number_token4] = {
    .visible = false,
    .named = false,
  },
  [aux_sym_number_token5] = {
    .visible = false,
    .named = false,
  },
  [aux_sym_number_token6] = {
    .visible = false,
    .named = false,
  },
  [sym_string] = {
    .visible = true,
    .named = true,
  },
  [sym_character] = {
    .visible = true,
    .named = true,
  },
  [sym_line_comment] = {
    .visible = true,
    .named = true,
  },
  [anon_sym_LBRACE_DASH] = {
    .visible = true,
    .named = false,
  },
  [aux_sym_block_comment_token1] = {
    .visible = false,
    .named = false,
  },
  [anon_sym_LBRACE] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_RBRACE] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_DASH] = {
    .visible = true,
    .named = false,
  },
  [anon_sym_DASH_RBRACE] = {
    .visible = true,
    .named = false,
  },
  [sym_source_file] = {
    .visible = true,
    .named = true,
  },
  [sym_package_ref] = {
    .visible = true,
    .named = true,
  },
  [sym_package_keyword] = {
    .visible = true,
    .named = true,
  },
  [sym_keyword] = {
    .visible = true,
    .named = true,
  },
  [sym_pragma_delimiter] = {
    .visible = true,
    .named = true,
  },
  [sym_number] = {
    .visible = true,
    .named = true,
  },
  [sym_block_comment] = {
    .visible = true,
    .named = true,
  },
  [aux_sym_source_file_repeat1] = {
    .visible = false,
    .named = false,
  },
  [aux_sym_block_comment_repeat1] = {
    .visible = false,
    .named = false,
  },
  [alias_sym_package_name] = {
    .visible = true,
    .named = true,
  },
};

static const TSSymbol ts_alias_sequences[PRODUCTION_ID_COUNT][MAX_ALIAS_SEQUENCE_LENGTH] = {
  [0] = {0},
  [1] = {
    [1] = alias_sym_package_name,
  },
};

static const uint16_t ts_non_terminal_alias_map[] = {
  0,
};

static const TSStateId ts_primary_state_ids[STATE_COUNT] = {
  [0] = 0,
  [1] = 1,
  [2] = 2,
  [3] = 3,
  [4] = 4,
  [5] = 5,
  [6] = 6,
  [7] = 7,
  [8] = 8,
  [9] = 9,
  [10] = 10,
  [11] = 11,
  [12] = 12,
  [13] = 13,
  [14] = 14,
  [15] = 12,
  [16] = 13,
  [17] = 9,
  [18] = 11,
  [19] = 19,
};

static inline bool sym_operator_character_set_1(int32_t c) {
  return (c < 9084
    ? (c < 8512
      ? (c < 1542
        ? (c < 215
          ? (c < 172
            ? (c >= '!' && c <= '~')
            : (c <= 172 || c == 177))
          : (c <= 215 || (c < 1014
            ? c == 247
            : c <= 1014)))
        : (c <= 1544 || (c < 8314
          ? (c < 8274
            ? c == 8260
            : c <= 8274)
          : (c <= 8316 || (c < 8472
            ? (c >= 8330 && c <= 8332)
            : c <= 8472)))))
      : (c <= 8516 || (c < 8622
        ? (c < 8608
          ? (c < 8592
            ? c == 8523
            : (c <= 8596 || (c >= 8602 && c <= 8603)))
          : (c <= 8608 || (c < 8614
            ? c == 8611
            : c <= 8614)))
        : (c <= 8622 || (c < 8660
          ? (c < 8658
            ? (c >= 8654 && c <= 8655)
            : c <= 8658)
          : (c <= 8660 || (c < 8992
            ? (c >= 8692 && c <= 8959)
            : c <= 8993)))))))
    : (c <= 9084 || (c < 10750
      ? (c < 10176
        ? (c < 9665
          ? (c < 9180
            ? (c >= 9115 && c <= 9139)
            : (c <= 9185 || c == 9655))
          : (c <= 9665 || (c < 9839
            ? (c >= 9720 && c <= 9727)
            : c <= 9839)))
        : (c <= 10180 || (c < 10496
          ? (c < 10224
            ? (c >= 10183 && c <= 10213)
            : c <= 10239)
          : (c <= 10626 || (c < 10716
            ? (c >= 10649 && c <= 10711)
            : c <= 10747)))))
      : (c <= 11007 || (c < 65291
        ? (c < 64297
          ? (c < 11079
            ? (c >= 11056 && c <= 11076)
            : c <= 11084)
          : (c <= 64297 || (c < 65124
            ? c == 65122
            : c <= 65126)))
        : (c <= 65291 || (c < 65374
          ? (c < 65372
            ? (c >= 65308 && c <= 65310)
            : c <= 65372)
          : (c <= 65374 || (c < 65513
            ? c == 65506
            : c <= 65516)))))))));
}

static inline bool sym_operator_character_set_2(int32_t c) {
  return (c < 8654
    ? (c < 1014
      ? (c < '^'
        ? (c < '-'
          ? (c < '#'
            ? c == '!'
            : (c <= '&' || (c >= '*' && c <= '+')))
          : (c <= '/' || (c < '<'
            ? c == ':'
            : (c <= '@' || c == '\\'))))
        : (c <= '^' || (c < 177
          ? (c < '~'
            ? c == '|'
            : (c <= '~' || c == 172))
          : (c <= 177 || (c < 247
            ? c == 215
            : c <= 247)))))
      : (c <= 1014 || (c < 8523
        ? (c < 8314
          ? (c < 8260
            ? (c >= 1542 && c <= 1544)
            : (c <= 8260 || c == 8274))
          : (c <= 8316 || (c < 8472
            ? (c >= 8330 && c <= 8332)
            : (c <= 8472 || (c >= 8512 && c <= 8516)))))
        : (c <= 8523 || (c < 8611
          ? (c < 8602
            ? (c >= 8592 && c <= 8596)
            : (c <= 8603 || c == 8608))
          : (c <= 8611 || (c < 8622
            ? c == 8614
            : c <= 8622)))))))
    : (c <= 8655 || (c < 10496
      ? (c < 9655
        ? (c < 8992
          ? (c < 8660
            ? c == 8658
            : (c <= 8660 || (c >= 8692 && c <= 8959)))
          : (c <= 8993 || (c < 9115
            ? c == 9084
            : (c <= 9139 || (c >= 9180 && c <= 9185)))))
        : (c <= 9655 || (c < 10176
          ? (c < 9720
            ? c == 9665
            : (c <= 9727 || c == 9839))
          : (c <= 10180 || (c < 10224
            ? (c >= 10183 && c <= 10213)
            : c <= 10239)))))
      : (c <= 10626 || (c < 65124
        ? (c < 11056
          ? (c < 10716
            ? (c >= 10649 && c <= 10711)
            : (c <= 10747 || (c >= 10750 && c <= 11007)))
          : (c <= 11076 || (c < 64297
            ? (c >= 11079 && c <= 11084)
            : (c <= 64297 || c == 65122))))
        : (c <= 65126 || (c < 65374
          ? (c < 65308
            ? c == 65291
            : (c <= 65310 || c == 65372))
          : (c <= 65374 || (c < 65513
            ? c == 65506
            : c <= 65516)))))))));
}

static inline bool sym_operator_character_set_3(int32_t c) {
  return (c < 8654
    ? (c < 1014
      ? (c < '^'
        ? (c < '.'
          ? (c < '#'
            ? c == '!'
            : (c <= '&' || (c >= '*' && c <= '+')))
          : (c <= '/' || (c < '<'
            ? c == ':'
            : (c <= '@' || c == '\\'))))
        : (c <= '^' || (c < 177
          ? (c < '~'
            ? c == '|'
            : (c <= '~' || c == 172))
          : (c <= 177 || (c < 247
            ? c == 215
            : c <= 247)))))
      : (c <= 1014 || (c < 8523
        ? (c < 8314
          ? (c < 8260
            ? (c >= 1542 && c <= 1544)
            : (c <= 8260 || c == 8274))
          : (c <= 8316 || (c < 8472
            ? (c >= 8330 && c <= 8332)
            : (c <= 8472 || (c >= 8512 && c <= 8516)))))
        : (c <= 8523 || (c < 8611
          ? (c < 8602
            ? (c >= 8592 && c <= 8596)
            : (c <= 8603 || c == 8608))
          : (c <= 8611 || (c < 8622
            ? c == 8614
            : c <= 8622)))))))
    : (c <= 8655 || (c < 10496
      ? (c < 9655
        ? (c < 8992
          ? (c < 8660
            ? c == 8658
            : (c <= 8660 || (c >= 8692 && c <= 8959)))
          : (c <= 8993 || (c < 9115
            ? c == 9084
            : (c <= 9139 || (c >= 9180 && c <= 9185)))))
        : (c <= 9655 || (c < 10176
          ? (c < 9720
            ? c == 9665
            : (c <= 9727 || c == 9839))
          : (c <= 10180 || (c < 10224
            ? (c >= 10183 && c <= 10213)
            : c <= 10239)))))
      : (c <= 10626 || (c < 65124
        ? (c < 11056
          ? (c < 10716
            ? (c >= 10649 && c <= 10711)
            : (c <= 10747 || (c >= 10750 && c <= 11007)))
          : (c <= 11076 || (c < 64297
            ? (c >= 11079 && c <= 11084)
            : (c <= 64297 || c == 65122))))
        : (c <= 65126 || (c < 65374
          ? (c < 65308
            ? c == 65291
            : (c <= 65310 || c == 65372))
          : (c <= 65374 || (c < 65513
            ? c == 65506
            : c <= 65516)))))))));
}

static inline bool sym_operator_character_set_4(int32_t c) {
  return (c < '<'
    ? (c < '*'
      ? (c < '#'
        ? c == '!'
        : c <= '&')
      : (c <= '+' || (c < ':'
        ? (c >= '.' && c <= '/')
        : c <= ':')))
    : (c <= '?' || (c < '|'
      ? (c < '^'
        ? c == '\\'
        : c <= '^')
      : (c <= '|' || c == '~'))));
}

static inline bool sym_operator_character_set_5(int32_t c) {
  return (c < 9084
    ? (c < 8523
      ? (c < 8260
        ? (c < 247
          ? (c < 177
            ? c == 172
            : (c <= 177 || c == 215))
          : (c <= 247 || (c < 1542
            ? c == 1014
            : c <= 1544)))
        : (c <= 8260 || (c < 8330
          ? (c < 8314
            ? c == 8274
            : c <= 8316)
          : (c <= 8332 || (c < 8512
            ? c == 8472
            : c <= 8516)))))
      : (c <= 8523 || (c < 8622
        ? (c < 8608
          ? (c < 8602
            ? (c >= 8592 && c <= 8596)
            : c <= 8603)
          : (c <= 8608 || (c < 8614
            ? c == 8611
            : c <= 8614)))
        : (c <= 8622 || (c < 8660
          ? (c < 8658
            ? (c >= 8654 && c <= 8655)
            : c <= 8658)
          : (c <= 8660 || (c < 8992
            ? (c >= 8692 && c <= 8959)
            : c <= 8993)))))))
    : (c <= 9084 || (c < 10750
      ? (c < 10176
        ? (c < 9665
          ? (c < 9180
            ? (c >= 9115 && c <= 9139)
            : (c <= 9185 || c == 9655))
          : (c <= 9665 || (c < 9839
            ? (c >= 9720 && c <= 9727)
            : c <= 9839)))
        : (c <= 10180 || (c < 10496
          ? (c < 10224
            ? (c >= 10183 && c <= 10213)
            : c <= 10239)
          : (c <= 10626 || (c < 10716
            ? (c >= 10649 && c <= 10711)
            : c <= 10747)))))
      : (c <= 11007 || (c < 65291
        ? (c < 64297
          ? (c < 11079
            ? (c >= 11056 && c <= 11076)
            : c <= 11084)
          : (c <= 64297 || (c < 65124
            ? c == 65122
            : c <= 65126)))
        : (c <= 65291 || (c < 65374
          ? (c < 65372
            ? (c >= 65308 && c <= 65310)
            : c <= 65372)
          : (c <= 65374 || (c < 65513
            ? c == 65506
            : c <= 65516)))))))));
}

static inline bool sym_operator_character_set_6(int32_t c) {
  return (c < 8658
    ? (c < 1542
      ? (c < '|'
        ? (c < '-'
          ? (c < '#'
            ? c == '!'
            : (c <= '&' || (c >= '*' && c <= '+')))
          : (c <= '/' || (c < '\\'
            ? (c >= '<' && c <= '@')
            : (c <= '\\' || c == '^'))))
        : (c <= '|' || (c < 215
          ? (c < 172
            ? c == '~'
            : (c <= 172 || c == 177))
          : (c <= 215 || (c < 1014
            ? c == 247
            : c <= 1014)))))
      : (c <= 1544 || (c < 8592
        ? (c < 8330
          ? (c < 8274
            ? c == 8260
            : (c <= 8274 || (c >= 8314 && c <= 8316)))
          : (c <= 8332 || (c < 8512
            ? c == 8472
            : (c <= 8516 || c == 8523))))
        : (c <= 8596 || (c < 8614
          ? (c < 8608
            ? (c >= 8602 && c <= 8603)
            : (c <= 8608 || c == 8611))
          : (c <= 8614 || (c < 8654
            ? c == 8622
            : c <= 8655)))))))
    : (c <= 8658 || (c < 10649
      ? (c < 9665
        ? (c < 9084
          ? (c < 8692
            ? c == 8660
            : (c <= 8959 || (c >= 8992 && c <= 8993)))
          : (c <= 9084 || (c < 9180
            ? (c >= 9115 && c <= 9139)
            : (c <= 9185 || c == 9655))))
        : (c <= 9665 || (c < 10183
          ? (c < 9839
            ? (c >= 9720 && c <= 9727)
            : (c <= 9839 || (c >= 10176 && c <= 10180)))
          : (c <= 10213 || (c < 10496
            ? (c >= 10224 && c <= 10239)
            : c <= 10626)))))
      : (c <= 10711 || (c < 65124
        ? (c < 11079
          ? (c < 10750
            ? (c >= 10716 && c <= 10747)
            : (c <= 11007 || (c >= 11056 && c <= 11076)))
          : (c <= 11084 || (c < 65122
            ? c == 64297
            : c <= 65122)))
        : (c <= 65126 || (c < 65374
          ? (c < 65308
            ? c == 65291
            : (c <= 65310 || c == 65372))
          : (c <= 65374 || (c < 65513
            ? c == 65506
            : c <= 65516)))))))));
}

static inline bool sym_operator_character_set_7(int32_t c) {
  return (c < 8658
    ? (c < 1542
      ? (c < '^'
        ? (c < '-'
          ? (c < '#'
            ? c == '!'
            : (c <= '&' || (c >= '*' && c <= '+')))
          : (c <= '/' || (c < '<'
            ? c == ':'
            : (c <= '@' || c == '\\'))))
        : (c <= '^' || (c < 215
          ? (c < 172
            ? (c >= '|' && c <= '~')
            : (c <= 172 || c == 177))
          : (c <= 215 || (c < 1014
            ? c == 247
            : c <= 1014)))))
      : (c <= 1544 || (c < 8592
        ? (c < 8330
          ? (c < 8274
            ? c == 8260
            : (c <= 8274 || (c >= 8314 && c <= 8316)))
          : (c <= 8332 || (c < 8512
            ? c == 8472
            : (c <= 8516 || c == 8523))))
        : (c <= 8596 || (c < 8614
          ? (c < 8608
            ? (c >= 8602 && c <= 8603)
            : (c <= 8608 || c == 8611))
          : (c <= 8614 || (c < 8654
            ? c == 8622
            : c <= 8655)))))))
    : (c <= 8658 || (c < 10649
      ? (c < 9665
        ? (c < 9084
          ? (c < 8692
            ? c == 8660
            : (c <= 8959 || (c >= 8992 && c <= 8993)))
          : (c <= 9084 || (c < 9180
            ? (c >= 9115 && c <= 9139)
            : (c <= 9185 || c == 9655))))
        : (c <= 9665 || (c < 10183
          ? (c < 9839
            ? (c >= 9720 && c <= 9727)
            : (c <= 9839 || (c >= 10176 && c <= 10180)))
          : (c <= 10213 || (c < 10496
            ? (c >= 10224 && c <= 10239)
            : c <= 10626)))))
      : (c <= 10711 || (c < 65124
        ? (c < 11079
          ? (c < 10750
            ? (c >= 10716 && c <= 10747)
            : (c <= 11007 || (c >= 11056 && c <= 11076)))
          : (c <= 11084 || (c < 65122
            ? c == 64297
            : c <= 65122)))
        : (c <= 65126 || (c < 65374
          ? (c < 65308
            ? c == 65291
            : (c <= 65310 || c == 65372))
          : (c <= 65374 || (c < 65513
            ? c == 65506
            : c <= 65516)))))))));
}

static bool ts_lex(TSLexer *lexer, TSStateId state) {
  START_LEXER();
  eof = lexer->eof(lexer);
  switch (state) {
    case 0:
      if (eof) ADVANCE(21);
      if (lookahead == '"') ADVANCE(1);
      if (lookahead == '#') ADVANCE(5);
      if (lookahead == '$') ADVANCE(17);
      if (lookahead == '\'') ADVANCE(7);
      if (lookahead == '-') ADVANCE(58);
      if (lookahead == '0') ADVANCE(44);
      if (lookahead == ':') ADVANCE(6);
      if (lookahead == '{') ADVANCE(56);
      if (lookahead == '}') ADVANCE(57);
      if (lookahead == '\t' ||
          lookahead == '\n' ||
          lookahead == '\r' ||
          lookahead == ' ') SKIP(0)
      if (lookahead == '(' ||
          lookahead == ')' ||
          lookahead == ',' ||
          lookahead == ';' ||
          lookahead == '[' ||
          lookahead == ']' ||
          lookahead == '`') ADVANCE(35);
      if (('1' <= lookahead && lookahead <= '9')) ADVANCE(45);
      if (('A' <= lookahead && lookahead <= 'Z')) ADVANCE(23);
      if (('_' <= lookahead && lookahead <= 'z')) ADVANCE(22);
      END_STATE();
    case 1:
      if (lookahead == '"') ADVANCE(49);
      if (lookahead == '\\') ADVANCE(19);
      if (lookahead != 0 &&
          lookahead != '\n') ADVANCE(1);
      END_STATE();
    case 2:
      if (lookahead == '\'') ADVANCE(50);
      END_STATE();
    case 3:
      if (lookahead == '\'') ADVANCE(50);
      if (('0' <= lookahead && lookahead <= '9') ||
          ('A' <= lookahead && lookahead <= 'Z') ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(3);
      END_STATE();
    case 4:
      if (lookahead == '-') ADVANCE(58);
      if (lookahead == '{') ADVANCE(56);
      if (lookahead == '}') ADVANCE(57);
      if (lookahead == '\t' ||
          lookahead == '\n' ||
          lookahead == '\r' ||
          lookahead == ' ') ADVANCE(54);
      if (lookahead != 0) ADVANCE(55);
      END_STATE();
    case 5:
      if (lookahead == '-') ADVANCE(9);
      END_STATE();
    case 6:
      if (lookahead == ':') ADVANCE(25);
      END_STATE();
    case 7:
      if (lookahead == '\\') ADVANCE(18);
      if (lookahead == '0' ||
          lookahead == '1') ADVANCE(39);
      if (lookahead != 0 &&
          lookahead != '\n' &&
          lookahead != '\'') ADVANCE(2);
      END_STATE();
    case 8:
      if (lookahead == 'b') ADVANCE(11);
      if (lookahead == 'd') ADVANCE(15);
      if (lookahead == 'h') ADVANCE(16);
      if (lookahead == 'o') ADVANCE(12);
      END_STATE();
    case 9:
      if (lookahead == '}') ADVANCE(38);
      END_STATE();
    case 10:
      if (lookahead == '+' ||
          lookahead == '-') ADVANCE(14);
      if (('0' <= lookahead && lookahead <= '9')) ADVANCE(48);
      END_STATE();
    case 11:
      if (lookahead == '0' ||
          lookahead == '1' ||
          lookahead == '_') ADVANCE(41);
      END_STATE();
    case 12:
      if (('0' <= lookahead && lookahead <= '7') ||
          lookahead == '_') ADVANCE(42);
      END_STATE();
    case 13:
      if (('0' <= lookahead && lookahead <= '9')) ADVANCE(47);
      END_STATE();
    case 14:
      if (('0' <= lookahead && lookahead <= '9')) ADVANCE(48);
      END_STATE();
    case 15:
      if (('0' <= lookahead && lookahead <= '9') ||
          lookahead == '_') ADVANCE(43);
      END_STATE();
    case 16:
      if (('0' <= lookahead && lookahead <= '9') ||
          ('A' <= lookahead && lookahead <= 'F') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'f')) ADVANCE(40);
      END_STATE();
    case 17:
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(24);
      END_STATE();
    case 18:
      if (('0' <= lookahead && lookahead <= '9') ||
          ('A' <= lookahead && lookahead <= 'Z') ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(3);
      if (lookahead != 0 &&
          lookahead != '\n') ADVANCE(2);
      END_STATE();
    case 19:
      if (lookahead != 0 &&
          lookahead != '\n') ADVANCE(1);
      END_STATE();
    case 20:
      if (eof) ADVANCE(21);
      if (lookahead == '"') ADVANCE(1);
      if (lookahead == '#') ADVANCE(27);
      if (lookahead == '$') ADVANCE(32);
      if (lookahead == '\'') ADVANCE(7);
      if (lookahead == '-') ADVANCE(29);
      if (lookahead == '0') ADVANCE(44);
      if (lookahead == ':') ADVANCE(30);
      if (lookahead == '{') ADVANCE(36);
      if (lookahead == '\t' ||
          lookahead == '\n' ||
          lookahead == '\r' ||
          lookahead == ' ') SKIP(20)
      if (lookahead == '(' ||
          lookahead == ')' ||
          lookahead == ',' ||
          lookahead == ';' ||
          lookahead == '[' ||
          lookahead == ']' ||
          lookahead == '`' ||
          lookahead == '}') ADVANCE(35);
      if (('1' <= lookahead && lookahead <= '9')) ADVANCE(45);
      if (('A' <= lookahead && lookahead <= 'Z')) ADVANCE(23);
      if (('_' <= lookahead && lookahead <= 'z')) ADVANCE(22);
      if (sym_operator_character_set_1(lookahead)) ADVANCE(33);
      END_STATE();
    case 21:
      ACCEPT_TOKEN(ts_builtin_sym_end);
      END_STATE();
    case 22:
      ACCEPT_TOKEN(sym_identifier);
      if (lookahead == '\'' ||
          ('0' <= lookahead && lookahead <= '9') ||
          ('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(22);
      END_STATE();
    case 23:
      ACCEPT_TOKEN(sym_capitalized);
      if (lookahead == '\'' ||
          ('0' <= lookahead && lookahead <= '9') ||
          ('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(23);
      END_STATE();
    case 24:
      ACCEPT_TOKEN(sym_system_task);
      if (lookahead == '$' ||
          ('0' <= lookahead && lookahead <= '9') ||
          ('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(24);
      END_STATE();
    case 25:
      ACCEPT_TOKEN(sym_signature_op);
      END_STATE();
    case 26:
      ACCEPT_TOKEN(sym_signature_op);
      if (sym_operator_character_set_2(lookahead)) ADVANCE(33);
      END_STATE();
    case 27:
      ACCEPT_TOKEN(sym_operator);
      if (lookahead == '-') ADVANCE(31);
      if (sym_operator_character_set_3(lookahead)) ADVANCE(33);
      END_STATE();
    case 28:
      ACCEPT_TOKEN(sym_operator);
      if (lookahead == '-') ADVANCE(28);
      if (lookahead == '@') ADVANCE(34);
      if (sym_operator_character_set_4(lookahead)) ADVANCE(33);
      if (sym_operator_character_set_5(lookahead)) ADVANCE(34);
      if (lookahead != 0 &&
          lookahead != '\n') ADVANCE(51);
      END_STATE();
    case 29:
      ACCEPT_TOKEN(sym_operator);
      if (lookahead == '-') ADVANCE(28);
      if (sym_operator_character_set_3(lookahead)) ADVANCE(33);
      END_STATE();
    case 30:
      ACCEPT_TOKEN(sym_operator);
      if (lookahead == ':') ADVANCE(26);
      if (sym_operator_character_set_6(lookahead)) ADVANCE(33);
      END_STATE();
    case 31:
      ACCEPT_TOKEN(sym_operator);
      if (lookahead == '}') ADVANCE(38);
      if (sym_operator_character_set_7(lookahead)) ADVANCE(33);
      END_STATE();
    case 32:
      ACCEPT_TOKEN(sym_operator);
      if (('A' <= lookahead && lookahead <= 'Z') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'z')) ADVANCE(24);
      if (sym_operator_character_set_2(lookahead)) ADVANCE(33);
      END_STATE();
    case 33:
      ACCEPT_TOKEN(sym_operator);
      if (sym_operator_character_set_2(lookahead)) ADVANCE(33);
      END_STATE();
    case 34:
      ACCEPT_TOKEN(sym_operator);
      if (sym_operator_character_set_2(lookahead)) ADVANCE(34);
      if (lookahead != 0 &&
          lookahead != '\n') ADVANCE(51);
      END_STATE();
    case 35:
      ACCEPT_TOKEN(sym_punctuation);
      END_STATE();
    case 36:
      ACCEPT_TOKEN(sym_punctuation);
      if (lookahead == '-') ADVANCE(53);
      END_STATE();
    case 37:
      ACCEPT_TOKEN(anon_sym_LBRACE_DASH_POUND);
      END_STATE();
    case 38:
      ACCEPT_TOKEN(anon_sym_POUND_DASH_RBRACE);
      END_STATE();
    case 39:
      ACCEPT_TOKEN(aux_sym_number_token1);
      if (lookahead == '\'') ADVANCE(50);
      END_STATE();
    case 40:
      ACCEPT_TOKEN(aux_sym_number_token2);
      if (('0' <= lookahead && lookahead <= '9') ||
          ('A' <= lookahead && lookahead <= 'F') ||
          lookahead == '_' ||
          ('a' <= lookahead && lookahead <= 'f')) ADVANCE(40);
      END_STATE();
    case 41:
      ACCEPT_TOKEN(aux_sym_number_token3);
      if (lookahead == '0' ||
          lookahead == '1' ||
          lookahead == '_') ADVANCE(41);
      END_STATE();
    case 42:
      ACCEPT_TOKEN(aux_sym_number_token4);
      if (('0' <= lookahead && lookahead <= '7') ||
          lookahead == '_') ADVANCE(42);
      END_STATE();
    case 43:
      ACCEPT_TOKEN(aux_sym_number_token5);
      if (('0' <= lookahead && lookahead <= '9') ||
          lookahead == '_') ADVANCE(43);
      END_STATE();
    case 44:
      ACCEPT_TOKEN(aux_sym_number_token6);
      if (lookahead == '\'') ADVANCE(8);
      if (lookahead == '.') ADVANCE(13);
      if (lookahead == '_') ADVANCE(46);
      if (lookahead == 'B' ||
          lookahead == 'b') ADVANCE(11);
      if (lookahead == 'E' ||
          lookahead == 'e') ADVANCE(10);
      if (lookahead == 'O' ||
          lookahead == 'o') ADVANCE(12);
      if (lookahead == 'X' ||
          lookahead == 'x') ADVANCE(16);
      if (('0' <= lookahead && lookahead <= '9')) ADVANCE(45);
      END_STATE();
    case 45:
      ACCEPT_TOKEN(aux_sym_number_token6);
      if (lookahead == '\'') ADVANCE(8);
      if (lookahead == '.') ADVANCE(13);
      if (lookahead == '_') ADVANCE(46);
      if (lookahead == 'E' ||
          lookahead == 'e') ADVANCE(10);
      if (('0' <= lookahead && lookahead <= '9')) ADVANCE(45);
      END_STATE();
    case 46:
      ACCEPT_TOKEN(aux_sym_number_token6);
      if (lookahead == '.') ADVANCE(13);
      if (lookahead == 'E' ||
          lookahead == 'e') ADVANCE(10);
      if (('0' <= lookahead && lookahead <= '9') ||
          lookahead == '_') ADVANCE(46);
      END_STATE();
    case 47:
      ACCEPT_TOKEN(aux_sym_number_token6);
      if (lookahead == 'E' ||
          lookahead == 'e') ADVANCE(10);
      if (('0' <= lookahead && lookahead <= '9')) ADVANCE(47);
      END_STATE();
    case 48:
      ACCEPT_TOKEN(aux_sym_number_token6);
      if (('0' <= lookahead && lookahead <= '9')) ADVANCE(48);
      END_STATE();
    case 49:
      ACCEPT_TOKEN(sym_string);
      END_STATE();
    case 50:
      ACCEPT_TOKEN(sym_character);
      END_STATE();
    case 51:
      ACCEPT_TOKEN(sym_line_comment);
      if (lookahead != 0 &&
          lookahead != '\n') ADVANCE(51);
      END_STATE();
    case 52:
      ACCEPT_TOKEN(anon_sym_LBRACE_DASH);
      END_STATE();
    case 53:
      ACCEPT_TOKEN(anon_sym_LBRACE_DASH);
      if (lookahead == '#') ADVANCE(37);
      END_STATE();
    case 54:
      ACCEPT_TOKEN(aux_sym_block_comment_token1);
      if (lookahead == '\t' ||
          lookahead == '\n' ||
          lookahead == '\r' ||
          lookahead == ' ') ADVANCE(54);
      if (lookahead != 0 &&
          lookahead != '-' &&
          lookahead != '{' &&
          lookahead != '}') ADVANCE(55);
      END_STATE();
    case 55:
      ACCEPT_TOKEN(aux_sym_block_comment_token1);
      if (lookahead != 0 &&
          lookahead != '-' &&
          lookahead != '{' &&
          lookahead != '}') ADVANCE(55);
      END_STATE();
    case 56:
      ACCEPT_TOKEN(anon_sym_LBRACE);
      if (lookahead == '-') ADVANCE(52);
      END_STATE();
    case 57:
      ACCEPT_TOKEN(anon_sym_RBRACE);
      END_STATE();
    case 58:
      ACCEPT_TOKEN(anon_sym_DASH);
      if (lookahead == '}') ADVANCE(59);
      END_STATE();
    case 59:
      ACCEPT_TOKEN(anon_sym_DASH_RBRACE);
      END_STATE();
    default:
      return false;
  }
}

static bool ts_lex_keywords(TSLexer *lexer, TSStateId state) {
  START_LEXER();
  eof = lexer->eof(lexer);
  switch (state) {
    case 0:
      if (lookahead == 'a') ADVANCE(1);
      if (lookahead == 'c') ADVANCE(2);
      if (lookahead == 'd') ADVANCE(3);
      if (lookahead == 'e') ADVANCE(4);
      if (lookahead == 'f') ADVANCE(5);
      if (lookahead == 'i') ADVANCE(6);
      if (lookahead == 'l') ADVANCE(7);
      if (lookahead == 'm') ADVANCE(8);
      if (lookahead == 'o') ADVANCE(9);
      if (lookahead == 'p') ADVANCE(10);
      if (lookahead == 'q') ADVANCE(11);
      if (lookahead == 'r') ADVANCE(12);
      if (lookahead == 's') ADVANCE(13);
      if (lookahead == 't') ADVANCE(14);
      if (lookahead == 'v') ADVANCE(15);
      if (lookahead == 'w') ADVANCE(16);
      if (lookahead == '\t' ||
          lookahead == '\n' ||
          lookahead == '\r' ||
          lookahead == ' ') SKIP(0)
      END_STATE();
    case 1:
      if (lookahead == 'c') ADVANCE(17);
      END_STATE();
    case 2:
      if (lookahead == 'a') ADVANCE(18);
      if (lookahead == 'l') ADVANCE(19);
      if (lookahead == 'o') ADVANCE(20);
      END_STATE();
    case 3:
      if (lookahead == 'a') ADVANCE(21);
      if (lookahead == 'e') ADVANCE(22);
      if (lookahead == 'o') ADVANCE(23);
      END_STATE();
    case 4:
      if (lookahead == 'l') ADVANCE(24);
      END_STATE();
    case 5:
      if (lookahead == 'o') ADVANCE(25);
      END_STATE();
    case 6:
      if (lookahead == 'f') ADVANCE(26);
      if (lookahead == 'm') ADVANCE(27);
      if (lookahead == 'n') ADVANCE(28);
      END_STATE();
    case 7:
      if (lookahead == 'e') ADVANCE(29);
      END_STATE();
    case 8:
      if (lookahead == 'o') ADVANCE(30);
      END_STATE();
    case 9:
      if (lookahead == 'f') ADVANCE(31);
      END_STATE();
    case 10:
      if (lookahead == 'a') ADVANCE(32);
      if (lookahead == 'r') ADVANCE(33);
      END_STATE();
    case 11:
      if (lookahead == 'u') ADVANCE(34);
      END_STATE();
    case 12:
      if (lookahead == 'u') ADVANCE(35);
      END_STATE();
    case 13:
      if (lookahead == 'i') ADVANCE(36);
      if (lookahead == 't') ADVANCE(37);
      if (lookahead == 'y') ADVANCE(38);
      END_STATE();
    case 14:
      if (lookahead == 'h') ADVANCE(39);
      if (lookahead == 'y') ADVANCE(40);
      END_STATE();
    case 15:
      if (lookahead == 'a') ADVANCE(41);
      if (lookahead == 'e') ADVANCE(42);
      END_STATE();
    case 16:
      if (lookahead == 'h') ADVANCE(43);
      END_STATE();
    case 17:
      if (lookahead == 't') ADVANCE(44);
      END_STATE();
    case 18:
      if (lookahead == 's') ADVANCE(45);
      END_STATE();
    case 19:
      if (lookahead == 'a') ADVANCE(46);
      END_STATE();
    case 20:
      if (lookahead == 'h') ADVANCE(47);
      END_STATE();
    case 21:
      if (lookahead == 't') ADVANCE(48);
      END_STATE();
    case 22:
      if (lookahead == 'r') ADVANCE(49);
      END_STATE();
    case 23:
      ACCEPT_TOKEN(anon_sym_do);
      END_STATE();
    case 24:
      if (lookahead == 's') ADVANCE(50);
      END_STATE();
    case 25:
      if (lookahead == 'r') ADVANCE(51);
      END_STATE();
    case 26:
      ACCEPT_TOKEN(anon_sym_if);
      END_STATE();
    case 27:
      if (lookahead == 'p') ADVANCE(52);
      END_STATE();
    case 28:
      ACCEPT_TOKEN(anon_sym_in);
      if (lookahead == 'c') ADVANCE(53);
      if (lookahead == 'f') ADVANCE(54);
      if (lookahead == 's') ADVANCE(55);
      if (lookahead == 't') ADVANCE(56);
      END_STATE();
    case 29:
      if (lookahead == 't') ADVANCE(57);
      END_STATE();
    case 30:
      if (lookahead == 'd') ADVANCE(58);
      END_STATE();
    case 31:
      ACCEPT_TOKEN(anon_sym_of);
      END_STATE();
    case 32:
      if (lookahead == 'c') ADVANCE(59);
      END_STATE();
    case 33:
      if (lookahead == 'i') ADVANCE(60);
      END_STATE();
    case 34:
      if (lookahead == 'a') ADVANCE(61);
      END_STATE();
    case 35:
      if (lookahead == 'l') ADVANCE(62);
      END_STATE();
    case 36:
      if (lookahead == 'g') ADVANCE(63);
      END_STATE();
    case 37:
      if (lookahead == 'r') ADVANCE(64);
      END_STATE();
    case 38:
      if (lookahead == 'n') ADVANCE(65);
      END_STATE();
    case 39:
      if (lookahead == 'e') ADVANCE(66);
      END_STATE();
    case 40:
      if (lookahead == 'p') ADVANCE(67);
      END_STATE();
    case 41:
      if (lookahead == 'l') ADVANCE(68);
      END_STATE();
    case 42:
      if (lookahead == 'r') ADVANCE(69);
      END_STATE();
    case 43:
      if (lookahead == 'e') ADVANCE(70);
      END_STATE();
    case 44:
      if (lookahead == 'i') ADVANCE(71);
      END_STATE();
    case 45:
      if (lookahead == 'e') ADVANCE(72);
      END_STATE();
    case 46:
      if (lookahead == 's') ADVANCE(73);
      END_STATE();
    case 47:
      if (lookahead == 'e') ADVANCE(74);
      END_STATE();
    case 48:
      if (lookahead == 'a') ADVANCE(75);
      END_STATE();
    case 49:
      if (lookahead == 'i') ADVANCE(76);
      END_STATE();
    case 50:
      if (lookahead == 'e') ADVANCE(77);
      END_STATE();
    case 51:
      if (lookahead == 'e') ADVANCE(78);
      END_STATE();
    case 52:
      if (lookahead == 'o') ADVANCE(79);
      END_STATE();
    case 53:
      if (lookahead == 'o') ADVANCE(80);
      END_STATE();
    case 54:
      if (lookahead == 'i') ADVANCE(81);
      END_STATE();
    case 55:
      if (lookahead == 't') ADVANCE(82);
      END_STATE();
    case 56:
      if (lookahead == 'e') ADVANCE(83);
      END_STATE();
    case 57:
      ACCEPT_TOKEN(anon_sym_let);
      if (lookahead == 's') ADVANCE(84);
      END_STATE();
    case 58:
      if (lookahead == 'u') ADVANCE(85);
      END_STATE();
    case 59:
      if (lookahead == 'k') ADVANCE(86);
      END_STATE();
    case 60:
      if (lookahead == 'm') ADVANCE(87);
      END_STATE();
    case 61:
      if (lookahead == 'l') ADVANCE(88);
      END_STATE();
    case 62:
      if (lookahead == 'e') ADVANCE(89);
      END_STATE();
    case 63:
      if (lookahead == 'n') ADVANCE(90);
      END_STATE();
    case 64:
      if (lookahead == 'i') ADVANCE(91);
      if (lookahead == 'u') ADVANCE(92);
      END_STATE();
    case 65:
      if (lookahead == 't') ADVANCE(93);
      END_STATE();
    case 66:
      if (lookahead == 'n') ADVANCE(94);
      END_STATE();
    case 67:
      if (lookahead == 'e') ADVANCE(95);
      END_STATE();
    case 68:
      if (lookahead == 'u') ADVANCE(96);
      END_STATE();
    case 69:
      if (lookahead == 'i') ADVANCE(97);
      END_STATE();
    case 70:
      if (lookahead == 'n') ADVANCE(98);
      if (lookahead == 'r') ADVANCE(99);
      END_STATE();
    case 71:
      if (lookahead == 'o') ADVANCE(100);
      END_STATE();
    case 72:
      ACCEPT_TOKEN(anon_sym_case);
      END_STATE();
    case 73:
      if (lookahead == 's') ADVANCE(101);
      END_STATE();
    case 74:
      if (lookahead == 'r') ADVANCE(102);
      END_STATE();
    case 75:
      ACCEPT_TOKEN(anon_sym_data);
      END_STATE();
    case 76:
      if (lookahead == 'v') ADVANCE(103);
      END_STATE();
    case 77:
      ACCEPT_TOKEN(anon_sym_else);
      END_STATE();
    case 78:
      if (lookahead == 'i') ADVANCE(104);
      END_STATE();
    case 79:
      if (lookahead == 'r') ADVANCE(105);
      END_STATE();
    case 80:
      if (lookahead == 'h') ADVANCE(106);
      END_STATE();
    case 81:
      if (lookahead == 'x') ADVANCE(107);
      END_STATE();
    case 82:
      if (lookahead == 'a') ADVANCE(108);
      END_STATE();
    case 83:
      if (lookahead == 'r') ADVANCE(109);
      END_STATE();
    case 84:
      if (lookahead == 'e') ADVANCE(110);
      END_STATE();
    case 85:
      if (lookahead == 'l') ADVANCE(111);
      END_STATE();
    case 86:
      if (lookahead == 'a') ADVANCE(112);
      END_STATE();
    case 87:
      if (lookahead == 'i') ADVANCE(113);
      END_STATE();
    case 88:
      if (lookahead == 'i') ADVANCE(114);
      END_STATE();
    case 89:
      if (lookahead == 's') ADVANCE(115);
      END_STATE();
    case 90:
      if (lookahead == 'a') ADVANCE(116);
      END_STATE();
    case 91:
      if (lookahead == 'n') ADVANCE(117);
      END_STATE();
    case 92:
      if (lookahead == 'c') ADVANCE(118);
      END_STATE();
    case 93:
      if (lookahead == 'h') ADVANCE(119);
      END_STATE();
    case 94:
      ACCEPT_TOKEN(anon_sym_then);
      END_STATE();
    case 95:
      ACCEPT_TOKEN(anon_sym_type);
      END_STATE();
    case 96:
      if (lookahead == 'e') ADVANCE(120);
      END_STATE();
    case 97:
      if (lookahead == 'l') ADVANCE(121);
      END_STATE();
    case 98:
      ACCEPT_TOKEN(anon_sym_when);
      END_STATE();
    case 99:
      if (lookahead == 'e') ADVANCE(122);
      END_STATE();
    case 100:
      if (lookahead == 'n') ADVANCE(123);
      END_STATE();
    case 101:
      ACCEPT_TOKEN(anon_sym_class);
      END_STATE();
    case 102:
      if (lookahead == 'e') ADVANCE(124);
      END_STATE();
    case 103:
      if (lookahead == 'i') ADVANCE(125);
      END_STATE();
    case 104:
      if (lookahead == 'g') ADVANCE(126);
      END_STATE();
    case 105:
      if (lookahead == 't') ADVANCE(127);
      END_STATE();
    case 106:
      if (lookahead == 'e') ADVANCE(128);
      END_STATE();
    case 107:
      ACCEPT_TOKEN(anon_sym_infix);
      if (lookahead == 'l') ADVANCE(129);
      if (lookahead == 'r') ADVANCE(130);
      END_STATE();
    case 108:
      if (lookahead == 'n') ADVANCE(131);
      END_STATE();
    case 109:
      if (lookahead == 'f') ADVANCE(132);
      END_STATE();
    case 110:
      if (lookahead == 'q') ADVANCE(133);
      END_STATE();
    case 111:
      if (lookahead == 'e') ADVANCE(134);
      END_STATE();
    case 112:
      if (lookahead == 'g') ADVANCE(135);
      END_STATE();
    case 113:
      if (lookahead == 't') ADVANCE(136);
      END_STATE();
    case 114:
      if (lookahead == 'f') ADVANCE(137);
      END_STATE();
    case 115:
      ACCEPT_TOKEN(anon_sym_rules);
      END_STATE();
    case 116:
      if (lookahead == 't') ADVANCE(138);
      END_STATE();
    case 117:
      if (lookahead == 'g') ADVANCE(139);
      END_STATE();
    case 118:
      if (lookahead == 't') ADVANCE(140);
      END_STATE();
    case 119:
      if (lookahead == 'e') ADVANCE(141);
      END_STATE();
    case 120:
      if (lookahead == 'O') ADVANCE(142);
      END_STATE();
    case 121:
      if (lookahead == 'o') ADVANCE(143);
      END_STATE();
    case 122:
      ACCEPT_TOKEN(anon_sym_where);
      END_STATE();
    case 123:
      ACCEPT_TOKEN(anon_sym_action);
      END_STATE();
    case 124:
      if (lookahead == 'n') ADVANCE(144);
      END_STATE();
    case 125:
      if (lookahead == 'n') ADVANCE(145);
      END_STATE();
    case 126:
      if (lookahead == 'n') ADVANCE(146);
      END_STATE();
    case 127:
      ACCEPT_TOKEN(anon_sym_import);
      END_STATE();
    case 128:
      if (lookahead == 'r') ADVANCE(147);
      END_STATE();
    case 129:
      ACCEPT_TOKEN(anon_sym_infixl);
      END_STATE();
    case 130:
      ACCEPT_TOKEN(anon_sym_infixr);
      END_STATE();
    case 131:
      if (lookahead == 'c') ADVANCE(148);
      END_STATE();
    case 132:
      if (lookahead == 'a') ADVANCE(149);
      END_STATE();
    case 133:
      ACCEPT_TOKEN(anon_sym_letseq);
      END_STATE();
    case 134:
      ACCEPT_TOKEN(anon_sym_module);
      END_STATE();
    case 135:
      if (lookahead == 'e') ADVANCE(150);
      END_STATE();
    case 136:
      if (lookahead == 'i') ADVANCE(151);
      END_STATE();
    case 137:
      if (lookahead == 'i') ADVANCE(152);
      END_STATE();
    case 138:
      if (lookahead == 'u') ADVANCE(153);
      END_STATE();
    case 139:
      if (lookahead == 'O') ADVANCE(154);
      END_STATE();
    case 140:
      ACCEPT_TOKEN(anon_sym_struct);
      END_STATE();
    case 141:
      if (lookahead == 's') ADVANCE(155);
      END_STATE();
    case 142:
      if (lookahead == 'f') ADVANCE(156);
      END_STATE();
    case 143:
      if (lookahead == 'g') ADVANCE(157);
      END_STATE();
    case 144:
      if (lookahead == 't') ADVANCE(158);
      END_STATE();
    case 145:
      if (lookahead == 'g') ADVANCE(159);
      END_STATE();
    case 146:
      ACCEPT_TOKEN(anon_sym_foreign);
      END_STATE();
    case 147:
      if (lookahead == 'e') ADVANCE(160);
      END_STATE();
    case 148:
      if (lookahead == 'e') ADVANCE(161);
      END_STATE();
    case 149:
      if (lookahead == 'c') ADVANCE(162);
      END_STATE();
    case 150:
      ACCEPT_TOKEN(anon_sym_package);
      END_STATE();
    case 151:
      if (lookahead == 'v') ADVANCE(163);
      END_STATE();
    case 152:
      if (lookahead == 'e') ADVANCE(164);
      END_STATE();
    case 153:
      if (lookahead == 'r') ADVANCE(165);
      END_STATE();
    case 154:
      if (lookahead == 'f') ADVANCE(166);
      END_STATE();
    case 155:
      if (lookahead == 'i') ADVANCE(167);
      END_STATE();
    case 156:
      ACCEPT_TOKEN(anon_sym_valueOf);
      END_STATE();
    case 157:
      ACCEPT_TOKEN(anon_sym_verilog);
      END_STATE();
    case 158:
      ACCEPT_TOKEN(anon_sym_coherent);
      END_STATE();
    case 159:
      ACCEPT_TOKEN(anon_sym_deriving);
      END_STATE();
    case 160:
      if (lookahead == 'n') ADVANCE(168);
      END_STATE();
    case 161:
      ACCEPT_TOKEN(anon_sym_instance);
      END_STATE();
    case 162:
      if (lookahead == 'e') ADVANCE(169);
      END_STATE();
    case 163:
      if (lookahead == 'e') ADVANCE(170);
      END_STATE();
    case 164:
      if (lookahead == 'd') ADVANCE(171);
      END_STATE();
    case 165:
      if (lookahead == 'e') ADVANCE(172);
      END_STATE();
    case 166:
      ACCEPT_TOKEN(anon_sym_stringOf);
      END_STATE();
    case 167:
      if (lookahead == 'z') ADVANCE(173);
      END_STATE();
    case 168:
      if (lookahead == 't') ADVANCE(174);
      END_STATE();
    case 169:
      ACCEPT_TOKEN(anon_sym_interface);
      END_STATE();
    case 170:
      ACCEPT_TOKEN(anon_sym_primitive);
      END_STATE();
    case 171:
      ACCEPT_TOKEN(anon_sym_qualified);
      END_STATE();
    case 172:
      ACCEPT_TOKEN(anon_sym_signature);
      END_STATE();
    case 173:
      if (lookahead == 'e') ADVANCE(175);
      END_STATE();
    case 174:
      ACCEPT_TOKEN(anon_sym_incoherent);
      END_STATE();
    case 175:
      ACCEPT_TOKEN(anon_sym_synthesize);
      END_STATE();
    default:
      return false;
  }
}

static const TSLexMode ts_lex_modes[STATE_COUNT] = {
  [0] = {.lex_state = 0},
  [1] = {.lex_state = 20},
  [2] = {.lex_state = 20},
  [3] = {.lex_state = 20},
  [4] = {.lex_state = 20},
  [5] = {.lex_state = 20},
  [6] = {.lex_state = 20},
  [7] = {.lex_state = 20},
  [8] = {.lex_state = 20},
  [9] = {.lex_state = 20},
  [10] = {.lex_state = 20},
  [11] = {.lex_state = 20},
  [12] = {.lex_state = 4},
  [13] = {.lex_state = 4},
  [14] = {.lex_state = 4},
  [15] = {.lex_state = 4},
  [16] = {.lex_state = 4},
  [17] = {.lex_state = 4},
  [18] = {.lex_state = 4},
  [19] = {.lex_state = 0},
};

static const uint16_t ts_parse_table[LARGE_STATE_COUNT][SYMBOL_COUNT] = {
  [0] = {
    [ts_builtin_sym_end] = ACTIONS(1),
    [sym_identifier] = ACTIONS(1),
    [anon_sym_package] = ACTIONS(1),
    [anon_sym_import] = ACTIONS(1),
    [anon_sym_qualified] = ACTIONS(1),
    [anon_sym_action] = ACTIONS(1),
    [anon_sym_case] = ACTIONS(1),
    [anon_sym_class] = ACTIONS(1),
    [anon_sym_data] = ACTIONS(1),
    [anon_sym_deriving] = ACTIONS(1),
    [anon_sym_do] = ACTIONS(1),
    [anon_sym_else] = ACTIONS(1),
    [anon_sym_foreign] = ACTIONS(1),
    [anon_sym_if] = ACTIONS(1),
    [anon_sym_in] = ACTIONS(1),
    [anon_sym_coherent] = ACTIONS(1),
    [anon_sym_incoherent] = ACTIONS(1),
    [anon_sym_infix] = ACTIONS(1),
    [anon_sym_infixl] = ACTIONS(1),
    [anon_sym_infixr] = ACTIONS(1),
    [anon_sym_interface] = ACTIONS(1),
    [anon_sym_instance] = ACTIONS(1),
    [anon_sym_let] = ACTIONS(1),
    [anon_sym_letseq] = ACTIONS(1),
    [anon_sym_of] = ACTIONS(1),
    [anon_sym_primitive] = ACTIONS(1),
    [anon_sym_rules] = ACTIONS(1),
    [anon_sym_signature] = ACTIONS(1),
    [anon_sym_struct] = ACTIONS(1),
    [anon_sym_module] = ACTIONS(1),
    [anon_sym_then] = ACTIONS(1),
    [anon_sym_type] = ACTIONS(1),
    [anon_sym_valueOf] = ACTIONS(1),
    [anon_sym_stringOf] = ACTIONS(1),
    [anon_sym_verilog] = ACTIONS(1),
    [anon_sym_synthesize] = ACTIONS(1),
    [anon_sym_when] = ACTIONS(1),
    [anon_sym_where] = ACTIONS(1),
    [sym_capitalized] = ACTIONS(1),
    [sym_system_task] = ACTIONS(1),
    [sym_signature_op] = ACTIONS(1),
    [sym_punctuation] = ACTIONS(1),
    [anon_sym_POUND_DASH_RBRACE] = ACTIONS(1),
    [aux_sym_number_token1] = ACTIONS(1),
    [aux_sym_number_token2] = ACTIONS(1),
    [aux_sym_number_token3] = ACTIONS(1),
    [aux_sym_number_token4] = ACTIONS(1),
    [aux_sym_number_token5] = ACTIONS(1),
    [aux_sym_number_token6] = ACTIONS(1),
    [sym_string] = ACTIONS(1),
    [sym_character] = ACTIONS(1),
    [anon_sym_LBRACE_DASH] = ACTIONS(1),
    [anon_sym_LBRACE] = ACTIONS(1),
    [anon_sym_RBRACE] = ACTIONS(1),
    [anon_sym_DASH] = ACTIONS(1),
    [anon_sym_DASH_RBRACE] = ACTIONS(1),
  },
  [1] = {
    [sym_source_file] = STATE(19),
    [sym_package_ref] = STATE(2),
    [sym_package_keyword] = STATE(8),
    [sym_keyword] = STATE(2),
    [sym_pragma_delimiter] = STATE(2),
    [sym_number] = STATE(2),
    [sym_block_comment] = STATE(2),
    [aux_sym_source_file_repeat1] = STATE(2),
    [ts_builtin_sym_end] = ACTIONS(3),
    [sym_identifier] = ACTIONS(5),
    [anon_sym_package] = ACTIONS(7),
    [anon_sym_import] = ACTIONS(7),
    [anon_sym_qualified] = ACTIONS(7),
    [anon_sym_action] = ACTIONS(9),
    [anon_sym_case] = ACTIONS(9),
    [anon_sym_class] = ACTIONS(9),
    [anon_sym_data] = ACTIONS(9),
    [anon_sym_deriving] = ACTIONS(9),
    [anon_sym_do] = ACTIONS(9),
    [anon_sym_else] = ACTIONS(9),
    [anon_sym_foreign] = ACTIONS(9),
    [anon_sym_if] = ACTIONS(9),
    [anon_sym_in] = ACTIONS(9),
    [anon_sym_coherent] = ACTIONS(9),
    [anon_sym_incoherent] = ACTIONS(9),
    [anon_sym_infix] = ACTIONS(9),
    [anon_sym_infixl] = ACTIONS(9),
    [anon_sym_infixr] = ACTIONS(9),
    [anon_sym_interface] = ACTIONS(9),
    [anon_sym_instance] = ACTIONS(9),
    [anon_sym_let] = ACTIONS(9),
    [anon_sym_letseq] = ACTIONS(9),
    [anon_sym_of] = ACTIONS(9),
    [anon_sym_primitive] = ACTIONS(9),
    [anon_sym_rules] = ACTIONS(9),
    [anon_sym_signature] = ACTIONS(9),
    [anon_sym_struct] = ACTIONS(9),
    [anon_sym_module] = ACTIONS(9),
    [anon_sym_then] = ACTIONS(9),
    [anon_sym_type] = ACTIONS(9),
    [anon_sym_valueOf] = ACTIONS(9),
    [anon_sym_stringOf] = ACTIONS(9),
    [anon_sym_verilog] = ACTIONS(9),
    [anon_sym_synthesize] = ACTIONS(9),
    [anon_sym_when] = ACTIONS(9),
    [anon_sym_where] = ACTIONS(9),
    [sym_capitalized] = ACTIONS(11),
    [sym_system_task] = ACTIONS(11),
    [sym_signature_op] = ACTIONS(5),
    [sym_operator] = ACTIONS(5),
    [sym_punctuation] = ACTIONS(5),
    [anon_sym_LBRACE_DASH_POUND] = ACTIONS(13),
    [anon_sym_POUND_DASH_RBRACE] = ACTIONS(13),
    [aux_sym_number_token1] = ACTIONS(15),
    [aux_sym_number_token2] = ACTIONS(17),
    [aux_sym_number_token3] = ACTIONS(17),
    [aux_sym_number_token4] = ACTIONS(17),
    [aux_sym_number_token5] = ACTIONS(17),
    [aux_sym_number_token6] = ACTIONS(15),
    [sym_string] = ACTIONS(11),
    [sym_character] = ACTIONS(11),
    [sym_line_comment] = ACTIONS(5),
    [anon_sym_LBRACE_DASH] = ACTIONS(19),
  },
  [2] = {
    [sym_package_ref] = STATE(3),
    [sym_package_keyword] = STATE(8),
    [sym_keyword] = STATE(3),
    [sym_pragma_delimiter] = STATE(3),
    [sym_number] = STATE(3),
    [sym_block_comment] = STATE(3),
    [aux_sym_source_file_repeat1] = STATE(3),
    [ts_builtin_sym_end] = ACTIONS(21),
    [sym_identifier] = ACTIONS(23),
    [anon_sym_package] = ACTIONS(7),
    [anon_sym_import] = ACTIONS(7),
    [anon_sym_qualified] = ACTIONS(7),
    [anon_sym_action] = ACTIONS(9),
    [anon_sym_case] = ACTIONS(9),
    [anon_sym_class] = ACTIONS(9),
    [anon_sym_data] = ACTIONS(9),
    [anon_sym_deriving] = ACTIONS(9),
    [anon_sym_do] = ACTIONS(9),
    [anon_sym_else] = ACTIONS(9),
    [anon_sym_foreign] = ACTIONS(9),
    [anon_sym_if] = ACTIONS(9),
    [anon_sym_in] = ACTIONS(9),
    [anon_sym_coherent] = ACTIONS(9),
    [anon_sym_incoherent] = ACTIONS(9),
    [anon_sym_infix] = ACTIONS(9),
    [anon_sym_infixl] = ACTIONS(9),
    [anon_sym_infixr] = ACTIONS(9),
    [anon_sym_interface] = ACTIONS(9),
    [anon_sym_instance] = ACTIONS(9),
    [anon_sym_let] = ACTIONS(9),
    [anon_sym_letseq] = ACTIONS(9),
    [anon_sym_of] = ACTIONS(9),
    [anon_sym_primitive] = ACTIONS(9),
    [anon_sym_rules] = ACTIONS(9),
    [anon_sym_signature] = ACTIONS(9),
    [anon_sym_struct] = ACTIONS(9),
    [anon_sym_module] = ACTIONS(9),
    [anon_sym_then] = ACTIONS(9),
    [anon_sym_type] = ACTIONS(9),
    [anon_sym_valueOf] = ACTIONS(9),
    [anon_sym_stringOf] = ACTIONS(9),
    [anon_sym_verilog] = ACTIONS(9),
    [anon_sym_synthesize] = ACTIONS(9),
    [anon_sym_when] = ACTIONS(9),
    [anon_sym_where] = ACTIONS(9),
    [sym_capitalized] = ACTIONS(25),
    [sym_system_task] = ACTIONS(25),
    [sym_signature_op] = ACTIONS(23),
    [sym_operator] = ACTIONS(23),
    [sym_punctuation] = ACTIONS(23),
    [anon_sym_LBRACE_DASH_POUND] = ACTIONS(13),
    [anon_sym_POUND_DASH_RBRACE] = ACTIONS(13),
    [aux_sym_number_token1] = ACTIONS(15),
    [aux_sym_number_token2] = ACTIONS(17),
    [aux_sym_number_token3] = ACTIONS(17),
    [aux_sym_number_token4] = ACTIONS(17),
    [aux_sym_number_token5] = ACTIONS(17),
    [aux_sym_number_token6] = ACTIONS(15),
    [sym_string] = ACTIONS(25),
    [sym_character] = ACTIONS(25),
    [sym_line_comment] = ACTIONS(23),
    [anon_sym_LBRACE_DASH] = ACTIONS(19),
  },
  [3] = {
    [sym_package_ref] = STATE(3),
    [sym_package_keyword] = STATE(8),
    [sym_keyword] = STATE(3),
    [sym_pragma_delimiter] = STATE(3),
    [sym_number] = STATE(3),
    [sym_block_comment] = STATE(3),
    [aux_sym_source_file_repeat1] = STATE(3),
    [ts_builtin_sym_end] = ACTIONS(27),
    [sym_identifier] = ACTIONS(29),
    [anon_sym_package] = ACTIONS(32),
    [anon_sym_import] = ACTIONS(32),
    [anon_sym_qualified] = ACTIONS(32),
    [anon_sym_action] = ACTIONS(35),
    [anon_sym_case] = ACTIONS(35),
    [anon_sym_class] = ACTIONS(35),
    [anon_sym_data] = ACTIONS(35),
    [anon_sym_deriving] = ACTIONS(35),
    [anon_sym_do] = ACTIONS(35),
    [anon_sym_else] = ACTIONS(35),
    [anon_sym_foreign] = ACTIONS(35),
    [anon_sym_if] = ACTIONS(35),
    [anon_sym_in] = ACTIONS(35),
    [anon_sym_coherent] = ACTIONS(35),
    [anon_sym_incoherent] = ACTIONS(35),
    [anon_sym_infix] = ACTIONS(35),
    [anon_sym_infixl] = ACTIONS(35),
    [anon_sym_infixr] = ACTIONS(35),
    [anon_sym_interface] = ACTIONS(35),
    [anon_sym_instance] = ACTIONS(35),
    [anon_sym_let] = ACTIONS(35),
    [anon_sym_letseq] = ACTIONS(35),
    [anon_sym_of] = ACTIONS(35),
    [anon_sym_primitive] = ACTIONS(35),
    [anon_sym_rules] = ACTIONS(35),
    [anon_sym_signature] = ACTIONS(35),
    [anon_sym_struct] = ACTIONS(35),
    [anon_sym_module] = ACTIONS(35),
    [anon_sym_then] = ACTIONS(35),
    [anon_sym_type] = ACTIONS(35),
    [anon_sym_valueOf] = ACTIONS(35),
    [anon_sym_stringOf] = ACTIONS(35),
    [anon_sym_verilog] = ACTIONS(35),
    [anon_sym_synthesize] = ACTIONS(35),
    [anon_sym_when] = ACTIONS(35),
    [anon_sym_where] = ACTIONS(35),
    [sym_capitalized] = ACTIONS(38),
    [sym_system_task] = ACTIONS(38),
    [sym_signature_op] = ACTIONS(29),
    [sym_operator] = ACTIONS(29),
    [sym_punctuation] = ACTIONS(29),
    [anon_sym_LBRACE_DASH_POUND] = ACTIONS(41),
    [anon_sym_POUND_DASH_RBRACE] = ACTIONS(41),
    [aux_sym_number_token1] = ACTIONS(44),
    [aux_sym_number_token2] = ACTIONS(47),
    [aux_sym_number_token3] = ACTIONS(47),
    [aux_sym_number_token4] = ACTIONS(47),
    [aux_sym_number_token5] = ACTIONS(47),
    [aux_sym_number_token6] = ACTIONS(44),
    [sym_string] = ACTIONS(38),
    [sym_character] = ACTIONS(38),
    [sym_line_comment] = ACTIONS(29),
    [anon_sym_LBRACE_DASH] = ACTIONS(50),
  },
  [4] = {
    [ts_builtin_sym_end] = ACTIONS(53),
    [sym_identifier] = ACTIONS(55),
    [anon_sym_package] = ACTIONS(55),
    [anon_sym_import] = ACTIONS(55),
    [anon_sym_qualified] = ACTIONS(55),
    [anon_sym_action] = ACTIONS(55),
    [anon_sym_case] = ACTIONS(55),
    [anon_sym_class] = ACTIONS(55),
    [anon_sym_data] = ACTIONS(55),
    [anon_sym_deriving] = ACTIONS(55),
    [anon_sym_do] = ACTIONS(55),
    [anon_sym_else] = ACTIONS(55),
    [anon_sym_foreign] = ACTIONS(55),
    [anon_sym_if] = ACTIONS(55),
    [anon_sym_in] = ACTIONS(55),
    [anon_sym_coherent] = ACTIONS(55),
    [anon_sym_incoherent] = ACTIONS(55),
    [anon_sym_infix] = ACTIONS(55),
    [anon_sym_infixl] = ACTIONS(55),
    [anon_sym_infixr] = ACTIONS(55),
    [anon_sym_interface] = ACTIONS(55),
    [anon_sym_instance] = ACTIONS(55),
    [anon_sym_let] = ACTIONS(55),
    [anon_sym_letseq] = ACTIONS(55),
    [anon_sym_of] = ACTIONS(55),
    [anon_sym_primitive] = ACTIONS(55),
    [anon_sym_rules] = ACTIONS(55),
    [anon_sym_signature] = ACTIONS(55),
    [anon_sym_struct] = ACTIONS(55),
    [anon_sym_module] = ACTIONS(55),
    [anon_sym_then] = ACTIONS(55),
    [anon_sym_type] = ACTIONS(55),
    [anon_sym_valueOf] = ACTIONS(55),
    [anon_sym_stringOf] = ACTIONS(55),
    [anon_sym_verilog] = ACTIONS(55),
    [anon_sym_synthesize] = ACTIONS(55),
    [anon_sym_when] = ACTIONS(55),
    [anon_sym_where] = ACTIONS(55),
    [sym_capitalized] = ACTIONS(53),
    [sym_system_task] = ACTIONS(53),
    [sym_signature_op] = ACTIONS(55),
    [sym_operator] = ACTIONS(55),
    [sym_punctuation] = ACTIONS(55),
    [anon_sym_LBRACE_DASH_POUND] = ACTIONS(53),
    [anon_sym_POUND_DASH_RBRACE] = ACTIONS(53),
    [aux_sym_number_token1] = ACTIONS(55),
    [aux_sym_number_token2] = ACTIONS(53),
    [aux_sym_number_token3] = ACTIONS(53),
    [aux_sym_number_token4] = ACTIONS(53),
    [aux_sym_number_token5] = ACTIONS(53),
    [aux_sym_number_token6] = ACTIONS(55),
    [sym_string] = ACTIONS(53),
    [sym_character] = ACTIONS(53),
    [sym_line_comment] = ACTIONS(55),
    [anon_sym_LBRACE_DASH] = ACTIONS(55),
  },
  [5] = {
    [ts_builtin_sym_end] = ACTIONS(57),
    [sym_identifier] = ACTIONS(59),
    [anon_sym_package] = ACTIONS(59),
    [anon_sym_import] = ACTIONS(59),
    [anon_sym_qualified] = ACTIONS(59),
    [anon_sym_action] = ACTIONS(59),
    [anon_sym_case] = ACTIONS(59),
    [anon_sym_class] = ACTIONS(59),
    [anon_sym_data] = ACTIONS(59),
    [anon_sym_deriving] = ACTIONS(59),
    [anon_sym_do] = ACTIONS(59),
    [anon_sym_else] = ACTIONS(59),
    [anon_sym_foreign] = ACTIONS(59),
    [anon_sym_if] = ACTIONS(59),
    [anon_sym_in] = ACTIONS(59),
    [anon_sym_coherent] = ACTIONS(59),
    [anon_sym_incoherent] = ACTIONS(59),
    [anon_sym_infix] = ACTIONS(59),
    [anon_sym_infixl] = ACTIONS(59),
    [anon_sym_infixr] = ACTIONS(59),
    [anon_sym_interface] = ACTIONS(59),
    [anon_sym_instance] = ACTIONS(59),
    [anon_sym_let] = ACTIONS(59),
    [anon_sym_letseq] = ACTIONS(59),
    [anon_sym_of] = ACTIONS(59),
    [anon_sym_primitive] = ACTIONS(59),
    [anon_sym_rules] = ACTIONS(59),
    [anon_sym_signature] = ACTIONS(59),
    [anon_sym_struct] = ACTIONS(59),
    [anon_sym_module] = ACTIONS(59),
    [anon_sym_then] = ACTIONS(59),
    [anon_sym_type] = ACTIONS(59),
    [anon_sym_valueOf] = ACTIONS(59),
    [anon_sym_stringOf] = ACTIONS(59),
    [anon_sym_verilog] = ACTIONS(59),
    [anon_sym_synthesize] = ACTIONS(59),
    [anon_sym_when] = ACTIONS(59),
    [anon_sym_where] = ACTIONS(59),
    [sym_capitalized] = ACTIONS(57),
    [sym_system_task] = ACTIONS(57),
    [sym_signature_op] = ACTIONS(59),
    [sym_operator] = ACTIONS(59),
    [sym_punctuation] = ACTIONS(59),
    [anon_sym_LBRACE_DASH_POUND] = ACTIONS(57),
    [anon_sym_POUND_DASH_RBRACE] = ACTIONS(57),
    [aux_sym_number_token1] = ACTIONS(59),
    [aux_sym_number_token2] = ACTIONS(57),
    [aux_sym_number_token3] = ACTIONS(57),
    [aux_sym_number_token4] = ACTIONS(57),
    [aux_sym_number_token5] = ACTIONS(57),
    [aux_sym_number_token6] = ACTIONS(59),
    [sym_string] = ACTIONS(57),
    [sym_character] = ACTIONS(57),
    [sym_line_comment] = ACTIONS(59),
    [anon_sym_LBRACE_DASH] = ACTIONS(59),
  },
  [6] = {
    [ts_builtin_sym_end] = ACTIONS(61),
    [sym_identifier] = ACTIONS(63),
    [anon_sym_package] = ACTIONS(63),
    [anon_sym_import] = ACTIONS(63),
    [anon_sym_qualified] = ACTIONS(63),
    [anon_sym_action] = ACTIONS(63),
    [anon_sym_case] = ACTIONS(63),
    [anon_sym_class] = ACTIONS(63),
    [anon_sym_data] = ACTIONS(63),
    [anon_sym_deriving] = ACTIONS(63),
    [anon_sym_do] = ACTIONS(63),
    [anon_sym_else] = ACTIONS(63),
    [anon_sym_foreign] = ACTIONS(63),
    [anon_sym_if] = ACTIONS(63),
    [anon_sym_in] = ACTIONS(63),
    [anon_sym_coherent] = ACTIONS(63),
    [anon_sym_incoherent] = ACTIONS(63),
    [anon_sym_infix] = ACTIONS(63),
    [anon_sym_infixl] = ACTIONS(63),
    [anon_sym_infixr] = ACTIONS(63),
    [anon_sym_interface] = ACTIONS(63),
    [anon_sym_instance] = ACTIONS(63),
    [anon_sym_let] = ACTIONS(63),
    [anon_sym_letseq] = ACTIONS(63),
    [anon_sym_of] = ACTIONS(63),
    [anon_sym_primitive] = ACTIONS(63),
    [anon_sym_rules] = ACTIONS(63),
    [anon_sym_signature] = ACTIONS(63),
    [anon_sym_struct] = ACTIONS(63),
    [anon_sym_module] = ACTIONS(63),
    [anon_sym_then] = ACTIONS(63),
    [anon_sym_type] = ACTIONS(63),
    [anon_sym_valueOf] = ACTIONS(63),
    [anon_sym_stringOf] = ACTIONS(63),
    [anon_sym_verilog] = ACTIONS(63),
    [anon_sym_synthesize] = ACTIONS(63),
    [anon_sym_when] = ACTIONS(63),
    [anon_sym_where] = ACTIONS(63),
    [sym_capitalized] = ACTIONS(61),
    [sym_system_task] = ACTIONS(61),
    [sym_signature_op] = ACTIONS(63),
    [sym_operator] = ACTIONS(63),
    [sym_punctuation] = ACTIONS(63),
    [anon_sym_LBRACE_DASH_POUND] = ACTIONS(61),
    [anon_sym_POUND_DASH_RBRACE] = ACTIONS(61),
    [aux_sym_number_token1] = ACTIONS(63),
    [aux_sym_number_token2] = ACTIONS(61),
    [aux_sym_number_token3] = ACTIONS(61),
    [aux_sym_number_token4] = ACTIONS(61),
    [aux_sym_number_token5] = ACTIONS(61),
    [aux_sym_number_token6] = ACTIONS(63),
    [sym_string] = ACTIONS(61),
    [sym_character] = ACTIONS(61),
    [sym_line_comment] = ACTIONS(63),
    [anon_sym_LBRACE_DASH] = ACTIONS(63),
  },
  [7] = {
    [ts_builtin_sym_end] = ACTIONS(65),
    [sym_identifier] = ACTIONS(67),
    [anon_sym_package] = ACTIONS(67),
    [anon_sym_import] = ACTIONS(67),
    [anon_sym_qualified] = ACTIONS(67),
    [anon_sym_action] = ACTIONS(67),
    [anon_sym_case] = ACTIONS(67),
    [anon_sym_class] = ACTIONS(67),
    [anon_sym_data] = ACTIONS(67),
    [anon_sym_deriving] = ACTIONS(67),
    [anon_sym_do] = ACTIONS(67),
    [anon_sym_else] = ACTIONS(67),
    [anon_sym_foreign] = ACTIONS(67),
    [anon_sym_if] = ACTIONS(67),
    [anon_sym_in] = ACTIONS(67),
    [anon_sym_coherent] = ACTIONS(67),
    [anon_sym_incoherent] = ACTIONS(67),
    [anon_sym_infix] = ACTIONS(67),
    [anon_sym_infixl] = ACTIONS(67),
    [anon_sym_infixr] = ACTIONS(67),
    [anon_sym_interface] = ACTIONS(67),
    [anon_sym_instance] = ACTIONS(67),
    [anon_sym_let] = ACTIONS(67),
    [anon_sym_letseq] = ACTIONS(67),
    [anon_sym_of] = ACTIONS(67),
    [anon_sym_primitive] = ACTIONS(67),
    [anon_sym_rules] = ACTIONS(67),
    [anon_sym_signature] = ACTIONS(67),
    [anon_sym_struct] = ACTIONS(67),
    [anon_sym_module] = ACTIONS(67),
    [anon_sym_then] = ACTIONS(67),
    [anon_sym_type] = ACTIONS(67),
    [anon_sym_valueOf] = ACTIONS(67),
    [anon_sym_stringOf] = ACTIONS(67),
    [anon_sym_verilog] = ACTIONS(67),
    [anon_sym_synthesize] = ACTIONS(67),
    [anon_sym_when] = ACTIONS(67),
    [anon_sym_where] = ACTIONS(67),
    [sym_capitalized] = ACTIONS(65),
    [sym_system_task] = ACTIONS(65),
    [sym_signature_op] = ACTIONS(67),
    [sym_operator] = ACTIONS(67),
    [sym_punctuation] = ACTIONS(67),
    [anon_sym_LBRACE_DASH_POUND] = ACTIONS(65),
    [anon_sym_POUND_DASH_RBRACE] = ACTIONS(65),
    [aux_sym_number_token1] = ACTIONS(67),
    [aux_sym_number_token2] = ACTIONS(65),
    [aux_sym_number_token3] = ACTIONS(65),
    [aux_sym_number_token4] = ACTIONS(65),
    [aux_sym_number_token5] = ACTIONS(65),
    [aux_sym_number_token6] = ACTIONS(67),
    [sym_string] = ACTIONS(65),
    [sym_character] = ACTIONS(65),
    [sym_line_comment] = ACTIONS(67),
    [anon_sym_LBRACE_DASH] = ACTIONS(67),
  },
  [8] = {
    [ts_builtin_sym_end] = ACTIONS(69),
    [sym_identifier] = ACTIONS(71),
    [anon_sym_package] = ACTIONS(71),
    [anon_sym_import] = ACTIONS(71),
    [anon_sym_qualified] = ACTIONS(71),
    [anon_sym_action] = ACTIONS(71),
    [anon_sym_case] = ACTIONS(71),
    [anon_sym_class] = ACTIONS(71),
    [anon_sym_data] = ACTIONS(71),
    [anon_sym_deriving] = ACTIONS(71),
    [anon_sym_do] = ACTIONS(71),
    [anon_sym_else] = ACTIONS(71),
    [anon_sym_foreign] = ACTIONS(71),
    [anon_sym_if] = ACTIONS(71),
    [anon_sym_in] = ACTIONS(71),
    [anon_sym_coherent] = ACTIONS(71),
    [anon_sym_incoherent] = ACTIONS(71),
    [anon_sym_infix] = ACTIONS(71),
    [anon_sym_infixl] = ACTIONS(71),
    [anon_sym_infixr] = ACTIONS(71),
    [anon_sym_interface] = ACTIONS(71),
    [anon_sym_instance] = ACTIONS(71),
    [anon_sym_let] = ACTIONS(71),
    [anon_sym_letseq] = ACTIONS(71),
    [anon_sym_of] = ACTIONS(71),
    [anon_sym_primitive] = ACTIONS(71),
    [anon_sym_rules] = ACTIONS(71),
    [anon_sym_signature] = ACTIONS(71),
    [anon_sym_struct] = ACTIONS(71),
    [anon_sym_module] = ACTIONS(71),
    [anon_sym_then] = ACTIONS(71),
    [anon_sym_type] = ACTIONS(71),
    [anon_sym_valueOf] = ACTIONS(71),
    [anon_sym_stringOf] = ACTIONS(71),
    [anon_sym_verilog] = ACTIONS(71),
    [anon_sym_synthesize] = ACTIONS(71),
    [anon_sym_when] = ACTIONS(71),
    [anon_sym_where] = ACTIONS(71),
    [sym_capitalized] = ACTIONS(73),
    [sym_system_task] = ACTIONS(69),
    [sym_signature_op] = ACTIONS(71),
    [sym_operator] = ACTIONS(71),
    [sym_punctuation] = ACTIONS(71),
    [anon_sym_LBRACE_DASH_POUND] = ACTIONS(69),
    [anon_sym_POUND_DASH_RBRACE] = ACTIONS(69),
    [aux_sym_number_token1] = ACTIONS(71),
    [aux_sym_number_token2] = ACTIONS(69),
    [aux_sym_number_token3] = ACTIONS(69),
    [aux_sym_number_token4] = ACTIONS(69),
    [aux_sym_number_token5] = ACTIONS(69),
    [aux_sym_number_token6] = ACTIONS(71),
    [sym_string] = ACTIONS(69),
    [sym_character] = ACTIONS(69),
    [sym_line_comment] = ACTIONS(71),
    [anon_sym_LBRACE_DASH] = ACTIONS(71),
  },
  [9] = {
    [ts_builtin_sym_end] = ACTIONS(75),
    [sym_identifier] = ACTIONS(77),
    [anon_sym_package] = ACTIONS(77),
    [anon_sym_import] = ACTIONS(77),
    [anon_sym_qualified] = ACTIONS(77),
    [anon_sym_action] = ACTIONS(77),
    [anon_sym_case] = ACTIONS(77),
    [anon_sym_class] = ACTIONS(77),
    [anon_sym_data] = ACTIONS(77),
    [anon_sym_deriving] = ACTIONS(77),
    [anon_sym_do] = ACTIONS(77),
    [anon_sym_else] = ACTIONS(77),
    [anon_sym_foreign] = ACTIONS(77),
    [anon_sym_if] = ACTIONS(77),
    [anon_sym_in] = ACTIONS(77),
    [anon_sym_coherent] = ACTIONS(77),
    [anon_sym_incoherent] = ACTIONS(77),
    [anon_sym_infix] = ACTIONS(77),
    [anon_sym_infixl] = ACTIONS(77),
    [anon_sym_infixr] = ACTIONS(77),
    [anon_sym_interface] = ACTIONS(77),
    [anon_sym_instance] = ACTIONS(77),
    [anon_sym_let] = ACTIONS(77),
    [anon_sym_letseq] = ACTIONS(77),
    [anon_sym_of] = ACTIONS(77),
    [anon_sym_primitive] = ACTIONS(77),
    [anon_sym_rules] = ACTIONS(77),
    [anon_sym_signature] = ACTIONS(77),
    [anon_sym_struct] = ACTIONS(77),
    [anon_sym_module] = ACTIONS(77),
    [anon_sym_then] = ACTIONS(77),
    [anon_sym_type] = ACTIONS(77),
    [anon_sym_valueOf] = ACTIONS(77),
    [anon_sym_stringOf] = ACTIONS(77),
    [anon_sym_verilog] = ACTIONS(77),
    [anon_sym_synthesize] = ACTIONS(77),
    [anon_sym_when] = ACTIONS(77),
    [anon_sym_where] = ACTIONS(77),
    [sym_capitalized] = ACTIONS(75),
    [sym_system_task] = ACTIONS(75),
    [sym_signature_op] = ACTIONS(77),
    [sym_operator] = ACTIONS(77),
    [sym_punctuation] = ACTIONS(77),
    [anon_sym_LBRACE_DASH_POUND] = ACTIONS(75),
    [anon_sym_POUND_DASH_RBRACE] = ACTIONS(75),
    [aux_sym_number_token1] = ACTIONS(77),
    [aux_sym_number_token2] = ACTIONS(75),
    [aux_sym_number_token3] = ACTIONS(75),
    [aux_sym_number_token4] = ACTIONS(75),
    [aux_sym_number_token5] = ACTIONS(75),
    [aux_sym_number_token6] = ACTIONS(77),
    [sym_string] = ACTIONS(75),
    [sym_character] = ACTIONS(75),
    [sym_line_comment] = ACTIONS(77),
    [anon_sym_LBRACE_DASH] = ACTIONS(77),
  },
  [10] = {
    [ts_builtin_sym_end] = ACTIONS(79),
    [sym_identifier] = ACTIONS(81),
    [anon_sym_package] = ACTIONS(81),
    [anon_sym_import] = ACTIONS(81),
    [anon_sym_qualified] = ACTIONS(81),
    [anon_sym_action] = ACTIONS(81),
    [anon_sym_case] = ACTIONS(81),
    [anon_sym_class] = ACTIONS(81),
    [anon_sym_data] = ACTIONS(81),
    [anon_sym_deriving] = ACTIONS(81),
    [anon_sym_do] = ACTIONS(81),
    [anon_sym_else] = ACTIONS(81),
    [anon_sym_foreign] = ACTIONS(81),
    [anon_sym_if] = ACTIONS(81),
    [anon_sym_in] = ACTIONS(81),
    [anon_sym_coherent] = ACTIONS(81),
    [anon_sym_incoherent] = ACTIONS(81),
    [anon_sym_infix] = ACTIONS(81),
    [anon_sym_infixl] = ACTIONS(81),
    [anon_sym_infixr] = ACTIONS(81),
    [anon_sym_interface] = ACTIONS(81),
    [anon_sym_instance] = ACTIONS(81),
    [anon_sym_let] = ACTIONS(81),
    [anon_sym_letseq] = ACTIONS(81),
    [anon_sym_of] = ACTIONS(81),
    [anon_sym_primitive] = ACTIONS(81),
    [anon_sym_rules] = ACTIONS(81),
    [anon_sym_signature] = ACTIONS(81),
    [anon_sym_struct] = ACTIONS(81),
    [anon_sym_module] = ACTIONS(81),
    [anon_sym_then] = ACTIONS(81),
    [anon_sym_type] = ACTIONS(81),
    [anon_sym_valueOf] = ACTIONS(81),
    [anon_sym_stringOf] = ACTIONS(81),
    [anon_sym_verilog] = ACTIONS(81),
    [anon_sym_synthesize] = ACTIONS(81),
    [anon_sym_when] = ACTIONS(81),
    [anon_sym_where] = ACTIONS(81),
    [sym_capitalized] = ACTIONS(79),
    [sym_system_task] = ACTIONS(79),
    [sym_signature_op] = ACTIONS(81),
    [sym_operator] = ACTIONS(81),
    [sym_punctuation] = ACTIONS(81),
    [anon_sym_LBRACE_DASH_POUND] = ACTIONS(79),
    [anon_sym_POUND_DASH_RBRACE] = ACTIONS(79),
    [aux_sym_number_token1] = ACTIONS(81),
    [aux_sym_number_token2] = ACTIONS(79),
    [aux_sym_number_token3] = ACTIONS(79),
    [aux_sym_number_token4] = ACTIONS(79),
    [aux_sym_number_token5] = ACTIONS(79),
    [aux_sym_number_token6] = ACTIONS(81),
    [sym_string] = ACTIONS(79),
    [sym_character] = ACTIONS(79),
    [sym_line_comment] = ACTIONS(81),
    [anon_sym_LBRACE_DASH] = ACTIONS(81),
  },
  [11] = {
    [ts_builtin_sym_end] = ACTIONS(83),
    [sym_identifier] = ACTIONS(85),
    [anon_sym_package] = ACTIONS(85),
    [anon_sym_import] = ACTIONS(85),
    [anon_sym_qualified] = ACTIONS(85),
    [anon_sym_action] = ACTIONS(85),
    [anon_sym_case] = ACTIONS(85),
    [anon_sym_class] = ACTIONS(85),
    [anon_sym_data] = ACTIONS(85),
    [anon_sym_deriving] = ACTIONS(85),
    [anon_sym_do] = ACTIONS(85),
    [anon_sym_else] = ACTIONS(85),
    [anon_sym_foreign] = ACTIONS(85),
    [anon_sym_if] = ACTIONS(85),
    [anon_sym_in] = ACTIONS(85),
    [anon_sym_coherent] = ACTIONS(85),
    [anon_sym_incoherent] = ACTIONS(85),
    [anon_sym_infix] = ACTIONS(85),
    [anon_sym_infixl] = ACTIONS(85),
    [anon_sym_infixr] = ACTIONS(85),
    [anon_sym_interface] = ACTIONS(85),
    [anon_sym_instance] = ACTIONS(85),
    [anon_sym_let] = ACTIONS(85),
    [anon_sym_letseq] = ACTIONS(85),
    [anon_sym_of] = ACTIONS(85),
    [anon_sym_primitive] = ACTIONS(85),
    [anon_sym_rules] = ACTIONS(85),
    [anon_sym_signature] = ACTIONS(85),
    [anon_sym_struct] = ACTIONS(85),
    [anon_sym_module] = ACTIONS(85),
    [anon_sym_then] = ACTIONS(85),
    [anon_sym_type] = ACTIONS(85),
    [anon_sym_valueOf] = ACTIONS(85),
    [anon_sym_stringOf] = ACTIONS(85),
    [anon_sym_verilog] = ACTIONS(85),
    [anon_sym_synthesize] = ACTIONS(85),
    [anon_sym_when] = ACTIONS(85),
    [anon_sym_where] = ACTIONS(85),
    [sym_capitalized] = ACTIONS(83),
    [sym_system_task] = ACTIONS(83),
    [sym_signature_op] = ACTIONS(85),
    [sym_operator] = ACTIONS(85),
    [sym_punctuation] = ACTIONS(85),
    [anon_sym_LBRACE_DASH_POUND] = ACTIONS(83),
    [anon_sym_POUND_DASH_RBRACE] = ACTIONS(83),
    [aux_sym_number_token1] = ACTIONS(85),
    [aux_sym_number_token2] = ACTIONS(83),
    [aux_sym_number_token3] = ACTIONS(83),
    [aux_sym_number_token4] = ACTIONS(83),
    [aux_sym_number_token5] = ACTIONS(83),
    [aux_sym_number_token6] = ACTIONS(85),
    [sym_string] = ACTIONS(83),
    [sym_character] = ACTIONS(83),
    [sym_line_comment] = ACTIONS(85),
    [anon_sym_LBRACE_DASH] = ACTIONS(85),
  },
};

static const uint16_t ts_small_parse_table[] = {
  [0] = 5,
    ACTIONS(87), 1,
      anon_sym_LBRACE_DASH,
    ACTIONS(89), 1,
      aux_sym_block_comment_token1,
    ACTIONS(93), 1,
      anon_sym_DASH_RBRACE,
    STATE(13), 2,
      sym_block_comment,
      aux_sym_block_comment_repeat1,
    ACTIONS(91), 3,
      anon_sym_LBRACE,
      anon_sym_RBRACE,
      anon_sym_DASH,
  [19] = 5,
    ACTIONS(87), 1,
      anon_sym_LBRACE_DASH,
    ACTIONS(95), 1,
      aux_sym_block_comment_token1,
    ACTIONS(99), 1,
      anon_sym_DASH_RBRACE,
    STATE(14), 2,
      sym_block_comment,
      aux_sym_block_comment_repeat1,
    ACTIONS(97), 3,
      anon_sym_LBRACE,
      anon_sym_RBRACE,
      anon_sym_DASH,
  [38] = 5,
    ACTIONS(101), 1,
      anon_sym_LBRACE_DASH,
    ACTIONS(104), 1,
      aux_sym_block_comment_token1,
    ACTIONS(110), 1,
      anon_sym_DASH_RBRACE,
    STATE(14), 2,
      sym_block_comment,
      aux_sym_block_comment_repeat1,
    ACTIONS(107), 3,
      anon_sym_LBRACE,
      anon_sym_RBRACE,
      anon_sym_DASH,
  [57] = 5,
    ACTIONS(87), 1,
      anon_sym_LBRACE_DASH,
    ACTIONS(112), 1,
      aux_sym_block_comment_token1,
    ACTIONS(116), 1,
      anon_sym_DASH_RBRACE,
    STATE(16), 2,
      sym_block_comment,
      aux_sym_block_comment_repeat1,
    ACTIONS(114), 3,
      anon_sym_LBRACE,
      anon_sym_RBRACE,
      anon_sym_DASH,
  [76] = 5,
    ACTIONS(87), 1,
      anon_sym_LBRACE_DASH,
    ACTIONS(95), 1,
      aux_sym_block_comment_token1,
    ACTIONS(118), 1,
      anon_sym_DASH_RBRACE,
    STATE(14), 2,
      sym_block_comment,
      aux_sym_block_comment_repeat1,
    ACTIONS(97), 3,
      anon_sym_LBRACE,
      anon_sym_RBRACE,
      anon_sym_DASH,
  [95] = 2,
    ACTIONS(75), 1,
      aux_sym_block_comment_token1,
    ACTIONS(77), 5,
      anon_sym_LBRACE_DASH,
      anon_sym_LBRACE,
      anon_sym_RBRACE,
      anon_sym_DASH,
      anon_sym_DASH_RBRACE,
  [106] = 2,
    ACTIONS(83), 1,
      aux_sym_block_comment_token1,
    ACTIONS(85), 5,
      anon_sym_LBRACE_DASH,
      anon_sym_LBRACE,
      anon_sym_RBRACE,
      anon_sym_DASH,
      anon_sym_DASH_RBRACE,
  [117] = 1,
    ACTIONS(120), 1,
      ts_builtin_sym_end,
};

static const uint32_t ts_small_parse_table_map[] = {
  [SMALL_STATE(12)] = 0,
  [SMALL_STATE(13)] = 19,
  [SMALL_STATE(14)] = 38,
  [SMALL_STATE(15)] = 57,
  [SMALL_STATE(16)] = 76,
  [SMALL_STATE(17)] = 95,
  [SMALL_STATE(18)] = 106,
  [SMALL_STATE(19)] = 117,
};

static const TSParseActionEntry ts_parse_actions[] = {
  [0] = {.entry = {.count = 0, .reusable = false}},
  [1] = {.entry = {.count = 1, .reusable = false}}, RECOVER(),
  [3] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_source_file, 0),
  [5] = {.entry = {.count = 1, .reusable = false}}, SHIFT(2),
  [7] = {.entry = {.count = 1, .reusable = false}}, SHIFT(4),
  [9] = {.entry = {.count = 1, .reusable = false}}, SHIFT(5),
  [11] = {.entry = {.count = 1, .reusable = true}}, SHIFT(2),
  [13] = {.entry = {.count = 1, .reusable = true}}, SHIFT(6),
  [15] = {.entry = {.count = 1, .reusable = false}}, SHIFT(7),
  [17] = {.entry = {.count = 1, .reusable = true}}, SHIFT(7),
  [19] = {.entry = {.count = 1, .reusable = false}}, SHIFT(12),
  [21] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_source_file, 1),
  [23] = {.entry = {.count = 1, .reusable = false}}, SHIFT(3),
  [25] = {.entry = {.count = 1, .reusable = true}}, SHIFT(3),
  [27] = {.entry = {.count = 1, .reusable = true}}, REDUCE(aux_sym_source_file_repeat1, 2),
  [29] = {.entry = {.count = 2, .reusable = false}}, REDUCE(aux_sym_source_file_repeat1, 2), SHIFT_REPEAT(3),
  [32] = {.entry = {.count = 2, .reusable = false}}, REDUCE(aux_sym_source_file_repeat1, 2), SHIFT_REPEAT(4),
  [35] = {.entry = {.count = 2, .reusable = false}}, REDUCE(aux_sym_source_file_repeat1, 2), SHIFT_REPEAT(5),
  [38] = {.entry = {.count = 2, .reusable = true}}, REDUCE(aux_sym_source_file_repeat1, 2), SHIFT_REPEAT(3),
  [41] = {.entry = {.count = 2, .reusable = true}}, REDUCE(aux_sym_source_file_repeat1, 2), SHIFT_REPEAT(6),
  [44] = {.entry = {.count = 2, .reusable = false}}, REDUCE(aux_sym_source_file_repeat1, 2), SHIFT_REPEAT(7),
  [47] = {.entry = {.count = 2, .reusable = true}}, REDUCE(aux_sym_source_file_repeat1, 2), SHIFT_REPEAT(7),
  [50] = {.entry = {.count = 2, .reusable = false}}, REDUCE(aux_sym_source_file_repeat1, 2), SHIFT_REPEAT(12),
  [53] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_package_keyword, 1),
  [55] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_package_keyword, 1),
  [57] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_keyword, 1),
  [59] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_keyword, 1),
  [61] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_pragma_delimiter, 1),
  [63] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_pragma_delimiter, 1),
  [65] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_number, 1),
  [67] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_number, 1),
  [69] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_package_ref, 1),
  [71] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_package_ref, 1),
  [73] = {.entry = {.count = 1, .reusable = true}}, SHIFT(10),
  [75] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_block_comment, 2),
  [77] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_block_comment, 2),
  [79] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_package_ref, 2, .production_id = 1),
  [81] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_package_ref, 2, .production_id = 1),
  [83] = {.entry = {.count = 1, .reusable = true}}, REDUCE(sym_block_comment, 3),
  [85] = {.entry = {.count = 1, .reusable = false}}, REDUCE(sym_block_comment, 3),
  [87] = {.entry = {.count = 1, .reusable = false}}, SHIFT(15),
  [89] = {.entry = {.count = 1, .reusable = true}}, SHIFT(13),
  [91] = {.entry = {.count = 1, .reusable = false}}, SHIFT(13),
  [93] = {.entry = {.count = 1, .reusable = false}}, SHIFT(9),
  [95] = {.entry = {.count = 1, .reusable = true}}, SHIFT(14),
  [97] = {.entry = {.count = 1, .reusable = false}}, SHIFT(14),
  [99] = {.entry = {.count = 1, .reusable = false}}, SHIFT(11),
  [101] = {.entry = {.count = 2, .reusable = false}}, REDUCE(aux_sym_block_comment_repeat1, 2), SHIFT_REPEAT(15),
  [104] = {.entry = {.count = 2, .reusable = true}}, REDUCE(aux_sym_block_comment_repeat1, 2), SHIFT_REPEAT(14),
  [107] = {.entry = {.count = 2, .reusable = false}}, REDUCE(aux_sym_block_comment_repeat1, 2), SHIFT_REPEAT(14),
  [110] = {.entry = {.count = 1, .reusable = false}}, REDUCE(aux_sym_block_comment_repeat1, 2),
  [112] = {.entry = {.count = 1, .reusable = true}}, SHIFT(16),
  [114] = {.entry = {.count = 1, .reusable = false}}, SHIFT(16),
  [116] = {.entry = {.count = 1, .reusable = false}}, SHIFT(17),
  [118] = {.entry = {.count = 1, .reusable = false}}, SHIFT(18),
  [120] = {.entry = {.count = 1, .reusable = true}},  ACCEPT_INPUT(),
};

#ifdef __cplusplus
extern "C" {
#endif
#ifdef _WIN32
#define extern __declspec(dllexport)
#endif

extern const TSLanguage *tree_sitter_bluespec_classic(void) {
  static const TSLanguage language = {
    .version = LANGUAGE_VERSION,
    .symbol_count = SYMBOL_COUNT,
    .alias_count = ALIAS_COUNT,
    .token_count = TOKEN_COUNT,
    .external_token_count = EXTERNAL_TOKEN_COUNT,
    .state_count = STATE_COUNT,
    .large_state_count = LARGE_STATE_COUNT,
    .production_id_count = PRODUCTION_ID_COUNT,
    .field_count = FIELD_COUNT,
    .max_alias_sequence_length = MAX_ALIAS_SEQUENCE_LENGTH,
    .parse_table = &ts_parse_table[0][0],
    .small_parse_table = ts_small_parse_table,
    .small_parse_table_map = ts_small_parse_table_map,
    .parse_actions = ts_parse_actions,
    .symbol_names = ts_symbol_names,
    .symbol_metadata = ts_symbol_metadata,
    .public_symbol_map = ts_symbol_map,
    .alias_map = ts_non_terminal_alias_map,
    .alias_sequences = &ts_alias_sequences[0][0],
    .lex_modes = ts_lex_modes,
    .lex_fn = ts_lex,
    .keyword_lex_fn = ts_lex_keywords,
    .keyword_capture_token = sym_identifier,
    .primary_state_ids = ts_primary_state_ids,
  };
  return &language;
}
#ifdef __cplusplus
}
#endif
