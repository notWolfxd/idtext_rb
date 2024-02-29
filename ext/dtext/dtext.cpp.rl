#include "dtext.h"
#include "url.h"

#include <algorithm>
#include <unordered_map>
#include <unordered_set>
#include <regex>

#ifdef DEBUG
#undef g_debug
#define STRINGIFY(x) XSTRINGIFY(x)
#define XSTRINGIFY(x) #x
#define g_debug(fmt, ...) fprintf(stderr, "\x1B[1;32mDEBUG\x1B[0m %-28.28s %-24.24s " fmt "\n", __FILE__ ":" STRINGIFY(__LINE__), __func__, ##__VA_ARGS__)
#else
#undef g_debug
#define g_debug(...)
#endif

static const size_t MAX_STACK_DEPTH = 512;

// Strip qualifier from tag: "Artoria Pendragon (Lancer) (Fate)" -> "Artoria Pendragon (Lancer)"
static const std::regex tag_qualifier_regex("[ _]\\([^)]+?\\)$");

// Permitted HTML attribute names.
static const std::unordered_map<std::string_view, const std::unordered_set<std::string_view>> permitted_attribute_names = {
  { "thead",    { "align" } },
  { "tbody",    { "align" } },
  { "tr",       { "align" } },
  { "td",       { "align", "colspan", "rowspan" } },
  { "th",       { "align", "colspan", "rowspan" } },
  { "col",      { "align", "span" } },
  { "colgroup", {} },
};

// Permitted HTML attribute values.
static const std::unordered_set<std::string_view> align_values = { "left", "center", "right", "justify" };
static const std::unordered_map<std::string_view, std::function<bool(std::string_view)>> permitted_attribute_values = {
  { "align",   [](auto value) { return align_values.find(value) != align_values.end(); } },
  { "span",    [](auto value) { return std::all_of(value.begin(), value.end(), isdigit); } },
  { "colspan", [](auto value) { return std::all_of(value.begin(), value.end(), isdigit); } },
  { "rowspan", [](auto value) { return std::all_of(value.begin(), value.end(), isdigit); } },
};

%%{
machine dtext;

access sm->;
variable p sm->p;
variable pe sm->pe;
variable eof sm->eof;
variable top sm->top;
variable ts sm->ts;
variable te sm->te;
variable act sm->act;
variable stack (sm->stack.data());

prepush {
  size_t len = sm->stack.size();

  if (len > MAX_STACK_DEPTH) {
    // Should never happen.
    throw DTextError("too many nested elements");
  }

  if (sm->top >= len) {
    g_debug("growing sm->stack %zi", len + 16);
    sm->stack.resize(len + 16, 0);
  }
}

action mark_a1 { sm->a1 = sm->p; }
action mark_a2 { sm->a2 = sm->p; }
action mark_b1 { sm->b1 = sm->p; }
action mark_b2 { sm->b2 = sm->p; }
action mark_c1 { sm->c1 = sm->p; }
action mark_c2 { sm->c2 = sm->p; }
action mark_d1 { sm->d1 = sm->p; }
action mark_d2 { sm->d2 = sm->p; }
action mark_e1 { sm->e1 = sm->p; }
action mark_e2 { sm->e2 = sm->p; }

action after_mention_boundary { is_mention_boundary(p[-1]) }
action mentions_enabled { sm->options.f_mentions }
action in_quote { dstack_is_open(sm, BLOCK_QUOTE) }
action in_expand { dstack_is_open(sm, BLOCK_EXPAND) }
action in_color { dstack_is_open(sm, BLOCK_COLOR) }
action save_tag_attribute { save_tag_attribute(sm, { sm->a1, sm->a2 }, { sm->b1, sm->b2 }); }

# Matches the beginning or the end of the string. The input string has null bytes prepended and appended to mark the ends of the string.
eos = '\0';

newline = '\n';
ws = ' ' | '\t';
eol = newline | eos;
blank_line = ws* eol;
blank_lines = blank_line{2,};

asciichar = 0x00..0x7F;
utf8char  = 0xC2..0xDF 0x80..0xBF
          | 0xE0..0xEF 0x80..0xBF 0x80..0xBF
          | 0xF0..0xF4 0x80..0xBF 0x80..0xBF 0x80..0xBF;
char = asciichar | utf8char;

# Characters that can't be the first or last character in a @-mention, or be contained in a URL.
# http://www.fileformat.info/info/unicode/category/Pe/list.htm
# http://www.fileformat.info/info/unicode/block/cjk_symbols_and_punctuation/list.htm
utf8_boundary_char =
  0xE2 0x9D 0xAD | # '❭' U+276D MEDIUM RIGHT-POINTING ANGLE BRACKET ORNAMENT
  0xE3 0x80 0x80 | # '　' U+3000 IDEOGRAPHIC SPACE (U+3000)
  0xE3 0x80 0x81 | # '、' U+3001 IDEOGRAPHIC COMMA (U+3001)
  0xE3 0x80 0x82 | # '。' U+3002 IDEOGRAPHIC FULL STOP (U+3002)
  0xE3 0x80 0x88 | # '〈' U+3008 LEFT ANGLE BRACKET (U+3008)
  0xE3 0x80 0x89 | # '〉' U+3009 RIGHT ANGLE BRACKET (U+3009)
  0xE3 0x80 0x8A | # '《' U+300A LEFT DOUBLE ANGLE BRACKET (U+300A)
  0xE3 0x80 0x8B | # '》' U+300B RIGHT DOUBLE ANGLE BRACKET (U+300B)
  0xE3 0x80 0x8C | # '「' U+300C LEFT CORNER BRACKET (U+300C)
  0xE3 0x80 0x8D | # '」' U+300D RIGHT CORNER BRACKET (U+300D)
  0xE3 0x80 0x8E | # '『' U+300E LEFT WHITE CORNER BRACKET (U+300E)
  0xE3 0x80 0x8F | # '』' U+300F RIGHT WHITE CORNER BRACKET (U+300F)
  0xE3 0x80 0x90 | # '【' U+3010 LEFT BLACK LENTICULAR BRACKET (U+3010)
  0xE3 0x80 0x91 | # '】' U+3011 RIGHT BLACK LENTICULAR BRACKET (U+3011)
  0xE3 0x80 0x94 | # '〔' U+3014 LEFT TORTOISE SHELL BRACKET (U+3014)
  0xE3 0x80 0x95 | # '〕' U+3015 RIGHT TORTOISE SHELL BRACKET (U+3015)
  0xE3 0x80 0x96 | # '〖' U+3016 LEFT WHITE LENTICULAR BRACKET (U+3016)
  0xE3 0x80 0x97 | # '〗' U+3017 RIGHT WHITE LENTICULAR BRACKET (U+3017)
  0xE3 0x80 0x98 | # '〘' U+3018 LEFT WHITE TORTOISE SHELL BRACKET (U+3018)
  0xE3 0x80 0x99 | # '〙' U+3019 RIGHT WHITE TORTOISE SHELL BRACKET (U+3019)
  0xE3 0x80 0x9A | # '〚' U+301A LEFT WHITE SQUARE BRACKET (U+301A)
  0xE3 0x80 0x9B | # '〛' U+301B RIGHT WHITE SQUARE BRACKET (U+301B)
  0xE3 0x80 0x9C | # '〜' U+301C WAVE DASH (U+301C)
  0xEF 0xBC 0x89 | # '）' U+FF09 FULLWIDTH RIGHT PARENTHESIS
  0xEF 0xBC 0xBD | # '］' U+FF3D FULLWIDTH RIGHT SQUARE BRACKET
  0xEF 0xBD 0x9D | # '｝' U+FF5D FULLWIDTH RIGHT CURLY BRACKET
  0xEF 0xBD 0xA0 | # '｠' U+FF60 FULLWIDTH RIGHT WHITE PARENTHESIS
  0xEF 0xBD 0xA3 ; # '｣' U+FF63 HALFWIDTH RIGHT CORNER BRACKET

nonspace = ^space - eos;
nonnewline = any - newline - eos - '\r';
nonbracket = ^']';
nonpipe = ^'|';
nonpipebracket = nonpipe & nonbracket;

# A bare @-mention (e.g. `@username`):
#
# * Can only appear after a space or one of the following characters: / " \ ( ) [ ] { }
# * Can't start or end with a punctuation character (either ASCII or Unicode).
# ** Exception: it can start with `_` or `.`, as long the next character is a non-punctuation character (this is to grandfather in names like @.Dank or @_cf).
# * Can't contain punctuation characters, except for . _ / ' - + !
# * Can't end in "'s" or "'d" (to allow `@kia'ra`, but not `@user's`).
# * The second character can't be '@' (to avoid emoticons like '@_@').
# * Must be at least two characters long.

mention_nonboundary_char = char - punct - space - eos - utf8_boundary_char;
mention_char = nonspace - (punct - [._/'\-+!]);
bare_username = ([_.]? mention_nonboundary_char mention_char* mention_nonboundary_char) - (char '@') - (char* '\'' [sd]);

bare_mention = ('@' when after_mention_boundary) (bare_username >mark_a1 @mark_a2);
delimited_mention = '<@' (nonspace nonnewline*) >mark_a1 %mark_a2 :>> '>';

http = 'http'i 's'i? '://';
subdomain = (utf8char | alnum | [_\-])+;
domain = subdomain ('.' subdomain)+;
port = ':' [0-9]+;

url_boundary_char = ["':;,.?] | utf8_boundary_char;
url_char = char - space - eos - utf8_boundary_char;
path = '/' (url_char - [?#<>[\]])*;
query = '?' (url_char - [#])*;
fragment = '#' (url_char - [#<>[\]])*;

bare_absolute_url = (http domain port? path? query? fragment?) - (char* url_boundary_char);
bare_relative_url = (path query? fragment? | fragment) - (char* url_boundary_char);

delimited_absolute_url = http nonspace+;
delimited_relative_url = [/#] nonspace*;

delimited_url = '<' delimited_absolute_url >mark_a1 %mark_a2 :>> '>';
basic_textile_link = '"' ^'"'+ >mark_a1 %mark_a2 '"' ':' (bare_absolute_url | bare_relative_url) >mark_b1 @mark_b2;
bracketed_textile_link = '"' ^'"'+ >mark_a1 %mark_a2 '"' ':[' (delimited_absolute_url | delimited_relative_url) >mark_b1 %mark_b2 :>> ']';

# XXX: internal markdown links aren't allowed to avoid parsing closing tags as links: `[b]foo[/b](bar)`.
markdown_link = '[' delimited_absolute_url >mark_a1 %mark_a2 :>> '](' nonnewline+ >mark_b1 %mark_b2 :>> ')';
html_link = '<a'i ws+ 'href="'i (delimited_absolute_url | delimited_relative_url) >mark_a1 %mark_a2 :>> '">' nonnewline+ >mark_b1 %mark_b2 :>> '</a>'i;

unquoted_bbcode_url = delimited_absolute_url | delimited_relative_url;
double_quoted_bbcode_url = '"' unquoted_bbcode_url >mark_b1 %mark_b2 :>> '"';
single_quoted_bbcode_url = "'" unquoted_bbcode_url >mark_b1 %mark_b2 :>> "'";
bbcode_url = double_quoted_bbcode_url | single_quoted_bbcode_url | unquoted_bbcode_url >mark_b1 %mark_b2;
named_bbcode_link   = '[url'i ws* '=' ws* (bbcode_url :>> ws* ']') ws* (nonnewline+ >mark_a1 %mark_a2 :>> ws* '[/url]'i);
unnamed_bbcode_link = '[url]'i ws* unquoted_bbcode_url >mark_a1 %mark_a2 ws* :>> '[/url]'i;

emoticon_tags = '|' alnum | ':|' | '|_|' | '||_||' | '\\||/' | '<|>_<|>' | '>:|' | '>|3' | '|w|' | ':{' | ':}';
wiki_prefix = alnum* >mark_a1 %mark_a2;
wiki_suffix = alnum* >mark_e1 %mark_e2;
wiki_target = (nonpipebracket* (nonpipebracket - space) | emoticon_tags) >mark_b1 %mark_b2;
wiki_anchor_id = ([A-Z] ([ _\-]* alnum+)*) >mark_c1 %mark_c2;
wiki_title = (ws* (nonpipebracket - space)+)* >mark_d1 %mark_d2;

basic_wiki_link = wiki_prefix '[[' ws* wiki_target ws* :>> ('#' wiki_anchor_id ws*)? ']]' wiki_suffix;
aliased_wiki_link = wiki_prefix '[[' ws* wiki_target ws* :>> ('#' wiki_anchor_id ws*)? '|' ws* wiki_title ws* ']]' wiki_suffix;

tag = (nonspace - [|{}])+ | ([~\-]? emoticon_tags);
tags = (tag (ws+ tag)*) >mark_b1 %mark_b2;
search_title = ((nonnewline* nonspace) -- '}')? >mark_c1 %mark_c2;
search_prefix = alnum* >mark_a1 %mark_a2;
search_suffix = alnum* >mark_d1 %mark_d2;

basic_post_search_link = search_prefix '{{' ws* tags ws* '}}' search_suffix;
aliased_post_search_link = search_prefix '{{' ws* tags ws* '|' ws* search_title ws* '}}' search_suffix;

id = (alnum{11} | digit+) >mark_a1 %mark_a2;
alnum_id = alnum+ >mark_a1 %mark_a2;
page = digit+ >mark_b1 %mark_b2;
dmail_key = (alnum | '=' | '-')+ >mark_b1 %mark_b2;

header_id = (alnum | [_/#!:&\-])+; # XXX '/', '#', '!', ':', and '&' are grandfathered in for old wiki versions.
header = 'h'i [123456] >mark_a1 %mark_a2 '.' >mark_b1 >mark_b2 ws*;
header_with_id = 'h'i [123456] >mark_a1 %mark_a2 '#' header_id >mark_b1 %mark_b2 '.' ws*;
aliased_expand = ('[expand'i (ws* '=' ws* | ws+) ((nonnewline - ']')* >mark_a1 %mark_a2) ']')
               | ('<expand'i (ws* '=' ws* | ws+) ((nonnewline - '>')* >mark_a1 %mark_a2) '>');
aliased_color = ('[color'i (ws* '=' ws* | ws+) ((nonnewline - ']')* >mark_a1 %mark_a2) ']')
               | ('<color'i (ws* '=' ws* | ws+) ((nonnewline - '>')* >mark_a1 %mark_a2) '>');

list_item = '*'+ >mark_a1 %mark_a2 ws+ nonnewline+ >mark_b1 %mark_b2;

hr = ws* ('[hr]'i | '<hr>'i) ws* eol+;

code_fence = ('```' ws* (alnum* >mark_a1 %mark_a2) ws* eol) (any* >mark_b1 %mark_b2) :>> (eol '```' ws* eol);

double_quoted_value = '"' (nonnewline+ >mark_b1 %mark_b2) :>> '"';
single_quoted_value = "'" (nonnewline+ >mark_b1 %mark_b2) :>> "'";
unquoted_value = alnum+ >mark_b1 %mark_b2;
tag_attribute_value = double_quoted_value | single_quoted_value | unquoted_value;
tag_attribute = ws+ (alnum+ >mark_a1 %mark_a2) ws* '=' ws* tag_attribute_value %save_tag_attribute;
tag_attributes = tag_attribute*;

open_spoilers = ('[spoiler'i 's'i? ']') | ('<spoiler'i 's'i? '>');
open_nodtext = '[nodtext]'i | '<nodtext>'i;
open_quote = '[quote]'i | '<quote>'i | '<blockquote>'i;
open_expand = '[expand]'i | '<expand>'i;
open_color = '[color]'i | '<color>'i;
open_code = '[code]'i | '<code>'i;
open_code_lang = '[code'i ws* '=' ws* (alnum+ >mark_a1 %mark_a2) ']' | '<code'i ws* '=' ws* (alnum+ >mark_a1 %mark_a2) '>';
open_table = '[table]'i | '<table>'i;
open_colgroup = '[colgroup'i tag_attributes :>> ']' | '<colgroup'i tag_attributes :>> '>';
open_col = '[col'i tag_attributes :>> ']' | '<col'i tag_attributes :>> '>';
open_thead = '[thead'i tag_attributes :>> ']' | '<thead'i tag_attributes :>> '>';
open_tbody = '[tbody'i tag_attributes :>> ']' | '<tbody'i tag_attributes :>> '>';
open_tr = '[tr'i tag_attributes :>> ']' | '<tr'i tag_attributes :>> '>';
open_th = '[th'i tag_attributes :>> ']' | '<th'i tag_attributes :>> '>';
open_td = '[td'i tag_attributes :>> ']' | '<td'i tag_attributes :>> '>';
open_br = '[br]'i | '<br>'i;

open_tn = '[tn]'i | '<tn>'i;
open_center = '[center]'i | '<center>'i;
open_b = '[b]'i | '<b>'i | '<strong>'i;
open_i = '[i]'i | '<i>'i | '<em>'i;
open_s = '[s]'i | '<s>'i;
open_u = '[u]'i | '<u>'i;

close_spoilers = ('[/spoiler'i 's'i? ']') | ('</spoiler'i 's'i? '>');
close_nodtext = '[/nodtext]'i | '</nodtext>'i;
close_quote = '[/quote'i (']' when in_quote) | '</quote'i ('>' when in_quote) | '</blockquote'i (']' when in_quote);
close_expand = '[/expand'i (']' when in_expand) | '</expand'i ('>' when in_expand);
close_color = '[/color'i (']' when in_color) | '</color'i ('>' when in_color);
close_code = '[/code]'i | '</code>'i;
close_table = '[/table]'i | '</table>'i;
close_colgroup = '[/colgroup]'i | '</colgroup>'i;
close_thead = '[/thead]'i | '</thead>'i;
close_tbody = '[/tbody]'i | '</tbody>'i;
close_tr = '[/tr]'i | '</tr>'i;
close_th = '[/th]'i | '</th>'i;
close_td = '[/td]'i | '</td>'i;
close_tn = '[/tn]'i | '</tn>'i;
close_center = '[/center]'i | '</center>'i;
close_b = '[/b]'i | '</b>'i | '</strong>'i;
close_i = '[/i]'i | '</i>'i | '</em>'i;
close_s = '[/s]'i | '</s>'i;
close_u = '[/u]'i | '</u>'i;

basic_inline := |*
  open_b  => { dstack_open_element(sm,  INLINE_B, "<strong>"); };
  close_b => { dstack_close_element(sm, INLINE_B); };
  open_i  => { dstack_open_element(sm,  INLINE_I, "<em>"); };
  close_i => { dstack_close_element(sm, INLINE_I); };
  open_s  => { dstack_open_element(sm,  INLINE_S, "<s>"); };
  close_s => { dstack_close_element(sm, INLINE_S); };
  open_u  => { dstack_open_element(sm,  INLINE_U, "<u>"); };
  close_u => { dstack_close_element(sm, INLINE_U); };
  eos;
  any => { append_html_escaped(sm, fc); };
*|;

inline := |*
  'post #'i id             => { append_id_link(sm, "post", "post", "/posts/", { sm->a1, sm->a2 }); };
  'forum #'i id            => { append_id_link(sm, "forum", "forum-post", "/forums/", { sm->a1, sm->a2 }); };
  'topic #'i id            => { append_id_link(sm, "topic", "forum-topic", "/forums/", { sm->a1, sm->a2 }); };
  'comment #'i id          => { append_id_link(sm, "comment", "comment", "/comments/", { sm->a1, sm->a2 }); };
  'dmail #'i id            => { append_id_link(sm, "dmail", "dmail", "/dmails/", { sm->a1, sm->a2 }); };
  'pool #'i id             => { append_id_link(sm, "pool", "pool", "/pools/", { sm->a1, sm->a2 }); };
  'user #'i id             => { append_id_link(sm, "user", "user", "/users/", { sm->a1, sm->a2 }); };
  'artist #'i id           => { append_id_link(sm, "artist", "artist", "/artists/", { sm->a1, sm->a2 }); };
  'user report #'i id           => { append_id_link(sm, "user report", "user-report", "/user_flags/", { sm->a1, sm->a2 }); };
  'tag alias #'i id            => { append_id_link(sm, "tag alias", "tag-alias", "/tag_aliases?id=", { sm->a1, sm->a2 }); };
  'tag implication #'i id      => { append_id_link(sm, "tag implication", "tag-implication", "/tag_implications?id=", { sm->a1, sm->a2 }); };
  'tag translation #'i id      => { append_id_link(sm, "tag translation", "tag-translation", "/tag_translations?id=", { sm->a1, sm->a2 }); };
  'book #'i id      => { append_id_link(sm, "book", "book", "/pools/", { sm->a1, sm->a2 }); };
  'series #'i id      => { append_id_link(sm, "series", "series", "/series/", { sm->a1, sm->a2 }); };
  'mod action #'i id       => { append_id_link(sm, "mod action", "mod-action", "/mod_actions?id=", { sm->a1, sm->a2 }); };
  'record #'i id         => { append_id_link(sm, "record", "user-record", "/user_records?id=", { sm->a1, sm->a2 }); };
  'wiki #'i id             => { append_id_link(sm, "wiki", "wiki-page", "/wiki/", { sm->a1, sm->a2 }); };

  'dmail #'i id '/' dmail_key => { append_dmail_key_link(sm); };

  'topic #'i id '/p'i page => { append_paged_link(sm, "topic #", "<a class=\"dtext-link dtext-id-link dtext-forum-topic-id-link\" href=\"", "/forums/", "?page="); };
  'pixiv #'i id '/p'i page => { append_paged_link(sm, "pixiv #", "<a rel=\"external nofollow noreferrer\" class=\"dtext-link dtext-id-link dtext-pixiv-id-link\" href=\"", "https://www.pixiv.net/artworks/", "#"); };

  basic_post_search_link => {
    append_post_search_link(sm, { sm->a1, sm->a2 }, { sm->b1, sm->b2 }, { sm->b1, sm->b2 }, { sm->d1, sm->d2 });
  };

  aliased_post_search_link => {
    append_post_search_link(sm, { sm->a1, sm->a2 }, { sm->b1, sm->b2 }, { sm->c1, sm->c2 }, { sm->d1, sm->d2 });
  };

  basic_wiki_link => {
    append_wiki_link(sm, { sm->a1, sm->a2 }, { sm->b1, sm->b2 }, { sm->c1, sm->c2 }, { sm->b1, sm->b2 }, { sm->e1, sm->e2 });
  };

  aliased_wiki_link => {
    append_wiki_link(sm, { sm->a1, sm->a2 }, { sm->b1, sm->b2 }, { sm->c1, sm->c2 }, { sm->d1, sm->d2 }, { sm->e1, sm->e2 });
  };

  basic_textile_link => {
    append_bare_named_url(sm, { sm->b1, sm->b2 + 1 }, { sm->a1, sm->a2 });
  };

  bracketed_textile_link | named_bbcode_link => {
    append_named_url(sm, { sm->b1, sm->b2 }, { sm->a1, sm->a2 });
  };

  markdown_link | html_link => {
    append_named_url(sm, { sm->a1, sm->a2 }, { sm->b1, sm->b2 });
  };

  bare_absolute_url => {
    append_bare_unnamed_url(sm, { sm->ts, sm->te });
  };

  delimited_url | unnamed_bbcode_link => {
    append_unnamed_url(sm, { sm->a1, sm->a2 });
  };

  bare_mention when mentions_enabled => {
    append_mention(sm, { sm->a1, sm->a2 + 1 });
  };

  delimited_mention when mentions_enabled => {
    g_debug("delimited mention: <@%.*s>", (int)(sm->a2 - sm->a1), sm->a1);
    append_mention(sm, { sm->a1, sm->a2 });
  };

  newline list_item => {
    g_debug("inline list");
    fexec sm->ts + 1;
    fret;
  };

  open_b  => { dstack_open_element(sm,  INLINE_B, "<strong>"); };
  close_b => { dstack_close_element(sm, INLINE_B); };
  open_i  => { dstack_open_element(sm,  INLINE_I, "<em>"); };
  close_i => { dstack_close_element(sm, INLINE_I); };
  open_s  => { dstack_open_element(sm,  INLINE_S, "<s>"); };
  close_s => { dstack_close_element(sm, INLINE_S); };
  open_u  => { dstack_open_element(sm,  INLINE_U, "<u>"); };
  close_u => { dstack_close_element(sm, INLINE_U); };

  open_tn => {
    dstack_open_element(sm, INLINE_TN, "<span class=\"tn\">");
  };

  newline* close_tn => {
    g_debug("inline [/tn]");

    if (dstack_check(sm, INLINE_TN)) {
      dstack_close_element(sm, INLINE_TN);
    } else if (dstack_close_element(sm, BLOCK_TN)) {
      fret;
    }
  };

  open_center => {
    dstack_open_element(sm, INLINE_CENTER, "<span class=\"center\">");
  };

  newline* close_center => {
    g_debug("inline [/center]");

    if (dstack_check(sm, INLINE_CENTER)) {
      dstack_close_element(sm, INLINE_CENTER);
    } else if (dstack_close_element(sm, BLOCK_CENTER)) {
      fret;
    }
  };

  open_br => {
    if (sm->header_mode) {
      append_html_escaped(sm, "<br>");
    } else {
      append(sm, "<br>");
    };
  };

  open_code blank_line? => {
    append_inline_code(sm);
    fcall code;
  };

  open_code_lang blank_line? => {
    append_inline_code(sm, { sm->a1, sm->a2 });
    fcall code;
  };

  newline code_fence => {
    dstack_close_leaf_blocks(sm);
    fexec sm->ts;
    fret;
  };

  newline ws* open_spoilers ws* eol => {
    dstack_close_leaf_blocks(sm);
    fexec sm->ts;
    fret;
  };

  open_spoilers => {
    dstack_open_element(sm, INLINE_SPOILER, "<span class=\"spoiler\">");
  };

  newline? close_spoilers => {
    if (dstack_is_open(sm, INLINE_SPOILER)) {
      dstack_close_element(sm, INLINE_SPOILER);
    } else if (dstack_is_open(sm, BLOCK_SPOILER)) {
      dstack_close_until(sm, BLOCK_SPOILER);
      fret;
    } else {
      append_html_escaped(sm, { sm->ts, sm->te });
    }
  };

  open_nodtext blank_line? => {
    dstack_open_element(sm, INLINE_NODTEXT, "");
    fcall nodtext;
  };
  
  # these are block level elements that should kick us out of the inline
  # scanner

  newline (open_code | open_code_lang | open_nodtext) => {
    dstack_close_leaf_blocks(sm);
    fexec sm->ts;
    fret;
  };

  newline (header | header_with_id) => {
    dstack_close_leaf_blocks(sm);
    fexec sm->ts;
    fret;
  };

  open_quote => {
    g_debug("inline [quote]");
    dstack_close_leaf_blocks(sm);
    fexec sm->ts;
    fret;
  };

  newline? close_quote ws* => {
    g_debug("inline [/quote]");
    dstack_close_until(sm, BLOCK_QUOTE);
    fret;
  };

  (open_expand | aliased_expand) => {
    g_debug("inline [expand]");
    dstack_close_leaf_blocks(sm);
    fexec sm->ts;
    fret;
  };

  newline? close_expand ws* => {
    g_debug("inline [/expand]");
    dstack_close_until(sm, BLOCK_EXPAND);
    fret;
  };

  (open_color | aliased_color) => {
    g_debug("inline [color]");
    dstack_close_leaf_blocks(sm);
    fexec sm->ts;
    fret;
  };

  newline? close_color ws* => {
    g_debug("inline [/color]");
    dstack_close_until(sm, BLOCK_COLOR);
    fret;
  };

  newline ws* open_table => {
    dstack_close_leaf_blocks(sm);
    fexec sm->ts;
    fret;
  };

  newline* close_th => {
    if (dstack_close_element(sm, BLOCK_TH)) {
      fret;
    }
  };

  newline* close_td => {
    if (dstack_close_element(sm, BLOCK_TD)) {
      fret;
    }
  };

  newline hr => {
    g_debug("inline [hr] (pos: %ld)", sm->ts - sm->pb);
    dstack_close_leaf_blocks(sm);
    fexec sm->ts;
    fret;
  };

  blank_lines => {
    g_debug("inline newline2");

    if (dstack_check(sm, BLOCK_P)) {
      dstack_rewind(sm);
    } else if (sm->header_mode) {
      dstack_close_leaf_blocks(sm);
    } else {
      dstack_close_list(sm);
    }

    if (sm->options.f_inline) {
      append(sm, " ");
    }

    fret;
  };

  newline => {
    g_debug("inline newline");

    if (sm->header_mode) {
      dstack_close_leaf_blocks(sm);
      fret;
    } else if (dstack_is_open(sm, BLOCK_UL)) {
      dstack_close_list(sm);
      fret;
    } else {
      append(sm, "<br>");
    }
  };

  '\r' => {
    append(sm, ' ');
  };

  eos;

  alnum+ | utf8char+ => {
    append(sm, std::string_view { sm->ts, sm->te });
  };

  any => {
    append_html_escaped(sm, fc);
  };
*|;

code := |*
  newline? close_code => {
    dstack_rewind(sm);
    fret;
  };

  eos;

  any => {
    append_html_escaped(sm, fc);
  };
*|;

nodtext := |*
  newline? close_nodtext => {
    dstack_rewind(sm);
    fret;
  };

  eos;

  any => {
    append_html_escaped(sm, fc);
  };
*|;

table := |*
  open_colgroup => {
    dstack_open_element(sm, BLOCK_COLGROUP, "colgroup", sm->tag_attributes);
  };

  close_colgroup => {
    dstack_close_element(sm, BLOCK_COLGROUP);
  };

  open_col => {
    dstack_open_element(sm, BLOCK_COL, "col", sm->tag_attributes);
    dstack_pop(sm); // XXX [col] has no end tag
  };

  open_thead => {
    dstack_open_element(sm, BLOCK_THEAD, "thead", sm->tag_attributes);
  };

  close_thead => {
    dstack_close_element(sm, BLOCK_THEAD);
  };

  open_tbody => {
    dstack_open_element(sm, BLOCK_TBODY, "tbody", sm->tag_attributes);
  };

  close_tbody => {
    dstack_close_element(sm, BLOCK_TBODY);
  };

  open_th => {
    dstack_open_element(sm, BLOCK_TH, "th", sm->tag_attributes);
    fcall inline;
  };

  open_tr => {
    dstack_open_element(sm, BLOCK_TR, "tr", sm->tag_attributes);
  };

  close_tr => {
    dstack_close_element(sm, BLOCK_TR);
  };

  open_td => {
    dstack_open_element(sm, BLOCK_TD, "td", sm->tag_attributes);
    fcall inline;
  };

  close_table => {
    if (dstack_close_element(sm, BLOCK_TABLE)) {
      fret;
    }
  };

  any;
*|;

main := |*
  header | header_with_id => {
    append_header(sm, *sm->a1, { sm->b1, sm->b2 });
    fcall inline;
  };

  open_quote space* => {
    dstack_close_leaf_blocks(sm);
    dstack_open_element(sm, BLOCK_QUOTE, "<blockquote>");
  };

  open_spoilers space* => {
    dstack_close_leaf_blocks(sm);
    dstack_open_element(sm, BLOCK_SPOILER, "<div class=\"spoiler\">");
  };

  open_code blank_line? => {
    append_block_code(sm);
    fcall code;
  };

  open_code_lang blank_line? => {
    append_block_code(sm, { sm->a1, sm->a2 });
    fcall code;
  };

  code_fence => {
    append_code_fence(sm, { sm->b1, sm->b2 }, { sm->a1, sm->a2 });
  };

  open_expand space* => {
    dstack_close_leaf_blocks(sm);
    dstack_open_element(sm, BLOCK_EXPAND, "<details>");
    append_block(sm, "<summary>Show</summary><div>");
  };

  aliased_expand space* => {
    g_debug("block [expand=]");
    dstack_close_leaf_blocks(sm);
    dstack_open_element(sm, BLOCK_EXPAND, "<details>");
    append_block(sm, "<summary>");
    append_block_html_escaped(sm, { sm->a1, sm->a2 });
    append_block(sm, "</summary><div>");
  };

  open_color space* => {
    dstack_close_leaf_blocks(sm);
    dstack_open_element(sm, BLOCK_COLOR, "<span style=\"color:#FF761C;\">");
  };

  aliased_color space* => {
    g_debug("block [color=]");
    dstack_close_leaf_blocks(sm);
    dstack_open_element(sm, BLOCK_COLOR, "<span style=\"color:");
    append_block_html_escaped(sm, { sm->a1, sm->a2 });
    append_block(sm, "\">");
  };

  open_nodtext blank_line? => {
    dstack_close_leaf_blocks(sm);
    dstack_open_element(sm, BLOCK_NODTEXT, "<p>");
    fcall nodtext;
  };

  ws* open_table => {
    dstack_close_leaf_blocks(sm);
    dstack_open_element(sm, BLOCK_TABLE, "<table class=\"highlightable\">");
    fcall table;
  };

  open_tn => {
    dstack_open_element(sm, BLOCK_TN, "<p class=\"tn\">");
    fcall inline;
  };

  open_center => {
    dstack_open_element(sm, BLOCK_CENTER, "<p class=\"center\">");
    fcall inline;
  };

  hr => {
    g_debug("write '<hr>' (pos: %ld)", sm->ts - sm->pb);
    append_block(sm, "<hr>");
  };

  list_item => {
    g_debug("block list");
    dstack_open_list(sm, sm->a2 - sm->a1);
    fexec sm->b1;
    fcall inline;
  };

  blank_line+ => {
    g_debug("block blank line(s)");
  };

  any => {
    g_debug("block char");
    fhold;

    if (sm->dstack.empty() || dstack_check(sm, BLOCK_QUOTE) || dstack_check(sm, BLOCK_SPOILER) || dstack_check(sm, BLOCK_EXPAND) || dstack_check(sm, BLOCK_COLOR)) {
      dstack_open_element(sm, BLOCK_P, "<p>");
    }

    fcall inline;
  };
*|;

}%%

%% write data;

static void dstack_push(StateMachine * sm, element_t element) {
  sm->dstack.push_back(element);
}

static element_t dstack_pop(StateMachine * sm) {
  if (sm->dstack.empty()) {
    g_debug("dstack pop empty stack");
    return DSTACK_EMPTY;
  } else {
    auto element = sm->dstack.back();
    sm->dstack.pop_back();
    return element;
  }
}

static element_t dstack_peek(const StateMachine * sm) {
  return sm->dstack.empty() ? DSTACK_EMPTY : sm->dstack.back();
}

static bool dstack_check(const StateMachine * sm, element_t expected_element) {
  return dstack_peek(sm) == expected_element;
}

// Return true if the given tag is currently open.
static bool dstack_is_open(const StateMachine * sm, element_t element) {
  return std::find(sm->dstack.begin(), sm->dstack.end(), element) != sm->dstack.end();
}

static int dstack_count(const StateMachine * sm, element_t element) {
  return std::count(sm->dstack.begin(), sm->dstack.end(), element);
}

static bool is_internal_url(StateMachine * sm, const std::string_view url) {
  if (url.starts_with("/")) {
    return true;
  } else if (sm->options.domain.empty() || url.empty()) {
    return false;
  } else {
    // Matches the domain name part of a URL.
    static const std::regex url_regex("^https?://(?:[^/?#]*@)?([^/?#:]+)", std::regex_constants::icase);

    std::match_results<std::string_view::const_iterator> matches;
    std::regex_search(url.begin(), url.end(), matches, url_regex);
    return matches[1] == sm->options.domain;
  }
}

static void append(StateMachine * sm, const auto c) {
  sm->output += c;
}

static void append(StateMachine * sm, const char * a, const char * b) {
  append(sm, std::string_view(a, b));
}

static void append_html_escaped(StateMachine * sm, char s) {
  switch (s) {
    case '<': append(sm, "&lt;"); break;
    case '>': append(sm, "&gt;"); break;
    case '&': append(sm, "&amp;"); break;
    case '"': append(sm, "&quot;"); break;
    default:  append(sm, s);
  }
}

static void append_html_escaped(StateMachine * sm, const std::string_view string) {
  for (const unsigned char c : string) {
    append_html_escaped(sm, c);
  }
}

static void append_uri_escaped(StateMachine * sm, const std::string_view string) {
  static const char hex[] = "0123456789ABCDEF";

  for (const unsigned char c : string) {
    if ((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '-' || c == '_' || c == '.' || c == '~') {
      append(sm, c);
    } else {
      append(sm, '%');
      append(sm, hex[c >> 4]);
      append(sm, hex[c & 0x0F]);
    }
  }
}

static void append_relative_url(StateMachine * sm, const auto url) {
  if ((url[0] == '/' || url[0] == '#') && !sm->options.base_url.empty()) {
    append_html_escaped(sm, sm->options.base_url);
  }

  append_html_escaped(sm, url);
}

static void append_absolute_link(StateMachine * sm, const std::string_view url, const std::string_view title, bool internal_url, bool escape_title) {
  if (internal_url) {
    append(sm, "<a class=\"dtext-link\" href=\"");
  } else if (url == title) {
    append(sm, "<a rel=\"external nofollow noreferrer\" class=\"dtext-link dtext-external-link\" href=\"");
  } else {
    append(sm, "<a rel=\"external nofollow noreferrer\" class=\"dtext-link dtext-external-link dtext-named-external-link\" href=\"");
  }

  append_html_escaped(sm, url);
  append(sm, "\">");

  if (escape_title) {
    append_html_escaped(sm, title);
  } else {
    append(sm, title);
  }

  append(sm, "</a>");
}

static void append_mention(StateMachine * sm, const std::string_view name) {
  append(sm, "<a class=\"dtext-link dtext-user-mention-link\" data-user-name=\"");
  append_html_escaped(sm, name);
  append(sm, "\" href=\"");
  append_relative_url(sm, "/users?name=");
  append_uri_escaped(sm, name);
  append(sm, "\">@");
  append_html_escaped(sm, name);
  append(sm, "</a>");
}

static void append_id_link(StateMachine * sm, const char * title, const char * id_name, const char * url, const std::string_view id) {
  if (url[0] == '/') {
    append(sm, "<a class=\"dtext-link dtext-id-link dtext-");
    append(sm, id_name);
    append(sm, "-id-link\" href=\"");
    append_relative_url(sm, url);
  } else {
    append(sm, "<a rel=\"external nofollow noreferrer\" class=\"dtext-link dtext-id-link dtext-");
    append(sm, id_name);
    append(sm, "-id-link\" href=\"");
    append_html_escaped(sm, url);
  }

  append_uri_escaped(sm, id);
  append(sm, "\">");
  append(sm, title);
  append(sm, " #");
  append_html_escaped(sm, id);
  append(sm, "</a>");
}

static void append_bare_unnamed_url(StateMachine * sm, const std::string_view url) {
  auto [trimmed_url, leftovers] = trim_url(url);
  append_unnamed_url(sm, trimmed_url);
  append_html_escaped(sm, leftovers);
}

static void append_unnamed_url(StateMachine * sm, const std::string_view url) {
  DText::URL parsed_url(url);

  if (sm->options.internal_domains.find(std::string(parsed_url.domain)) != sm->options.internal_domains.end()) {
    append_internal_url(sm, parsed_url);
  } else {
    append_absolute_link(sm, url, url, parsed_url.domain == sm->options.domain);
  }
}

static void append_internal_url(StateMachine * sm, const DText::URL& url) {
  auto path_components = url.path_components();
  auto query = url.query;
  auto fragment = url.fragment;

  if (path_components.size() == 2) {
    auto controller = path_components.at(0);
    auto id = path_components.at(1);

    if (!id.empty() && std::all_of(id.begin(), id.end(), ::isdigit)) {
      if (controller == "post" && fragment.empty()) {
        // https://danbooru.donmai.us/posts/6000000#comment_2288996
        return append_id_link(sm, "post", "post", "/posts/", id);
      } else if (controller == "pool" && query.empty()) {
        // https://danbooru.donmai.us/pools/903?page=2
        return append_id_link(sm, "pool", "pool", "/pools/", id);
      } else if (controller == "comment") {
        return append_id_link(sm, "comment", "comment", "/comments/", id);
      } else if (controller == "forum") {
        return append_id_link(sm, "forum", "forum-post", "/forums/", id);
      } else if (controller == "forum" && query.empty() && fragment.empty()) {
        // https://danbooru.donmai.us/forum_topics/1234?page=2
        // https://danbooru.donmai.us/forum_topics/1234#forum_post_5678
        return append_id_link(sm, "topic", "forum-topic", "/forums/", id);
      } else if (controller == "user") {
        return append_id_link(sm, "user", "user", "/users/", id);
      } else if (controller == "artist") {
        return append_id_link(sm, "artist", "artist", "/artists/", id);
      } else if (controller == "wiki" && fragment.empty()) {
        // http://danbooru.donmai.us/wiki_pages/10933#dtext-self-upload
        return append_id_link(sm, "wiki", "wiki-page", "/wiki/", id);
      }
    } else if (controller == "wiki" && fragment.empty()) {
      return append_wiki_link(sm, {}, id, {}, id, {});
    }
  } else if (path_components.size() >= 3) {
    // http://danbooru.donmai.us/post/show/1234/touhou
    auto controller = path_components.at(0);
    auto action = path_components.at(1);
    auto id = path_components.at(2);

    if (!id.empty() && std::all_of(id.begin(), id.end(), ::isdigit)) {
      if (controller == "post" && action == "show") {
        return append_id_link(sm, "post", "post", "/posts/", id);
      }
    }
  }

  append_absolute_link(sm, url.url, url.url, url.domain == sm->options.domain);
}

static void append_named_url(StateMachine * sm, const std::string_view url, const std::string_view title) {
  auto parsed_title = sm->parse_basic_inline(title);

  // protocol-relative url; treat `//example.com` like `http://example.com`
  if (url.size() > 2 && url.starts_with("//")) {
    auto full_url = "http:" + std::string(url);
    append_absolute_link(sm, full_url, parsed_title, is_internal_url(sm, full_url), false);
  } else if (url[0] == '/' || url[0] == '#') {
    append(sm, "<a class=\"dtext-link\" href=\"");
    append_relative_url(sm, url);
    append(sm, "\">");
    append(sm, parsed_title);
    append(sm, "</a>");
  } else if (url == title) {
    append_unnamed_url(sm, url);
  } else {
    append_absolute_link(sm, url, parsed_title, is_internal_url(sm, url), false);
  }
}

static void append_bare_named_url(StateMachine * sm, const std::string_view url, std::string_view title) {
  auto [trimmed_url, leftovers] = trim_url(url);
  append_named_url(sm, trimmed_url, title);
  append_html_escaped(sm, leftovers);
}

static void append_post_search_link(StateMachine * sm, const std::string_view prefix, const std::string_view search, const std::string_view title, const std::string_view suffix) {
  auto normalized_title = std::string(title);

  append(sm, "<a class=\"dtext-link dtext-post-search-link\" href=\"");
  append_relative_url(sm, "/post?tags=");
  append_uri_escaped(sm, search);
  append(sm, "\">");

  // 19{{60s}} -> {{60s|1960s}}
  if (!prefix.empty()) {
    normalized_title.insert(0, prefix);
  }

  // {{pokemon_(creature)|}} -> {{pokemon_(creature)|pokemon}}
  if (title.empty()) {
    std::regex_replace(std::back_inserter(normalized_title), search.begin(), search.end(), tag_qualifier_regex, "");
  }

  // {{cat}}s -> {{cat|cats}}
  if (!suffix.empty()) {
    normalized_title.append(suffix);
  }

  append_html_escaped(sm, normalized_title);
  append(sm, "</a>");

  clear_matches(sm);
}

static void append_wiki_link(StateMachine * sm, const std::string_view prefix, const std::string_view tag, const std::string_view anchor, const std::string_view title, const std::string_view suffix) {
  auto normalized_tag = std::string(tag);
  auto title_string = std::string(title);

  // "Kantai Collection" -> "kantai_collection"
  std::transform(normalized_tag.cbegin(), normalized_tag.cend(), normalized_tag.begin(), [](unsigned char c) { return c == ' ' ? '_' : std::tolower(c); });

  // [[2019]] -> [[~2019]]
  if (std::all_of(normalized_tag.cbegin(), normalized_tag.cend(), ::isdigit)) {
    normalized_tag.insert(0, "~");
  }

  // Pipe trick: [[Kaga (Kantai Collection)|]] -> [[kaga_(kantai_collection)|Kaga]]
  if (title_string.empty()) {
    std::regex_replace(std::back_inserter(title_string), tag.cbegin(), tag.cend(), tag_qualifier_regex, "");
  }

  // 19[[60s]] -> [[60s|1960s]]
  if (!prefix.empty()) {
    title_string.insert(0, prefix);
  }

  // [[cat]]s -> [[cat|cats]]
  if (!suffix.empty()) {
    title_string.append(suffix);
  }

  append(sm, "<a class=\"dtext-link dtext-wiki-link\" href=\"");
  append_relative_url(sm, "/wiki/");
  append_uri_escaped(sm, normalized_tag);

  if (!anchor.empty()) {
    std::string normalized_anchor(anchor);
    std::transform(normalized_anchor.begin(), normalized_anchor.end(), normalized_anchor.begin(), [](char c) { return isalnum(c) ? tolower(c) : '-'; });
    append_html_escaped(sm, "#dtext-");
    append_html_escaped(sm, normalized_anchor);
  }

  append(sm, "\">");
  append_html_escaped(sm, title_string);
  append(sm, "</a>");

  sm->wiki_pages.insert(std::string(tag));

  clear_matches(sm);
}

static void append_paged_link(StateMachine * sm, const char * title, const char * tag, const char * href, const char * param) {
  append(sm, tag);
  append_relative_url(sm, href);
  append(sm, sm->a1, sm->a2);
  append(sm, param);
  append(sm, sm->b1, sm->b2);
  append(sm, "\">");
  append(sm, title);
  append(sm, sm->a1, sm->a2);
  append(sm, "/p");
  append(sm, sm->b1, sm->b2);
  append(sm, "</a>");
}

static void append_dmail_key_link(StateMachine * sm) {
  append(sm, "<a class=\"dtext-link dtext-id-link dtext-dmail-id-link\" href=\"");
  append_relative_url(sm, "/dmails/");
  append(sm, sm->a1, sm->a2);
  append(sm, "?key=");
  append_uri_escaped(sm, { sm->b1, sm->b2 });
  append(sm, "\">");
  append(sm, "dmail #");
  append(sm, sm->a1, sm->a2);
  append(sm, "</a>");
}

static void append_code_fence(StateMachine * sm, const std::string_view code, const std::string_view language) {
  if (language.empty()) {
    append_block(sm, "<pre>");
    append_html_escaped(sm, code);
    append_block(sm, "</pre>");
  } else {
    append_block(sm, "<pre class=\"language-");
    append_html_escaped(sm, language);
    append_block(sm, "\">");
    append_html_escaped(sm, code);
    append_block(sm, "</pre>");
  }
}

static void append_inline_code(StateMachine * sm, const std::string_view language = {}) {
  if (language.empty()) {
    dstack_open_element(sm, INLINE_CODE, "<code>");
  } else {
    dstack_open_element(sm, INLINE_CODE, "<code class=\"language-");
    append_html_escaped(sm, language);
    append(sm, "\">");
  }
}

static void append_block_code(StateMachine * sm, const std::string_view language = {}) {
  dstack_close_leaf_blocks(sm);

  if (language.empty()) {
    dstack_open_element(sm, BLOCK_CODE, "<pre>");
  } else {
    dstack_open_element(sm, BLOCK_CODE, "<pre class=\"language-");
    append_html_escaped(sm, language);
    append(sm, "\">");
  }
}

static void append_header(StateMachine * sm, char header, const std::string_view id) {
  static element_t blocks[] = { BLOCK_H1, BLOCK_H2, BLOCK_H3, BLOCK_H4, BLOCK_H5, BLOCK_H6 };
  element_t block = blocks[header - '1'];

  if (id.empty()) {
    dstack_open_element(sm, block, "<h");
    append_block(sm, header);
    append_block(sm, ">");
  } else {
    auto normalized_id = std::string(id);
    std::transform(id.begin(), id.end(), normalized_id.begin(), [](char c) { return isalnum(c) ? tolower(c) : '-'; });

    dstack_open_element(sm, block, "<h");
    append_block(sm, header);
    append_block(sm, " id=\"dtext-");
    append_block(sm, normalized_id);
    append_block(sm, "\">");
  }

  sm->header_mode = true;
}

static void append_block(StateMachine * sm, const auto s) {
  if (!sm->options.f_inline) {
    append(sm, s);
  }
}

static void append_block_html_escaped(StateMachine * sm, const std::string_view string) {
  if (!sm->options.f_inline) {
    append_html_escaped(sm, string);
  }
}

static void append_closing_p(StateMachine * sm) {
  g_debug("append closing p");

  if (sm->output.size() > 4 && sm->output.ends_with("<br>")) {
    g_debug("trim last <br>");
    sm->output.resize(sm->output.size() - 4);
  }

  if (sm->output.size() > 3 && sm->output.ends_with("<p>")) {
    g_debug("trim last <p>");
    sm->output.resize(sm->output.size() - 3);
    return;
  }

  append_block(sm, "</p>");
}

static void dstack_open_element(StateMachine * sm, element_t type, const char * html) {
  g_debug("opening %s", html);

  dstack_push(sm, type);

  if (type >= INLINE) {
    append(sm, html);
  } else {
    append_block(sm, html);
  }
}

static void dstack_open_element(StateMachine * sm, element_t type, std::string_view tag_name, const StateMachine::TagAttributes& tag_attributes) {
  dstack_push(sm, type);
  append_block(sm, "<");
  append_block(sm, tag_name);

  auto& permitted_names = permitted_attribute_names.at(tag_name);
  for (auto& [name, value] : tag_attributes) {
    if (permitted_names.find(name) != permitted_names.end()) {
      auto validate_value = permitted_attribute_values.at(name);

      if (validate_value(value)) {
        append_block(sm, " ");
        append_block_html_escaped(sm, name);
        append_block(sm, "=\"");
        append_block_html_escaped(sm, value);
        append_block(sm, "\"");
      }
    }
  }

  append_block(sm, ">");
  clear_tag_attributes(sm);
}

static bool dstack_close_element(StateMachine * sm, element_t type) {
  if (dstack_check(sm, type)) {
    dstack_rewind(sm);
    return true;
  } else if (type >= INLINE && dstack_peek(sm) >= INLINE) {
    g_debug("out-of-order close %s; closing %s instead", element_names[type], element_names[dstack_peek(sm)]);
    dstack_rewind(sm);
    return true;
  } else if (type >= INLINE) {
    g_debug("out-of-order closing %s", element_names[type]);
    append_html_escaped(sm, { sm->ts, sm->te });
    return false;
  } else {
    g_debug("out-of-order closing %s", element_names[type]);
    append_block_html_escaped(sm, { sm->ts, sm->te });
    return false;
  }
}

// Close the last open tag.
static void dstack_rewind(StateMachine * sm) {
  element_t element = dstack_pop(sm);
  g_debug("dstack rewind %s", element_names[element]);

  switch(element) {
    case BLOCK_P: append_closing_p(sm); break;
    case INLINE_SPOILER: append(sm, "</span>"); break;
    case BLOCK_SPOILER: append_block(sm, "</div>"); break;
    case BLOCK_QUOTE: append_block(sm, "</blockquote>"); break;
    case BLOCK_EXPAND: append_block(sm, "</div></details>"); break;
    case BLOCK_COLOR: append_block(sm, "</span>"); break;
    case BLOCK_NODTEXT: append_block(sm, "</p>"); break;
    case BLOCK_CODE: append_block(sm, "</pre>"); break;
    case BLOCK_TD: append_block(sm, "</td>"); break;
    case BLOCK_TH: append_block(sm, "</th>"); break;

    case INLINE_NODTEXT: break;
    case INLINE_B: append(sm, "</strong>"); break;
    case INLINE_I: append(sm, "</em>"); break;
    case INLINE_U: append(sm, "</u>"); break;
    case INLINE_S: append(sm, "</s>"); break;
    case INLINE_TN: append(sm, "</span>"); break;
    case INLINE_CENTER: append(sm, "</span>"); break;
    case INLINE_CODE: append(sm, "</code>"); break;

    case BLOCK_TN: append_closing_p(sm); break;
    case BLOCK_CENTER: append_closing_p(sm); break;
    case BLOCK_TABLE: append_block(sm, "</table>"); break;
    case BLOCK_COLGROUP: append_block(sm, "</colgroup>"); break;
    case BLOCK_THEAD: append_block(sm, "</thead>"); break;
    case BLOCK_TBODY: append_block(sm, "</tbody>"); break;
    case BLOCK_TR: append_block(sm, "</tr>"); break;
    case BLOCK_UL: append_block(sm, "</ul>"); break;
    case BLOCK_LI: append_block(sm, "</li>"); break;
    case BLOCK_H6: append_block(sm, "</h6>"); sm->header_mode = false; break;
    case BLOCK_H5: append_block(sm, "</h5>"); sm->header_mode = false; break;
    case BLOCK_H4: append_block(sm, "</h4>"); sm->header_mode = false; break;
    case BLOCK_H3: append_block(sm, "</h3>"); sm->header_mode = false; break;
    case BLOCK_H2: append_block(sm, "</h2>"); sm->header_mode = false; break;
    case BLOCK_H1: append_block(sm, "</h1>"); sm->header_mode = false; break;

    // Should never happen.
    case INLINE: break;
    case DSTACK_EMPTY: break;
  } 
}

// container blocks: [spoiler], [quote], [expand], [tn], [center], [color]
// leaf blocks: [nodtext], [code], [table], [td]?, [th]?, <h1>, <p>, <li>, <ul>
static void dstack_close_leaf_blocks(StateMachine * sm) {
  g_debug("dstack close leaf blocks");

  while (!sm->dstack.empty() && !dstack_check(sm, BLOCK_QUOTE) && !dstack_check(sm, BLOCK_SPOILER) && !dstack_check(sm, BLOCK_EXPAND) && !dstack_check(sm, BLOCK_TN) && !dstack_check(sm, BLOCK_CENTER) && !dstack_check(sm, BLOCK_COLOR)) {
    dstack_rewind(sm);
  }
}

// Close all open tags up to and including the given tag.
static void dstack_close_until(StateMachine * sm, element_t element) {
  while (!sm->dstack.empty() && !dstack_check(sm, element)) {
    dstack_rewind(sm);
  }

  dstack_rewind(sm);
}

// Close all remaining open tags.
static void dstack_close_all(StateMachine * sm) {
  while (!sm->dstack.empty()) {
    dstack_rewind(sm);
  }
}

static void dstack_open_list(StateMachine * sm, int depth) {
  g_debug("open list");

  if (dstack_is_open(sm, BLOCK_LI)) {
    dstack_close_until(sm, BLOCK_LI);
  } else {
    dstack_close_leaf_blocks(sm);
  }

  while (dstack_count(sm, BLOCK_UL) < depth) {
    dstack_open_element(sm, BLOCK_UL, "<ul>");
  }

  while (dstack_count(sm, BLOCK_UL) > depth) {
    dstack_close_until(sm, BLOCK_UL);
  }

  dstack_open_element(sm, BLOCK_LI, "<li>");
}

static void dstack_close_list(StateMachine * sm) {
  while (dstack_is_open(sm, BLOCK_UL)) {
    dstack_close_until(sm, BLOCK_UL);
  }
}

static void save_tag_attribute(StateMachine * sm, const std::string_view name, const std::string_view value) {
  sm->tag_attributes[name] = value;
}

static void clear_tag_attributes(StateMachine * sm) {
  sm->tag_attributes.clear();
}

static void clear_matches(StateMachine * sm) {
  sm->a1 = NULL;
  sm->a2 = NULL;
  sm->b1 = NULL;
  sm->b2 = NULL;
  sm->c1 = NULL;
  sm->c2 = NULL;
  sm->d1 = NULL;
  sm->d2 = NULL;
  sm->e1 = NULL;
  sm->e2 = NULL;
}

// True if a mention is allowed to start after this character.
static bool is_mention_boundary(unsigned char c) {
  switch (c) {
    case '\0': return true;
    case '\r': return true;
    case '\n': return true;
    case ' ':  return true;
    case '/':  return true;
    case '"':  return true;
    case '\'': return true;
    case '(':  return true;
    case ')':  return true;
    case '[':  return true;
    case ']':  return true;
    case '{':  return true;
    case '}':  return true;
    default:   return false;
  }
}

// Trim trailing unbalanced ')' characters from the URL.
static std::tuple<std::string_view, std::string_view> trim_url(const std::string_view url) {
  std::string_view trimmed = url;

  while (!trimmed.empty() && trimmed.back() == ')' && std::count(trimmed.begin(), trimmed.end(), ')') > std::count(trimmed.begin(), trimmed.end(), '(')) {
    trimmed.remove_suffix(1);
  }

  return { trimmed, { trimmed.end(), url.end() } };
}

// Replace CRLF sequences with LF.
static void replace_newlines(const std::string_view input, std::string& output) {
  size_t pos, last = 0;

  while (std::string::npos != (pos = input.find("\r\n", last))) {
    output.append(input, last, pos - last);
    output.append("\n");
    last = pos + 2;
  }

  output.append(input, last, pos - last);
}

StateMachine::StateMachine(const auto string, int initial_state, const DTextOptions options) : options(options) {
  // Add null bytes to the beginning and end of the string as start and end of string markers.
  input.reserve(string.size());
  input.append(1, '\0');
  replace_newlines(string, input);
  input.append(1, '\0');

  output.reserve(string.size() * 1.5);
  stack.reserve(16);
  dstack.reserve(16);

  p = input.c_str();
  pb = input.c_str();
  pe = input.c_str() + input.size();
  eof = pe;
  cs = initial_state;
}

std::string StateMachine::parse_inline(const std::string_view dtext) {
  StateMachine sm(dtext, dtext_en_inline, options);
  return sm.parse();
}

std::string StateMachine::parse_basic_inline(const std::string_view dtext) {
  StateMachine sm(dtext, dtext_en_basic_inline, options);
  return sm.parse();
}

StateMachine::ParseResult StateMachine::parse_dtext(const std::string_view dtext, DTextOptions options) {
  StateMachine sm(dtext, dtext_en_main, options);
  return { sm.parse(), sm.wiki_pages };
}

std::string StateMachine::parse() {
  StateMachine* sm = this;
  g_debug("parse '%.*s'", (int)(sm->input.size() - 2), sm->input.c_str() + 1);

  %% write init nocs;
  %% write exec;

  g_debug("EOF; closing stray blocks");
  dstack_close_all(sm);
  g_debug("done");

  return sm->output;
}

/* Everything below is optional, it's only needed to build bin/cdtext.exe. */
#ifdef CDTEXT

#include <glib.h>
#include <iostream>

static void parse_file(FILE* input, FILE* output) {
  std::stringstream ss;
  ss << std::cin.rdbuf();
  std::string dtext = ss.str();

  try {
    auto result = StateMachine::parse_dtext(dtext, options);

    if (fwrite(result.c_str(), 1, result.size(), output) != result.size()) {
      perror("fwrite failed");
      exit(1);
    }
  } catch (std::exception& e) {
    fprintf(stderr, "dtext parse error: %s\n", e.what());
    exit(1);
  }
}

int main(int argc, char* argv[]) {
  GError* error = NULL;
  bool opt_verbose = FALSE;
  bool opt_inline = FALSE;
  bool opt_no_mentions = FALSE;

  GOptionEntry options[] = {
    { "no-mentions", 'm', 0, G_OPTION_ARG_NONE, &opt_no_mentions, "Don't parse @mentions", NULL },
    { "inline",      'i', 0, G_OPTION_ARG_NONE, &opt_inline,      "Parse in inline mode", NULL },
    { "verbose",     'v', 0, G_OPTION_ARG_NONE, &opt_verbose,     "Print debug output", NULL },
    { NULL }
  };

  g_autoptr(GOptionContext) context = g_option_context_new("[FILE...]");
  g_option_context_add_main_entries(context, options, NULL);

  if (!g_option_context_parse(context, &argc, &argv, &error)) {
    fprintf(stderr, "option parsing failed: %s\n", error->message);
    g_clear_error(&error);
    return 1;
  }

  if (opt_verbose) {
    g_setenv("G_MESSAGES_DEBUG", "all", TRUE);
  }

  /* skip first argument (progname) */
  argc--, argv++;

  if (argc == 0) {
    parse_file(stdin, stdout, { .f_inline = opt_inline, .f_mentions = !opt_no_mentions });
    return 0;
  }

  for (const char* filename = *argv; argc > 0; argc--, argv++) {
    FILE* input = fopen(filename, "r");
    if (!input) {
      perror("fopen failed");
      return 1;
    }

    parse_file(input, stdout, opt_inline, !opt_no_mentions);
    fclose(input);
  }

  return 0;
}

#endif