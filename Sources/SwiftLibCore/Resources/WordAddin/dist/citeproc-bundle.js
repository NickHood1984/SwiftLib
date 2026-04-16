(() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __commonJS = (cb, mod) => function __require() {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));

  // node_modules/citeproc/citeproc_commonjs.js
  var require_citeproc_commonjs = __commonJS({
    "node_modules/citeproc/citeproc_commonjs.js"(exports, module) {
      "use strict";
      var CSL2 = {
        PROCESSOR_VERSION: "1.4.61",
        error: function(str) {
          if ("undefined" === typeof Error) {
            throw new Error("citeproc-js error: " + str);
          } else {
            throw "citeproc-js error: " + str;
          }
        },
        debug: function(str) {
          if ("undefined" === typeof console) {
            dump("CSL: " + str + "\n");
          } else {
            console.log("citeproc-js warning: " + str);
          }
        },
        toLocaleUpperCase(str) {
          var arr = this.tmp.lang_array;
          try {
            str = str.toLocaleUpperCase(arr);
          } catch (e) {
            str = str.toUpperCase();
          }
          return str;
        },
        toLocaleLowerCase(str) {
          var arr = this.tmp.lang_array;
          try {
            str = str.toLocaleLowerCase(arr);
          } catch (e) {
            str = str.toLowerCase();
          }
          return str;
        },
        LOCATOR_LABELS_REGEXP: new RegExp("^((vrs|sv|subpara|op|subch|add|amend|annot|app|art|bibliog|bk|ch|cl|col|cmt|dec|dept|div|ex|fig|fld|fol|n|hypo|illus|intro|l|no|p|pp|para|pt|pmbl|princ|pub|r|rn|sched|sec|ser|subdiv|subsec|supp|tbl|tit|vol)\\.)\\s+(.*)"),
        STATUTE_SUBDIV_PLAIN_REGEX: /(?:(?:^| )(?:vrs|sv|subpara|op|subch|add|amend|annot|app|art|bibliog|bk|ch|cl|col|cmt|dec|dept|div|ex|fig|fld|fol|n|hypo|illus|intro|l|no|p|pp|para|pt|pmbl|princ|pub|r|rn|sched|sec|ser|subdiv|subsec|supp|tbl|tit|vol)\. *)/,
        STATUTE_SUBDIV_PLAIN_REGEX_FRONT: /(?:^\s*[.,;]*\s*(?:vrs|sv|subpara|op|subch|add|amend|annot|app|art|bibliog|bk|ch|cl|col|cmt|dec|dept|div|ex|fig|fld|fol|n|hypo|illus|intro|l|no|p|pp|para|pt|pmbl|princ|pub|r|rn|sched|sec|ser|subdiv|subsec|supp|tbl|tit|vol)\. *)/,
        STATUTE_SUBDIV_STRINGS: {
          "vrs.": "verse",
          "sv.": "sub-verbo",
          "subpara.": "subparagraph",
          "op.": "opus",
          "subch.": "subchapter",
          "add.": "addendum",
          "amend.": "amendment",
          "annot.": "annotation",
          "app.": "appendix",
          "art.": "article",
          "bibliog.": "bibliography",
          "bk.": "book",
          "ch.": "chapter",
          "cl.": "clause",
          "col.": "column",
          "cmt.": "comment",
          "dec.": "decision",
          "dept.": "department",
          "ex.": "example",
          "fig.": "figure",
          "fld.": "field",
          "fol.": "folio",
          "n.": "note",
          "hypo.": "hypothetical",
          "illus.": "illustration",
          "intro.": "introduction",
          "l.": "line",
          "no.": "issue",
          "p.": "page",
          "pp.": "page",
          "para.": "paragraph",
          "pt.": "part",
          "pmbl.": "preamble",
          "princ.": "principle",
          "pub.": "publication",
          "r.": "rule",
          "rn.": "randnummer",
          "sched.": "schedule",
          "sec.": "section",
          "ser.": "series,",
          "subdiv.": "subdivision",
          "subsec.": "subsection",
          "supp.": "supplement",
          "tbl.": "table",
          "tit.": "title",
          "vol.": "volume"
        },
        STATUTE_SUBDIV_STRINGS_REVERSE: {
          "verse": "vrs.",
          "sub-verbo": "sv.",
          "sub verbo": "sv.",
          "subparagraph": "subpara.",
          "opus": "op.",
          "subchapter": "subch.",
          "addendum": "add.",
          "amendment": "amend.",
          "annotation": "annot.",
          "appendix": "app.",
          "article": "art.",
          "bibliography": "bibliog.",
          "book": "bk.",
          "chapter": "ch.",
          "clause": "cl.",
          "column": "col.",
          "comment": "cmt.",
          "decision": "dec.",
          "department": "dept.",
          "example": "ex.",
          "figure": "fig.",
          "field": "fld.",
          "folio": "fol.",
          "note": "n.",
          "hypothetical": "hypo.",
          "illustration": "illus.",
          "introduction": "intro.",
          "line": "l.",
          "issue": "no.",
          "page": "p.",
          "paragraph": "para.",
          "part": "pt.",
          "preamble": "pmbl.",
          "principle": "princ.",
          "publication": "pub.",
          "rule": "r.",
          "randnummer": "rn.",
          "schedule": "sched.",
          "section": "sec.",
          "series,": "ser.",
          "subdivision": "subdiv.",
          "subsection": "subsec.",
          "supplement": "supp.",
          "table": "tbl.",
          "title": "tit.",
          "volume": "vol."
        },
        LOCATOR_LABELS_MAP: {
          "vrs": "verse",
          "sv": "sub-verbo",
          "subpara": "subparagraph",
          "op": "opus",
          "subch": "subchapter",
          "add": "addendum",
          "amend": "amendment",
          "annot": "annotation",
          "app": "appendix",
          "art": "article",
          "bibliog": "bibliography",
          "bk": "book",
          "ch": "chapter",
          "cl": "clause",
          "col": "column",
          "cmt": "comment",
          "dec": "decision",
          "dept": "department",
          "ex": "example",
          "fig": "figure",
          "fld": "field",
          "fol": "folio",
          "n": "note",
          "hypo": "hypothetical",
          "illus": "illustration",
          "intro": "introduction",
          "l": "line",
          "no": "issue",
          "p": "page",
          "pp": "page",
          "para": "paragraph",
          "pt": "part",
          "pmbl": "preamble",
          "princ": "principle",
          "pub": "publication",
          "r": "rule",
          "rn": "randnummer",
          "sched": "schedule",
          "sec": "section",
          "ser": "series,",
          "subdiv": "subdivision",
          "subsec": "subsection",
          "supp": "supplement",
          "tbl": "table",
          "tit": "title",
          "vol": "volume"
        },
        MODULE_MACROS: {
          "juris-pretitle": true,
          "juris-title": true,
          "juris-pretitle-short": true,
          "juris-title-short": true,
          "juris-main": true,
          "juris-main-short": true,
          "juris-tail": true,
          "juris-tail-short": true,
          "juris-locator": true
        },
        MODULE_TYPES: {
          "legal_case": true,
          "legislation": true,
          "bill": true,
          "hearing": true,
          "gazette": true,
          "report": true,
          "regulation": true,
          "standard": true,
          "patent": true,
          "locator": true
        },
        checkNestedBrace: function(state) {
          if (state.opt.xclass === "note") {
            this.depth = 0;
            this.update = function(str) {
              var str = str ? str : "";
              var lst = str.split(/([\(\)])/);
              for (var i = 1, ilen = lst.length; i < ilen; i += 2) {
                if (lst[i] === "(") {
                  if (1 === this.depth % 2) {
                    lst[i] = "[";
                  }
                  this.depth += 1;
                } else if (lst[i] === ")") {
                  if (0 === this.depth % 2) {
                    lst[i] = "]";
                  }
                  this.depth -= 1;
                }
              }
              var ret = lst.join("");
              return ret;
            };
          } else {
            this.update = function(str) {
              return str;
            };
          }
        },
        MULTI_FIELDS: ["event", "publisher", "publisher-place", "event-place", "title", "container-title", "collection-title", "authority", "genre", "title-short", "medium", "country", "jurisdiction", "archive", "archive-place"],
        LangPrefsMap: {
          "title": "titles",
          "title-short": "titles",
          "event": "titles",
          "genre": "titles",
          "medium": "titles",
          "container-title": "journals",
          "collection-title": "titles",
          "archive": "journals",
          "publisher": "publishers",
          "authority": "publishers",
          "publisher-place": "places",
          "event-place": "places",
          "archive-place": "places",
          "jurisdiction": "places",
          "number": "places",
          "edition": "places",
          "issue": "places",
          "volume": "places"
        },
        AbbreviationSegments: function() {
          this["container-title"] = {};
          this["collection-title"] = {};
          this["institution-entire"] = {};
          this["institution-part"] = {};
          this.nickname = {};
          this.number = {};
          this.title = {};
          this.place = {};
          this.hereinafter = {};
          this.classic = {};
          this["container-phrase"] = {};
          this["title-phrase"] = {};
        },
        getAbbrevsDomain: function(state, country, lang) {
          var domain = null;
          if (state.opt.availableAbbrevDomains && country && country !== "default") {
            var globalDomainPreference = state.locale[state.opt.lang].opts["jurisdiction-preference"];
            var itemDomainPreference = null;
            if (state.locale[lang]) {
              itemDomainPreference = state.locale[lang].opts["jurisdiction-preference"];
            }
            if (itemDomainPreference) {
              for (var j = itemDomainPreference.length - 1; j > -1; j--) {
                if (state.opt.availableAbbrevDomains[country].indexOf(itemDomainPreference[j]) > -1) {
                  domain = itemDomainPreference[j];
                  break;
                }
              }
            }
            if (!domain && globalDomainPreference) {
              for (var j = globalDomainPreference.length - 1; j > -1; j--) {
                if (state.opt.availableAbbrevDomains[country].indexOf(globalDomainPreference[j]) > -1) {
                  domain = globalDomainPreference[j];
                  break;
                }
              }
            }
          }
          return domain;
        },
        FIELD_CATEGORY_REMAP: {
          "title": "title",
          "container-title": "container-title",
          "collection-title": "collection-title",
          "country": "place",
          "number": "number",
          "place": "place",
          "archive": "container-title",
          "title-short": "title",
          "genre": "title",
          "event": "title",
          "medium": "title",
          "archive-place": "place",
          "publisher-place": "place",
          "event-place": "place",
          "jurisdiction": "place",
          "language-name": "place",
          "language-name-original": "place",
          "call-number": "number",
          "chapter-number": "number",
          "collection-number": "number",
          "edition": "number",
          "page": "number",
          "issue": "number",
          "locator": "number",
          "locator-extra": "number",
          "number-of-pages": "number",
          "number-of-volumes": "number",
          "volume": "number",
          "citation-number": "number",
          "publisher": "institution-part"
        },
        parseLocator: function(item) {
          if (this.opt.development_extensions.locator_date_and_revision) {
            if (item.locator) {
              item.locator = "" + item.locator;
              var idx = item.locator.indexOf("|");
              if (idx > -1) {
                var raw_locator = item.locator;
                item.locator = raw_locator.slice(0, idx);
                raw_locator = raw_locator.slice(idx + 1);
                var m = raw_locator.match(/^([0-9]{4}-[0-9]{2}-[0-9]{2}).*/);
                if (m) {
                  item["locator-date"] = this.fun.dateparser.parseDateToObject(m[1]);
                  raw_locator = raw_locator.slice(m[1].length);
                }
                item["locator-extra"] = raw_locator.replace(/^\s+/, "").replace(/\s+$/, "");
              }
            }
          }
          if (item.locator) {
            item.locator = ("" + item.locator).replace(/\s+$/, "");
          }
          return item;
        },
        normalizeLocaleStr: function(str) {
          if (!str) {
            return;
          }
          var lst = str.split("-");
          lst[0] = lst[0].toLowerCase();
          if (lst[1]) {
            lst[1] = lst[1].toUpperCase();
          }
          return lst.join("-");
        },
        parseNoteFieldHacks: function(Item, validFieldsForType, allowDateOverride) {
          if ("string" !== typeof Item.note) {
            return;
          }
          var elems = [];
          var lines = Item.note.split("\n");
          for (var i = 0, ilen = lines.length; i < ilen; i++) {
            var line = lines[i];
            var elems = [];
            var m = line.match(CSL2.NOTE_FIELDS_REGEXP);
            if (m) {
              var splt = line.split(CSL2.NOTE_FIELDS_REGEXP);
              for (var j = 0, jlen = splt.length - 1; j < jlen; j++) {
                elems.push(splt[j]);
                elems.push(m[j]);
              }
              elems.push(splt[splt.length - 1]);
              for (var j = 1, jlen = elems.length; j < jlen; j += 2) {
                if (elems[j - 1].trim() && (i > 0 || j > 1) && !elems[j - 1].match(CSL2.NOTE_FIELD_REGEXP)) {
                  break;
                } else {
                  elems[j] = "\n" + elems[j].slice(2, -1).trim() + "\n";
                }
              }
              lines[i] = elems.join("");
            }
          }
          lines = lines.join("\n").split("\n");
          var offset = 0;
          var names = {};
          for (var i = 0, ilen = lines.length; i < ilen; i++) {
            var line = lines[i];
            var mm = line.match(CSL2.NOTE_FIELD_REGEXP);
            if (!line.trim()) {
              continue;
            } else if (!mm) {
              if (i === 0) {
                continue;
              } else {
                offset = i;
                break;
              }
            }
            var key = mm[1];
            var val = mm[2].replace(/^\s+/, "").replace(/\s+$/, "");
            if (key === "type") {
              Item.type = val;
              lines[i] = "";
            } else if (CSL2.DATE_VARIABLES.indexOf(key.replace(/^alt-/, "")) > -1) {
              if (!Item[key] || allowDateOverride) {
                Item[key] = CSL2.DateParser.parseDateToArray(val);
                if (!validFieldsForType || validFieldsForType[key] && this.isDateString(val)) {
                  lines[i] = "";
                }
              }
            } else if (!Item[key]) {
              if (CSL2.NAME_VARIABLES.indexOf(key.replace(/^alt-/, "")) > -1) {
                if (!names[key]) {
                  names[key] = [];
                }
                var lst = val.split(/\s*\|\|\s*/);
                if (lst.length === 1) {
                  names[key].push({ literal: lst[0] });
                } else if (lst.length === 2) {
                  var name = { family: lst[0], given: lst[1] };
                  CSL2.parseParticles(name);
                  names[key].push(name);
                }
              } else {
                Item[key] = val;
              }
              if (!validFieldsForType || validFieldsForType[key]) {
                lines[i] = "";
              }
            }
          }
          for (var key in names) {
            Item[key] = names[key];
          }
          if (validFieldsForType) {
            if (lines[offset].trim()) {
              lines[offset] = "\n" + lines[offset];
            }
            for (var i = offset - 1; i > -1; i--) {
              if (!lines[i].trim()) {
                lines = lines.slice(0, i).concat(lines.slice(i + 1));
              }
            }
          }
          Item.note = lines.join("\n").trim();
        },
        checkPrefixSpaceAppend: function(state, prefix) {
          if (!prefix) {
            prefix = "";
          }
          var sp = "";
          var test_prefix = prefix.replace(/<[^>]+>/g, "").replace(/["'\u201d\u2019\u00bb\u202f\u00a0 ]+$/g, "");
          var test_char = test_prefix.slice(-1);
          if (test_prefix.match(CSL2.ENDSWITH_ROMANESQUE_REGEXP)) {
            sp = " ";
          } else if (CSL2.TERMINAL_PUNCTUATION.slice(0, -1).indexOf(test_char) > -1) {
            sp = " ";
          } else if (test_char.match(/[\)\],0-9]/)) {
            sp = " ";
          }
          var prefix = (prefix + sp).replace(/\s+/g, " ");
          return prefix;
        },
        checkIgnorePredecessor: function(state, prefix) {
          var ignorePredecessor = false;
          var test_prefix = prefix.replace(/<[^>]+>/g, "").replace(/["'\u201d\u2019\u00bb\u202f\u00a0 ]+$/g, "");
          var test_char = test_prefix.slice(-1);
          if (CSL2.TERMINAL_PUNCTUATION.slice(0, -1).indexOf(test_char) > -1 && prefix.trim().indexOf(" ") > -1) {
            state.tmp.term_predecessor = false;
            return true;
          }
          return false;
        },
        checkSuffixSpacePrepend: function(state, suffix) {
          if (!suffix) {
            return "";
          }
          if (suffix.match(CSL2.STARTSWITH_ROMANESQUE_REGEXP) || ["[", "("].indexOf(suffix.slice(0, 1)) > -1) {
            suffix = " " + suffix;
          }
          return suffix;
        },
        GENDERS: ["masculine", "feminine"],
        ERROR_NO_RENDERED_FORM: 1,
        PREVIEW: "Just for laughs.",
        ASSUME_ALL_ITEMS_REGISTERED: 2,
        START: 0,
        END: 1,
        SINGLETON: 2,
        SEEN: 6,
        SUCCESSOR: 3,
        SUCCESSOR_OF_SUCCESSOR: 4,
        SUPPRESS: 5,
        SINGULAR: 0,
        PLURAL: 1,
        LITERAL: true,
        BEFORE: 1,
        AFTER: 2,
        DESCENDING: 1,
        ASCENDING: 2,
        PRIMARY: 1,
        SECONDARY: 2,
        POSITION_FIRST: 0,
        POSITION_SUBSEQUENT: 1,
        POSITION_IBID: 2,
        POSITION_IBID_WITH_LOCATOR: 3,
        POSITION_CONTAINER_SUBSEQUENT: 4,
        POSITION_MAP: {
          "0": 0,
          "4": 1,
          "1": 2,
          "2": 3,
          "3": 4
        },
        POSITION_TEST_VARS: ["position", "first-reference-note-number", "near-note"],
        AREAS: ["citation", "citation_sort", "bibliography", "bibliography_sort", "intext"],
        CITE_FIELDS: ["first-reference-note-number", "first-container-reference-note-number", "locator", "locator-extra"],
        SWAPPING_PUNCTUATION: [".", "!", "?", ":", ","],
        TERMINAL_PUNCTUATION: [":", ".", ";", "!", "?", " "],
        // update modes
        NONE: 0,
        NUMERIC: 1,
        POSITION: 2,
        TRIGRAPH: 3,
        DATE_PARTS: ["year", "month", "day"],
        DATE_PARTS_ALL: ["year", "month", "day", "season"],
        DATE_PARTS_INTERNAL: ["year", "month", "day", "year_end", "month_end", "day_end"],
        NAME_PARTS: ["non-dropping-particle", "family", "given", "dropping-particle", "suffix", "literal"],
        DISAMBIGUATE_OPTIONS: [
          "disambiguate-add-names",
          "disambiguate-add-givenname",
          "disambiguate-add-year-suffix"
        ],
        GIVENNAME_DISAMBIGUATION_RULES: [
          "all-names",
          "all-names-with-initials",
          "primary-name",
          "primary-name-with-initials",
          "by-cite"
        ],
        NAME_ATTRIBUTES: [
          "and",
          "delimiter-precedes-last",
          "delimiter-precedes-et-al",
          "initialize-with",
          "initialize",
          "name-as-sort-order",
          "sort-separator",
          "et-al-min",
          "et-al-use-first",
          "et-al-subsequent-min",
          "et-al-subsequent-use-first",
          "form",
          "prefix",
          "suffix",
          "delimiter"
        ],
        LOOSE: 0,
        STRICT: 1,
        TOLERANT: 2,
        PREFIX_PUNCTUATION: /[.;:]\s*$/,
        SUFFIX_PUNCTUATION: /^\s*[.;:,\(\)]/,
        NUMBER_REGEXP: /(?:^\d+|\d+$)/,
        //
        // \u0400-\u042f are cyrillic and extended cyrillic capitals
        // this is not fully smart yet.  can't do what this was trying to do
        // with regexps, actually; we want to identify strings with a leading
        // capital letter, and any subsequent capital letters.  Have to compare
        // locale caps version with existing version, character by character.
        // hard stuff, but if it breaks, that's what to do.
        // \u0600-\u06ff is Arabic/Persian
        // \u200c-\u200e and \u202a-\u202e are special spaces and left-right 
        // control characters
        NAME_INITIAL_REGEXP: /^([A-Z\u0e01-\u0e5b\u00c0-\u017f\u0400-\u042f\u0590-\u05d4\u05d6-\u05ff\u0600-\u06ff\u0370\u0372\u0376\u0386\u0388-\u03ab\u03e2\u03e4\u03e6\u03e8\u03ea\u03ec\u03ee\u03f4\u03f7\u03fd-\u03ff])([a-zA-Z\u0e01-\u0e5b\u00c0-\u017f\u0400-\u052f\u0600-\u06ff\u0370-\u03ff\u1f00-\u1fff]*|)(\.)*/,
        ROMANESQUE_REGEXP: /[-0-9a-zA-Z\u0e01-\u0e5b\u00c0-\u017f\u0370-\u03ff\u0400-\u052f\u0590-\u05d4\u05d6-\u05ff\u1f00-\u1fff\u0600-\u06ff\u200c\u200d\u200e\u0218\u0219\u021a\u021b\u202a-\u202e]/,
        ROMANESQUE_NOT_REGEXP: /[^a-zA-Z\u0e01-\u0e5b\u00c0-\u017f\u0370-\u03ff\u0400-\u052f\u0590-\u05d4\u05d6-\u05ff\u1f00-\u1fff\u0600-\u06ff\u200c\u200d\u200e\u0218\u0219\u021a\u021b\u202a-\u202e]/g,
        STARTSWITH_ROMANESQUE_REGEXP: /^[&a-zA-Z\u0e01-\u0e5b\u00c0-\u017f\u0370-\u03ff\u0400-\u052f\u0590-\u05d4\u05d6-\u05ff\u1f00-\u1fff\u0600-\u06ff\u200c\u200d\u200e\u0218\u0219\u021a\u021b\u202a-\u202e]/,
        ENDSWITH_ROMANESQUE_REGEXP: /[.;:&a-zA-Z\u0e01-\u0e5b\u00c0-\u017f\u0370-\u03ff\u0400-\u052f\u0590-\u05d4\u05d6-\u05ff\u1f00-\u1fff\u0600-\u06ff\u200c\u200d\u200e\u0218\u0219\u021a\u021b\u202a-\u202e]$/,
        ALL_ROMANESQUE_REGEXP: /^[a-zA-Z\u0e01-\u0e5b\u00c0-\u017f\u0370-\u03ff\u0400-\u052f\u0590-\u05d4\u05d6-\u05ff\u1f00-\u1fff\u0600-\u06ff\u200c\u200d\u200e\u0218\u0219\u021a\u021b\u202a-\u202e]+$/,
        VIETNAMESE_SPECIALS: /[\u00c0-\u00c3\u00c8-\u00ca\u00cc\u00cd\u00d2-\u00d5\u00d9\u00da\u00dd\u00e0-\u00e3\u00e8-\u00ea\u00ec\u00ed\u00f2-\u00f5\u00f9\u00fa\u00fd\u0101\u0103\u0110\u0111\u0128\u0129\u0168\u0169\u01a0\u01a1\u01af\u01b0\u1ea0-\u1ef9]/,
        VIETNAMESE_NAMES: /^(?:(?:[.AaBbCcDdEeGgHhIiKkLlMmNnOoPpQqRrSsTtUuVvXxYy \u00c0-\u00c3\u00c8-\u00ca\u00cc\u00cd\u00d2-\u00d5\u00d9\u00da\u00dd\u00e0-\u00e3\u00e8-\u00ea\u00ec\u00ed\u00f2-\u00f5\u00f9\u00fa\u00fd\u0101\u0103\u0110\u0111\u0128\u0129\u0168\u0169\u01a0\u01a1\u01af\u01b0\u1ea0-\u1ef9]{2,6})(\s+|$))+$/,
        NOTE_FIELDS_REGEXP: /\{:(?:[\-_a-z]+|[A-Z]+):[^\}]+\}/g,
        NOTE_FIELD_REGEXP: /^([\-_a-z]+|[A-Z]+):\s*([^\}]+)$/,
        PARTICLE_GIVEN_REGEXP: /^([^ ]+(?:\u02bb |\u2019 | |\' ) *)(.+)$/,
        PARTICLE_FAMILY_REGEXP: /^([^ ]+(?:\-|\u02bb|\u2019| |\') *)(.+)$/,
        DISPLAY_CLASSES: ["block", "left-margin", "right-inline", "indent"],
        NAME_VARIABLES: [
          "author",
          "chair",
          "collection-editor",
          "compiler",
          "composer",
          "container-author",
          "contributor",
          "curator",
          "director",
          "editor",
          "editor-translator",
          "editorial-director",
          "executive-producer",
          "guest",
          "host",
          "illustrator",
          "interviewer",
          "narrator",
          "organizer",
          "original-author",
          "performer",
          "producer",
          "recipient",
          "reviewed-author",
          "script-writer",
          "series-creator",
          "translator",
          "commenter"
        ],
        CREATORS: [
          "author",
          "chair",
          "collection-editor",
          "compiler",
          "composer",
          "container-author",
          "contributor",
          "curator",
          "director",
          "editor",
          "editor-translator",
          "editorial-director",
          "executive-producer",
          "guest",
          "host",
          "illustrator",
          "interviewer",
          "narrator",
          "organizer",
          "original-author",
          "performer",
          "producer",
          "recipient",
          "reviewed-author",
          "script-writer",
          "series-creator",
          "translator",
          "commenter"
        ],
        NUMERIC_VARIABLES: [
          "call-number",
          "chapter-number",
          "collection-number",
          "division",
          "edition",
          "page",
          "issue",
          "locator",
          "locator-extra",
          "number",
          "number-of-pages",
          "number-of-volumes",
          "part-number",
          "printing-number",
          "section",
          "supplement-number",
          "version",
          "volume",
          "supplement",
          // maybe deprecated this? supplement-number should serve this purpose in standard CSL.
          "citation-number"
        ],
        //var x = new Array();
        //x = x.concat(["title","container-title","issued","page"]);
        //x = x.concat(["locator","collection-number","original-date"]);
        //x = x.concat(["reporting-date","decision-date","filing-date"]);
        //x = x.concat(["revision-date"]);
        //NUMERIC_VARIABLES = x.slice();
        DATE_VARIABLES: [
          "locator-date",
          "issued",
          "event-date",
          "accessed",
          "original-date",
          "publication-date",
          "available-date",
          "submitted",
          "alt-issued",
          "alt-event"
        ],
        VARIABLES_WITH_SHORT_FORM: [
          "title",
          "container-title"
        ],
        TITLE_FIELD_SPLITS: function(seg) {
          var keys = ["title", "short", "main", "sub", "subjoin"];
          var ret = {};
          for (var i = 0, ilen = keys.length; i < ilen; i++) {
            ret[keys[i]] = seg + "title" + (keys[i] === "title" ? "" : "-" + keys[i]);
          }
          return ret;
        },
        demoteNoiseWords: function(state, fld, drop_or_demote) {
          var SKIP_WORDS = state.locale[state.opt.lang].opts["leading-noise-words"];
          if (fld && drop_or_demote) {
            fld = fld.split(/\s+/);
            fld.reverse();
            var toEnd = [];
            for (var j = fld.length - 1; j > -1; j += -1) {
              if (SKIP_WORDS.indexOf(fld[j].toLowerCase()) > -1) {
                toEnd.push(fld.pop());
              } else {
                break;
              }
            }
            fld.reverse();
            var start = fld.join(" ");
            var end = toEnd.join(" ");
            if ("drop" === drop_or_demote || !end) {
              fld = start;
            } else if ("demote" === drop_or_demote) {
              fld = [start, end].join(", ");
            }
          }
          return fld;
        },
        extractTitleAndSubtitle: function(Item, narrowSpaceLocale) {
          var narrowSpace = narrowSpaceLocale ? "\u202F" : "";
          var segments = [""];
          if (this.opt.development_extensions.split_container_title) {
            segments.push("container-");
          }
          for (var i = 0, ilen = segments.length; i < ilen; i++) {
            var seg = segments[i];
            var title = CSL2.TITLE_FIELD_SPLITS(seg);
            var langs = [false];
            if (Item.multi) {
              for (var lang in Item.multi._keys[title.short]) {
                langs.push(lang);
              }
            }
            for (var j = 0, jlen = langs.length; j < jlen; j++) {
              var lang = langs[j];
              var vals = {};
              if (lang) {
                if (Item.multi._keys[title.title]) {
                  vals[title.title] = Item.multi._keys[title.title][lang];
                }
                if (Item.multi._keys[title["short"]]) {
                  vals[title["short"]] = Item.multi._keys[title["short"]][lang];
                }
              } else {
                vals[title.title] = Item[title.title];
                vals[title["short"]] = Item[title["short"]];
              }
              vals[title.main] = vals[title.title];
              vals[title.sub] = false;
              var shortTitle = vals[title["short"]];
              if (vals[title.title]) {
                if (shortTitle && shortTitle.toLowerCase() === vals[title.title].toLowerCase()) {
                  vals[title.main] = vals[title.title];
                  vals[title.subjoin] = "";
                  vals[title.sub] = "";
                } else if (shortTitle) {
                  var tail = vals[title.title].slice(shortTitle.replace(/[\?\!]+$/, "").length);
                  var top = vals[title.title].replace(tail.replace(/^[\?\!]+/, ""), "").trim();
                  var m = CSL2.TITLE_SPLIT_REGEXP.matchfirst.exec(tail);
                  if (m && top.toLowerCase() === shortTitle.toLowerCase()) {
                    vals[title.main] = top;
                    vals[title.subjoin] = m[1].replace(/[\?\!]+(\s*)$/, "$1");
                    vals[title.sub] = tail.replace(CSL2.TITLE_SPLIT_REGEXP.matchfirst, "");
                    if (this.opt.development_extensions.force_short_title_casing_alignment) {
                      vals[title["short"]] = vals[title.main];
                    }
                  } else {
                    var splitTitle = CSL2.TITLE_SPLIT(vals[title.title]);
                    if (splitTitle.length == 3) {
                      vals[title.main] = splitTitle[0];
                      vals[title.subjoin] = splitTitle[1];
                      vals[title.sub] = splitTitle[2];
                    } else {
                      vals[title.main] = vals[title.title];
                      vals[title.subjoin] = "";
                      vals[title.sub] = "";
                    }
                  }
                } else {
                  var splitTitle = CSL2.TITLE_SPLIT(vals[title.title]);
                  if (splitTitle.length == 3) {
                    vals[title.main] = splitTitle[0];
                    vals[title.subjoin] = splitTitle[1];
                    vals[title.sub] = splitTitle[2];
                    if (this.opt.development_extensions.implicit_short_title && Item.type !== "legal_case") {
                      if (!Item[title.short] && !vals[title.main].match(/^[\-\.[0-9]+$/)) {
                        var punct = vals[title.subjoin].trim();
                        if (["?", "!"].indexOf(punct) === -1) {
                          punct = "";
                        }
                        vals[title.short] = vals[title.main] + punct;
                      }
                    }
                  } else {
                    vals[title.main] = vals[title.title];
                    vals[title.subjoin] = "";
                    vals[title.sub] = "";
                  }
                }
                if (vals[title.subjoin]) {
                  if (vals[title.subjoin].match(/([\?\!])/)) {
                    var m = vals[title.subjoin].match(/(\s*)$/);
                    vals[title.main] = vals[title.main] + narrowSpace + vals[title.subjoin].trim();
                    vals[title.subjoin] = m[1];
                  }
                }
              }
              if (vals[title.subjoin]) {
                if (vals[title.subjoin].indexOf(":") > -1) {
                  vals[title.subjoin] = narrowSpace + ": ";
                }
                if (vals[title.subjoin].indexOf("-") > -1 || vals[title.subjoin].indexOf("\u2014") > -1) {
                  vals[title.subjoin] = "\u2014";
                }
              }
              if (lang) {
                for (var key in vals) {
                  if (!Item.multi._keys[key]) {
                    Item.multi._keys[key] = {};
                  }
                  Item.multi._keys[key][lang] = vals[key];
                }
              } else {
                for (var key in vals) {
                  Item[key] = vals[key];
                }
              }
            }
          }
        },
        titlecaseSentenceOrNormal: function(state, Item, seg, lang, sentenceCase) {
          var title = CSL2.TITLE_FIELD_SPLITS(seg);
          var vals = {};
          if (lang && Item.multi) {
            if (Item.multi._keys[title.title]) {
              vals[title.title] = Item.multi._keys[title.title][lang];
            }
            if (Item.multi._keys[title.main]) {
              vals[title.main] = Item.multi._keys[title.main][lang];
            }
            if (Item.multi._keys[title.sub]) {
              vals[title.sub] = Item.multi._keys[title.sub][lang];
            }
            if (Item.multi._keys[title.subjoin]) {
              vals[title.subjoin] = Item.multi._keys[title.subjoin][lang];
            }
          } else {
            vals[title.title] = Item[title.title];
            vals[title.main] = Item[title.main];
            vals[title.sub] = Item[title.sub];
            vals[title.subjoin] = Item[title.subjoin];
          }
          if (vals[title.main] && vals[title.sub]) {
            var mainTitle = vals[title.main];
            var subJoin = vals[title.subjoin];
            var subTitle = vals[title.sub];
            if (sentenceCase) {
              mainTitle = CSL2.Output.Formatters.sentence(state, mainTitle);
              subTitle = CSL2.Output.Formatters.sentence(state, subTitle);
            } else if (state.opt.development_extensions.uppercase_subtitles) {
              subTitle = CSL2.Output.Formatters["capitalize-first"](state, subTitle);
            }
            return [mainTitle, subJoin, subTitle].join("");
          } else if (vals[title.title]) {
            if (sentenceCase) {
              return CSL2.Output.Formatters.sentence(state, vals[title.title]);
            } else if (state.opt.development_extensions.uppercase_subtitles) {
              var splits = CSL2.TITLE_SPLIT(vals[title.title]);
              for (var i = 0, ilen = splits.length; i < ilen; i += 2) {
                splits[i] = CSL2.Output.Formatters["capitalize-first"](state, splits[i]);
              }
              for (var i = 1, ilen = splits.length - 1; i < ilen; i += 2) {
                var m = splits[i].match(/([:\?\!] )/);
                if (m) {
                  var narrowSpace = state.opt["default-locale"][0].slice(0, 2).toLowerCase() === "fr" ? "\u202F" : "";
                  splits[i] = narrowSpace + m[1];
                }
                if (splits[i].indexOf("-") > -1 || splits[i].indexOf("\u2014") > -1) {
                  splits[i] = "\u2014";
                }
              }
              vals[title.title] = splits.join("");
              return vals[title.title];
            } else {
              return vals[title.title];
            }
          } else {
            return "";
          }
        },
        getSafeEscape: function(state) {
          if (["bibliography", "citation"].indexOf(state.tmp.area) > -1) {
            var callbacks = [];
            if (state.opt.development_extensions.thin_non_breaking_space_html_hack && state.opt.mode === "html") {
              callbacks.push(function(txt) {
                return txt.replace(/\u202f/g, '<span style="white-space:nowrap">&thinsp;</span>');
              });
            }
            if (callbacks.length) {
              return function(txt) {
                for (var i = 0, ilen = callbacks.length; i < ilen; i += 1) {
                  txt = callbacks[i](txt);
                }
                return CSL2.Output.Formats[state.opt.mode].text_escape(txt);
              };
            } else {
              return CSL2.Output.Formats[state.opt.mode].text_escape;
            }
          } else {
            return function(txt) {
              return txt;
            };
          }
        },
        SKIP_WORDS: ["about", "above", "across", "afore", "after", "against", "al", "along", "alongside", "amid", "amidst", "among", "amongst", "anenst", "apropos", "apud", "around", "as", "aside", "astride", "at", "athwart", "atop", "barring", "before", "behind", "below", "beneath", "beside", "besides", "between", "beyond", "but", "by", "circa", "despite", "down", "during", "et", "except", "for", "forenenst", "from", "given", "in", "inside", "into", "lest", "like", "modulo", "near", "next", "notwithstanding", "of", "off", "on", "onto", "out", "over", "per", "plus", "pro", "qua", "sans", "since", "than", "through", " thru", "throughout", "thruout", "till", "to", "toward", "towards", "under", "underneath", "until", "unto", "up", "upon", "versus", "vs.", "v.", "vs", "v", "via", "vis-\xE0-vis", "with", "within", "without", "according to", "ahead of", "apart from", "as for", "as of", "as per", "as regards", "aside from", "back to", "because of", "close to", "due to", "except for", "far from", "inside of", "instead of", "near to", "next to", "on to", "out from", "out of", "outside of", "prior to", "pursuant to", "rather than", "regardless of", "such as", "that of", "up to", "where as", "or", "yet", "so", "for", "and", "nor", "a", "an", "the", "de", "d'", "von", "van", "c", "ca"],
        FORMAT_KEY_SEQUENCE: [
          "@strip-periods",
          "@font-style",
          "@font-variant",
          "@font-weight",
          "@text-decoration",
          "@vertical-align",
          "@quotes"
        ],
        INSTITUTION_KEYS: [
          "font-style",
          "font-variant",
          "font-weight",
          "text-decoration",
          "text-case"
        ],
        SUFFIX_CHARS: "a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z",
        ROMAN_NUMERALS: [
          ["", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix"],
          ["", "x", "xx", "xxx", "xl", "l", "lx", "lxx", "lxxx", "xc"],
          ["", "c", "cc", "ccc", "cd", "d", "dc", "dcc", "dccc", "cm"],
          ["", "m", "mm", "mmm", "mmmm", "mmmmm"]
        ],
        LANGS: {
          "af-ZA": "Afrikaans",
          "ar": "Arabic",
          "bg-BG": "Bulgarian",
          "ca-AD": "Catalan",
          "cs-CZ": "Czech",
          "da-DK": "Danish",
          "de-AT": "Austrian",
          "de-CH": "German (CH)",
          "de-DE": "German (DE)",
          "el-GR": "Greek",
          "en-GB": "English (GB)",
          "en-US": "English (US)",
          "es-ES": "Spanish",
          "et-EE": "Estonian",
          "eu": "European",
          "fa-IR": "Persian",
          "fi-FI": "Finnish",
          "fr-CA": "French (CA)",
          "fr-FR": "French (FR)",
          "he-IL": "Hebrew",
          "hr-HR": "Croatian",
          "hu-HU": "Hungarian",
          "is-IS": "Icelandic",
          "it-IT": "Italian",
          "ja-JP": "Japanese",
          "km-KH": "Khmer",
          "ko-KR": "Korean",
          "lt-LT": "Lithuanian",
          "lv-LV": "Latvian",
          "mn-MN": "Mongolian",
          "nb-NO": "Norwegian (Bokm\xE5l)",
          "nl-NL": "Dutch",
          "nn-NO": "Norwegian (Nynorsk)",
          "pl-PL": "Polish",
          "pt-BR": "Portuguese (BR)",
          "pt-PT": "Portuguese (PT)",
          "ro-RO": "Romanian",
          "ru-RU": "Russian",
          "sk-SK": "Slovak",
          "sl-SI": "Slovenian",
          "sr-RS": "Serbian",
          "sv-SE": "Swedish",
          "th-TH": "Thai",
          "tr-TR": "Turkish",
          "uk-UA": "Ukrainian",
          "vi-VN": "Vietnamese",
          "zh-CN": "Chinese (CN)",
          "zh-TW": "Chinese (TW)"
        },
        LANG_BASES: {
          af: "af_ZA",
          ar: "ar",
          bg: "bg_BG",
          ca: "ca_AD",
          cs: "cs_CZ",
          da: "da_DK",
          de: "de_DE",
          el: "el_GR",
          en: "en_US",
          es: "es_ES",
          et: "et_EE",
          eu: "eu",
          fa: "fa_IR",
          fi: "fi_FI",
          fr: "fr_FR",
          he: "he_IL",
          hr: "hr-HR",
          hu: "hu_HU",
          is: "is_IS",
          it: "it_IT",
          ja: "ja_JP",
          km: "km_KH",
          ko: "ko_KR",
          lt: "lt_LT",
          lv: "lv-LV",
          mn: "mn_MN",
          nb: "nb_NO",
          nl: "nl_NL",
          nn: "nn-NO",
          pl: "pl_PL",
          pt: "pt_PT",
          ro: "ro_RO",
          ru: "ru_RU",
          sk: "sk_SK",
          sl: "sl_SI",
          sr: "sr_RS",
          sv: "sv_SE",
          th: "th_TH",
          tr: "tr_TR",
          uk: "uk_UA",
          vi: "vi_VN",
          zh: "zh_CN"
        },
        SUPERSCRIPTS: {
          "\xAA": "a",
          "\xB2": "2",
          "\xB3": "3",
          "\xB9": "1",
          "\xBA": "o",
          "\u02B0": "h",
          "\u02B1": "\u0266",
          "\u02B2": "j",
          "\u02B3": "r",
          "\u02B4": "\u0279",
          "\u02B5": "\u027B",
          "\u02B6": "\u0281",
          "\u02B7": "w",
          "\u02B8": "y",
          "\u02E0": "\u0263",
          "\u02E1": "l",
          "\u02E2": "s",
          "\u02E3": "x",
          "\u02E4": "\u0295",
          "\u1D2C": "A",
          "\u1D2D": "\xC6",
          "\u1D2E": "B",
          "\u1D30": "D",
          "\u1D31": "E",
          "\u1D32": "\u018E",
          "\u1D33": "G",
          "\u1D34": "H",
          "\u1D35": "I",
          "\u1D36": "J",
          "\u1D37": "K",
          "\u1D38": "L",
          "\u1D39": "M",
          "\u1D3A": "N",
          "\u1D3C": "O",
          "\u1D3D": "\u0222",
          "\u1D3E": "P",
          "\u1D3F": "R",
          "\u1D40": "T",
          "\u1D41": "U",
          "\u1D42": "W",
          "\u1D43": "a",
          "\u1D44": "\u0250",
          "\u1D45": "\u0251",
          "\u1D46": "\u1D02",
          "\u1D47": "b",
          "\u1D48": "d",
          "\u1D49": "e",
          "\u1D4A": "\u0259",
          "\u1D4B": "\u025B",
          "\u1D4C": "\u025C",
          "\u1D4D": "g",
          "\u1D4F": "k",
          "\u1D50": "m",
          "\u1D51": "\u014B",
          "\u1D52": "o",
          "\u1D53": "\u0254",
          "\u1D54": "\u1D16",
          "\u1D55": "\u1D17",
          "\u1D56": "p",
          "\u1D57": "t",
          "\u1D58": "u",
          "\u1D59": "\u1D1D",
          "\u1D5A": "\u026F",
          "\u1D5B": "v",
          "\u1D5C": "\u1D25",
          "\u1D5D": "\u03B2",
          "\u1D5E": "\u03B3",
          "\u1D5F": "\u03B4",
          "\u1D60": "\u03C6",
          "\u1D61": "\u03C7",
          "\u2070": "0",
          "\u2071": "i",
          "\u2074": "4",
          "\u2075": "5",
          "\u2076": "6",
          "\u2077": "7",
          "\u2078": "8",
          "\u2079": "9",
          "\u207A": "+",
          "\u207B": "\u2212",
          "\u207C": "=",
          "\u207D": "(",
          "\u207E": ")",
          "\u207F": "n",
          "\u2120": "SM",
          "\u2122": "TM",
          "\u3192": "\u4E00",
          "\u3193": "\u4E8C",
          "\u3194": "\u4E09",
          "\u3195": "\u56DB",
          "\u3196": "\u4E0A",
          "\u3197": "\u4E2D",
          "\u3198": "\u4E0B",
          "\u3199": "\u7532",
          "\u319A": "\u4E59",
          "\u319B": "\u4E19",
          "\u319C": "\u4E01",
          "\u319D": "\u5929",
          "\u319E": "\u5730",
          "\u319F": "\u4EBA",
          "\u02C0": "\u0294",
          "\u02C1": "\u0295",
          "\u06E5": "\u0648",
          "\u06E6": "\u064A"
        },
        SUPERSCRIPTS_REGEXP: new RegExp("[\xAA\xB2\xB3\xB9\xBA\u02B0\u02B1\u02B2\u02B3\u02B4\u02B5\u02B6\u02B7\u02B8\u02E0\u02E1\u02E2\u02E3\u02E4\u1D2C\u1D2D\u1D2E\u1D30\u1D31\u1D32\u1D33\u1D34\u1D35\u1D36\u1D37\u1D38\u1D39\u1D3A\u1D3C\u1D3D\u1D3E\u1D3F\u1D40\u1D41\u1D42\u1D43\u1D44\u1D45\u1D46\u1D47\u1D48\u1D49\u1D4A\u1D4B\u1D4C\u1D4D\u1D4F\u1D50\u1D51\u1D52\u1D53\u1D54\u1D55\u1D56\u1D57\u1D58\u1D59\u1D5A\u1D5B\u1D5C\u1D5D\u1D5E\u1D5F\u1D60\u1D61\u2070\u2071\u2074\u2075\u2076\u2077\u2078\u2079\u207A\u207B\u207C\u207D\u207E\u207F\u2120\u2122\u3192\u3193\u3194\u3195\u3196\u3197\u3198\u3199\u319A\u319B\u319C\u319D\u319E\u319F\u02C0\u02C1\u06E5\u06E6]", "g"),
        // I think we need to have separate args for prefix and term,
        // since they have different effects between comma-safe and comma-safe-numbers-only.
        // Either that, or -- oh, we could just bang the two together for the test where
        // necessary.
        UPDATE_GROUP_CONTEXT_CONDITION: function(state, str, valueTerm, token, value) {
          if (!state.opt.use_context_condition) return;
          var flags = state.tmp.group_context.tip;
          if (flags.condition) {
            if (!flags.condition.termtxt) {
              flags.condition.termtxt = str;
              flags.condition.valueTerm = valueTerm;
            }
            if (!flags.value_seen && flags.condition.test === "comma-safe-numbers-only") {
              if (value) {
                flags.value_seen = true;
                if (!value.match(/^[0-9]/)) {
                  state.tmp.just_did_number = false;
                }
              }
            }
          } else {
            if (token && token.decorations.filter((o) => o[0] === "@vertical-align").length > 0) {
              state.tmp.just_did_number = false;
            } else if (token && token.strings.suffix) {
              state.tmp.just_did_number = false;
            } else if (str) {
              if (str.match(/[0-9]$/)) {
                state.tmp.just_did_number = true;
              } else {
                state.tmp.just_did_number = false;
              }
            }
          }
        },
        EVALUATE_GROUP_CONDITION: function(state, flags) {
          if (!state.opt.use_context_condition) return;
          var testres;
          var numbersOnly = flags.condition.test === "comma-safe-numbers-only";
          if (flags.condition.test === "empty-label") {
            testres = !flags.condition.termtxt;
          } else if (flags.condition.test === "empty-label-no-decor") {
            testres = !flags.condition.termtxt || flags.condition.termtxt.indexOf("%s") > -1;
          } else if (["comma-safe", "comma-safe-numbers-only"].indexOf(flags.condition.test) > -1) {
            var locale_term = flags.condition.termtxt;
            var termStartAlpha = false;
            if (flags.condition.termtxt) {
              termStartAlpha = flags.condition.termtxt.slice(0, 1).match(CSL2.ALL_ROMANESQUE_REGEXP);
            }
            var num = state.tmp.just_did_number;
            if (num) {
              if (flags.condition.valueTerm) {
                testres = numbersOnly ? false : true;
              } else if (!locale_term) {
                testres = true;
              } else if (termStartAlpha) {
                testres = numbersOnly ? false : true;
              } else if (["always", "after-number"].indexOf(state.opt.require_comma_on_symbol) > -1) {
                testres = true;
              } else {
                testres = false;
              }
            } else {
              if (flags.condition.valueTerm) {
                testres = false;
              } else if (!locale_term) {
                testres = false;
              } else if (termStartAlpha) {
                testres = numbersOnly ? false : true;
              } else if (state.opt.require_comma_on_symbol === "always") {
                testres = true;
              } else {
                testres = false;
              }
            }
          }
          if (testres) {
            var force_suppress = false;
          } else {
            var force_suppress = true;
          }
          if (flags.condition.not) {
            force_suppress = !force_suppress;
          }
          return force_suppress;
        },
        SYS_OPTIONS: [
          "prioritize_disambiguate_condition",
          "csl_reverse_lookup_support",
          "main_title_from_short_title",
          "uppercase_subtitles",
          "force_short_title_casing_alignment",
          "implicit_short_title",
          "split_container_title"
        ],
        TITLE_SPLIT_REGEXP: (function() {
          var splits = [
            "\\.\\s+",
            "\\!\\s+",
            "\\?\\s+",
            "\\s*::*\\s+",
            "\\s*\u2014\\s*",
            "\\s+\\-\\s+",
            "\\s*\\-\\-\\-*\\s*"
          ];
          return {
            match: new RegExp("(" + splits.join("|") + ")", "g"),
            matchfirst: new RegExp("^(" + splits.join("|") + ")"),
            split: new RegExp("(?:" + splits.join("|") + ")")
          };
        })(),
        TITLE_SPLIT: function(str) {
          if (!str) {
            return str;
          }
          var m = str.match(CSL2.TITLE_SPLIT_REGEXP.match);
          var lst = str.split(CSL2.TITLE_SPLIT_REGEXP.split);
          for (var i = lst.length - 2; i > -1; i--) {
            lst[i] = lst[i].trim();
            if (lst[i] && lst[i].slice(-1).toLowerCase() !== lst[i].slice(-1)) {
              lst[i] = lst[i] + m[i] + lst[i + 1];
              lst = lst.slice(0, i + 1).concat(lst.slice(i + 2));
            } else {
              lst = lst.slice(0, i + 1).concat([m[i]]).concat(lst.slice(i + 1));
            }
          }
          return lst;
        },
        GET_COURT_CLASS: function(state, Item, sortKey) {
          var cls = "";
          var authority = null;
          var country = Item.jurisdiction ? Item.jurisdiction.split(":")[0] : null;
          var classType = "court_condition_classes";
          if (sortKey) {
            classType = "court_key_classes";
          }
          if (country && Item.authority) {
            if ("string" === typeof Item.authority) {
              authority = Item.authority;
            } else {
              if (Item.authority[0] && Item.authority[0].literal) {
                authority = Item.authority[0].literal;
              }
            }
          }
          if (authority) {
            if (this.lang && state.locale[this.lang].opts[classType] && state.locale[this.lang].opts[classType][country] && state.locale[this.lang].opts[classType][country][authority]) {
              cls = state.locale[this.lang].opts[classType][country][authority];
            } else if (state.locale[state.opt["default-locale"][0]].opts[classType] && state.locale[state.opt["default-locale"][0]].opts[classType][country] && state.locale[state.opt["default-locale"][0]].opts[classType][country][authority]) {
              cls = state.locale[state.opt["default-locale"][0]].opts[classType][country][authority];
            }
          }
          return cls;
        },
        SET_COURT_CLASSES: function(state, lang, myxml, dataObj) {
          var nodes = myxml.getNodesByName(dataObj, "court-class");
          for (var pos = 0, len = myxml.numberofnodes(nodes); pos < len; pos += 1) {
            var courtclass = nodes[pos];
            var attributes = myxml.attributes(courtclass);
            var cls = attributes["@name"];
            var country = attributes["@country"];
            var courts = attributes["@courts"];
            var classType = "court_key_classes";
            if (state.registry) {
              classType = "court_condition_classes";
            }
            if (cls && country && courts) {
              courts = courts.trim().split(/\s+/);
              if (!state.locale[lang].opts[classType]) {
                state.locale[lang].opts[classType] = {};
              }
              if (!state.locale[lang].opts[classType][country]) {
                state.locale[lang].opts[classType][country] = {};
              }
              for (var i = 0, ilen = courts.length; i < ilen; i++) {
                state.locale[lang].opts[classType][country][courts[i]] = cls;
              }
            }
          }
        },
        INIT_JURISDICTION_MACROS: function(state, Item, item, macroName) {
          if (Item["best-jurisdiction"]) {
            return true;
          }
          if (!state.sys.retrieveStyleModule || !CSL2.MODULE_MACROS[macroName] || !Item.jurisdiction) {
            return false;
          }
          var jurisdictionList = state.getJurisdictionList(Item.jurisdiction);
          if (!state.opt.jurisdictions_seen[jurisdictionList[0]]) {
            var res = state.retrieveAllStyleModules(jurisdictionList);
            for (var jurisdiction in res) {
              var fallback = state.loadStyleModule(jurisdiction, res[jurisdiction]);
              if (fallback) {
                if (!res[fallback]) {
                  Object.assign(res, state.retrieveAllStyleModules([fallback]));
                  state.loadStyleModule(fallback, res[fallback], true);
                }
              }
            }
          }
          var jurisdictionList = state.getJurisdictionList(Item.jurisdiction);
          if (state.opt.parallel.enable) {
            if (!state.parallel) {
              state.parallel = new CSL2.Parallel(state);
            }
          }
          for (var i = 0, ilen = jurisdictionList.length; i < ilen; i++) {
            var jurisdiction = jurisdictionList[i];
            if (item) {
              if (state.juris[jurisdiction] && !item["best-jurisdiction"] && state.juris[jurisdiction].types.locator) {
                Item["best-jurisdiction"] = jurisdiction;
              }
            }
            if (state.juris[jurisdiction] && state.juris[jurisdiction].types[Item.type]) {
              Item["best-jurisdiction"] = jurisdiction;
              return true;
            }
          }
          return false;
        }
      };
      CSL2.XmlJSON = function(dataObj) {
        this.dataObj = dataObj;
        this.institution = {
          name: "institution",
          attrs: {
            "institution-parts": "long",
            "delimiter": ", "
          },
          children: [
            {
              name: "institution-part",
              attrs: {
                name: "long"
              },
              children: []
            }
          ]
        };
      };
      CSL2.XmlJSON.prototype.clean = function(json) {
        return json;
      };
      CSL2.XmlJSON.prototype.getStyleId = function(myjson, styleName) {
        var tagName = "id";
        if (styleName) {
          tagName = "title";
        }
        var ret = "";
        var children = myjson.children;
        for (var i = 0, ilen = children.length; i < ilen; i++) {
          if (children[i].name === "info") {
            var grandkids = children[i].children;
            for (var j = 0, jlen = grandkids.length; j < jlen; j++) {
              if (grandkids[j].name === tagName) {
                ret = grandkids[j].children[0];
              }
            }
          }
        }
        return ret;
      };
      CSL2.XmlJSON.prototype.children = function(myjson) {
        if (myjson && myjson.children.length) {
          return myjson.children.slice();
        } else {
          return false;
        }
      };
      CSL2.XmlJSON.prototype.nodename = function(myjson) {
        return myjson ? myjson.name : null;
      };
      CSL2.XmlJSON.prototype.attributes = function(myjson) {
        var ret = {};
        for (var attrname in myjson.attrs) {
          ret["@" + attrname] = myjson.attrs[attrname];
        }
        return ret;
      };
      CSL2.XmlJSON.prototype.content = function(myjson) {
        var ret = "";
        if (!myjson || !myjson.children) {
          return ret;
        }
        for (var i = 0, ilen = myjson.children.length; i < ilen; i += 1) {
          if ("string" === typeof myjson.children[i]) {
            ret += myjson.children[i];
          }
        }
        return ret;
      };
      CSL2.XmlJSON.prototype.namespace = {};
      CSL2.XmlJSON.prototype.numberofnodes = function(myjson) {
        if (myjson && "number" == typeof myjson.length) {
          return myjson.length;
        } else {
          return 0;
        }
      };
      CSL2.XmlJSON.prototype.getAttributeValue = function(myjson, name, namespace) {
        var ret = "";
        if (namespace) {
          name = namespace + ":" + name;
        }
        if (myjson) {
          if (myjson.attrs) {
            if (myjson.attrs[name]) {
              ret = myjson.attrs[name];
            } else {
              ret = "";
            }
          }
        }
        return ret;
      };
      CSL2.XmlJSON.prototype.getNodeValue = function(myjson, name) {
        var ret = "";
        if (name) {
          for (var i = 0, ilen = myjson.children.length; i < ilen; i += 1) {
            if (myjson.children[i].name === name) {
              if (myjson.children[i].children.length) {
                ret = myjson.children[i];
              } else {
                ret = "";
              }
            }
          }
        } else if (myjson) {
          ret = myjson;
        }
        if (ret && ret.children && ret.children.length == 1 && "string" === typeof ret.children[0]) {
          ret = ret.children[0];
        }
        return ret;
      };
      CSL2.XmlJSON.prototype.setAttributeOnNodeIdentifiedByNameAttribute = function(myjson, nodename, partname, attrname, val) {
        var pos, len, xml, nodes, node;
        if (attrname.slice(0, 1) === "@") {
          attrname = attrname.slice(1);
        }
        for (var i = 0, ilen = myjson.children.length; i < ilen; i += 1) {
          if (myjson.children[i].name === nodename && myjson.children[i].attrs.name === partname) {
            myjson.children[i].attrs[attrname] = val;
          }
        }
      };
      CSL2.XmlJSON.prototype.deleteNodeByNameAttribute = function(myjson, val) {
        var i, ilen;
        for (i = 0, ilen = myjson.children.length; i < ilen; i += 1) {
          if (!myjson.children[i] || "string" === typeof myjson.children[i]) {
            continue;
          }
          if (myjson.children[i].attrs.name == val) {
            myjson.children = myjson.children.slice(0, i).concat(myjson.children.slice(i + 1));
          }
        }
      };
      CSL2.XmlJSON.prototype.deleteAttribute = function(myjson, attrname) {
        var i, ilen;
        if ("undefined" !== typeof myjson.attrs[attrname]) {
          myjson.attrs.pop(attrname);
        }
      };
      CSL2.XmlJSON.prototype.setAttribute = function(myjson, attr, val) {
        myjson.attrs[attr] = val;
        return false;
      };
      CSL2.XmlJSON.prototype.nodeCopy = function(myjson, clone) {
        if (!clone) {
          var clone = {};
        }
        if ("object" === typeof clone && "undefined" === typeof clone.length) {
          for (var key in myjson) {
            if ("string" === typeof myjson[key]) {
              clone[key] = myjson[key];
            } else if ("object" === typeof myjson[key]) {
              if ("undefined" === typeof myjson[key].length) {
                clone[key] = this.nodeCopy(myjson[key], {});
              } else {
                clone[key] = this.nodeCopy(myjson[key], []);
              }
            }
          }
        } else {
          for (var i = 0, ilen = myjson.length; i < ilen; i += 1) {
            if ("string" === typeof myjson[i]) {
              clone[i] = myjson[i];
            } else {
              clone[i] = this.nodeCopy(myjson[i], {});
            }
          }
        }
        return clone;
      };
      CSL2.XmlJSON.prototype.getNodesByName = function(myjson, name, nameattrval, ret) {
        var nodes, node, pos, len;
        if (!ret) {
          var ret = [];
        }
        if (!myjson || !myjson.children) {
          return ret;
        }
        if (name === myjson.name) {
          if (nameattrval) {
            if (nameattrval === myjson.attrs.name) {
              ret.push(myjson);
            }
          } else {
            ret.push(myjson);
          }
        }
        for (var i = 0, ilen = myjson.children.length; i < ilen; i += 1) {
          if ("object" !== typeof myjson.children[i]) {
            continue;
          }
          this.getNodesByName(myjson.children[i], name, nameattrval, ret);
        }
        return ret;
      };
      CSL2.XmlJSON.prototype.nodeNameIs = function(myjson, name) {
        if (typeof myjson === "undefined") {
          return false;
        }
        if (name == myjson.name) {
          return true;
        }
        return false;
      };
      CSL2.XmlJSON.prototype.makeXml = function(myjson) {
        if ("string" === typeof myjson) {
          if (myjson.slice(0, 1) === "<") {
            myjson = this.jsonStringWalker.walkToObject(myjson);
          } else {
            myjson = JSON.parse(myjson);
          }
        }
        return myjson;
      };
      CSL2.XmlJSON.prototype.insertChildNodeAfter = function(parent, node, pos, datejson) {
        for (var i = 0, ilen = parent.children.length; i < ilen; i += 1) {
          if (node === parent.children[i]) {
            parent.children = parent.children.slice(0, i).concat([datejson]).concat(parent.children.slice(i + 1));
            break;
          }
        }
        return parent;
      };
      CSL2.XmlJSON.prototype.insertPublisherAndPlace = function(myjson) {
        if (myjson.name === "group") {
          var useme = true;
          var mustHaves = ["publisher", "publisher-place"];
          for (var i = 0, ilen = myjson.children.length; i < ilen; i += 1) {
            var haveVarname = mustHaves.indexOf(myjson.children[i].attrs.variable);
            var isText = myjson.children[i].name === "text";
            if (isText && haveVarname > -1 && !myjson.children[i].attrs.prefix && !myjson.children[i].attrs.suffix) {
              mustHaves = mustHaves.slice(0, haveVarname).concat(mustHaves.slice(haveVarname + 1));
            } else {
              useme = false;
              break;
            }
          }
          if (useme && !mustHaves.length) {
            myjson.attrs["has-publisher-and-publisher-place"] = true;
          }
        }
        for (var i = 0, ilen = myjson.children.length; i < ilen; i += 1) {
          if ("object" === typeof myjson.children[i]) {
            this.insertPublisherAndPlace(myjson.children[i]);
          }
        }
      };
      CSL2.XmlJSON.prototype.isChildOfSubstitute = function(parents) {
        if (parents.length > 0) {
          var myparents = parents.slice();
          var parent = myparents.pop();
          if (parent === "substitute") {
            return true;
          } else {
            return this.isChildOfSubstitute(myparents);
          }
        }
        return false;
      };
      CSL2.XmlJSON.prototype.addMissingNameNodes = function(myjson, parents) {
        if (!parents) {
          parents = [];
        }
        if (myjson.name === "names") {
          if (!this.isChildOfSubstitute(parents)) {
            var addName = true;
            for (var i = 0, ilen = myjson.children.length; i < ilen; i++) {
              if (myjson.children[i].name === "name") {
                addName = false;
                break;
              }
            }
            if (addName) {
              myjson.children = [{ name: "name", attrs: {}, children: [] }].concat(myjson.children);
            }
          }
        }
        parents.push(myjson.name);
        for (var i = 0, ilen = myjson.children.length; i < ilen; i += 1) {
          if ("object" === typeof myjson.children[i]) {
            this.addMissingNameNodes(myjson.children[i], parents);
          }
        }
        parents.pop();
      };
      CSL2.XmlJSON.prototype.addInstitutionNodes = function(myjson) {
        var names, thenames, institution, theinstitution, name, thename, xml, pos, len;
        if (myjson.name === "names") {
          var attributes = {};
          var insertPos = -1;
          for (var i = 0, ilen = myjson.children.length; i < ilen; i += 1) {
            if (myjson.children[i].name == "name") {
              for (var key in myjson.children[i].attrs) {
                attributes[key] = myjson.children[i].attrs[key];
              }
              attributes.delimiter = myjson.children[i].attrs.delimiter;
              attributes.and = myjson.children[i].attrs.and;
              insertPos = i;
              for (var k = 0, klen = myjson.children[i].children.length; k < klen; k += 1) {
                if (myjson.children[i].children[k].attrs.name !== "family") {
                  continue;
                }
                for (var key in myjson.children[i].children[k].attrs) {
                  attributes[key] = myjson.children[i].children[k].attrs[key];
                }
              }
            }
            if (myjson.children[i].name == "institution") {
              insertPos = -1;
              break;
            }
          }
          if (insertPos > -1) {
            var institution = this.nodeCopy(this.institution);
            for (var i = 0, ilen = CSL2.INSTITUTION_KEYS.length; i < ilen; i += 1) {
              var attrname = CSL2.INSTITUTION_KEYS[i];
              if ("undefined" !== typeof attributes[attrname]) {
                institution.children[0].attrs[attrname] = attributes[attrname];
              }
              if (attributes.delimiter) {
                institution.attrs.delimiter = attributes.delimiter;
              }
              if (attributes.and) {
                institution.attrs.and = attributes.and;
              }
            }
            myjson.children = myjson.children.slice(0, insertPos + 1).concat([institution]).concat(myjson.children.slice(insertPos + 1));
          }
        }
        for (var i = 0, ilen = myjson.children.length; i < ilen; i += 1) {
          if ("string" === typeof myjson.children[i]) {
            continue;
          }
          this.addInstitutionNodes(myjson.children[i]);
        }
      };
      CSL2.XmlJSON.prototype.flagDateMacros = function(myjson) {
        for (var i = 0, ilen = myjson.children.length; i < ilen; i += 1) {
          if (myjson.children[i].name === "macro") {
            if (this.inspectDateMacros(myjson.children[i])) {
              myjson.children[i].attrs["macro-has-date"] = "true";
            }
          }
        }
      };
      CSL2.XmlJSON.prototype.inspectDateMacros = function(myjson) {
        if (!myjson || !myjson.children) {
          return false;
        }
        if (myjson.name === "date") {
          return true;
        } else {
          for (var i = 0, ilen = myjson.children.length; i < ilen; i += 1) {
            if (this.inspectDateMacros(myjson.children[i])) {
              return true;
            }
          }
        }
        return false;
      };
      CSL2.stripXmlProcessingInstruction = function(xml) {
        if (!xml) {
          return xml;
        }
        xml = xml.replace(/^<\?[^?]+\?>/, "");
        xml = xml.replace(/<!--[^>]+-->/g, "");
        xml = xml.replace(/^\s+/g, "");
        xml = xml.replace(/\s+$/g, "");
        return xml;
      };
      CSL2.parseXml = function(str) {
        var _pos = 0;
        var _obj = { children: [] };
        var _stack = [_obj.children];
        function _listifyString(str2) {
          str2 = str2.split(/(?:\r\n|\n|\r)/).join(" ").replace(/>[	 ]+</g, "><").replace(/<\!--.*?-->/g, "");
          var lst2 = str2.split("><");
          var stylePos = null;
          for (var i2 = 0, ilen2 = lst2.length; i2 < ilen2; i2++) {
            if (i2 > 0) {
              lst2[i2] = "<" + lst2[i2];
            }
            if (i2 < lst2.length - 1) {
              lst2[i2] = lst2[i2] + ">";
            }
            if ("number" != typeof stylePos) {
              if (lst2[i2].slice(0, 7) === "<style " || lst2[i2].slice(0, 8) == "<locale ") {
                stylePos = i2;
              }
            }
          }
          lst2 = lst2.slice(stylePos);
          for (var i2 = lst2.length - 2; i2 > -1; i2--) {
            if (lst2[i2].slice(1).indexOf("<") === -1) {
              var stub = lst2[i2].slice(0, 5);
              if (lst2[i2].slice(-2) !== "/>") {
                if (stub === "<term") {
                  if (lst2[i2 + 1].slice(0, 6) === "</term") {
                    lst2[i2] = lst2[i2] + lst2[i2 + 1];
                    lst2 = lst2.slice(0, i2 + 1).concat(lst2.slice(i2 + 2));
                  }
                } else if (["<sing", "<mult"].indexOf(stub) > -1) {
                  if (lst2[i2].slice(-2) !== "/>" && lst2[i2 + 1].slice(0, 1) === "<") {
                    lst2[i2] = lst2[i2] + lst2[i2 + 1];
                    lst2 = lst2.slice(0, i2 + 1).concat(lst2.slice(i2 + 2));
                  }
                }
              }
            }
          }
          return lst2;
        }
        function _decodeHtmlEntities(str2) {
          return str2.split("&amp;").join("&").split("&quot;").join('"').split("&gt;").join(">").split("&lt;").join("<").replace(/&#([0-9]{1,6});/gi, function(match, numStr) {
            var num = parseInt(numStr, 10);
            return String.fromCharCode(num);
          }).replace(/&#x([a-f0-9]{1,6});/gi, function(match, numStr) {
            var num = parseInt(numStr, 16);
            return String.fromCharCode(num);
          });
        }
        function _getAttributes(elem2) {
          var m = elem2.match(/([^\'\"=	 ]+)=(?:\"[^\"]*\"|\'[^\']*\')/g);
          if (m) {
            for (var i2 = 0, ilen2 = m.length; i2 < ilen2; i2++) {
              m[i2] = m[i2].replace(/=.*/, "");
            }
          }
          return m;
        }
        function _getAttribute(elem2, attr) {
          var rex = RegExp("^.*[	 ]+" + attr + `=("(?:[^"]*)"|'(?:[^']*)').*$`);
          var m = elem2.match(rex);
          return m ? m[1].slice(1, -1) : null;
        }
        function _getTagName(elem2) {
          var rex = RegExp("^<([^	 />]+)");
          var m = elem2.match(rex);
          return m ? m[1] : null;
        }
        function _castObjectFromOpeningTag(elem2) {
          var obj = {};
          obj.name = _getTagName(elem2);
          obj.attrs = {};
          var attributes = _getAttributes(elem2);
          if (attributes) {
            for (var i2 = 0, ilen2 = attributes.length; i2 < ilen2; i2++) {
              var attr = {
                name: attributes[i2],
                value: _getAttribute(elem2, attributes[i2])
              };
              obj.attrs[attr.name] = _decodeHtmlEntities(attr.value);
            }
          }
          obj.children = [];
          return obj;
        }
        function _extractTextFromCompositeElement(elem2) {
          var m = elem2.match(/^.*>([^<]*)<.*$/);
          return _decodeHtmlEntities(m[1]);
        }
        function _appendToChildren(obj) {
          _stack.slice(-1)[0].push(obj);
        }
        function _extendStackWithNewChildren(obj) {
          _stack.push(obj.children);
        }
        function processElement(elem2) {
          var obj;
          if (elem2.slice(1).indexOf("<") > -1) {
            var tag = elem2.slice(0, elem2.indexOf(">") + 1);
            obj = _castObjectFromOpeningTag(tag);
            obj.children = [_extractTextFromCompositeElement(elem2)];
            _appendToChildren(obj);
          } else if (elem2.slice(-2) === "/>") {
            obj = _castObjectFromOpeningTag(elem2);
            if (_getTagName(elem2) === "term") {
              obj.children.push("");
            }
            _appendToChildren(obj);
          } else if (elem2.slice(0, 2) === "</") {
            _stack.pop();
          } else {
            obj = _castObjectFromOpeningTag(elem2);
            _appendToChildren(obj);
            _extendStackWithNewChildren(obj);
          }
        }
        var lst = _listifyString(str);
        for (var i = 0, ilen = lst.length; i < ilen; i++) {
          var elem = lst[i];
          processElement(elem);
        }
        return _obj.children[0];
      };
      CSL2.XmlDOM = function(dataObj) {
        this.dataObj = dataObj;
        if ("undefined" == typeof DOMParser) {
          DOMParser = function() {
          };
          DOMParser.prototype.parseFromString = function(str2, contentType) {
            if ("undefined" != typeof ActiveXObject) {
              var xmldata = new ActiveXObject("MSXML.DomDocument");
              xmldata.async = false;
              xmldata.loadXML(str2);
              return xmldata;
            } else if ("undefined" != typeof XMLHttpRequest) {
              var xmldata = new XMLHttpRequest();
              if (!contentType) {
                contentType = "text/xml";
              }
              xmldata.open("GET", "data:" + contentType + ";charset=utf-8," + encodeURIComponent(str2), false);
              if (xmldata.overrideMimeType) {
                xmldata.overrideMimeType(contentType);
              }
              xmldata.send(null);
              return xmldata.responseXML;
            } else if ("undefined" != typeof marknote) {
              var parser = new marknote.Parser();
              return parser.parse(str2);
            }
          };
          this.hasAttributes = function(node) {
            var ret;
            if (node.attributes && node.attributes.length) {
              ret = true;
            } else {
              ret = false;
            }
            return ret;
          };
        } else {
          this.hasAttributes = function(node) {
            var ret;
            if (node.attributes && node.attributes.length) {
              ret = true;
            } else {
              ret = false;
            }
            return ret;
          };
        }
        this.importNode = function(doc, srcElement) {
          var ret;
          if ("undefined" == typeof doc.importNode) {
            ret = this._importNode(doc, srcElement, true);
          } else {
            ret = doc.importNode(srcElement, true);
          }
          return ret;
        };
        this._importNode = function(doc, node, allChildren) {
          switch (node.nodeType) {
            // element node
            case 1:
              var newNode = doc.createElement(node.nodeName);
              if (node.attributes && node.attributes.length > 0)
                for (var i = 0, il = node.attributes.length; i < il; )
                  newNode.setAttribute(node.attributes[i].nodeName, node.getAttribute(node.attributes[i++].nodeName));
              if (allChildren && node.childNodes && node.childNodes.length > 0)
                for (var i = 0, il = node.childNodes.length; i < il; )
                  newNode.appendChild(this._importNode(doc, node.childNodes[i++], allChildren));
              return newNode;
              break;
            case 3:
            case 4:
            case 8:
          }
        };
        this.parser = new DOMParser();
        var str = '<docco><institution institution-parts="long" delimiter=", " substitute-use-first="1" use-last="1"><institution-part name="long"/></institution></docco>';
        var inst_doc = this.parser.parseFromString(str, "text/xml");
        var inst_node = inst_doc.getElementsByTagName("institution");
        this.institution = inst_node.item(0);
        var inst_part_node = inst_doc.getElementsByTagName("institution-part");
        this.institutionpart = inst_part_node.item(0);
        this.ns = "http://purl.org/net/xbiblio/csl";
      };
      CSL2.XmlDOM.prototype.clean = function(xml) {
        xml = xml.replace(/<\?[^?]+\?>/g, "");
        xml = xml.replace(/<![^>]+>/g, "");
        xml = xml.replace(/^\s+/, "");
        xml = xml.replace(/\s+$/, "");
        xml = xml.replace(/^\n*/, "");
        return xml;
      };
      CSL2.XmlDOM.prototype.getStyleId = function(myxml, styleName) {
        var text = "";
        var tagName = "id";
        if (styleName) {
          tagName = "title";
        }
        var node = myxml.getElementsByTagName(tagName);
        if (node && node.length) {
          node = node.item(0);
        }
        if (node) {
          text = node.textContent;
        }
        if (!text) {
          text = node.innerText;
        }
        if (!text) {
          text = node.innerHTML;
        }
        return text;
      };
      CSL2.XmlDOM.prototype.children = function(myxml) {
        var children, pos, len, ret;
        if (myxml) {
          ret = [];
          children = myxml.childNodes;
          for (pos = 0, len = children.length; pos < len; pos += 1) {
            if (children[pos].nodeName != "#text") {
              ret.push(children[pos]);
            }
          }
          return ret;
        } else {
          return [];
        }
      };
      CSL2.XmlDOM.prototype.nodename = function(myxml) {
        var ret = myxml.nodeName;
        return ret;
      };
      CSL2.XmlDOM.prototype.attributes = function(myxml) {
        var ret, attrs, attr, key, xml, pos, len;
        ret = new Object();
        if (myxml && this.hasAttributes(myxml)) {
          attrs = myxml.attributes;
          for (pos = 0, len = attrs.length; pos < len; pos += 1) {
            attr = attrs[pos];
            ret["@" + attr.name] = attr.value;
          }
        }
        return ret;
      };
      CSL2.XmlDOM.prototype.content = function(myxml) {
        var ret;
        if ("undefined" != typeof myxml.textContent) {
          ret = myxml.textContent;
        } else if ("undefined" != typeof myxml.innerText) {
          ret = myxml.innerText;
        } else {
          ret = myxml.txt;
        }
        return ret;
      };
      CSL2.XmlDOM.prototype.namespace = {
        "xml": "http://www.w3.org/XML/1998/namespace"
      };
      CSL2.XmlDOM.prototype.numberofnodes = function(myxml) {
        if (myxml) {
          return myxml.length;
        } else {
          return 0;
        }
      };
      CSL2.XmlDOM.prototype.getAttributeName = function(attr) {
        var ret = attr.name;
        return ret;
      };
      CSL2.XmlDOM.prototype.getAttributeValue = function(myxml, name, namespace) {
        var ret = "";
        if (namespace) {
          name = namespace + ":" + name;
        }
        if (myxml && this.hasAttributes(myxml) && myxml.getAttribute(name)) {
          ret = myxml.getAttribute(name);
        }
        return ret;
      };
      CSL2.XmlDOM.prototype.getNodeValue = function(myxml, name) {
        var ret = null;
        if (name) {
          var vals = myxml.getElementsByTagName(name);
          if (vals.length > 0) {
            if ("undefined" != typeof vals[0].textContent) {
              ret = vals[0].textContent;
            } else if ("undefined" != typeof vals[0].innerText) {
              ret = vals[0].innerText;
            } else {
              ret = vals[0].text;
            }
          }
        }
        if (ret === null && myxml && myxml.childNodes && (myxml.childNodes.length == 0 || myxml.childNodes.length == 1 && myxml.firstChild.nodeName == "#text")) {
          if ("undefined" != typeof myxml.textContent) {
            ret = myxml.textContent;
          } else if ("undefined" != typeof myxml.innerText) {
            ret = myxml.innerText;
          } else {
            ret = myxml.text;
          }
        }
        if (ret === null) {
          ret = myxml;
        }
        return ret;
      };
      CSL2.XmlDOM.prototype.setAttributeOnNodeIdentifiedByNameAttribute = function(myxml, nodename, partname, attrname, val) {
        var pos, len, xml, nodes, node;
        if (attrname.slice(0, 1) === "@") {
          attrname = attrname.slice(1);
        }
        nodes = myxml.getElementsByTagName(nodename);
        for (pos = 0, len = nodes.length; pos < len; pos += 1) {
          node = nodes[pos];
          if (node.getAttribute("name") != partname) {
            continue;
          }
          node.setAttribute(attrname, val);
        }
      };
      CSL2.XmlDOM.prototype.deleteNodeByNameAttribute = function(myxml, val) {
        var pos, len, node, nodes;
        nodes = myxml.childNodes;
        for (pos = 0, len = nodes.length; pos < len; pos += 1) {
          node = nodes[pos];
          if (!node || node.nodeType == node.TEXT_NODE) {
            continue;
          }
          if (this.hasAttributes(node) && node.getAttribute("name") == val) {
            myxml.removeChild(nodes[pos]);
          }
        }
      };
      CSL2.XmlDOM.prototype.deleteAttribute = function(myxml, attr) {
        myxml.removeAttribute(attr);
      };
      CSL2.XmlDOM.prototype.setAttribute = function(myxml, attr, val) {
        if (!myxml.ownerDocument) {
          myxml = myxml.firstChild;
        }
        if (["function", "unknown"].indexOf(typeof myxml.setAttribute) > -1) {
          myxml.setAttribute(attr, val);
        }
        return false;
      };
      CSL2.XmlDOM.prototype.nodeCopy = function(myxml) {
        var cloned_node = myxml.cloneNode(true);
        return cloned_node;
      };
      CSL2.XmlDOM.prototype.getNodesByName = function(myxml, name, nameattrval) {
        var ret, nodes, node, pos, len;
        ret = [];
        nodes = myxml.getElementsByTagName(name);
        for (pos = 0, len = nodes.length; pos < len; pos += 1) {
          node = nodes.item(pos);
          if (nameattrval && !(this.hasAttributes(node) && node.getAttribute("name") == nameattrval)) {
            continue;
          }
          ret.push(node);
        }
        return ret;
      };
      CSL2.XmlDOM.prototype.nodeNameIs = function(myxml, name) {
        if (name == myxml.nodeName) {
          return true;
        }
        return false;
      };
      CSL2.XmlDOM.prototype.makeXml = function(myxml) {
        var ret, topnode;
        if (!myxml) {
          myxml = "<docco><bogus/></docco>";
        }
        myxml = myxml.replace(/\s*<\?[^>]*\?>\s*\n*/g, "");
        var nodetree = this.parser.parseFromString(myxml, "application/xml");
        return nodetree.firstChild;
      };
      CSL2.XmlDOM.prototype.insertChildNodeAfter = function(parent, node, pos, datexml) {
        var myxml, xml;
        myxml = this.importNode(node.ownerDocument, datexml);
        parent.replaceChild(myxml, node);
        return parent;
      };
      CSL2.XmlDOM.prototype.insertPublisherAndPlace = function(myxml) {
        var group = myxml.getElementsByTagName("group");
        for (var i = 0, ilen = group.length; i < ilen; i += 1) {
          var node = group.item(i);
          var skippers = [];
          for (var j = 0, jlen = node.childNodes.length; j < jlen; j += 1) {
            if (node.childNodes.item(j).nodeType !== 1) {
              skippers.push(j);
            }
          }
          if (node.childNodes.length - skippers.length === 2) {
            var twovars = [];
            for (var j = 0, jlen = 2; j < jlen; j += 1) {
              if (skippers.indexOf(j) > -1) {
                continue;
              }
              var child = node.childNodes.item(j);
              var subskippers = [];
              for (var k = 0, klen = child.childNodes.length; k < klen; k += 1) {
                if (child.childNodes.item(k).nodeType !== 1) {
                  subskippers.push(k);
                }
              }
              if (child.childNodes.length - subskippers.length === 0) {
                twovars.push(child.getAttribute("variable"));
                if (child.getAttribute("suffix") || child.getAttribute("prefix")) {
                  twovars = [];
                  break;
                }
              }
            }
            if (twovars.indexOf("publisher") > -1 && twovars.indexOf("publisher-place") > -1) {
              node.setAttribute("has-publisher-and-publisher-place", true);
            }
          }
        }
      };
      CSL2.XmlDOM.prototype.isChildOfSubstitute = function(node) {
        if (node.parentNode) {
          if (node.parentNode.tagName.toLowerCase() === "substitute") {
            return true;
          } else {
            return this.isChildOfSubstitute(node.parentNode);
          }
        }
        return false;
      };
      CSL2.XmlDOM.prototype.addMissingNameNodes = function(myxml) {
        var nameslist = myxml.getElementsByTagName("names");
        for (var i = 0, ilen = nameslist.length; i < ilen; i += 1) {
          var names = nameslist.item(i);
          var namelist = names.getElementsByTagName("name");
          if ((!namelist || namelist.length === 0) && !this.isChildOfSubstitute(names)) {
            var doc = names.ownerDocument;
            var name = doc.createElement("name");
            names.appendChild(name);
          }
        }
      };
      CSL2.XmlDOM.prototype.addInstitutionNodes = function(myxml) {
        var names, thenames, institution, theinstitution, theinstitutionpart, name, thename, xml, pos, len;
        names = myxml.getElementsByTagName("names");
        for (pos = 0, len = names.length; pos < len; pos += 1) {
          thenames = names.item(pos);
          name = thenames.getElementsByTagName("name");
          if (name.length == 0) {
            continue;
          }
          institution = thenames.getElementsByTagName("institution");
          if (institution.length == 0) {
            theinstitution = this.importNode(myxml.ownerDocument, this.institution);
            theinstitutionpart = theinstitution.getElementsByTagName("institution-part").item(0);
            thename = name.item(0);
            thenames.insertBefore(theinstitution, thename.nextSibling);
            for (var j = 0, jlen = CSL2.INSTITUTION_KEYS.length; j < jlen; j += 1) {
              var attrname = CSL2.INSTITUTION_KEYS[j];
              var attrval = thename.getAttribute(attrname);
              if (attrval) {
                theinstitutionpart.setAttribute(attrname, attrval);
              }
            }
            var nameparts = thename.getElementsByTagName("name-part");
            for (var j = 0, jlen = nameparts.length; j < jlen; j += 1) {
              if ("family" === nameparts[j].getAttribute("name")) {
                for (var k = 0, klen = CSL2.INSTITUTION_KEYS.length; k < klen; k += 1) {
                  var attrname = CSL2.INSTITUTION_KEYS[k];
                  var attrval = nameparts[j].getAttribute(attrname);
                  if (attrval) {
                    theinstitutionpart.setAttribute(attrname, attrval);
                  }
                }
              }
            }
          }
        }
      };
      CSL2.XmlDOM.prototype.flagDateMacros = function(myxml) {
        var pos, len, thenode, thedate;
        var nodes = myxml.getElementsByTagName("macro");
        for (pos = 0, len = nodes.length; pos < len; pos += 1) {
          thenode = nodes.item(pos);
          thedate = thenode.getElementsByTagName("date");
          if (thedate.length) {
            thenode.setAttribute("macro-has-date", "true");
          }
        }
      };
      CSL2.setupXml = function(xmlObject) {
        var dataObj = {};
        var parser = null;
        if ("undefined" !== typeof xmlObject) {
          if ("string" === typeof xmlObject) {
            xmlObject = xmlObject.replace("^\uFEFF", "").replace(/^\s+/, "");
            if (xmlObject.slice(0, 1) === "<") {
              dataObj = CSL2.parseXml(xmlObject);
            } else {
              dataObj = JSON.parse(xmlObject);
            }
            parser = new CSL2.XmlJSON(dataObj);
          } else if ("undefined" !== typeof xmlObject.getAttribute) {
            parser = new CSL2.XmlDOM(xmlObject);
          } else if ("undefined" !== typeof xmlObject.toXMLString) {
            parser = new CSL2.XmlE4X(xmlObject);
          } else {
            parser = new CSL2.XmlJSON(xmlObject);
          }
        } else {
          CSL2.error("unable to parse XML input");
        }
        if (!parser) {
          CSL2.error("citeproc-js error: unable to parse CSL style or locale object");
        }
        return parser;
      };
      CSL2.getSortCompare = function(default_locale) {
        if (CSL2.stringCompare) {
          return CSL2.stringCompare;
        }
        var me = this;
        var strcmp;
        var strcmp_opts = {
          sensitivity: "base",
          ignorePunctuation: true,
          numeric: true
        };
        if (!default_locale) {
          default_locale = "en-US";
        }
        strcmp = function(a, b) {
          return CSL2.toLocaleLowerCase.call(me, a).localeCompare(CSL2.toLocaleLowerCase.call(me, b), default_locale, strcmp_opts);
        };
        var stripPunct = function(str) {
          return str.replace(/^[\[\]\'\"]*/g, "");
        };
        var getBracketPreSort = function() {
          if (!strcmp("[x", "x")) {
            return false;
          } else {
            return function(a, b) {
              return strcmp(stripPunct(a), stripPunct(b));
            };
          }
        };
        var bracketPreSort = getBracketPreSort();
        var sortCompare = function(a, b) {
          if (bracketPreSort) {
            return bracketPreSort(a, b);
          } else {
            return strcmp(a, b);
          }
        };
        return sortCompare;
      };
      CSL2.ambigConfigDiff = function(a, b) {
        var pos, len, ppos, llen;
        if (a.names.length !== b.names.length) {
          return 1;
        } else {
          for (pos = 0, len = a.names.length; pos < len; pos += 1) {
            if (a.names[pos] !== b.names[pos]) {
              return 1;
            } else {
              for (ppos = 0, llen = a.givens[pos]; ppos < llen; ppos += 1) {
                if (a.givens[pos][ppos] !== b.givens[pos][ppos]) {
                  return 1;
                }
              }
            }
          }
        }
        if (a.disambiguate != b.disambiguate) {
          return 1;
        }
        if (a.year_suffix !== b.year_suffix) {
          return 1;
        }
        return 0;
      };
      CSL2.cloneAmbigConfig = function(config, oldconfig) {
        var i, ilen, j, jlen, param;
        var ret = {};
        ret.names = [];
        ret.givens = [];
        ret.year_suffix = false;
        ret.disambiguate = false;
        for (i = 0, ilen = config.names.length; i < ilen; i += 1) {
          param = config.names[i];
          ret.names[i] = param;
        }
        for (i = 0, ilen = config.givens.length; i < ilen; i += 1) {
          param = [];
          for (j = 0, jlen = config.givens[i].length; j < jlen; j += 1) {
            param.push(config.givens[i][j]);
          }
          ret.givens.push(param);
        }
        if (oldconfig) {
          ret.year_suffix = oldconfig.year_suffix;
          ret.disambiguate = oldconfig.disambiguate;
        } else {
          ret.year_suffix = config.year_suffix;
          ret.disambiguate = config.disambiguate;
        }
        return ret;
      };
      CSL2.getAmbigConfig = function() {
        var config, ret;
        config = this.tmp.disambig_request;
        if (!config) {
          config = this.tmp.disambig_settings;
        }
        var ret = CSL2.cloneAmbigConfig(config);
        return ret;
      };
      CSL2.getMaxVals = function() {
        return this.tmp.names_max.mystack.slice();
      };
      CSL2.getMinVal = function() {
        return this.tmp["et-al-min"];
      };
      CSL2.tokenExec = function(token, Item, item) {
        var next, maybenext, exec, debug;
        debug = false;
        next = token.next;
        maybenext = false;
        var record = function(result) {
          if (result) {
            this.tmp.jump.replace("succeed");
            return token.succeed;
          } else {
            this.tmp.jump.replace("fail");
            return token.fail;
          }
        };
        if (token.test) {
          next = record.call(this, token.test(Item, item));
        }
        for (var i = 0, ilen = token.execs.length; i < ilen; i++) {
          exec = token.execs[i];
          maybenext = exec.call(token, this, Item, item);
          if (maybenext) {
            next = maybenext;
          }
        }
        if (debug) {
          CSL2.debug(token.name + " (" + token.tokentype + ") ---> done");
        }
        return next;
      };
      CSL2.expandMacro = function(macro_key_token, target) {
        var mkey, macro_nodes, end_of_macro, func;
        mkey = macro_key_token.postponed_macro;
        var sort_direction = macro_key_token.strings.sort_direction;
        macro_key_token = new CSL2.Token("group", CSL2.START);
        var hasDate = false;
        var macroid = false;
        macro_nodes = this.cslXml.getNodesByName(this.cslXml.dataObj, "macro", mkey);
        if (macro_nodes.length) {
          macroid = this.cslXml.getAttributeValue(macro_nodes[0], "cslid");
          hasDate = this.cslXml.getAttributeValue(macro_nodes[0], "macro-has-date");
        }
        if (hasDate) {
          mkey = mkey + "@" + this.build.current_default_locale;
          func = function(state) {
            if (state.tmp.extension) {
              state.tmp["doing-macro-with-date"] = true;
            }
          };
          macro_key_token.execs.push(func);
        }
        if (this.build.macro_stack.indexOf(mkey) > -1) {
          CSL2.error('CSL processor error: call to macro "' + mkey + '" would cause an infinite loop');
        } else {
          this.build.macro_stack.push(mkey);
        }
        macro_key_token.cslid = macroid;
        if (CSL2.MODULE_MACROS[mkey]) {
          macro_key_token.juris = mkey;
          this.opt.update_mode = CSL2.POSITION;
        }
        CSL2.Node.group.build.call(macro_key_token, this, target, true);
        if (!this.cslXml.getNodeValue(macro_nodes)) {
          CSL2.error('CSL style error: undefined macro "' + mkey + '"');
        }
        var mytarget = CSL2.getMacroTarget.call(this, mkey);
        if (mytarget) {
          CSL2.buildMacro.call(this, mytarget, macro_nodes);
          CSL2.configureMacro.call(this, mytarget);
        }
        if (!this.build.extension) {
          var func = /* @__PURE__ */ (function(macro_name) {
            return function(state, Item, item) {
              var next = 0;
              while (next < state.macros[macro_name].length) {
                next = CSL2.tokenExec.call(state, state.macros[macro_name][next], Item, item);
              }
            };
          })(mkey);
          var text_node = new CSL2.Token("text", CSL2.SINGLETON);
          text_node.execs.push(func);
          target.push(text_node);
        }
        end_of_macro = new CSL2.Token("group", CSL2.END);
        end_of_macro.strings.sort_direction = sort_direction;
        if (hasDate) {
          func = function(state) {
            if (state.tmp.extension) {
              state.tmp["doing-macro-with-date"] = false;
            }
          };
          end_of_macro.execs.push(func);
        }
        if (macro_key_token.juris) {
          end_of_macro.juris = mkey;
        }
        CSL2.Node.group.build.call(end_of_macro, this, target, true);
        this.build.macro_stack.pop();
      };
      CSL2.getMacroTarget = function(mkey) {
        var mytarget = false;
        if (this.build.extension) {
          mytarget = this[this.build.root + this.build.extension].tokens;
        } else if (!this.macros[mkey]) {
          mytarget = [];
          this.macros[mkey] = mytarget;
        }
        return mytarget;
      };
      CSL2.buildMacro = function(mytarget, macro_nodes) {
        var builder = CSL2.makeBuilder(this, mytarget);
        var mynode;
        if ("undefined" === typeof macro_nodes.length) {
          mynode = macro_nodes;
        } else {
          mynode = macro_nodes[0];
        }
        builder(mynode);
      };
      CSL2.configureMacro = function(mytarget) {
        if (!this.build.extension) {
          this.configureTokenList(mytarget);
        }
      };
      CSL2.XmlToToken = function(state, tokentype, explicitTarget, var_stack) {
        var name, txt, attrfuncs, attributes, decorations, token, key, target;
        name = state.cslXml.nodename(this);
        if (state.build.skip && state.build.skip !== name) {
          return;
        }
        if (!name) {
          txt = state.cslXml.content(this);
          if (txt) {
            state.build.text = txt;
          }
          return;
        }
        if (!CSL2.Node[state.cslXml.nodename(this)]) {
          CSL2.error('Undefined node name "' + name + '".');
        }
        attrfuncs = [];
        attributes = state.cslXml.attributes(this);
        decorations = CSL2.setDecorations.call(this, state, attributes);
        token = new CSL2.Token(name, tokentype);
        if (tokentype !== CSL2.END || name === "if" || name === "else-if" || name === "layout") {
          for (var key in attributes) {
            if (attributes.hasOwnProperty(key)) {
              if (tokentype === CSL2.END && key !== "@language" && key !== "@locale") {
                continue;
              }
              if (attributes.hasOwnProperty(key)) {
                if (CSL2.Attributes[key]) {
                  try {
                    CSL2.Attributes[key].call(token, state, "" + attributes[key]);
                  } catch (e) {
                    CSL2.error(key + " attribute: " + e);
                  }
                } else {
                  CSL2.debug('warning: undefined attribute "' + key + '" in style');
                }
              }
            }
          }
          token.decorations = decorations;
          if (CSL2.DATE_VARIABLES.indexOf(attributes["@variable"]) > -1) {
            var_stack.push(token.variables);
          }
        } else if (tokentype === CSL2.END && attributes["@variable"]) {
          token.hasVariable = true;
          if (CSL2.DATE_VARIABLES.indexOf(attributes["@variable"]) > -1) {
            token.variables = var_stack.pop();
          }
        }
        if (explicitTarget) {
          target = explicitTarget;
        } else {
          target = state[state.build.area].tokens;
        }
        CSL2.Node[name].build.call(token, state, target, true);
      };
      CSL2.DateParser = function() {
        var epochPairs = [
          ["\u660E\u6CBB", 1867],
          ["\u5927\u6B63", 1911],
          ["\u662D\u548C", 1925],
          ["\u5E73\u6210", 1988]
        ];
        var epochYearByName = {};
        for (var i = 0, ilen = epochPairs.length; i < ilen; i++) {
          var key = epochPairs[i][0];
          var val = epochPairs[i][1];
          epochYearByName[key] = val;
        }
        var epochMatchStrings = [];
        var epochMap = {};
        for (var i = 0, ilen = epochPairs.length; i < ilen; i++) {
          var pair = epochPairs[i];
          var val = pair[0];
          epochMatchStrings.push(val);
          epochMap[pair[0]] = pair[1];
        }
        var epochMatchString = epochMatchStrings.join("|");
        var epochSplitter = new RegExp("(?:" + epochMatchString + ")(?:[0-9]+)");
        var epochMatcher = new RegExp("(?:" + epochMatchString + ")(?:[0-9]+)", "g");
        var kanjiMonthDay = /(\u6708|\u5E74)/g;
        var kanjiYear = /\u65E5/g;
        var kanjiRange = /\u301c/g;
        var yearLast = "(?:[?0-9]{1,2}%%NUMD%%){0,2}[?0-9]{4}(?![0-9])";
        var yearFirst = "[?0-9]{4}(?:%%NUMD%%[?0-9]{1,2}){0,2}(?![0-9])";
        var numberVal = "[?0-9]{1,3}";
        var rangeSeparator = "[%%DATED%%]";
        var fuzzyChar = "[?~]";
        var chars = "[^-/~?0-9]+";
        var rexString = "(" + yearFirst + "|" + yearLast + "|" + numberVal + "|" + rangeSeparator + "|" + fuzzyChar + "|" + chars + ")";
        var rexDash = new RegExp(rexString.replace(/%%NUMD%%/g, "-").replace(/%%DATED%%/g, "-"));
        var rexDashSlash = new RegExp(rexString.replace(/%%NUMD%%/g, "-").replace(/%%DATED%%/g, "/"));
        var rexSlashDash = new RegExp(rexString.replace(/%%NUMD%%/g, "/").replace(/%%DATED%%/g, "-"));
        var monthString = "january february march april may june july august september october november december spring summer fall winter spring summer";
        this.monthStrings = monthString.split(" ");
        this.setOrderDayMonth = function() {
          this.monthGuess = 1;
          this.dayGuess = 0;
        };
        this.setOrderMonthDay = function() {
          this.monthGuess = 0;
          this.dayGuess = 1;
        };
        this.resetDateParserMonths = function() {
          this.monthSets = [];
          for (var i2 = 0, ilen2 = this.monthStrings.length; i2 < ilen2; i2++) {
            this.monthSets.push([this.monthStrings[i2]]);
          }
          this.monthAbbrevs = [];
          for (var i2 = 0, ilen2 = this.monthSets.length; i2 < ilen2; i2++) {
            this.monthAbbrevs.push([]);
            for (var j = 0, jlen = this.monthSets[i2].length; j < jlen; j++) {
              this.monthAbbrevs[i2].push(this.monthSets[i2][0].slice(0, 3));
            }
          }
          this.monthRexes = [];
          for (var i2 = 0, ilen2 = this.monthAbbrevs.length; i2 < ilen2; i2++) {
            this.monthRexes.push(new RegExp("(?:" + this.monthAbbrevs[i2].join("|") + ")"));
          }
        };
        this.addDateParserMonths = function(lst) {
          if ("string" === typeof lst) {
            lst = lst.split(/\s+/);
          }
          if (lst.length !== 12 && lst.length !== 16) {
            CSL2.debug("month [+season] list of " + lst.length + ", expected 12 or 16. Ignoring.");
            return;
          }
          for (var i2 = 0, ilen2 = lst.length; i2 < ilen2; i2++) {
            var abbrevLength = null;
            var skip = false;
            var insert = 3;
            var extendedSets = {};
            for (var j = 0, jlen = this.monthAbbrevs.length; j < jlen; j++) {
              extendedSets[j] = {};
              if (j === i2) {
                for (var k = 0, klen = this.monthAbbrevs[i2].length; k < klen; k++) {
                  if (this.monthAbbrevs[i2][k] === lst[i2].slice(0, this.monthAbbrevs[i2][k].length)) {
                    skip = true;
                    break;
                  }
                }
              } else {
                for (var k = 0, klen = this.monthAbbrevs[j].length; k < klen; k++) {
                  abbrevLength = this.monthAbbrevs[j][k].length;
                  if (this.monthAbbrevs[j][k] === lst[i2].slice(0, abbrevLength)) {
                    while (this.monthSets[j][k].slice(0, abbrevLength) === lst[i2].slice(0, abbrevLength)) {
                      if (abbrevLength > lst[i2].length || abbrevLength > this.monthSets[j][k].length) {
                        CSL2.debug("unable to disambiguate month string in date parser: " + lst[i2]);
                        break;
                      } else {
                        abbrevLength += 1;
                      }
                    }
                    insert = abbrevLength;
                    extendedSets[j][k] = abbrevLength;
                  }
                }
              }
              for (var jKey in extendedSets) {
                for (var kKey in extendedSets[jKey]) {
                  abbrevLength = extendedSets[jKey][kKey];
                  jKey = parseInt(jKey, 10);
                  kKey = parseInt(kKey, 10);
                  this.monthAbbrevs[jKey][kKey] = this.monthSets[jKey][kKey].slice(0, abbrevLength);
                }
              }
            }
            if (!skip) {
              this.monthSets[i2].push(lst[i2]);
              this.monthAbbrevs[i2].push(lst[i2].slice(0, insert));
            }
          }
          this.monthRexes = [];
          this.monthRexStrs = [];
          for (var i2 = 0, ilen2 = this.monthAbbrevs.length; i2 < ilen2; i2++) {
            this.monthRexes.push(new RegExp("^(?:" + this.monthAbbrevs[i2].join("|") + ")"));
            this.monthRexStrs.push("^(?:" + this.monthAbbrevs[i2].join("|") + ")");
          }
          if (this.monthAbbrevs.length === 18) {
            for (var i2 = 12, ilen2 = 14; i2 < ilen2; i2++) {
              this.monthRexes[i2 + 4] = new RegExp("^(?:" + this.monthAbbrevs[i2].join("|") + ")");
              this.monthRexStrs[i2 + 4] = "^(?:" + this.monthAbbrevs[i2].join("|") + ")";
            }
          }
        };
        this.convertDateObjectToArray = function(thedate) {
          thedate["date-parts"] = [];
          thedate["date-parts"].push([]);
          var slicelen = 0;
          var part;
          for (var i2 = 0, ilen2 = 3; i2 < ilen2; i2++) {
            part = ["year", "month", "day"][i2];
            if (!thedate[part]) {
              break;
            }
            slicelen += 1;
            thedate["date-parts"][0].push(thedate[part]);
            delete thedate[part];
          }
          thedate["date-parts"].push([]);
          for (var i2 = 0, ilen2 = slicelen; i2 < ilen2; i2++) {
            part = ["year_end", "month_end", "day_end"][i2];
            if (!thedate[part]) {
              break;
            }
            thedate["date-parts"][1].push(thedate[part]);
            delete thedate[part];
          }
          if (thedate["date-parts"][0].length !== thedate["date-parts"][1].length) {
            thedate["date-parts"].pop();
          }
          return thedate;
        };
        this.convertDateObjectToString = function(thedate) {
          var ret = [];
          for (var i2 = 0, ilen2 = 3; i2 < ilen2; i2 += 1) {
            if (thedate[CSL2.DATE_PARTS_ALL[i2]]) {
              ret.push(thedate[CSL2.DATE_PARTS_ALL[i2]]);
            } else {
              break;
            }
          }
          return ret.join("-");
        };
        this._parseNumericDate = function(ret, delim, suff, txt) {
          if (!suff) {
            suff = "";
          }
          var lst = txt.split(delim);
          for (var i2 = 0, ilen2 = lst.length; i2 < ilen2; i2++) {
            if (lst[i2].length === 4) {
              ret["year" + suff] = lst[i2].replace(/^0*/, "");
              if (!i2) {
                lst = lst.slice(1);
              } else {
                lst = lst.slice(0, i2);
              }
              break;
            }
          }
          for (var i2 = 0, ilen2 = lst.length; i2 < ilen2; i2++) {
            lst[i2] = parseInt(lst[i2], 10);
          }
          if (lst.length === 1 || lst.length === 2 && !lst[1]) {
            var month = lst[0];
            if (month) {
              ret["month" + suff] = "" + lst[0];
            }
          } else if (lst.length === 2) {
            if (lst[this.monthGuess] > 12) {
              var month = lst[this.dayGuess];
              var day = lst[this.monthGuess];
              if (month) {
                ret["month" + suff] = "" + month;
                if (day) {
                  ret["day" + suff] = "" + day;
                }
              }
            } else {
              var month = lst[this.monthGuess];
              var day = lst[this.dayGuess];
              if (month) {
                ret["month" + suff] = "" + month;
                if (day) {
                  ret["day" + suff] = "" + day;
                }
              }
            }
          }
        };
        this.parseDateToObject = function(txt) {
          var orig = txt;
          var slashPos = -1;
          var dashPos = -1;
          var yearIsNegative = false;
          var lst;
          if (txt) {
            txt = txt.replace(/^(.*[0-9])T[0-9].*/, "$1");
            if (txt.slice(0, 1) === "-") {
              yearIsNegative = true;
              txt = txt.slice(1);
            }
            if (txt.match(/^[0-9]{1,3}$/)) {
              while (txt.length < 4) {
                txt = "0" + txt;
              }
            }
            txt = "" + txt;
            txt = txt.replace(/\s*[0-9]{2}:[0-9]{2}(?::[0-9]+)/, "");
            var m = txt.match(kanjiMonthDay);
            if (m) {
              txt = txt.replace(/\s+/g, "");
              txt = txt.replace(kanjiYear, "");
              txt = txt.replace(kanjiMonthDay, "-");
              txt = txt.replace(kanjiRange, "/");
              txt = txt.replace(/\-\//g, "/");
              txt = txt.replace(/-$/g, "");
              var slst = txt.split(epochSplitter);
              lst = [];
              var mm = txt.match(epochMatcher);
              if (mm) {
                var mmx = [];
                for (var i2 = 0, ilen2 = mm.length; i2 < ilen2; i2++) {
                  mmx = mmx.concat(mm[i2].match(/([^0-9]+)([0-9]+)/).slice(1));
                }
                for (var i2 = 0, ilen2 = slst.length; i2 < ilen2; i2++) {
                  lst.push(slst[i2]);
                  if (i2 !== ilen2 - 1) {
                    var mmpos = i2 * 2;
                    lst.push(mmx[mmpos]);
                    lst.push(mmx[mmpos + 1]);
                  }
                }
              } else {
                lst = slst;
              }
              for (var i2 = 1, ilen2 = lst.length; i2 < ilen2; i2 += 3) {
                lst[i2 + 1] = epochMap[lst[i2]] + parseInt(lst[i2 + 1], 10);
                lst[i2] = "";
              }
              txt = lst.join("");
              txt = txt.replace(/\s*-\s*$/, "").replace(/\s*-\s*\//, "/");
              txt = txt.replace(/\.\s*$/, "");
              txt = txt.replace(/\.(?! )/, "");
              slashPos = txt.indexOf("/");
              dashPos = txt.indexOf("-");
            }
          }
          txt = txt.replace(/([A-Za-z])\./g, "$1");
          var number = "";
          var note = "";
          var thedate = {};
          var rangeDelim;
          var dateDelim;
          if (txt.slice(0, 1) === '"' && txt.slice(-1) === '"') {
            thedate.literal = txt.slice(1, -1);
            return thedate;
          }
          if (slashPos > -1 && dashPos > -1) {
            var slashCount = txt.split("/");
            if (slashCount.length > 3) {
              rangeDelim = "-";
              txt = txt.replace(/\_/g, "-");
              dateDelim = "/";
              lst = txt.split(rexSlashDash);
            } else {
              rangeDelim = "/";
              txt = txt.replace(/\_/g, "/");
              dateDelim = "-";
              lst = txt.split(rexDashSlash);
            }
          } else {
            txt = txt.replace(/\//g, "-");
            txt = txt.replace(/\_/g, "-");
            rangeDelim = "-";
            dateDelim = "-";
            lst = txt.split(rexDash);
          }
          var ret = [];
          for (var i2 = 0, ilen2 = lst.length; i2 < ilen2; i2++) {
            var m = lst[i2].match(/^\s*([\-\/]|[^\-\/\~\?0-9]+|[\-~?0-9]+)\s*$/);
            if (m) {
              ret.push(m[1]);
            }
          }
          var delimPos = ret.indexOf(rangeDelim);
          var delims = [];
          var isRange = false;
          if (delimPos > -1) {
            delims.push([0, delimPos]);
            delims.push([delimPos + 1, ret.length]);
            isRange = true;
          } else {
            delims.push([0, ret.length]);
          }
          var suff = "";
          for (var i2 = 0, ilen2 = delims.length; i2 < ilen2; i2++) {
            var delim = delims[i2];
            var date = ret.slice(delim[0], delim[1]);
            outer:
              for (var j = 0, jlen = date.length; j < jlen; j++) {
                var element = date[j];
                if (element.indexOf(dateDelim) > -1) {
                  this._parseNumericDate(thedate, dateDelim, suff, element);
                  continue;
                }
                if (element.match(/[0-9]{4}/)) {
                  thedate["year" + suff] = element.replace(/^0*/, "");
                  continue;
                }
                if (element === "~" || element === "?" || element === "c" || element.match(/^cir/)) {
                  thedate.circa = true;
                }
                for (var k = 0, klen = this.monthRexes.length; k < klen; k++) {
                  if (element.toLocaleLowerCase().match(this.monthRexes[k])) {
                    thedate["month" + suff] = "" + (parseInt(k, 10) + 1);
                    continue outer;
                  }
                }
                if (element.match(/^[0-9]+$/)) {
                  number = element;
                }
                if (element.toLocaleLowerCase().match(/^bc/) && number) {
                  thedate["year" + suff] = "" + number * -1;
                  number = "";
                  continue;
                }
                if (element.toLocaleLowerCase().match(/^ad/) && number) {
                  thedate["year" + suff] = "" + number;
                  number = "";
                  continue;
                }
                if (element.toLocaleLowerCase().match(/(?:mic|tri|hil|eas)/) && !thedate["season" + suff]) {
                  note = element;
                  continue;
                }
              }
            if (number) {
              thedate["day" + suff] = number;
              number = "";
            }
            if (note && !thedate["season" + suff]) {
              thedate["season" + suff] = note.trim();
              note = "";
            }
            suff = "_end";
          }
          if (isRange) {
            for (var j = 0, jlen = CSL2.DATE_PARTS_ALL.length; j < jlen; j++) {
              var item = CSL2.DATE_PARTS_ALL[j];
              if (thedate[item] && !thedate[item + "_end"]) {
                thedate[item + "_end"] = thedate[item];
              } else if (!thedate[item] && thedate[item + "_end"]) {
                thedate[item] = thedate[item + "_end"];
              }
            }
          }
          if (!thedate.year || thedate.year && thedate.day && !thedate.month) {
            thedate = { "literal": orig };
          }
          var parts = ["year", "month", "day", "year_end", "month_end", "day_end"];
          for (var i2 = 0, ilen2 = parts.length; i2 < ilen2; i2++) {
            var part = parts[i2];
            if ("string" === typeof thedate[part] && thedate[part].match(/^[0-9]+$/)) {
              thedate[part] = parseInt(thedate[part], 10);
            }
          }
          if (yearIsNegative && Object.keys(thedate).indexOf("year") > -1) {
            thedate.year = thedate.year * -1;
          }
          return thedate;
        };
        this.parseDateToArray = function(txt) {
          return this.convertDateObjectToArray(this.parseDateToObject(txt));
        };
        this.parseDateToString = function(txt) {
          return this.convertDateObjectToString(this.parseDateToObject(txt));
        };
        this.parse = function(txt) {
          return this.parseDateToObject(txt);
        };
        this.setOrderMonthDay();
        this.resetDateParserMonths();
      };
      CSL2.DateParser = new CSL2.DateParser();
      CSL2.Engine = function(sys, style, lang, forceLang) {
        var attrs, langspec;
        this.processor_version = CSL2.PROCESSOR_VERSION;
        this.csl_version = "1.0";
        this.sys = sys;
        if (typeof Object.assign != "function") {
          Object.defineProperty(Object, "assign", {
            value: function assign(target) {
              "use strict";
              if (target == null) {
                throw new TypeError("Cannot convert undefined or null to object");
              }
              var to = Object(target);
              for (var index = 1; index < arguments.length; index++) {
                var nextSource = arguments[index];
                if (nextSource != null) {
                  for (var nextKey in nextSource) {
                    if (Object.prototype.hasOwnProperty.call(nextSource, nextKey)) {
                      to[nextKey] = nextSource[nextKey];
                    }
                  }
                }
              }
              return to;
            },
            writable: true,
            configurable: true
          });
        }
        if (sys.variableWrapper) {
          CSL2.VARIABLE_WRAPPER_PREPUNCT_REX = new RegExp("^([" + [" "].concat(CSL2.SWAPPING_PUNCTUATION).join("") + "]*)(.*)");
        }
        if (CSL2.retrieveStyleModule) {
          this.sys.retrieveStyleModule = CSL2.retrieveStyleModule;
        }
        if (CSL2.getAbbreviation) {
          this.sys.getAbbreviation = CSL2.getAbbreviation;
        }
        if (this.sys.stringCompare) {
          CSL2.stringCompare = this.sys.stringCompare;
        }
        this.sys.AbbreviationSegments = CSL2.AbbreviationSegments;
        this.transform = new CSL2.Transform(this);
        this.setParseNames = function(val) {
          this.opt["parse-names"] = val;
        };
        this.opt = new CSL2.Engine.Opt();
        this.tmp = new CSL2.Engine.Tmp();
        this.build = new CSL2.Engine.Build();
        this.fun = new CSL2.Engine.Fun(this);
        this.configure = new CSL2.Engine.Configure();
        this.citation_sort = new CSL2.Engine.CitationSort();
        this.bibliography_sort = new CSL2.Engine.BibliographySort();
        this.citation = new CSL2.Engine.Citation(this);
        this.bibliography = new CSL2.Engine.Bibliography();
        this.intext = new CSL2.Engine.InText();
        this.output = new CSL2.Output.Queue(this);
        this.dateput = new CSL2.Output.Queue(this);
        this.cslXml = CSL2.setupXml(style);
        for (var i in CSL2.SYS_OPTIONS) {
          var option = CSL2.SYS_OPTIONS[i];
          if ("boolean" === typeof this.sys[option]) {
            this.opt.development_extensions[option] = this.sys[option];
          }
        }
        if (this.opt.development_extensions.uppercase_subtitles || this.opt.development_extensions.implicit_short_title) {
          this.opt.development_extensions.main_title_from_short_title = true;
        }
        if (this.opt.development_extensions.csl_reverse_lookup_support) {
          this.build.cslNodeId = 0;
          this.setCslNodeIds = function(myxml, nodename) {
            var children = this.cslXml.children(myxml);
            this.cslXml.setAttribute(myxml, "cslid", this.build.cslNodeId);
            this.opt.nodenames.push(nodename);
            this.build.cslNodeId += 1;
            for (var i2 = 0, ilen = this.cslXml.numberofnodes(children); i2 < ilen; i2 += 1) {
              nodename = this.cslXml.nodename(children[i2]);
              if (nodename) {
                this.setCslNodeIds(children[i2], nodename);
              }
            }
          };
          this.setCslNodeIds(this.cslXml.dataObj, "style");
        }
        this.cslXml.addMissingNameNodes(this.cslXml.dataObj);
        this.cslXml.addInstitutionNodes(this.cslXml.dataObj);
        this.cslXml.insertPublisherAndPlace(this.cslXml.dataObj);
        this.cslXml.flagDateMacros(this.cslXml.dataObj);
        attrs = this.cslXml.attributes(this.cslXml.dataObj);
        if ("undefined" === typeof attrs["@sort-separator"]) {
          this.cslXml.setAttribute(this.cslXml.dataObj, "sort-separator", ", ");
        }
        this.opt["initialize-with-hyphen"] = true;
        this.setStyleAttributes();
        this.opt.xclass = this.cslXml.getAttributeValue(this.cslXml.dataObj, "class");
        this.opt["class"] = this.opt.xclass;
        this.opt.styleID = this.cslXml.getStyleId(this.cslXml.dataObj);
        this.opt.styleName = this.cslXml.getStyleId(this.cslXml.dataObj, true);
        if (this.opt.version.slice(0, 4) === "1.1m") {
          this.opt.development_extensions.consolidate_legal_items = true;
          this.opt.development_extensions.consolidate_container_items = true;
          this.opt.development_extensions.main_title_from_short_title = true;
          this.opt.development_extensions.expect_and_symbol_form = true;
          this.opt.development_extensions.require_explicit_legal_case_title_short = true;
          this.opt.development_extensions.force_jurisdiction = true;
          this.opt.development_extensions.force_title_abbrev_fallback = true;
        }
        if (lang) {
          lang = lang.replace("_", "-");
          lang = CSL2.normalizeLocaleStr(lang);
        }
        if (this.opt["default-locale"][0]) {
          this.opt["default-locale"][0] = this.opt["default-locale"][0].replace("_", "-");
          this.opt["default-locale"][0] = CSL2.normalizeLocaleStr(this.opt["default-locale"][0]);
        }
        if (lang && forceLang) {
          this.opt["default-locale"] = [lang];
        }
        if (lang && !forceLang && this.opt["default-locale"][0]) {
          lang = this.opt["default-locale"][0];
        }
        if (this.opt["default-locale"].length === 0) {
          if (!lang) {
            lang = "en-US";
          }
          this.opt["default-locale"].push("en-US");
        }
        if (!lang) {
          lang = this.opt["default-locale"][0];
        }
        langspec = CSL2.localeResolve(lang);
        this.opt.lang = langspec.best;
        this.opt["default-locale"][0] = langspec.best;
        this.locale = {};
        if (!this.opt["default-locale-sort"]) {
          this.opt["default-locale-sort"] = this.opt["default-locale"][0];
        }
        if ("dale|".localeCompare("daleb", this.opt["default-locale-sort"]) > -1) {
          this.opt.sort_sep = "@";
        } else {
          this.opt.sort_sep = "|";
        }
        this.localeConfigure(langspec);
        function makeRegExp(lst) {
          var lst = lst.slice();
          var ret = new RegExp("(?:(?:[?!:]*\\s+|-|^)(?:" + lst.join("|") + ")(?=[!?:]*\\s+|-|$))", "g");
          return ret;
        }
        this.locale[this.opt.lang].opts["skip-words-regexp"] = makeRegExp(this.locale[this.opt.lang].opts["skip-words"]);
        this.output.adjust = new CSL2.Output.Queue.adjust(this.getOpt("punctuation-in-quote"));
        this.registry = new CSL2.Registry(this);
        this.macros = {};
        this.build.area = "citation";
        var area_nodes = this.cslXml.getNodesByName(this.cslXml.dataObj, this.build.area);
        this.buildTokenLists(area_nodes, this[this.build.area].tokens);
        this.build.area = "bibliography";
        var area_nodes = this.cslXml.getNodesByName(this.cslXml.dataObj, this.build.area);
        this.buildTokenLists(area_nodes, this[this.build.area].tokens);
        this.build.area = "intext";
        var area_nodes = this.cslXml.getNodesByName(this.cslXml.dataObj, this.build.area);
        this.buildTokenLists(area_nodes, this[this.build.area].tokens);
        if (this.opt.parallel.enable) {
          this.parallel = new CSL2.Parallel(this);
        }
        this.juris = {};
        this.configureTokenLists();
        this.disambiguate = new CSL2.Disambiguation(this);
        this.splice_delimiter = false;
        this.fun.dateparser = CSL2.DateParser;
        this.fun.flipflopper = new CSL2.Util.FlipFlopper(this);
        this.setCloseQuotesArray();
        this.fun.ordinalizer.init(this);
        this.fun.long_ordinalizer.init(this);
        this.fun.page_mangler = CSL2.Util.PageRangeMangler.getFunction(this, "page");
        this.fun.year_mangler = CSL2.Util.PageRangeMangler.getFunction(this, "year");
        this.setOutputFormat("html");
      };
      CSL2.Engine.prototype.setCloseQuotesArray = function() {
        var ret;
        ret = [];
        ret.push(this.getTerm("close-quote"));
        ret.push(this.getTerm("close-inner-quote"));
        ret.push('"');
        ret.push("'");
        this.opt.close_quotes_array = ret;
      };
      CSL2.makeBuilder = function(me, target) {
        var var_stack = [];
        var node_stack = [];
        function runStart(node) {
          node_stack.push(node);
          CSL2.XmlToToken.call(node, me, CSL2.START, target, var_stack);
        }
        function runEnd() {
          var node = node_stack.pop();
          CSL2.XmlToToken.call(node, me, CSL2.END, target, var_stack);
        }
        function runSingle(node) {
          CSL2.XmlToToken.call(node, me, CSL2.SINGLETON, target, var_stack);
        }
        function buildStyle(nodes, parent, node_stack2) {
          if (!node_stack2) {
            node_stack2 = [];
          }
          if (!nodes) {
            nodes = [];
          }
          if ("undefined" === typeof nodes.length) {
            nodes = [nodes];
          }
          for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            if (me.cslXml.nodename(node) === null) {
              continue;
            }
            if (parent && me.cslXml.nodename(node) === "date") {
              CSL2.Util.fixDateNode.call(me, parent, i, node);
              node = me.cslXml.children(parent)[i];
            }
            if (me.cslXml.numberofnodes(me.cslXml.children(node))) {
              runStart(node);
              buildStyle(me.cslXml.children(node), node, node_stack2);
              runEnd();
            } else {
              runSingle(node);
            }
          }
        }
        return buildStyle;
      };
      CSL2.Engine.prototype.buildTokenLists = function(area_nodes, target) {
        if (!this.cslXml.getNodeValue(area_nodes)) {
          return;
        }
        var builder = CSL2.makeBuilder(this, target);
        var mynode;
        if ("undefined" === typeof area_nodes.length) {
          mynode = area_nodes;
        } else {
          mynode = area_nodes[0];
        }
        builder(mynode);
      };
      CSL2.Engine.prototype.setStyleAttributes = function() {
        var dummy, attributes, attrname;
        var dummy = {};
        dummy.name = this.cslXml.nodename(this.cslXml.dataObj);
        attributes = this.cslXml.attributes(this.cslXml.dataObj);
        for (attrname in attributes) {
          if (attributes.hasOwnProperty(attrname)) {
            CSL2.Attributes[attrname].call(dummy, this, attributes[attrname]);
          }
        }
      };
      CSL2.Engine.prototype.getTerm = function(term, form, plural, gender, mode, forceDefaultLocale) {
        if (term && term.match(/[A-Z]/) && term === term.toUpperCase()) {
          CSL2.debug("Warning: term key is in uppercase form: " + term);
          term = term.toLowerCase();
        }
        var lang;
        if (forceDefaultLocale) {
          lang = this.opt["default-locale"][0];
        } else {
          lang = this.opt.lang;
        }
        var ret = CSL2.Engine.getField(CSL2.LOOSE, this.locale[lang].terms, term, form, plural, gender);
        if (!ret && term === "range-delimiter") {
          ret = "\u2013";
        }
        if (typeof ret === "undefined") {
          if (mode === CSL2.STRICT) {
            CSL2.error('Error in getTerm: term "' + term + '" does not exist.');
          } else if (mode === CSL2.TOLERANT) {
            ret = "";
          }
        }
        if (ret) {
          this.tmp.cite_renders_content = true;
        }
        return ret;
      };
      CSL2.Engine.prototype.getDate = function(form, forceDefaultLocale) {
        var lang;
        if (forceDefaultLocale) {
          lang = this.opt["default-locale"];
        } else {
          lang = this.opt.lang;
        }
        if (this.locale[lang].dates[form]) {
          return this.locale[lang].dates[form];
        } else {
          return false;
        }
      };
      CSL2.Engine.prototype.getOpt = function(arg) {
        if ("undefined" !== typeof this.locale[this.opt.lang].opts[arg]) {
          return this.locale[this.opt.lang].opts[arg];
        } else {
          return false;
        }
      };
      CSL2.Engine.prototype.getVariable = function(Item, varname, form, plural) {
        return CSL2.Engine.getField(CSL2.LOOSE, Item, varname, form, plural);
      };
      CSL2.Engine.prototype.getDateNum = function(ItemField, partname) {
        if ("undefined" === typeof ItemField) {
          return 0;
        } else {
          return ItemField[partname];
        }
      };
      CSL2.Engine.getField = function(mode, hash, term, form, plural, gender) {
        var ret, forms, f, pos, len, hashterm;
        ret = "";
        if ("undefined" === typeof hash[term]) {
          if (mode === CSL2.STRICT) {
            CSL2.error('Error in getField: term "' + term + '" does not exist.');
          } else {
            return void 0;
          }
        }
        if (gender && hash[term][gender]) {
          hashterm = hash[term][gender];
        } else {
          hashterm = hash[term];
        }
        forms = [];
        if (form === "symbol") {
          forms = ["symbol", "short"];
        } else if (form === "verb-short") {
          forms = ["verb-short", "verb"];
        } else if (form !== "long") {
          forms = [form];
        }
        forms = forms.concat(["long"]);
        len = forms.length;
        for (pos = 0; pos < len; pos += 1) {
          f = forms[pos];
          if ("string" === typeof hashterm || "number" === typeof hashterm) {
            ret = hashterm;
          } else if ("undefined" !== typeof hashterm[f]) {
            if ("string" === typeof hashterm[f] || "number" === typeof hashterm[f]) {
              ret = hashterm[f];
            } else {
              if ("number" === typeof plural) {
                ret = hashterm[f][plural];
              } else {
                ret = hashterm[f][0];
              }
            }
            break;
          }
        }
        return ret;
      };
      CSL2.Engine.prototype.configureTokenLists = function() {
        var area, pos, len;
        len = CSL2.AREAS.length;
        for (pos = 0; pos < len; pos += 1) {
          area = CSL2.AREAS[pos];
          var tokens = this[area].tokens;
          this.configureTokenList(tokens);
        }
        this.version = CSL2.version;
        return this.state;
      };
      CSL2.Engine.prototype.configureTokenList = function(tokens) {
        var dateparts_master, token, dateparts, part, ppos, pppos, llen, lllen;
        dateparts_master = ["year", "month", "day"];
        llen = tokens.length - 1;
        for (ppos = llen; ppos > -1; ppos += -1) {
          token = tokens[ppos];
          if ("date" === token.name && CSL2.END === token.tokentype) {
            dateparts = [];
          }
          if ("date-part" === token.name && token.strings.name) {
            lllen = dateparts_master.length;
            for (pppos = 0; pppos < lllen; pppos += 1) {
              part = dateparts_master[pppos];
              if (part === token.strings.name) {
                dateparts.push(token.strings.name);
              }
            }
          }
          if ("date" === token.name && CSL2.START === token.tokentype) {
            dateparts.reverse();
            token.dateparts = dateparts;
          }
          token.next = ppos + 1;
          if (token.name && CSL2.Node[token.name].configure) {
            CSL2.Node[token.name].configure.call(token, this, ppos);
          }
        }
      };
      CSL2.Engine.prototype.refetchItems = function(ids) {
        var ret = [];
        for (var i = 0, ilen = ids.length; i < ilen; i += 1) {
          ret.push(this.refetchItem("" + ids[i]));
        }
        return ret;
      };
      CSL2.ITERATION = 0;
      CSL2.Engine.prototype.retrieveItem = function(id) {
        var Item, m, i;
        if (!this.tmp.loadedItemIDs[id]) {
          this.tmp.loadedItemIDs[id] = true;
        } else {
          return this.registry.refhash[id];
        }
        if (this.opt.development_extensions.normalize_lang_keys_to_lowercase && "boolean" === typeof this.opt.development_extensions.normalize_lang_keys_to_lowercase) {
          for (var i = 0, ilen = this.opt["default-locale"].length; i < ilen; i += 1) {
            this.opt["default-locale"][i] = this.opt["default-locale"][i].toLowerCase();
          }
          for (var i = 0, ilen = this.opt["locale-translit"].length; i < ilen; i += 1) {
            this.opt["locale-translit"][i] = this.opt["locale-translit"][i].toLowerCase();
          }
          for (var i = 0, ilen = this.opt["locale-translat"].length; i < ilen; i += 1) {
            this.opt["locale-translat"][i] = this.opt["locale-translat"][i].toLowerCase();
          }
          this.opt.development_extensions.normalize_lang_keys_to_lowercase = 100;
        }
        CSL2.ITERATION += 1;
        Item = JSON.parse(JSON.stringify(this.sys.retrieveItem("" + id)));
        if (this.opt.development_extensions.normalize_lang_keys_to_lowercase) {
          if (Item.multi) {
            if (Item.multi._keys) {
              for (var field in Item.multi._keys) {
                for (var key in Item.multi._keys[field]) {
                  if (key !== key.toLowerCase()) {
                    Item.multi._keys[field][key.toLowerCase()] = Item.multi._keys[field][key];
                    delete Item.multi._keys[field][key];
                  }
                }
              }
            }
            if (Item.multi.main) {
              for (var field in Item.multi.main) {
                Item.multi.main[field] = Item.multi.main[field].toLowerCase();
              }
            }
          }
          for (var i = 0, ilen = CSL2.NAME_VARIABLES.length; i > ilen; i += 1) {
            var ctype = CSL2.NAME_VARIABLES[i];
            if (Item[ctype] && Item[ctype].multi) {
              for (var j = 0, jlen = Item[ctype].length; j < jlen; j += 1) {
                var creator = Item[ctype][j];
                if (creator.multi) {
                  if (creator.multi._key) {
                    for (var key in creator.multi._key) {
                      if (key !== key.toLowerCase()) {
                        creator.multi._key[key.toLowerCase()] = creator.multi._key[key];
                        delete creator.multi._key[key];
                      }
                    }
                  }
                  if (creator.multi.main) {
                    creator.multi.main = creator.multi.main.toLowerCase();
                  }
                }
              }
            }
          }
        }
        if (Item.language && Item.language.match(/[><]/)) {
          var m = Item.language.match(/(.*?)([<>])(.*)/);
          if (m[2] === "<") {
            Item["language-name"] = m[1];
            Item["language-name-original"] = m[3];
          } else {
            Item["language-name"] = m[3];
            Item["language-name-original"] = m[1];
          }
          if (this.opt.multi_layout) {
            if (Item["language-name-original"]) {
              Item.language = Item["language-name-original"];
            }
          } else {
            if (Item["language-name"]) {
              Item.language = Item["language-name"];
            }
          }
        }
        if (Item.page) {
          Item["page-first"] = Item.page;
          var num = "" + Item.page;
          var m = num.split(/\s*(?:&|, |-|\u2013)\s*/);
          if (m[0].slice(-1) !== "\\") {
            Item["page-first"] = m[0];
          }
        }
        if (this.opt.development_extensions.field_hack && Item.note) {
          CSL2.parseNoteFieldHacks(Item, false, this.opt.development_extensions.allow_field_hack_date_override);
        }
        for (var key in Item) {
          if (CSL2.DATE_VARIABLES.indexOf(key.replace(/^alt-/, "")) > -1) {
            var dateobj = Item[key];
            if (dateobj) {
              if (this.opt.development_extensions.raw_date_parsing) {
                if (dateobj.raw && (!dateobj["date-parts"] || dateobj["date-parts"].length === 0)) {
                  dateobj = this.fun.dateparser.parseDateToObject(dateobj.raw);
                }
              }
              Item[key] = this.dateParseArray(dateobj);
            }
          }
        }
        if (this.opt.development_extensions.consolidate_legal_items) {
          if (Item.type && ["bill", "gazette", "legislation", "regulation", "treaty"].indexOf(Item.type) > -1) {
            var varname;
            var elements = ["type", "title", "jurisdiction", "genre", "volume", "container-title"];
            var legislation_id = [];
            for (var i = 0, ilen = elements.length; i < ilen; i += 1) {
              varname = elements[i];
              if (Item[varname]) {
                legislation_id.push(Item[varname]);
              }
            }
            elements = ["original-date", "issued"];
            for (var i = 0, ilen = elements.length; i < ilen; i += 1) {
              varname = elements[i];
              if (Item[varname] && Item[varname].year) {
                var value = Item[varname].year;
                legislation_id.push(value);
                break;
              }
            }
            Item.legislation_id = legislation_id.join("::");
          }
        }
        if (this.bibliography.opt.track_container_items) {
          if (this.bibliography.opt.track_container_items.indexOf(Item.type) > -1) {
            var varname;
            var elements = ["type", "container-title", "publisher", "edition"];
            var container_id = [];
            for (var i = 0, ilen = elements.length; i < ilen; i += 1) {
              varname = elements[i];
              if (Item[varname]) {
                container_id.push(Item[varname]);
              }
            }
            Item.container_id = container_id.join("::");
          }
        }
        if (this.opt.development_extensions.force_jurisdiction) {
          if ("string" === typeof Item.authority) {
            Item.authority = [
              {
                literal: Item.authority,
                multi: {
                  _key: {}
                }
              }
            ];
            if (Item.multi && Item.multi._keys && Item.multi._keys.authority) {
              Item.authority[0].multi._key = {};
              for (var key in Item.multi._keys.authority) {
                Item.authority[0].multi._key[key] = {
                  literal: Item.multi._keys.authority[key]
                };
              }
            }
          }
        }
        if (!Item["title-short"]) {
          Item["title-short"] = Item.shortTitle;
        }
        if (this.opt.development_extensions.main_title_from_short_title) {
          var narrowSpaceLocale = this.opt["default-locale"][0].slice(0, 2).toLowerCase() === "fr";
          CSL2.extractTitleAndSubtitle.call(this, Item, narrowSpaceLocale);
        }
        var isLegalType = ["bill", "legal_case", "legislation", "gazette", "regulation"].indexOf(Item.type) > -1;
        if (this.opt.development_extensions.force_jurisdiction && isLegalType) {
          if (!Item.jurisdiction) {
            Item.jurisdiction = "us";
          }
        }
        var normalizedKey;
        if (!isLegalType && Item.title && this.sys.getAbbreviation) {
          var noHints = false;
          if (!Item.jurisdiction) {
            noHints = true;
          }
          if (this.sys.normalizeAbbrevsKey) {
            normalizedKey = this.sys.normalizeAbbrevsKey("title", Item.title);
          } else {
            normalizedKey = Item.title;
          }
          var jurisdiction = this.transform.loadAbbreviation(Item.jurisdiction, "title", normalizedKey, Item.language);
          if (this.transform.abbrevs[jurisdiction].title) {
            if (this.transform.abbrevs[jurisdiction].title[normalizedKey]) {
              Item["title-short"] = this.transform.abbrevs[jurisdiction].title[normalizedKey];
            }
          }
        }
        if (!Item["container-title-short"]) {
          Item["container-title-short"] = Item.journalAbbreviation;
        }
        if (Item["container-title"] && this.sys.getAbbreviation) {
          if (this.sys.normalizeAbbrevsKey) {
            normalizedKey = this.sys.normalizeAbbrevsKey(Item["container-title"]);
          } else {
            normalizedKey = Item["container-title"];
          }
          var jurisdiction = this.transform.loadAbbreviation(Item.jurisdiction, "container-title", normalizedKey, Item.language);
          if (this.transform.abbrevs[jurisdiction]["container-title"]) {
            if (this.transform.abbrevs[jurisdiction]["container-title"][normalizedKey]) {
              Item["container-title-short"] = this.transform.abbrevs[jurisdiction]["container-title"][normalizedKey];
            }
          }
        }
        if (Item.jurisdiction) {
          Item.country = Item.jurisdiction.split(":")[0];
        }
        if (this.registry.refhash[id]) {
          if (JSON.stringify(this.registry.refhash[id]) != JSON.stringify(Item)) {
            for (var key in this.registry.refhash[id]) {
              delete this.registry.refhash[id][key];
            }
            this.tmp.taintedItemIDs[Item.id] = true;
            Object.assign(this.registry.refhash[id], Item);
          }
        } else {
          this.registry.refhash[id] = Item;
        }
        return this.registry.refhash[id];
      };
      CSL2.Engine.prototype.refetchItem = function(id) {
        return this.registry.refhash[id];
      };
      CSL2.Engine.prototype.setOpt = function(token, name, value) {
        if (token.name === "style" || token.name === "cslstyle") {
          this.opt.inheritedAttributes[name] = value;
          this.citation.opt.inheritedAttributes[name] = value;
          this.bibliography.opt.inheritedAttributes[name] = value;
        } else if (["citation", "bibliography"].indexOf(token.name) > -1) {
          this[token.name].opt.inheritedAttributes[name] = value;
        } else {
          token.strings[name] = value;
        }
      };
      CSL2.Engine.prototype.inheritOpt = function(token, attrname, parentname, defaultValue) {
        if ("undefined" !== typeof token.strings[attrname]) {
          return token.strings[attrname];
        } else {
          var parentValue = this[this.tmp.root].opt.inheritedAttributes[parentname ? parentname : attrname];
          if ("undefined" !== typeof parentValue) {
            return parentValue;
          } else {
            return defaultValue;
          }
        }
      };
      CSL2.Engine.prototype.remapSectionVariable = function(inputList) {
        for (var i = 0, ilen = inputList.length; i < ilen; i += 1) {
          var Item = inputList[i][0];
          var item = inputList[i][1];
          if (["bill", "gazette", "legislation", "regulation", "treaty"].indexOf(Item.type) > -1) {
            if (item.locator) {
              item.locator = item.locator.trim();
              var m = item.locator.match(CSL2.STATUTE_SUBDIV_PLAIN_REGEX_FRONT);
              if (!m) {
                if (item.label) {
                  item.locator = CSL2.STATUTE_SUBDIV_STRINGS_REVERSE[item.label] + " " + item.locator;
                } else {
                  item.locator = "p. " + item.locator;
                }
              }
            }
            var sectionMasterLabel = null;
            if (Item.section) {
              Item.section = Item.section.trim();
              var m = Item.section.match(CSL2.STATUTE_SUBDIV_PLAIN_REGEX_FRONT);
              if (!m) {
                Item.section = "sec. " + Item.section;
                sectionMasterLabel = "sec.";
              } else {
                sectionMasterLabel = m[0].trim();
              }
            }
            if (Item.section) {
              if (!item.locator) {
                item.locator = Item.section;
              } else {
                var m = item.locator.match(/^([^ ]*)\s*(.*)/);
                var space = " ";
                if (m) {
                  if (m[1] === "p." && sectionMasterLabel !== "p.") {
                    item.locator = m[2];
                  }
                  if (["[", "(", ".", ",", ";", ":", "?"].indexOf(item.locator.slice(0, 1)) > -1) {
                    space = "";
                  }
                } else {
                  space = "";
                }
                item.locator = Item.section + space + item.locator;
              }
            }
            item.label = "";
          }
        }
      };
      CSL2.Engine.prototype.setNumberLabels = function(Item) {
        if (Item.number && ["bill", "gazette", "legislation", "regulation", "treaty"].indexOf(Item.type) > -1 && this.opt.development_extensions.consolidate_legal_items && !this.tmp.shadow_numbers["number"]) {
          this.tmp.shadow_numbers["number"] = {};
          this.tmp.shadow_numbers["number"].values = [];
          this.tmp.shadow_numbers["number"].plural = 0;
          this.tmp.shadow_numbers["number"].numeric = false;
          this.tmp.shadow_numbers["number"].label = false;
          var value = "" + Item.number;
          value = value.split("\\").join("");
          var firstword = value.split(/\s+/)[0];
          var firstlabel = CSL2.STATUTE_SUBDIV_STRINGS[firstword];
          if (firstlabel) {
            var splt = value.split(CSL2.STATUTE_SUBDIV_PLAIN_REGEX);
            if (splt.length > 1) {
              var lst = [];
              for (var j = 1, jlen = splt.length; j < jlen; j += 1) {
                lst.push(splt[j].replace(/\s*$/, "").replace(/^\s*/, ""));
              }
              value = lst.join(" ");
            } else {
              value = splt[0];
            }
            this.tmp.shadow_numbers["number"].label = firstlabel;
            this.tmp.shadow_numbers["number"].values.push(["Blob", value, false]);
            this.tmp.shadow_numbers["number"].numeric = false;
          } else {
            this.tmp.shadow_numbers["number"].values.push(["Blob", value, false]);
            this.tmp.shadow_numbers["number"].numeric = true;
          }
        }
      };
      CSL2.substituteOne = function(template) {
        return function(state, list) {
          if (!list) {
            return "";
          } else {
            return template.replace("%%STRING%%", list);
          }
        };
      };
      CSL2.substituteTwo = function(template) {
        return function(param) {
          var template2 = template.replace("%%PARAM%%", param);
          return function(state, list) {
            if (!list) {
              return "";
            } else {
              return template2.replace("%%STRING%%", list);
            }
          };
        };
      };
      CSL2.Mode = function(mode) {
        var decorations, params, param, func, val, args;
        decorations = {};
        params = CSL2.Output.Formats[mode];
        for (param in params) {
          if (true) {
            if ("@" !== param.slice(0, 1)) {
              decorations[param] = params[param];
              continue;
            }
            func = false;
            val = params[param];
            args = param.split("/");
            if (typeof val === "string" && val.indexOf("%%STRING%%") > -1) {
              if (val.indexOf("%%PARAM%%") > -1) {
                func = CSL2.substituteTwo(val);
              } else {
                func = CSL2.substituteOne(val);
              }
            } else if (typeof val === "boolean" && !val) {
              func = CSL2.Output.Formatters.passthrough;
            } else if (typeof val === "function") {
              func = val;
            } else {
              CSL2.error("Bad " + mode + " config entry for " + param + ": " + val);
            }
            if (args.length === 1) {
              decorations[args[0]] = func;
            } else if (args.length === 2) {
              if (!decorations[args[0]]) {
                decorations[args[0]] = {};
              }
              decorations[args[0]][args[1]] = func;
            }
          }
        }
        return decorations;
      };
      CSL2.setDecorations = function(state, attributes) {
        var ret, key, pos;
        ret = [];
        for (pos in CSL2.FORMAT_KEY_SEQUENCE) {
          if (true) {
            var key = CSL2.FORMAT_KEY_SEQUENCE[pos];
            if (attributes[key]) {
              ret.push([key, attributes[key]]);
              delete attributes[key];
            }
          }
        }
        return ret;
      };
      CSL2.Doppeler = function(rexStr, stringMangler) {
        var matchRex = new RegExp("(" + rexStr + ")", "g");
        var splitRex = new RegExp(rexStr, "g");
        this.split = function(str) {
          if (stringMangler) {
            str = stringMangler(str);
          }
          var match = str.match(matchRex);
          if (!match) {
            return {
              tags: [],
              strings: [str]
            };
          }
          var split = str.split(splitRex);
          for (var i = match.length - 1; i > -1; i--) {
            if (typeof match[i] === "number") {
              match[i] = "";
            }
            var tag = match[i];
            if (tag === "'" && split[i + 1].length > 0) {
              split[i + 1] = match[i] + split[i + 1];
              match[i] = "";
            }
          }
          return {
            tags: match,
            strings: split,
            origStrings: split.slice()
          };
        };
        this.join = function(obj) {
          var lst = obj.strings.slice(-1);
          for (var i = obj.tags.length - 1; i > -1; i--) {
            lst.push(obj.tags[i]);
            lst.push(obj.strings[i]);
          }
          lst.reverse();
          return lst.join("");
        };
      };
      CSL2.Engine.prototype.normalDecorIsOrphan = function(blob, params) {
        if (params[1] === "normal") {
          var use_param = false;
          var all_the_decor;
          if (this.tmp.area === "citation") {
            all_the_decor = [this.citation.opt.layout_decorations].concat(blob.alldecor);
          } else {
            all_the_decor = blob.alldecor;
          }
          for (var k = all_the_decor.length - 1; k > -1; k += -1) {
            for (var n = all_the_decor[k].length - 1; n > -1; n += -1) {
              if (all_the_decor[k][n][0] === params[0]) {
                if (all_the_decor[k][n][1] !== "normal") {
                  use_param = true;
                }
              }
            }
          }
          if (!use_param) {
            return true;
          }
        }
        return false;
      };
      CSL2.Engine.prototype.getCitationLabel = function(Item) {
        var label = "";
        var params = this.getTrigraphParams();
        var config = params[0];
        var myname = this.getTerm("reference", "short", 0);
        if ("undefined" === typeof myname) {
          myname = "reference";
        }
        myname = myname.replace(".", "");
        myname = myname.slice(0, 1).toUpperCase() + myname.slice(1);
        for (var i = 0, ilen = CSL2.NAME_VARIABLES.length; i < ilen; i += 1) {
          var n = CSL2.NAME_VARIABLES[i];
          if (Item[n]) {
            var names = Item[n];
            if (names.length > params.length) {
              config = params[params.length - 1];
            } else {
              config = params[names.length - 1];
            }
            for (var j = 0, jlen = names.length; j < jlen; j += 1) {
              if (j === config.authors.length) {
                break;
              }
              var res = this.nameOutput.getName(names[j], "locale-translit", true);
              var name = res.name;
              if (name && name.family) {
                myname = name.family;
                myname = myname.replace(/^([ \'\u2019a-z]+\s+)/, "");
              } else if (name && name.literal) {
                myname = name.literal;
              }
              var m = myname.toLowerCase().match(/^(a\s+|the\s+|an\s+)/);
              if (m) {
                myname = myname.slice(m[1].length);
              }
              myname = myname.replace(CSL2.ROMANESQUE_NOT_REGEXP, "");
              if (!myname) {
                break;
              }
              myname = myname.slice(0, config.authors[j]);
              if (myname.length > 1) {
                myname = myname.slice(0, 1).toUpperCase() + myname.slice(1).toLowerCase();
              } else if (myname.length === 1) {
                myname = myname.toUpperCase();
              }
              label += myname;
            }
            break;
          }
        }
        if (!label) {
          if (Item.title) {
            var skipWords = this.locale[this.opt.lang].opts["skip-words"];
            var lst = Item.title.split(/\s+/);
            for (var i = lst.length - 1; i > -1; i--) {
              if (skipWords.indexOf(lst[i]) > -1) {
                lst = lst.slice(0, i).concat(lst.slice(i + 1));
              }
            }
            var str = lst.join("");
            str = str.slice(0, params[0].authors[0]);
            if (str.length > 1) {
              str = str.slice(0, 1).toUpperCase() + str.slice(1).toLowerCase();
            } else if (str.length === 1) {
              str = str.toUpperCase();
            }
            label = str;
          }
        }
        var year = "0000";
        if (Item.issued) {
          if (Item.issued.year) {
            year = "" + Item.issued.year;
          }
        }
        year = year.slice(config.year * -1);
        label = label + year;
        return label;
      };
      CSL2.Engine.prototype.getTrigraphParams = function() {
        var params = [];
        var ilst = this.opt.trigraph.split(":");
        if (!this.opt.trigraph || this.opt.trigraph.slice(0, 1) !== "A") {
          CSL2.error("Bad trigraph definition: " + this.opt.trigraph);
        }
        for (var i = 0, ilen = ilst.length; i < ilen; i += 1) {
          var str = ilst[i];
          var config = { authors: [], year: 0 };
          for (var j = 0, jlen = str.length; j < jlen; j += 1) {
            switch (str.slice(j, j + 1)) {
              case "A":
                config.authors.push(1);
                break;
              case "a":
                config.authors[config.authors.length - 1] += 1;
                break;
              case "0":
                config.year += 1;
                break;
              default:
                CSL2.error("Invalid character in trigraph definition: " + this.opt.trigraph);
            }
          }
          params.push(config);
        }
        return params;
      };
      CSL2.Engine.prototype.setOutputFormat = function(mode) {
        this.opt.mode = mode;
        this.fun.decorate = CSL2.Mode(mode);
        if (!this.output[mode]) {
          this.output[mode] = {};
          this.output[mode].tmp = {};
        }
      };
      CSL2.Engine.prototype.getSortFunc = function() {
        return function(a, b) {
          a = a.split("-");
          b = b.split("-");
          if (a.length < b.length) {
            return 1;
          } else if (a.length > b.length) {
            return -1;
          } else {
            a = a.slice(-1)[0];
            b = b.slice(-1)[0];
            if (a.length < b.length) {
              return 1;
            } else if (a.length > b.length) {
              return -1;
            } else {
              return 0;
            }
          }
        };
      };
      CSL2.Engine.prototype.setLangTagsForCslSort = function(tags) {
        var i, ilen;
        if (tags) {
          this.opt["locale-sort"] = [];
          for (i = 0, ilen = tags.length; i < ilen; i += 1) {
            this.opt["locale-sort"].push(tags[i]);
          }
        }
        this.opt["locale-sort"].sort(this.getSortFunc());
      };
      CSL2.Engine.prototype.setLangTagsForCslTransliteration = function(tags) {
        var i, ilen;
        this.opt["locale-translit"] = [];
        if (tags) {
          for (i = 0, ilen = tags.length; i < ilen; i += 1) {
            this.opt["locale-translit"].push(tags[i]);
          }
        }
        this.opt["locale-translit"].sort(this.getSortFunc());
      };
      CSL2.Engine.prototype.setLangTagsForCslTranslation = function(tags) {
        var i, ilen;
        this.opt["locale-translat"] = [];
        if (tags) {
          for (i = 0, ilen = tags.length; i < ilen; i += 1) {
            this.opt["locale-translat"].push(tags[i]);
          }
        }
        this.opt["locale-translat"].sort(this.getSortFunc());
      };
      CSL2.Engine.prototype.setLangPrefsForCites = function(obj, conv) {
        var opt = this.opt["cite-lang-prefs"];
        if (!conv) {
          conv = function(key) {
            return key.toLowerCase();
          };
        }
        var segments = ["Persons", "Institutions", "Titles", "Journals", "Publishers", "Places"];
        for (var i = 0, ilen = segments.length; i < ilen; i += 1) {
          var clientSegment = conv(segments[i]);
          var citeprocSegment = segments[i].toLowerCase();
          if (!obj[clientSegment]) {
            continue;
          }
          var supplements = [];
          while (obj[clientSegment].length > 1) {
            supplements.push(obj[clientSegment].pop());
          }
          var sortval = { orig: 1, translit: 2, translat: 3 };
          if (supplements.length === 2 && sortval[supplements[0]] < sortval[supplements[1]]) {
            supplements.reverse();
          }
          while (supplements.length) {
            obj[clientSegment].push(supplements.pop());
          }
          var lst = opt[citeprocSegment];
          while (lst.length) {
            lst.pop();
          }
          for (var j = 0, jlen = obj[clientSegment].length; j < jlen; j += 1) {
            lst.push(obj[clientSegment][j]);
          }
        }
      };
      CSL2.Engine.prototype.setLangPrefsForCiteAffixes = function(affixList) {
        if (affixList && affixList.length === 48) {
          var affixes = this.opt.citeAffixes;
          var count = 0;
          var settings = ["persons", "institutions", "titles", "journals", "publishers", "places"];
          var forms = ["translit", "orig", "translit", "translat"];
          var value;
          for (var i = 0, ilen = settings.length; i < ilen; i += 1) {
            for (var j = 0, jlen = forms.length; j < jlen; j += 1) {
              value = "";
              if (count % 8 === 4) {
                if (!affixes[settings[i]]["locale-" + forms[j]].prefix && !affixes[settings[i]]["locale-" + forms[j]].suffix) {
                  value = affixList[count] ? affixList[count] : "";
                  affixes[settings[i]]["locale-" + forms[j]].prefix = value;
                  value = affixList[count] ? affixList[count + 1] : "";
                  affixes[settings[i]]["locale-" + forms[j]].suffix = value;
                }
              } else {
                value = affixList[count] ? affixList[count] : "";
                affixes[settings[i]]["locale-" + forms[j]].prefix = value;
                value = affixList[count] ? affixList[count + 1] : "";
                affixes[settings[i]]["locale-" + forms[j]].suffix = value;
              }
              count += 2;
            }
          }
          this.opt.citeAffixes = affixes;
        }
      };
      CSL2.Engine.prototype.setAutoVietnameseNamesOption = function(arg) {
        if (arg) {
          this.opt["auto-vietnamese-names"] = true;
        } else {
          this.opt["auto-vietnamese-names"] = false;
        }
      };
      CSL2.Engine.prototype.setAbbreviations = function(arg) {
        if (this.sys.setAbbreviations) {
          this.sys.setAbbreviations(arg);
        }
      };
      CSL2.Engine.prototype.setSuppressTrailingPunctuation = function(arg) {
        this.citation.opt.suppressTrailingPunctuation = !!arg;
      };
      CSL2.Output = {};
      CSL2.Output.Queue = function(state) {
        this.levelname = ["top"];
        this.state = state;
        this.queue = [];
        this.empty = new CSL2.Token("empty");
        var tokenstore = {};
        tokenstore.empty = this.empty;
        this.formats = new CSL2.Stack(tokenstore);
        this.current = new CSL2.Stack(this.queue);
      };
      CSL2.Output.Queue.prototype.pop = function() {
        var drip = this.current.value();
        if (drip.length) {
          return drip.pop();
        } else {
          return drip.blobs.pop();
        }
      };
      CSL2.Output.Queue.prototype.getToken = function(name) {
        var ret = this.formats.value()[name];
        return ret;
      };
      CSL2.Output.Queue.prototype.mergeTokenStrings = function(base, modifier) {
        var base_token, modifier_token, ret, key;
        base_token = this.formats.value()[base];
        modifier_token = this.formats.value()[modifier];
        ret = base_token;
        if (modifier_token) {
          if (!base_token) {
            base_token = new CSL2.Token(base, CSL2.SINGLETON);
            base_token.decorations = [];
          }
          ret = new CSL2.Token(base, CSL2.SINGLETON);
          var key = "";
          for (var key in base_token.strings) {
            if (base_token.strings.hasOwnProperty(key)) {
              ret.strings[key] = base_token.strings[key];
            }
          }
          for (var key in modifier_token.strings) {
            if (modifier_token.strings.hasOwnProperty(key)) {
              ret.strings[key] = modifier_token.strings[key];
            }
          }
          ret.decorations = base_token.decorations.concat(modifier_token.decorations);
        }
        return ret;
      };
      CSL2.Output.Queue.prototype.addToken = function(name, modifier, token) {
        var newtok, attr;
        newtok = new CSL2.Token("output");
        if ("string" === typeof token) {
          token = this.formats.value()[token];
        }
        if (token && token.strings) {
          for (attr in token.strings) {
            if (token.strings.hasOwnProperty(attr)) {
              newtok.strings[attr] = token.strings[attr];
            }
          }
          newtok.decorations = token.decorations;
        }
        if ("string" === typeof modifier) {
          newtok.strings.delimiter = modifier;
        }
        this.formats.value()[name] = newtok;
      };
      CSL2.Output.Queue.prototype.pushFormats = function(tokenstore) {
        if (!tokenstore) {
          tokenstore = {};
        }
        tokenstore.empty = this.empty;
        this.formats.push(tokenstore);
      };
      CSL2.Output.Queue.prototype.popFormats = function() {
        this.formats.pop();
      };
      CSL2.Output.Queue.prototype.startTag = function(name, token) {
        var tokenstore = {};
        if (this.state.tmp["doing-macro-with-date"] && this.state.tmp.extension) {
          token = this.empty;
          name = "empty";
        }
        tokenstore[name] = token;
        this.pushFormats(tokenstore);
        this.openLevel(name);
      };
      CSL2.Output.Queue.prototype.endTag = function(name) {
        this.closeLevel(name);
        this.popFormats();
      };
      CSL2.Output.Queue.prototype.openLevel = function(token) {
        var blob, curr;
        if ("object" === typeof token) {
          blob = new CSL2.Blob(void 0, token);
        } else if ("undefined" === typeof token) {
          blob = new CSL2.Blob(void 0, this.formats.value().empty, "empty");
        } else {
          if (!this.formats.value() || !this.formats.value()[token]) {
            CSL2.error('CSL processor error: call to nonexistent format token "' + token + '"');
          }
          blob = new CSL2.Blob(void 0, this.formats.value()[token], token);
        }
        curr = this.current.value();
        if (!this.state.tmp.just_looking && this.checkNestedBrace) {
          blob.strings.prefix = this.checkNestedBrace.update(blob.strings.prefix);
        }
        curr.push(blob);
        this.current.push(blob);
      };
      CSL2.Output.Queue.prototype.closeLevel = function(name) {
        if (name && name !== this.current.value().levelname) {
          CSL2.error("Level mismatch error:  wanted " + name + " but found " + this.current.value().levelname);
        }
        var blob = this.current.pop();
        if (!this.state.tmp.just_looking && this.checkNestedBrace) {
          blob.strings.suffix = this.checkNestedBrace.update(blob.strings.suffix);
        }
      };
      CSL2.Output.Queue.prototype.append = function(str, tokname, notSerious, ignorePredecessor, noStripPeriods) {
        var token, blob, curr;
        var useblob = true;
        if (notSerious) {
          ignorePredecessor = true;
        }
        if (this.state.tmp["doing-macro-with-date"] && !notSerious) {
          if (tokname !== "macro-with-date") {
            return false;
          }
          if (tokname === "macro-with-date") {
            tokname = "empty";
          }
        }
        if ("undefined" === typeof str) {
          return false;
        }
        if ("number" === typeof str) {
          str = "" + str;
        }
        if (!notSerious && this.state.tmp.element_trace && this.state.tmp.element_trace.value() === "suppress-me") {
          return false;
        }
        blob = false;
        if (!tokname) {
          token = this.formats.value().empty;
        } else if (tokname === "literal") {
          token = true;
          useblob = false;
        } else if ("string" === typeof tokname) {
          token = this.formats.value()[tokname];
        } else {
          token = tokname;
        }
        if (!token) {
          CSL2.error("CSL processor error: unknown format token name: " + tokname);
        }
        if (token.strings && "undefined" === typeof token.strings.delimiter) {
          token.strings.delimiter = "";
        }
        if ("string" === typeof str && str.length) {
          str = str.replace(/ ([:;?!\u00bb])/g, "\u202F$1").replace(/\u00ab /g, "\xAB\u202F");
          this.last_char_rendered = str.slice(-1);
          str = str.replace(/\s+'/g, " '");
          if (!notSerious) {
            str = str.replace(/^'/g, " '");
          }
          if (!ignorePredecessor) {
            this.state.tmp.term_predecessor = true;
            this.state.tmp.in_cite_predecessor = true;
          } else if (notSerious) {
            this.state.tmp.term_predecessor_name = true;
          }
        }
        blob = new CSL2.Blob(str, token);
        curr = this.current.value();
        if ("undefined" === typeof curr && this.current.mystack.length === 0) {
          this.current.mystack.push([]);
          curr = this.current.value();
        }
        if ("string" === typeof blob.blobs) {
          if (!ignorePredecessor) {
            this.state.tmp.term_predecessor = true;
            this.state.tmp.in_cite_predecessor = true;
          } else if (notSerious) {
            this.state.tmp.term_predecessor_name = true;
          }
        }
        if ("string" === typeof str) {
          if ("string" === typeof blob.blobs) {
            if (blob.blobs.slice(0, 1) !== " ") {
              var blobPrefix = "";
              var blobBlobs = blob.blobs;
              while (CSL2.TERMINAL_PUNCTUATION.indexOf(blobBlobs.slice(0, 1)) > -1) {
                blobPrefix = blobPrefix + blobBlobs.slice(0, 1);
                blobBlobs = blobBlobs.slice(1);
              }
              if (blobBlobs && blobPrefix) {
                blob.strings.prefix = blob.strings.prefix + blobPrefix;
                blob.blobs = blobBlobs;
              }
            }
          }
          if (blob.strings["text-case"]) {
            blob.blobs = CSL2.Output.Formatters[blob.strings["text-case"]](this.state, str);
          }
          if (this.state.tmp.strip_periods && !noStripPeriods) {
            blob.blobs = blob.blobs.replace(/\.([^a-z]|$)/g, "$1");
          }
          for (var i = blob.decorations.length - 1; i > -1; i += -1) {
            if (blob.decorations[i][0] === "@quotes" && blob.decorations[i][1] !== "false") {
              blob.punctuation_in_quote = this.state.getOpt("punctuation-in-quote");
            }
            if (!blob.blobs.match(CSL2.ROMANESQUE_REGEXP)) {
              if (blob.decorations[i][0] === "@font-style") {
                blob.decorations = blob.decorations.slice(0, i).concat(blob.decorations.slice(i + 1));
              }
            }
          }
          curr.push(blob);
          this.state.fun.flipflopper.processTags(blob);
        } else if (useblob) {
          curr.push(blob);
        } else {
          curr.push(str);
        }
        return true;
      };
      CSL2.Output.Queue.prototype.string = function(state, myblobs, blob) {
        var i, ilen, j, jlen, b;
        var txt_esc = CSL2.getSafeEscape(this.state);
        var blobs = myblobs.slice();
        var ret = [];
        if (blobs.length === 0) {
          return ret;
        }
        var blob_delimiter = "";
        if (blob) {
          blob_delimiter = blob.strings.delimiter;
        } else {
          state.tmp.count_offset_characters = false;
          state.tmp.offset_characters = 0;
        }
        if (blob && blob.new_locale) {
          blob.old_locale = state.opt.lang;
          state.opt.lang = blob.new_locale;
        }
        var blobjr, use_suffix, use_prefix, params;
        for (var i = 0, ilen = blobs.length; i < ilen; i += 1) {
          blobjr = blobs[i];
          if (blobjr.strings.first_blob) {
            state.tmp.count_offset_characters = blobjr.strings.first_blob;
          }
          if ("string" === typeof blobjr.blobs) {
            if ("number" === typeof blobjr.num) {
              ret.push(blobjr);
            } else if (blobjr.blobs) {
              if (blobjr.particle) {
                blobjr.blobs = blobjr.particle + blobjr.blobs;
                blobjr.particle = "";
              }
              b = txt_esc(blobjr.blobs);
              var blen = b.length;
              if (!state.tmp.suppress_decorations) {
                for (j = 0, jlen = blobjr.decorations.length; j < jlen; j += 1) {
                  params = blobjr.decorations[j];
                  if (params[0] === "@showid") {
                    continue;
                  }
                  if (state.normalDecorIsOrphan(blobjr, params)) {
                    continue;
                  }
                  b = state.fun.decorate[params[0]][params[1]].call(blobjr, state, b, params[2]);
                }
              }
              if (b && b.length) {
                b = txt_esc(blobjr.strings.prefix) + b + txt_esc(blobjr.strings.suffix);
                if (state.opt.development_extensions.csl_reverse_lookup_support && !state.tmp.suppress_decorations) {
                  for (j = 0, jlen = blobjr.decorations.length; j < jlen; j += 1) {
                    params = blobjr.decorations[j];
                    if (params[0] === "@showid") {
                      b = state.fun.decorate[params[0]][params[1]].call(blobjr, state, b, params[2]);
                    }
                  }
                }
                ret.push(b);
                if (state.tmp.count_offset_characters) {
                  state.tmp.offset_characters += blen + blobjr.strings.suffix.length + blobjr.strings.prefix.length;
                }
              }
            }
          } else if (blobjr.blobs.length) {
            var addtoret = state.output.string(state, blobjr.blobs, blobjr);
            if (blob) {
              if ("string" !== addtoret && addtoret.length > 1 && blobjr.strings.delimiter) {
                var numberSeen = false;
                for (var j = 0, jlen = addtoret.length; j < jlen; j++) {
                  if ("string" !== typeof addtoret[j]) {
                    numberSeen = true;
                  } else if (numberSeen) {
                    addtoret[j] = blobjr.strings.delimiter + addtoret[j];
                  }
                }
              }
            }
            ret = ret.concat(addtoret);
          }
          if (blobjr.strings.first_blob && state.registry.registry[blobjr.strings.first_blob]) {
            state.registry.registry[blobjr.strings.first_blob].offset = state.tmp.offset_characters;
            state.tmp.count_offset_characters = false;
          }
        }
        for (i = 0, ilen = ret.length - 1; i < ilen; i += 1) {
          if ("number" === typeof ret[i].num && "number" === typeof ret[i + 1].num && !ret[i + 1].UGLY_DELIMITER_SUPPRESS_HACK) {
            ret[i].strings.suffix = ret[i].strings.suffix + (blob_delimiter ? blob_delimiter : "");
            ret[i + 1].successor_prefix = "";
            ret[i + 1].UGLY_DELIMITER_SUPPRESS_HACK = true;
          }
        }
        var span_split = 0;
        for (var i = 0, ilen = ret.length; i < ilen; i += 1) {
          if ("string" === typeof ret[i]) {
            span_split = parseInt(i, 10) + 1;
            if (i < ret.length - 1 && "object" === typeof ret[i + 1]) {
              if (blob_delimiter && !ret[i + 1].UGLY_DELIMITER_SUPPRESS_HACK) {
                ret[i] += txt_esc(blob_delimiter);
              }
              ret[i + 1].UGLY_DELIMITER_SUPPRESS_HACK = true;
            }
          }
        }
        if (blob && (blob.decorations.length || blob.strings.suffix)) {
          span_split = ret.length;
        } else if (blob && blob.strings.prefix) {
          for (var i = 0, ilen = ret.length; i < ilen; i++) {
            if ("undefined" !== typeof ret[i].num) {
              span_split = i;
              if (i === 0) {
                ret[i].strings.prefix = blob.strings.prefix + ret[i].strings.prefix;
              }
              break;
            }
          }
        }
        var blobs_start = state.output.renderBlobs(ret.slice(0, span_split), blob_delimiter, false, blob);
        if (blobs_start && blob && (blob.decorations.length || blob.strings.suffix || blob.strings.prefix)) {
          if (!state.tmp.suppress_decorations) {
            for (var i = 0, ilen = blob.decorations.length; i < ilen; i += 1) {
              params = blob.decorations[i];
              if (["@cite", "@bibliography", "@display", "@showid"].indexOf(params[0]) > -1) {
                continue;
              }
              if (state.normalDecorIsOrphan(blobjr, params)) {
                continue;
              }
              if (!params[0]) continue;
              if ("string" === typeof blobs_start) {
                blobs_start = state.fun.decorate[params[0]][params[1]].call(blob, state, blobs_start, params[2]);
              }
            }
          }
          b = blobs_start;
          use_suffix = blob.strings.suffix;
          if (b && b.length) {
            use_prefix = blob.strings.prefix;
            b = txt_esc(use_prefix) + b + txt_esc(use_suffix);
            if (state.tmp.count_offset_characters) {
              state.tmp.offset_characters += use_prefix.length + use_suffix.length;
            }
          }
          blobs_start = b;
          if (!state.tmp.suppress_decorations) {
            for (var i = 0, ilen = blob.decorations.length; i < ilen; i += 1) {
              params = blob.decorations[i];
              if (["@cite", "@bibliography", "@display", "@showid"].indexOf(params[0]) === -1) {
                continue;
              }
              if ("string" === typeof blobs_start) {
                blobs_start = state.fun.decorate[params[0]][params[1]].call(blob, state, blobs_start, params[2]);
              }
            }
          }
        }
        var blobs_end = ret.slice(span_split, ret.length);
        if (!blobs_end.length && blobs_start) {
          ret = [blobs_start];
        } else if (blobs_end.length && !blobs_start) {
          ret = blobs_end;
        } else if (blobs_start && blobs_end.length) {
          ret = [blobs_start].concat(blobs_end);
        }
        if ("undefined" === typeof blob) {
          this.queue = [];
          this.current.mystack = [];
          this.current.mystack.push(this.queue);
          if (state.tmp.suppress_decorations) {
            ret = state.output.renderBlobs(ret, void 0, false);
          }
        } else if ("boolean" === typeof blob) {
          ret = state.output.renderBlobs(ret, void 0, true);
        }
        if (blob && blob.new_locale) {
          state.opt.lang = blob.old_locale;
        }
        return ret;
      };
      CSL2.Output.Queue.prototype.clearlevel = function() {
        var blob, pos, len;
        blob = this.current.value();
        len = blob.blobs.length;
        for (pos = 0; pos < len; pos += 1) {
          blob.blobs.pop();
        }
      };
      CSL2.Output.Queue.prototype.renderBlobs = function(blobs, delim, in_cite, parent) {
        var state, ret, ret_last_char, use_delim, blob, pos, len, ppos, llen, str, params, txt_esc;
        txt_esc = CSL2.getSafeEscape(this.state);
        if (!delim) {
          delim = "";
        }
        state = this.state;
        ret = "";
        ret_last_char = [];
        use_delim = "";
        len = blobs.length;
        if (this.state.tmp.area === "citation" && !this.state.tmp.just_looking && len === 1 && typeof blobs[0] === "object" && parent) {
          blobs[0].strings.prefix = parent.strings.prefix + blobs[0].strings.prefix;
          blobs[0].strings.suffix = blobs[0].strings.suffix + parent.strings.suffix;
          blobs[0].decorations = blobs[0].decorations.concat(parent.decorations);
          blobs[0].params = parent.params;
          return blobs[0];
        }
        var start = true;
        for (pos = 0; pos < len; pos += 1) {
          if (blobs[pos].checkNext) {
            blobs[pos].checkNext(blobs[pos + 1], start);
            start = false;
          } else if (blobs[pos + 1] && blobs[pos + 1].splice_prefix) {
            start = false;
          } else {
            start = true;
          }
        }
        var doit = true;
        for (pos = blobs.length - 1; pos > 0; pos += -1) {
          if (blobs[pos].checkLast) {
            if (doit && blobs[pos].checkLast(blobs[pos - 1])) {
              doit = false;
            }
          } else {
            doit = true;
          }
        }
        len = blobs.length;
        for (pos = 0; pos < len; pos += 1) {
          blob = blobs[pos];
          if (ret) {
            use_delim = delim;
          }
          if ("string" === typeof blob) {
            ret += txt_esc(use_delim);
            ret += blob;
            if (state.tmp.count_offset_characters) {
              state.tmp.offset_characters += use_delim.length;
            }
          } else if (in_cite) {
            if (ret) {
              ret = [ret, blob];
            } else {
              ret = [blob];
            }
          } else if (blob.status !== CSL2.SUPPRESS) {
            if (blob.particle) {
              str = blob.particle + blob.num;
            } else {
              str = blob.formatter.format(blob.num, blob.gender);
            }
            var strlen = str.replace(/<[^>]*>/g, "").length;
            this.append(str, "empty", true);
            var str_blob = this.pop();
            var count_offset_characters = state.tmp.count_offset_characters;
            str = this.string(state, [str_blob], false);
            state.tmp.count_offset_characters = count_offset_characters;
            if (blob.strings["text-case"]) {
              str = CSL2.Output.Formatters[blob.strings["text-case"]](this.state, str);
            }
            if (str && this.state.tmp.strip_periods) {
              str = str.replace(/\.([^a-z]|$)/g, "$1");
            }
            if (!state.tmp.suppress_decorations) {
              llen = blob.decorations.length;
              for (ppos = 0; ppos < llen; ppos += 1) {
                params = blob.decorations[ppos];
                if (state.normalDecorIsOrphan(blob, params)) {
                  continue;
                }
                str = state.fun.decorate[params[0]][params[1]].call(blob, state, str, params[2]);
              }
            }
            str = txt_esc(blob.strings.prefix) + str + txt_esc(blob.strings.suffix);
            var addme = "";
            if (blob.status === CSL2.END) {
              addme = txt_esc(blob.range_prefix);
            } else if (blob.status === CSL2.SUCCESSOR) {
              addme = txt_esc(blob.successor_prefix);
            } else if (blob.status === CSL2.START) {
              if (pos > 0 && !blob.suppress_splice_prefix) {
                addme = txt_esc(blob.splice_prefix);
              } else {
                addme = "";
              }
            } else if (blob.status === CSL2.SEEN) {
              addme = txt_esc(blob.splice_prefix);
            }
            ret += addme;
            ret += str;
            if (state.tmp.count_offset_characters) {
              state.tmp.offset_characters += addme.length + blob.strings.prefix.length + strlen + blob.strings.suffix.length;
            }
          }
        }
        return ret;
      };
      CSL2.Output.Queue.purgeEmptyBlobs = function(parent) {
        if ("object" !== typeof parent || "object" !== typeof parent.blobs || !parent.blobs.length) {
          return;
        }
        for (var i = parent.blobs.length - 1; i > -1; i--) {
          CSL2.Output.Queue.purgeEmptyBlobs(parent.blobs[i]);
          var child = parent.blobs[i];
          if (!child || !child.blobs || !child.blobs.length) {
            var buf = [];
            while (parent.blobs.length - 1 > i) {
              buf.push(parent.blobs.pop());
            }
            parent.blobs.pop();
            while (buf.length) {
              parent.blobs.push(buf.pop());
            }
          }
        }
      };
      CSL2.Output.Queue.adjust = function(punctInQuote) {
        var NO_SWAP_IN = {
          ";": true,
          ":": true
        };
        var NO_SWAP_OUT = {
          ".": true,
          "!": true,
          "?": true
        };
        var LtoR_MAP = {
          "!": {
            ".": "!",
            "?": "!?",
            ":": "!",
            ",": "!,",
            ";": "!;"
          },
          "?": {
            "!": "?!",
            ".": "?",
            ":": "?",
            ",": "?,",
            ";": "?;"
          },
          ".": {
            "!": ".!",
            "?": ".?",
            ":": ".:",
            ",": ".,",
            ";": ".;"
          },
          ":": {
            "!": "!",
            "?": "?",
            ".": ":",
            ",": ":,",
            ";": ":;"
          },
          ",": {
            "!": ",!",
            "?": ",?",
            ":": ",:",
            ".": ",.",
            ";": ",;"
          },
          ";": {
            "!": "!",
            "?": "?",
            ":": ";",
            ",": ";,",
            ".": ";"
          }
        };
        var SWAP_IN = {};
        var SWAP_OUT = {};
        var PUNCT = {};
        var PUNCT_OR_SPACE = {};
        for (var key in LtoR_MAP) {
          PUNCT[key] = true;
          PUNCT_OR_SPACE[key] = true;
          if (!NO_SWAP_IN[key]) {
            SWAP_IN[key] = true;
          }
          if (!NO_SWAP_OUT[key]) {
            SWAP_OUT[key] = true;
          }
        }
        PUNCT_OR_SPACE[" "] = true;
        PUNCT_OR_SPACE["\xA0"] = true;
        var RtoL_MAP = {};
        for (var key in LtoR_MAP) {
          for (var subkey in LtoR_MAP[key]) {
            if (!RtoL_MAP[subkey]) {
              RtoL_MAP[subkey] = {};
            }
            RtoL_MAP[subkey][key] = LtoR_MAP[key][subkey];
          }
        }
        function blobIsNumber(blob) {
          return "number" === typeof blob.num || blob.blobs && blob.blobs.length === 1 && "number" === typeof blob.blobs[0].num;
        }
        function blobEndsInNumber(blob) {
          if ("number" === typeof blob.num) {
            return true;
          }
          if (!blob.blobs || "object" !== typeof blob.blobs) {
            return false;
          }
          if (blobEndsInNumber(blob.blobs[blob.blobs.length - 1])) {
            return true;
          }
        }
        function blobHasDecorations(blob, includeQuotes) {
          var ret = false;
          var decorlist = ["@font-style", "@font-variant", "@font-weight", "@text-decoration", "@vertical-align"];
          if (includeQuotes) {
            decorlist.push("@quotes");
          }
          if (blob.decorations) {
            for (var i = 0, ilen = blob.decorations.length; i < ilen; i++) {
              if (decorlist.indexOf(blob.decorations[i][0]) > -1) {
                ret = true;
                break;
              }
            }
          }
          return ret;
        }
        function blobHasDescendantQuotes(blob) {
          if (blob.decorations) {
            for (var i = 0, ilen = blob.decorations.length; i < ilen; i++) {
              if (blob.decorations[i][0] === "@quotes" && blob.decorations[i][1] !== "false") {
                return true;
              }
            }
          }
          if ("object" !== typeof blob.blobs) {
            return false;
          }
          return blobHasDescendantQuotes(blob.blobs[blob.blobs.length - 1]);
        }
        function blobHasDescendantMergingPunctuation(parentChar, blob) {
          var childChar = blob.strings.suffix.slice(-1);
          if (!childChar && "string" === typeof blob.blobs) {
            childChar = blob.blobs.slice(-1);
          }
          var mergedChars = RtoL_MAP[parentChar][childChar];
          if (mergedChars && mergedChars.length === 1) {
            return true;
          }
          if ("object" !== typeof blob.blobs) {
            return false;
          }
          if (blobHasDescendantMergingPunctuation(parentChar, blob.blobs[blob.blobs.length - 1])) {
            return true;
          }
          return false;
        }
        function matchLastChar(blob, chr) {
          if (!PUNCT[chr]) {
            return false;
          }
          if ("string" === typeof blob.blobs) {
            if (blob.blobs.slice(-1) === chr) {
              return true;
            } else {
              return false;
            }
          } else {
            var child = blob.blobs[blob.blobs.length - 1];
            if (child) {
              var childChar = child.strings.suffix.slice(-1);
              if (!childChar) {
                return matchLastChar(child, chr);
              } else if (child.strings.suffix.slice(-1) == chr) {
                return true;
              } else {
                return false;
              }
            } else {
              return false;
            }
          }
        }
        function mergeChars(First, first, Second, second, merge_right) {
          var FirstStrings = "blobs" === first ? First : First.strings;
          var SecondStrings = "blobs" === second ? Second : Second.strings;
          var firstChar = FirstStrings[first].slice(-1);
          var secondChar = SecondStrings[second].slice(0, 1);
          function cullRight() {
            SecondStrings[second] = SecondStrings[second].slice(1);
          }
          function cullLeft() {
            FirstStrings[first] = FirstStrings[first].slice(0, -1);
          }
          function addRight(chr) {
            SecondStrings[second] = chr + SecondStrings[second];
          }
          function addLeft(chr) {
            FirstStrings[first] += chr;
          }
          var cull = merge_right ? cullLeft : cullRight;
          function matchOnRight() {
            return RtoL_MAP[secondChar];
          }
          function matchOnLeft() {
            return LtoR_MAP[firstChar];
          }
          var match = merge_right ? matchOnLeft : matchOnRight;
          function mergeToRight() {
            var chr = LtoR_MAP[firstChar][secondChar];
            if ("string" === typeof chr) {
              cullLeft();
              cullRight();
              addRight(chr);
            } else {
              addRight(firstChar);
              cullLeft();
            }
          }
          function mergeToLeft() {
            var chr = RtoL_MAP[secondChar][firstChar];
            if ("string" === typeof chr) {
              cullLeft();
              cullRight();
              addLeft(chr);
            } else {
              addLeft(secondChar);
              cullRight();
            }
          }
          var merge = merge_right ? mergeToRight : mergeToLeft;
          var isDuplicate = firstChar === secondChar;
          if (isDuplicate) {
            cull();
          } else {
            if (match()) {
              merge();
            }
          }
        }
        function upward(parent) {
          if (parent.blobs && "string" == typeof parent.blobs) {
            if (PUNCT[parent.strings.suffix.slice(0, 1)] && parent.strings.suffix.slice(0, 1) === parent.blobs.slice(-1)) {
              parent.strings.suffix = parent.strings.suffix.slice(1);
            }
            return;
          } else if ("object" !== typeof parent || "object" !== typeof parent.blobs || !parent.blobs.length) {
            return;
          }
          var parentDecorations = blobHasDecorations(parent, true);
          for (var i = parent.blobs.length - 1; i > -1; i--) {
            this.upward(parent.blobs[i]);
            var parentStrings = parent.strings;
            var childStrings = parent.blobs[i].strings;
            if (i === 0) {
              if (" " === parentStrings.prefix.slice(-1) && " " === childStrings.prefix.slice(0, 1)) {
                childStrings.prefix = childStrings.prefix.slice(1);
              }
              var childChar = childStrings.prefix.slice(0, 1);
              if (!parentDecorations && PUNCT_OR_SPACE[childChar] && !parentStrings.prefix) {
                parentStrings.prefix += childChar;
                childStrings.prefix = childStrings.prefix.slice(1);
              }
            }
            if (i === parent.blobs.length - 1) {
              var childChar = childStrings.suffix.slice(-1);
              if (!parentDecorations && [" "].indexOf(childChar) > -1) {
                if (parentStrings.suffix.slice(0, 1) !== childChar) {
                  parentStrings.suffix = childChar + parentStrings.suffix;
                }
                childStrings.suffix = childStrings.suffix.slice(0, -1);
              }
            }
            if (parentStrings.delimiter && i > 0) {
              if (PUNCT_OR_SPACE[parentStrings.delimiter.slice(-1)] && parentStrings.delimiter.slice(-1) === childStrings.prefix.slice(0, 1)) {
                childStrings.prefix = childStrings.prefix.slice(1);
              }
            }
          }
        }
        function leftward(parent) {
          if ("object" !== typeof parent || "object" !== typeof parent.blobs || !parent.blobs.length) {
            return;
          }
          for (var i = parent.blobs.length - 1; i > -1; i--) {
            this.leftward(parent.blobs[i]);
            if (i < parent.blobs.length - 1 && !parent.strings.delimiter) {
              var child = parent.blobs[i];
              var childChar = child.strings.suffix.slice(-1);
              var sibling = parent.blobs[i + 1];
              var siblingChar = sibling.strings.prefix.slice(0, 1);
              var hasDecorations = blobHasDecorations(child) || blobHasDecorations(sibling);
              var hasNumber = "number" === typeof childChar || "number" === typeof siblingChar;
              if (!hasDecorations && !hasNumber && PUNCT[siblingChar] && !hasNumber) {
                var suffixAndPrefixMatch = siblingChar === child.strings.suffix.slice(-1);
                var suffixAndFieldMatch = !child.strings.suffix && "string" === typeof child.blobs && child.blobs.slice(-1) === siblingChar;
                if (!suffixAndPrefixMatch && !suffixAndFieldMatch) {
                  mergeChars(child, "suffix", sibling, "prefix");
                } else {
                  sibling.strings.prefix = sibling.strings.prefix.slice(1);
                }
              }
            }
          }
        }
        function downward(parent) {
          if (parent.blobs && "string" == typeof parent.blobs) {
            if (PUNCT[parent.strings.suffix.slice(0, 1)] && parent.strings.suffix.slice(0, 1) === parent.blobs.slice(-1)) {
              parent.strings.suffix = parent.strings.suffix.slice(1);
            }
            return;
          } else if ("object" !== typeof parent || "object" !== typeof parent.blobs || !parent.blobs.length) {
            return;
          }
          var parentStrings = parent.strings;
          var someChildrenAreNumbers = false;
          for (var i = 0, ilen = parent.blobs.length; i < ilen; i++) {
            if (blobIsNumber(parent.blobs[i])) {
              someChildrenAreNumbers = true;
              break;
            }
          }
          if (true) {
            if (parentStrings.delimiter && PUNCT[parentStrings.delimiter.slice(0, 1)]) {
              var delimChar = parentStrings.delimiter.slice(0, 1);
              for (var i = parent.blobs.length - 2; i > -1; i--) {
                var childStrings = parent.blobs[i].strings;
                if (childStrings.suffix.slice(-1) !== delimChar) {
                  childStrings.suffix += delimChar;
                }
              }
              parentStrings.delimiter = parentStrings.delimiter.slice(1);
            }
          }
          for (var i = parent.blobs.length - 1; i > -1; i--) {
            var child = parent.blobs[i];
            var childStrings = parent.blobs[i].strings;
            var childDecorations = blobHasDecorations(child, true);
            var childIsNumber = blobIsNumber(child);
            if (i === parent.blobs.length - 1) {
              if (true) {
                var parentChar = parentStrings.suffix.slice(0, 1);
                var allowMigration = false;
                if (PUNCT[parentChar]) {
                  allowMigration = blobHasDescendantMergingPunctuation(parentChar, child);
                  if (!allowMigration && punctInQuote) {
                    allowMigration = blobHasDescendantQuotes(child);
                  }
                }
                if (allowMigration) {
                  if (PUNCT[parentChar]) {
                    if (!blobEndsInNumber(child)) {
                      if ("string" === typeof child.blobs) {
                        mergeChars(child, "blobs", parent, "suffix");
                      } else {
                        mergeChars(child, "suffix", parent, "suffix");
                      }
                      if (parentStrings.suffix.slice(0, 1) === ".") {
                        childStrings.suffix += parentStrings.suffix.slice(0, 1);
                        parentStrings.suffix = parentStrings.suffix.slice(1);
                      }
                    }
                  }
                }
                if (childStrings.suffix.slice(-1) === "\xA0" && parentStrings.suffix.slice(0, 1) === " ") {
                  parentStrings.suffix = parentStrings.suffix.slice(1);
                }
                if (PUNCT_OR_SPACE[childStrings.suffix.slice(0, 1)]) {
                  if ("string" === typeof child.blobs && child.blobs.slice(-1) === childStrings.suffix.slice(0, 1)) {
                    childStrings.suffix = childStrings.suffix.slice(1);
                  }
                  if (childStrings.suffix.slice(-1) === parentStrings.suffix.slice(0, 1)) {
                    parentStrings.suffix = parentStrings.suffix.slice(0, -1);
                  }
                }
              }
              if (matchLastChar(parent, parent.strings.suffix.slice(0, 1))) {
                parent.strings.suffix = parent.strings.suffix.slice(1);
              }
            } else if (parentStrings.delimiter) {
              if (PUNCT_OR_SPACE[parentStrings.delimiter.slice(0, 1)] && parentStrings.delimiter.slice(0, 1) === childStrings.suffix.slice(-1)) {
                parent.blobs[i].strings.suffix = parent.blobs[i].strings.suffix.slice(0, -1);
              }
            } else {
              var siblingStrings = parent.blobs[i + 1].strings;
              if (!blobIsNumber(child) && !childDecorations && PUNCT_OR_SPACE[childStrings.suffix.slice(-1)] && childStrings.suffix.slice(-1) === siblingStrings.prefix.slice(0, 1)) {
                siblingStrings.prefix = siblingStrings.prefix.slice(1);
              }
            }
            if (!childIsNumber && !childDecorations && PUNCT[childStrings.suffix.slice(0, 1)] && "string" === typeof child.blobs) {
              mergeChars(child, "blobs", child, "suffix");
            }
            this.downward(parent.blobs[i]);
          }
        }
        function swapToTheLeft(child) {
          var childChar = child.strings.suffix.slice(0, 1);
          if ("string" === typeof child.blobs) {
            while (SWAP_IN[childChar]) {
              mergeChars(child, "blobs", child, "suffix");
              childChar = child.strings.suffix.slice(0, 1);
            }
          } else {
            while (SWAP_IN[childChar]) {
              mergeChars(child.blobs[child.blobs.length - 1], "suffix", child, "suffix");
              childChar = child.strings.suffix.slice(0, 1);
            }
          }
        }
        function swapToTheRight(child) {
          if ("string" === typeof child.blobs) {
            var childChar = child.blobs.slice(-1);
            while (SWAP_OUT[childChar]) {
              mergeChars(child, "blobs", child, "suffix", true);
              childChar = child.blobs.slice(-1);
            }
          } else {
            var childChar = child.blobs[child.blobs.length - 1].strings.suffix.slice(-1);
            while (SWAP_OUT[childChar]) {
              mergeChars(child.blobs[child.blobs.length - 1], "suffix", child, "suffix", true);
              childChar = child.blobs[child.blobs.length - 1].strings.suffix.slice(-1);
            }
          }
        }
        function fix(parent) {
          if ("object" !== typeof parent || "object" !== typeof parent.blobs || !parent.blobs.length) {
            return;
          }
          var lastChar;
          for (var i = 0, ilen = parent.blobs.length; i < ilen; i++) {
            var child = parent.blobs[i];
            var quoteSwap = false;
            for (var j = 0, jlen = child.decorations.length; j < jlen; j++) {
              var decoration = child.decorations[j];
              if (decoration[0] === "@quotes" && decoration[1] !== "false") {
                quoteSwap = true;
              }
            }
            if (quoteSwap) {
              if (punctInQuote) {
                swapToTheLeft(child);
              } else {
                swapToTheRight(child);
              }
            }
            lastChar = this.fix(parent.blobs[i]);
            if (child.blobs && "string" === typeof child.blobs) {
              lastChar = child.blobs.slice(-1);
            }
          }
          return lastChar;
        }
        this.upward = upward;
        this.leftward = leftward;
        this.downward = downward;
        this.fix = fix;
      };
      CSL2.Engine.Opt = function() {
        this.parallel = {
          enable: false
        }, this.has_disambiguate = false;
        this.mode = "html";
        this.dates = {};
        this.jurisdictions_seen = {};
        this.suppressedJurisdictions = {};
        this.inheritedAttributes = {};
        this["locale-sort"] = [];
        this["locale-translit"] = [];
        this["locale-translat"] = [];
        this.citeAffixes = {
          persons: {
            "locale-orig": {
              prefix: "",
              suffix: ""
            },
            "locale-translit": {
              prefix: "",
              suffix: ""
            },
            "locale-translat": {
              prefix: "",
              suffix: ""
            }
          },
          institutions: {
            "locale-orig": {
              prefix: "",
              suffix: ""
            },
            "locale-translit": {
              prefix: "",
              suffix: ""
            },
            "locale-translat": {
              prefix: "",
              suffix: ""
            }
          },
          titles: {
            "locale-orig": {
              prefix: "",
              suffix: ""
            },
            "locale-translit": {
              prefix: "",
              suffix: ""
            },
            "locale-translat": {
              prefix: "",
              suffix: ""
            }
          },
          journals: {
            "locale-orig": {
              prefix: "",
              suffix: ""
            },
            "locale-translit": {
              prefix: "",
              suffix: ""
            },
            "locale-translat": {
              prefix: "",
              suffix: ""
            }
          },
          publishers: {
            "locale-orig": {
              prefix: "",
              suffix: ""
            },
            "locale-translit": {
              prefix: "",
              suffix: ""
            },
            "locale-translat": {
              prefix: "",
              suffix: ""
            }
          },
          places: {
            "locale-orig": {
              prefix: "",
              suffix: ""
            },
            "locale-translit": {
              prefix: "",
              suffix: ""
            },
            "locale-translat": {
              prefix: "",
              suffix: ""
            }
          }
        };
        this["default-locale"] = [];
        this.update_mode = CSL2.NONE;
        this.bib_mode = CSL2.NONE;
        this.sort_citations = false;
        this["et-al-min"] = 0;
        this["et-al-use-first"] = 1;
        this["et-al-use-last"] = false;
        this["et-al-subsequent-min"] = false;
        this["et-al-subsequent-use-first"] = false;
        this["demote-non-dropping-particle"] = "display-and-sort";
        this["parse-names"] = true;
        this.citation_number_slug = false;
        this.trigraph = "Aaaa00:AaAa00:AaAA00:AAAA00";
        this.nodenames = [];
        this.gender = {};
        this["cite-lang-prefs"] = {
          persons: ["orig"],
          institutions: ["orig"],
          titles: ["orig"],
          journals: ["orig"],
          publishers: ["orig"],
          places: ["orig"],
          number: ["orig"]
        };
        this.has_layout_locale = false;
        this.disable_duplicate_year_suppression = [];
        this.use_context_condition = false;
        this.jurisdiction_fallbacks = {};
        this.development_extensions = {};
        this.development_extensions.field_hack = true;
        this.development_extensions.allow_field_hack_date_override = true;
        this.development_extensions.locator_date_and_revision = true;
        this.development_extensions.locator_label_parse = true;
        this.development_extensions.raw_date_parsing = true;
        this.development_extensions.clean_up_csl_flaws = true;
        this.development_extensions.consolidate_legal_items = false;
        this.development_extensions.csl_reverse_lookup_support = false;
        this.development_extensions.wrap_url_and_doi = false;
        this.development_extensions.thin_non_breaking_space_html_hack = false;
        this.development_extensions.apply_citation_wrapper = false;
        this.development_extensions.main_title_from_short_title = false;
        this.development_extensions.uppercase_subtitles = false;
        this.development_extensions.normalize_lang_keys_to_lowercase = false;
        this.development_extensions.strict_text_case_locales = false;
        this.development_extensions.expect_and_symbol_form = false;
        this.development_extensions.require_explicit_legal_case_title_short = false;
        this.development_extensions.spoof_institutional_affiliations = false;
        this.development_extensions.force_jurisdiction = false;
        this.development_extensions.parse_names = true;
        this.development_extensions.hanging_indent_legacy_number = false;
        this.development_extensions.throw_on_empty = false;
        this.development_extensions.strict_inputs = true;
        this.development_extensions.prioritize_disambiguate_condition = false;
        this.development_extensions.force_short_title_casing_alignment = true;
        this.development_extensions.implicit_short_title = false;
        this.development_extensions.force_title_abbrev_fallback = false;
        this.development_extensions.split_container_title = false;
        this.development_extensions.legacy_institution_name_ordering = false;
        this.development_extensions.etal_min_etal_usefirst_hack = false;
      };
      CSL2.Engine.Tmp = function() {
        this.names_max = new CSL2.Stack();
        this.names_base = new CSL2.Stack();
        this.givens_base = new CSL2.Stack();
        this.value = [];
        this.namepart_decorations = {};
        this.namepart_type = false;
        this.area = "citation";
        this.root = "citation";
        this.extension = "";
        this.can_substitute = new CSL2.Stack(0, CSL2.LITERAL);
        this.element_rendered_ok = false;
        this.element_trace = new CSL2.Stack("style");
        this.nameset_counter = 0;
        this.group_context = new CSL2.Stack({
          term_intended: false,
          variable_attempt: false,
          variable_success: false,
          output_tip: void 0,
          label_form: void 0,
          parallel_first: void 0,
          parallel_last: void 0,
          parallel_delimiter_override: void 0,
          condition: false,
          force_suppress: false,
          done_vars: []
        });
        this.term_predecessor = false;
        this.in_cite_predecessor = false;
        this.jump = new CSL2.Stack(0, CSL2.LITERAL);
        this.decorations = new CSL2.Stack();
        this.tokenstore_stack = new CSL2.Stack();
        this.last_suffix_used = "";
        this.last_names_used = [];
        this.last_years_used = [];
        this.years_used = [];
        this.names_used = [];
        this.taintedItemIDs = {};
        this.taintedCitationIDs = {};
        this.initialize_with = new CSL2.Stack();
        this.disambig_request = false;
        this["name-as-sort-order"] = false;
        this.suppress_decorations = false;
        this.disambig_settings = new CSL2.AmbigConfig();
        this.bib_sort_keys = [];
        this.prefix = new CSL2.Stack("", CSL2.LITERAL);
        this.suffix = new CSL2.Stack("", CSL2.LITERAL);
        this.delimiter = new CSL2.Stack("", CSL2.LITERAL);
        this.cite_locales = [];
        this.cite_affixes = {
          citation: false,
          bibliography: false,
          citation_sort: false,
          bibliography_sort: false
        };
        this.strip_periods = 0;
        this.shadow_numbers = {};
        this.authority_stop_last = 0;
        this.loadedItemIDs = {};
        this.condition_counter = 0;
        this.condition_lang_val_arr = [];
        this.condition_lang_counter_arr = [];
      };
      CSL2.Engine.Fun = function(state) {
        this.match = new CSL2.Util.Match();
        this.suffixator = new CSL2.Util.Suffixator(CSL2.SUFFIX_CHARS);
        this.romanizer = new CSL2.Util.Romanizer();
        this.ordinalizer = new CSL2.Util.Ordinalizer(state);
        this.long_ordinalizer = new CSL2.Util.LongOrdinalizer();
      };
      CSL2.Engine.Build = function() {
        this["alternate-term"] = false;
        this.in_bibliography = false;
        this.in_style = false;
        this.skip = false;
        this.postponed_macro = false;
        this.layout_flag = false;
        this.name = false;
        this.names_variables = [[]];
        this.name_label = [{}];
        this.form = false;
        this.term = false;
        this.macro = {};
        this.macro_stack = [];
        this.text = false;
        this.lang = false;
        this.area = "citation";
        this.root = "citation";
        this.extension = "";
        this.substitute_level = new CSL2.Stack(0, CSL2.LITERAL);
        this.names_level = 0;
        this.render_nesting_level = 0;
        this.render_seen = false;
        this.bibliography_key_pos = 0;
      };
      CSL2.Engine.Configure = function() {
        this.tests = [];
        this.fail = [];
        this.succeed = [];
      };
      CSL2.Engine.Citation = function(state) {
        this.opt = {
          inheritedAttributes: {}
        };
        this.tokens = [];
        this.srt = new CSL2.Registry.Comparifier(state, "citation_sort");
        this.opt.collapse = [];
        this.opt["disambiguate-add-names"] = false;
        this.opt["disambiguate-add-givenname"] = false;
        this.opt["disambiguate-add-year-suffix"] = false;
        this.opt["givenname-disambiguation-rule"] = "by-cite";
        this.opt["near-note-distance"] = 5;
        this.opt.topdecor = [];
        this.opt.layout_decorations = [];
        this.opt.layout_prefix = "";
        this.opt.layout_suffix = "";
        this.opt.layout_delimiter = "";
        this.opt.sort_locales = [];
        this.opt.max_number_of_names = 0;
        this.root = "citation";
      };
      CSL2.Engine.Bibliography = function() {
        this.opt = {
          inheritedAttributes: {}
        };
        this.tokens = [];
        this.opt.collapse = [];
        this.opt.topdecor = [];
        this.opt.layout_decorations = [];
        this.opt.layout_prefix = "";
        this.opt.layout_suffix = "";
        this.opt.layout_delimiter = "";
        this.opt["line-spacing"] = 1;
        this.opt["entry-spacing"] = 1;
        this.opt.sort_locales = [];
        this.opt.max_number_of_names = 0;
        this.root = "bibliography";
      };
      CSL2.Engine.BibliographySort = function() {
        this.tokens = [];
        this.opt = {};
        this.opt.sort_directions = [];
        this.opt.topdecor = [];
        this.opt.citation_number_sort_direction = CSL2.ASCENDING;
        this.opt.citation_number_secondary = false;
        this.tmp = {};
        this.keys = [];
        this.root = "bibliography";
      };
      CSL2.Engine.CitationSort = function() {
        this.tokens = [];
        this.opt = {};
        this.opt.sort_directions = [];
        this.keys = [];
        this.opt.topdecor = [];
        this.root = "citation";
      };
      CSL2.Engine.InText = function() {
        this.opt = {
          inheritedAttributes: {}
        };
        this.tokens = [];
        this.opt.collapse = [];
        this.opt["disambiguate-add-names"] = false;
        this.opt["disambiguate-add-givenname"] = false;
        this.opt["disambiguate-add-year-suffix"] = false;
        this.opt["givenname-disambiguation-rule"] = "by-cite";
        this.opt["near-note-distance"] = 5;
        this.opt.topdecor = [];
        this.opt.layout_decorations = [];
        this.opt.layout_prefix = "";
        this.opt.layout_suffix = "";
        this.opt.layout_delimiter = "";
        this.opt.sort_locales = [];
        this.opt.max_number_of_names = 0;
        this.root = "intext";
      };
      CSL2.Engine.prototype.previewCitationCluster = function(citation, citationsPre, citationsPost, newMode) {
        var oldMode = this.opt.mode;
        this.setOutputFormat(newMode);
        if (citation.citationID) {
          delete citation.citationID;
        }
        var ret = this.processCitationCluster(citation, citationsPre, citationsPost, CSL2.PREVIEW);
        this.setOutputFormat(oldMode);
        return ret[1];
      };
      CSL2.Engine.prototype.appendCitationCluster = function(citation) {
        var citationsPre = [];
        var len = this.registry.citationreg.citationByIndex.length;
        for (var pos = 0; pos < len; pos += 1) {
          var c = this.registry.citationreg.citationByIndex[pos];
          citationsPre.push(["" + c.citationID, c.properties.noteIndex]);
        }
        return this.processCitationCluster(citation, citationsPre, [])[1];
      };
      CSL2.Engine.prototype.processCitationCluster = function(citation, citationsPre, citationsPost, flag) {
        var c, preCitation, postCitation, i, ilen, j, jlen, k, klen, n, nlen, key, Item, item, noteCitations, textCitations, m, citationsInNote;
        this.debug = false;
        this.tmp.loadedItemIDs = {};
        this.tmp.citation_errors = [];
        this.registry.return_data = { "bibchange": false };
        this.setCitationId(citation);
        var oldCitationList;
        var oldItemList;
        var oldAmbigs;
        if (flag === CSL2.PREVIEW) {
          if (this.debug) {
            CSL2.debug("****** start state save *********");
          }
          oldCitationList = this.registry.citationreg.citationByIndex.slice();
          oldItemList = this.registry.reflist.slice();
          var newCitationList = citationsPre.concat(citationsPost);
          var newItemIds = {};
          var newItemIdsList = [];
          for (var i = 0, ilen = newCitationList.length; i < ilen; i += 1) {
            c = this.registry.citationreg.citationById[newCitationList[i][0]];
            for (j = 0, jlen = c.citationItems.length; j < jlen; j += 1) {
              newItemIds[c.citationItems[j].id] = true;
              newItemIdsList.push("" + c.citationItems[j].id);
            }
          }
          for (j = 0, jlen = citation.citationItems.length; j < jlen; j += 1) {
            newItemIds[citation.citationItems[j].id] = true;
            newItemIdsList.push("" + citation.citationItems[j].id);
          }
          oldAmbigs = {};
          for (var i = 0, ilen = oldItemList.length; i < ilen; i += 1) {
            if (!newItemIds[oldItemList[i].id]) {
              var oldAkey = this.registry.registry[oldItemList[i].id].ambig;
              var ids = this.registry.ambigcites[oldAkey];
              if (ids) {
                for (j = 0, jlen = ids.length; j < jlen; j += 1) {
                  oldAmbigs[ids[j]] = CSL2.cloneAmbigConfig(this.registry.registry[ids[j]].disambig);
                }
              }
            }
          }
          if (this.debug) {
            CSL2.debug("****** end state save *********");
          }
        }
        this.tmp.taintedCitationIDs = {};
        var sortedItems = [];
        var rerunAkeys = {};
        for (var i = 0, ilen = citation.citationItems.length; i < ilen; i += 1) {
          item = {};
          for (var key in citation.citationItems[i]) {
            item[key] = citation.citationItems[i][key];
          }
          Item = this.retrieveItem("" + item.id);
          if (Item.id) {
            this.transform.loadAbbreviation("default", "hereinafter", Item.id, Item.language);
          }
          item = CSL2.parseLocator.call(this, item);
          if (this.opt.development_extensions.consolidate_legal_items) {
            this.remapSectionVariable([[Item, item]]);
          }
          if (this.opt.development_extensions.locator_label_parse) {
            if (item.locator && ["bill", "gazette", "legislation", "regulation", "treaty"].indexOf(Item.type) === -1 && (!item.label || item.label === "page")) {
              var m = CSL2.LOCATOR_LABELS_REGEXP.exec(item.locator);
              if (m) {
                var tryLabel = CSL2.LOCATOR_LABELS_MAP[m[2]];
                if (this.getTerm(tryLabel)) {
                  item.label = tryLabel;
                  item.locator = m[3];
                }
              }
            }
          }
          var newitem = [Item, item];
          sortedItems.push(newitem);
          citation.citationItems[i].item = Item;
        }
        citation.sortedItems = sortedItems;
        var citationByIndex = [];
        var citationById = {};
        var lastNotePos;
        for (i = 0, ilen = citationsPre.length; i < ilen; i += 1) {
          preCitation = citationsPre[i];
          if (this.opt.development_extensions.strict_inputs) {
            if (citationById[preCitation[0]]) {
              CSL2.error("Previously referenced citationID " + preCitation[0] + " encountered in citationsPre");
            }
            if (preCitation[1]) {
              if (lastNotePos > preCitation[1]) {
                CSL2.debug("Note index sequence is not sane at citationsPre[" + i + "]");
              }
              lastNotePos = preCitation[1];
            }
          }
          this.registry.citationreg.citationById[preCitation[0]].properties.noteIndex = preCitation[1];
          citationByIndex.push(this.registry.citationreg.citationById[preCitation[0]]);
          citationById[preCitation[0]] = this.registry.citationreg.citationById[preCitation[0]];
        }
        if (!citation.properties) {
          citation.properties = {
            noteIndex: 0
          };
        }
        if (this.opt.development_extensions.strict_inputs) {
          if (citationById[citation.citationID]) {
            CSL2.error("Citation with previously referenced citationID " + citation.citationID);
          }
          if (citation.properties.noteIndex) {
            if (lastNotePos > citation.properties.noteIndex) {
              CSL2.debug("Note index sequence is not sane for citation " + citation.citationID);
            }
            lastNotePos = citation.properties.noteIndex;
          }
        }
        citationByIndex.push(citation);
        citationById[citation.citationID] = citation;
        for (i = 0, ilen = citationsPost.length; i < ilen; i += 1) {
          postCitation = citationsPost[i];
          if (this.opt.development_extensions.strict_inputs) {
            if (citationById[postCitation[0]]) {
              CSL2.error("Previously referenced citationID " + postCitation[0] + " encountered in citationsPost");
            }
            if (postCitation[1]) {
              if (lastNotePos > postCitation[1]) {
                CSL2.debug("Note index sequence is not sane at postCitation[" + i + "]");
              }
              lastNotePos = postCitation[1];
            }
          }
          this.registry.citationreg.citationById[postCitation[0]].properties.noteIndex = postCitation[1];
          citationByIndex.push(this.registry.citationreg.citationById[postCitation[0]]);
          citationById[postCitation[0]] = this.registry.citationreg.citationById[postCitation[0]];
        }
        this.registry.citationreg.citationByIndex = citationByIndex;
        this.registry.citationreg.citationById = citationById;
        this.registry.citationreg.citationsByItemId = {};
        if (this.opt.update_mode === CSL2.POSITION) {
          textCitations = [];
          noteCitations = [];
          citationsInNote = {};
        }
        var update_items = [];
        for (var i = 0, ilen = citationByIndex.length; i < ilen; i += 1) {
          citationByIndex[i].properties.index = i;
          for (j = 0, jlen = citationByIndex[i].sortedItems.length; j < jlen; j += 1) {
            item = citationByIndex[i].sortedItems[j];
            if (!this.registry.citationreg.citationsByItemId[item[1].id]) {
              this.registry.citationreg.citationsByItemId[item[1].id] = [];
              update_items.push("" + item[1].id);
            }
            if (this.registry.citationreg.citationsByItemId[item[1].id].indexOf(citationByIndex[i]) === -1) {
              this.registry.citationreg.citationsByItemId[item[1].id].push(citationByIndex[i]);
            }
          }
          if (this.opt.update_mode === CSL2.POSITION) {
            if (citationByIndex[i].properties.noteIndex) {
              noteCitations.push(citationByIndex[i]);
            } else {
              citationByIndex[i].properties.noteIndex = 0;
              textCitations.push(citationByIndex[i]);
            }
          }
        }
        if (flag !== CSL2.ASSUME_ALL_ITEMS_REGISTERED) {
          if (this.debug) {
            CSL2.debug("****** start update items *********");
          }
          this.updateItems(update_items, null, null, true);
          if (this.debug) {
            CSL2.debug("****** endo update items *********");
          }
        }
        if (!this.opt.citation_number_sort && sortedItems && sortedItems.length > 1 && this.citation_sort.tokens.length > 0) {
          for (var i = 0, ilen = sortedItems.length; i < ilen; i += 1) {
            sortedItems[i][1].sortkeys = CSL2.getSortKeys.call(this, sortedItems[i][0], "citation_sort");
          }
          if (this.opt.grouped_sort && !citation.properties.unsorted) {
            for (var i = 0, ilen = sortedItems.length; i < ilen; i += 1) {
              var sortkeys = sortedItems[i][1].sortkeys;
              this.tmp.authorstring_request = true;
              var mydisambig = this.registry.registry[sortedItems[i][0].id].disambig;
              this.tmp.authorstring_request = true;
              CSL2.getAmbiguousCite.call(this, sortedItems[i][0], mydisambig);
              var authorstring = this.registry.authorstrings[sortedItems[i][0].id];
              this.tmp.authorstring_request = false;
              sortedItems[i][1].sortkeys = [authorstring].concat(sortkeys);
            }
            sortedItems.sort(this.citation.srt.compareCompositeKeys);
            var lastauthor = false;
            var thiskey = false;
            var thisauthor = false;
            for (var i = 0, ilen = sortedItems.length; i < ilen; i += 1) {
              if (sortedItems[i][1].sortkeys[0] !== lastauthor) {
                thisauthor = sortedItems[i][1].sortkeys[0];
                thiskey = sortedItems[i][1].sortkeys[1];
              }
              sortedItems[i][1].sortkeys[0] = "" + thiskey + i;
              lastauthor = thisauthor;
            }
          }
          if (!citation.properties.unsorted) {
            sortedItems.sort(this.citation.srt.compareCompositeKeys);
          }
        }
        if (this.opt.parallel.enable) {
          this.parallel.StartCitation(citation.sortedItems);
        }
        var citations;
        if (this.opt.update_mode === CSL2.POSITION) {
          for (var i = 0; i < 2; i += 1) {
            var first_ref = {};
            var last_ref = {};
            var first_container_ref = {};
            citations = [textCitations, noteCitations][i];
            for (j = 0, jlen = citations.length; j < jlen; j += 1) {
              var onecitation = citations[j];
              if (!citations[j].properties.noteIndex) {
                citations[j].properties.noteIndex = 0;
              }
              citations[j].properties.noteIndex = parseInt(citations[j].properties.noteIndex, 10);
              if (j > 0 && onecitation.properties.noteIndex && citations[j - 1].properties.noteIndex > onecitation.properties.noteIndex) {
                citationsInNote = {};
                first_ref = {};
                last_ref = {};
                first_container_ref = {};
              }
              for (k = 0, klen = onecitation.sortedItems.length; k < klen; k += 1) {
                if (onecitation.sortedItems[k][1].parallel && onecitation.sortedItems[k][1].parallel !== "first") {
                  continue;
                }
                if (!citationsInNote[onecitation.properties.noteIndex]) {
                  citationsInNote[onecitation.properties.noteIndex] = 1;
                } else {
                  citationsInNote[onecitation.properties.noteIndex] += 1;
                }
              }
              for (k = 0, klen = citations[j].sortedItems.length; k < klen; k += 1) {
                item = citations[j].sortedItems[k];
                var item_id = item[0].id;
                var first_id = item[0].legislation_id ? item[0].legislation_id : item[0].id;
                var last_id = item[0].legislation_id ? item[0].legislation_id : item[0].container_id ? item[0].container_id : item[0].id;
                var myxloc = item[1]["locator-extra"];
                var mylocator = item[1].locator;
                var mylabel = item[1].label;
                var incitationid;
                var incitationxloc;
                if (k > 0) {
                  if (onecitation.sortedItems[k - 1][0].legislation_id) {
                    incitationid = onecitation.sortedItems[k - 1][0].legislation_id;
                  } else {
                    incitationid = onecitation.sortedItems[k - 1][1].id;
                    incitationxloc = onecitation.sortedItems[k - 1][1]["locator-extra"];
                    for (var l = k - 2; l > -1; l--) {
                      if (onecitation.sortedItems[l][1].parallel === "first") {
                        incitationid = onecitation.sortedItems[l][1].id;
                        incitationxloc = onecitation.sortedItems[l][1]["locator-extra"];
                      }
                    }
                  }
                }
                if (flag === CSL2.PREVIEW) {
                  if (onecitation.citationID != citation.citationID) {
                    if ("undefined" === typeof first_ref[item[1].id]) {
                      first_ref[first_id] = onecitation.properties.noteIndex;
                      last_ref[last_id] = onecitation.properties.noteIndex;
                    } else {
                      last_ref[last_id] = onecitation.properties.noteIndex;
                    }
                    continue;
                  }
                }
                var oldvalue = {};
                oldvalue.position = item[1].position;
                oldvalue["first-reference-note-number"] = item[1]["first-reference-note-number"];
                oldvalue["first-container-reference-note-number"] = item[1]["first-container-reference-note-number"];
                oldvalue["near-note"] = item[1]["near-note"];
                item[1]["first-reference-note-number"] = 0;
                item[1]["first-container-reference-note-number"] = 0;
                item[1]["near-note"] = false;
                if (this.registry.citationreg.citationsByItemId[item_id]) {
                  if (this.opt.xclass === "note" && this.opt.has_disambiguate) {
                    var oldCount = this.registry.registry[item[0].id]["citation-count"];
                    var newCount = this.registry.citationreg.citationsByItemId[item_id].length;
                    this.registry.registry[item[0].id]["citation-count"] = this.registry.citationreg.citationsByItemId[item_id].length;
                    if ("number" === typeof oldCount) {
                      var oldCountCheck = oldCount < 2;
                      var newCountCheck = newCount < 2;
                      if (oldCountCheck !== newCountCheck) {
                        for (var l = 0, llen = this.registry.citationreg.citationsByItemId[item_id].length; l < llen; l++) {
                          rerunAkeys[this.registry.registry[item[0].id].ambig] = true;
                          this.tmp.taintedCitationIDs[this.registry.citationreg.citationsByItemId[item_id][l].citationID] = true;
                        }
                      }
                    } else {
                      for (var l = 0, llen = this.registry.citationreg.citationsByItemId[item_id].length; l < llen; l++) {
                        rerunAkeys[this.registry.registry[item[0].id].ambig] = true;
                        this.tmp.taintedCitationIDs[this.registry.citationreg.citationsByItemId[item_id][l].citationID] = true;
                      }
                    }
                  }
                }
                var oldlastid;
                var oldlastxloc;
                if ("undefined" === typeof last_ref[last_id] && onecitation.properties.mode !== "author-only") {
                  first_ref[first_id] = onecitation.properties.noteIndex;
                  last_ref[last_id] = onecitation.properties.noteIndex;
                  first_container_ref[last_id] = onecitation.properties.noteIndex;
                  item[1].position = CSL2.POSITION_FIRST;
                } else {
                  var ibidme = false;
                  var suprame = false;
                  var prevCitation = null;
                  if (j > 0) {
                    var prevCitation = citations[j - 1];
                  }
                  var thisCitation = citations[j];
                  if (j > 0) {
                    var old_last_id_offset = 1;
                    if (prevCitation.properties.mode === "author-only" && j > 1) {
                      old_last_id_offset = 2;
                    }
                    var adjusted_offset = j - old_last_id_offset;
                    if (citations[adjusted_offset].sortedItems.length) {
                      oldlastid = citations[adjusted_offset].sortedItems.slice(-1)[0][1].id;
                      oldlastxloc = citations[j - old_last_id_offset].sortedItems.slice(-1)[0][1]["locator-extra"];
                    }
                    if (prevCitation.sortedItems.length) {
                      if (prevCitation.sortedItems[0].slice(-1)[0].legislation_id) {
                        oldlastid = prevCitation.sortedItems[0].slice(-1)[0].legislation_id;
                      }
                    }
                  }
                  if (j > 0 && k === 0 && prevCitation.properties.noteIndex !== thisCitation.properties.noteIndex) {
                    var useme = false;
                    var oldid = prevCitation.sortedItems[0][0].id;
                    if (prevCitation.sortedItems[0][0].legislation_id) {
                      oldid = prevCitation.sortedItems[0][0].legislation_id;
                    }
                    if (oldid == first_id && prevCitation.properties.noteIndex >= thisCitation.properties.noteIndex - 1) {
                      var prevxloc = prevCitation.sortedItems[0][1]["locator-extra"];
                      var thisxloc = thisCitation.sortedItems[0][1]["locator-extra"];
                      if ((citationsInNote[prevCitation.properties.noteIndex] === 1 || prevCitation.properties.noteIndex === 0) && prevxloc === thisxloc) {
                        useme = true;
                      }
                    }
                    if (useme) {
                      ibidme = true;
                    } else {
                      suprame = true;
                    }
                  } else if (k > 0 && incitationid == first_id && incitationxloc == myxloc) {
                    ibidme = true;
                  } else if (k === 0 && j > 0 && prevCitation.properties.noteIndex == thisCitation.properties.noteIndex && prevCitation.sortedItems.length && oldlastid == first_id && oldlastxloc == myxloc) {
                    ibidme = true;
                  } else {
                    suprame = true;
                  }
                  var prev, prev_locator, prev_label, curr_locator, curr_label;
                  if (ibidme) {
                    if (k > 0) {
                      prev = onecitation.sortedItems[k - 1][1];
                    } else {
                      prev = citations[j - 1].sortedItems[0][1];
                    }
                    if (prev.locator) {
                      if (prev.label) {
                        prev_label = prev.label;
                      } else {
                        prev_label = "";
                      }
                      prev_locator = "" + prev.locator + prev_label;
                    } else {
                      prev_locator = prev.locator;
                    }
                    if (mylocator) {
                      if (mylabel) {
                        curr_label = mylabel;
                      } else {
                        curr_label = "";
                      }
                      curr_locator = "" + mylocator + curr_label;
                    } else {
                      curr_locator = mylocator;
                    }
                  }
                  if (ibidme && prev_locator && !curr_locator) {
                    ibidme = false;
                    suprame = true;
                  }
                  if (ibidme) {
                    if (!prev_locator && curr_locator) {
                      item[1].position = CSL2.POSITION_IBID_WITH_LOCATOR;
                    } else if (!prev_locator && !curr_locator) {
                      item[1].position = CSL2.POSITION_IBID;
                    } else if (prev_locator && curr_locator === prev_locator) {
                      item[1].position = CSL2.POSITION_IBID;
                    } else if (prev_locator && curr_locator && curr_locator !== prev_locator) {
                      item[1].position = CSL2.POSITION_IBID_WITH_LOCATOR;
                    } else {
                      ibidme = false;
                      suprame = true;
                    }
                  }
                  if (suprame) {
                    item[1].position = CSL2.POSITION_CONTAINER_SUBSEQUENT;
                    if ("undefined" === typeof first_ref[first_id]) {
                      first_ref[first_id] = onecitation.properties.noteIndex;
                    } else {
                      item[1].position = CSL2.POSITION_SUBSEQUENT;
                    }
                  }
                  if (suprame || ibidme) {
                    if (onecitation.properties.mode === "author-only") {
                      item[1].position = CSL2.POSITION_FIRST;
                    }
                    if (first_container_ref[last_id] != onecitation.properties.noteIndex) {
                      item[1]["first-container-reference-note-number"] = first_container_ref[last_id];
                      if (this.registry.registry[item[0].id]) {
                        this.registry.registry[item[0].id]["first-container-reference-note-number"] = first_container_ref[last_id];
                      }
                    }
                    if (first_ref[first_id] != onecitation.properties.noteIndex) {
                      item[1]["first-reference-note-number"] = first_ref[first_id];
                      if (this.registry.registry[item[0].id]) {
                        this.registry.registry[item[0].id]["first-reference-note-number"] = first_ref[first_id];
                      }
                    }
                  }
                }
                if (onecitation.properties.noteIndex) {
                  var note_distance = parseInt(onecitation.properties.noteIndex, 10) - parseInt(last_ref[last_id], 10);
                  if (item[1].position !== CSL2.POSITION_FIRST && note_distance <= this.citation.opt["near-note-distance"]) {
                    item[1]["near-note"] = true;
                  }
                  last_ref[last_id] = onecitation.properties.noteIndex;
                } else if (item[1].position !== CSL2.POSITION_FIRST) {
                  item[1]["near-note"] = true;
                }
                if (onecitation.citationID != citation.citationID) {
                  for (n = 0, nlen = CSL2.POSITION_TEST_VARS.length; n < nlen; n += 1) {
                    var param = CSL2.POSITION_TEST_VARS[n];
                    if (item[1][param] !== oldvalue[param]) {
                      if (this.registry.registry[item[0].id]) {
                        if (param === "first-reference-note-number") {
                          rerunAkeys[this.registry.registry[item[0].id].ambig] = true;
                          this.tmp.taintedItemIDs[item[0].id] = true;
                        }
                      }
                      this.tmp.taintedCitationIDs[onecitation.citationID] = true;
                    }
                  }
                }
                if (this.sys.variableWrapper) {
                  item[1].index = onecitation.properties.index;
                  item[1].noteIndex = onecitation.properties.noteIndex;
                }
              }
            }
          }
        }
        if (this.opt.citation_number_sort && sortedItems && sortedItems.length > 1 && this.citation_sort.tokens.length > 0) {
          if (!citation.properties.unsorted) {
            for (var i = 0, ilen = sortedItems.length; i < ilen; i += 1) {
              sortedItems[i][1].sortkeys = CSL2.getSortKeys.call(this, sortedItems[i][0], "citation_sort");
            }
            sortedItems.sort(this.citation.srt.compareCompositeKeys);
          }
        }
        for (var key in this.tmp.taintedItemIDs) {
          if (this.tmp.taintedItemIDs.hasOwnProperty(key)) {
            citations = this.registry.citationreg.citationsByItemId[key];
            if (citations) {
              for (var i = 0, ilen = citations.length; i < ilen; i += 1) {
                this.tmp.taintedCitationIDs[citations[i].citationID] = true;
              }
            }
          }
        }
        var ret = [];
        if (flag === CSL2.PREVIEW) {
          if (this.debug) {
            CSL2.debug("****** start run processor *********");
          }
          try {
            ret = this.process_CitationCluster.call(this, citation.sortedItems, citation);
          } catch (e) {
            CSL2.error("Error running CSL processor for preview: " + e);
          }
          if (this.debug) {
            CSL2.debug("****** end run processor *********");
            CSL2.debug("****** start state restore *********");
          }
          this.registry.citationreg.citationByIndex = oldCitationList;
          this.registry.citationreg.citationById = {};
          for (var i = 0, ilen = oldCitationList.length; i < ilen; i += 1) {
            this.registry.citationreg.citationById[oldCitationList[i].citationID] = oldCitationList[i];
          }
          if (this.debug) {
            CSL2.debug("****** start final update *********");
          }
          var oldItemIds = [];
          for (var i = 0, ilen = oldItemList.length; i < ilen; i += 1) {
            oldItemIds.push("" + oldItemList[i].id);
          }
          this.updateItems(oldItemIds, null, null, true);
          if (this.debug) {
            CSL2.debug("****** end final update *********");
          }
          for (var key in oldAmbigs) {
            if (oldAmbigs.hasOwnProperty(key)) {
              this.registry.registry[key].disambig = oldAmbigs[key];
            }
          }
          if (this.debug) {
            CSL2.debug("****** end state restore *********");
          }
        } else {
          for (var rerunAkey in rerunAkeys) {
            this.disambiguate.run(rerunAkey, citation);
          }
          var obj;
          for (var key in this.tmp.taintedCitationIDs) {
            if (key == citation.citationID) {
              continue;
            }
            var mycitation = this.registry.citationreg.citationById[key];
            if (!mycitation.properties.unsorted) {
              for (var i = 0, ilen = mycitation.sortedItems.length; i < ilen; i += 1) {
                mycitation.sortedItems[i][1].sortkeys = CSL2.getSortKeys.call(this, mycitation.sortedItems[i][0], "citation_sort");
              }
              mycitation.sortedItems.sort(this.citation.srt.compareCompositeKeys);
            }
            this.tmp.citation_pos = mycitation.properties.index;
            this.tmp.citation_note_index = mycitation.properties.noteIndex;
            this.tmp.citation_id = "" + mycitation.citationID;
            obj = [];
            obj.push(mycitation.properties.index);
            obj.push(this.process_CitationCluster.call(this, mycitation.sortedItems, mycitation));
            obj.push(mycitation.citationID);
            ret.push(obj);
          }
          this.tmp.taintedItemIDs = {};
          this.tmp.taintedCitationIDs = {};
          this.tmp.citation_pos = citation.properties.index;
          this.tmp.citation_note_index = citation.properties.noteIndex;
          this.tmp.citation_id = "" + citation.citationID;
          obj = [];
          obj.push(citationsPre.length);
          obj.push(this.process_CitationCluster.call(this, sortedItems, citation));
          obj.push(citation.citationID);
          ret.push(obj);
          ret.sort(function(a, b) {
            if (a[0] > b[0]) {
              return 1;
            } else if (a[0] < b[0]) {
              return -1;
            } else {
              return 0;
            }
          });
        }
        this.registry.return_data.citation_errors = this.tmp.citation_errors.slice();
        return [this.registry.return_data, ret];
      };
      CSL2.Engine.prototype.process_CitationCluster = function(sortedItems, citation) {
        var str = "";
        if (citation && citation.properties && citation.properties.mode === "composite") {
          citation.properties.mode = "author-only";
          var firstChunk = CSL2.getCitationCluster.call(this, sortedItems, citation);
          citation.properties.mode = "suppress-author";
          var secondChunk = "";
          if (citation.properties.infix) {
            this.output.append(citation.properties.infix);
            secondChunk = this.output.string(this, this.output.queue);
            if ("object" === typeof secondChunk) {
              secondChunk = secondChunk.join("");
            }
          }
          var thirdChunk = CSL2.getCitationCluster.call(this, sortedItems, citation);
          citation.properties.mode = "composite";
          if (firstChunk && secondChunk && CSL2.SWAPPING_PUNCTUATION.concat(["\u2019", "'"]).indexOf(secondChunk[0]) > -1) {
            firstChunk += secondChunk;
            secondChunk = false;
          }
          str = [firstChunk, secondChunk, thirdChunk].filter(function(obj) {
            return obj;
          }).join(" ");
        } else {
          str = CSL2.getCitationCluster.call(this, sortedItems, citation);
        }
        return str;
      };
      CSL2.Engine.prototype.makeCitationCluster = function(rawList) {
        var inputList, newitem, str, pos, len, item, Item;
        inputList = [];
        len = rawList.length;
        for (pos = 0; pos < len; pos += 1) {
          item = {};
          for (var key in rawList[pos]) {
            item[key] = rawList[pos][key];
          }
          Item = this.retrieveItem("" + item.id);
          if (this.opt.development_extensions.locator_label_parse) {
            if (item.locator && ["bill", "gazette", "legislation", "regulation", "treaty"].indexOf(Item.type) === -1 && (!item.label || item.label === "page")) {
              var m = CSL2.LOCATOR_LABELS_REGEXP.exec(item.locator);
              if (m) {
                var tryLabel = CSL2.LOCATOR_LABELS_MAP[m[2]];
                if (this.getTerm(tryLabel)) {
                  item.label = tryLabel;
                  item.locator = m[3];
                }
              }
            }
          }
          if (item.locator) {
            item.locator = ("" + item.locator).replace(/\s+$/, "");
          }
          newitem = [Item, item];
          inputList.push(newitem);
        }
        if (this.opt.development_extensions.consolidate_legal_items) {
          this.remapSectionVariable(inputList);
        }
        if (inputList && inputList.length > 1 && this.citation_sort.tokens.length > 0) {
          len = inputList.length;
          for (pos = 0; pos < len; pos += 1) {
            inputList[pos][1].sortkeys = CSL2.getSortKeys.call(this, inputList[pos][0], "citation_sort");
          }
          inputList.sort(this.citation.srt.compareCompositeKeys);
        }
        this.tmp.citation_errors = [];
        var str = CSL2.getCitationCluster.call(this, inputList);
        return str;
      };
      CSL2.getAmbiguousCite = function(Item, disambig, visualForm, item) {
        var ret;
        var flags = this.tmp.group_context.tip;
        var oldTermSiblingLayer = {
          term_intended: flags.term_intended,
          variable_attempt: flags.variable_attempt,
          variable_success: flags.variable_success,
          output_tip: flags.output_tip,
          label_form: flags.label_form,
          non_parallel: flags.non_parallel,
          parallel_last: flags.parallel_last,
          parallel_first: flags.parallel_first,
          parallel_last_override: flags.parallel_last_override,
          parallel_delimiter_override: flags.parallel_delimiter_override,
          parallel_delimiter_override_on_suppress: flags.parallel_delimiter_override_on_suppress,
          condition: flags.condition,
          force_suppress: flags.force_suppress,
          done_vars: flags.done_vars.slice()
        };
        if (disambig) {
          this.tmp.disambig_request = disambig;
        } else {
          this.tmp.disambig_request = false;
        }
        var itemSupp = {
          position: CSL2.POSITION_SUBSEQUENT,
          "near-note": true
        };
        if (item) {
          itemSupp.locator = item.locator;
          itemSupp.label = item.label;
        }
        if (this.registry.registry[Item.id] && this.registry.citationreg.citationsByItemId && this.registry.citationreg.citationsByItemId[Item.id] && this.registry.citationreg.citationsByItemId[Item.id].length && visualForm) {
          if (this.citation.opt["givenname-disambiguation-rule"] === "by-cite") {
            itemSupp["first-reference-note-number"] = this.registry.registry[Item.id]["first-reference-note-number"];
          }
        }
        this.tmp.area = "citation";
        this.tmp.root = "citation";
        var origSuppressDecorations = this.tmp.suppress_decorations;
        this.tmp.suppress_decorations = true;
        this.tmp.just_looking = true;
        CSL2.getCite.call(this, Item, itemSupp, null, false);
        for (var i = 0, ilen = this.output.queue.length; i < ilen; i += 1) {
          CSL2.Output.Queue.purgeEmptyBlobs(this.output.queue[i]);
        }
        if (this.opt.development_extensions.clean_up_csl_flaws) {
          for (var j = 0, jlen = this.output.queue.length; j < jlen; j += 1) {
            this.output.adjust.upward(this.output.queue[j]);
            this.output.adjust.leftward(this.output.queue[j]);
            this.output.adjust.downward(this.output.queue[j]);
            this.output.adjust.fix(this.output.queue[j]);
          }
        }
        var ret = this.output.string(this, this.output.queue);
        this.tmp.just_looking = false;
        this.tmp.suppress_decorations = origSuppressDecorations;
        this.tmp.group_context.replace(oldTermSiblingLayer);
        return ret;
      };
      CSL2.getSpliceDelimiter = function(last_locator, last_collapsed, pos) {
        if (void 0 !== this.citation.opt["after-collapse-delimiter"]) {
          if (last_locator) {
            this.tmp.splice_delimiter = this.citation.opt["after-collapse-delimiter"];
          } else if (last_collapsed && !this.tmp.have_collapsed) {
            this.tmp.splice_delimiter = this.citation.opt["after-collapse-delimiter"];
          } else if (!last_collapsed && !this.tmp.have_collapsed && this.citation.opt.collapse !== "year-suffix") {
            this.tmp.splice_delimiter = this.citation.opt["after-collapse-delimiter"];
          } else {
            this.tmp.splice_delimiter = this.citation.opt.layout_delimiter;
          }
        } else if (this.tmp.use_cite_group_delimiter) {
          this.tmp.splice_delimiter = this.citation.opt.cite_group_delimiter;
        } else {
          if (this.tmp.have_collapsed && this.opt.xclass === "in-text" && this.opt.update_mode !== CSL2.NUMERIC) {
            this.tmp.splice_delimiter = ", ";
          } else if (this.tmp.cite_locales[pos - 1]) {
            var alt_affixes = this.tmp.cite_affixes[this.tmp.area][this.tmp.cite_locales[pos - 1]];
            if (alt_affixes && alt_affixes.delimiter) {
              this.tmp.splice_delimiter = alt_affixes.delimiter;
            }
          } else if (!this.tmp.splice_delimiter) {
            this.tmp.splice_delimiter = "";
          }
        }
        return this.tmp.splice_delimiter;
      };
      CSL2.getCitationCluster = function(inputList, citation) {
        var result, objects, myparams, len, pos, item, last_collapsed, params, empties, composite, compie, myblobs, Item, llen, ppos, obj, preceding_item, txt_esc, error_object, citationID, authorOnly, suppressAuthor;
        var citation_prefix = "";
        this.output.checkNestedBrace = new CSL2.checkNestedBrace(this);
        if (citation) {
          citationID = citation.citationID;
          authorOnly = citation.properties.mode === "author-only" ? !!citation.properties.mode : false;
          if (this.opt.xclass !== "note") {
            suppressAuthor = citation.properties.mode === "suppress-author" ? !!citation.properties.mode : false;
          }
          if (citation.properties.prefix) {
            citation_prefix = CSL2.checkPrefixSpaceAppend(this, citation.properties.prefix);
          }
        }
        inputList = inputList ? inputList : [];
        this.tmp.last_primary_names_string = false;
        txt_esc = CSL2.getSafeEscape(this);
        this.tmp.area = "citation";
        this.tmp.root = "citation";
        result = "";
        objects = [];
        this.tmp.last_suffix_used = "";
        this.tmp.last_names_used = [];
        this.tmp.last_years_used = [];
        this.tmp.backref_index = [];
        this.tmp.cite_locales = [];
        if (!this.tmp.just_looking) {
          this.tmp.abbrev_trimmer = {
            QUASHES: {}
          };
        }
        var use_layout_prefix = this.output.checkNestedBrace.update(this.citation.opt.layout_prefix + citation_prefix);
        var suppressTrailingPunctuation = false;
        if (this.citation.opt.suppressTrailingPunctuation) {
          suppressTrailingPunctuation = true;
        }
        if (citationID) {
          if (this.registry.citationreg.citationById[citationID].properties["suppress-trailing-punctuation"]) {
            suppressTrailingPunctuation = true;
          }
        }
        if (this.opt.xclass === "note") {
          var parasets = [];
          var lastTitle = false;
          var lastPosition = false;
          var lastID = false;
          var lst = [];
          for (var i = 0, ilen = inputList.length; i < ilen; i += 1) {
            var type = inputList[i][0].type;
            var title = inputList[i][0].title;
            var position = inputList[i][1].position;
            var id = inputList[i][0].id;
            if (title && type === "legal_case" && id !== lastID && position) {
              if (title !== lastTitle || parasets.length === 0) {
                lst = [];
                parasets.push(lst);
              }
              lst.push(inputList[i][1]);
            }
            lastTitle = title;
            lastPosition = position;
            lastID = id;
          }
          for (i = 0, ilen = parasets.length; i < ilen; i += 1) {
            lst = parasets[i];
            if (lst.length < 2) {
              continue;
            }
            var locatorInLastPosition = lst.slice(-1)[0].locator;
            if (locatorInLastPosition) {
              for (var j = 0, jlen = lst.length - 1; j < jlen; j += 1) {
                if (lst[j].locator) {
                  locatorInLastPosition = false;
                }
              }
            }
            if (locatorInLastPosition) {
              lst[0].locator = locatorInLastPosition;
              delete lst.slice(-1)[0].locator;
              lst[0].label = lst.slice(-1)[0].label;
              if (lst.slice(-1)[0].label) {
                delete lst.slice(-1)[0].label;
              }
            }
          }
        }
        myparams = [];
        len = inputList.length;
        if (inputList[0] && inputList[0][1]) {
          if (authorOnly) {
            delete inputList[0][1]["suppress-author"];
            inputList[0][1]["author-only"] = true;
          } else if (suppressAuthor) {
            delete inputList[0][1]["author-only"];
            inputList[0][1]["suppress-author"] = true;
          }
        }
        if (this.opt.parallel.enable) {
          this.parallel.StartCitation(inputList);
        }
        for (pos = 0; pos < len; pos += 1) {
          this.tmp.cite_index = pos;
          Item = inputList[pos][0];
          item = inputList[pos][1];
          item = CSL2.parseLocator.call(this, item);
          last_collapsed = this.tmp.have_collapsed;
          var last_locator = false;
          if (pos > 0 && inputList[pos - 1][1]) {
            last_locator = !!inputList[pos - 1][1].locator;
          }
          params = {};
          this.tmp.shadow_numbers = {};
          if (!this.tmp.just_looking && this.opt.hasPlaceholderTerm) {
            var output = this.output;
            this.output = new CSL2.Output.Queue(this);
            this.output.adjust = new CSL2.Output.Queue.adjust();
            CSL2.getAmbiguousCite.call(this, Item, null, false, item);
            this.output = output;
          }
          this.tmp.in_cite_predecessor = false;
          if (pos > 0) {
            CSL2.getCite.call(this, Item, item, "" + inputList[pos - 1][0].id, true);
          } else {
            this.tmp.term_predecessor = false;
            CSL2.getCite.call(this, Item, item, null, true);
          }
          if (!this.tmp.cite_renders_content) {
            error_object = {
              citationID: "" + this.tmp.citation_id,
              index: this.tmp.citation_pos,
              noteIndex: this.tmp.citation_note_index,
              itemID: "" + Item.id,
              citationItems_pos: pos,
              error_code: CSL2.ERROR_NO_RENDERED_FORM
            };
            this.tmp.citation_errors.push(error_object);
          }
          params.splice_delimiter = CSL2.getSpliceDelimiter.call(this, last_locator, last_collapsed, pos);
          if (item && item["author-only"]) {
            this.tmp.suppress_decorations = true;
          }
          if (pos > 0) {
            preceding_item = inputList[pos - 1][1];
            var precedingEndsInPeriodOrComma = preceding_item.suffix && [";", ".", ","].indexOf(preceding_item.suffix.slice(-1)) > -1;
            var currentStartsWithPeriodOrComma = !preceding_item.suffix && item.prefix && [";", ".", ","].indexOf(item.prefix.slice(0, 1)) > -1;
            if (precedingEndsInPeriodOrComma || currentStartsWithPeriodOrComma) {
              var spaceidx = params.splice_delimiter.indexOf(" ");
              if (spaceidx > -1 && !currentStartsWithPeriodOrComma) {
                params.splice_delimiter = params.splice_delimiter.slice(spaceidx);
              } else {
                params.splice_delimiter = "";
              }
            }
          }
          params.suppress_decorations = this.tmp.suppress_decorations;
          params.have_collapsed = this.tmp.have_collapsed;
          myparams.push(params);
          if (item["author-only"]) {
            break;
          }
        }
        empties = 0;
        myblobs = this.output.queue.slice();
        var citation_suffix = "";
        if (citation) {
          citation_suffix = CSL2.checkSuffixSpacePrepend(this, citation.properties.suffix);
        }
        var suffix = this.citation.opt.layout_suffix;
        var last_locale = this.tmp.cite_locales[this.tmp.cite_locales.length - 1];
        if (last_locale && this.tmp.cite_affixes[this.tmp.area][last_locale] && this.tmp.cite_affixes[this.tmp.area][last_locale].suffix) {
          suffix = this.tmp.cite_affixes[this.tmp.area][last_locale].suffix;
        }
        if (CSL2.TERMINAL_PUNCTUATION.slice(0, -1).indexOf(suffix.slice(0, 1)) > -1) {
          suffix = suffix.slice(0, 1);
        }
        suffix = this.output.checkNestedBrace.update(citation_suffix + suffix);
        for (var i = 0, ilen = this.output.queue.length; i < ilen; i += 1) {
          CSL2.Output.Queue.purgeEmptyBlobs(this.output.queue[i]);
        }
        if (!this.tmp.suppress_decorations && this.output.queue.length) {
          if (!(this.opt.development_extensions.apply_citation_wrapper && this.sys.wrapCitationEntry && !this.tmp.just_looking && this.tmp.area === "citation")) {
            if (!suppressTrailingPunctuation) {
              this.output.queue[this.output.queue.length - 1].strings.suffix = suffix;
            }
            this.output.queue[0].strings.prefix = use_layout_prefix;
          }
        }
        if (this.opt.development_extensions.clean_up_csl_flaws) {
          for (var j = 0, jlen = this.output.queue.length; j < jlen; j += 1) {
            this.output.adjust.upward(this.output.queue[j]);
            this.output.adjust.leftward(this.output.queue[j]);
            this.output.adjust.downward(this.output.queue[j]);
            this.tmp.last_chr = this.output.adjust.fix(this.output.queue[j]);
          }
        }
        for (pos = 0, len = myblobs.length; pos < len; pos += 1) {
          var buffer = [];
          this.output.queue = [myblobs[pos]];
          this.tmp.suppress_decorations = myparams[pos].suppress_decorations;
          this.tmp.splice_delimiter = myparams[pos].splice_delimiter;
          if (myblobs[pos].parallel_delimiter) {
            this.tmp.splice_delimiter = myblobs[pos].parallel_delimiter;
          }
          this.tmp.have_collapsed = myparams[pos].have_collapsed;
          composite = this.output.string(this, this.output.queue);
          this.tmp.suppress_decorations = false;
          if ("string" === typeof composite) {
            this.tmp.suppress_decorations = false;
            if (!composite) {
              if (this.opt.development_extensions.throw_on_empty) {
                CSL2.error("Citation would render no content");
              } else {
                composite = "[NO_PRINTED_FORM]";
              }
            }
            return composite;
          }
          if ("object" === typeof composite && composite.length === 0 && !item["suppress-author"]) {
            if (pos === 0) {
              var errStr = "[CSL STYLE ERROR: reference with no printed form.]";
              var preStr = pos === 0 ? txt_esc(this.citation.opt.layout_prefix) : "";
              var sufStr = pos === myblobs.length - 1 ? txt_esc(this.citation.opt.layout_suffix) : "";
              composite.push(preStr + errStr + sufStr);
            } else if (pos === myblobs.length - 1) {
              var tmpobj = objects[objects.length - 1];
              if (typeof tmpobj === "string") {
                objects[objects.length - 1] += txt_esc(this.citation.opt.layout_suffix);
              } else if (typeof tmpobj === "object") {
                tmpobj.strings.suffix += txt_esc(this.citation.opt.layout_suffix);
              }
            }
          }
          if (buffer.length && "string" === typeof composite[0]) {
            composite.reverse();
            var tmpstr = composite.pop();
            if (tmpstr && tmpstr.slice(0, 1) === ",") {
              buffer.push(tmpstr);
            } else if ("string" == typeof buffer.slice(-1)[0] && buffer.slice(-1)[0].slice(-1) === ",") {
              buffer.push(" " + tmpstr);
            } else if (tmpstr) {
              buffer.push(txt_esc(this.tmp.splice_delimiter) + tmpstr);
            }
          } else {
            composite.reverse();
            compie = composite.pop();
            if ("undefined" !== typeof compie) {
              if (buffer.length && "string" === typeof buffer[buffer.length - 1]) {
                buffer[buffer.length - 1] += compie.successor_prefix;
              }
              buffer.push(compie);
            }
          }
          llen = composite.length;
          for (ppos = 0; ppos < llen; ppos += 1) {
            obj = composite[ppos];
            if ("string" === typeof obj) {
              buffer.push(txt_esc(this.tmp.splice_delimiter) + obj);
              continue;
            }
            compie = composite.pop();
            if ("undefined" !== typeof compie) {
              buffer.push(compie);
            }
          }
          if (buffer.length === 0 && !inputList[pos][1]["suppress-author"]) {
            empties += 1;
          }
          if (buffer.length > 1 && typeof buffer[0] !== "string") {
            buffer = [this.output.renderBlobs(buffer)];
          }
          if (buffer.length) {
            if ("string" === typeof buffer[0]) {
              if (pos > 0) {
                buffer[0] = txt_esc(this.tmp.splice_delimiter) + buffer[0];
              }
            } else {
              if (pos > 0) {
                buffer[0].splice_prefix = this.tmp.splice_delimiter;
              } else {
                buffer[0].splice_prefix = "";
              }
            }
          }
          objects = objects.concat(buffer);
        }
        result += this.output.renderBlobs(objects);
        if (result) {
          if (!this.tmp.suppress_decorations) {
            len = this.citation.opt.layout_decorations.length;
            for (pos = 0; pos < len; pos += 1) {
              params = this.citation.opt.layout_decorations[pos];
              if (params[1] === "normal") {
                continue;
              }
              if (!item || !item["author-only"]) {
                result = this.fun.decorate[params[0]][params[1]](this, result);
              }
            }
          }
        }
        this.tmp.suppress_decorations = false;
        if (!result) {
          if (this.opt.development_extensions.throw_on_empty) {
            CSL2.error("Citation would render no content");
          } else {
            result = "[NO_PRINTED_FORM]";
          }
        }
        return result;
      };
      CSL2.getCite = function(Item, item, prevItemID, blockShadowNumberReset) {
        var next, error_object;
        var areaOrig = this.tmp.area;
        if (item && item["author-only"] && this.intext && this.intext.tokens.length > 0) {
          this.tmp.area = "intext";
        }
        this.tmp.cite_renders_content = false;
        this.tmp.probably_rendered_something = false;
        this.tmp.prevItemID = prevItemID;
        CSL2.citeStart.call(this, Item, item, blockShadowNumberReset);
        next = 0;
        this.tmp.name_node = {};
        this.nameOutput = new CSL2.NameOutput(this, Item, item);
        while (next < this[this.tmp.area].tokens.length) {
          next = CSL2.tokenExec.call(this, this[this.tmp.area].tokens[next], Item, item);
        }
        CSL2.citeEnd.call(this, Item, item);
        if (!this.tmp.cite_renders_content && !this.tmp.just_looking) {
          if (this.tmp.area === "bibliography") {
            error_object = {
              index: this.tmp.bibliography_pos,
              itemID: "" + Item.id,
              error_code: CSL2.ERROR_NO_RENDERED_FORM
            };
            this.tmp.bibliography_errors.push(error_object);
          }
        }
        this.tmp.area = areaOrig;
        return "" + Item.id;
      };
      CSL2.citeStart = function(Item, item, blockShadowNumberReset) {
        this.tmp.lang_array = [];
        if (Item.language) {
          var m = Item.language.match(/^([a-zA-Z]+).*/);
          if (m) {
            this.tmp.lang_array.push(m[1].toLowerCase());
          }
        }
        this.tmp.lang_array.push(this.opt.lang);
        if (!blockShadowNumberReset) {
          this.tmp.shadow_numbers = {};
        }
        this.tmp.disambiguate_count = 0;
        this.tmp.disambiguate_maxMax = 0;
        this.tmp.same_author_as_previous_cite = false;
        if (!this.tmp.suppress_decorations) {
          this.tmp.subsequent_author_substitute_ok = true;
        } else {
          this.tmp.subsequent_author_substitute_ok = false;
        }
        this.tmp.lastchr = "";
        if (this.tmp.area === "citation" && this.citation.opt.collapse && this.citation.opt.collapse.length) {
          this.tmp.have_collapsed = true;
        } else {
          this.tmp.have_collapsed = false;
        }
        this.tmp.render_seen = false;
        if (this.tmp.disambig_request && !this.tmp.disambig_override) {
          this.tmp.disambig_settings = this.tmp.disambig_request;
        } else if (this.registry.registry[Item.id] && !this.tmp.disambig_override) {
          this.tmp.disambig_request = this.registry.registry[Item.id].disambig;
          this.tmp.disambig_settings = this.registry.registry[Item.id].disambig;
        } else {
          this.tmp.disambig_settings = new CSL2.AmbigConfig();
        }
        if (this.tmp.area !== "citation") {
          if (!this.registry.registry[Item.id]) {
            this.tmp.disambig_restore = new CSL2.AmbigConfig();
          } else {
            this.tmp.disambig_restore = CSL2.cloneAmbigConfig(this.registry.registry[Item.id].disambig);
            if (this.tmp.area === "bibliography" && this.tmp.disambig_settings && this.tmp.disambig_override) {
              if (this.opt["disambiguate-add-names"]) {
                this.tmp.disambig_settings.names = this.registry.registry[Item.id].disambig.names.slice();
                if (this.tmp.disambig_request) {
                  this.tmp.disambig_request.names = this.registry.registry[Item.id].disambig.names.slice();
                }
              }
              if (this.opt["disambiguate-add-givenname"]) {
                this.tmp.disambig_request = this.tmp.disambig_settings;
                this.tmp.disambig_settings.givens = this.registry.registry[Item.id].disambig.givens.slice();
                this.tmp.disambig_request.givens = this.registry.registry[Item.id].disambig.givens.slice();
                for (var i = 0, ilen = this.tmp.disambig_settings.givens.length; i < ilen; i += 1) {
                  this.tmp.disambig_settings.givens[i] = this.registry.registry[Item.id].disambig.givens[i].slice();
                }
                for (var i = 0, ilen = this.tmp.disambig_request.givens.length; i < ilen; i += 1) {
                  this.tmp.disambig_request.givens[i] = this.registry.registry[Item.id].disambig.givens[i].slice();
                }
              }
            }
          }
        }
        this.tmp.names_used = [];
        this.tmp.nameset_counter = 0;
        this.tmp.years_used = [];
        this.tmp.names_max.clear();
        if (!this.tmp.just_looking) {
          if (!item || item.parallel === "first" || !item.parallel) {
            this.tmp.abbrev_trimmer = {
              QUASHES: {}
            };
          }
        }
        this.tmp.splice_delimiter = this[this.tmp.area].opt.layout_delimiter;
        this.bibliography_sort.keys = [];
        this.citation_sort.keys = [];
        this.tmp.has_done_year_suffix = false;
        this.tmp.last_cite_locale = false;
        if (!this.tmp.just_looking && item && !item.position && this.registry.registry[Item.id]) {
          this.tmp.disambig_restore = CSL2.cloneAmbigConfig(this.registry.registry[Item.id].disambig);
        }
        this.tmp.first_name_string = false;
        this.tmp.authority_stop_last = 0;
      };
      CSL2.citeEnd = function(Item, item) {
        if (this.tmp.disambig_restore && this.registry.registry[Item.id]) {
          this.registry.registry[Item.id].disambig.names = this.tmp.disambig_restore.names.slice();
          this.registry.registry[Item.id].disambig.givens = this.tmp.disambig_restore.givens.slice();
          for (var i = 0, ilen = this.registry.registry[Item.id].disambig.givens.length; i < ilen; i += 1) {
            this.registry.registry[Item.id].disambig.givens[i] = this.tmp.disambig_restore.givens[i].slice();
          }
        }
        this.tmp.disambig_restore = false;
        if (item && item.suffix) {
          this.tmp.last_suffix_used = item.suffix;
        } else {
          this.tmp.last_suffix_used = "";
        }
        this.tmp.last_years_used = this.tmp.years_used.slice();
        this.tmp.last_names_used = this.tmp.names_used.slice();
        this.tmp.cut_var = false;
        this.tmp.disambig_request = false;
        this.tmp.cite_locales.push(this.tmp.last_cite_locale);
        if (this.tmp.issued_date && this.tmp.renders_collection_number) {
          var buf = [];
          for (var i = this.tmp.issued_date.list.length - 1; i > this.tmp.issued_date.pos; i += -1) {
            buf.push(this.tmp.issued_date.list.pop());
          }
          this.tmp.issued_date.list.pop();
          for (i = buf.length - 1; i > -1; i += -1) {
            this.tmp.issued_date.list.push(buf.pop());
          }
        }
        this.tmp.issued_date = false;
        this.tmp.renders_collection_number = false;
      };
      CSL2.Engine.prototype.makeBibliography = function(bibsection) {
        var debug, ret, params, maxoffset, item, len, pos, tok, tokk, tokkk, entry_ids, entry_strings;
        debug = false;
        if (!bibsection && (this.bibliography.opt.exclude_types || this.bibliography.opt.exclude_with_fields)) {
          bibsection = {
            exclude: []
          };
          if (this.bibliography.opt.exclude_types) {
            for (var i in this.bibliography.opt.exclude_types) {
              var val = this.bibliography.opt.exclude_types[i];
              bibsection.exclude.push({
                field: "type",
                value: val
              });
            }
          }
          if (this.bibliography.opt.exclude_with_fields) {
            for (var i in this.bibliography.opt.exclude_with_fields) {
              var field = this.bibliography.opt.exclude_with_fields[i];
              bibsection.exclude.push({
                field,
                value: true
              });
            }
          }
        }
        if (!this.bibliography.tokens.length) {
          return false;
        }
        if ("string" === typeof bibsection) {
          this.opt.citation_number_slug = bibsection;
          bibsection = false;
        }
        if (debug) {
          len = this.bibliography.tokens.length;
          for (pos = 0; pos < len; pos += 1) {
            tok = this.bibliography.tokens[pos];
            CSL2.debug("bibtok: " + tok.name);
          }
          CSL2.debug("---");
          len = this.citation.tokens.length;
          for (pos = 0; pos < len; pos += 1) {
            tokk = this.citation.tokens[pos];
            CSL2.debug("cittok: " + tok.name);
          }
          CSL2.debug("---");
          len = this.bibliography_sort.tokens.length;
          for (pos = 0; pos < len; pos += 1) {
            tokkk = this.bibliography_sort.tokens[pos];
            CSL2.debug("bibsorttok: " + tok.name);
          }
        }
        ret = CSL2.getBibliographyEntries.call(this, bibsection);
        entry_ids = ret[0];
        entry_strings = ret[1];
        var done = ret[2];
        params = {
          "maxoffset": 0,
          "entryspacing": this.bibliography.opt["entry-spacing"],
          "linespacing": this.bibliography.opt["line-spacing"],
          "second-field-align": false,
          "entry_ids": entry_ids,
          "bibliography_errors": this.tmp.bibliography_errors.slice(),
          "done": done
        };
        if (this.bibliography.opt["second-field-align"]) {
          params["second-field-align"] = this.bibliography.opt["second-field-align"];
        }
        maxoffset = 0;
        len = this.registry.reflist.length;
        for (pos = 0; pos < len; pos += 1) {
          item = this.registry.reflist[pos];
          if (item.offset > params.maxoffset) {
            params.maxoffset = item.offset;
          }
        }
        if (this.bibliography.opt.hangingindent) {
          params.hangingindent = this.bibliography.opt.hangingindent;
        }
        params.bibstart = this.fun.decorate.bibstart;
        params.bibend = this.fun.decorate.bibend;
        this.opt.citation_number_slug = false;
        return [params, entry_strings];
      };
      CSL2.getBibliographyEntries = function(bibsection) {
        var ret, input, include, anymatch, allmatch, bib_entry, res, item, spec, lllen, pppos, topblobs, entry_item_ids, debug, i, ilen, siblings, skips, sortedItems, eyetem, entry_item_data, j, jlen;
        ret = [];
        entry_item_data = [];
        this.tmp.area = "bibliography";
        this.tmp.root = "bibliography";
        this.tmp.last_rendered_name = false;
        this.tmp.bibliography_errors = [];
        this.tmp.bibliography_pos = 0;
        if (bibsection && bibsection.page_start && bibsection.page_length) {
          input = this.registry.getSortedIds();
        } else {
          input = this.refetchItems(this.registry.getSortedIds());
        }
        this.tmp.disambig_override = true;
        function eval_string(a, b) {
          if (a === b) {
            return true;
          }
          return false;
        }
        function eval_list(a, lst) {
          lllen = lst.length;
          for (pppos = 0; pppos < lllen; pppos += 1) {
            if (eval_string(a, lst[pppos])) {
              return true;
            }
          }
          return false;
        }
        function eval_spec(a, b) {
          if ("boolean" === typeof a || !a) {
            if (a) {
              return !!b;
            } else {
              return !b;
            }
          } else {
            if ("string" === typeof b) {
              return eval_string(a, b);
            } else if (!b) {
              return false;
            } else {
              return eval_list(a, b);
            }
          }
        }
        skips = {};
        var page_item_count;
        if (bibsection && bibsection.page_start && bibsection.page_length) {
          page_item_count = 0;
          if (bibsection.page_start !== true) {
            for (i = 0, ilen = input.length; i < ilen; i += 1) {
              skips[input[i]] = true;
              if (bibsection.page_start == input[i]) {
                break;
              }
            }
          }
        }
        var processed_item_ids = [];
        var consolidatedIDs = {};
        this.tmp.container_item_count = {};
        input = input.filter((o) => {
          var ret2 = o;
          if (o.legislation_id) {
            if (consolidatedIDs[o.legislation_id]) {
              ret2 = false;
            } else {
              consolidatedIDs[o.legislation_id] = true;
            }
          } else if (o.container_id) {
            if (!this.tmp.container_item_count[o.container_id]) {
              this.tmp.container_item_count[o.container_id] = 0;
            }
            this.tmp.container_item_count[o.container_id]++;
            if (this.bibliography.opt.consolidate_containers.indexOf(o.type) > -1) {
              if (consolidatedIDs[o.container_id]) {
                ret2 = false;
              } else {
                consolidatedIDs[o.container_id] = true;
              }
            }
          }
          return ret2;
        });
        this.tmp.container_item_pos = {};
        for (i = 0, ilen = input.length; i < ilen; i += 1) {
          if (bibsection && bibsection.page_start && bibsection.page_length) {
            if (skips[input[i]]) {
              continue;
            }
            item = this.refetchItem(input[i]);
            if (page_item_count === bibsection.page_length) {
              break;
            }
          } else {
            item = input[i];
            if (skips[item.id]) {
              continue;
            }
          }
          if (bibsection) {
            include = true;
            if (bibsection.include) {
              include = false;
              for (j = 0, jlen = bibsection.include.length; j < jlen; j += 1) {
                spec = bibsection.include[j];
                if (eval_spec(spec.value, item[spec.field])) {
                  include = true;
                  break;
                }
              }
            } else if (bibsection.exclude) {
              anymatch = false;
              for (j = 0, jlen = bibsection.exclude.length; j < jlen; j += 1) {
                spec = bibsection.exclude[j];
                if (eval_spec(spec.value, item[spec.field])) {
                  anymatch = true;
                  break;
                }
              }
              if (anymatch) {
                include = false;
              }
            } else if (bibsection.select) {
              include = false;
              allmatch = true;
              for (j = 0, jlen = bibsection.select.length; j < jlen; j += 1) {
                spec = bibsection.select[j];
                if (!eval_spec(spec.value, item[spec.field])) {
                  allmatch = false;
                }
              }
              if (allmatch) {
                include = true;
              }
            }
            if (bibsection.quash) {
              allmatch = true;
              for (j = 0, jlen = bibsection.quash.length; j < jlen; j += 1) {
                spec = bibsection.quash[j];
                if (!eval_spec(spec.value, item[spec.field])) {
                  allmatch = false;
                }
              }
              if (allmatch) {
                include = false;
              }
            }
            if (!include) {
              continue;
            }
          }
          if (debug) {
            CSL2.debug("BIB: " + item.id);
          }
          if (item.container_id) {
            if (!this.tmp.container_item_pos[item.container_id]) {
              this.tmp.container_item_pos[item.container_id] = 0;
            }
            this.tmp.container_item_pos[item.container_id]++;
          }
          bib_entry = new CSL2.Token("group", CSL2.START);
          bib_entry.decorations = [["@bibliography", "entry"]].concat(this.bibliography.opt.layout_decorations);
          this.output.startTag("bib_entry", bib_entry);
          if (item.system_id && this.sys.embedBibliographyEntry) {
            this.output.current.value().item_id = item.system_id;
          } else {
            this.output.current.value().system_id = item.id;
          }
          entry_item_ids = [];
          if (this.registry.registry[item.id].master && !(bibsection && bibsection.page_start && bibsection.page_length)) {
            sortedItems = [[item, { id: item.id }]];
            siblings = this.registry.registry[item.id].siblings;
            for (var j = 0, jlen = siblings.length; j < jlen; j++) {
              sortedItems.push([this.refetchItem(siblings[j]), { id: siblings[j] }]);
            }
            this.parallel.StartCitation(sortedItems);
            if (this.registry.registry[item.id].parallel_delimiter_override) {
              this.output.queue[0].strings.delimiter = this.registry.registry[item.id].parallel_delimiter_override;
            } else {
              this.output.queue[0].strings.delimiter = ", ";
            }
            this.tmp.term_predecessor = false;
            this.tmp.cite_index = 0;
            for (j = 0, jlen = sortedItems.length; j < jlen; j += 1) {
              if (j < sortedItems.length - 1) {
                this.tmp.parallel_and_not_last = true;
              } else {
                delete this.tmp.parallel_and_not_last;
              }
              entry_item_ids.push("" + CSL2.getCite.call(this, sortedItems[j][0], sortedItems[j][1]));
              this.tmp.cite_index++;
              skips[sortedItems[j][0].id] = true;
            }
          } else if (!this.registry.registry[item.id].siblings) {
            this.tmp.term_predecessor = false;
            this.tmp.cite_index = 0;
            entry_item_ids.push("" + CSL2.getCite.call(this, item));
            if (bibsection && bibsection.page_start && bibsection.page_length) {
              page_item_count += 1;
            }
          }
          entry_item_data.push("");
          this.tmp.bibliography_pos += 1;
          processed_item_ids.push(entry_item_ids);
          this.output.endTag("bib_entry");
          if (this.output.queue[0].blobs.length && this.output.queue[0].blobs[0].blobs.length) {
            if (!this.output.queue[0].blobs[0].blobs[0].strings) {
              topblobs = this.output.queue[0].blobs;
            } else {
              topblobs = this.output.queue[0].blobs[0].blobs;
            }
            topblobs[0].strings.prefix = this.bibliography.opt.layout_prefix + topblobs[0].strings.prefix;
          }
          for (j = 0, jlen = this.output.queue.length; j < jlen; j += 1) {
            CSL2.Output.Queue.purgeEmptyBlobs(this.output.queue[j]);
          }
          for (j = 0, jlen = this.output.queue.length; j < jlen; j += 1) {
            this.output.adjust.upward(this.output.queue[j]);
            this.output.adjust.leftward(this.output.queue[j]);
            this.output.adjust.downward(this.output.queue[j], true);
            this.output.adjust.fix(this.output.queue[j]);
          }
          res = this.output.string(this, this.output.queue)[0];
          if (!res && this.opt.update_mode === CSL2.NUMERIC) {
            var err = ret.length + 1 + ". [CSL STYLE ERROR: reference with no printed form.]";
            res = CSL2.Output.Formats[this.opt.mode]["@bibliography/entry"](this, err);
          }
          if (res) {
            ret.push(res);
          }
        }
        var done = false;
        if (bibsection && bibsection.page_start && bibsection.page_length) {
          var last_expected_id = input.slice(-1)[0];
          var last_seen_id = processed_item_ids.slice(-1)[0];
          if (!last_expected_id || !last_seen_id || last_expected_id == last_seen_id) {
            done = true;
          }
        }
        this.tmp.disambig_override = false;
        return [processed_item_ids, ret, done];
      };
      CSL2.Engine.prototype.setCitationId = function(citation, force) {
        var ret, id, direction;
        ret = false;
        if (!citation.citationID || force) {
          id = Math.floor(Math.random() * 1e14);
          while (true) {
            direction = 0;
            if (!this.registry.citationreg.citationById[id]) {
              citation.citationID = "a" + id.toString(32);
              break;
            } else if (!direction && id < 5e13) {
              direction = 1;
            } else {
              direction = -1;
            }
            if (direction === 1) {
              id += 1;
            } else {
              id += -1;
            }
          }
          ret = "" + id;
        }
        this.registry.citationreg.citationById[citation.citationID] = citation;
        return ret;
      };
      CSL2.Engine.prototype.rebuildProcessorState = function(citations, mode, uncitedItemIDs) {
        if (!citations) {
          citations = [];
        }
        if (!mode) {
          mode = "html";
        }
        var doneIDs = {};
        var itemIDs = [];
        for (var i = 0, ilen = citations.length; i < ilen; i += 1) {
          for (var j = 0, jlen = citations[i].citationItems.length; j < jlen; j += 1) {
            var itemID = "" + citations[i].citationItems[j].id;
            if (!doneIDs[itemID]) {
              itemIDs.push(itemID);
            }
            doneIDs[itemID] = true;
          }
        }
        this.updateItems(itemIDs);
        var pre = [];
        var post = [];
        var ret = [];
        var oldMode = this.opt.mode;
        this.setOutputFormat(mode);
        for (var i = 0, ilen = citations.length; i < ilen; i += 1) {
          var res = this.processCitationCluster(citations[i], pre, post, CSL2.ASSUME_ALL_ITEMS_REGISTERED);
          pre.push([citations[i].citationID, citations[i].properties.noteIndex]);
          for (var j = 0, jlen = res[1].length; j < jlen; j += 1) {
            var index = res[1][j][0];
            ret[index] = [
              pre[index][0],
              pre[index][1],
              res[1][j][1]
            ];
          }
        }
        this.updateUncitedItems(uncitedItemIDs);
        this.setOutputFormat(oldMode);
        return ret;
      };
      CSL2.Engine.prototype.restoreProcessorState = function(citations) {
        var i, ilen, j, jlen, item, Item, newitem, citationList, itemList, sortedItems;
        citationList = [];
        itemList = [];
        if (!citations) {
          citations = [];
        }
        var indexNumbers = [];
        var citationIds = {};
        for (i = 0, ilen = citations.length; i < ilen; i += 1) {
          if (citationIds[citations[i].citationID]) {
            this.setCitationId(citations[i], true);
          }
          citationIds[citations[i].citationID] = true;
          indexNumbers.push(citations[i].properties.index);
        }
        var oldCitations = citations.slice();
        oldCitations.sort(
          function(a, b) {
            if (a.properties.index < b.properties.index) {
              return -1;
            } else if (a.properties.index > b.properties.index) {
              return 1;
            } else {
              return 0;
            }
          }
        );
        for (i = 0, ilen = oldCitations.length; i < ilen; i += 1) {
          oldCitations[i].properties.index = i;
        }
        for (i = 0, ilen = oldCitations.length; i < ilen; i += 1) {
          sortedItems = [];
          for (j = 0, jlen = oldCitations[i].citationItems.length; j < jlen; j += 1) {
            item = oldCitations[i].citationItems[j];
            if ("undefined" === typeof item.sortkeys) {
              item.sortkeys = [];
            }
            Item = this.retrieveItem("" + item.id);
            newitem = [Item, item];
            sortedItems.push(newitem);
            oldCitations[i].citationItems[j].item = Item;
            itemList.push("" + item.id);
          }
          if (!oldCitations[i].properties.unsorted) {
            sortedItems.sort(this.citation.srt.compareCompositeKeys);
          }
          oldCitations[i].sortedItems = sortedItems;
          this.registry.citationreg.citationById[oldCitations[i].citationID] = oldCitations[i];
        }
        this.updateItems(itemList);
        for (i = 0, ilen = citations.length; i < ilen; i += 1) {
          citationList.push(["" + citations[i].citationID, citations[i].properties.noteIndex]);
        }
        var ret = [];
        if (citations && citations.length) {
          ret = this.processCitationCluster(citations[0], [], citationList.slice(1));
        } else {
          this.registry = new CSL2.Registry(this);
          this.tmp = new CSL2.Engine.Tmp();
          this.disambiguate = new CSL2.Disambiguation(this);
        }
        return ret;
      };
      CSL2.Engine.prototype.updateItems = function(idList, nosort, rerun_ambigs, implicitUpdate) {
        var debug = false;
        var oldArea = this.tmp.area;
        var oldRoot = this.tmp.root;
        var oldExtension = this.tmp.extension;
        if (this.bibliography_sort.tokens.length === 0) {
          nosort = true;
        }
        this.tmp.area = "citation";
        this.tmp.root = "citation";
        this.tmp.extension = "";
        if (!implicitUpdate) {
          this.tmp.loadedItemIDs = {};
        }
        if (debug) {
          CSL2.debug("--> init <--");
        }
        this.registry.init(idList);
        if (rerun_ambigs) {
          for (var ambig in this.registry.ambigcites) {
            this.registry.ambigsTouched[ambig] = true;
          }
        }
        this.registry.dodeletes(this.registry.myhash);
        this.registry.doinserts(this.registry.mylist);
        this.registry.dorefreshes();
        this.registry.rebuildlist(nosort);
        this.registry.setsortkeys();
        this.registry.setdisambigs();
        this.registry.sorttokens(nosort);
        this.registry.renumber();
        this.tmp.extension = oldExtension;
        this.tmp.area = oldArea;
        this.tmp.root = oldRoot;
        return this.registry.getSortedIds();
      };
      CSL2.Engine.prototype.updateUncitedItems = function(idList, nosort) {
        var idHash;
        var oldArea = this.tmp.area;
        var oldRoot = this.tmp.root;
        var oldExtension = this.tmp.extension;
        if (this.bibliography_sort.tokens.length === 0) {
          nosort = true;
        }
        this.tmp.area = "citation";
        this.tmp.root = "citation";
        this.tmp.extension = "";
        this.tmp.loadedItemIDs = {};
        if (!idList) {
          idList = [];
        }
        if ("object" == typeof idList) {
          if ("undefined" == typeof idList.length) {
            idHash = idList;
            idList = [];
            for (var key in idHash) {
              idList.push(key);
            }
          } else if ("number" == typeof idList.length) {
            idHash = {};
            for (var i = 0, ilen = idList.length; i < ilen; i += 1) {
              idHash[idList[i]] = true;
            }
          }
        }
        this.registry.init(idList, true);
        this.registry.dopurge(idHash);
        this.registry.doinserts(this.registry.mylist);
        this.registry.dorefreshes();
        this.registry.rebuildlist(nosort);
        this.registry.setsortkeys();
        this.registry.setdisambigs();
        this.registry.sorttokens(nosort);
        this.registry.renumber();
        this.tmp.extension = oldExtension;
        this.tmp.area = oldArea;
        this.tmp.root = oldRoot;
        return this.registry.getSortedIds();
      };
      CSL2.localeResolve = function(langstr, defaultLocale) {
        var ret, langlst;
        if (!defaultLocale) {
          defaultLocale = "en-US";
        }
        if (!langstr) {
          langstr = defaultLocale;
        }
        ret = {};
        langlst = langstr.split(/[\-_]/);
        ret.base = CSL2.LANG_BASES[langlst[0]];
        if ("undefined" === typeof ret.base) {
          return { base: defaultLocale, best: langstr, bare: langlst[0] };
        }
        if (langlst.length === 1) {
          ret.generic = true;
        }
        if (langlst.length === 1 || langlst[1] === "x") {
          ret.best = ret.base.replace("_", "-");
        } else {
          ret.best = langlst.slice(0, 2).join("-");
        }
        ret.base = ret.base.replace("_", "-");
        ret.bare = langlst[0];
        return ret;
      };
      CSL2.Engine.prototype.localeConfigure = function(langspec, beShy) {
        var localexml;
        if (beShy && this.locale[langspec.best]) {
          return;
        }
        if (langspec.best === "en-US") {
          localexml = CSL2.setupXml(this.sys.retrieveLocale("en-US"));
          this.localeSet(localexml, "en-US", langspec.best);
        } else if (langspec.best !== "en-US") {
          if (langspec.base !== langspec.best) {
            localexml = CSL2.setupXml(this.sys.retrieveLocale(langspec.base));
            this.localeSet(localexml, langspec.base, langspec.best);
          }
          localexml = CSL2.setupXml(this.sys.retrieveLocale(langspec.best));
          this.localeSet(localexml, langspec.best, langspec.best);
        }
        this.localeSet(this.cslXml, "", langspec.best);
        this.localeSet(this.cslXml, langspec.bare, langspec.best);
        if (langspec.base !== langspec.best) {
          this.localeSet(this.cslXml, langspec.base, langspec.best);
        }
        this.localeSet(this.cslXml, langspec.best, langspec.best);
        if ("undefined" === typeof this.locale[langspec.best].terms["page-range-delimiter"]) {
          if (["fr", "pt"].indexOf(langspec.best.slice(0, 2).toLowerCase()) > -1) {
            this.locale[langspec.best].terms["page-range-delimiter"] = "-";
          } else {
            this.locale[langspec.best].terms["page-range-delimiter"] = "\u2013";
          }
        }
        if ("undefined" === typeof this.locale[langspec.best].terms["year-range-delimiter"]) {
          this.locale[langspec.best].terms["year-range-delimiter"] = "\u2013";
        }
        if ("undefined" === typeof this.locale[langspec.best].terms["citation-range-delimiter"]) {
          this.locale[langspec.best].terms["citation-range-delimiter"] = "\u2013";
        }
        if (this.opt.development_extensions.normalize_lang_keys_to_lowercase) {
          var localeLists = ["default-locale", "locale-sort", "locale-translit", "locale-translat"];
          for (var i = 0, ilen = localeLists.length; i < ilen; i += 1) {
            for (var j = 0, jlen = this.opt[localeLists[i]].length; j < jlen; j += 1) {
              this.opt[localeLists[i]][j] = this.opt[localeLists[i]][j].toLowerCase();
            }
          }
          this.opt.lang = this.opt.lang.toLowerCase();
        }
      };
      CSL2.Engine.prototype.localeSet = function(myxml, lang_in, lang_out) {
        var blob, locale, nodes, attributes, pos, term, form, termname, styleopts, date, attrname, len, genderform, target, i, ilen;
        lang_in = lang_in.replace("_", "-");
        lang_out = lang_out.replace("_", "-");
        if (this.opt.development_extensions.normalize_lang_keys_to_lowercase) {
          lang_in = lang_in.toLowerCase();
          lang_out = lang_out.toLowerCase();
        }
        if (!this.locale[lang_out]) {
          this.locale[lang_out] = {};
          this.locale[lang_out].terms = {};
          this.locale[lang_out].opts = {};
          this.locale[lang_out].opts["skip-words"] = CSL2.SKIP_WORDS;
          if (!this.locale[lang_out].opts["leading-noise-words"]) {
            this.locale[lang_out].opts["leading-noise-words"] = [];
          }
          this.locale[lang_out].dates = {};
          this.locale[lang_out].ord = { "1.0.1": false, keys: {} };
          this.locale[lang_out]["noun-genders"] = {};
        }
        locale = myxml.makeXml();
        if (myxml.nodeNameIs(myxml.dataObj, "locale")) {
          locale = myxml.dataObj;
        } else {
          nodes = myxml.getNodesByName(myxml.dataObj, "locale");
          var foundLocale = false;
          for (pos = 0, len = myxml.numberofnodes(nodes); pos < len; pos += 1) {
            blob = nodes[pos];
            if (!foundLocale && myxml.getAttributeValue(blob, "lang", "xml") === lang_in) {
              locale = blob;
              foundLocale = true;
            } else {
              var lang = myxml.getAttributeValue(blob, "lang", "xml");
              var style_options = myxml.getNodesByName(blob, "style-options");
              if (lang && style_options && style_options.length) {
                var jurispref = myxml.getAttributeValue(style_options[0], "jurisdiction-preference");
                if (jurispref) {
                  if (!this.locale[lang]) {
                    this.locale[lang] = {
                      opts: {}
                    };
                  }
                  this.locale[lang].opts["jurisdiction-preference"] = jurispref.split(/\s+/);
                }
              }
            }
          }
        }
        nodes = myxml.getNodesByName(locale, "type");
        for (i = 0, ilen = myxml.numberofnodes(nodes); i < ilen; i += 1) {
          var typenode = nodes[i];
          var type = myxml.getAttributeValue(typenode, "name");
          var gender = myxml.getAttributeValue(typenode, "gender");
          this.opt.gender[type] = gender;
        }
        var hasCslOrdinals101 = myxml.getNodesByName(locale, "term", "ordinal").length;
        if (hasCslOrdinals101) {
          for (var key in this.locale[lang_out].ord.keys) {
            delete this.locale[lang_out].terms[key];
          }
          this.locale[lang_out].ord = { "1.0.1": false, keys: {} };
        }
        nodes = myxml.getNodesByName(locale, "term");
        var ordinals101 = { "last-digit": {}, "last-two-digits": {}, "whole-number": {} };
        var ordinals101_toggle = false;
        var genderized_terms = {};
        for (pos = 0, len = myxml.numberofnodes(nodes); pos < len; pos += 1) {
          term = nodes[pos];
          termname = myxml.getAttributeValue(term, "name");
          if (termname === "sub verbo") {
            termname = "sub-verbo";
          }
          if (termname.slice(0, 7) === "ordinal") {
            if (termname === "ordinal") {
              ordinals101_toggle = true;
            } else {
              var match = myxml.getAttributeValue(term, "match");
              var termstub = termname.slice(8);
              var genderform = myxml.getAttributeValue(term, "gender-form");
              if (!genderform) {
                genderform = "neuter";
              }
              if (!match) {
                match = "last-two-digits";
                if (termstub.slice(0, 1) === "0") {
                  match = "last-digit";
                }
              }
              if (termstub.slice(0, 1) === "0") {
                termstub = termstub.slice(1);
              }
              if (!ordinals101[match][termstub]) {
                ordinals101[match][termstub] = {};
              }
              ordinals101[match][termstub][genderform] = termname;
            }
            this.locale[lang_out].ord.keys[termname] = true;
          }
          if ("undefined" === typeof this.locale[lang_out].terms[termname]) {
            this.locale[lang_out].terms[termname] = {};
          }
          form = "long";
          genderform = false;
          if (myxml.getAttributeValue(term, "form")) {
            form = myxml.getAttributeValue(term, "form");
          }
          if (myxml.getAttributeValue(term, "gender-form")) {
            genderform = myxml.getAttributeValue(term, "gender-form");
          }
          if (myxml.getAttributeValue(term, "gender")) {
            this.locale[lang_out]["noun-genders"][termname] = myxml.getAttributeValue(term, "gender");
          }
          if (genderform) {
            this.locale[lang_out].terms[termname][genderform] = {};
            this.locale[lang_out].terms[termname][genderform][form] = [];
            target = this.locale[lang_out].terms[termname][genderform];
            genderized_terms[termname] = true;
          } else {
            this.locale[lang_out].terms[termname][form] = [];
            target = this.locale[lang_out].terms[termname];
          }
          if (myxml.numberofnodes(myxml.getNodesByName(term, "multiple"))) {
            target[form][0] = myxml.getNodeValue(term, "single");
            if (target[form][0].indexOf("%s") > -1) {
              this.opt.hasPlaceholderTerm = true;
            }
            target[form][1] = myxml.getNodeValue(term, "multiple");
            if (target[form][1].indexOf("%s") > -1) {
              this.opt.hasPlaceholderTerm = true;
            }
          } else {
            target[form] = myxml.getNodeValue(term);
            if (target[form].indexOf("%s") > -1) {
              this.opt.hasPlaceholderTerm = true;
            }
          }
        }
        if (!this.locale[lang_out].terms.supplement) {
          this.locale[lang_out].terms.supplement = {};
        }
        if (!this.locale[lang_out].terms.supplement["long"]) {
          this.locale[lang_out].terms.supplement["long"] = ["supplement", "supplements"];
        }
        if (ordinals101_toggle) {
          for (var ikey in genderized_terms) {
            var gender_segments = {};
            var form_segments = 0;
            for (var jkey in this.locale[lang_out].terms[ikey]) {
              if (["masculine", "feminine"].indexOf(jkey) > -1) {
                gender_segments[jkey] = this.locale[lang_out].terms[ikey][jkey];
              } else {
                form_segments += 1;
              }
            }
            if (!form_segments) {
              if (gender_segments.feminine) {
                for (var jkey in gender_segments.feminine) {
                  this.locale[lang_out].terms[ikey][jkey] = gender_segments.feminine[jkey];
                }
              } else if (gender_segments.masculine) {
                for (var jkey in gender_segments.masculine) {
                  this.locale[lang_out].terms[ikey][jkey] = gender_segments.masculine[jkey];
                }
              }
            }
          }
          this.locale[lang_out].ord["1.0.1"] = ordinals101;
        }
        for (termname in this.locale[lang_out].terms) {
          for (i = 0, ilen = 2; i < ilen; i += 1) {
            genderform = CSL2.GENDERS[i];
            if (this.locale[lang_out].terms[termname][genderform]) {
              for (form in this.locale[lang_out].terms[termname]) {
                if (!this.locale[lang_out].terms[termname][genderform][form]) {
                  this.locale[lang_out].terms[termname][genderform][form] = this.locale[lang_out].terms[termname][form];
                }
              }
            }
          }
        }
        nodes = myxml.getNodesByName(locale, "style-options");
        for (pos = 0, len = myxml.numberofnodes(nodes); pos < len; pos += 1) {
          if (true) {
            styleopts = nodes[pos];
            attributes = myxml.attributes(styleopts);
            for (attrname in attributes) {
              if (attributes.hasOwnProperty(attrname)) {
                if (attrname === "@punctuation-in-quote" || attrname === "@limit-day-ordinals-to-day-1") {
                  if (attributes[attrname] === "true") {
                    this.locale[lang_out].opts[attrname.slice(1)] = true;
                  } else {
                    this.locale[lang_out].opts[attrname.slice(1)] = false;
                  }
                } else if (attrname === "@jurisdiction-preference") {
                  var jurisdiction_preference = attributes[attrname].split(/\s+/);
                  this.locale[lang_out].opts[attrname.slice(1)] = jurisdiction_preference;
                } else if (attrname === "@skip-words") {
                  var skip_words = attributes[attrname].split(/\s*,\s*/);
                  this.locale[lang_out].opts[attrname.slice(1)] = skip_words;
                } else if (attrname === "@leading-noise-words") {
                  var val = attributes[attrname].split(/\s*,\s*/);
                  this.locale[lang_out].opts["leading-noise-words"] = val;
                } else if (attrname === "@name-as-sort-order") {
                  this.locale[lang_out].opts["name-as-sort-order"] = {};
                  var lst = attributes[attrname].split(/\s+/);
                  for (var i = 0, ilen = lst.length; i < ilen; i += 1) {
                    this.locale[lang_out].opts["name-as-sort-order"][lst[i]] = true;
                  }
                } else if (attrname === "@name-as-reverse-order") {
                  this.locale[lang_out].opts["name-as-reverse-order"] = {};
                  var lst = attributes[attrname].split(/\s+/);
                  for (var i = 0, ilen = lst.length; i < ilen; i += 1) {
                    this.locale[lang_out].opts["name-as-reverse-order"][lst[i]] = true;
                  }
                } else if (attrname === "@name-never-short") {
                  this.locale[lang_out].opts["name-never-short"] = {};
                  var lst = attributes[attrname].split(/\s+/);
                  for (var i = 0, ilen = lst.length; i < ilen; i += 1) {
                    this.locale[lang_out].opts["name-never-short"][lst[i]] = true;
                  }
                }
              }
            }
          }
        }
        nodes = myxml.getNodesByName(locale, "date");
        for (pos = 0, len = myxml.numberofnodes(nodes); pos < len; pos += 1) {
          if (true) {
            var date = nodes[pos];
            this.locale[lang_out].dates[myxml.getAttributeValue(date, "form")] = date;
          }
        }
        CSL2.SET_COURT_CLASSES(this, lang_out, myxml, locale);
      };
      CSL2.getLocaleNames = function(myxml, preferredLocale) {
        var stylexml = CSL2.setupXml(myxml);
        function extendLocaleList(localeList, locale) {
          var forms = ["base", "best"];
          if (locale) {
            var normalizedLocale = CSL2.localeResolve(locale);
            for (var i2 = 0, ilen2 = forms.length; i2 < ilen2; i2++) {
              if (normalizedLocale[forms[i2]] && localeList.indexOf(normalizedLocale[forms[i2]]) === -1) {
                localeList.push(normalizedLocale[forms[i2]]);
              }
            }
          }
        }
        var localeIDs = ["en-US"];
        function sniffLocaleOnOneNodeName(nodeName) {
          var nodes = stylexml.getNodesByName(stylexml.dataObj, nodeName);
          for (var i2 = 0, ilen2 = nodes.length; i2 < ilen2; i2++) {
            var nodeLocales = stylexml.getAttributeValue(nodes[i2], "locale");
            if (nodeLocales) {
              nodeLocales = nodeLocales.split(/ +/);
              for (var j = 0, jlen = nodeLocales.length; j < jlen; j++) {
                this.extendLocaleList(localeIDs, nodeLocales[j]);
              }
            }
          }
        }
        extendLocaleList(localeIDs, preferredLocale);
        var styleNode = stylexml.getNodesByName(stylexml.dataObj, "style")[0];
        var defaultLocale = stylexml.getAttributeValue(styleNode, "default-locale");
        extendLocaleList(localeIDs, defaultLocale);
        var nodeNames = ["layout", "if", "else-if", "condition"];
        for (var i = 0, ilen = nodeNames.length; i < ilen; i++) {
          sniffLocaleOnOneNodeName(stylexml, localeIDs, nodeNames[i]);
        }
        return localeIDs;
      };
      CSL2.Node = {};
      CSL2.Node.bibliography = {
        build: function(state, target) {
          if (this.tokentype === CSL2.START) {
            state.build.area = "bibliography";
            state.build.root = "bibliography";
            state.build.extension = "";
            var func = function(state2) {
              state2.tmp.area = "bibliography";
              state2.tmp.root = "bibliography";
              state2.tmp.extension = "";
            };
            this.execs.push(func);
          }
          target.push(this);
        }
      };
      CSL2.Node.choose = {
        build: function(state, target) {
          var func;
          if (this.tokentype === CSL2.START) {
            func = function(state2) {
              state2.tmp.jump.push(void 0, CSL2.LITERAL);
            };
          }
          if (this.tokentype === CSL2.END) {
            func = function(state2) {
              state2.tmp.jump.pop();
            };
          }
          this.execs.push(func);
          target.push(this);
        },
        configure: function(state, pos) {
          if (this.tokentype === CSL2.END) {
            state.configure.fail.push(pos);
            state.configure.succeed.push(pos);
          } else {
            state.configure.fail.pop();
            state.configure.succeed.pop();
          }
        }
      };
      CSL2.Node.citation = {
        build: function(state, target) {
          if (this.tokentype === CSL2.START) {
            state.build.area = "citation";
            state.build.root = "citation";
            state.build.extension = "";
            var func = function(state2) {
              state2.tmp.area = "citation";
              state2.tmp.root = "citation";
              state2.tmp.extension = "";
            };
            this.execs.push(func);
          }
          if (this.tokentype === CSL2.END) {
            state.opt.grouped_sort = state.opt.xclass === "in-text" && (state.citation.opt.collapse && state.citation.opt.collapse.length) || state.citation.opt.cite_group_delimiter && state.citation.opt.cite_group_delimiter.length && state.opt.update_mode !== CSL2.POSITION && state.opt.update_mode !== CSL2.NUMERIC;
            if (state.opt.grouped_sort && state.citation_sort.opt.sort_directions.length) {
              var firstkey = state.citation_sort.opt.sort_directions[0].slice();
              state.citation_sort.opt.sort_directions = [firstkey].concat(state.citation_sort.opt.sort_directions);
            }
            state.citation.srt = new CSL2.Registry.Comparifier(state, "citation_sort");
          }
          target.push(this);
        }
      };
      CSL2.Node["#comment"] = {
        // This is a comment in the CSL file.
        build: function() {
        }
      };
      CSL2.Node.date = {
        build: function(state, target) {
          var func, date_obj, len, pos, part, dpx, parts, mypos, start, end;
          if (this.tokentype === CSL2.START || this.tokentype === CSL2.SINGLETON) {
            state.dateput.string(state, state.dateput.queue);
            state.tmp.date_token = CSL2.Util.cloneToken(this);
            state.tmp.date_token.strings.prefix = "";
            state.tmp.date_token.strings.suffix = "";
            state.dateput.openLevel(this);
            state.build.date_parts = [];
            state.build.date_variables = this.variables;
            if (!state.build.extension) {
              CSL2.Util.substituteStart.call(this, state, target);
            }
            if (state.build.extension) {
              func = CSL2.dateMacroAsSortKey;
            } else {
              func = function(state2, Item, item) {
                var dp;
                state2.tmp.element_rendered_ok = false;
                state2.tmp.donesies = [];
                state2.tmp.dateparts = [];
                dp = [];
                if (this.variables.length && !(state2.tmp.just_looking && this.variables[0] === "accessed")) {
                  date_obj = Item[this.variables[0]];
                  if ("undefined" === typeof date_obj) {
                    date_obj = { "date-parts": [[0]] };
                    if (state2.opt.development_extensions.locator_date_and_revision) {
                      if (item && this.variables[0] === "locator-date" && item["locator-date"]) {
                        date_obj = item["locator-date"];
                      }
                    }
                  }
                  state2.tmp.date_object = date_obj;
                  len = this.dateparts.length;
                  for (pos = 0; pos < len; pos += 1) {
                    part = this.dateparts[pos];
                    if ("undefined" !== typeof state2.tmp.date_object[part + "_end"]) {
                      dp.push(part);
                    } else if (part === "month" && "undefined" !== typeof state2.tmp.date_object.season_end) {
                      dp.push(part);
                    }
                  }
                  dpx = [];
                  parts = ["year", "month", "day"];
                  len = parts.length;
                  for (pos = 0; pos < len; pos += 1) {
                    if (dp.indexOf(parts[pos]) > -1) {
                      dpx.push(parts[pos]);
                    }
                  }
                  dp = dpx.slice();
                  mypos = 2;
                  len = dp.length;
                  for (pos = 0; pos < len; pos += 1) {
                    part = dp[pos];
                    start = state2.tmp.date_object[part];
                    end = state2.tmp.date_object[part + "_end"];
                    if (start !== end) {
                      mypos = pos;
                      break;
                    }
                  }
                  state2.tmp.date_collapse_at = dp.slice(mypos);
                } else {
                  state2.tmp.date_object = false;
                }
              };
            }
            this.execs.push(func);
            func = function(state2, Item) {
              if (!Item[this.variables[0]]) {
                return;
              }
              state2.output.startTag("date", this);
              if (this.variables[0] === "issued" && (Item.type === "legal_case" || Item.type === "legislation") && state2.opt.disable_duplicate_year_suppression.indexOf(Item.country) === -1 && !state2.tmp.extension && "" + Item["collection-number"] === "" + state2.tmp.date_object.year && this.dateparts.length === 1 && this.dateparts[0] === "year") {
                for (var key in state2.tmp.date_object) {
                  if (state2.tmp.date_object.hasOwnProperty(key)) {
                    if (key.slice(0, 4) === "year") {
                      state2.tmp.issued_date = {};
                      var lst = state2.output.current.mystack.slice(-2)[0].blobs;
                      state2.tmp.issued_date.list = lst;
                      state2.tmp.issued_date.pos = lst.length - 1;
                    }
                  }
                }
              }
            };
            this.execs.push(func);
          }
          if (!state.build.extension && (this.tokentype === CSL2.END || this.tokentype === CSL2.SINGLETON)) {
            func = function(state2, Item) {
              if (!Item[this.variables[0]]) {
                return;
              }
              state2.output.endTag();
            };
            this.execs.push(func);
          }
          target.push(this);
          if (this.tokentype === CSL2.END || this.tokentype === CSL2.SINGLETON) {
            if (!state.build.extension) {
              CSL2.Util.substituteEnd.call(this, state, target);
            }
          }
        }
      };
      CSL2.Node["date-part"] = {
        build: function(state, target) {
          var func, pos, len, first_date, value, value_end, real, have_collapsed, invoked, precondition, known_year, bc, ad, bc_end, ad_end, ready, curr, dcurr, number, num, formatter, item, blob;
          if (!this.strings.form) {
            this.strings.form = "long";
          }
          state.build.date_parts.push(this.strings.name);
          var date_variable = state.build.date_variables[0];
          function formatAndStrip(myform, gender, val) {
            if (!val) {
              return val;
            }
            val = "" + CSL2.Util.Dates[this.strings.name][myform](state, val, gender, this.default_locale);
            if ("month" === this.strings.name) {
              if (state.tmp.strip_periods) {
                val = val.replace(/\./g, "");
              } else {
                for (var i = 0, ilen = this.decorations.length; i < ilen; i += 1) {
                  if ("@strip-periods" === this.decorations[i][0] && "true" === this.decorations[i][1]) {
                    val = val.replace(/\./g, "");
                    break;
                  }
                }
              }
            }
            return val;
          }
          func = function(state2, Item) {
            if (!state2.tmp.date_object) {
              return;
            } else {
              state2.tmp.probably_rendered_something = true;
            }
            var last_string_output = "";
            first_date = true;
            value = "";
            value_end = "";
            state2.tmp.donesies.push(this.strings.name);
            if (state2.tmp.date_object.literal && "year" === this.strings.name) {
              last_string_output = state2.tmp.date_object.literal;
              state2.output.append(state2.tmp.date_object.literal, this);
            }
            if (state2.tmp.date_object) {
              value = state2.tmp.date_object[this.strings.name];
              value_end = state2.tmp.date_object[this.strings.name + "_end"];
            }
            if ("year" === this.strings.name && value === 0 && !state2.tmp.suppress_decorations) {
              value = false;
            }
            real = !state2.tmp.suppress_decorations;
            have_collapsed = state2.tmp.have_collapsed;
            invoked = state2[state2.tmp.area].opt.collapse === "year-suffix" || state2[state2.tmp.area].opt.collapse === "year-suffix-ranged";
            precondition = state2.opt["disambiguate-add-year-suffix"];
            if (real && precondition && invoked) {
              state2.tmp.years_used.push(value);
              known_year = state2.tmp.last_years_used.length >= state2.tmp.years_used.length;
              if (known_year && have_collapsed) {
                if (state2.tmp.last_years_used[state2.tmp.years_used.length - 1] === value) {
                  value = false;
                }
              }
            }
            if ("undefined" !== typeof value) {
              bc = false;
              ad = false;
              bc_end = false;
              ad_end = false;
              if ("year" === this.strings.name) {
                if (parseInt(value, 10) < 500 && parseInt(value, 10) > 0) {
                  ad = state2.getTerm("ad");
                }
                if (parseInt(value, 10) < 0) {
                  bc = state2.getTerm("bc");
                  value = parseInt(value, 10) * -1;
                }
                if (value_end) {
                  if (parseInt(value_end, 10) < 500 && parseInt(value_end, 10) > 0) {
                    ad_end = state2.getTerm("ad");
                  }
                  if (parseInt(value_end, 10) < 0) {
                    bc_end = state2.getTerm("bc");
                    value_end = parseInt(value_end, 10) * -1;
                  }
                }
              }
              var monthnameid = "" + state2.tmp.date_object.month;
              while (monthnameid.length < 2) {
                monthnameid = "0" + monthnameid;
              }
              monthnameid = "month-" + monthnameid;
              var gender = state2.locale[state2.opt.lang]["noun-genders"][monthnameid];
              if (this.strings.form) {
                var myform = this.strings.form;
                var myform_end = this.strings.form;
                if (this.strings.name === "day") {
                  if (myform === "ordinal" && state2.locale[state2.opt.lang].opts["limit-day-ordinals-to-day-1"]) {
                    if (value != 1) {
                      myform = "numeric";
                    }
                    if (value_end != 1) {
                      myform_end = "numeric";
                    }
                  }
                }
                value = formatAndStrip.call(this, myform, gender, value);
                value_end = formatAndStrip.call(this, myform_end, gender, value_end);
              }
              state2.output.openLevel("empty");
              if (state2.tmp.date_collapse_at.length) {
                ready = true;
                len = state2.tmp.date_collapse_at.length;
                for (pos = 0; pos < len; pos += 1) {
                  item = state2.tmp.date_collapse_at[pos];
                  if (state2.tmp.donesies.indexOf(item) === -1) {
                    ready = false;
                    break;
                  }
                }
                if (ready) {
                  if ("" + value_end !== "0") {
                    if (state2.dateput.queue.length === 0) {
                      first_date = true;
                    }
                    if (state2.opt["year-range-format"] && state2.opt["year-range-format"] !== "expanded" && !state2.tmp.date_object.day && !state2.tmp.date_object.month && !state2.tmp.date_object.season && this.strings.name === "year" && value && value_end) {
                      value_end = state2.fun.year_mangler(value + "-" + value_end, true);
                      var range_delimiter = state2.getTerm("year-range-delimiter");
                      value_end = value_end.slice(value_end.indexOf(range_delimiter) + 1);
                    }
                    last_string_output = value_end;
                    state2.dateput.append(value_end, this);
                    if (first_date) {
                      blob = state2.dateput.current.value().blobs[0];
                      if (blob) {
                        blob.strings.prefix = "";
                      }
                    }
                  }
                  last_string_output = value;
                  state2.output.append(value, this);
                  curr = state2.output.current.value();
                  blob = curr.blobs[curr.blobs.length - 1];
                  if (blob) {
                    blob.strings.suffix = "";
                  }
                  if (this.strings["range-delimiter"]) {
                    state2.output.append(this.strings["range-delimiter"]);
                  } else {
                    state2.output.append(state2.getTerm("year-range-delimiter"), "empty");
                  }
                  state2.dateput.closeLevel();
                  dcurr = state2.dateput.current.value();
                  curr.blobs = curr.blobs.concat(dcurr);
                  state2.dateput.string(state2, state2.dateput.queue);
                  state2.dateput.openLevel(state2.tmp.date_token);
                  state2.tmp.date_collapse_at = [];
                } else {
                  last_string_output = value;
                  state2.output.append(value, this);
                  if (state2.tmp.date_collapse_at.indexOf(this.strings.name) > -1) {
                    if ("" + value_end !== "0") {
                      if (state2.dateput.queue.length === 0) {
                        first_date = true;
                      }
                      state2.dateput.openLevel("empty");
                      last_string_output = value_end;
                      state2.dateput.append(value_end, this);
                      if (first_date) {
                        blob = state2.dateput.current.value().blobs[0];
                        if (blob) {
                          blob.strings.prefix = "";
                        }
                      }
                      if (bc) {
                        last_string_output = bc;
                        state2.dateput.append(bc);
                      }
                      if (ad) {
                        last_string_output = ad;
                        state2.dateput.append(ad);
                      }
                      state2.dateput.closeLevel();
                    }
                  }
                }
              } else {
                last_string_output = value;
                state2.output.append(value, this);
              }
              if (bc) {
                last_string_output = bc;
                state2.output.append(bc);
              }
              if (ad) {
                last_string_output = ad;
                state2.output.append(ad);
              }
              state2.output.closeLevel();
            } else if ("month" === this.strings.name) {
              if (state2.tmp.date_object.season) {
                value = "" + state2.tmp.date_object.season;
                if (value && value.match(/^[1-4]$/)) {
                  state2.tmp.group_context.tip.variable_success = true;
                  last_string_output = "winter";
                  state2.output.append(state2.getTerm("season-0" + value), this);
                } else if (value) {
                  last_string_output = value;
                  state2.output.append(value, this);
                }
              }
            }
            state2.tmp.value = [];
            if (Item[date_variable] && (value || state2.tmp.have_collapsed) && !state2.opt.has_year_suffix && "year" === this.strings.name && !state2.tmp.just_looking) {
              if (state2.registry.registry[Item.id] && state2.registry.registry[Item.id].disambig.year_suffix !== false && !state2.tmp.has_done_year_suffix) {
                state2.tmp.has_done_year_suffix = true;
                last_string_output = "x";
                num = parseInt(state2.registry.registry[Item.id].disambig.year_suffix, 10);
                number = new CSL2.NumericBlob(state2, false, num, this, Item.id);
                this.successor_prefix = state2[state2.build.area].opt.layout_delimiter;
                this.splice_prefix = state2[state2.build.area].opt.layout_delimiter;
                formatter = new CSL2.Util.Suffixator(CSL2.SUFFIX_CHARS);
                number.setFormatter(formatter);
                if (state2[state2.tmp.area].opt.collapse === "year-suffix-ranged") {
                  number.range_prefix = state2.getTerm("citation-range-delimiter");
                }
                if (state2[state2.tmp.area].opt.cite_group_delimiter) {
                  number.successor_prefix = state2[state2.tmp.area].opt.cite_group_delimiter;
                } else if (state2[state2.tmp.area].opt["year-suffix-delimiter"]) {
                  number.successor_prefix = state2[state2.tmp.area].opt["year-suffix-delimiter"];
                } else {
                  number.successor_prefix = state2[state2.tmp.area].opt.layout_delimiter;
                }
                number.UGLY_DELIMITER_SUPPRESS_HACK = true;
                state2.output.append(number, "literal");
              }
            }
            if (last_string_output && !state2.tmp.group_context.tip.condition) {
              state2.tmp.just_did_number = last_string_output.match(/[0-9]$/);
              if (state2.output.current.tip.strings.suffix) {
                state2.tmp.just_did_number = false;
              }
            }
          };
          this.execs.push(func);
          target.push(this);
        }
      };
      CSL2.Node["else-if"] = {
        //
        // these function are the same as those in if, might just clone
        build: function(state, target) {
          CSL2.Conditions.TopNode.call(this, state, target);
          target.push(this);
        },
        configure: function(state, pos) {
          CSL2.Conditions.Configure.call(this, state, pos);
        }
      };
      CSL2.Node["else"] = {
        build: function(state, target) {
          target.push(this);
        },
        configure: function(state, pos) {
          if (this.tokentype === CSL2.START) {
            state.configure.fail[state.configure.fail.length - 1] = pos;
          }
        }
      };
      CSL2.Node["et-al"] = {
        build: function(state, target) {
          if (state.build.area === "citation" || state.build.area === "bibliography") {
            var func = function(state2) {
              state2.tmp.etal_node = this;
              if ("string" === typeof this.strings.term) {
                state2.tmp.etal_term = this.strings.term;
              }
            };
            this.execs.push(func);
          }
          target.push(this);
        }
      };
      CSL2.Node.group = {
        build: function(state, target, realGroup) {
          var func, execs;
          this.realGroup = realGroup;
          if (this.tokentype === CSL2.START) {
            CSL2.Util.substituteStart.call(this, state, target);
            if (state.build.substitute_level.value()) {
              state.build.substitute_level.replace(state.build.substitute_level.value() + 1);
            }
            if (!this.juris) {
              target.push(this);
            }
            func = function(state2) {
              state2.output.startTag("group", this);
              if (this.strings.label_form_override) {
                if (!state2.tmp.group_context.tip.label_form) {
                  state2.tmp.group_context.tip.label_form = this.strings.label_form_override;
                }
              }
              if (this.strings.label_capitalize_if_first_override) {
                if (!state2.tmp.group_context.tip.label_capitalize_if_first) {
                  state2.tmp.group_context.tip.label_capitalize_if_first = this.strings.label_capitalize_if_first_override;
                }
              }
              if (this.realGroup) {
                if (state2.tmp.group_context.tip.condition) {
                  CSL2.UPDATE_GROUP_CONTEXT_CONDITION(state2, this.strings.prefix, null, this);
                }
                var condition = false;
                var force_suppress = false;
                if (state2.tmp.group_context.mystack.length) {
                  state2.output.current.value().parent = state2.tmp.group_context.tip.output_tip;
                }
                var label_form = state2.tmp.group_context.tip.label_form;
                if (!label_form) {
                  label_form = this.strings.label_form_override;
                }
                var label_capitalize_if_first = state2.tmp.group_context.tip.label_capitalize_if_first;
                if (!label_capitalize_if_first) {
                  label_capitalize_if_first = this.strings.label_capitalize_if_first;
                }
                if (state2.tmp.group_context.tip.condition) {
                  condition = state2.tmp.group_context.tip.condition;
                  force_suppress = state2.tmp.group_context.tip.force_suppress;
                } else if (this.strings.reject) {
                  condition = {
                    test: this.strings.reject,
                    not: true
                  };
                } else if (this.strings.require) {
                  condition = {
                    test: this.strings.require,
                    not: false
                  };
                }
                var context = {
                  old_term_predecessor: state2.tmp.term_predecessor,
                  term_intended: false,
                  variable_attempt: false,
                  variable_success: false,
                  variable_success_parent: state2.tmp.group_context.tip.variable_success,
                  output_tip: state2.output.current.tip,
                  label_form,
                  label_static: state2.tmp.group_context.tip.label_static,
                  label_capitalize_if_first,
                  parallel_delimiter_override: this.strings.set_parallel_delimiter_override,
                  parallel_delimiter_override_on_suppress: this.strings.set_parallel_delimiter_override_on_suppress,
                  condition,
                  force_suppress,
                  done_vars: state2.tmp.group_context.tip.done_vars.slice()
                };
                if (this.non_parallel) {
                  var non_parallel = state2.tmp.group_context.tip.non_parallel;
                  if (!non_parallel) {
                    non_parallel = {};
                  }
                  Object.assign(non_parallel, this.non_parallel);
                  context.non_parallel = non_parallel;
                }
                if (this.parallel_first) {
                  var parallel_first = state2.tmp.group_context.tip.parallel_first;
                  if (!parallel_first) {
                    parallel_first = {};
                  }
                  Object.assign(parallel_first, this.parallel_first);
                  context.parallel_first = parallel_first;
                }
                if (this.parallel_last) {
                  var parallel_last = state2.tmp.group_context.tip.parallel_last;
                  if (!parallel_last) {
                    parallel_last = {};
                  }
                  Object.assign(parallel_last, this.parallel_last);
                  context.parallel_last = parallel_last;
                }
                if (state2.tmp.abbrev_trimmer && state2.tmp.abbrev_trimmer.LAST_TO_FIRST && context.parallel_last) {
                  if (!context.parallel_first) {
                    context.parallel_first = {};
                  }
                  for (var varname in state2.tmp.abbrev_trimmer.LAST_TO_FIRST) {
                    if (context.parallel_last[varname]) {
                      context.parallel_first[varname] = true;
                      delete context.parallel_last[varname];
                    }
                  }
                }
                state2.tmp.group_context.push(context);
                if (state2.tmp.abbrev_trimmer && this.parallel_last_to_first) {
                  if (!state2.tmp.abbrev_trimmer.LAST_TO_FIRST) {
                    state2.tmp.abbrev_trimmer.LAST_TO_FIRST = {};
                  }
                  for (var varname in this.parallel_last_to_first) {
                    state2.tmp.abbrev_trimmer.LAST_TO_FIRST[varname] = true;
                  }
                }
              }
            };
            execs = [];
            execs.push(func);
            this.execs = execs.concat(this.execs);
            if (this.strings["has-publisher-and-publisher-place"]) {
              state.build["publisher-special"] = true;
              if (this.strings["subgroup-delimiter"]) {
                func = function(state2, Item) {
                  if (Item.publisher && Item["publisher-place"]) {
                    var publisher_lst = Item.publisher.split(/;\s*/);
                    var publisher_place_lst = Item["publisher-place"].split(/;\s*/);
                    if (publisher_lst.length > 1 && publisher_lst.length === publisher_place_lst.length) {
                      state2.publisherOutput = new CSL2.PublisherOutput(state2, this);
                      state2.publisherOutput["publisher-list"] = publisher_lst;
                      state2.publisherOutput["publisher-place-list"] = publisher_place_lst;
                    }
                  }
                };
                this.execs.push(func);
              }
            }
            if (this.juris) {
              var choose_start = new CSL2.Token("choose", CSL2.START);
              CSL2.Node.choose.build.call(choose_start, state, target);
              var if_start = new CSL2.Token("if", CSL2.START);
              func = /* @__PURE__ */ (function(macroName) {
                return function(Item, item) {
                  return CSL2.INIT_JURISDICTION_MACROS(state, Item, item, macroName);
                };
              })(this.juris);
              if_start.tests ? {} : if_start.tests = [];
              if_start.tests.push(func);
              if_start.test = state.fun.match.any(if_start, state, if_start.tests);
              target.push(if_start);
              var text_node = new CSL2.Token("text", CSL2.SINGLETON);
              func = function(state2, Item, item) {
                var itemItem = Item;
                if (item && item["best-jurisdiction"] && this.juris === "juris-locator") {
                  itemItem = item;
                }
                var next = 0;
                if (state2.juris[itemItem["best-jurisdiction"]][this.juris]) {
                  while (next < state2.juris[itemItem["best-jurisdiction"]][this.juris].length) {
                    next = CSL2.tokenExec.call(state2, state2.juris[itemItem["best-jurisdiction"]][this.juris][next], Item, item);
                  }
                }
              };
              text_node.juris = this.juris;
              text_node.execs.push(func);
              target.push(text_node);
              var if_end = new CSL2.Token("if", CSL2.END);
              CSL2.Node["if"].build.call(if_end, state, target);
              var else_start = new CSL2.Token("else", CSL2.START);
              CSL2.Node["else"].build.call(else_start, state, target);
            }
          }
          if (this.tokentype === CSL2.END) {
            if (state.build["publisher-special"]) {
              state.build["publisher-special"] = false;
              func = function(state2) {
                if (state2.publisherOutput) {
                  state2.publisherOutput.render();
                  state2.publisherOutput = false;
                }
              };
              this.execs.push(func);
            }
            func = function(state2, Item, item) {
              if (!state2.tmp.group_context.tip.condition) {
                if (state2.output.current.tip.strings.suffix) {
                  state2.tmp.just_did_number = false;
                }
              }
              state2.output.endTag();
              if (this.realGroup) {
                var flags = state2.tmp.group_context.pop();
                if (flags.parallel_delimiter_override) {
                  state2.tmp.group_context.tip.parallel_delimiter_override = flags.parallel_delimiter_override;
                  if (!state2.tmp.just_looking && state2.registry.registry[Item.id].master) {
                    state2.registry.registry[Item.id].parallel_delimiter_override = flags.parallel_delimiter_override;
                  }
                }
                if (flags.parallel_delimiter_override_on_suppress) {
                  state2.tmp.group_context.tip.parallel_delimiter_override_on_suppress = flags.parallel_delimiter_override_on_suppress;
                }
                if (state2.tmp.area === "bibliography_sort") {
                  var citationNumberIdx = flags.done_vars.indexOf("citation-number");
                  if (this.strings.sort_direction && citationNumberIdx > -1 && state2.tmp.group_context.length() == 1) {
                    if (this.strings.sort_direction === CSL2.DESCENDING) {
                      state2.bibliography_sort.opt.citation_number_sort_direction = CSL2.DESCENDING;
                    } else {
                      state2.bibliography_sort.opt.citation_number_sort_direction = CSL2.ASCENDING;
                    }
                    flags.done_vars = flags.done_vars.slice(0, citationNumberIdx).concat(flags.done_vars.slice(citationNumberIdx + 1));
                  }
                }
                if (flags.condition) {
                  flags.force_suppress = CSL2.EVALUATE_GROUP_CONDITION(state2, flags);
                }
                if (state2.tmp.group_context.tip.condition) {
                  state2.tmp.group_context.tip.force_suppress = flags.force_suppress;
                }
                if (!flags.force_suppress && (flags.variable_success || flags.term_intended && !flags.variable_attempt)) {
                  if (!this.isJurisLocatorLabel) {
                    state2.tmp.group_context.tip.variable_success = true;
                  }
                  var blobs = state2.output.current.value().blobs;
                  var pos = state2.output.current.value().blobs.length - 1;
                  if (!state2.tmp.just_looking && (flags.non_parallel || flags.parallel_last || flags.parallel_first || flags.parallel_delimiter_override || flags.parallel_delimiter_override_on_suppress)) {
                    var hasRepeat = state2.parallel.checkRepeats(flags);
                    if (hasRepeat) {
                      if (blobs) {
                        blobs.pop();
                      }
                    }
                    if (state2.tmp.cite_index > 0 && (hasRepeat || !flags.parallel_first && !flags.parallel_last && !flags.non_parallel)) {
                      var info = state2.tmp.suppress_repeats[state2.tmp.cite_index - 1];
                      if (hasRepeat && flags.parallel_delimiter_override_on_suppress && (info.SIBLING || info.ORPHAN)) {
                        state2.output.queue.slice(-1)[0].parallel_delimiter = flags.parallel_delimiter_override_on_suppress;
                      } else if (flags.parallel_delimiter_override && info.SIBLING) {
                        state2.output.queue.slice(-1)[0].parallel_delimiter = flags.parallel_delimiter_override;
                      }
                    }
                  }
                } else {
                  state2.tmp.term_predecessor = flags.old_term_predecessor;
                  state2.tmp.group_context.tip.variable_attempt = flags.variable_attempt;
                  if (flags.force_suppress && !state2.tmp.group_context.tip.condition) {
                    state2.tmp.group_context.tip.variable_attempt = true;
                    state2.tmp.group_context.tip.variable_success = flags.variable_success_parent;
                  }
                  if (flags.force_suppress) {
                    for (var i = 0, ilen = flags.done_vars.length; i < ilen; i++) {
                      var doneVar = flags.done_vars[i];
                      for (var j = 0, jlen = state2.tmp.done_vars.length; j < jlen; j++) {
                        if (state2.tmp.done_vars[j] === doneVar) {
                          state2.tmp.done_vars = state2.tmp.done_vars.slice(0, j).concat(state2.tmp.done_vars.slice(j + 1));
                        }
                      }
                    }
                  }
                  if (state2.output.current.value().blobs) {
                    state2.output.current.value().blobs.pop();
                  }
                }
              }
            };
            this.execs.push(func);
            if (this.juris) {
              var else_end = new CSL2.Token("else", CSL2.END);
              CSL2.Node["else"].build.call(else_end, state, target);
              var choose_end = new CSL2.Token("choose", CSL2.END);
              CSL2.Node.choose.build.call(choose_end, state, target);
            }
          }
          if (this.tokentype === CSL2.END) {
            if (!this.juris) {
              target.push(this);
            }
            if (state.build.substitute_level.value()) {
              state.build.substitute_level.replace(state.build.substitute_level.value() - 1);
            }
            CSL2.Util.substituteEnd.call(this, state, target);
          }
        }
      };
      CSL2.Node["if"] = {
        build: function(state, target) {
          CSL2.Conditions.TopNode.call(this, state, target);
          target.push(this);
        },
        configure: function(state, pos) {
          CSL2.Conditions.Configure.call(this, state, pos);
        }
      };
      CSL2.Node["conditions"] = {
        build: function(state) {
          if (this.tokentype === CSL2.START) {
            state.tmp.conditions.addMatch(this.match);
          }
          if (this.tokentype === CSL2.END) {
            state.tmp.conditions.matchCombine();
          }
        }
      };
      CSL2.Node["condition"] = {
        build: function(state) {
          if (this.tokentype === CSL2.SINGLETON) {
            var test = state.fun.match[this.match](this, state, this.tests);
            state.tmp.conditions.addTest(test);
          }
        }
      };
      CSL2.Conditions = {};
      CSL2.Conditions.TopNode = function(state) {
        var func;
        if (this.tokentype === CSL2.START || this.tokentype === CSL2.SINGLETON) {
          if (this.locale) {
            state.opt.lang = this.locale;
          }
          if (!this.tests || !this.tests.length) {
            state.tmp.conditions = new CSL2.Conditions.Engine(state, this);
          } else {
            this.test = state.fun.match[this.match](this, state, this.tests);
          }
          if (state.build.substitute_level.value() === 0) {
            func = function(state2) {
              state2.tmp.condition_counter++;
            };
            this.execs.push(func);
          }
        }
        if (this.tokentype === CSL2.END || this.tokentype === CSL2.SINGLETON) {
          if (state.build.substitute_level.value() === 0) {
            func = function(state2) {
              state2.tmp.condition_counter--;
              if (state2.tmp.condition_lang_counter_arr.length > 0) {
                var counter = state2.tmp.condition_lang_counter_arr.slice(-1)[0];
                if (counter === state2.tmp.condition_counter) {
                  state2.opt.lang = state2.tmp.condition_lang_val_arr.pop();
                  state2.tmp.condition_lang_counter_arr.pop();
                }
              }
              if (this.locale_default) {
                state2.output.current.value().old_locale = this.locale_default;
                state2.output.closeLevel("empty");
                state2.opt.lang = this.locale_default;
              }
            };
            this.execs.push(func);
          }
          func = function(state2) {
            var next = this[state2.tmp.jump.value()];
            return next;
          };
          this.execs.push(func);
          if (this.locale_default) {
            state.opt.lang = this.locale_default;
          }
        }
      };
      CSL2.Conditions.Configure = function(state, pos) {
        if (this.tokentype === CSL2.START) {
          this.fail = state.configure.fail.slice(-1)[0];
          this.succeed = this.next;
          state.configure.fail[state.configure.fail.length - 1] = pos;
        } else if (this.tokentype === CSL2.SINGLETON) {
          this.fail = this.next;
          this.succeed = state.configure.succeed.slice(-1)[0];
          state.configure.fail[state.configure.fail.length - 1] = pos;
        } else {
          this.succeed = state.configure.succeed.slice(-1)[0];
          this.fail = this.next;
        }
      };
      CSL2.Conditions.Engine = function(state, token) {
        this.token = token;
        this.state = state;
      };
      CSL2.Conditions.Engine.prototype.addTest = function(test) {
        this.token.tests ? {} : this.token.tests = [];
        this.token.tests.push(test);
      };
      CSL2.Conditions.Engine.prototype.addMatch = function(match) {
        this.token.match = match;
      };
      CSL2.Conditions.Engine.prototype.matchCombine = function() {
        this.token.test = this.state.fun.match[this.token.match](this.token, this.state, this.token.tests);
      };
      CSL2.Node.info = {
        build: function(state) {
          if (this.tokentype === CSL2.START) {
            state.build.skip = "info";
          } else {
            state.build.skip = false;
          }
        }
      };
      CSL2.Node.institution = {
        build: function(state, target) {
          if ([CSL2.SINGLETON, CSL2.START].indexOf(this.tokentype) > -1) {
            var func = function(state2) {
              if ("string" === typeof this.strings.delimiter) {
                state2.tmp.institution_delimiter = this.strings.delimiter;
              } else {
                state2.tmp.institution_delimiter = state2.tmp.name_delimiter;
              }
              if ("text" === state2.inheritOpt(this, "and")) {
                this.and_term = state2.getTerm("and", "long", 0);
              } else if ("symbol" === state2.inheritOpt(this, "and")) {
                if (state2.opt.development_extensions.expect_and_symbol_form) {
                  this.and_term = state2.getTerm("and", "symbol", 0);
                } else {
                  this.and_term = "&";
                }
              } else if ("none" === state2.inheritOpt(this, "and")) {
                this.and_term = state2.tmp.institution_delimiter;
              }
              if ("undefined" === typeof this.and_term && state2.tmp.and_term) {
                this.and_term = state2.tmp.and_term;
              }
              if (CSL2.STARTSWITH_ROMANESQUE_REGEXP.test(this.and_term)) {
                this.and_prefix_single = " ";
                this.and_prefix_multiple = ", ";
                if ("string" === typeof state2.tmp.institution_delimiter) {
                  this.and_prefix_multiple = state2.tmp.institution_delimiter;
                }
                this.and_suffix = " ";
              } else {
                this.and_prefix_single = "";
                this.and_prefix_multiple = "";
                this.and_suffix = "";
              }
              if (state2.inheritOpt(this, "delimiter-precedes-last") === "always") {
                this.and_prefix_single = state2.tmp.institution_delimiter;
              } else if (state2.inheritOpt(this, "delimiter-precedes-last") === "never") {
                if (this.and_prefix_multiple) {
                  this.and_prefix_multiple = " ";
                }
              }
              this.and = {};
              if ("undefined" !== typeof this.and_term) {
                state2.output.append(this.and_term, "empty", true);
                this.and.single = state2.output.pop();
                this.and.single.strings.prefix = this.and_prefix_single;
                this.and.single.strings.suffix = this.and_suffix;
                state2.output.append(this.and_term, "empty", true);
                this.and.multiple = state2.output.pop();
                this.and.multiple.strings.prefix = this.and_prefix_multiple;
                this.and.multiple.strings.suffix = this.and_suffix;
              } else if ("undefined" !== this.strings.delimiter) {
                this.and.single = new CSL2.Blob(state2.tmp.institution_delimiter);
                this.and.single.strings.prefix = "";
                this.and.single.strings.suffix = "";
                this.and.multiple = new CSL2.Blob(state2.tmp.institution_delimiter);
                this.and.multiple.strings.prefix = "";
                this.and.multiple.strings.suffix = "";
              }
              state2.nameOutput.institution = this;
            };
            this.execs.push(func);
          }
          target.push(this);
        },
        configure: function(state) {
          if ([CSL2.SINGLETON, CSL2.START].indexOf(this.tokentype) > -1) {
            state.build.has_institution = true;
          }
        }
      };
      CSL2.Node["institution-part"] = {
        build: function(state, target) {
          var func;
          if ("long" === this.strings.name) {
            if (this.strings["if-short"]) {
              func = function(state2) {
                state2.nameOutput.institutionpart["long-with-short"] = this;
              };
            } else {
              func = function(state2) {
                state2.nameOutput.institutionpart["long"] = this;
              };
            }
          } else if ("short" === this.strings.name) {
            func = function(state2) {
              state2.nameOutput.institutionpart["short"] = this;
            };
          }
          this.execs.push(func);
          target.push(this);
        }
      };
      CSL2.Node.key = {
        build: function(state, target) {
          target = state[state.build.root + "_sort"].tokens;
          var func;
          var debug = false;
          var start_key = new CSL2.Token("key", CSL2.START);
          state.tmp.root = state.build.root;
          start_key.strings["et-al-min"] = state.inheritOpt(this, "et-al-min");
          start_key.strings["et-al-use-first"] = state.inheritOpt(this, "et-al-use-first");
          start_key.strings["et-al-use-last"] = state.inheritOpt(this, "et-al-use-last");
          func = function(state2) {
            state2.tmp.done_vars = [];
          };
          start_key.execs.push(func);
          func = function(state2) {
            state2.output.openLevel("empty");
          };
          start_key.execs.push(func);
          var sort_direction = [];
          if (this.strings.sort_direction === CSL2.DESCENDING) {
            sort_direction.push(1);
            sort_direction.push(-1);
          } else {
            sort_direction.push(-1);
            sort_direction.push(1);
          }
          state[state.build.area].opt.sort_directions.push(sort_direction);
          if (CSL2.DATE_VARIABLES.indexOf(this.variables[0]) > -1) {
            state.build.date_key = true;
          }
          func = function(state2) {
            state2.tmp.sort_key_flag = true;
            if (state2.inheritOpt(this, "et-al-min")) {
              state2.tmp["et-al-min"] = state2.inheritOpt(this, "et-al-min");
            }
            if (state2.inheritOpt(this, "et-al-use-first")) {
              state2.tmp["et-al-use-first"] = state2.inheritOpt(this, "et-al-use-first");
            }
            if ("boolean" === typeof state2.inheritOpt(this, "et-al-use-last")) {
              state2.tmp["et-al-use-last"] = state2.inheritOpt(this, "et-al-use-last");
            }
          };
          start_key.execs.push(func);
          target.push(start_key);
          if (this.variables.length) {
            var variable = this.variables[0];
            if (CSL2.NAME_VARIABLES.indexOf(variable) > -1) {
              var names_start_token = new CSL2.Token("names", CSL2.START);
              names_start_token.tokentype = CSL2.START;
              names_start_token.variables = this.variables;
              CSL2.Node.names.build.call(names_start_token, state, target);
              var name_token = new CSL2.Token("name", CSL2.SINGLETON);
              name_token.tokentype = CSL2.SINGLETON;
              name_token.strings["name-as-sort-order"] = "all";
              name_token.strings["sort-separator"] = " ";
              name_token.strings["et-al-use-last"] = state.inheritOpt(this, "et-al-use-last");
              name_token.strings["et-al-min"] = state.inheritOpt(this, "et-al-min");
              name_token.strings["et-al-use-first"] = state.inheritOpt(this, "et-al-use-first");
              CSL2.Node.name.build.call(name_token, state, target);
              var institution_token = new CSL2.Token("institution", CSL2.SINGLETON);
              institution_token.tokentype = CSL2.SINGLETON;
              CSL2.Node.institution.build.call(institution_token, state, target);
              var names_end_token = new CSL2.Token("names", CSL2.END);
              names_end_token.tokentype = CSL2.END;
              CSL2.Node.names.build.call(names_end_token, state, target);
            } else {
              var single_text = new CSL2.Token("text", CSL2.SINGLETON);
              single_text.strings.sort_direction = this.strings.sort_direction;
              single_text.dateparts = this.dateparts;
              if (CSL2.NUMERIC_VARIABLES.indexOf(variable) > -1) {
                if (variable === "citation-number") {
                  func = function(state2, Item) {
                    if (state2.tmp.area === "bibliography_sort") {
                      if (this.strings.sort_direction === CSL2.DESCENDING) {
                        state2.bibliography_sort.opt.citation_number_sort_direction = CSL2.DESCENDING;
                      } else {
                        state2.bibliography_sort.opt.citation_number_sort_direction = CSL2.ASCENDING;
                      }
                    }
                    if (state2.tmp.area === "citation_sort" && state2.bibliography_sort.tmp.citation_number_map) {
                      var num = state2.bibliography_sort.tmp.citation_number_map[state2.registry.registry[Item.id].seq];
                    } else {
                      var num = state2.registry.registry[Item.id].seq;
                    }
                    if (num) {
                      num = CSL2.Util.padding("" + num);
                    }
                    state2.output.append(num, this);
                  };
                } else {
                  func = function(state2, Item) {
                    var num = false;
                    num = Item[variable];
                    if (num) {
                      num = CSL2.Util.padding(num);
                    }
                    state2.output.append(num, this);
                  };
                }
              } else if (variable === "citation-label") {
                func = function(state2, Item) {
                  var trigraph = state2.getCitationLabel(Item);
                  state2.output.append(trigraph, this);
                };
              } else if (CSL2.DATE_VARIABLES.indexOf(variable) > -1) {
                func = CSL2.dateAsSortKey;
                single_text.variables = this.variables;
              } else if ("title" === variable) {
                var abbrevfam = "title";
                var abbrfall = false;
                var altvar = false;
                var transfall = true;
                func = state.transform.getOutputFunction(this.variables, abbrevfam, abbrfall, altvar, transfall);
              } else if ("court-class" === variable) {
                func = function(state2, Item, item) {
                  CSL2.INIT_JURISDICTION_MACROS(state2, Item, item, "juris-main");
                  var cls = CSL2.GET_COURT_CLASS(state2, Item, true);
                  state2.output.append(cls, "empty");
                };
              } else {
                func = function(state2, Item) {
                  var varval = Item[variable];
                  state2.output.append(varval, "empty");
                };
              }
              single_text.execs.push(func);
              target.push(single_text);
            }
          } else {
            var token = new CSL2.Token("text", CSL2.SINGLETON);
            token.strings.sort_direction = this.strings.sort_direction;
            token.postponed_macro = this.postponed_macro;
            CSL2.expandMacro.call(state, token, target);
          }
          var end_key = new CSL2.Token("key", CSL2.END);
          func = function(state2) {
            var keystring = state2.output.string(state2, state2.output.queue);
            if (state2.sys.normalizeUnicode) {
              keystring = state2.sys.normalizeUnicode(keystring);
            }
            keystring = keystring ? keystring.split(" ").join(state2.opt.sort_sep) + state2.opt.sort_sep : "";
            if (debug) {
              CSL2.debug("keystring: " + keystring + " " + typeof keystring);
            }
            if ("" === keystring) {
              keystring = void 0;
            }
            if ("string" !== typeof keystring) {
              keystring = void 0;
            }
            state2[state2[state2.tmp.area].root + "_sort"].keys.push(keystring);
            state2.tmp.value = [];
          };
          end_key.execs.push(func);
          if (state.build.date_key) {
            if (state.build.area === "citation" && state.build.extension === "_sort") {
              state[state.build.area].opt.sort_directions.push([-1, 1]);
              func = function(state2, Item) {
                var year_suffix = state2.registry.registry[Item.id].disambig.year_suffix;
                if (!year_suffix) {
                  year_suffix = 0;
                }
                var key = CSL2.Util.padding("" + year_suffix);
                state2[state2.tmp.area].keys.push(key);
              };
              end_key.execs.push(func);
            }
            state.build.date_key = false;
          }
          func = function(state2) {
            state2.tmp["et-al-min"] = void 0;
            state2.tmp["et-al-use-first"] = void 0;
            state2.tmp["et-al-use-last"] = void 0;
            state2.tmp.sort_key_flag = false;
          };
          end_key.execs.push(func);
          target.push(end_key);
        }
      };
      CSL2.Node.label = {
        build: function(state, target) {
          if (this.strings.term) {
            var func = function(state2, Item, item) {
              var termtxt = CSL2.evaluateLabel(this, state2, Item, item);
              if (item && this.strings.term === "locator") {
                item.section_form_override = this.strings.form;
              }
              if (termtxt) {
                state2.tmp.group_context.tip.term_intended = true;
              }
              CSL2.UPDATE_GROUP_CONTEXT_CONDITION(state2, termtxt, null, this);
              if (termtxt.indexOf("%s") === -1) {
                if (this.strings.capitalize_if_first) {
                  if (!state2.tmp.term_predecessor && !(state2.opt["class"] === "in-text" && state2.tmp.area === "citation")) {
                    termtxt = CSL2.Output.Formatters["capitalize-first"](state2, termtxt);
                  }
                }
                state2.output.append(termtxt, this);
              }
            };
            this.execs.push(func);
          } else {
            if (!this.strings.form) {
              this.strings.form = "long";
            }
            var namevars = state.build.names_variables[state.build.names_variables.length - 1];
            var namelabels = state.build.name_label[state.build.name_label.length - 1];
            for (var i = 0, ilen = namevars.length; i < ilen; i += 1) {
              if (!namelabels[namevars[i]]) {
                namelabels[namevars[i]] = {};
              }
            }
            if (!state.build.name_flag) {
              for (var i = 0, ilen = namevars.length; i < ilen; i += 1) {
                namelabels[namevars[i]].before = this;
              }
            } else {
              for (var i = 0, ilen = namevars.length; i < ilen; i += 1) {
                namelabels[namevars[i]].after = this;
              }
            }
          }
          target.push(this);
        }
      };
      CSL2.Node.layout = {
        build: function(state, target) {
          var func, prefix_token, suffix_token, tok;
          function setSuffix() {
            if (state.build.area === "bibliography") {
              suffix_token = new CSL2.Token("text", CSL2.SINGLETON);
              func = function(state2) {
                if (!state2.tmp.parallel_and_not_last) {
                  var suffix;
                  if (state2.tmp.cite_affixes[state2.tmp.area][state2.tmp.last_cite_locale]) {
                    suffix = state2.tmp.cite_affixes[state2.tmp.area][state2.tmp.last_cite_locale].suffix;
                  } else {
                    suffix = state2.bibliography.opt.layout_suffix;
                  }
                  var topblob = state2.output.current.value();
                  if (state2.opt.using_display) {
                    topblob.blobs[topblob.blobs.length - 1].strings.suffix = suffix;
                  } else {
                    topblob.strings.suffix = suffix;
                  }
                }
                if (state2.bibliography.opt["second-field-align"]) {
                  state2.output.endTag("bib_other");
                }
              };
              suffix_token.execs.push(func);
              target.push(suffix_token);
            }
          }
          if (this.tokentype === CSL2.START) {
            if (this.locale_raw) {
              state.build.current_default_locale = this.locale_raw;
            } else {
              state.build.current_default_locale = state.opt["default-locale"];
            }
            func = function(state2, Item, item) {
              if (state2.opt.development_extensions.apply_citation_wrapper && state2.sys.wrapCitationEntry && !state2.tmp.just_looking && Item.system_id && state2.tmp.area === "citation") {
                var cite_entry = new CSL2.Token("group", CSL2.START);
                cite_entry.decorations = [["@cite", "entry"]];
                state2.output.startTag("cite_entry", cite_entry);
                state2.output.current.value().item_id = Item.system_id;
                if (item) {
                  state2.output.current.value().locator_txt = item.locator_txt;
                  state2.output.current.value().suffix_txt = item.suffix_txt;
                }
              }
            };
            this.execs.push(func);
          }
          if (this.tokentype === CSL2.START && !state.tmp.cite_affixes[state.build.area]) {
            func = function(state2, Item, item) {
              state2.tmp.done_vars = [];
              if (item && item["author-only"]) {
                state2.tmp.done_vars.push("locator");
              }
              if (state2.opt.suppressedJurisdictions[Item["country"]] && Item["country"] && ["treaty", "patent"].indexOf(Item.type) === -1) {
                state2.tmp.done_vars.push("country");
              }
              if (!state2.tmp.just_looking && state2.registry.registry[Item.id] && state2.registry.registry[Item.id].parallel) {
                state2.tmp.done_vars.push("first-reference-note-number");
              }
              if (!state2.tmp.just_looking && state2.tmp.abbrev_trimmer && Item.jurisdiction) {
                for (var field in state2.tmp.abbrev_trimmer.QUASHES[Item.jurisdiction]) {
                  state2.tmp.done_vars.push(field);
                }
              }
              state2.tmp.rendered_name = false;
            };
            this.execs.push(func);
            func = function(state2) {
              state2.tmp.sort_key_flag = false;
            };
            this.execs.push(func);
            func = function(state2) {
              state2.tmp.nameset_counter = 0;
            };
            this.execs.push(func);
            func = function(state2, Item) {
              var tok2 = new CSL2.Token();
              state2.output.openLevel(tok2);
            };
            this.execs.push(func);
            target.push(this);
            if (state.build.area === "citation") {
              prefix_token = new CSL2.Token("text", CSL2.SINGLETON);
              func = function(state2, Item, item) {
                if (item && item.prefix) {
                  var prefix = CSL2.checkPrefixSpaceAppend(state2, item.prefix);
                  if (!state2.tmp.just_looking) {
                    prefix = state2.output.checkNestedBrace.update(prefix);
                  }
                  var ignorePredecessor = CSL2.checkIgnorePredecessor(state2, prefix);
                  state2.output.append(prefix, this, false, ignorePredecessor);
                }
              };
              prefix_token.execs.push(func);
              target.push(prefix_token);
            }
          }
          var my_tok;
          if (this.locale_raw) {
            my_tok = new CSL2.Token("dummy", CSL2.START);
            my_tok.locale = this.locale_raw;
            my_tok.strings.delimiter = this.strings.delimiter;
            my_tok.strings.suffix = this.strings.suffix;
            if (!state.tmp.cite_affixes[state.build.area]) {
              state.tmp.cite_affixes[state.build.area] = {};
            }
          }
          if (this.tokentype === CSL2.START) {
            state.build.layout_flag = true;
            if (!this.locale_raw) {
              state[state.tmp.area].opt.topdecor = [this.decorations];
              state[state.tmp.area + "_sort"].opt.topdecor = [this.decorations];
              state[state.build.area].opt.layout_prefix = this.strings.prefix;
              state[state.build.area].opt.layout_suffix = this.strings.suffix;
              state[state.build.area].opt.layout_delimiter = this.strings.delimiter;
              state[state.build.area].opt.layout_decorations = this.decorations;
              if (state.tmp.cite_affixes[state.build.area]) {
                tok = new CSL2.Token("else", CSL2.START);
                CSL2.Node["else"].build.call(tok, state, target);
              }
            }
            if (this.locale_raw) {
              if (!state.build.layout_locale_flag) {
                var choose_tok = new CSL2.Token("choose", CSL2.START);
                CSL2.Node.choose.build.call(choose_tok, state, target);
                my_tok.name = "if";
                CSL2.Attributes["@locale-internal"].call(my_tok, state, this.locale_raw);
                CSL2.Node["if"].build.call(my_tok, state, target);
              } else {
                my_tok.name = "else-if";
                CSL2.Attributes["@locale-internal"].call(my_tok, state, this.locale_raw);
                CSL2.Node["else-if"].build.call(my_tok, state, target);
              }
              state.tmp.cite_affixes[state.build.area][my_tok.locale] = {};
              state.tmp.cite_affixes[state.build.area][my_tok.locale].delimiter = this.strings.delimiter;
              state.tmp.cite_affixes[state.build.area][my_tok.locale].suffix = this.strings.suffix;
            }
          }
          if (this.tokentype === CSL2.END) {
            if (this.locale_raw) {
              setSuffix();
              if (!state.build.layout_locale_flag) {
                my_tok.name = "if";
                my_tok.tokentype = CSL2.END;
                CSL2.Attributes["@locale-internal"].call(my_tok, state, this.locale_raw);
                CSL2.Node["if"].build.call(my_tok, state, target);
                state.build.layout_locale_flag = true;
              } else {
                my_tok.name = "else-if";
                my_tok.tokentype = CSL2.END;
                CSL2.Attributes["@locale-internal"].call(my_tok, state, this.locale_raw);
                CSL2.Node["else-if"].build.call(my_tok, state, target);
              }
            }
            if (!this.locale_raw) {
              setSuffix();
              if (state.tmp.cite_affixes[state.build.area]) {
                if (state.build.layout_locale_flag) {
                  tok = new CSL2.Token("else", CSL2.END);
                  CSL2.Node["else"].build.call(tok, state, target);
                  tok = new CSL2.Token("choose", CSL2.END);
                  CSL2.Node.choose.build.call(tok, state, target);
                }
              }
              state.build_layout_locale_flag = true;
              if (state.build.area === "citation") {
                suffix_token = new CSL2.Token("text", CSL2.SINGLETON);
                func = function(state2, Item, item) {
                  var sp;
                  if (item && item.suffix) {
                    var suffix = CSL2.checkSuffixSpacePrepend(state2, item.suffix);
                    if (!state2.tmp.just_looking) {
                      suffix = state2.output.checkNestedBrace.update(suffix);
                    }
                    state2.output.append(suffix, this);
                  }
                };
                suffix_token.execs.push(func);
                target.push(suffix_token);
              }
              func = function(state2) {
                state2.output.closeLevel();
              };
              this.execs.push(func);
              func = function(state2, Item) {
                if (state2.opt.development_extensions.apply_citation_wrapper && state2.sys.wrapCitationEntry && !state2.tmp.just_looking && Item.system_id && state2.tmp.area === "citation") {
                  state2.output.endTag();
                }
              };
              this.execs.push(func);
              target.push(this);
              state.build.layout_flag = false;
              state.build.layout_locale_flag = false;
            }
          }
        }
      };
      CSL2.Node.macro = {
        build: function() {
        }
      };
      CSL2.Node.alternative = {
        build: function(state, target) {
          if (this.tokentype === CSL2.START) {
            var choose_tok = new CSL2.Token("choose", CSL2.START);
            CSL2.Node["choose"].build.call(choose_tok, state, target);
            var if_tok = new CSL2.Token("if", CSL2.START);
            CSL2.Attributes["@alternative-node-internal"].call(if_tok, state);
            CSL2.Node["if"].build.call(if_tok, state, target);
            var func = function(state2, Item) {
              state2.tmp.oldItem = Item;
              state2.tmp.oldLang = state2.opt.lang;
              state2.tmp.abort_alternative = true;
              if (Item["language-name"] && Item["language-name-original"]) {
                var newItem = JSON.parse(JSON.stringify(Item));
                newItem.language = newItem["language-name"];
                var langspec = CSL2.localeResolve(newItem.language, state2.opt["default-locale"][0]);
                if (state2.opt.multi_layout) {
                  for (var i in state2.opt.multi_layout) {
                    var locale_list = state2.opt.multi_layout[i];
                    var gotlang = false;
                    for (var j in locale_list) {
                      var tryspec = locale_list[j];
                      if (langspec.best === tryspec.best || langspec.base === tryspec.base || langspec.bare === tryspec.bare) {
                        gotlang = locale_list[0].best;
                        break;
                      }
                    }
                    if (!gotlang) {
                      gotlang = state2.opt["default-locale"][0];
                    }
                    state2.opt.lang = gotlang;
                  }
                }
                for (var key in newItem) {
                  if (["id", "type", "language", "multi"].indexOf(key) === -1 && key.slice(0, 4) !== "alt-") {
                    if (newItem.multi && newItem.multi._keys[key]) {
                      var deleteme = true;
                      for (var lang in newItem.multi._keys[key]) {
                        if (langspec.bare === lang.replace(/^([a-zA-Z]+).*/, "$1")) {
                          deleteme = false;
                          break;
                        }
                      }
                      if (deleteme) {
                        delete newItem[key];
                      }
                    } else {
                      delete newItem[key];
                    }
                  }
                }
                for (var key in newItem) {
                  if (key.slice(0, 4) === "alt-") {
                    newItem[key.slice(4)] = newItem[key];
                    state2.tmp.abort_alternative = false;
                  } else {
                    if (newItem.multi && newItem.multi._keys) {
                      if (!newItem["alt-" + key] && newItem.multi._keys[key]) {
                        if (newItem.multi._keys[key][langspec.best]) {
                          newItem[key] = newItem.multi._keys[key][langspec.best];
                          state2.tmp.abort_alternative = false;
                        } else if (newItem.multi._keys[key][langspec.base]) {
                          newItem[key] = newItem.multi._keys[key][langspec.base];
                          state2.tmp.abort_alternative = false;
                        } else if (newItem.multi._keys[key][langspec.bare]) {
                          newItem[key] = newItem.multi._keys[key][langspec.bare];
                          state2.tmp.abort_alternative = false;
                        }
                      }
                    }
                  }
                }
              }
              state2.output.openLevel(this);
              state2.registry.refhash[Item.id] = newItem;
              state2.nameOutput = new CSL2.NameOutput(state2, newItem);
            };
            this.execs.push(func);
            target.push(this);
            var choose_tok = new CSL2.Token("choose", CSL2.START);
            CSL2.Node["choose"].build.call(choose_tok, state, target);
            var if_tok = new CSL2.Token("if", CSL2.START);
            CSL2.Attributes["@alternative-node-internal"].call(if_tok, state);
            var func = function(state2) {
              state2.tmp.abort_alternative = true;
            };
            if_tok.execs.push(func);
            CSL2.Node["if"].build.call(if_tok, state, target);
          } else if (this.tokentype === CSL2.END) {
            var if_tok = new CSL2.Token("if", CSL2.END);
            CSL2.Node["if"].build.call(if_tok, state, target);
            var choose_tok = new CSL2.Token("choose", CSL2.END);
            CSL2.Node["choose"].build.call(choose_tok, state, target);
            var func = function(state2, Item) {
              state2.output.closeLevel();
              state2.registry.refhash[Item.id] = state2.tmp.oldItem;
              state2.opt.lang = state2.tmp.oldLang;
              state2.nameOutput = new CSL2.NameOutput(state2, state2.tmp.oldItem);
              state2.tmp.abort_alternative = false;
            };
            this.execs.push(func);
            target.push(this);
            var if_tok = new CSL2.Token("if", CSL2.END);
            CSL2.Node["if"].build.call(if_tok, state, target);
            var choose_tok = new CSL2.Token("choose", CSL2.END);
            CSL2.Node["choose"].build.call(choose_tok, state, target);
          }
        }
      };
      CSL2.Node["alternative-text"] = {
        build: function(state, target) {
          if (this.tokentype === CSL2.SINGLETON) {
            var func = function(state2, Item) {
              var Item = state2.refetchItem(Item.id);
              CSL2.getCite.call(state2, Item);
            };
            this.execs.push(func);
          }
          target.push(this);
        }
      };
      CSL2.NameOutput = function(state, Item, item) {
        this.debug = false;
        this.state = state;
        if (this.debug) {
          this.state.sys.print("(1)");
        }
        this.Item = Item;
        this.item = item;
        this.nameset_base = 0;
        this.etal_spec = {};
        this._first_creator_variable = false;
        this._please_chop = false;
      };
      CSL2.NameOutput.prototype.init = function(names) {
        this.requireMatch = names.requireMatch;
        if (this.state.tmp.term_predecessor) {
          this.state.tmp.subsequent_author_substitute_ok = false;
        }
        if (this.nameset_offset) {
          this.nameset_base = this.nameset_base + this.nameset_offset;
        }
        this.nameset_offset = 0;
        this.names = names;
        this.variables = names.variables;
        this.state.tmp.value = [];
        this.state.tmp.rendered_name = [];
        this.state.tmp.label_blob = false;
        this.state.tmp.etal_node = false;
        this.state.tmp.etal_term = false;
        for (var i = 0, ilen = this.variables.length; i < ilen; i += 1) {
          if (this.Item[this.variables[i]] && this.Item[this.variables[i]].length) {
            this.state.tmp.value = this.state.tmp.value.concat(this.Item[this.variables[i]]);
          }
        }
        this["et-al"] = void 0;
        this["with"] = void 0;
        this.name = void 0;
        this.institutionpart = {};
        this.state.tmp.group_context.tip.variable_attempt = true;
        this.labelVariable = this.variables[0];
        if (!this.state.tmp.value.length) {
          return;
        }
        var checkCommonTerm = this.checkCommonAuthor(this.requireMatch);
        if (checkCommonTerm) {
          this.state.tmp.can_substitute.pop();
          this.state.tmp.can_substitute.push(true);
          for (var i in this.variables) {
            var idx = this.state.tmp.done_vars.indexOf(this.variables[i]);
            if (idx > -1) {
              this.state.tmp.done_vars = this.state.tmp.done_vars.slice(0, idx).concat(this.state.tmp.done_vars.slice(i + 1));
            }
          }
          this.state.tmp.common_term_match_fail = true;
          this.variables = [];
        }
      };
      CSL2.NameOutput.prototype.reinit = function(names, labelVariable) {
        this.requireMatch = names.requireMatch;
        this.labelVariable = labelVariable;
        if (this.state.tmp.can_substitute.value()) {
          this.nameset_offset = 0;
          this.variables = names.variables;
          var oldval = this.state.tmp.value.slice();
          this.state.tmp.value = [];
          for (var i = 0, ilen = this.variables.length; i < ilen; i += 1) {
            if (this.Item[this.variables[i]] && this.Item[this.variables[i]].length) {
              this.state.tmp.value = this.state.tmp.value.concat(this.Item[this.variables[i]]);
            }
          }
          if (this.state.tmp.value.length) {
            this.state.tmp.can_substitute.replace(false, CSL2.LITERAL);
          }
          this.state.tmp.value = oldval;
        }
        var checkCommonTerm = this.checkCommonAuthor(this.requireMatch);
        if (checkCommonTerm) {
          this.state.tmp.can_substitute.pop();
          this.state.tmp.can_substitute.push(true);
          for (var i in this.variables) {
            var idx = this.state.tmp.done_vars.indexOf(this.variables[i]);
            if (idx > -1) {
              this.state.tmp.done_vars = this.state.tmp.done_vars.slice(0, idx).concat(this.state.tmp.done_vars.slice(i + 1));
            }
          }
          this.variables = [];
        }
      };
      CSL2.NameOutput.prototype.outputNames = function() {
        var i, ilen;
        var variables = this.variables;
        if (this.institution.and) {
          if (!this.institution.and.single.blobs || !this.institution.and.single.blobs.length) {
            this.institution.and.single.blobs = this.name.and.single.blobs;
          }
          if (!this.institution.and.multiple.blobs || !this.institution.and.multiple.blobs.length) {
            this.institution.and.multiple.blobs = this.name.and.multiple.blobs;
          }
        }
        this.variable_offset = {};
        if (this.family) {
          this.family_decor = CSL2.Util.cloneToken(this.family);
          this.family_decor.strings.prefix = "";
          this.family_decor.strings.suffix = "";
          for (i = 0, ilen = this.family.execs.length; i < ilen; i += 1) {
            this.family.execs[i].call(this.family_decor, this.state, this.Item);
          }
        } else {
          this.family_decor = false;
        }
        if (this.given) {
          this.given_decor = CSL2.Util.cloneToken(this.given);
          this.given_decor.strings.prefix = "";
          this.given_decor.strings.suffix = "";
          for (i = 0, ilen = this.given.execs.length; i < ilen; i += 1) {
            this.given.execs[i].call(this.given_decor, this.state, this.Item);
          }
        } else {
          this.given_decor = false;
        }
        if (this.debug) {
          this.state.sys.print("(2)");
        }
        this.getEtAlConfig();
        if (this.debug) {
          this.state.sys.print("(3)");
        }
        this.divideAndTransliterateNames();
        if (this.debug) {
          this.state.sys.print("(4)");
        }
        this.truncatePersonalNameLists();
        if (this.debug) {
          this.state.sys.print("(5)");
        }
        if (this.debug) {
          this.state.sys.print("(6)");
        }
        this.disambigNames();
        this.constrainNames();
        if (this.debug) {
          this.state.sys.print("(7)");
        }
        if (this.name.strings.form === "count") {
          if (this.state.tmp.extension || this.names_count != 0) {
            this.state.output.append(this.names_count, "empty");
            this.state.tmp.group_context.tip.variable_success = true;
          }
          return;
        }
        if (this.debug) {
          this.state.sys.print("(8)");
        }
        this.setEtAlParameters();
        if (this.debug) {
          this.state.sys.print("(9)");
        }
        this.setCommonTerm(this.requireMatch);
        if (this.debug) {
          this.state.sys.print("(10)");
        }
        this.renderAllNames();
        if (this.debug) {
          this.state.sys.print("(11)");
        }
        var blob_list = [];
        for (i = 0, ilen = variables.length; i < ilen; i += 1) {
          var v = variables[i];
          var institution_sets = [];
          var institutions = false;
          var varblob = null;
          if (!this.state.opt.development_extensions.spoof_institutional_affiliations) {
            varblob = this._join([this.freeters[v]], "");
          } else {
            if (this.debug) {
              this.state.sys.print("(11a)");
            }
            for (var j = 0, jlen = this.institutions[v].length; j < jlen; j += 1) {
              institution_sets.push(this.joinPersonsAndInstitutions([this.persons[v][j], this.institutions[v][j]]));
            }
            if (this.debug) {
              this.state.sys.print("(11b)");
            }
            if (this.institutions[v].length) {
              var pos = this.nameset_base + this.variable_offset[v];
              if (this.freeters[v].length) {
                pos += 1;
              }
              institutions = this.joinInstitutionSets(institution_sets, pos);
            }
            if (this.debug) {
              this.state.sys.print("(11c)");
            }
            var varblob = this.joinFreetersAndInstitutionSets([this.freeters[v], institutions]);
            if (this.debug) {
              this.state.sys.print("(11d)");
            }
          }
          if (varblob) {
            if (!this.state.tmp.extension) {
              varblob = this._applyLabels(varblob, v);
            }
            blob_list.push(varblob);
          }
          if (this.debug) {
            this.state.sys.print("(11e)");
          }
          if (this.common_term) {
            break;
          }
        }
        if (this.debug) {
          this.state.sys.print("(12)");
        }
        this.state.output.openLevel("empty");
        this.state.output.current.value().strings.delimiter = this.state.inheritOpt(this.names, "delimiter", "names-delimiter");
        if (this.debug) {
          this.state.sys.print("(13)");
        }
        for (i = 0, ilen = blob_list.length; i < ilen; i += 1) {
          this.state.output.append(blob_list[i], "literal", true);
        }
        if (!this.state.tmp.just_looking && blob_list.length > 0) {
          this.state.tmp.probably_rendered_something = true;
        }
        if (this.debug) {
          this.state.sys.print("(14)");
        }
        this.state.output.closeLevel("empty");
        if (this.debug) {
          this.state.sys.print("(15)");
        }
        var blob = this.state.output.pop();
        this.state.tmp.name_node.top = blob;
        if (this.debug) {
          this.state.sys.print("(16)");
        }
        var namesToken = CSL2.Util.cloneToken(this.names);
        if (this.state.tmp.group_context.tip.condition) {
          CSL2.UPDATE_GROUP_CONTEXT_CONDITION(this.state, this.names.strings.prefix, null, this.names);
        }
        this.state.output.append(blob, namesToken);
        if (this.state.tmp.term_predecessor_name) {
          this.state.tmp.term_predecessor = true;
        }
        if (this.debug) {
          this.state.sys.print("(17)");
        }
        if (this.debug) {
          this.state.sys.print("(18)");
        }
        if (variables[0] !== "authority") {
          var name_node_string = [];
          var nameobjs = this.Item[variables[0]];
          if (nameobjs) {
            for (var i = 0, ilen = nameobjs.length; i < ilen; i += 1) {
              var substring = CSL2.Util.Names.getRawName(nameobjs[i]);
              if (substring) {
                name_node_string.push(substring);
              }
            }
          }
          name_node_string = name_node_string.join(", ");
          if (name_node_string) {
            this.state.tmp.name_node.string = name_node_string;
          }
        }
        if (this.state.tmp.name_node.string && !this.state.tmp.first_name_string) {
          this.state.tmp.first_name_string = this.state.tmp.name_node.string;
        }
        if ("classic" === this.Item.type) {
          if (this.state.tmp.first_name_string) {
            var author_title = [];
            author_title.push(this.state.tmp.first_name_string);
            if (this.Item.title) {
              author_title.push(this.Item.title);
            }
            author_title = author_title.join(", ");
            if (author_title && this.state.sys.getAbbreviation) {
              if (this.state.sys.normalizeAbbrevsKey) {
                author_title = this.state.sys.normalizeAbbrevsKey("classic", author_title);
              }
              this.state.transform.loadAbbreviation("default", "classic", author_title, this.Item.language);
              if (this.state.transform.abbrevs["default"].classic[author_title]) {
                this.state.tmp.done_vars.push("title");
                this.state.output.append(this.state.transform.abbrevs["default"].classic[author_title], "empty", true);
                blob = this.state.output.pop();
                this.state.tmp.name_node.top.blobs.pop();
                this.state.tmp.name_node.top.blobs.push(blob);
              }
            }
          }
        }
        this._collapseAuthor();
        this.variables = [];
        this.state.tmp.authority_stop_last = 0;
        if (this.debug) {
          this.state.sys.print("(19)");
        }
      };
      CSL2.NameOutput.prototype._applyLabels = function(blob, v) {
        var txt;
        if (!this.label || !this.label[this.labelVariable]) {
          return blob;
        }
        var plural = 0;
        var num = this.freeters_count[v] + this.institutions_count[v];
        if (num > 1) {
          plural = 1;
        } else {
          for (var i = 0, ilen = this.persons[v].length; i < ilen; i += 1) {
            num += this.persons_count[v][i];
          }
          if (num > 1) {
            plural = 1;
          }
        }
        if (this.label[this.labelVariable].before) {
          if ("number" === typeof this.label[this.labelVariable].before.strings.plural) {
            plural = this.label[this.labelVariable].before.strings.plural;
          }
          txt = this._buildLabel(v, plural, "before", this.labelVariable);
          this.state.output.openLevel("empty");
          this.state.output.append(txt, this.label[this.labelVariable].before, true);
          this.state.output.append(blob, "literal", true);
          this.state.output.closeLevel("empty");
          blob = this.state.output.pop();
        } else if (this.label[this.labelVariable].after) {
          if ("number" === typeof this.label[this.labelVariable].after.strings.plural) {
            plural = this.label[this.labelVariable].after.strings.plural;
          }
          txt = this._buildLabel(v, plural, "after", this.labelVariable);
          this.state.output.openLevel("empty");
          this.state.output.append(blob, "literal", true);
          this.state.output.append(txt, this.label[this.labelVariable].after, true);
          this.state.tmp.label_blob = this.state.output.pop();
          this.state.output.append(this.state.tmp.label_blob, "literal", true);
          this.state.output.closeLevel("empty");
          blob = this.state.output.pop();
        }
        return blob;
      };
      CSL2.NameOutput.prototype._buildLabel = function(term, plural, position, v) {
        if (this.common_term) {
          term = this.common_term;
        }
        var ret = false;
        var node = this.label[v][position];
        if (node) {
          ret = CSL2.castLabel(this.state, node, term, plural, CSL2.TOLERANT);
        }
        return ret;
      };
      CSL2.NameOutput.prototype._collapseAuthor = function() {
        var myqueue, mystr, oldchars;
        if (this.state.tmp.name_node.top.blobs.length === 0) {
          return;
        }
        if (this.nameset_base === 0 && this.Item[this.variables[0]] && !this._first_creator_variable) {
          this._first_creator_variable = this.variables[0];
        }
        if (this.state[this.state.tmp.area].opt.collapse && this.state[this.state.tmp.area].opt.collapse.length || this.state[this.state.tmp.area].opt.cite_group_delimiter && this.state[this.state.tmp.area].opt.cite_group_delimiter.length) {
          if (this.state.tmp.authorstring_request) {
            mystr = "";
            myqueue = this.state.tmp.name_node.top.blobs.slice(-1)[0].blobs;
            oldchars = this.state.tmp.offset_characters;
            if (myqueue) {
              mystr = this.state.output.string(this.state, myqueue, false);
            }
            this.state.tmp.offset_characters = oldchars;
            this.state.registry.authorstrings[this.Item.id] = mystr;
          } else if (!this.state.tmp.just_looking && !this.state.tmp.suppress_decorations && (this.state[this.state.tmp.area].opt.collapse && this.state[this.state.tmp.area].opt.collapse.length || this.state[this.state.tmp.area].opt.cite_group_delimiter && this.state[this.state.tmp.area].opt.cite_group_delimiter)) {
            mystr = "";
            myqueue = this.state.tmp.name_node.top.blobs.slice(-1)[0].blobs;
            oldchars = this.state.tmp.offset_characters;
            if (myqueue) {
              mystr = this.state.output.string(this.state, myqueue, false);
            }
            if (mystr === this.state.tmp.last_primary_names_string) {
              if (this.item["suppress-author"] || this.state[this.state.tmp.area].opt.collapse && this.state[this.state.tmp.area].opt.collapse.length) {
                this.state.tmp.name_node.top.blobs.pop();
                this.state.tmp.name_node.children = [];
                this.state.tmp.offset_characters = oldchars;
              }
              if (this.state[this.state.tmp.area].opt.cite_group_delimiter && this.state[this.state.tmp.area].opt.cite_group_delimiter) {
                this.state.tmp.use_cite_group_delimiter = true;
              }
            } else {
              this.state.tmp.last_primary_names_string = mystr;
              if (this.variables.indexOf(this._first_creator_variable) > -1 && this.item && this.item["suppress-author"] && this.Item.type !== "legal_case") {
                this.state.tmp.name_node.top.blobs.pop();
                this.state.tmp.name_node.children = [];
                this.state.tmp.offset_characters = oldchars;
                this.state.tmp.term_predecessor = false;
              }
              this.state.tmp.have_collapsed = false;
              if (this.state[this.state.tmp.area].opt.cite_group_delimiter && this.state[this.state.tmp.area].opt.cite_group_delimiter) {
                this.state.tmp.use_cite_group_delimiter = false;
              }
            }
          }
        }
      };
      CSL2.NameOutput.prototype.isPerson = function(value) {
        if (value.literal || !value.given && value.family && value.isInstitution) {
          return false;
        } else {
          return true;
        }
      };
      CSL2.NameOutput.prototype.truncatePersonalNameLists = function() {
        var v, i, ilen, j, jlen, chopvar, values;
        this.freeters_count = {};
        this.persons_count = {};
        this.institutions_count = {};
        for (v in this.freeters) {
          if (this.freeters.hasOwnProperty(v)) {
            this.freeters_count[v] = this.freeters[v].length;
            this.freeters[v] = this._truncateNameList(this.freeters, v);
          }
        }
        for (v in this.persons) {
          if (this.persons.hasOwnProperty(v)) {
            this.institutions_count[v] = this.institutions[v].length;
            this._truncateNameList(this.institutions, v);
            this.persons[v] = this.persons[v].slice(0, this.institutions[v].length);
            this.persons_count[v] = [];
            for (j = 0, jlen = this.persons[v].length; j < jlen; j += 1) {
              this.persons_count[v][j] = this.persons[v][j].length;
              this.persons[v][j] = this._truncateNameList(this.persons, v, j);
            }
          }
        }
        if (this.state.opt.development_extensions.etal_min_etal_usefirst_hack && this.etal_min === 1 && this.etal_use_first === 1 && !(this.state.tmp.extension || this.state.tmp.just_looking)) {
          chopvar = v;
        } else {
          chopvar = false;
        }
        if (chopvar || this._please_chop) {
          for (i = 0, ilen = this.variables.length; i < ilen; i += 1) {
            v = this.variables[i];
            if (this.freeters[v].length) {
              if (this._please_chop === v) {
                this.freeters[v] = this.freeters[v].slice(1);
                this.freeters_count[v] += -1;
                this._please_chop = false;
              } else if (chopvar && !this._please_chop) {
                this.freeters[v] = this.freeters[v].slice(0, 1);
                this.freeters_count[v] = 1;
                this.institutions[v] = [];
                this.persons[v] = [];
                this._please_chop = chopvar;
              }
            }
            for (var j = 0, jlen = this.persons[v].length; j < jlen; j++) {
              if (this.persons[v][j].length) {
                if (this._please_chop === v) {
                  this.persons[v][j] = this.persons[v][j].slice(1);
                  this.persons_count[v][j] += -1;
                  this._please_chop = false;
                  break;
                } else if (chopvar && !this._please_chop) {
                  this.freeters[v] = this.persons[v][j].slice(0, 1);
                  this.freeters_count[v] = 1;
                  this.institutions[v] = [];
                  this.persons[v] = [];
                  values = [];
                  this._please_chop = chopvar;
                  break;
                }
              }
            }
            if (this.institutions[v].length) {
              if (this._please_chop === v) {
                this.institutions[v] = this.institutions[v].slice(1);
                this.institutions_count[v] += -1;
                this._please_chop = false;
              } else if (chopvar && !this._please_chop) {
                this.institutions[v] = this.institutions[v].slice(0, 1);
                this.institutions_count[v] = 1;
                values = [];
                this._please_chop = chopvar;
              }
            }
          }
        }
        for (i = 0, ilen = this.variables.length; i < ilen; i += 1) {
          if (this.institutions[v].length) {
            this.nameset_offset += 1;
          }
          for (var j = 0, jlen = this.persons[v].length; j < jlen; j++) {
            if (this.persons[v][j].length) {
              this.nameset_offset += 1;
            }
          }
        }
      };
      CSL2.NameOutput.prototype._truncateNameList = function(container, variable, index) {
        var lst;
        if ("undefined" === typeof index) {
          lst = container[variable];
        } else {
          lst = container[variable][index];
        }
        if (this.state[this.state[this.state.tmp.area].root].opt.max_number_of_names && lst.length > 50 && lst.length > this.state[this.state[this.state.tmp.area].root].opt.max_number_of_names + 2) {
          var limit = this.state[this.state[this.state.tmp.area].root].opt.max_number_of_names;
          lst = lst.slice(0, limit + 1).concat(lst.slice(-1));
        }
        return lst;
      };
      CSL2.NameOutput.prototype.divideAndTransliterateNames = function() {
        var i, ilen, j, jlen;
        var Item = this.Item;
        var variables = this.variables;
        this.varnames = variables.slice();
        this.freeters = {};
        this.persons = {};
        this.institutions = {};
        for (i = 0, ilen = variables.length; i < ilen; i += 1) {
          var v = variables[i];
          this.variable_offset[v] = this.nameset_offset;
          var values = this._normalizeVariableValue(Item, v);
          if (this.name.strings["suppress-min"] && values.length >= this.name.strings["suppress-min"]) {
            values = [];
          }
          if (this.name.strings["suppress-max"] && values.length <= this.name.strings["suppress-max"]) {
            values = [];
          }
          this._getFreeters(v, values);
          this._getPersonsAndInstitutions(v, values);
          if (this.state.opt.development_extensions.spoof_institutional_affiliations) {
            if (this.name.strings["suppress-min"] === 0) {
              this.freeters[v] = [];
              for (j = 0, jlen = this.persons[v].length; j < jlen; j += 1) {
                this.persons[v][j] = [];
              }
            } else if (this.institution.strings["suppress-min"] === 0) {
              this.institutions[v] = [];
              this.freeters[v] = this.freeters[v].concat(this.persons[v]);
              for (j = 0, jlen = this.persons[v].length; j < jlen; j += 1) {
                for (var k = 0, klen = this.persons[v][j].length; k < klen; k += 1) {
                  this.freeters[v].push(this.persons[v][j][k]);
                }
              }
              this.persons[v] = [];
            }
          }
        }
      };
      CSL2.NameOutput.prototype._normalizeVariableValue = function(Item, variable) {
        var names;
        if ("string" === typeof Item[variable] || "number" === typeof Item[variable]) {
          CSL2.debug('name variable "' + variable + '" is string or number, not array. Attempting to fix.');
          names = [{ literal: Item[variable] + "" }];
        } else if (!Item[variable]) {
          names = [];
        } else if ("number" !== typeof Item[variable].length) {
          CSL2.debug('name variable "' + variable + '" is object, not array. Attempting to fix.');
          Item[variable] = [Item[variable]];
          names = Item[variable].slice();
        } else {
          names = Item[variable].slice();
        }
        return names;
      };
      CSL2.NameOutput.prototype._getFreeters = function(v, values) {
        this.freeters[v] = [];
        if (this.state.opt.development_extensions.spoof_institutional_affiliations) {
          for (var i = values.length - 1; i > -1; i--) {
            if (this.isPerson(values[i])) {
              var value = this._checkNickname(values.pop());
              if (value) {
                this.freeters[v].push(value);
              }
            } else {
              break;
            }
          }
        } else {
          for (var i = values.length - 1; i > -1; i--) {
            var value = values.pop();
            if (this.isPerson(value)) {
              var value = this._checkNickname(value);
            }
            this.freeters[v].push(value);
          }
        }
        this.freeters[v].reverse();
        if (this.freeters[v].length) {
          this.nameset_offset += 1;
        }
      };
      CSL2.NameOutput.prototype._getPersonsAndInstitutions = function(v, values) {
        this.persons[v] = [];
        this.institutions[v] = [];
        if (!this.state.opt.development_extensions.spoof_institutional_affiliations) {
          return;
        }
        var persons = [];
        var has_affiliates = false;
        var first = true;
        for (var i = values.length - 1; i > -1; i += -1) {
          if (this.isPerson(values[i])) {
            var value = this._checkNickname(values[i]);
            if (value) {
              persons.push(value);
            }
          } else {
            has_affiliates = true;
            this.institutions[v].push(values[i]);
            if (!first) {
              persons.reverse();
              this.persons[v].push(persons);
              persons = [];
            }
            first = false;
          }
        }
        if (has_affiliates) {
          persons.reverse();
          this.persons[v].push(persons);
          this.persons[v].reverse();
          this.institutions[v].reverse();
        }
      };
      CSL2.NameOutput.prototype._clearValues = function(values) {
        for (var i = values.length - 1; i > -1; i += -1) {
          values.pop();
        }
      };
      CSL2.NameOutput.prototype._checkNickname = function(name) {
        if (["interview", "personal_communication"].indexOf(this.Item.type) > -1) {
          var author = "";
          author = CSL2.Util.Names.getRawName(name);
          if (author && this.state.sys.getAbbreviation && !(this.item && this.item["suppress-author"])) {
            var normalizedKey = author;
            if (this.state.sys.normalizeAbbrevsKey) {
              normalizedKey = this.state.sys.normalizeAbbrevsKey("author", author);
            }
            this.state.transform.loadAbbreviation("default", "nickname", normalizedKey, this.Item.language);
            var myLocalName = this.state.transform.abbrevs["default"].nickname[normalizedKey];
            if (myLocalName) {
              if (myLocalName === "!here>>>") {
                name = false;
              } else {
                name = { family: myLocalName, given: "" };
              }
            }
          }
        }
        return name;
      };
      CSL2.NameOutput.prototype._purgeEmptyBlobs = function(blobs) {
        for (var i = blobs.length - 1; i > -1; i += -1) {
          if (!blobs[i] || blobs[i].length === 0 || !blobs[i].blobs.length) {
            blobs = blobs.slice(0, i).concat(blobs.slice(i + 1));
          }
        }
        return blobs;
      };
      CSL2.NameOutput.prototype.joinPersons = function(blobs, pos, j, tokenname) {
        var ret;
        blobs = this._purgeEmptyBlobs(blobs);
        if (!tokenname) {
          tokenname = "name";
        }
        if ("undefined" === typeof j) {
          if (this.etal_spec[pos].freeters === 1) {
            ret = this._joinEtAl(blobs);
          } else if (this.etal_spec[pos].freeters === 2) {
            ret = this._joinEllipsis(blobs);
          } else if (!this.state.tmp.sort_key_flag) {
            ret = this._joinAnd(blobs);
          } else {
            ret = this._join(blobs, this.state.inheritOpt(this.name, "delimiter", "name-delimiter", ", "));
          }
        } else {
          if (this.etal_spec[pos].persons[j] === 1) {
            ret = this._joinEtAl(blobs);
          } else if (this.etal_spec[pos].persons[j] === 2) {
            ret = this._joinEllipsis(blobs);
          } else if (!this.state.tmp.sort_key_flag) {
            ret = this._joinAnd(blobs);
          } else {
            ret = this._join(blobs, this.state.inheritOpt(this.name, "delimiter", "name-delimiter", ", "));
          }
        }
        return ret;
      };
      CSL2.NameOutput.prototype.joinInstitutionSets = function(blobs, pos) {
        var ret;
        blobs = this._purgeEmptyBlobs(blobs);
        if (this.etal_spec[pos].institutions === 1) {
          ret = this._joinEtAl(blobs, "institution");
        } else if (this.etal_spec[pos].institutions === 2) {
          ret = this._joinEllipsis(blobs, "institution");
        } else {
          ret = this._joinAnd(blobs);
        }
        return ret;
      };
      CSL2.NameOutput.prototype.joinPersonsAndInstitutions = function(blobs) {
        blobs = this._purgeEmptyBlobs(blobs);
        var ret = this._join(blobs, this.state.tmp.name_delimiter);
        ret.isInstitution = true;
        return ret;
      };
      CSL2.NameOutput.prototype.joinFreetersAndInstitutionSets = function(blobs) {
        blobs = this._purgeEmptyBlobs(blobs);
        var ret = this._join(blobs, "[never here]", this["with"].single, this["with"].multiple);
        return ret;
      };
      CSL2.NameOutput.prototype._getAfterInvertedName = function(blobs, delimiter, finalJoin) {
        if (finalJoin && blobs.length > 1) {
          if (this.state.inheritOpt(this.name, "delimiter-precedes-last") === "after-inverted-name") {
            var prevBlob = blobs[blobs.length - 2];
            if (prevBlob.blobs.length > 0 && prevBlob.blobs[0].isInverted) {
              finalJoin.strings.prefix = delimiter;
            }
          }
        }
        return finalJoin;
      };
      CSL2.NameOutput.prototype._getAndJoin = function(blobs, delimiter) {
        var finalJoin = false;
        if (blobs.length > 1) {
          var singleOrMultiple = "single";
          if (blobs.length > 2) {
            singleOrMultiple = "multiple";
          }
          if (blobs[blobs.length - 1].isInstitution) {
            finalJoin = this.institution.and[singleOrMultiple];
          } else {
            finalJoin = this.name.and[singleOrMultiple];
          }
          finalJoin = JSON.parse(JSON.stringify(finalJoin));
          finalJoin = this._getAfterInvertedName(blobs, delimiter, finalJoin);
        }
        return finalJoin;
      };
      CSL2.NameOutput.prototype._joinEtAl = function(blobs) {
        var delimiter = this.state.inheritOpt(this.name, "delimiter", "name-delimiter", ", ");
        var blob = this._join(blobs, delimiter);
        this.state.output.openLevel(this._getToken("name"));
        this.state.output.current.value().strings.delimiter = "";
        this.state.output.append(blob, "literal", true);
        if (blobs.length > 1) {
          this.state.output.append(this["et-al"].multiple, "literal", true);
        } else if (blobs.length === 1) {
          this.state.output.append(this["et-al"].single, "literal", true);
        }
        this.state.output.closeLevel();
        return this.state.output.pop();
      };
      CSL2.NameOutput.prototype._joinEllipsis = function(blobs) {
        var delimiter = this.state.inheritOpt(this.name, "delimiter", "name-delimiter", ", ");
        var finalJoin = false;
        if (blobs.length > 1) {
          var singleOrMultiple = "single";
          if (blobs.length > 2) {
            singleOrMultiple = "multiple";
          }
          finalJoin = JSON.parse(JSON.stringify(this.name.ellipsis[singleOrMultiple]));
          finalJoin = this._getAfterInvertedName(blobs, delimiter, finalJoin);
        }
        return this._join(blobs, delimiter, finalJoin);
      };
      CSL2.NameOutput.prototype._joinAnd = function(blobs) {
        var delimiter = this.state.inheritOpt(this.name, "delimiter", "name-delimiter", ", ");
        var finalJoin = this._getAndJoin(blobs, delimiter);
        return this._join(blobs, delimiter, finalJoin);
      };
      CSL2.NameOutput.prototype._join = function(blobs, delimiter, finalJoin) {
        var i, ilen;
        if (!blobs) {
          return false;
        }
        blobs = this._purgeEmptyBlobs(blobs);
        if (!blobs.length) {
          return false;
        }
        if (blobs.length > 1) {
          if (blobs.length === 2) {
            if (!finalJoin) {
              blobs[0].strings.suffix += delimiter;
            } else {
              blobs = [blobs[0], finalJoin, blobs[1]];
            }
          } else {
            var offset;
            if (finalJoin) {
              offset = 1;
            } else {
              offset = 0;
            }
            var blob = blobs.pop();
            for (var i = 0, ilen = blobs.length - offset; i < ilen; i++) {
              blobs[i].strings.suffix += delimiter;
            }
            blobs.push(finalJoin);
            blobs.push(blob);
          }
        }
        this.state.output.openLevel();
        for (i = 0, ilen = blobs.length; i < ilen; i += 1) {
          this.state.output.append(blobs[i], false, true);
        }
        this.state.output.closeLevel();
        return this.state.output.pop();
      };
      CSL2.NameOutput.prototype._getToken = function(tokenname) {
        var token = this[tokenname];
        if (tokenname === "institution") {
          var newtoken = new CSL2.Token();
          return newtoken;
        }
        return token;
      };
      CSL2.NameOutput.prototype.checkCommonAuthor = function(requireMatch) {
        if (!requireMatch) {
          return false;
        }
        var common_term = false;
        if (this.variables.length === 2) {
          var variables = this.variables;
          var varnames = variables.slice();
          varnames.sort();
          common_term = varnames.join("");
        }
        if (!common_term) {
          return false;
        }
        var has_term = false;
        if (this.state.locale[this.state.opt.lang].terms[common_term]) {
          has_term = true;
        }
        if (!has_term) {
          this.state.tmp.done_vars.push(this.variables[0]);
          this.state.tmp.done_vars.push(this.variables[1]);
          return false;
        }
        var firstSet = this.Item[this.variables[0]];
        var secondSet = this.Item[this.variables[1]];
        var perfectMatch = this._compareNamesets(firstSet, secondSet);
        if (perfectMatch === true) {
          this.state.tmp.done_vars.push(this.variables[0]);
          this.state.tmp.done_vars.push(this.variables[1]);
        }
        return !perfectMatch;
      };
      CSL2.NameOutput.prototype.setCommonTerm = function() {
        var variables = this.variables;
        var varnames = variables.slice();
        varnames.sort();
        this.common_term = varnames.join("");
        if (!this.common_term) {
          return;
        }
        var has_term = false;
        if (this.label && this.label[this.variables[0]]) {
          if (this.label[this.variables[0]].before) {
            has_term = this.state.getTerm(this.common_term, this.label[this.variables[0]].before.strings.form, 0);
          } else if (this.label[this.variables[0]].after) {
            has_term = this.state.getTerm(this.common_term, this.label[this.variables[0]].after.strings.form, 0);
          }
        }
        if (!this.state.locale[this.state.opt.lang].terms[this.common_term] || !has_term || this.variables.length < 2) {
          this.common_term = false;
          return;
        }
        var freeters_offset = 0;
        for (var i = 0, ilen = this.variables.length - 1; i < ilen; i += 1) {
          var v = this.variables[i];
          var vv = this.variables[i + 1];
          if (this.freeters[v].length || this.freeters[vv].length) {
            if (this.etal_spec[v].freeters !== this.etal_spec[vv].freeters || !this._compareNamesets(this.freeters[v], this.freeters[vv])) {
              this.common_term = false;
              return;
            }
            freeters_offset += 1;
          }
          if (this.persons[v].length !== this.persons[vv].length) {
            this.common_term = false;
            return;
          }
          for (var j = 0, jlen = this.persons[v].length; j < jlen; j += 1) {
            if (this.etal_spec[v].persons[j] !== this.etal_spec[vv].persons[j] || !this._compareNamesets(this.persons[v][j], this.persons[vv][j])) {
              this.common_term = false;
              return;
            }
          }
        }
      };
      CSL2.NameOutput.prototype._compareNamesets = function(base_nameset, nameset) {
        if (!base_nameset || !nameset || base_nameset.length !== nameset.length) {
          return false;
        }
        for (var i = 0, ilen = nameset.length; i < ilen; i += 1) {
          for (var j = 0, jlen = CSL2.NAME_PARTS.length; j < jlen; j += 1) {
            var part = CSL2.NAME_PARTS[j];
            if (!base_nameset[i] || base_nameset[i][part] != nameset[i][part]) {
              return false;
            }
          }
        }
        return true;
      };
      CSL2.NameOutput.prototype.constrainNames = function() {
        this.names_count = 0;
        var pos;
        for (var i = 0, ilen = this.variables.length; i < ilen; i += 1) {
          var v = this.variables[i];
          pos = this.nameset_base + i;
          if (this.freeters[v].length) {
            this.state.tmp.names_max.push(this.freeters[v].length, "literal");
            this._imposeNameConstraints(this.freeters, this.freeters_count, v, pos);
            this.names_count += this.freeters[v].length;
          }
          if (this.institutions[v].length) {
            this.state.tmp.names_max.push(this.institutions[v].length, "literal");
            this._imposeNameConstraints(this.institutions, this.institutions_count, v, pos);
            this.persons[v] = this.persons[v].slice(0, this.institutions[v].length);
            this.names_count += this.institutions[v].length;
          }
          for (var j = 0, jlen = this.persons[v].length; j < jlen; j += 1) {
            if (this.persons[v][j].length) {
              this.state.tmp.names_max.push(this.persons[v][j].length, "literal");
              this._imposeNameConstraints(this.persons[v], this.persons_count[v], j, pos);
              this.names_count += this.persons[v][j].length;
            }
          }
        }
      };
      CSL2.NameOutput.prototype._imposeNameConstraints = function(lst, count, key, pos) {
        var display_names = lst[key];
        var discretionary_names_length = this.state.tmp["et-al-min"];
        if (this.state.tmp.suppress_decorations) {
          if (this.state.tmp.disambig_request && this.state.tmp.disambig_request.names[pos]) {
            discretionary_names_length = this.state.tmp.disambig_request.names[pos];
          } else if (count[key] >= this.etal_min) {
            discretionary_names_length = this.etal_use_first;
          }
        } else {
          if (this.state.tmp.disambig_request && this.state.tmp.disambig_request.names[pos] > this.etal_use_first) {
            if (count[key] < this.etal_min) {
              discretionary_names_length = count[key];
            } else {
              discretionary_names_length = this.state.tmp.disambig_request.names[pos];
            }
          } else if (count[key] >= this.etal_min) {
            discretionary_names_length = this.etal_use_first;
          }
          if (this.etal_use_last && discretionary_names_length > this.etal_min - 2) {
            discretionary_names_length = this.etal_min - 2;
          }
        }
        var sane = this.etal_min >= this.etal_use_first;
        var overlength = count[key] > discretionary_names_length;
        if (discretionary_names_length > count[key]) {
          discretionary_names_length = display_names.length;
        }
        if (sane && overlength) {
          if (this.etal_use_last) {
            lst[key] = display_names.slice(0, discretionary_names_length).concat(display_names.slice(-1));
          } else {
            lst[key] = display_names.slice(0, discretionary_names_length);
          }
        }
        this.state.tmp.disambig_settings.names[pos] = lst[key].length;
        this.state.disambiguate.padBase(this.state.tmp.disambig_settings);
      };
      CSL2.NameOutput.prototype.disambigNames = function() {
        var pos;
        for (var i = 0, ilen = this.variables.length; i < ilen; i += 1) {
          var v = this.variables[i];
          pos = this.nameset_base + i;
          if (this.freeters[v].length) {
            this._runDisambigNames(this.freeters[v], pos);
          }
          if (this.institutions[v].length) {
            if ("undefined" === typeof this.state.tmp.disambig_settings.givens[pos]) {
              this.state.tmp.disambig_settings.givens[pos] = [];
            }
            for (var j = 0, jlen = this.institutions[v].length; j < jlen; j += 1) {
              if ("undefined" === typeof this.state.tmp.disambig_settings.givens[pos][j]) {
                this.state.tmp.disambig_settings.givens[pos].push(2);
              }
            }
          }
          for (var j = 0, jlen = this.persons[v].length; j < jlen; j += 1) {
            if (this.persons[v][j].length) {
              this._runDisambigNames(this.persons[v][j], pos);
            }
          }
        }
      };
      CSL2.NameOutput.prototype._runDisambigNames = function(lst, pos) {
        var chk, myform, myinitials, param, i, ilen, paramx;
        for (i = 0, ilen = lst.length; i < ilen; i += 1) {
          if (!lst[i].given && !lst[i].family) {
            continue;
          }
          myinitials = this.state.inheritOpt(this.name, "initialize-with");
          this.state.registry.namereg.addname("" + this.Item.id, lst[i], i);
          chk = this.state.tmp.disambig_settings.givens[pos];
          if ("undefined" === typeof chk) {
            for (var j = 0, jlen = pos + 1; j < jlen; j += 1) {
              if (!this.state.tmp.disambig_settings.givens[j]) {
                this.state.tmp.disambig_settings.givens[j] = [];
              }
            }
          }
          chk = this.state.tmp.disambig_settings.givens[pos][i];
          if ("undefined" === typeof chk) {
            myform = this.state.inheritOpt(this.name, "form", "name-form", "long");
            param = this.state.registry.namereg.evalname("" + this.Item.id, lst[i], i, 0, myform, myinitials);
            this.state.tmp.disambig_settings.givens[pos].push(param);
          }
          myform = this.state.inheritOpt(this.name, "form", "name-form", "long");
          paramx = this.state.registry.namereg.evalname("" + this.Item.id, lst[i], i, 0, myform, myinitials);
          if (this.state.tmp.disambig_request) {
            var val = this.state.tmp.disambig_settings.givens[pos][i];
            if (val === 1 && this.state.citation.opt["givenname-disambiguation-rule"] === "by-cite" && ("undefined" === typeof this.state.inheritOpt(this.name, "initialize-with") || "undefined" === typeof lst[i].given)) {
              val = 2;
            }
            param = val;
            if (this.state.opt["disambiguate-add-givenname"] && lst[i].given) {
              param = this.state.registry.namereg.evalname("" + this.Item.id, lst[i], i, param, this.state.inheritOpt(this.name, "form", "name-form", "long"), this.state.inheritOpt(this.name, "initialize-with"));
            }
          } else {
            param = paramx;
          }
          if (!this.state.tmp.just_looking && this.item && this.item.position === CSL2.POSITION_FIRST) {
            if (paramx > param) {
              param = paramx;
            }
          }
          if (!this.state.tmp.sort_key_flag) {
            this.state.tmp.disambig_settings.givens[pos][i] = param;
            if ("string" === typeof myinitials && ("undefined" === typeof this.name.strings["initialize"] || true === this.name.strings["initialize"])) {
              this.state.tmp.disambig_settings.use_initials = true;
            }
          }
        }
      };
      CSL2.NameOutput.prototype.getEtAlConfig = function() {
        var item = this.item;
        this["et-al"] = {};
        this.state.output.append(this.etal_term, this.etal_style, true);
        this["et-al"].single = this.state.output.pop();
        this["et-al"].single.strings.suffix = this.etal_suffix;
        this["et-al"].single.strings.prefix = this.etal_prefix_single;
        this.state.output.append(this.etal_term, this.etal_style, true);
        this["et-al"].multiple = this.state.output.pop();
        this["et-al"].multiple.strings.suffix = this.etal_suffix;
        this["et-al"].multiple.strings.prefix = this.etal_prefix_multiple;
        if ("undefined" === typeof item) {
          item = {};
        }
        if (item.position) {
          if (this.state.inheritOpt(this.name, "et-al-subsequent-min")) {
            this.etal_min = this.state.inheritOpt(this.name, "et-al-subsequent-min");
          } else {
            this.etal_min = this.state.inheritOpt(this.name, "et-al-min");
          }
          if (this.state.inheritOpt(this.name, "et-al-subsequent-use-first")) {
            this.etal_use_first = this.state.inheritOpt(this.name, "et-al-subsequent-use-first");
          } else {
            this.etal_use_first = this.state.inheritOpt(this.name, "et-al-use-first");
          }
        } else {
          if (this.state.tmp["et-al-min"]) {
            this.etal_min = this.state.tmp["et-al-min"];
          } else {
            this.etal_min = this.state.inheritOpt(this.name, "et-al-min");
          }
          if (this.state.tmp["et-al-use-first"]) {
            this.etal_use_first = this.state.tmp["et-al-use-first"];
          } else {
            this.etal_use_first = this.state.inheritOpt(this.name, "et-al-use-first");
          }
          if ("boolean" === typeof this.state.tmp["et-al-use-last"]) {
            this.etal_use_last = this.state.tmp["et-al-use-last"];
          } else {
            this.etal_use_last = this.state.inheritOpt(this.name, "et-al-use-last");
          }
        }
        if (!this.state.tmp["et-al-min"]) {
          this.state.tmp["et-al-min"] = this.etal_min;
        }
      };
      CSL2.NameOutput.prototype.setEtAlParameters = function() {
        var i, ilen, j, jlen;
        for (i = 0, ilen = this.variables.length; i < ilen; i += 1) {
          var v = this.variables[i];
          if ("undefined" === typeof this.etal_spec[v]) {
            this.etal_spec[v] = { freeters: 0, institutions: 0, persons: [] };
          }
          this.etal_spec[this.nameset_base + i] = this.etal_spec[v];
          if (this.freeters[v].length) {
            this._setEtAlParameter("freeters", v);
          }
          for (j = 0, jlen = this.persons[v].length; j < jlen; j += 1) {
            if ("undefined" === typeof this.etal_spec[v][j]) {
              this.etal_spec[v].persons[j] = 0;
            }
            this._setEtAlParameter("persons", v, j);
          }
          if (this.institutions[v].length) {
            this._setEtAlParameter("institutions", v);
          }
        }
      };
      CSL2.NameOutput.prototype._setEtAlParameter = function(type, v, j) {
        var lst, count;
        if (type === "persons") {
          lst = this.persons[v][j];
          count = this.persons_count[v][j];
        } else {
          lst = this[type][v];
          count = this[type + "_count"][v];
        }
        if (lst.length < count && !this.state.tmp.sort_key_flag) {
          if (this.etal_use_last) {
            if (type === "persons") {
              this.etal_spec[v].persons[j] = 2;
            } else {
              this.etal_spec[v][type] = 2;
            }
          } else {
            if (type === "persons") {
              this.etal_spec[v].persons[j] = 1;
            } else {
              this.etal_spec[v][type] = 1;
            }
          }
        } else {
          if (type === "persons") {
            this.etal_spec[v].persons[j] = 0;
          } else {
            this.etal_spec[v][type] = 0;
          }
        }
      };
      CSL2.NameOutput.prototype.renderAllNames = function() {
        var pos;
        for (var i = 0, ilen = this.variables.length; i < ilen; i += 1) {
          var v = this.variables[i];
          if (this.freeters[v].length || this.institutions[v].length) {
            if (!this.state.tmp.group_context.tip.condition) {
              this.state.tmp.just_did_number = false;
            }
          }
          pos = this.nameset_base + i;
          if (this.freeters[v].length) {
            this.freeters[v] = this._renderNames(v, this.freeters[v], pos);
          }
          for (var j = 0, jlen = this.institutions[v].length; j < jlen; j += 1) {
            this.persons[v][j] = this._renderNames(v, this.persons[v][j], pos, j);
          }
        }
        this.renderInstitutionNames();
      };
      CSL2.NameOutput.prototype.renderInstitutionNames = function() {
        for (var i = 0, ilen = this.variables.length; i < ilen; i += 1) {
          var v = this.variables[i];
          for (var j = 0, jlen = this.institutions[v].length; j < jlen; j += 1) {
            var institution;
            var name = this.institutions[v][j];
            var j, jlen, localesets;
            if (this.state.tmp.extension) {
              localesets = ["sort"];
            } else if (name.isInstitution || name.literal) {
              localesets = this.state.opt["cite-lang-prefs"].institutions;
            } else {
              localesets = this.state.opt["cite-lang-prefs"].persons;
            }
            var slot = { primary: "locale-orig", secondary: false, tertiary: false };
            if (localesets) {
              var slotnames = ["primary", "secondary", "tertiary"];
              for (var k = 0, klen = slotnames.length; k < klen; k += 1) {
                if (localesets.length - 1 < k) {
                  break;
                }
                if (localesets[k]) {
                  slot[slotnames[k]] = "locale-" + localesets[k];
                }
              }
            } else {
              slot.primary = "locale-translat";
            }
            if (this.state.tmp.area !== "bibliography" && !(this.state.tmp.area === "citation" && this.state.opt.xclass === "note" && this.item && !this.item.position)) {
              slot.secondary = false;
              slot.tertiary = false;
            }
            this.setRenderedName(name);
            var institution = this._renderInstitutionName(v, name, slot, j);
            this.institutions[v][j] = institution;
          }
        }
      };
      CSL2.NameOutput.prototype._renderInstitutionName = function(v, name, slot, j) {
        var secondary, tertiary, long_style, short_style, institution, institution_short, institution_long;
        var res = this.getName(name, slot.primary, true);
        var primary = res.name;
        var usedOrig = res.usedOrig;
        if (primary) {
          primary = this.fixupInstitution(primary, v, j);
        }
        secondary = false;
        if (slot.secondary) {
          res = this.getName(name, slot.secondary, false, usedOrig);
          var secondary = res.name;
          usedOrig = res.usedOrig;
          if (secondary) {
            secondary = this.fixupInstitution(secondary, v, j);
          }
        }
        tertiary = false;
        if (slot.tertiary) {
          res = this.getName(name, slot.tertiary, false, usedOrig);
          tertiary = res.name;
          if (tertiary) {
            tertiary = this.fixupInstitution(tertiary, v, j);
          }
        }
        var n = {
          l: {
            pri: false,
            sec: false,
            ter: false
          },
          s: {
            pri: false,
            sec: false,
            ter: false
          }
        };
        if (primary) {
          n.l.pri = primary["long"];
          n.s.pri = primary["short"].length ? primary["short"] : primary["long"];
        }
        if (secondary) {
          n.l.sec = secondary["long"];
          n.s.sec = secondary["short"].length ? secondary["short"] : secondary["long"];
        }
        if (tertiary) {
          n.l.ter = tertiary["long"];
          n.s.ter = tertiary["short"].length ? tertiary["short"] : tertiary["long"];
        }
        switch (this.institution.strings["institution-parts"]) {
          case "short":
            if (primary["short"].length) {
              short_style = this._getShortStyle();
              institution = [this._composeOneInstitutionPart([n.s.pri, n.s.sec, n.s.ter], slot, short_style, v)];
            } else {
              long_style = this._getLongStyle(primary, v, j);
              institution = [this._composeOneInstitutionPart([n.l.pri, n.l.sec, n.l.ter], slot, long_style, v)];
            }
            break;
          case "short-long":
            long_style = this._getLongStyle(primary, v, j);
            short_style = this._getShortStyle();
            institution_short = this._renderOneInstitutionPart(primary["short"], short_style);
            institution_long = this._composeOneInstitutionPart([n.l.pri, n.l.sec, n.l.ter], slot, long_style, v);
            institution = [institution_short, institution_long];
            break;
          case "long-short":
            long_style = this._getLongStyle(primary, v, j);
            short_style = this._getShortStyle();
            institution_short = this._renderOneInstitutionPart(primary["short"], short_style);
            institution_long = this._composeOneInstitutionPart([n.l.pri, n.l.sec, n.l.ter], slot, long_style, v);
            institution = [institution_long, institution_short];
            break;
          default:
            long_style = this._getLongStyle(primary, v, j);
            institution = [this._composeOneInstitutionPart([n.l.pri, n.l.sec, n.l.ter], slot, long_style, v)];
            break;
        }
        var blob = this._join(institution, " ");
        if (blob) {
          blob.isInstitution = true;
        }
        this.state.tmp.name_node.children.push(blob);
        return blob;
      };
      CSL2.NameOutput.prototype._composeOneInstitutionPart = function(names, slot, style) {
        var primary = false, secondary = false, tertiary = false, primary_tok, secondary_tok, tertiary_tok;
        if (names[0]) {
          primary_tok = CSL2.Util.cloneToken(style);
          if (this.state.opt.citeAffixes[slot.primary]) {
            if ("<i>" === this.state.opt.citeAffixes.institutions[slot.primary].prefix) {
              var hasItalic = false;
              for (var i = 0, ilen = primary_tok.decorations.length; i < ilen; i += 1) {
                if (style.decorations[i][0] === "@font-style" && primary_tok.decorations[i][1] === "italic") {
                  hasItalic = true;
                }
              }
              if (!hasItalic) {
                primary_tok.decorations.push(["@font-style", "italic"]);
              }
            }
          }
          primary = this._renderOneInstitutionPart(names[0], primary_tok);
        }
        if (names[1]) {
          secondary = this._renderOneInstitutionPart(names[1], style);
        }
        if (names[2]) {
          tertiary = this._renderOneInstitutionPart(names[2], style);
        }
        var institutionblob;
        if (secondary || tertiary) {
          this.state.output.openLevel("empty");
          this.state.output.append(primary);
          secondary_tok = CSL2.Util.cloneToken(style);
          if (slot.secondary) {
            secondary_tok.strings.prefix = this.state.opt.citeAffixes.institutions[slot.secondary].prefix;
            secondary_tok.strings.suffix = this.state.opt.citeAffixes.institutions[slot.secondary].suffix;
            if (!secondary_tok.strings.prefix) {
              secondary_tok.strings.prefix = " ";
            }
          }
          var secondary_outer = new CSL2.Token();
          secondary_outer.decorations.push(["@font-style", "normal"]);
          secondary_outer.decorations.push(["@font-weight", "normal"]);
          this.state.output.openLevel(secondary_outer);
          this.state.output.append(secondary, secondary_tok);
          this.state.output.closeLevel();
          tertiary_tok = CSL2.Util.cloneToken(style);
          if (slot.tertiary) {
            tertiary_tok.strings.prefix = this.state.opt.citeAffixes.institutions[slot.tertiary].prefix;
            tertiary_tok.strings.suffix = this.state.opt.citeAffixes.institutions[slot.tertiary].suffix;
            if (!tertiary_tok.strings.prefix) {
              tertiary_tok.strings.prefix = " ";
            }
          }
          var tertiary_outer = new CSL2.Token();
          tertiary_outer.decorations.push(["@font-style", "normal"]);
          tertiary_outer.decorations.push(["@font-weight", "normal"]);
          this.state.output.openLevel(tertiary_outer);
          this.state.output.append(tertiary, tertiary_tok);
          this.state.output.closeLevel();
          this.state.output.closeLevel();
          institutionblob = this.state.output.pop();
        } else {
          institutionblob = primary;
        }
        return institutionblob;
      };
      CSL2.NameOutput.prototype._renderOneInstitutionPart = function(blobs, style) {
        for (var i = 0, ilen = blobs.length; i < ilen; i += 1) {
          if (blobs[i]) {
            var str = blobs[i];
            if (this.state.tmp.strip_periods) {
              str = str.replace(/\./g, "");
            } else {
              for (var j = 0, jlen = style.decorations.length; j < jlen; j += 1) {
                if ("@strip-periods" === style.decorations[j][0] && "true" === style.decorations[j][1]) {
                  str = str.replace(/\./g, "");
                  break;
                }
              }
            }
            this.state.tmp.group_context.tip.variable_success = true;
            this.state.tmp.can_substitute.replace(false, CSL2.LITERAL);
            if (str === "!here>>>") {
              blobs[i] = false;
            } else {
              this.state.output.append(str, style, true);
              blobs[i] = this.state.output.pop();
            }
          }
        }
        if ("undefined" === typeof this.institution.strings["part-separator"]) {
          this.institution.strings["part-separator"] = this.state.tmp.name_delimiter;
        }
        return this._join(blobs, this.institution.strings["part-separator"]);
      };
      CSL2.NameOutput.prototype._renderNames = function(v, values, pos, j) {
        var ret = false;
        if (values.length) {
          var names = [];
          for (var i = 0, ilen = values.length; i < ilen; i += 1) {
            var name = values[i];
            var ret, localesets;
            if (this.state.tmp.extension) {
              localesets = ["sort"];
            } else if (name.isInstitution || name.literal) {
              localesets = this.state.opt["cite-lang-prefs"].institutions;
            } else {
              localesets = this.state.opt["cite-lang-prefs"].persons;
            }
            var slot = { primary: "locale-orig", secondary: false, tertiary: false };
            if (localesets) {
              var slotnames = ["primary", "secondary", "tertiary"];
              for (var k = 0, klen = slotnames.length; k < klen; k += 1) {
                if (localesets.length - 1 < k) {
                  break;
                }
                slot[slotnames[k]] = "locale-" + localesets[k];
              }
            } else {
              slot.primary = "locale-translat";
            }
            if (this.state.tmp.sort_key_flag || this.state.tmp.area !== "bibliography" && !(this.state.tmp.area === "citation" && this.state.opt.xclass === "note" && this.item && !this.item.position)) {
              slot.secondary = false;
              slot.tertiary = false;
            }
            this.setRenderedName(name);
            if (!name.literal && !name.isInstitution) {
              var nameBlob = this._renderPersonalName(v, name, slot, pos, i, j);
              var nameToken = CSL2.Util.cloneToken(this.name);
              this.state.output.append(nameBlob, nameToken, true);
              names.push(this.state.output.pop());
            } else {
              names.push(this._renderInstitutionName(v, name, slot, j));
            }
          }
          ret = this.joinPersons(names, pos, j);
        }
        return ret;
      };
      CSL2.NameOutput.prototype._renderPersonalName = function(v, name, slot, pos, i, j) {
        var res = this.getName(name, slot.primary, true);
        var primary = this._renderOnePersonalName(res.name, pos, i, j);
        var secondary = false;
        if (slot.secondary) {
          res = this.getName(name, slot.secondary, false, res.usedOrig);
          if (res.name) {
            secondary = this._renderOnePersonalName(res.name, pos, i, j);
          }
        }
        var tertiary = false;
        if (slot.tertiary) {
          res = this.getName(name, slot.tertiary, false, res.usedOrig);
          if (res.name) {
            tertiary = this._renderOnePersonalName(res.name, pos, i, j);
          }
        }
        var personblob;
        if (secondary || tertiary) {
          this.state.output.openLevel("empty");
          this.state.output.append(primary);
          var secondary_tok = new CSL2.Token();
          if (slot.secondary) {
            secondary_tok.strings.prefix = this.state.opt.citeAffixes.persons[slot.secondary].prefix;
            secondary_tok.strings.suffix = this.state.opt.citeAffixes.persons[slot.secondary].suffix;
            if (!secondary_tok.strings.prefix) {
              secondary_tok.strings.prefix = " ";
            }
          }
          this.state.output.append(secondary, secondary_tok);
          var tertiary_tok = new CSL2.Token();
          if (slot.tertiary) {
            tertiary_tok.strings.prefix = this.state.opt.citeAffixes.persons[slot.tertiary].prefix;
            tertiary_tok.strings.suffix = this.state.opt.citeAffixes.persons[slot.tertiary].suffix;
            if (!tertiary_tok.strings.prefix) {
              tertiary_tok.strings.prefix = " ";
            }
          }
          this.state.output.append(tertiary, tertiary_tok);
          this.state.output.closeLevel();
          personblob = this.state.output.pop();
        } else {
          personblob = primary;
        }
        return personblob;
      };
      CSL2.NameOutput.prototype._isRomanesque = function(name) {
        var ret = 2;
        if (!name.family.replace(/\"/g, "").match(CSL2.ROMANESQUE_REGEXP)) {
          ret = 0;
        }
        if (!ret && name.given && name.given.match(CSL2.STARTSWITH_ROMANESQUE_REGEXP)) {
          ret = 1;
        }
        var top_locale;
        if (ret == 2) {
          if (name.multi && name.multi.main) {
            top_locale = name.multi.main.slice(0, 2);
          } else if (this.Item.language) {
            top_locale = this.Item.language.slice(0, 2);
          }
          if (["ja", "zh"].indexOf(top_locale) > -1) {
            ret = 1;
          }
        }
        return ret;
      };
      CSL2.NameOutput.prototype._renderOnePersonalName = function(value, pos, i, j) {
        var name = value;
        var dropping_particle = this._droppingParticle(name, pos, j);
        var family = this._familyName(name);
        var non_dropping_particle = this._nonDroppingParticle(name);
        var givenInfo = this._givenName(name, pos, i);
        var given = givenInfo.blob;
        var suffix = this._nameSuffix(name);
        if (given === false) {
          dropping_particle = false;
          suffix = false;
        }
        var sort_sep = this.state.inheritOpt(this.name, "sort-separator");
        if (!sort_sep) {
          sort_sep = "";
        }
        var suffix_sep;
        if (name["comma-suffix"]) {
          suffix_sep = ", ";
        } else {
          suffix_sep = " ";
        }
        var romanesque = this._isRomanesque(name);
        function hasJoiningPunctuation(blob2) {
          if (!blob2) {
            return false;
          } else if ("string" === typeof blob2.blobs) {
            if (["\u2019", "'", "-", " "].indexOf(blob2.blobs.slice(-1)) > -1) {
              return true;
            } else {
              return false;
            }
          } else {
            return hasJoiningPunctuation(blob2.blobs[blob2.blobs.length - 1]);
          }
        }
        var has_hyphenated_non_dropping_particle = hasJoiningPunctuation(non_dropping_particle);
        var nbspace;
        if (["fr", "ru", "cs"].indexOf(this.state.opt["default-locale"][0].slice(0, 2)) > -1) {
          nbspace = "\xA0";
        } else {
          nbspace = " ";
        }
        var blob, merged, first, second;
        if (romanesque === 0) {
          blob = this._join([non_dropping_particle, family, given], "");
        } else if (romanesque === 1 || name["static-ordering"]) {
          merged = this._join([non_dropping_particle, family], nbspace);
          blob = this._join([merged, given], " ");
        } else if (name["reverse-ordering"]) {
          merged = this._join([non_dropping_particle, family], nbspace);
          blob = this._join([given, merged], " ");
        } else if (this.state.tmp.sort_key_flag) {
          if (this.state.opt["demote-non-dropping-particle"] === "never") {
            merged = this._join([non_dropping_particle, family], nbspace);
            merged = this._join([merged, dropping_particle], " ");
            merged = this._join([merged, given], this.state.opt.sort_sep);
            blob = this._join([merged, suffix], " ");
          } else {
            second = this._join([given, dropping_particle, non_dropping_particle], " ");
            merged = this._join([family, second], this.state.opt.sort_sep);
            blob = this._join([merged, suffix], " ");
          }
        } else if (this.state.inheritOpt(this.name, "name-as-sort-order") === "all" || this.state.inheritOpt(this.name, "name-as-sort-order") === "first" && i === 0 && (j === 0 || "undefined" === typeof j)) {
          if (["Lord", "Lady"].indexOf(name.given) > -1) {
            sort_sep = ", ";
          }
          if (["always", "display-and-sort"].indexOf(this.state.opt["demote-non-dropping-particle"]) > -1) {
            second = this._join([given, dropping_particle], name["comma-dropping-particle"] + " ");
            second = this._join([second, non_dropping_particle], " ");
            if (second && this.given) {
              second.strings.prefix = this.given.strings.prefix;
              second.strings.suffix = this.given.strings.suffix;
            }
            if (family && this.family) {
              family.strings.prefix = this.family.strings.prefix;
              family.strings.suffix = this.family.strings.suffix;
            }
            merged = this._join([family, second], sort_sep);
            blob = this._join([merged, suffix], sort_sep);
          } else {
            if (has_hyphenated_non_dropping_particle) {
              first = this._join([non_dropping_particle, family], "");
            } else {
              first = this._join([non_dropping_particle, family], nbspace);
            }
            if (first && this.family) {
              first.strings.prefix = this.family.strings.prefix;
              first.strings.suffix = this.family.strings.suffix;
            }
            second = this._join([given, dropping_particle], name["comma-dropping-particle"] + " ");
            if (second && this.given) {
              second.strings.prefix = this.given.strings.prefix;
              second.strings.suffix = this.given.strings.suffix;
            }
            merged = this._join([first, second], sort_sep);
            blob = this._join([merged, suffix], sort_sep);
          }
          blob.isInverted = true;
        } else {
          if (name["dropping-particle"] && name.family && !name["non-dropping-particle"]) {
            var dp = name["dropping-particle"];
            var apostrophes = ["'", "\u02BC", "\u2019", "-"];
            if (apostrophes.indexOf(dp.slice(-1)) > -1 && dp.slice(0, -1) !== "de") {
              family = this._join([dropping_particle, family], "");
              dropping_particle = false;
            }
          }
          if (has_hyphenated_non_dropping_particle) {
            second = this._join([non_dropping_particle, family], "");
            second = this._join([dropping_particle, second], nbspace);
          } else {
            second = this._join([dropping_particle, non_dropping_particle, family], nbspace);
          }
          second = this._join([second, suffix], suffix_sep);
          if (second && this.family) {
            second.strings.prefix = this.family.strings.prefix;
            second.strings.suffix = this.family.strings.suffix;
          }
          if (given && this.given) {
            given.strings.prefix = this.given.strings.prefix;
            given.strings.suffix = this.given.strings.suffix;
          }
          if (second.strings.prefix) {
            name["comma-dropping-particle"] = "";
          }
          var space;
          if (this.state.inheritOpt(this.name, "initialize-with") && this.state.inheritOpt(this.name, "initialize-with").match(/[\u00a0\ufeff]/) && givenInfo.initializationLevel === 1) {
            space = nbspace;
          } else {
            space = " ";
          }
          blob = this._join([given, second], name["comma-dropping-particle"] + space);
        }
        this.state.tmp.group_context.tip.variable_success = true;
        this.state.tmp.can_substitute.replace(false, CSL2.LITERAL);
        this.state.tmp.term_predecessor = true;
        this.state.tmp.name_node.children.push(blob);
        return blob;
      };
      CSL2.NameOutput.prototype._normalizeNameInput = function(value) {
        var name = {
          literal: value.literal,
          family: value.family,
          isInstitution: value.isInstitution,
          given: value.given,
          suffix: value.suffix,
          "comma-suffix": value["comma-suffix"],
          "non-dropping-particle": value["non-dropping-particle"],
          "dropping-particle": value["dropping-particle"],
          "static-ordering": value["static-ordering"],
          "static-particles": value["static-particles"],
          "reverse-ordering": value["reverse-ordering"],
          "full-form-always": value["full-form-always"],
          "parse-names": value["parse-names"],
          "comma-dropping-particle": "",
          block_initialize: value.block_initialize,
          multi: value.multi
        };
        this._parseName(name);
        return name;
      };
      CSL2.NameOutput.prototype._stripPeriods = function(tokname, str) {
        var decor_tok = this[tokname + "_decor"];
        if (str) {
          if (this.state.tmp.strip_periods) {
            str = str.replace(/\./g, "");
          } else if (decor_tok) {
            for (var i = 0, ilen = decor_tok.decorations.length; i < ilen; i += 1) {
              if ("@strip-periods" === decor_tok.decorations[i][0] && "true" === decor_tok.decorations[i][1]) {
                str = str.replace(/\./g, "");
                break;
              }
            }
          }
        }
        return str;
      };
      CSL2.NameOutput.prototype._nonDroppingParticle = function(name) {
        var ndp = name["non-dropping-particle"];
        if (ndp && this.state.tmp.sort_key_flag) {
          ndp = ndp.replace(/[\'\u2019]/, "");
        }
        var str = this._stripPeriods("family", ndp);
        if (this.state.output.append(str, this.family_decor, true)) {
          return this.state.output.pop();
        }
        return false;
      };
      CSL2.NameOutput.prototype._droppingParticle = function(name, pos, j) {
        var dp = name["dropping-particle"];
        if (dp && this.state.tmp.sort_key_flag) {
          dp = dp.replace(/[\'\u2019]/, "");
        }
        var str = this._stripPeriods("given", dp);
        if (name["dropping-particle"] && name["dropping-particle"].match(/^et.?al[^a-z]$/)) {
          if (this.state.inheritOpt(this.name, "et-al-use-last")) {
            if ("undefined" === typeof j) {
              this.etal_spec[pos].freeters = 2;
            } else {
              this.etal_spec[pos].persons = 2;
            }
          } else {
            if ("undefined" === typeof j) {
              this.etal_spec[pos].freeters = 1;
            } else {
              this.etal_spec[pos].persons = 1;
            }
          }
          name["comma-dropping-particle"] = "";
        } else if (this.state.output.append(str, this.given_decor, true)) {
          return this.state.output.pop();
        }
        return false;
      };
      CSL2.NameOutput.prototype._familyName = function(name) {
        var str = this._stripPeriods("family", name.family);
        if (this.state.output.append(str, this.family_decor, true)) {
          return this.state.output.pop();
        }
        return false;
      };
      CSL2.NameOutput.prototype._givenName = function(name, pos, i) {
        var ret;
        var formIsShort = this.state.inheritOpt(this.name, "form", "name-form", "long") !== "long";
        var initializeIsTurnedOn = this.state.inheritOpt(this.name, "initialize") !== false;
        var hasInitializeWith = "string" === typeof this.state.inheritOpt(this.name, "initialize-with") && !name.block_initialize;
        var defaultLevel;
        var useLevel;
        if (name["full-form-always"]) {
          useLevel = 2;
        } else {
          if (formIsShort) {
            defaultLevel = 0;
          } else if (hasInitializeWith) {
            defaultLevel = 1;
          } else {
            defaultLevel = 2;
          }
          var requestedLevel = this.state.tmp.disambig_settings.givens[pos][i];
          if (requestedLevel > defaultLevel) {
            useLevel = requestedLevel;
          } else {
            useLevel = defaultLevel;
          }
        }
        var gdropt = this.state.citation.opt["givenname-disambiguation-rule"];
        if (gdropt && gdropt.slice(-14) === "-with-initials") {
          hasInitializeWith = true;
        }
        if (name.family && useLevel === 1) {
          if (hasInitializeWith) {
            var initialize_with = this.state.inheritOpt(this.name, "initialize-with", false, "");
            name.given = CSL2.Util.Names.initializeWith(this.state, name.given, initialize_with, !initializeIsTurnedOn);
          } else {
            name.given = CSL2.Util.Names.unInitialize(this.state, name.given);
          }
        } else if (useLevel === 0) {
          return {
            blob: false
          };
        } else if (useLevel === 2) {
          name.given = CSL2.Util.Names.unInitialize(this.state, name.given);
        }
        var str = this._stripPeriods("given", name.given);
        var rendered = this.state.output.append(str, this.given_decor, true);
        if (rendered) {
          ret = this.state.output.pop();
          return {
            blob: ret,
            initializationLevel: useLevel
          };
        }
        return {
          blob: false
        };
      };
      CSL2.NameOutput.prototype._nameSuffix = function(name) {
        var str = name.suffix, ret;
        if (str && "string" === typeof this.state.inheritOpt(this.name, "initialize-with")) {
          str = CSL2.Util.Names.initializeWith(this.state, str, this.state.inheritOpt(this.name, "initialize-with"), true);
        }
        str = this._stripPeriods("family", str);
        var toSuffix = "";
        if (str && str.slice(-1) === ".") {
          str = str.slice(0, -1);
          toSuffix = ".";
        }
        var rendered = this.state.output.append(str, "empty", true);
        if (rendered) {
          ret = this.state.output.pop();
          ret.strings.suffix = toSuffix + ret.strings.suffix;
          return ret;
        }
        return false;
      };
      CSL2.NameOutput.prototype._getLongStyle = function(name) {
        var long_style;
        if (name["short"].length) {
          if (this.institutionpart["long-with-short"]) {
            long_style = this.institutionpart["long-with-short"];
          } else {
            long_style = this.institutionpart["long"];
          }
        } else {
          long_style = this.institutionpart["long"];
        }
        if (!long_style) {
          long_style = new CSL2.Token();
        }
        return long_style;
      };
      CSL2.NameOutput.prototype._getShortStyle = function() {
        var short_style;
        if (this.institutionpart["short"]) {
          short_style = this.institutionpart["short"];
        } else {
          short_style = new CSL2.Token();
        }
        return short_style;
      };
      CSL2.NameOutput.prototype._parseName = function(name) {
        if (!name["parse-names"] && "undefined" !== typeof name["parse-names"]) {
          return name;
        }
        if (name.family && !name.given && name.isInstitution) {
          name.literal = name.family;
          name.family = void 0;
          name.isInstitution = void 0;
        }
        var noparse;
        if (name.family && (name.family.slice(0, 1) === '"' && name.family.slice(-1) === '"') || !name["parse-names"] && "undefined" !== typeof name["parse-names"]) {
          name.family = name.family.slice(1, -1);
          noparse = true;
          name["parse-names"] = 0;
        } else {
          noparse = false;
        }
        if (this.state.opt.development_extensions.parse_names) {
          if (!name["non-dropping-particle"] && name.family && !noparse && name.given) {
            if (!name["static-particles"]) {
              CSL2.parseParticles(name, true);
            }
          }
        }
      };
      CSL2.NameOutput.prototype.getName = function(name, slotLocaleset, fallback, stopOrig) {
        if (stopOrig && slotLocaleset === "locale-orig") {
          return { name: false, usedOrig: stopOrig };
        }
        if (!name.family) {
          name.family = "";
        }
        if (!name.given) {
          name.given = "";
        }
        var name_params = {};
        name_params["static-ordering"] = this.getStaticOrder(name);
        var foundTag = true;
        var langTag;
        if (slotLocaleset !== "locale-orig") {
          foundTag = false;
          if (name.multi) {
            var langTags = this.state.opt[slotLocaleset];
            for (var i = 0, ilen = langTags.length; i < ilen; i += 1) {
              langTag = langTags[i];
              if (name.multi._key[langTag]) {
                foundTag = true;
                var isInstitution = name.isInstitution;
                name = name.multi._key[langTag];
                name.isInstitution = isInstitution;
                name_params = this.getNameParams(langTag);
                name_params.transliterated = true;
                break;
              }
            }
          }
        }
        if (!foundTag) {
          langTag = false;
          if (name.multi && name.multi.main) {
            langTag = name.multi.main;
          } else if (this.Item.language) {
            langTag = this.Item.language;
          }
          if (langTag) {
            name_params = this.getNameParams(langTag);
          }
        }
        if (!fallback && !foundTag) {
          return { name: false, usedOrig: stopOrig };
        }
        if (!name.family) {
          name.family = "";
        }
        if (!name.given) {
          name.given = "";
        }
        if (name.literal) {
          delete name.family;
          delete name.given;
        }
        name = {
          family: name.family,
          given: name.given,
          "non-dropping-particle": name["non-dropping-particle"],
          "dropping-particle": name["dropping-particle"],
          suffix: name.suffix,
          "static-ordering": name_params["static-ordering"],
          "static-particles": name["static-particles"],
          "reverse-ordering": name_params["reverse-ordering"],
          "full-form-always": name_params["full-form-always"],
          "parse-names": name["parse-names"],
          "comma-suffix": name["comma-suffix"],
          "comma-dropping-particle": name["comma-dropping-particle"],
          transliterated: name_params.transliterated,
          block_initialize: name_params["block-initialize"],
          literal: name.literal,
          isInstitution: name.isInstitution,
          multi: name.multi
        };
        if (!name.literal && (!name.given && name.family && name.isInstitution)) {
          name.literal = name.family;
        }
        if (name.literal) {
          delete name.family;
          delete name.given;
        }
        name = this._normalizeNameInput(name);
        var usedOrig;
        if (stopOrig) {
          usedOrig = stopOrig;
        } else {
          usedOrig = !foundTag;
        }
        return { name, usedOrig };
      };
      CSL2.NameOutput.prototype.getNameParams = function(langTag) {
        var ret = {};
        var langspec = CSL2.localeResolve(this.Item.language, this.state.opt["default-locale"][0]);
        var try_locale = this.state.locale[langspec.best] ? langspec.best : this.state.opt["default-locale"][0];
        var name_as_sort_order = this.state.locale[try_locale].opts["name-as-sort-order"];
        var name_as_reverse_order = this.state.locale[try_locale].opts["name-as-reverse-order"];
        var name_never_short = this.state.locale[try_locale].opts["name-never-short"];
        var field_lang_bare = langTag.split("-")[0];
        if (name_as_sort_order && name_as_sort_order[field_lang_bare]) {
          ret["static-ordering"] = true;
          ret["reverse-ordering"] = false;
        }
        if (name_as_reverse_order && name_as_reverse_order[field_lang_bare]) {
          ret["reverse-ordering"] = true;
          ret["static-ordering"] = false;
        }
        if (name_never_short && name_never_short[field_lang_bare]) {
          ret["full-form-always"] = true;
        }
        if (ret["static-ordering"]) {
          ret["block-initialize"] = true;
        }
        return ret;
      };
      CSL2.NameOutput.prototype.setRenderedName = function(name) {
        if (this.state.tmp.area === "bibliography") {
          var strname = "";
          for (var j = 0, jlen = CSL2.NAME_PARTS.length; j < jlen; j += 1) {
            if (name[CSL2.NAME_PARTS[j]]) {
              strname += name[CSL2.NAME_PARTS[j]];
            }
          }
          this.state.tmp.rendered_name.push(strname);
        }
      };
      CSL2.NameOutput.prototype.fixupInstitution = function(name, varname, listpos) {
        if (!name.literal && name.family) {
          name.literal = name.family;
          delete name.family;
        }
        var longNameStr = name.literal;
        var shortNameStr = longNameStr;
        var ret = {
          "long": longNameStr.split(/\s*\|\s*/),
          "short": shortNameStr.split(/\s*\|\s*/)
        };
        if (this.state.sys.getAbbreviation) {
          if (this.institution.strings.form === "short") {
            let jurisdiction = this.Item.jurisdiction;
            jurisdiction = this.state.transform.loadAbbreviation(jurisdiction, "institution-entire", longNameStr, this.Item.language);
            if (this.state.transform.abbrevs[jurisdiction]["institution-entire"][longNameStr]) {
              longNameStr = this.state.transform.abbrevs[jurisdiction]["institution-entire"][longNameStr];
            } else {
              jurisdiction = this.Item.jurisdiction;
              jurisdiction = this.state.transform.loadAbbreviation(jurisdiction, "institution-part", longNameStr, this.Item.language);
              if (this.state.transform.abbrevs[jurisdiction]["institution-part"][longNameStr]) {
                longNameStr = this.state.transform.abbrevs[jurisdiction]["institution-part"][longNameStr];
              }
            }
            longNameStr = this._quashChecks(jurisdiction, longNameStr);
          }
          if (["short", "short-long", "long-short"].indexOf(this.institution.strings["institution-parts"]) > -1) {
            let jurisdiction = this.Item.jurisdiction;
            jurisdiction = this.state.transform.loadAbbreviation(jurisdiction, "institution-part", shortNameStr, this.Item.language);
            if (this.state.transform.abbrevs[jurisdiction]["institution-part"][shortNameStr]) {
              shortNameStr = this.state.transform.abbrevs[jurisdiction]["institution-part"][shortNameStr];
            }
            shortNameStr = this._quashChecks(jurisdiction, shortNameStr);
            if (["short-long", "long-short"].indexOf(this.institution.strings["institution-parts"]) > -1) {
              if (shortNameStr === longNameStr) {
                shortNameStr = "";
              }
            }
          }
          ret["long"] = longNameStr.split(/\s*\|\s*/);
          ret["short"] = shortNameStr.split(/\s*\|\s*/);
          if (["short", "short-long", "long-short"].indexOf(this.institution.strings["institution-parts"]) > -1) {
            for (var j = ret["short"].length - 1; j > -1; j--) {
              let jurisdiction = this.Item.jurisdiction;
              var abbrevKey = ret["short"][j];
              jurisdiction = this.state.transform.loadAbbreviation(jurisdiction, "institution-part", abbrevKey, this.Item.language);
              if (this.state.transform.abbrevs[jurisdiction]["institution-part"][abbrevKey]) {
                ret["short"][j] = this.state.transform.abbrevs[jurisdiction]["institution-part"][abbrevKey];
              }
              if (ret["short"][j].indexOf("|") > -1) {
                let retShort = ret["short"];
                let splitShort = retShort[j].split(/\s*\|\s*/);
                ret["short"] = retShort.slice(0, j).concat(splitShort).concat(retShort.slice(j + 1));
              }
            }
          }
          if (this.state.opt.development_extensions.legacy_institution_name_ordering) {
            ret["short"].reverse();
          }
          ret["short"] = this._trimInstitution(ret["short"]);
          if (this.institution.strings["reverse-order"]) {
            ret["short"].reverse();
          }
          if (!this.state.tmp.just_looking) {
            if (this.Item.jurisdiction) {
              let jurisdiction = this.Item.jurisdiction;
              var trimmer = this.state.tmp.abbrev_trimmer;
              if (trimmer && trimmer[jurisdiction] && trimmer[jurisdiction][varname]) {
                for (var i = 0, ilen = ret["short"].length; i < ilen; i++) {
                  var frag = ret["short"][i];
                  ret["short"][i] = frag.replace(trimmer[jurisdiction][varname], "").trim();
                }
              }
            }
          }
        }
        if (this.state.opt.development_extensions.legacy_institution_name_ordering) {
          ret["long"].reverse();
        }
        ret["long"] = this._trimInstitution(ret["long"]);
        if (this.institution.strings["reverse-order"]) {
          ret["long"].reverse();
        }
        return ret;
      };
      CSL2.NameOutput.prototype.getStaticOrder = function(name, refresh) {
        var static_ordering_val = false;
        if (!refresh && name["static-ordering"]) {
          static_ordering_val = true;
        } else if (this._isRomanesque(name) === 0) {
          static_ordering_val = true;
        } else if ((!name.multi || !name.multi.main) && this.Item.language && ["vi", "hu"].indexOf(this.Item.language) > -1) {
          static_ordering_val = true;
        } else if (name.multi && name.multi.main && ["vi", "hu"].indexOf(name.multi.main.slice(0, 2)) > -1) {
          static_ordering_val = true;
        } else {
          if (this.state.opt["auto-vietnamese-names"] && (CSL2.VIETNAMESE_NAMES.exec(name.family + " " + name.given) && CSL2.VIETNAMESE_SPECIALS.exec(name.family + name.given))) {
            static_ordering_val = true;
          }
        }
        return static_ordering_val;
      };
      CSL2.NameOutput.prototype._quashChecks = function(jurisdiction, str) {
        var str = this.state.transform.quashCheck(jurisdiction, str);
        var lst = str.split(/>>[0-9]{4}>>/);
        var m = str.match(/>>([0-9]{4})>>/);
        str = lst.pop();
        var date = this.Item["original-date"] ? this.Item["original-date"] : this.Item["issued"];
        if (date) {
          date = parseInt(date.year, 10);
          date = isNaN(date) ? false : date;
        }
        if (date) {
          if (lst.length > 0) {
            for (var k = m.length - 1; k > 0; k--) {
              if (date >= parseInt(m[k], 10)) {
                break;
              }
              str = lst.pop();
            }
          }
          str = str.replace(/\s*\|\s*/g, "|");
        }
        return str;
      };
      CSL2.NameOutput.prototype._trimInstitution = function(subunits) {
        var use_first = false;
        var stop_last = false;
        var use_last = false;
        var stop_first = false;
        var s = subunits.slice();
        if (this.institution) {
          if ("undefined" !== typeof this.institution.strings["use-first"]) {
            use_first = this.institution.strings["use-first"];
          }
          if ("undefined" !== typeof this.institution.strings["use-last"]) {
            use_last = this.institution.strings["use-last"];
          }
          if ("undefined" !== typeof this.institution.strings["stop-first"]) {
            stop_first = this.institution.strings["stop-first"];
          }
          if ("undefined" !== typeof this.institution.strings["stop-last"]) {
            stop_last = this.institution.strings["stop-last"];
          }
          if (use_first) {
            if (stop_last) {
              s = s.slice(0, stop_last * -1);
            }
            s = s.slice(0, use_first);
          }
          if (use_last) {
            var ss = subunits.slice();
            if (use_first) {
              stop_first = use_first;
            } else {
              s = [];
            }
            if (stop_first) {
              ss = ss.slice(stop_first);
            }
            ss = ss.slice(use_last * -1);
            s = s.concat(ss);
          }
          subunits = s;
        }
        return subunits;
      };
      CSL2.PublisherOutput = function(state, group_tok) {
        this.state = state;
        this.group_tok = group_tok;
        this.varlist = [];
      };
      CSL2.PublisherOutput.prototype.render = function() {
        this.clearVars();
        this.composeAndBlob();
        this.composeElements();
        this.composePublishers();
        this.joinPublishers();
      };
      CSL2.PublisherOutput.prototype.composeAndBlob = function() {
        this.and_blob = {};
        var and_term = false;
        if (this.group_tok.strings.and === "text") {
          and_term = this.state.getTerm("and");
        } else if (this.group_tok.strings.and === "symbol") {
          and_term = "&";
        }
        var tok = new CSL2.Token();
        tok.strings.suffix = " ";
        tok.strings.prefix = " ";
        this.state.output.append(and_term, tok, true);
        var no_delim = this.state.output.pop();
        tok.strings.prefix = this.group_tok.strings["subgroup-delimiter"];
        this.state.output.append(and_term, tok, true);
        var with_delim = this.state.output.pop();
        this.and_blob.single = false;
        this.and_blob.multiple = false;
        if (and_term) {
          if (this.group_tok.strings["subgroup-delimiter-precedes-last"] === "always") {
            this.and_blob.single = with_delim;
          } else if (this.group_tok.strings["subgroup-delimiter-precedes-last"] === "never") {
            this.and_blob.single = no_delim;
            this.and_blob.multiple = no_delim;
          } else {
            this.and_blob.single = no_delim;
            this.and_blob.multiple = with_delim;
          }
        }
      };
      CSL2.PublisherOutput.prototype.composeElements = function() {
        for (var i = 0, ilen = 2; i < ilen; i += 1) {
          var varname = ["publisher", "publisher-place"][i];
          for (var j = 0, jlen = this["publisher-list"].length; j < jlen; j += 1) {
            var str = this[varname + "-list"][j];
            var tok = this[varname + "-token"];
            this.state.output.append(str, tok, true);
            this[varname + "-list"][j] = this.state.output.pop();
          }
        }
      };
      CSL2.PublisherOutput.prototype.composePublishers = function() {
        var blobs;
        for (var i = 0, ilen = this["publisher-list"].length; i < ilen; i += 1) {
          blobs = [this[this.varlist[0] + "-list"][i], this[this.varlist[1] + "-list"][i]];
          this["publisher-list"][i] = this._join(blobs, this.group_tok.strings.delimiter);
        }
      };
      CSL2.PublisherOutput.prototype.joinPublishers = function() {
        var blobs = this["publisher-list"];
        var publishers = this._join(blobs, this.group_tok.strings["subgroup-delimiter"], this.and_blob.single, this.and_blob.multiple, this.group_tok);
        this.state.output.append(publishers, "literal");
      };
      CSL2.PublisherOutput.prototype._join = CSL2.NameOutput.prototype._join;
      CSL2.PublisherOutput.prototype._getToken = CSL2.NameOutput.prototype._getToken;
      CSL2.PublisherOutput.prototype.clearVars = function() {
        this.state.tmp["publisher-list"] = false;
        this.state.tmp["publisher-place-list"] = false;
        this.state.tmp["publisher-group-token"] = false;
        this.state.tmp["publisher-token"] = false;
        this.state.tmp["publisher-place-token"] = false;
      };
      CSL2.evaluateLabel = function(node, state, Item, item) {
        var myterm;
        if ("locator" === node.strings.term) {
          if (item && item.label) {
            if (item.label === "sub verbo") {
              myterm = "sub-verbo";
            } else {
              myterm = item.label;
            }
          }
          if (!myterm) {
            myterm = "page";
          }
        } else {
          myterm = node.strings.term;
        }
        var plural = node.strings.plural;
        if ("number" !== typeof plural) {
          var theItem = item && node.strings.term === "locator" ? item : Item;
          if (theItem[node.strings.term]) {
            state.processNumber(false, theItem, node.strings.term, Item.type);
            plural = state.tmp.shadow_numbers[node.strings.term].plural;
            if (!state.tmp.shadow_numbers[node.strings.term].labelForm && !state.tmp.shadow_numbers[node.strings.term].labelDecorations) {
              if (node.strings.form) {
                state.tmp.shadow_numbers[node.strings.term].labelForm = node.strings.form;
              } else if (state.tmp.group_context.tip.label_form) {
                state.tmp.shadow_numbers[node.strings.term].labelForm = state.tmp.group_context.tip.label_form;
              }
              state.tmp.shadow_numbers[node.strings.term].labelCapitalizeIfFirst = node.strings.capitalize_if_first;
              state.tmp.shadow_numbers[node.strings.term].labelDecorations = node.decorations.slice();
            }
            if (["locator", "number", "page"].indexOf(node.strings.term) > -1 && state.tmp.shadow_numbers[node.strings.term].label) {
              myterm = state.tmp.shadow_numbers[node.strings.term].label;
            }
            if (node.decorations && state.opt.development_extensions.csl_reverse_lookup_support) {
              node.decorations.reverse();
              node.decorations.push(["@showid", "true", node.cslid]);
              node.decorations.reverse();
            }
          }
        }
        return CSL2.castLabel(state, node, myterm, plural, CSL2.TOLERANT);
      };
      CSL2.castLabel = function(state, node, term, plural, mode) {
        var label_form = node.strings.form;
        var label_capitalize_if_first = node.strings.capitalize_if_first;
        if (state.tmp.group_context.tip.label_form) {
          if (label_form === "static") {
            state.tmp.group_context.tip.label_static = true;
          } else {
            label_form = state.tmp.group_context.tip.label_form;
          }
        }
        if (state.tmp.group_context.tip.label_capitalize_if_first) {
          label_capitalize_if_first = state.tmp.group_context.tip.label_capitalize_if_first;
        }
        var ret = state.getTerm(term, label_form, plural, false, mode, node.default_locale);
        if (label_capitalize_if_first) {
          ret = CSL2.Output.Formatters["capitalize-first"](state, ret);
        }
        if (state.tmp.strip_periods) {
          ret = ret.replace(/\./g, "");
        } else {
          for (var i = 0, ilen = node.decorations.length; i < ilen; i += 1) {
            if ("@strip-periods" === node.decorations[i][0] && "true" === node.decorations[i][1]) {
              ret = ret.replace(/\./g, "");
              break;
            }
          }
        }
        return ret;
      };
      CSL2.Node.name = {
        build: function(state, target) {
          var func;
          if ([CSL2.SINGLETON, CSL2.START].indexOf(this.tokentype) > -1) {
            var oldTmpRoot;
            if ("undefined" === typeof state.tmp.root) {
              oldTmpRoot = void 0;
              state.tmp.root = "citation";
            } else {
              oldTmpRoot = state.tmp.root;
            }
            if (state.inheritOpt(this, "et-al-subsequent-min") && state.inheritOpt(this, "et-al-subsequent-min") !== state.inheritOpt(this, "et-al-min")) {
              state.opt.update_mode = CSL2.POSITION;
            }
            if (state.inheritOpt(this, "et-al-subsequent-use-first") && state.inheritOpt(this, "et-al-subsequent-use-first") !== state.inheritOpt(this, "et-al-use-first")) {
              state.opt.update_mode = CSL2.POSITION;
            }
            state.tmp.root = oldTmpRoot;
            func = function(state2) {
              state2.tmp.etal_term = "et-al";
              state2.tmp.name_delimiter = state2.inheritOpt(this, "delimiter", "name-delimiter", ", ");
              state2.tmp["delimiter-precedes-et-al"] = state2.inheritOpt(this, "delimiter-precedes-et-al");
              if ("text" === state2.inheritOpt(this, "and")) {
                this.and_term = state2.getTerm("and", "long", 0);
              } else if ("symbol" === state2.inheritOpt(this, "and")) {
                if (state2.opt.development_extensions.expect_and_symbol_form) {
                  this.and_term = state2.getTerm("and", "symbol", 0);
                } else {
                  this.and_term = "&";
                }
              }
              state2.tmp.and_term = this.and_term;
              if (CSL2.STARTSWITH_ROMANESQUE_REGEXP.test(this.and_term)) {
                this.and_prefix_single = " ";
                this.and_prefix_multiple = ", ";
                if ("string" === typeof state2.tmp.name_delimiter) {
                  this.and_prefix_multiple = state2.tmp.name_delimiter;
                }
                this.and_suffix = " ";
              } else {
                this.and_prefix_single = "";
                this.and_prefix_multiple = "";
                this.and_suffix = "";
              }
              if (state2.inheritOpt(this, "delimiter-precedes-last") === "always") {
                this.and_prefix_single = state2.tmp.name_delimiter;
              } else if (state2.inheritOpt(this, "delimiter-precedes-last") === "never") {
                if (this.and_prefix_multiple) {
                  this.and_prefix_multiple = " ";
                }
              } else if (state2.inheritOpt(this, "delimiter-precedes-last") === "after-inverted-name") {
                if (this.and_prefix_single) {
                  this.and_prefix_single = state2.tmp.name_delimiter;
                }
                if (this.and_prefix_multiple) {
                  this.and_prefix_multiple = " ";
                }
              }
              this.and = {};
              if (state2.inheritOpt(this, "and")) {
                state2.output.append(this.and_term, "empty", true);
                this.and.single = state2.output.pop();
                this.and.single.strings.prefix = this.and_prefix_single;
                this.and.single.strings.suffix = this.and_suffix;
                state2.output.append(this.and_term, "empty", true);
                this.and.multiple = state2.output.pop();
                this.and.multiple.strings.prefix = this.and_prefix_multiple;
                this.and.multiple.strings.suffix = this.and_suffix;
              } else if (state2.tmp.name_delimiter) {
                this.and.single = new CSL2.Blob(state2.tmp.name_delimiter);
                this.and.single.strings.prefix = "";
                this.and.single.strings.suffix = "";
                this.and.multiple = new CSL2.Blob(state2.tmp.name_delimiter);
                this.and.multiple.strings.prefix = "";
                this.and.multiple.strings.suffix = "";
              }
              this.ellipsis = {};
              if (state2.inheritOpt(this, "et-al-use-last")) {
                this.ellipsis_term = "\u2026";
                this.ellipsis_prefix_single = " ";
                this.ellipsis_prefix_multiple = state2.inheritOpt(this, "delimiter", "name-delimiter", ", ");
                this.ellipsis_suffix = " ";
                this.ellipsis.single = new CSL2.Blob(this.ellipsis_term);
                this.ellipsis.single.strings.prefix = this.ellipsis_prefix_single;
                this.ellipsis.single.strings.suffix = this.ellipsis_suffix;
                this.ellipsis.multiple = new CSL2.Blob(this.ellipsis_term);
                this.ellipsis.multiple.strings.prefix = this.ellipsis_prefix_multiple;
                this.ellipsis.multiple.strings.suffix = this.ellipsis_suffix;
              }
              if ("undefined" === typeof state2.tmp["et-al-min"]) {
                state2.tmp["et-al-min"] = state2.inheritOpt(this, "et-al-min");
              }
              if ("undefined" === typeof state2.tmp["et-al-use-first"]) {
                state2.tmp["et-al-use-first"] = state2.inheritOpt(this, "et-al-use-first");
              }
              if ("undefined" === typeof state2.tmp["et-al-use-last"]) {
                state2.tmp["et-al-use-last"] = state2.inheritOpt(this, "et-al-use-last");
              }
              state2.nameOutput.name = this;
            };
            state.build.name_flag = true;
            this.execs.push(func);
          }
          target.push(this);
        }
      };
      CSL2.Node["name-part"] = {
        build: function(state) {
          state.build[this.strings.name] = this;
        }
      };
      CSL2.Node.names = {
        build: function(state, target) {
          var func;
          if (this.tokentype === CSL2.START || this.tokentype === CSL2.SINGLETON) {
            CSL2.Util.substituteStart.call(this, state, target);
            state.build.substitute_level.push(1);
          }
          if (this.tokentype === CSL2.SINGLETON) {
            state.build.names_variables[state.build.names_variables.length - 1].concat(this.variables);
            for (var i in this.variables) {
              var variable = this.variables[i];
              var name_labels = state.build.name_label[state.build.name_label.length - 1];
              if (Object.keys(name_labels).length) {
                name_labels[variable] = name_labels[Object.keys(name_labels)[0]];
              }
            }
            func = function(state2) {
              state2.nameOutput.reinit(this, this.variables_real[0]);
            };
            this.execs.push(func);
          }
          if (this.tokentype === CSL2.START) {
            state.build.names_flag = true;
            state.build.name_flag = false;
            state.build.names_level += 1;
            state.build.names_variables.push(this.variables);
            state.build.name_label.push({});
            func = function(state2) {
              state2.tmp.can_substitute.push(true);
              state2.tmp.name_node = {};
              state2.tmp.name_node.children = [];
              state2.nameOutput.init(this);
            };
            this.execs.push(func);
          }
          if (this.tokentype === CSL2.END) {
            for (var i = 0, ilen = 3; i < ilen; i += 1) {
              var key = ["family", "given", "et-al"][i];
              this[key] = state.build[key];
              if (state.build.names_level === 1) {
                state.build[key] = void 0;
              }
            }
            this.label = state.build.name_label[state.build.name_label.length - 1];
            state.build.names_level += -1;
            state.build.names_variables.pop();
            state.build.name_label.pop();
            func = function(state2) {
              if (state2.tmp.etal_node) {
                this.etal_style = state2.tmp.etal_node;
              } else {
                this.etal_style = "empty";
              }
              this.etal_term = state2.getTerm(state2.tmp.etal_term, "long", 0);
              this.etal_prefix_single = " ";
              this.etal_prefix_multiple = state2.tmp.name_delimiter;
              if (state2.tmp["delimiter-precedes-et-al"] === "always") {
                this.etal_prefix_single = state2.tmp.name_delimiter;
              } else if (state2.tmp["delimiter-precedes-et-al"] === "never") {
                this.etal_prefix_multiple = " ";
              } else if (state2.tmp["delimiter-precedes-et-al"] === "after-inverted-name") {
                this.etal_prefix_single = state2.tmp.name_delimiter;
                this.etal_prefix_multiple = " ";
              }
              this.etal_suffix = "";
              if (!CSL2.STARTSWITH_ROMANESQUE_REGEXP.test(this.etal_term)) {
                if (this.etal_prefix_single === " ") {
                  this.etal_prefix_single = "";
                }
                if (this.etal_prefix_multiple === " ") {
                  this.etal_prefix_multiple = "";
                }
                if (this.etal_suffix === " ") {
                  this.etal_suffix = "";
                }
              }
              for (var i2 = 0, ilen2 = 3; i2 < ilen2; i2 += 1) {
                var key2 = ["family", "given"][i2];
                state2.nameOutput[key2] = this[key2];
              }
              state2.nameOutput["with"] = this["with"];
              var mywith = "with";
              var with_default_prefix = "";
              var with_suffix = "";
              if (CSL2.STARTSWITH_ROMANESQUE_REGEXP.test(mywith)) {
                with_default_prefix = " ";
                with_suffix = " ";
              }
              var thewith = {};
              thewith.single = new CSL2.Blob(mywith);
              thewith.single.strings.suffix = with_suffix;
              thewith.multiple = new CSL2.Blob(mywith);
              thewith.multiple.strings.suffix = with_suffix;
              if (state2.inheritOpt(state2.nameOutput.name, "delimiter-precedes-last") === "always") {
                thewith.single.strings.prefix = state2.inheritOpt(this, "delimiter", "names-delimiter");
                thewith.multiple.strings.prefix = state2.inheritOpt(this, "delimiter", "names-delimiter");
              } else if (state2.inheritOpt(state2.nameOutput.name, "delimiter-precedes-last") === "contextual") {
                thewith.single.strings.prefix = with_default_prefix;
                thewith.multiple.strings.prefix = state2.inheritOpt(this, "delimiter", "names-delimiter");
              } else if (state2.inheritOpt(state2.nameOutput.name, "delimiter-precedes-last") === "after-inverted-name") {
                thewith.single.strings.prefix = state2.inheritOpt(this, "delimiter", "names-delimiter");
                thewith.multiple.strings.prefix = with_default_prefix;
              } else {
                thewith.single.strings.prefix = with_default_prefix;
                thewith.multiple.strings.prefix = with_default_prefix;
              }
              state2.nameOutput["with"] = thewith;
              state2.nameOutput.label = this.label;
              state2.nameOutput.etal_style = this.etal_style;
              state2.nameOutput.etal_term = this.etal_term;
              state2.nameOutput.etal_prefix_single = this.etal_prefix_single;
              state2.nameOutput.etal_prefix_multiple = this.etal_prefix_multiple;
              state2.nameOutput.etal_suffix = this.etal_suffix;
              state2.nameOutput.outputNames();
              state2.tmp["et-al-use-first"] = void 0;
              state2.tmp["et-al-min"] = void 0;
              state2.tmp["et-al-use-last"] = void 0;
            };
            this.execs.push(func);
            func = function(state2) {
              if (!state2.tmp.can_substitute.pop()) {
                state2.tmp.can_substitute.replace(false, CSL2.LITERAL);
              }
              if (state2.tmp.can_substitute.mystack.length === 1) {
                state2.tmp.can_block_substitute = false;
              }
            };
            this.execs.push(func);
            state.build.name_flag = false;
          }
          target.push(this);
          if (this.tokentype === CSL2.END || this.tokentype === CSL2.SINGLETON) {
            state.build.substitute_level.pop();
            CSL2.Util.substituteEnd.call(this, state, target);
          }
        }
      };
      CSL2.Node.number = {
        build: function(state, target) {
          var func;
          CSL2.Util.substituteStart.call(this, state, target);
          if (this.strings.form === "roman") {
            this.formatter = state.fun.romanizer;
          } else if (this.strings.form === "ordinal") {
            this.formatter = state.fun.ordinalizer;
          } else if (this.strings.form === "long-ordinal") {
            this.formatter = state.fun.long_ordinalizer;
          }
          if ("undefined" === typeof this.successor_prefix) {
            this.successor_prefix = state[state.build.area].opt.layout_delimiter;
          }
          if ("undefined" === typeof this.splice_prefix) {
            this.splice_prefix = state[state.build.area].opt.layout_delimiter;
          }
          func = function(state2, Item, item) {
            if (this.variables.length === 0) {
              return;
            }
            var varname;
            varname = this.variables[0];
            if ("undefined" === typeof item) {
              var item = {};
            }
            if (["locator", "locator-extra"].indexOf(varname) > -1) {
              if (state2.tmp.just_looking) {
                return;
              }
              if (!item[varname]) {
                return;
              }
            } else {
              if (!Item[varname]) {
                return;
              }
            }
            if (varname === "collection-number" && Item.type === "legal_case") {
              state2.tmp.renders_collection_number = true;
            }
            var node = this;
            if (state2.tmp.group_context.tip.force_suppress) {
              return false;
            }
            if (["locator", "locator-extra"].indexOf(varname) > -1) {
              state2.processNumber.call(state2, node, item, varname, Item.type);
            } else {
              if (!state2.tmp.group_context.tip.condition && Item[varname]) {
                state2.tmp.just_did_number = ("" + Item[varname]).match(/[0-9]$/);
              }
              state2.processNumber.call(state2, node, Item, varname, Item.type);
            }
            if (this.substring) {
              var val = Item[varname].slice(this.substring);
              state2.output.append(val, node);
            } else {
              CSL2.Util.outputNumericField(state2, varname, Item.id);
            }
            if (["locator", "locator-extra"].indexOf(this.variables_real[0]) > -1 && !state2.tmp.just_looking) {
              state2.tmp.done_vars.push(this.variables_real[0]);
              state2.tmp.group_context.tip.done_vars.push(this.variables_real[0]);
            }
          };
          this.execs.push(func);
          target.push(this);
          CSL2.Util.substituteEnd.call(this, state, target);
        }
      };
      CSL2.Node.sort = {
        build: function(state, target) {
          target = state[state.build.root + "_sort"].tokens;
          if (this.tokentype === CSL2.START) {
            if (state.build.area === "citation") {
              state.opt.sort_citations = true;
            }
            state.build.area = state.build.root + "_sort";
            state.build.extension = "_sort";
            var func = function(state2, Item) {
              if (state2.opt.has_layout_locale) {
                var langspec = CSL2.localeResolve(Item.language, state2.opt["default-locale"][0]);
                var sort_locales = state2[state2.tmp.area.slice(0, -5)].opt.sort_locales;
                var langForItem;
                for (var i = 0, ilen = sort_locales.length; i < ilen; i += 1) {
                  langForItem = sort_locales[i][langspec.bare];
                  if (!langForItem) {
                    langForItem = sort_locales[i][langspec.best];
                  }
                  if (langForItem) {
                    break;
                  }
                }
                if (!langForItem) {
                  langForItem = state2.opt["default-locale"][0];
                }
                state2.tmp.lang_sort_hold = state2.opt.lang;
                state2.opt.lang = langForItem;
              }
            };
            this.execs.push(func);
          }
          if (this.tokentype === CSL2.END) {
            state.build.area = state.build.root;
            state.build.extension = "";
            var func = function(state2) {
              if (state2.opt.has_layout_locale) {
                state2.opt.lang = state2.tmp.lang_sort_hold;
                delete state2.tmp.lang_sort_hold;
              }
            };
            this.execs.push(func);
          }
          target.push(this);
        }
      };
      CSL2.Node.substitute = {
        build: function(state, target) {
          var func;
          if (this.tokentype === CSL2.START) {
            var choose_start = new CSL2.Token("choose", CSL2.START);
            CSL2.Node.choose.build.call(choose_start, state, target);
            var if_singleton = new CSL2.Token("if", CSL2.SINGLETON);
            func = function() {
              if (state.tmp.value.length && !state.tmp.common_term_match_fail) {
                return true;
              }
              return false;
            };
            if_singleton.tests = [func];
            if_singleton.test = state.fun.match.any(if_singleton, state, if_singleton.tests);
            target.push(if_singleton);
            func = function(state2) {
              state2.tmp.can_block_substitute = true;
              if (state2.tmp.value.length && !state2.tmp.common_term_match_fail) {
                state2.tmp.can_substitute.replace(false, CSL2.LITERAL);
              }
              state2.tmp.common_term_match_fail = false;
            };
            this.execs.push(func);
            target.push(this);
          }
          if (this.tokentype === CSL2.END) {
            target.push(this);
            var choose_end = new CSL2.Token("choose", CSL2.END);
            CSL2.Node.choose.build.call(choose_end, state, target);
          }
        }
      };
      CSL2.Node.text = {
        build: function(state, target) {
          var func, form, plural, id, num, number, formatter, firstoutput, specialdelimiter, label, suffix, term;
          if (this.postponed_macro) {
            var group_start = CSL2.Util.cloneToken(this);
            group_start.name = "group";
            group_start.tokentype = CSL2.START;
            CSL2.Node.group.build.call(group_start, state, target);
            CSL2.expandMacro.call(state, this, target);
            var group_end = CSL2.Util.cloneToken(this);
            group_end.name = "group";
            group_end.tokentype = CSL2.END;
            if (this.postponed_macro === "juris-locator-label") {
              group_end.isJurisLocatorLabel = true;
            }
            CSL2.Node.group.build.call(group_end, state, target);
          } else {
            CSL2.Util.substituteStart.call(this, state, target);
            if (!this.variables_real) {
              this.variables_real = [];
            }
            if (!this.variables) {
              this.variables = [];
            }
            form = "long";
            plural = 0;
            if (this.strings.form) {
              form = this.strings.form;
            }
            if (this.strings.plural) {
              plural = this.strings.plural;
            }
            if ("citation-number" === this.variables_real[0] || "year-suffix" === this.variables_real[0] || "citation-label" === this.variables_real[0]) {
              if (this.variables_real[0] === "citation-number") {
                if (state.build.root === "citation") {
                  state.opt.update_mode = CSL2.NUMERIC;
                }
                if (state.build.root === "bibliography") {
                  state.opt.bib_mode = CSL2.NUMERIC;
                }
                if ("citation-number" === state[state.tmp.area].opt.collapse) {
                  this.range_prefix = state.getTerm("citation-range-delimiter");
                }
                this.successor_prefix = state[state.build.area].opt.layout_delimiter;
                this.splice_prefix = state[state.build.area].opt.layout_delimiter;
                func = function(state2, Item, item) {
                  id = "" + Item.id;
                  if (!state2.tmp.just_looking) {
                    if (state2.tmp.area.slice(-5) === "_sort" && this.variables[0] === "citation-number") {
                      if (state2.tmp.area === "bibliography_sort") {
                        state2.tmp.group_context.tip.done_vars.push("citation-number");
                      }
                      if (state2.tmp.area === "citation_sort" && state2.bibliography_sort.tmp.citation_number_map) {
                        var num2 = state2.bibliography_sort.tmp.citation_number_map[state2.registry.registry[Item.id].seq];
                      } else {
                        var num2 = state2.registry.registry[Item.id].seq;
                      }
                      if (num2) {
                        num2 = CSL2.Util.padding("" + num2);
                      }
                      state2.output.append(num2, this);
                      return;
                    }
                    if (item && item["author-only"]) {
                      state2.tmp.element_trace.replace("suppress-me");
                    }
                    if (state2.tmp.area !== "bibliography_sort" && state2.bibliography_sort.tmp.citation_number_map && state2.bibliography_sort.opt.citation_number_sort_direction === CSL2.DESCENDING) {
                      num2 = state2.bibliography_sort.tmp.citation_number_map[state2.registry.registry[id].seq];
                    } else {
                      num2 = state2.registry.registry[id].seq;
                    }
                    if (state2.opt.citation_number_slug) {
                      state2.output.append(state2.opt.citation_number_slug, this);
                    } else {
                      number = new CSL2.NumericBlob(state2, false, num2, this, Item.id);
                      if (state2.tmp.in_cite_predecessor) {
                        number.suppress_splice_prefix = true;
                      }
                      state2.output.append(number, "literal");
                    }
                  }
                };
                this.execs.push(func);
              } else if (this.variables_real[0] === "year-suffix") {
                state.opt.has_year_suffix = true;
                if (state[state.tmp.area].opt.collapse === "year-suffix-ranged") {
                  this.range_prefix = state.getTerm("citation-range-delimiter");
                }
                this.successor_prefix = state[state.build.area].opt.layout_delimiter;
                if (state[state.tmp.area].opt["year-suffix-delimiter"]) {
                  this.successor_prefix = state[state.build.area].opt["year-suffix-delimiter"];
                }
                func = function(state2, Item) {
                  if (state2.registry.registry[Item.id] && state2.registry.registry[Item.id].disambig.year_suffix !== false && !state2.tmp.just_looking) {
                    num = parseInt(state2.registry.registry[Item.id].disambig.year_suffix, 10);
                    if (state2[state2.tmp.area].opt.cite_group_delimiter) {
                      this.successor_prefix = state2[state2.tmp.area].opt.cite_group_delimiter;
                    }
                    number = new CSL2.NumericBlob(state2, false, num, this, Item.id);
                    formatter = new CSL2.Util.Suffixator(CSL2.SUFFIX_CHARS);
                    number.setFormatter(formatter);
                    state2.output.append(number, "literal");
                    firstoutput = false;
                    for (var i = 0, ilen = state2.tmp.group_context.mystack.length; i < ilen; i++) {
                      var flags = state2.tmp.group_context.mystack[i];
                      if (!flags.variable_success && (flags.variable_attempt || !flags.variable_attempt && !flags.term_intended)) {
                        firstoutput = true;
                        break;
                      }
                    }
                    specialdelimiter = state2[state2.tmp.area].opt["year-suffix-delimiter"];
                    if (firstoutput && specialdelimiter && !state2.tmp.sort_key_flag) {
                      state2.tmp.splice_delimiter = state2[state2.tmp.area].opt["year-suffix-delimiter"];
                    }
                  }
                };
                this.execs.push(func);
              } else if (this.variables_real[0] === "citation-label") {
                if (state.build.root === "bibliography") {
                  state.opt.bib_mode = CSL2.TRIGRAPH;
                }
                state.opt.has_year_suffix = true;
                func = function(state2, Item) {
                  label = Item["citation-label"];
                  if (!label) {
                    label = state2.getCitationLabel(Item);
                  }
                  if (!state2.tmp.just_looking) {
                    suffix = "";
                    if (state2.registry.registry[Item.id] && state2.registry.registry[Item.id].disambig.year_suffix !== false) {
                      num = parseInt(state2.registry.registry[Item.id].disambig.year_suffix, 10);
                      suffix = state2.fun.suffixator.format(num);
                    }
                    label += suffix;
                  }
                  state2.output.append(label, this);
                };
                this.execs.push(func);
              }
            } else {
              if (this.strings.term) {
                func = function(state2, Item) {
                  var gender = state2.opt.gender[Item.type];
                  var term2 = this.strings.term;
                  term2 = state2.getTerm(term2, form, plural, gender, CSL2.TOLERANT, this.default_locale);
                  var myterm;
                  if (term2 !== "") {
                    state2.tmp.group_context.tip.term_intended = true;
                  }
                  CSL2.UPDATE_GROUP_CONTEXT_CONDITION(state2, term2, null, this);
                  if (!state2.tmp.term_predecessor && !(state2.opt["class"] === "in-text" && state2.tmp.area === "citation")) {
                    myterm = CSL2.Output.Formatters["capitalize-first"](state2, term2);
                  } else {
                    myterm = term2;
                  }
                  if (state2.tmp.strip_periods) {
                    myterm = myterm.replace(/\./g, "");
                  } else {
                    for (var i = 0, ilen = this.decorations.length; i < ilen; i += 1) {
                      if ("@strip-periods" === this.decorations[i][0] && "true" === this.decorations[i][1]) {
                        myterm = myterm.replace(/\./g, "");
                        break;
                      }
                    }
                  }
                  state2.output.append(myterm, this);
                  if (state2.tmp.can_block_substitute) {
                    state2.tmp.can_substitute.replace(false, CSL2.LITERAL);
                  }
                };
                this.execs.push(func);
                state.build.term = false;
                state.build.form = false;
                state.build.plural = false;
              } else if (this.variables_real.length) {
                func = function(state2, Item) {
                  if (this.variables_real[0] !== "locator") {
                    state2.tmp.have_collapsed = false;
                  }
                  if (!state2.tmp.group_context.tip.condition && Item[this.variables[0]]) {
                    state2.tmp.just_did_number = false;
                  }
                  var val = Item[this.variables[0]];
                  if (val && !state2.tmp.group_context.tip.condition) {
                    if (("" + val).slice(-1).match(/[0-9]/)) {
                      state2.tmp.just_did_number = true;
                    } else {
                      state2.tmp.just_did_number = false;
                    }
                  }
                };
                this.execs.push(func);
                if (CSL2.MULTI_FIELDS.indexOf(this.variables_real[0]) > -1 || this.variables_real[0].indexOf("-main") > -1 || this.variables_real[0].indexOf("-sub") > -1 || ["language-name", "language-name-original"].indexOf(this.variables_real[0]) > -1) {
                  var abbrevfam = this.variables[0];
                  var abbrfall = false;
                  var altvar = false;
                  var transfall = false;
                  if (form === "short") {
                    if (this.variables_real[0].slice(-6) !== "-short") {
                      altvar = this.variables_real[0] + "-short";
                    }
                  } else {
                    abbrevfam = false;
                  }
                  if (state.build.extension) {
                    transfall = true;
                  } else {
                    transfall = true;
                    abbrfall = true;
                  }
                  func = state.transform.getOutputFunction(this.variables, abbrevfam, abbrfall, altvar, transfall);
                } else {
                  if (CSL2.CITE_FIELDS.indexOf(this.variables_real[0]) > -1) {
                    func = function(state2, Item, item) {
                      if (item && item[this.variables[0]]) {
                        state2.processNumber(this, item, this.variables[0], Item.type);
                        CSL2.Util.outputNumericField(state2, this.variables[0], Item.id);
                        if (["locator", "locator-extra"].indexOf(this.variables_real[0]) > -1 && !state2.tmp.just_looking) {
                          state2.tmp.done_vars.push(this.variables_real[0]);
                        }
                      }
                    };
                  } else if (["page", "page-first", "chapter-number", "collection-number", "edition", "issue", "number", "number-of-pages", "number-of-volumes", "volume"].indexOf(this.variables_real[0]) > -1) {
                    func = function(state2, Item) {
                      state2.processNumber(this, Item, this.variables[0], Item.type);
                      CSL2.Util.outputNumericField(state2, this.variables[0], Item.id);
                    };
                  } else if (["URL", "DOI"].indexOf(this.variables_real[0]) > -1) {
                    func = function(state2, Item) {
                      var value;
                      if (this.variables[0]) {
                        value = state2.getVariable(Item, this.variables[0], form);
                        if (value) {
                          if (this.variables[0] === "URL" && form === "short") {
                            value = value.replace(/(.*\.[^\/]+)\/.*/, "$1");
                            if (value.match(/\/\/www\./)) {
                              value = value.replace(/https?:\/\//, "");
                            }
                          }
                          if (state2.opt.development_extensions.wrap_url_and_doi) {
                            if (!this.decorations.length || this.decorations[0][0] !== "@" + this.variables[0]) {
                              var clonetoken = CSL2.Util.cloneToken(this);
                              var groupblob = new CSL2.Blob(null, null, "url-wrapper");
                              groupblob.decorations.push(["@DOI", "true"]);
                              if (this.variables_real[0] === "DOI") {
                                var prefix;
                                if (this.strings.prefix && this.strings.prefix.match(/^.*https:\/\/doi\.org\/$/)) {
                                  value = value.replace(/^https?:\/\/doi\.org\//, "");
                                  if (value.match(/^https?:\/\//)) {
                                    prefix = "";
                                  } else {
                                    prefix = "https://doi.org/";
                                  }
                                  clonetoken.strings.prefix = this.strings.prefix.slice(0, clonetoken.strings.prefix.length - 16);
                                }
                                var prefixblob = new CSL2.Blob(prefix);
                                var valueblob = new CSL2.Blob(value);
                                groupblob.push(prefixblob);
                                groupblob.push(valueblob);
                                state2.output.append(groupblob, clonetoken, false, false, true);
                              } else {
                                var valueblob = new CSL2.Blob(value);
                                groupblob.push(valueblob);
                                state2.output.append(groupblob, clonetoken, false, false, true);
                              }
                            } else {
                              state2.output.append(value, this, false, false, true);
                            }
                          } else {
                            if (this.decorations.length) {
                              for (var i = this.decorations.length - 1; i > -1; i--) {
                                if (this.decorations[i][0] === "@" + this.variables[0]) {
                                  this.decorations = this.decorations.slice(0, i).concat(this.decorations.slice(i + 1));
                                }
                              }
                            }
                            state2.output.append(value, this, false, false, true);
                          }
                        }
                      }
                    };
                  } else if (this.variables_real[0] === "section") {
                    func = function(state2, Item) {
                      var value;
                      value = state2.getVariable(Item, this.variables[0], form);
                      if (value) {
                        state2.output.append(value, this);
                      }
                    };
                  } else if (this.variables_real[0] === "hereinafter") {
                    func = function(state2, Item) {
                      var value = state2.transform.abbrevs["default"]["hereinafter"][Item.id];
                      if (value) {
                        state2.output.append(value, this);
                        state2.tmp.group_context.tip.variable_success = true;
                      }
                    };
                  } else {
                    func = function(state2, Item) {
                      var value;
                      if (this.variables[0]) {
                        value = state2.getVariable(Item, this.variables[0], form);
                        if (value) {
                          value = "" + value;
                          value = value.split("\\").join("");
                          state2.output.append(value, this);
                        }
                      }
                    };
                  }
                }
                this.execs.push(func);
              } else if (this.strings.value) {
                func = function(state2) {
                  state2.tmp.group_context.tip.term_intended = true;
                  CSL2.UPDATE_GROUP_CONTEXT_CONDITION(state2, this.strings.value, true, this);
                  state2.output.append(this.strings.value, this);
                  if (state2.tmp.can_block_substitute) {
                    state2.tmp.can_substitute.replace(false, CSL2.LITERAL);
                  }
                };
                this.execs.push(func);
              }
            }
            target.push(this);
            CSL2.Util.substituteEnd.call(this, state, target);
          }
        }
      };
      CSL2.Node.intext = {
        build: function(state, target) {
          if (this.tokentype === CSL2.START) {
            state.build.area = "intext";
            state.build.root = "intext";
            state.build.extension = "";
            var func = function(state2, Item) {
              state2.tmp.area = "intext";
              state2.tmp.root = "intext";
              state2.tmp.extension = "";
            };
            this.execs.push(func);
          }
          if (this.tokentype === CSL2.END) {
            state.intext_sort = {
              opt: {
                sort_directions: state.citation_sort.opt.sort_directions
              }
            };
            state.intext.srt = state.citation.srt;
          }
          target.push(this);
        }
      };
      CSL2.Attributes = {};
      CSL2.Attributes["@disambiguate"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        if (arg === "true") {
          state.opt.has_disambiguate = true;
          var func = function(Item) {
            if (state.tmp.area === "bibliography") {
              if (state.tmp.disambiguate_count < state.registry.registry[Item.id].disambig.disambiguate) {
                state.tmp.disambiguate_count += 1;
                return true;
              }
            } else {
              state.tmp.disambiguate_maxMax += 1;
              if (state.tmp.disambig_settings.disambiguate && state.tmp.disambiguate_count < state.tmp.disambig_settings.disambiguate) {
                state.tmp.disambiguate_count += 1;
                return true;
              }
            }
            return false;
          };
          this.tests.push(func);
        } else if (arg === "check-ambiguity-and-backreference") {
          var func = function(Item) {
            if (state.registry.registry[Item.id].disambig.disambiguate && state.registry.registry[Item.id]["citation-count"] > 1) {
              return true;
            }
            return false;
          };
          this.tests.push(func);
        }
      };
      CSL2.Attributes["@is-numeric"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var variables = arg.split(/\s+/);
        var maketest = function(variable) {
          return function(Item, item) {
            var myitem = Item;
            if (item && ["locator", "locator-extra"].indexOf(variable) > -1) {
              myitem = item;
            }
            if (!myitem[variable]) {
              return false;
            }
            if (CSL2.NUMERIC_VARIABLES.indexOf(variable) > -1) {
              if (!state.tmp.shadow_numbers[variable]) {
                state.processNumber(false, myitem, variable, Item.type);
              }
              if (state.tmp.shadow_numbers[variable].numeric) {
                return true;
              }
            } else if (["title", "version"].indexOf(variable) > -1) {
              if (myitem[variable].slice(-1) === "" + parseInt(myitem[variable].slice(-1), 10)) {
                return true;
              }
            }
            return false;
          };
        };
        for (var i = 0; i < variables.length; i += 1) {
          this.tests.push(maketest(variables[i]));
        }
      };
      CSL2.Attributes["@is-uncertain-date"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var variables = arg.split(/\s+/);
        var maketest = function(myvariable) {
          return function(Item) {
            if (Item[myvariable] && Item[myvariable].circa) {
              return true;
            } else {
              return false;
            }
          };
        };
        for (var i = 0, ilen = variables.length; i < ilen; i += 1) {
          this.tests.push(maketest(variables[i]));
        }
      };
      CSL2.Attributes["@locator"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var trylabels = arg.replace("sub verbo", "sub-verbo");
        trylabels = trylabels.split(/\s+/);
        var maketest = function(trylabel) {
          return function(Item, item) {
            var label;
            state.processNumber(false, item, "locator");
            label = state.tmp.shadow_numbers.locator.label;
            if (label && trylabel === label) {
              return true;
            } else {
              return false;
            }
          };
        };
        for (var i = 0, ilen = trylabels.length; i < ilen; i += 1) {
          this.tests.push(maketest(trylabels[i]));
        }
      };
      CSL2.Attributes["@position"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var tryposition;
        state.opt.update_mode = CSL2.POSITION;
        var trypositions = arg.split(/\s+/);
        var testSubsequentNear = function(Item, item) {
          if (item && CSL2.POSITION_MAP[item.position] >= CSL2.POSITION_MAP[CSL2.POSITION_SUBSEQUENT] && item["near-note"]) {
            return true;
          }
          return false;
        };
        var testSubsequentNotNear = function(Item, item) {
          if (item && CSL2.POSITION_MAP[item.position] == CSL2.POSITION_MAP[CSL2.POSITION_SUBSEQUENT] && !item["near-note"]) {
            return true;
          }
          return false;
        };
        var maketest = function(tryposition2) {
          return function(Item, item) {
            if (state.tmp.area === "bibliography") {
              return false;
            }
            if (item && "undefined" === typeof item.position) {
              item.position = 0;
            }
            if (item && typeof item.position === "number") {
              if (item.position === 0 && tryposition2 === 0) {
                return true;
              } else if (tryposition2 > 0 && CSL2.POSITION_MAP[item.position] >= CSL2.POSITION_MAP[tryposition2]) {
                return true;
              }
            } else if (tryposition2 === 0) {
              return true;
            }
            return false;
          };
        };
        for (var i = 0, ilen = trypositions.length; i < ilen; i += 1) {
          var tryposition = trypositions[i];
          if (tryposition === "first") {
            tryposition = CSL2.POSITION_FIRST;
          } else if (tryposition === "container-subsequent") {
            tryposition = CSL2.POSITION_CONTAINER_SUBSEQUENT;
          } else if (tryposition === "subsequent") {
            tryposition = CSL2.POSITION_SUBSEQUENT;
          } else if (tryposition === "ibid") {
            tryposition = CSL2.POSITION_IBID;
          } else if (tryposition === "ibid-with-locator") {
            tryposition = CSL2.POSITION_IBID_WITH_LOCATOR;
          }
          if ("near-note" === tryposition) {
            this.tests.push(testSubsequentNear);
          } else if ("far-note" === tryposition) {
            this.tests.push(testSubsequentNotNear);
          } else {
            this.tests.push(maketest(tryposition));
          }
        }
      };
      CSL2.Attributes["@type"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var types = arg.split(/\s+/);
        var maketest = function(mytype) {
          return function(Item) {
            var ret = Item.type === mytype;
            if (ret) {
              return true;
            } else {
              return false;
            }
          };
        };
        var tests = [];
        for (var i = 0, ilen = types.length; i < ilen; i += 1) {
          tests.push(maketest(types[i]));
        }
        this.tests.push(state.fun.match.any(this, state, tests));
      };
      CSL2.Attributes["@variable"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var func;
        this.variables = arg.split(/\s+/);
        this.variables_real = this.variables.slice();
        if ("label" === this.name && this.variables[0]) {
          this.strings.term = this.variables[0];
        } else if (["names", "date", "text", "number"].indexOf(this.name) > -1) {
          func = function(state2, Item, item) {
            for (var i2 = this.variables.length - 1; i2 > -1; i2 += -1) {
              this.variables.pop();
            }
            for (var i2 = 0, ilen2 = this.variables_real.length; i2 < ilen2; i2++) {
              if (state2.tmp.done_vars.indexOf(this.variables_real[i2]) === -1) {
                this.variables.push(this.variables_real[i2]);
              }
              if (state2.tmp.can_block_substitute) {
                state2.tmp.done_vars.push(this.variables_real[i2]);
              }
            }
          };
          this.execs.push(func);
          func = function(state2, Item, item) {
            var output = false;
            for (var i2 = 0, ilen2 = this.variables.length; i2 < ilen2; i2++) {
              var variable = this.variables[i2];
              if (["authority", "committee"].indexOf(variable) > -1 && "string" === typeof Item[variable] && "names" === this.name) {
                var isValid = true;
                var rawNames = Item[variable].split(/\s*;\s*/);
                var rawMultiNames = {};
                if (Item.multi && Item.multi._keys[variable]) {
                  for (var langTag in Item.multi._keys[variable]) {
                    rawMultiNames[langTag] = Item.multi._keys[variable][langTag].split(/\s*;\s*/);
                    if (rawMultiNames[langTag].length !== rawNames.length) {
                      isValid = false;
                      break;
                    }
                  }
                }
                if (!isValid) {
                  rawNames = [Item[variable]];
                  rawMultiNames = Item.multi._keys[variable];
                }
                for (var j = 0, jlen = rawNames.length; j < jlen; j++) {
                  var creatorParent = {
                    literal: rawNames[j],
                    multi: {
                      _key: {}
                    }
                  };
                  for (var langTag in rawMultiNames) {
                    var creatorChild = {
                      literal: rawMultiNames[langTag][j]
                    };
                    creatorParent.multi._key[langTag] = creatorChild;
                  }
                  rawNames[j] = creatorParent;
                }
                Item[variable] = rawNames;
              }
              if (this.strings.form === "short" && !Item[variable]) {
                if (variable === "title") {
                  variable = "title-short";
                } else if (variable === "container-title") {
                  variable = "container-title-short";
                }
              }
              if (variable === "year-suffix") {
                output = true;
                break;
              } else if (CSL2.DATE_VARIABLES.indexOf(variable) > -1) {
                if (state2.opt.development_extensions.locator_date_and_revision && "locator-date" === variable) {
                  output = true;
                  break;
                }
                if (Item[variable]) {
                  for (var key in Item[variable]) {
                    if (this.dateparts.indexOf(key) === -1 && "literal" !== key) {
                      continue;
                    }
                    if (Item[variable][key]) {
                      output = true;
                      break;
                    }
                  }
                  if (output) {
                    break;
                  }
                }
              } else if ("locator" === variable) {
                if (item && item.locator) {
                  output = true;
                }
                break;
              } else if ("locator-extra" === variable) {
                if (item && item["locator-extra"]) {
                  output = true;
                }
                break;
              } else if (["citation-number", "citation-label"].indexOf(variable) > -1) {
                output = true;
                break;
              } else if ("first-reference-note-number" === variable) {
                if (item && item["first-reference-note-number"]) {
                  output = true;
                }
                break;
              } else if ("first-container-reference-note-number" === variable) {
                if (item && item["first-container-reference-note-number"]) {
                  output = true;
                }
                break;
              } else if ("hereinafter" === variable) {
                if (state2.transform.abbrevs["default"].hereinafter[Item.id] && state2.sys.getAbbreviation && Item.id) {
                  output = true;
                }
                break;
              } else if ("object" === typeof Item[variable]) {
                break;
              } else if ("string" === typeof Item[variable] && Item[variable]) {
                output = true;
                break;
              } else if ("number" === typeof Item[variable]) {
                output = true;
                break;
              }
              if (output) {
                break;
              }
            }
            if (output) {
              for (var i2 = 0, ilen2 = this.variables_real.length; i2 < ilen2; i2++) {
                var variable = this.variables_real[i2];
                if (variable !== "citation-number" || state2.tmp.area !== "bibliography") {
                  state2.tmp.cite_renders_content = true;
                }
                state2.tmp.group_context.tip.variable_success = true;
                if (state2.tmp.can_substitute.value() && state2.tmp.area === "bibliography" && "string" === typeof Item[variable]) {
                  state2.tmp.name_node.top = state2.output.current.value();
                  state2.tmp.rendered_name.push(Item[variable]);
                }
              }
              state2.tmp.can_substitute.replace(false, CSL2.LITERAL);
            } else {
              state2.tmp.group_context.tip.variable_attempt = true;
            }
          };
          this.execs.push(func);
        } else if (["if", "else-if", "condition"].indexOf(this.name) > -1) {
          var maketest = function(variable) {
            return function(Item, item) {
              var myitem = Item;
              if (item && ["locator", "locator-extra", "first-reference-note-number", "first-container-reference-note-number", "locator-date"].indexOf(variable) > -1) {
                myitem = item;
              }
              if (variable === "hereinafter" && state.sys.getAbbreviation && myitem.id) {
                if (state.transform.abbrevs["default"].hereinafter[myitem.id]) {
                  return true;
                }
              } else if (myitem[variable]) {
                if ("number" === typeof myitem[variable] || "string" === typeof myitem[variable]) {
                  return true;
                } else if ("object" === typeof myitem[variable]) {
                  for (var key in myitem[variable]) {
                    if (myitem[variable][key]) {
                      return true;
                    }
                  }
                }
              }
              return false;
            };
          };
          for (var i = 0, ilen = this.variables.length; i < ilen; i += 1) {
            this.tests.push(maketest(this.variables[i]));
          }
        }
      };
      CSL2.Attributes["@page"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var trylabels = arg.replace("sub verbo", "sub-verbo");
        trylabels = trylabels.split(/\s+/);
        var maketest = function(trylabel) {
          return function(Item) {
            var label;
            state.processNumber(false, Item, "page", Item.type);
            if (!state.tmp.shadow_numbers.page.label) {
              label = "page";
            } else if (state.tmp.shadow_numbers.page.label === "sub verbo") {
              label = "sub-verbo";
            } else {
              label = state.tmp.shadow_numbers.page.label;
            }
            if (state.tmp.shadow_numbers.page.values.length > 0) {
              if (state.tmp.shadow_numbers.page.values[0].gotosleepability) {
                state.tmp.shadow_numbers.page.values[0].labelVisibility = false;
              }
            }
            if (trylabel === label) {
              return true;
            } else {
              return false;
            }
          };
        };
        for (var i = 0, ilen = trylabels.length; i < ilen; i += 1) {
          this.tests.push(maketest(trylabels[i]));
        }
      };
      CSL2.Attributes["@number"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var trylabels = arg.split(/\s+/);
        var maketest = function(trylabel) {
          return function(Item) {
            var label;
            state.processNumber(false, Item, "number", Item.type);
            if (!state.tmp.shadow_numbers.number.label) {
              label = "number";
            } else {
              label = state.tmp.shadow_numbers.number.label;
            }
            if (trylabel === label) {
              return true;
            } else {
              return false;
            }
          };
        };
        for (var i = 0, ilen = trylabels.length; i < ilen; i += 1) {
          this.tests.push(maketest(trylabels[i]));
        }
      };
      CSL2.Attributes["@jurisdiction"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var tryjurisdictions = arg.split(/\s+/);
        var maketests = function(tryjurisdictions2) {
          return function(Item) {
            if (!Item.jurisdiction) {
              return false;
            }
            var jurisdiction = Item.jurisdiction;
            for (var i = 0, ilen = tryjurisdictions2.length; i < ilen; i++) {
              if (jurisdiction === tryjurisdictions2[i]) {
                return true;
              }
            }
            return false;
          };
        };
        this.tests.push(maketests(tryjurisdictions));
      };
      CSL2.Attributes["@country"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var trycountries = arg.split(/\s+/);
        var maketests = function(trycountries2) {
          return function(Item) {
            if (!Item.country) {
              return false;
            }
            var country = Item.country;
            for (var i = 0, ilen = trycountries2.length; i < ilen; i++) {
              if (country === trycountries2[i]) {
                return true;
              }
            }
            return false;
          };
        };
        this.tests.push(maketests(trycountries));
      };
      CSL2.Attributes["@context"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var func = function() {
          if (["bibliography", "citation"].indexOf(arg) > -1) {
            var area = state.tmp.area.slice(0, arg.length);
            if (area === arg) {
              return true;
            }
            return false;
          } else if ("alternative" === arg) {
            return !!state.tmp.abort_alternative;
          }
        };
        this.tests.push(func);
      };
      CSL2.Attributes["@has-year-only"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var trydates = arg.split(/\s+/);
        var maketest = function(trydate) {
          return function(Item) {
            var date = Item[trydate];
            if (!date || date.month || date.season) {
              return false;
            } else {
              return true;
            }
          };
        };
        for (var i = 0, ilen = trydates.length; i < ilen; i += 1) {
          this.tests.push(maketest(trydates[i]));
        }
      };
      CSL2.Attributes["@has-to-month-or-season"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var trydates = arg.split(/\s+/);
        var maketest = function(trydate) {
          return function(Item) {
            var date = Item[trydate];
            if (!date || !date.month && !date.season || date.day) {
              return false;
            } else {
              return true;
            }
          };
        };
        for (var i = 0, ilen = trydates.length; i < ilen; i += 1) {
          this.tests.push(maketest(trydates[i]));
        }
      };
      CSL2.Attributes["@has-day"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var trydates = arg.split(/\s+/);
        var maketest = function(trydate) {
          return function(Item) {
            var date = Item[trydate];
            if (!date || !date.day) {
              return false;
            } else {
              return true;
            }
          };
        };
        for (var i = 0, ilen = trydates.length; i < ilen; i += 1) {
          this.tests.push(maketest(trydates[i]));
        }
      };
      CSL2.Attributes["@is-plural"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var func = function(Item) {
          var nameList = Item[arg];
          if (nameList && nameList.length) {
            var persons = 0;
            var institutions = 0;
            var last_is_person = false;
            for (var i = 0, ilen = nameList.length; i < ilen; i += 1) {
              if (state.opt.development_extensions.spoof_institutional_affiliations && (nameList[i].literal || nameList[i].isInstitution && nameList[i].family && !nameList[i].given)) {
                institutions += 1;
                last_is_person = false;
              } else {
                persons += 1;
                last_is_person = true;
              }
            }
            if (persons > 1) {
              return true;
            } else if (institutions > 1) {
              return true;
            } else if (institutions && last_is_person) {
              return true;
            }
          }
          return false;
        };
        this.tests.push(func);
      };
      CSL2.Attributes["@is-multiple"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var func = function(Item) {
          var val = "" + Item[arg];
          var lst = val.split(/(?:,\s|\s(?:tot\sen\smet|līdz|oraz|and|bis|έως|και|och|až|do|en|et|in|ir|ja|og|sa|to|un|und|és|și|i|u|y|à|e|a|и|-|–)\s|—|\&)/);
          if (lst.length > 1) {
            return true;
          }
          return false;
        };
        this.tests.push(func);
      };
      CSL2.Attributes["@locale"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var ret, langspec, lang, lst, i, ilen;
        var locale_default = state.opt["default-locale"][0];
        if (this.name === "layout") {
          this.locale_raw = arg;
          if (this.tokentype === CSL2.START) {
            if (!state.opt.multi_layout) {
              state.opt.multi_layout = [];
            }
            var locale_data = [];
            var locales = arg.split(/\s+/);
            var sort_locale = {};
            var localeMaster = CSL2.localeResolve(locales[0], locale_default);
            locale_data.push(localeMaster);
            if (localeMaster.generic) {
              sort_locale[localeMaster.generic] = localeMaster.best;
            } else {
              sort_locale[localeMaster.best] = localeMaster.best;
            }
            for (var i = 1, ilen = locales.length; i < ilen; i += 1) {
              var localeServant = CSL2.localeResolve(locales[i], locale_default);
              locale_data.push(localeServant);
              if (localeServant.generic) {
                sort_locale[localeServant.generic] = localeMaster.best;
              } else {
                sort_locale[localeServant.best] = localeMaster.best;
              }
            }
            state[state.build.area].opt.sort_locales.push(sort_locale);
            state.opt.multi_layout.push(locale_data);
          }
          state.opt.has_layout_locale = true;
        } else {
          lst = arg.split(/\s+/);
          var locale_bares = [];
          for (i = 0, ilen = lst.length; i < ilen; i += 1) {
            lang = lst[i];
            langspec = CSL2.localeResolve(lang, locale_default);
            if (lst[i].length === 2) {
              locale_bares.push(langspec.bare);
            }
            state.localeConfigure(langspec, true);
            lst[i] = langspec;
          }
          var locale_list = lst.slice();
          var maketest = function(locale_list2, locale_default2, locale_bares2) {
            return function(Item) {
              var res;
              ret = [];
              res = false;
              var langspec2 = false;
              var lang2;
              if (!Item.language) {
                lang2 = locale_default2;
              } else {
                lang2 = Item.language;
              }
              langspec2 = CSL2.localeResolve(lang2, locale_default2);
              for (i = 0, ilen = locale_list2.length; i < ilen; i += 1) {
                if (langspec2.best === locale_list2[i].best) {
                  state.tmp.condition_lang_counter_arr.push(state.tmp.condition_counter);
                  state.tmp.condition_lang_val_arr.push(state.opt.lang);
                  state.opt.lang = locale_list2[0].best;
                  res = true;
                  break;
                }
              }
              if (!res && locale_bares2.indexOf(langspec2.bare) > -1) {
                state.tmp.condition_lang_counter_arr.push(state.tmp.condition_counter);
                state.tmp.condition_lang_val_arr.push(state.opt.lang);
                state.opt.lang = locale_list2[0].best;
                res = true;
              }
              return res;
            };
          };
          this.tests.push(maketest(locale_list, locale_default, locale_bares));
        }
      };
      CSL2.Attributes["@alternative-node-internal"] = function(state) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var maketest = function() {
          return function() {
            return !state.tmp.abort_alternative;
          };
        };
        var me = this;
        this.tests.push(maketest(me));
      };
      CSL2.Attributes["@locale-internal"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var langspec, lang, lst, i, ilen;
        lst = arg.split(/\s+/);
        this.locale_bares = [];
        for (i = 0, ilen = lst.length; i < ilen; i += 1) {
          lang = lst[i];
          langspec = CSL2.localeResolve(lang, state.opt["default-locale"][0]);
          if (lst[i].length === 2) {
            this.locale_bares.push(langspec.bare);
          }
          state.localeConfigure(langspec);
          lst[i] = langspec;
        }
        this.locale_default = state.opt["default-locale"][0];
        this.locale = lst[0].best;
        this.locale_list = lst.slice();
        var maketest = function(me2) {
          return function(Item) {
            var ret, res;
            ret = [];
            res = false;
            var langspec2 = false;
            if (Item.language) {
              lang = Item.language;
              langspec2 = CSL2.localeResolve(lang, state.opt["default-locale"][0]);
              if (langspec2.best === state.opt["default-locale"][0]) {
                langspec2 = false;
              }
            }
            if (langspec2) {
              for (i = 0, ilen = me2.locale_list.length; i < ilen; i += 1) {
                if (langspec2.best === me2.locale_list[i].best) {
                  state.opt.lang = me2.locale;
                  state.tmp.last_cite_locale = me2.locale;
                  state.output.openLevel("empty");
                  state.output.current.value().new_locale = me2.locale;
                  res = true;
                  break;
                }
              }
              if (!res && me2.locale_bares.indexOf(langspec2.bare) > -1) {
                state.opt.lang = me2.locale;
                state.tmp.last_cite_locale = me2.locale;
                state.output.openLevel("empty");
                state.output.current.value().new_locale = me2.locale;
                res = true;
              }
            }
            return res;
          };
        };
        var me = this;
        this.tests.push(maketest(me));
      };
      CSL2.Attributes["@court-class"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var tryclasses = arg.split(/\s+/);
        var maketest = function(tryclass) {
          return function(Item) {
            var cls = CSL2.GET_COURT_CLASS(state, Item);
            if (cls === tryclass) {
              return true;
            } else {
              return false;
            }
          };
        };
        for (var i = 0, ilen = tryclasses.length; i < ilen; i++) {
          this.tests.push(maketest(tryclasses[i]));
        }
      };
      CSL2.Attributes["@container-multiple"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var retval = "true" === arg ? true : false;
        var maketest = function(retval2) {
          return function(Item) {
            if (!state.tmp.container_item_count[Item.container_id]) {
              return !retval2;
            } else if (state.tmp.container_item_count[Item.container_id] > 1) {
              return retval2;
            }
            return !retval2;
          };
        };
        this.tests.push(maketest(retval));
      };
      CSL2.Attributes["@container-subsequent"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var retval = "true" === arg ? true : false;
        var maketest = function(retval2) {
          return function(Item) {
            if (state.tmp.container_item_pos[Item.container_id] > 1) {
              return retval2;
            }
            return !retval2;
          };
        };
        this.tests.push(maketest(retval));
      };
      CSL2.Attributes["@has-subunit"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var maketest = function(namevar) {
          return function(Item) {
            var subunit_count = 0;
            for (var i in Item[namevar]) {
              var name = Item[namevar][i];
              if (!name.given) {
                var institution = name.literal ? name.literal : name.family;
                var length = institution.split("|").length;
                if (subunit_count === 0 || length < subunit_count) {
                  subunit_count = length;
                }
              }
            }
            return subunit_count > 1;
          };
        };
        this.tests.push(maketest(arg));
      };
      CSL2.Attributes["@cite-form"] = function(state, arg) {
        if (!this.tests) {
          this.tests = [];
        }
        ;
        var maketest = function(citeForm) {
          return function(Item) {
            if (Item["cite-form"] === citeForm) {
              return true;
            }
            return false;
          };
        };
        this.tests.push(maketest(arg));
      };
      CSL2.Attributes["@disable-duplicate-year-suppression"] = function(state, arg) {
        state.opt.disable_duplicate_year_suppression = arg.split(/\s+/);
      };
      CSL2.Attributes["@consolidate-containers"] = function(state, arg) {
        CSL2.Attributes["@track-containers"](state, arg);
        var args = arg.split(/\s+/);
        state.bibliography.opt.consolidate_containers = args;
      };
      CSL2.Attributes["@track-containers"] = function(state, arg) {
        var args = arg.split(/\s+/);
        if (!state.bibliography.opt.track_container_items) {
          state.bibliography.opt.track_container_items = [];
        }
        if (!state.bibliography.opt.consolidate_containers) {
          state.bibliography.opt.consolidate_containers = [];
        }
        state.bibliography.opt.track_container_items = state.bibliography.opt.track_container_items.concat(args);
      };
      CSL2.Attributes["@parallel-first"] = function(state, arg) {
        state.opt.parallel.enable = true;
        var vars = arg.split(/\s+/);
        if (!state.opt.track_repeat) {
          state.opt.track_repeat = {};
        }
        this.parallel_first = {};
        for (var i in vars) {
          var v = vars[i];
          this.parallel_first[v] = true;
          state.opt.track_repeat[v] = true;
        }
      };
      CSL2.Attributes["@parallel-last"] = function(state, arg) {
        state.opt.parallel.enable = true;
        var vars = arg.split(/\s+/);
        if (!state.opt.track_repeat) {
          state.opt.track_repeat = {};
        }
        this.parallel_last = {};
        for (var i in vars) {
          var v = vars[i];
          this.parallel_last[v] = true;
          state.opt.track_repeat[v] = true;
        }
      };
      CSL2.Attributes["@parallel-last-to-first"] = function(state, arg) {
        state.opt.parallel.enable = true;
        var vars = arg.split(/\s+/);
        this.parallel_last_to_first = {};
        for (var i = 0, ilen = vars.length; i < ilen; i++) {
          this.parallel_last_to_first[vars[i]] = true;
        }
      };
      CSL2.Attributes["@parallel-delimiter-override"] = function(state, arg) {
        state.opt.parallel.enable = true;
        this.strings.set_parallel_delimiter_override = arg;
      };
      CSL2.Attributes["@parallel-delimiter-override-on-suppress"] = function(state, arg) {
        state.opt.parallel.enable = true;
        this.strings.set_parallel_delimiter_override_on_suppress = arg;
      };
      CSL2.Attributes["@no-repeat"] = function(state, arg) {
        state.opt.parallel.enable = true;
        var vars = arg.split(/\s+/);
        if (!state.opt.track_repeat) {
          state.opt.track_repeat = {};
        }
        this.non_parallel = {};
        for (var i in vars) {
          var v = vars[i];
          this.non_parallel[v] = true;
          state.opt.track_repeat[v] = true;
        }
      };
      CSL2.Attributes["@require"] = function(state, arg) {
        state.opt.use_context_condition = true;
        this.strings.require = arg;
      };
      CSL2.Attributes["@reject"] = function(state, arg) {
        state.opt.use_context_condition = true;
        this.strings.reject = arg;
      };
      CSL2.Attributes["@require-comma-on-symbol"] = function(state, arg) {
        state.opt.require_comma_on_symbol = arg;
      };
      CSL2.Attributes["@gender"] = function(state, arg) {
        this.gender = arg;
      };
      CSL2.Attributes["@cslid"] = function(state, arg) {
        this.cslid = parseInt(arg, 10);
      };
      CSL2.Attributes["@capitalize-if-first"] = function(state, arg) {
        this.strings.capitalize_if_first_override = arg;
      };
      CSL2.Attributes["@label-capitalize-if-first"] = function(state, arg) {
        this.strings.label_capitalize_if_first_override = arg;
      };
      CSL2.Attributes["@label-form"] = function(state, arg) {
        this.strings.label_form_override = arg;
      };
      CSL2.Attributes["@part-separator"] = function(state, arg) {
        this.strings["part-separator"] = arg;
      };
      CSL2.Attributes["@leading-noise-words"] = function(state, arg) {
        this["leading-noise-words"] = arg;
      };
      CSL2.Attributes["@name-never-short"] = function(state, arg) {
        this["name-never-short"] = arg;
      };
      CSL2.Attributes["@class"] = function(state, arg) {
        state.opt["class"] = arg;
      };
      CSL2.Attributes["@version"] = function(state, arg) {
        state.opt.version = arg;
      };
      CSL2.Attributes["@value"] = function(state, arg) {
        this.strings.value = arg;
      };
      CSL2.Attributes["@name"] = function(state, arg) {
        this.strings.name = arg;
      };
      CSL2.Attributes["@form"] = function(state, arg) {
        this.strings.form = arg;
      };
      CSL2.Attributes["@date-parts"] = function(state, arg) {
        this.strings["date-parts"] = arg;
      };
      CSL2.Attributes["@range-delimiter"] = function(state, arg) {
        this.strings["range-delimiter"] = arg;
      };
      CSL2.Attributes["@macro"] = function(state, arg) {
        this.postponed_macro = arg;
      };
      CSL2.Attributes["@term"] = function(state, arg) {
        if (arg === "sub verbo") {
          this.strings.term = "sub-verbo";
        } else {
          this.strings.term = arg;
        }
      };
      CSL2.Attributes["@xmlns"] = function() {
      };
      CSL2.Attributes["@lang"] = function(state, arg) {
        if (arg) {
          state.build.lang = arg;
        }
      };
      CSL2.Attributes["@lingo"] = function() {
      };
      CSL2.Attributes["@macro-has-date"] = function() {
        this["macro-has-date"] = true;
      };
      CSL2.Attributes["@suffix"] = function(state, arg) {
        this.strings.suffix = arg;
      };
      CSL2.Attributes["@prefix"] = function(state, arg) {
        this.strings.prefix = arg;
      };
      CSL2.Attributes["@delimiter"] = function(state, arg) {
        this.strings.delimiter = arg;
      };
      CSL2.Attributes["@match"] = function(state, arg) {
        this.match = arg;
      };
      CSL2.Attributes["@names-min"] = function(state, arg) {
        var val = parseInt(arg, 10);
        if (state[state.build.area].opt.max_number_of_names < val) {
          state[state.build.area].opt.max_number_of_names = val;
        }
        this.strings["et-al-min"] = val;
      };
      CSL2.Attributes["@names-use-first"] = function(state, arg) {
        this.strings["et-al-use-first"] = parseInt(arg, 10);
      };
      CSL2.Attributes["@names-use-last"] = function(state, arg) {
        if (arg === "true") {
          this.strings["et-al-use-last"] = true;
        } else {
          this.strings["et-al-use-last"] = false;
        }
      };
      CSL2.Attributes["@sort"] = function(state, arg) {
        if (arg === "descending") {
          this.strings.sort_direction = CSL2.DESCENDING;
        }
      };
      CSL2.Attributes["@plural"] = function(state, arg) {
        if ("always" === arg || "true" === arg) {
          this.strings.plural = 1;
        } else if ("never" === arg || "false" === arg) {
          this.strings.plural = 0;
        } else if ("contextual" === arg) {
          this.strings.plural = false;
        }
      };
      CSL2.Attributes["@has-publisher-and-publisher-place"] = function() {
        this.strings["has-publisher-and-publisher-place"] = true;
      };
      CSL2.Attributes["@publisher-delimiter-precedes-last"] = function(state, arg) {
        this.strings["publisher-delimiter-precedes-last"] = arg;
      };
      CSL2.Attributes["@publisher-delimiter"] = function(state, arg) {
        this.strings["publisher-delimiter"] = arg;
      };
      CSL2.Attributes["@publisher-and"] = function(state, arg) {
        this.strings["publisher-and"] = arg;
      };
      CSL2.Attributes["@givenname-disambiguation-rule"] = function(state, arg) {
        if (CSL2.GIVENNAME_DISAMBIGUATION_RULES.indexOf(arg) > -1) {
          state.citation.opt["givenname-disambiguation-rule"] = arg;
        }
      };
      CSL2.Attributes["@collapse"] = function(state, arg) {
        if (arg) {
          state[this.name].opt.collapse = arg;
        }
      };
      CSL2.Attributes["@cite-group-delimiter"] = function(state, arg) {
        if (arg) {
          state[state.tmp.area].opt.cite_group_delimiter = arg;
        }
      };
      CSL2.Attributes["@names-delimiter"] = function(state, arg) {
        state.setOpt(this, "names-delimiter", arg);
      };
      CSL2.Attributes["@name-form"] = function(state, arg) {
        state.setOpt(this, "name-form", arg);
      };
      CSL2.Attributes["@subgroup-delimiter"] = function(state, arg) {
        this.strings["subgroup-delimiter"] = arg;
      };
      CSL2.Attributes["@subgroup-delimiter-precedes-last"] = function(state, arg) {
        this.strings["subgroup-delimiter-precedes-last"] = arg;
      };
      CSL2.Attributes["@name-delimiter"] = function(state, arg) {
        state.setOpt(this, "name-delimiter", arg);
      };
      CSL2.Attributes["@et-al-min"] = function(state, arg) {
        var val = parseInt(arg, 10);
        if (state[state.build.area].opt.max_number_of_names < val) {
          state[state.build.area].opt.max_number_of_names = val;
        }
        state.setOpt(this, "et-al-min", val);
      };
      CSL2.Attributes["@et-al-use-first"] = function(state, arg) {
        state.setOpt(this, "et-al-use-first", parseInt(arg, 10));
      };
      CSL2.Attributes["@et-al-use-last"] = function(state, arg) {
        if (arg === "true") {
          state.setOpt(this, "et-al-use-last", true);
        } else {
          state.setOpt(this, "et-al-use-last", false);
        }
      };
      CSL2.Attributes["@et-al-subsequent-min"] = function(state, arg) {
        var val = parseInt(arg, 10);
        if (state[state.build.area].opt.max_number_of_names < val) {
          state[state.build.area].opt.max_number_of_names = val;
        }
        state.setOpt(this, "et-al-subsequent-min", val);
      };
      CSL2.Attributes["@et-al-subsequent-use-first"] = function(state, arg) {
        state.setOpt(this, "et-al-subsequent-use-first", parseInt(arg, 10));
      };
      CSL2.Attributes["@suppress-min"] = function(state, arg) {
        this.strings["suppress-min"] = parseInt(arg, 10);
      };
      CSL2.Attributes["@suppress-max"] = function(state, arg) {
        this.strings["suppress-max"] = parseInt(arg, 10);
      };
      CSL2.Attributes["@and"] = function(state, arg) {
        state.setOpt(this, "and", arg);
      };
      CSL2.Attributes["@delimiter-precedes-last"] = function(state, arg) {
        state.setOpt(this, "delimiter-precedes-last", arg);
      };
      CSL2.Attributes["@delimiter-precedes-et-al"] = function(state, arg) {
        state.setOpt(this, "delimiter-precedes-et-al", arg);
      };
      CSL2.Attributes["@initialize-with"] = function(state, arg) {
        state.setOpt(this, "initialize-with", arg);
      };
      CSL2.Attributes["@initialize"] = function(state, arg) {
        if (arg === "false") {
          state.setOpt(this, "initialize", false);
        }
      };
      CSL2.Attributes["@name-as-reverse-order"] = function(state, arg) {
        this["name-as-reverse-order"] = arg;
      };
      CSL2.Attributes["@name-as-sort-order"] = function(state, arg) {
        if (this.name === "style-options") {
          this["name-as-sort-order"] = arg;
        } else {
          state.setOpt(this, "name-as-sort-order", arg);
        }
      };
      CSL2.Attributes["@sort-separator"] = function(state, arg) {
        state.setOpt(this, "sort-separator", arg);
      };
      CSL2.Attributes["@require-match"] = function(state, arg) {
        if (arg === "true") {
          this.requireMatch = true;
        }
      };
      CSL2.Attributes["@exclude-types"] = function(state, arg) {
        state.bibliography.opt.exclude_types = arg.split(/\s+/);
      };
      CSL2.Attributes["@exclude-with-fields"] = function(state, arg) {
        state.bibliography.opt.exclude_with_fields = arg.split(/\s+/);
      };
      CSL2.Attributes["@year-suffix-delimiter"] = function(state, arg) {
        state[this.name].opt["year-suffix-delimiter"] = arg;
      };
      CSL2.Attributes["@after-collapse-delimiter"] = function(state, arg) {
        state[this.name].opt["after-collapse-delimiter"] = arg;
      };
      CSL2.Attributes["@subsequent-author-substitute"] = function(state, arg) {
        state[this.name].opt["subsequent-author-substitute"] = arg;
      };
      CSL2.Attributes["@subsequent-author-substitute-rule"] = function(state, arg) {
        state[this.name].opt["subsequent-author-substitute-rule"] = arg;
      };
      CSL2.Attributes["@disambiguate-add-names"] = function(state, arg) {
        if (arg === "true") {
          state.opt["disambiguate-add-names"] = true;
        }
      };
      CSL2.Attributes["@disambiguate-add-givenname"] = function(state, arg) {
        if (arg === "true") {
          state.opt["disambiguate-add-givenname"] = true;
        }
      };
      CSL2.Attributes["@disambiguate-add-year-suffix"] = function(state, arg) {
        if (arg === "true" && state.opt.xclass !== "numeric") {
          state.opt["disambiguate-add-year-suffix"] = true;
        }
      };
      CSL2.Attributes["@second-field-align"] = function(state, arg) {
        if (arg === "flush" || arg === "margin") {
          state[this.name].opt["second-field-align"] = arg;
        }
      };
      CSL2.Attributes["@hanging-indent"] = function(state, arg) {
        if (arg === "true") {
          if (state.opt.development_extensions.hanging_indent_legacy_number) {
            state[this.name].opt.hangingindent = 2;
          } else {
            state[this.name].opt.hangingindent = true;
          }
        }
      };
      CSL2.Attributes["@line-spacing"] = function(state, arg) {
        if (arg && arg.match(/^[.0-9]+$/)) {
          state[this.name].opt["line-spacing"] = parseFloat(arg, 10);
        }
      };
      CSL2.Attributes["@entry-spacing"] = function(state, arg) {
        if (arg && arg.match(/^[.0-9]+$/)) {
          state[this.name].opt["entry-spacing"] = parseFloat(arg, 10);
        }
      };
      CSL2.Attributes["@near-note-distance"] = function(state, arg) {
        state[this.name].opt["near-note-distance"] = parseInt(arg, 10);
      };
      CSL2.Attributes["@substring"] = function(state, arg) {
        this.substring = parseInt(arg, 10);
      };
      CSL2.Attributes["@text-case"] = function(state, arg) {
        var func = function(state2, Item) {
          if (arg === "normal") {
            this.text_case_normal = true;
          } else {
            this.strings["text-case"] = arg;
            if (arg === "title") {
              if (Item.jurisdiction) {
                this.strings["text-case"] = "passthrough";
              }
            }
          }
        };
        this.execs.push(func);
      };
      CSL2.Attributes["@page-range-format"] = function(state, arg) {
        state.opt["page-range-format"] = arg;
      };
      CSL2.Attributes["@year-range-format"] = function(state, arg) {
        state.opt["year-range-format"] = arg;
      };
      CSL2.Attributes["@default-locale"] = function(state, arg) {
        if (this.name === "style") {
          var lst, len, pos, m, ret;
          var m = arg.match(/-x-(sort|translit|translat)-/g);
          if (m) {
            for (pos = 0, len = m.length; pos < len; pos += 1) {
              m[pos] = m[pos].replace(/^-x-/, "").replace(/-$/, "");
            }
          }
          lst = arg.split(/-x-(?:sort|translit|translat)-/);
          ret = [lst[0]];
          for (pos = 1, len = lst.length; pos < len; pos += 1) {
            ret.push(m[pos - 1]);
            ret.push(lst[pos]);
          }
          lst = ret.slice();
          len = lst.length;
          for (pos = 1; pos < len; pos += 2) {
            state.opt["locale-" + lst[pos]].push(lst[pos + 1].replace(/^\s*/g, "").replace(/\s*$/g, ""));
          }
          if (lst.length) {
            state.opt["default-locale"] = lst.slice(0, 1);
          } else {
            state.opt["default-locale"] = ["en"];
          }
        } else if (arg === "true") {
          this.default_locale = true;
        }
      };
      CSL2.Attributes["@default-locale-sort"] = function(state, arg) {
        state.opt["default-locale-sort"] = arg;
      };
      CSL2.Attributes["@demote-non-dropping-particle"] = function(state, arg) {
        state.opt["demote-non-dropping-particle"] = arg;
      };
      CSL2.Attributes["@initialize-with-hyphen"] = function(state, arg) {
        if (arg === "false") {
          state.opt["initialize-with-hyphen"] = false;
        }
      };
      CSL2.Attributes["@institution-parts"] = function(state, arg) {
        this.strings["institution-parts"] = arg;
      };
      CSL2.Attributes["@if-short"] = function(state, arg) {
        if (arg === "true") {
          this.strings["if-short"] = true;
        }
      };
      CSL2.Attributes["@substitute-use-first"] = function(state, arg) {
        this.strings["substitute-use-first"] = parseInt(arg, 10);
      };
      CSL2.Attributes["@use-first"] = function(state, arg) {
        this.strings["use-first"] = parseInt(arg, 10);
      };
      CSL2.Attributes["@use-last"] = function(state, arg) {
        this.strings["use-last"] = parseInt(arg, 10);
      };
      CSL2.Attributes["@stop-first"] = function(state, arg) {
        this.strings["stop-first"] = parseInt(arg, 10);
      };
      CSL2.Attributes["@stop-last"] = function(state, arg) {
        this.strings["stop-last"] = parseInt(arg, 10) * -1;
      };
      CSL2.Attributes["@reverse-order"] = function(state, arg) {
        if ("true" === arg) {
          this.strings["reverse-order"] = true;
        }
      };
      CSL2.Attributes["@display"] = function(state, arg) {
        if (state.bibliography.tokens.length === 2) {
          state.opt.using_display = true;
        }
        this.strings.cls = arg;
      };
      CSL2.Stack = function(val, literal) {
        this.mystack = [];
        if (literal || val) {
          this.mystack.push(val);
        }
        this.tip = this.mystack[0];
      };
      CSL2.Stack.prototype.push = function(val, literal) {
        if (literal || val) {
          this.mystack.push(val);
        } else {
          this.mystack.push("");
        }
        this.tip = this.mystack[this.mystack.length - 1];
      };
      CSL2.Stack.prototype.clear = function() {
        this.mystack = [];
        this.tip = {};
      };
      CSL2.Stack.prototype.replace = function(val, literal) {
        if (this.mystack.length === 0) {
          CSL2.error("Internal CSL processor error: attempt to replace nonexistent stack item with " + val);
        }
        if (literal || val) {
          this.mystack[this.mystack.length - 1] = val;
        } else {
          this.mystack[this.mystack.length - 1] = "";
        }
        this.tip = this.mystack[this.mystack.length - 1];
      };
      CSL2.Stack.prototype.pop = function() {
        var ret = this.mystack.pop();
        if (this.mystack.length) {
          this.tip = this.mystack[this.mystack.length - 1];
        } else {
          this.tip = {};
        }
        return ret;
      };
      CSL2.Stack.prototype.value = function() {
        return this.mystack.slice(-1)[0];
      };
      CSL2.Stack.prototype.length = function() {
        return this.mystack.length;
      };
      CSL2.Parallel = function(state) {
        this.state = state;
      };
      CSL2.Parallel.prototype.StartCitation = function(sortedItems, out) {
        this.state.tmp.suppress_repeats = [];
        if (sortedItems.length < 2) return;
        var idxEnd = 0;
        var parallelMatchList = false;
        var siblingRanges = [];
        for (var i = 0, ilen = sortedItems.length - 1; i < ilen; i++) {
          var currItem = sortedItems[i][0];
          var nextItem = sortedItems[i + 1][0];
          var freshMatchList = false;
          var info = {};
          if (sortedItems[i][0].seeAlso && sortedItems[i][0].seeAlso.length > 0 && !parallelMatchList) {
            freshMatchList = true;
            parallelMatchList = [sortedItems[i][0].id].concat(sortedItems[i][0].seeAlso);
            var tempMatchList = parallelMatchList.slice();
            var remainder = sortedItems.slice(i);
            remainder[0][1].parallel = "first";
            for (var j = 0, jlen = remainder.length; j < jlen; j++) {
              var itemID = remainder[j][0].id;
              var ididx = tempMatchList.indexOf(itemID);
              idxEnd = false;
              if (ididx === -1) {
                idxEnd = i + j - 1;
              } else if (i + j === sortedItems.length - 1) {
                idxEnd = i + j;
              }
              if (idxEnd) {
                siblingRanges.push([i, idxEnd]);
                break;
              } else {
                tempMatchList = tempMatchList.slice(0, ididx).concat(tempMatchList.slice(ididx + 1));
              }
            }
          }
          if (i > 0 && freshMatchList) {
            this.state.tmp.suppress_repeats[i - 1].START = true;
            freshMatchList = false;
          }
          for (var varname in this.state.opt.track_repeat) {
            if (!currItem[varname] || !nextItem[varname]) {
              info[varname] = false;
            } else if ("string" === typeof nextItem[varname] || "number" === typeof nextItem[varname]) {
              if (varname === "title" && currItem["title-short"] && nextItem["title-short"]) {
                var currVal = currItem["title-short"];
                var nextVal = nextItem["title-short"];
              } else {
                var currVal = currItem[varname];
                var nextVal = nextItem[varname];
              }
              if (currVal == nextVal) {
                info[varname] = true;
              } else {
                info[varname] = false;
              }
            } else if ("undefined" === typeof currItem[varname].length) {
              info[varname] = false;
              var currYear = currItem[varname].year;
              var nextYear = nextItem[varname].year;
              if (currYear && nextYear) {
                if (currYear == nextYear) {
                  info[varname] = true;
                }
              }
            } else {
              var currVal = JSON.stringify(currItem[varname]);
              var nextVal = JSON.stringify(nextItem[varname]);
              if (currVal === nextVal) {
                info[varname] = true;
              } else {
                info[varname] = false;
              }
            }
          }
          if (!parallelMatchList) {
            info.ORPHAN = true;
          }
          if (idxEnd === i) {
            info.END = true;
            parallelMatchList = false;
          }
          this.state.tmp.suppress_repeats.push(info);
        }
        for (var j = 0, jlen = siblingRanges.length; j < jlen; j++) {
          var masterID = sortedItems[siblingRanges[j][0]][0].id;
          this.state.registry.registry[masterID].master = true;
          this.state.registry.registry[masterID].siblings = [];
          var start = siblingRanges[j][0];
          var end = siblingRanges[j][1];
          for (var k = start; k < end; k++) {
            this.state.tmp.suppress_repeats[k].SIBLING = true;
            var siblingID = sortedItems[k + 1][0].id;
            sortedItems[k + 1][1].parallel = "other";
            this.state.registry.registry[masterID].siblings.push(siblingID);
          }
        }
      };
      CSL2.Parallel.prototype.checkRepeats = function(params) {
        var idx = this.state.tmp.cite_index;
        if (this.state.tmp.suppress_repeats) {
          if (params.parallel_first && Object.keys(params.parallel_first).length > 0) {
            var arr = [{}].concat(this.state.tmp.suppress_repeats);
            var ret = true;
            for (var varname in params.parallel_first) {
              if (!arr[idx][varname] || arr[idx].START) {
                ret = false;
              }
            }
            return ret;
          }
          if (params.parallel_last && Object.keys(params.parallel_last).length > 0) {
            var arr = this.state.tmp.suppress_repeats.concat([{}]);
            var ret = Object.keys(params.parallel_last).length > 0 ? true : false;
            for (var varname in params.parallel_last) {
              if (!arr[idx][varname] || arr[idx].END) {
                ret = false;
              }
            }
            return ret;
          }
          if (params.non_parallel && Object.keys(params.non_parallel).length > 0) {
            var arr = [{}].concat(this.state.tmp.suppress_repeats);
            var ret = true;
            for (var varname in params.non_parallel) {
              if (!arr[idx][varname]) {
                ret = false;
              }
            }
            return ret;
          }
        }
        return false;
      };
      CSL2.Util = {};
      CSL2.Util.Match = function() {
        this.any = function(token, state, tests) {
          return function(Item, item) {
            for (var i = 0, ilen = tests.length; i < ilen; i += 1) {
              var result = tests[i](Item, item);
              if (result) {
                return true;
              }
            }
            return false;
          };
        };
        this.none = function(token, state, tests) {
          return function(Item, item) {
            for (var i = 0, ilen = tests.length; i < ilen; i += 1) {
              var result = tests[i](Item, item);
              if (result) {
                return false;
              }
            }
            return true;
          };
        };
        this.all = function(token, state, tests) {
          return function(Item, item) {
            for (var i = 0, ilen = tests.length; i < ilen; i += 1) {
              var result = tests[i](Item, item);
              if (!result) {
                return false;
              }
            }
            return true;
          };
        };
        this[void 0] = this.all;
        this.nand = function(token, state, tests) {
          return function(Item, item) {
            for (var i = 0, ilen = tests.length; i < ilen; i += 1) {
              var result = tests[i](Item, item);
              if (!result) {
                return true;
              }
            }
            return false;
          };
        };
      };
      CSL2.Transform = function(state) {
        this.abbrevs = {};
        this.abbrevs["default"] = new state.sys.AbbreviationSegments();
        function getCountryOrJurisdiction(variable, normalizedKey, quashCountry) {
          var value = "";
          if (state.sys.getHumanForm) {
            if (variable === "country") {
              value = state.sys.getHumanForm(normalizedKey.toLowerCase(), false, true);
              value = value.split("|")[0];
            } else if (variable === "jurisdiction") {
              value = state.sys.getHumanForm(normalizedKey.toLowerCase(), false, true);
              if (!quashCountry) {
                value = value.split("|").slice(1).join(", ");
              } else {
                value = "";
              }
            }
          }
          return value;
        }
        function abbreviate(state2, tok, Item, altvar, basevalue, family_var, use_field) {
          var value = "";
          var myabbrev_family = CSL2.FIELD_CATEGORY_REMAP[family_var];
          var preferredJurisdiction;
          if (!myabbrev_family) {
            return basevalue;
          }
          var variable = family_var;
          var normalizedKey = basevalue;
          if (state2.sys.normalizeAbbrevsKey) {
            normalizedKey = state2.sys.normalizeAbbrevsKey(family_var, basevalue);
          }
          var quashCountry = false;
          if (variable === "jurisdiction" && normalizedKey) {
            quashCountry = normalizedKey.indexOf(":") === -1;
          }
          if (["jurisdiction", "country"].indexOf(family_var) > -1 && basevalue === basevalue.toLowerCase()) {
            normalizedKey = basevalue.toUpperCase();
          }
          if (state2.sys.getAbbreviation) {
            if (["jurisdiction", "country", "language-name", "language-name-original"].indexOf(variable) > -1) {
              preferredJurisdiction = "default";
            } else if (Item.jurisdiction) {
              preferredJurisdiction = Item.jurisdiction;
            } else {
              preferredJurisdiction = "default";
            }
            var jurisdiction = state2.transform.loadAbbreviation(preferredJurisdiction, myabbrev_family, normalizedKey, Item.language);
            if (state2.transform.abbrevs[jurisdiction][myabbrev_family] && normalizedKey) {
              var abbrev = state2.transform.abbrevs[jurisdiction][myabbrev_family][normalizedKey];
              if (tok.strings.form === "short" && abbrev) {
                if (quashCountry) {
                  value = "";
                } else {
                  value = abbrev;
                }
              } else {
                value = getCountryOrJurisdiction(variable, normalizedKey, quashCountry);
              }
            }
          }
          if (!value && (!state2.opt.development_extensions.require_explicit_legal_case_title_short || Item.type !== "legal_case") && altvar && Item[altvar] && use_field) {
            value = Item[altvar];
          }
          if (!value && !state2.sys.getAbbreviation && state2.sys.getHumanForm) {
            value = getCountryOrJurisdiction(variable, normalizedKey, quashCountry);
          }
          if (!value && !quashCountry && (!state2.sys.getHumanForm || variable !== "jurisdiction")) {
            value = basevalue;
          }
          if (state2.opt.development_extensions.force_title_abbrev_fallback) {
            if (variable === "title" && value === basevalue && Item["title-short"]) {
              value = Item["title-short"];
            }
          }
          return value;
        }
        function getFieldLocale(Item, field) {
          var ret = state.opt["default-locale"][0].slice(0, 2);
          var localeRex;
          if (state.opt.development_extensions.strict_text_case_locales) {
            localeRex = new RegExp("^([a-zA-Z]{2})(?:$|-.*| .*)");
          } else {
            localeRex = new RegExp("^([a-zA-Z]{2})(?:$|-.*|.*)");
          }
          if (Item.language) {
            var m = ("" + Item.language).match(localeRex);
            if (m) {
              ret = m[1];
            } else {
              ret = "tlh";
            }
          }
          if (Item.multi && Item.multi && Item.multi.main && Item.multi.main[field]) {
            ret = Item.multi.main[field];
          }
          if (!state.opt.development_extensions.strict_text_case_locales || state.opt.development_extensions.normalize_lang_keys_to_lowercase) {
            ret = ret.toLowerCase();
          }
          return ret;
        }
        function getTextSubField(Item, field, locale_type, use_default, stopOrig, family_var) {
          var opt, o, ret, opts;
          var usedOrig = stopOrig;
          var usingOrig = false;
          if (!Item[field]) {
            return {
              name: "",
              usedOrig: stopOrig,
              token: CSL2.Util.cloneToken(this)
            };
          }
          var stickyLongForm = false;
          if (CSL2.VARIABLES_WITH_SHORT_FORM.indexOf(field) > -1 && family_var) {
            field = field + "-short";
            stickyLongForm = true;
          }
          var breakMe = false;
          var firstValue = null;
          var fieldsToTry = [];
          if (field.slice(-6) === "-short") {
            fieldsToTry.push(field);
            fieldsToTry.push(field.slice(0, -6));
          } else {
            fieldsToTry.push(field);
          }
          for (var h = 0, hlen = fieldsToTry.length; h < hlen; h++) {
            var variantMatch = false;
            var field = fieldsToTry[h];
            ret = { name: "", usedOrig: stopOrig, locale: getFieldLocale(Item, field) };
            opts = state.opt[locale_type] ? state.opt[locale_type].slice() : [];
            var hasVal = false;
            if (locale_type === "locale-orig") {
              if (!stopOrig) {
                ret.name = Item[field];
                ret.usedOrig = false;
              }
              hasVal = true;
              usingOrig = true;
            } else if (use_default && ("undefined" === typeof opts || opts.length === 0)) {
              ret.name = Item[field];
              ret.usedOrig = true;
              hasVal = true;
              usingOrig = true;
            }
            if (!hasVal) {
              for (var i = 0, ilen = opts.length; i < ilen; i += 1) {
                opt = opts[i];
                o = opt.split(/[\-_]/)[0];
                if (opt && Item.multi && Item.multi._keys[field] && Item.multi._keys[field][opt]) {
                  ret.name = Item.multi._keys[field][opt];
                  ret.locale = opt;
                  hasVal = true;
                  variantMatch = true;
                  usingOrig = false;
                  break;
                } else if (o && Item.multi && Item.multi._keys[field] && Item.multi._keys[field][o]) {
                  ret.name = Item.multi._keys[field][o];
                  ret.locale = o;
                  hasVal = true;
                  variantMatch = true;
                  usingOrig = false;
                  break;
                }
              }
              if (!ret.name && use_default) {
                ret = { name: Item[field], usedOrig: true, locale: getFieldLocale(Item, field) };
                usingOrig = true;
              }
            }
            ret.token = CSL2.Util.cloneToken(this);
            if (h === 0) {
              if (variantMatch) {
                ret.found_variant_ok = true;
              }
              firstValue = ret;
              if (!stickyLongForm && ("undefined" === typeof opts || opts.length === 0)) {
                breakMe = true;
              }
              if (variantMatch) {
                breakMe = true;
              }
            } else {
              if (!stickyLongForm && !variantMatch && firstValue) {
                ret = firstValue;
                field = fieldsToTry[0];
              } else if (variantMatch) {
                ret.found_variant_ok = true;
              }
            }
            if (["title", "container-title"].indexOf(field) > -1) {
              if (!usedOrig && (!ret.token.strings["text-case"] || ret.token.strings["text-case"] === "sentence" || ret.token.strings["text-case"] === "normal")) {
                var locale = state.opt.lang;
                var lang;
                if (usingOrig) {
                  lang = false;
                } else {
                  lang = ret.locale;
                }
                var seg = field.slice(0, -5);
                var sentenceCase = ret.token.strings["text-case"] === "sentence" ? true : false;
                ret.name = CSL2.titlecaseSentenceOrNormal(state, Item, seg, lang, sentenceCase);
                delete ret.token.strings["text-case"];
              }
            }
            if (breakMe) {
              break;
            }
          }
          return ret;
        }
        this.getTextSubField = getTextSubField;
        function loadAbbreviation(jurisdiction, category, orig, lang) {
          if (!jurisdiction) {
            jurisdiction = "default";
          }
          var country = jurisdiction.split(":")[0];
          var domain = CSL2.getAbbrevsDomain(state, country, lang);
          if (domain) {
            jurisdiction += "@" + domain;
          }
          if (!orig) {
            if (!state.transform.abbrevs[jurisdiction]) {
              state.transform.abbrevs[jurisdiction] = new state.sys.AbbreviationSegments();
            }
            if (!state.transform.abbrevs[jurisdiction][category]) {
              state.transform.abbrevs[jurisdiction][category] = {};
            }
            return jurisdiction;
          }
          if (state.sys.getAbbreviation) {
            jurisdiction = state.sys.getAbbreviation(state.opt.styleID, state.transform.abbrevs, jurisdiction, category, orig);
            if (!jurisdiction) {
              jurisdiction = "default";
              if (domain) {
                jurisdiction += "@" + domain;
              }
            }
          }
          return jurisdiction;
        }
        this.loadAbbreviation = loadAbbreviation;
        function publisherCheck(tok, Item, primary, family_var) {
          var varname = tok.variables[0];
          if (state.publisherOutput && primary) {
            if (["publisher", "publisher-place"].indexOf(varname) === -1) {
              return false;
            } else {
              state.publisherOutput[varname + "-token"] = tok;
              state.publisherOutput.varlist.push(varname);
              var lst = primary.split(/;\s*/);
              if (lst.length === state.publisherOutput[varname + "-list"].length) {
                state.publisherOutput[varname + "-list"] = lst;
              }
              for (var i = 0, ilen = lst.length; i < ilen; i += 1) {
                lst[i] = abbreviate(state, tok, Item, false, lst[i], family_var, true);
              }
              state.tmp[varname + "-token"] = tok;
              return true;
            }
          }
          return false;
        }
        function citeFormCheck(Item, value) {
          var m = value.match(/^#([0-9]+).*>>>/);
          if (m && m[1]) {
            Item["cite-form"] = m[1];
          }
        }
        function quashCheck(jurisdiction, value) {
          var m = value.match(/^(?:#[0-9]+)*(?:!((?:[-_a-z]+(?:(?:.*)))(?:,(?:[-_a-z]+(?:(?:.*))))*))*>>>/);
          if (m) {
            value = value.slice(m[0].length);
            if (m[1]) {
              var fields = m[1].split(",");
              for (var i = 0, ilen = fields.length; i < ilen; i += 1) {
                var rawField = fields[i];
                var mm = rawField.match(/^([-_a-z]+)(?:\:(.*))*$/);
                var field = mm[1];
                var trimmer = state.tmp.abbrev_trimmer;
                if (mm[2]) {
                  if (trimmer && jurisdiction) {
                    if (!trimmer[jurisdiction]) {
                      trimmer[jurisdiction] = {};
                    }
                    trimmer[jurisdiction][field] = mm[2];
                  }
                } else if (state.tmp.done_vars.indexOf(field) === -1) {
                  if (trimmer && jurisdiction) {
                    if (!trimmer.QUASHES[jurisdiction]) {
                      trimmer.QUASHES[jurisdiction] = {};
                    }
                    trimmer.QUASHES[jurisdiction][field] = true;
                  }
                  state.tmp.done_vars.push(field);
                }
              }
            }
          }
          return value;
        }
        this.quashCheck = quashCheck;
        function getOutputFunction(variables, family_var, abbreviation_fallback, alternative_varname) {
          var localesets;
          var langPrefs = CSL2.LangPrefsMap[variables[0]];
          if (!langPrefs) {
            localesets = false;
          } else {
            localesets = state.opt["cite-lang-prefs"][langPrefs];
          }
          return function(state2, Item, item) {
            var primary, primary_locale, secondary, secondary_locale, tertiary, tertiary_locale, primary_tok;
            if (!variables[0] || !Item[variables[0]] && !Item[alternative_varname]) {
              return null;
            }
            if (!state2.tmp.just_looking && item && item["suppress-author"]) {
              if (!state2.tmp.probably_rendered_something && state2.tmp.can_substitute.length() > 1) {
                return null;
              }
            }
            var slot = { primary: false, secondary: false, tertiary: false };
            if (state2.tmp.area.slice(-5) === "_sort") {
              slot.primary = "locale-sort";
            } else {
              if (localesets && localesets.length === 1 && localesets[0] === "locale-orig") {
                slot.primary = "locale-orig";
                localesets = false;
              } else if (localesets && !state2.tmp.multi_layout) {
                var slotnames = ["primary", "secondary", "tertiary"];
                for (var i = 0, ilen = slotnames.length; i < ilen; i += 1) {
                  if (localesets.length - 1 < i) {
                    break;
                  }
                  if (localesets[i]) {
                    slot[slotnames[i]] = "locale-" + localesets[i];
                  }
                }
              } else {
                slot.primary = "locale-orig";
              }
            }
            if (variables[0] === "title-short" || state2.tmp.area !== "bibliography" && !(state2.tmp.area === "citation" && state2.opt.xclass === "note" && item && !item.position)) {
              slot.secondary = false;
              slot.tertiary = false;
            }
            if (state2.tmp.multi_layout) {
              slot.secondary = false;
              slot.tertiary = false;
            }
            if (state2.tmp["publisher-list"]) {
              if (variables[0] === "publisher") {
                state2.tmp["publisher-token"] = this;
              } else if (variables[0] === "publisher-place") {
                state2.tmp["publisher-place-token"] = this;
              }
              return null;
            }
            var oldLangArray = state2.tmp.lang_array.slice();
            var res = getTextSubField.call(this, Item, variables[0], slot.primary, true, null, family_var);
            primary = res.name;
            primary_locale = res.locale;
            var primary_tok = res.token;
            var primaryUsedOrig = res.usedOrig;
            if (family_var && !res.found_variant_ok) {
              primary = abbreviate(state2, primary_tok, Item, alternative_varname, primary, family_var, true);
              if (primary) {
                citeFormCheck(Item, primary);
                if (!state2.tmp.just_looking) {
                  primary = quashCheck(Item.jurisdiction, primary);
                }
              }
            }
            if (publisherCheck(this, Item, primary, family_var)) {
              state2.tmp.lang_array = oldLangArray;
              return null;
            }
            secondary = false;
            tertiary = false;
            var secondary_tok;
            var tertiary_tok;
            if (slot.secondary) {
              res = getTextSubField.call(this, Item, variables[0], slot.secondary, false, res.usedOrig, null, family_var);
              secondary = res.name;
              secondary_locale = res.locale;
              secondary_tok = res.token;
              if (family_var && !res.found_variant_ok) {
                if (secondary) {
                  secondary = abbreviate(state2, secondary_tok, Item, false, secondary, family_var, true);
                }
              }
            }
            if (slot.tertiary) {
              res = getTextSubField.call(this, Item, variables[0], slot.tertiary, false, res.usedOrig, null, family_var);
              tertiary = res.name;
              tertiary_locale = res.locale;
              tertiary_tok = res.token;
              if (family_var && !res.found_variant_ok) {
                if (tertiary) {
                  tertiary = abbreviate(state2, tertiary_tok, Item, false, tertiary, family_var, true);
                }
              }
            }
            var primaryPrefix;
            if (slot.primary === "locale-translit") {
              primaryPrefix = state2.opt.citeAffixes[langPrefs][slot.primary].prefix;
            }
            if (primaryPrefix === "<i>" && variables[0] === "title" && !primaryUsedOrig) {
              var hasItalic = false;
              for (var i = 0, ilen = primary_tok.decorations.length; i < ilen; i += 1) {
                if (primary_tok.decorations[i][0] === "@font-style" && primary_tok.decorations[i][1] === "italic") {
                  hasItalic = true;
                }
              }
              if (!hasItalic) {
                primary_tok.decorations.push(["@font-style", "italic"]);
              }
            }
            if (primary_locale !== "en" && primary_tok.strings["text-case"] === "title") {
              primary_tok.strings["text-case"] = "passthrough";
            }
            if ("title" === variables[0]) {
              primary = CSL2.demoteNoiseWords(state2, primary, this["leading-noise-words"]);
            }
            if (secondary || tertiary) {
              state2.output.openLevel("empty");
              primary_tok.strings.suffix = primary_tok.strings.suffix.replace(/[ .,]+$/, "");
              if (primary_locale) {
                state2.tmp.lang_array = [primary_locale].concat(oldLangArray);
              }
              CSL2.UPDATE_GROUP_CONTEXT_CONDITION(state2, null, null, primary_tok, primary_tok.strings.prefix + primary);
              state2.output.append(primary, primary_tok);
              state2.tmp.probably_rendered_something = true;
              if (primary === secondary) {
                secondary = false;
              }
              if (secondary) {
                secondary_tok.strings.prefix = state2.opt.citeAffixes[langPrefs][slot.secondary].prefix;
                secondary_tok.strings.suffix = state2.opt.citeAffixes[langPrefs][slot.secondary].suffix;
                if (!secondary_tok.strings.prefix) {
                  secondary_tok.strings.prefix = " ";
                }
                for (var i = secondary_tok.decorations.length - 1; i > -1; i += -1) {
                  if (["@quotes/true", "@font-style/italic", "@font-style/oblique", "@font-weight/bold"].indexOf(secondary_tok.decorations[i].join("/")) > -1) {
                    secondary_tok.decorations = secondary_tok.decorations.slice(0, i).concat(secondary_tok.decorations.slice(i + 1));
                  }
                }
                if (secondary_locale !== "en" && secondary_tok.strings["text-case"] === "title") {
                  secondary_tok.strings["text-case"] = "passthrough";
                }
                if (secondary_locale) {
                  state2.tmp.lang_array = [secondary_locale].concat(oldLangArray);
                }
                var secondary_outer = new CSL2.Token();
                secondary_outer.decorations.push(["@font-style", "normal"]);
                secondary_outer.decorations.push(["@font-weight", "normal"]);
                state2.output.openLevel(secondary_outer);
                state2.output.append(secondary, secondary_tok);
                state2.output.closeLevel();
                var blob_obj = state2.output.current.value();
                var blobs_pos = state2.output.current.value().blobs.length - 1;
              }
              if (primary === tertiary) {
                tertiary = false;
              }
              if (tertiary) {
                tertiary_tok.strings.prefix = state2.opt.citeAffixes[langPrefs][slot.tertiary].prefix;
                tertiary_tok.strings.suffix = state2.opt.citeAffixes[langPrefs][slot.tertiary].suffix;
                if (!tertiary_tok.strings.prefix) {
                  tertiary_tok.strings.prefix = " ";
                }
                for (var i = tertiary_tok.decorations.length - 1; i > -1; i += -1) {
                  if (["@quotes/true", "@font-style/italic", "@font-style/oblique", "@font-weight/bold"].indexOf(tertiary_tok.decorations[i].join("/")) > -1) {
                    tertiary_tok.decorations = tertiary_tok.decorations.slice(0, i).concat(tertiary_tok.decorations.slice(i + 1));
                  }
                }
                if (tertiary_locale !== "en" && tertiary_tok.strings["text-case"] === "title") {
                  tertiary_tok.strings["text-case"] = "passthrough";
                }
                if (tertiary_locale) {
                  state2.tmp.lang_array = [tertiary_locale].concat(oldLangArray);
                }
                var tertiary_outer = new CSL2.Token();
                tertiary_outer.decorations.push(["@font-style", "normal"]);
                tertiary_outer.decorations.push(["@font-weight", "normal"]);
                state2.output.openLevel(tertiary_outer);
                state2.output.append(tertiary, tertiary_tok);
                state2.output.closeLevel();
                var blob_obj = state2.output.current.value();
                var blobs_pos = state2.output.current.value().blobs.length - 1;
              }
              state2.output.closeLevel();
            } else {
              if (primary_locale) {
                state2.tmp.lang_array = [primary_locale].concat(oldLangArray);
              }
              CSL2.UPDATE_GROUP_CONTEXT_CONDITION(state2, null, null, primary_tok, primary_tok.strings.prefix + primary);
              state2.output.append(primary, primary_tok);
              state2.tmp.probably_rendered_something = true;
            }
            state2.tmp.lang_array = oldLangArray;
            if (state2.tmp.can_block_substitute) {
              state2.tmp.name_node.children.push(state2.output.current.value());
            }
            return null;
          };
        }
        this.getOutputFunction = getOutputFunction;
      };
      CSL2.Token = function(name, tokentype, conditional) {
        this.name = name;
        this.strings = {};
        this.strings.delimiter = void 0;
        this.strings.prefix = "";
        this.strings.suffix = "";
        this.decorations = [];
        this.variables = [];
        this.execs = [];
        this.tokentype = tokentype;
      };
      CSL2.Util.cloneToken = function(token) {
        var newtok, key, pos, len;
        if ("string" === typeof token) {
          return token;
        }
        newtok = new CSL2.Token(token.name, token.tokentype);
        for (var key in token.strings) {
          if (token.strings.hasOwnProperty(key)) {
            newtok.strings[key] = token.strings[key];
          }
        }
        if (token.decorations) {
          newtok.decorations = [];
          for (pos = 0, len = token.decorations.length; pos < len; pos += 1) {
            newtok.decorations.push(token.decorations[pos].slice());
          }
        }
        if (token.variables) {
          newtok.variables = token.variables.slice();
        }
        if (token.execs) {
          newtok.execs = token.execs.slice();
          if (token.tests) {
            newtok.tests = token.tests.slice();
          }
        }
        return newtok;
      };
      CSL2.AmbigConfig = function() {
        this.maxvals = [];
        this.minval = 1;
        this.names = [];
        this.givens = [];
        this.year_suffix = false;
        this.disambiguate = 0;
      };
      CSL2.Blob = function(str, token, levelname) {
        var len, pos, key;
        this.levelname = levelname;
        if (token) {
          this.strings = { "prefix": "", "suffix": "" };
          for (var key in token.strings) {
            if (token.strings.hasOwnProperty(key)) {
              this.strings[key] = token.strings[key];
            }
          }
          this.decorations = [];
          if (token.decorations === void 0) {
            len = 0;
          } else {
            len = token.decorations.length;
          }
          for (pos = 0; pos < len; pos += 1) {
            this.decorations.push(token.decorations[pos].slice());
          }
        } else {
          this.strings = {};
          this.strings.prefix = "";
          this.strings.suffix = "";
          this.strings.delimiter = "";
          this.decorations = [];
        }
        if ("string" === typeof str) {
          this.blobs = str;
        } else if (str) {
          this.blobs = [str];
        } else {
          this.blobs = [];
        }
        this.alldecor = [this.decorations];
      };
      CSL2.Blob.prototype.push = function(blob) {
        if ("string" === typeof this.blobs) {
          CSL2.error("Attempt to push blob onto string object");
        } else if (false !== blob) {
          blob.alldecor = blob.alldecor.concat(this.alldecor);
          this.blobs.push(blob);
        }
      };
      CSL2.NumericBlob = function(state, particle, num, mother_token, id) {
        this.id = id;
        this.alldecor = [];
        this.num = num;
        this.particle = particle;
        this.blobs = num.toString();
        this.status = CSL2.START;
        this.strings = {};
        if (mother_token) {
          if (mother_token.strings["text-case"]) {
            var textCase = mother_token.strings["text-case"];
            this.particle = CSL2.Output.Formatters[textCase](state, this.particle);
            this.blobs = CSL2.Output.Formatters[textCase](state, this.blobs);
          }
          this.gender = mother_token.gender;
          this.decorations = mother_token.decorations;
          this.strings.prefix = mother_token.strings.prefix;
          this.strings.suffix = mother_token.strings.suffix;
          this.strings["text-case"] = mother_token.strings["text-case"];
          this.successor_prefix = mother_token.successor_prefix;
          this.range_prefix = mother_token.range_prefix;
          this.splice_prefix = mother_token.splice_prefix;
          this.formatter = mother_token.formatter;
          if (!this.formatter) {
            this.formatter = new CSL2.Output.DefaultFormatter();
          }
          if (this.formatter) {
            this.type = this.formatter.format(1);
          }
        } else {
          this.decorations = [];
          this.strings.prefix = "";
          this.strings.suffix = "";
          this.successor_prefix = "";
          this.range_prefix = "";
          this.splice_prefix = "";
          this.formatter = new CSL2.Output.DefaultFormatter();
        }
      };
      CSL2.NumericBlob.prototype.setFormatter = function(formatter) {
        this.formatter = formatter;
        this.type = this.formatter.format(1);
      };
      CSL2.Output.DefaultFormatter = function() {
      };
      CSL2.Output.DefaultFormatter.prototype.format = function(num) {
        return num.toString();
      };
      CSL2.NumericBlob.prototype.checkNext = function(next, start) {
        if (start) {
          this.status = CSL2.START;
          if ("object" === typeof next) {
            if (next.num === this.num + 1) {
              next.status = CSL2.SUCCESSOR;
            } else {
              next.status = CSL2.SEEN;
            }
          }
        } else if (!next || !next.num || this.type !== next.type || next.num !== this.num + 1) {
          if (this.status === CSL2.SUCCESSOR_OF_SUCCESSOR) {
            this.status = CSL2.END;
          }
          if ("object" === typeof next) {
            next.status = CSL2.SEEN;
          }
        } else {
          if (this.status === CSL2.START || this.status === CSL2.SEEN) {
            next.status = CSL2.SUCCESSOR;
          } else if (this.status === CSL2.SUCCESSOR || this.status === CSL2.SUCCESSOR_OF_SUCCESSOR) {
            if (this.range_prefix) {
              next.status = CSL2.SUCCESSOR_OF_SUCCESSOR;
              this.status = CSL2.SUPPRESS;
            } else {
              next.status = CSL2.SUCCESSOR;
            }
          }
        }
      };
      CSL2.NumericBlob.prototype.checkLast = function(last) {
        if (this.status === CSL2.SEEN || last.num !== this.num - 1 && this.status === CSL2.SUCCESSOR) {
          this.status = CSL2.SUCCESSOR;
          return true;
        }
        return false;
      };
      CSL2.Util.fixDateNode = function(parent, pos, node) {
        var form, variable, datexml, subnode, partname, attr, val, prefix, suffix, children, subchildren, display, cslid;
        var lingo = this.cslXml.getAttributeValue(node, "lingo");
        var default_locale = this.cslXml.getAttributeValue(node, "default-locale");
        this.build.date_key = true;
        form = this.cslXml.getAttributeValue(node, "form");
        var lingo;
        if (default_locale) {
          lingo = this.opt["default-locale"][0];
        } else {
          lingo = this.cslXml.getAttributeValue(node, "lingo");
        }
        if (!this.getDate(form, default_locale)) {
          return parent;
        }
        var dateparts = this.cslXml.getAttributeValue(node, "date-parts");
        variable = this.cslXml.getAttributeValue(node, "variable");
        prefix = this.cslXml.getAttributeValue(node, "prefix");
        suffix = this.cslXml.getAttributeValue(node, "suffix");
        display = this.cslXml.getAttributeValue(node, "display");
        cslid = this.cslXml.getAttributeValue(node, "cslid");
        datexml = this.cslXml.nodeCopy(this.getDate(form, default_locale));
        this.cslXml.setAttribute(datexml, "lingo", this.opt.lang);
        this.cslXml.setAttribute(datexml, "form", form);
        this.cslXml.setAttribute(datexml, "date-parts", dateparts);
        this.cslXml.setAttribute(datexml, "cslid", cslid);
        this.cslXml.setAttribute(datexml, "variable", variable);
        this.cslXml.setAttribute(datexml, "default-locale", default_locale);
        if (prefix) {
          this.cslXml.setAttribute(datexml, "prefix", prefix);
        }
        if (suffix) {
          this.cslXml.setAttribute(datexml, "suffix", suffix);
        }
        if (display) {
          this.cslXml.setAttribute(datexml, "display", display);
        }
        children = this.cslXml.children(datexml);
        for (var key in children) {
          subnode = children[key];
          if ("date-part" === this.cslXml.nodename(subnode)) {
            partname = this.cslXml.getAttributeValue(subnode, "name");
            if (default_locale) {
              this.cslXml.setAttributeOnNodeIdentifiedByNameAttribute(datexml, "date-part", partname, "@default-locale", "true");
            }
          }
        }
        children = this.cslXml.children(node);
        for (var key in children) {
          subnode = children[key];
          if ("date-part" === this.cslXml.nodename(subnode)) {
            partname = this.cslXml.getAttributeValue(subnode, "name");
            subchildren = this.cslXml.attributes(subnode);
            for (attr in subchildren) {
              if ("@name" === attr) {
                continue;
              }
              if (lingo && lingo !== this.opt.lang) {
                if (["@suffix", "@prefix", "@form"].indexOf(attr) > -1) {
                  continue;
                }
              }
              val = subchildren[attr];
              this.cslXml.setAttributeOnNodeIdentifiedByNameAttribute(datexml, "date-part", partname, attr, val);
            }
          }
        }
        if ("year" === this.cslXml.getAttributeValue(node, "date-parts")) {
          this.cslXml.deleteNodeByNameAttribute(datexml, "month");
          this.cslXml.deleteNodeByNameAttribute(datexml, "day");
        } else if ("year-month" === this.cslXml.getAttributeValue(node, "date-parts")) {
          this.cslXml.deleteNodeByNameAttribute(datexml, "day");
        } else if ("month-day" === this.cslXml.getAttributeValue(node, "date-parts")) {
          var childNodes = this.cslXml.children(datexml);
          for (var i = 1, ilen = this.cslXml.numberofnodes(childNodes); i < ilen; i++) {
            if (this.cslXml.getAttributeValue(childNodes[i], "name") === "year") {
              this.cslXml.setAttribute(childNodes[i - 1], "suffix", "");
              break;
            }
          }
          this.cslXml.deleteNodeByNameAttribute(datexml, "year");
        }
        return this.cslXml.insertChildNodeAfter(parent, node, pos, datexml);
      };
      CSL2.dateMacroAsSortKey = function(state, Item) {
        CSL2.dateAsSortKey.call(this, state, Item, true);
      };
      CSL2.dateAsSortKey = function(state, Item, isMacro) {
        var dp, elem, value, e, yr, prefix, i, ilen;
        var variable = this.variables[0];
        var macroFlag = "empty";
        if (isMacro && state.tmp.extension) {
          macroFlag = "macro-with-date";
        }
        dp = Item[variable];
        if ("undefined" === typeof dp) {
          dp = { "date-parts": [[0]] };
        }
        if ("undefined" === typeof this.dateparts) {
          this.dateparts = ["year", "month", "day"];
        }
        if (dp.raw) {
          dp = state.fun.dateparser.parseDateToArray(dp.raw);
        } else if (dp["date-parts"]) {
          dp = state.dateParseArray(dp);
        }
        if ("undefined" === typeof dp) {
          dp = {};
        }
        if (dp.year) {
          for (i = 0, ilen = CSL2.DATE_PARTS_INTERNAL.length; i < ilen; i += 1) {
            elem = CSL2.DATE_PARTS_INTERNAL[i];
            value = 0;
            e = elem;
            if (e.slice(-4) === "_end") {
              e = e.slice(0, -4);
            }
            if (dp[elem] && this.dateparts.indexOf(e) > -1) {
              value = dp[elem];
            }
            if (elem.slice(0, 4) === "year") {
              yr = CSL2.Util.Dates[e].numeric(state, value);
              var prefix = "1";
              if (yr[0] === "-") {
                prefix = "0";
                yr = yr.slice(1);
                yr = 9999 - parseInt(yr, 10);
              }
              state.output.append(CSL2.Util.Dates[elem.slice(0, 4)].numeric(state, prefix + yr), macroFlag);
            } else {
              value = CSL2.Util.Dates[e]["numeric-leading-zeros"](state, value);
              if (!value) {
                value = "00";
              }
              state.output.append(value, macroFlag);
            }
          }
        }
      };
      CSL2.Engine.prototype.dateParseArray = function(date_obj) {
        var ret, field, dp, exts;
        ret = {};
        for (field in date_obj) {
          if (field === "date-parts") {
            dp = date_obj["date-parts"];
            if (dp.length > 1) {
              if (dp[0].length !== dp[1].length) {
                CSL2.error("CSL data error: element mismatch in date range input.");
              }
            }
            exts = ["", "_end"];
            for (var i = 0, ilen = dp.length; i < ilen; i += 1) {
              for (var j = 0, jlen = CSL2.DATE_PARTS.length; j < jlen; j += 1) {
                if (isNaN(parseInt(dp[i][j], 10))) {
                  ret[CSL2.DATE_PARTS[j] + exts[i]] = void 0;
                } else {
                  ret[CSL2.DATE_PARTS[j] + exts[i]] = parseInt(dp[i][j], 10);
                }
              }
            }
          } else if (date_obj.hasOwnProperty(field)) {
            if (field === "literal" && "object" === typeof date_obj.literal && "string" === typeof date_obj.literal.part) {
              CSL2.debug("Warning: fixing up weird literal date value");
              ret.literal = date_obj.literal.part;
            } else {
              ret[field] = date_obj[field];
            }
          }
        }
        return ret;
      };
      CSL2.Util.Names = {};
      CSL2.Util.Names.compareNamesets = CSL2.NameOutput.prototype._compareNamesets;
      CSL2.Util.Names.unInitialize = function(state, name) {
        var i, ilen, namelist, punctlist, ret;
        if (!name) {
          return "";
        }
        namelist = name.split(/(?:\-|\s+)/);
        punctlist = name.match(/(\-|\s+)/g);
        ret = "";
        for (i = 0, ilen = namelist.length; i < ilen; i += 1) {
          ret += namelist[i];
          if (i < ilen - 1) {
            ret += punctlist[i];
          }
        }
        return ret;
      };
      CSL2.Util.Names.initializeWith = function(state, name, terminator, normalizeOnly) {
        var i, ilen, mm, lst, ret;
        if (!name) {
          return "";
        }
        if (!terminator) {
          terminator = "";
        }
        if (["Lord", "Lady"].indexOf(name) > -1 || !name.replace(/^(?:<[^>]+>)*/, "").match(CSL2.STARTSWITH_ROMANESQUE_REGEXP) && !terminator.match("%s")) {
          return name;
        }
        if (state.opt["initialize-with-hyphen"] === false) {
          name = name.replace(/\-/g, " ");
        }
        name = name.replace(/\s*\-\s*/g, "-").replace(/\s+/g, " ");
        name = name.replace(/-([a-z])/g, "\u2013$1");
        for (var i = name.length - 2; i > -1; i += -1) {
          if (name.slice(i, i + 1) === "." && name.slice(i + 1, i + 2) !== " ") {
            name = name.slice(0, i) + ". " + name.slice(i + 1);
          }
        }
        var nameSplits = CSL2.Output.Formatters.nameDoppel.split(name);
        var namelist = [];
        namelist = [nameSplits.strings[0]];
        if (nameSplits.tags.length === 0) {
          var mmm = namelist[0].match(/[^\.]+$/);
          if (mmm && mmm[0].length === 1 && mmm[0] !== mmm[0].toLowerCase()) {
            namelist[0] += ".";
          }
        }
        for (i = 1, ilen = nameSplits.strings.length; i < ilen; i += 1) {
          namelist.push(nameSplits.tags[i - 1]);
          namelist.push(nameSplits.strings[i]);
        }
        if (normalizeOnly) {
          ret = this.doNormalize(state, namelist, terminator);
        } else {
          ret = this.doInitialize(state, namelist, terminator);
        }
        ret = ret.replace(/\u2013([a-z])/g, "-$1");
        return ret;
      };
      CSL2.Util.Names.notag = function(str) {
        return str.replace(/^(?:<[^>]+>)*/, "");
      };
      CSL2.Util.Names.mergetag = function(state, tagstr, newstr) {
        var m = tagstr.match(/(?:-*<[^>]+>-*)/g);
        if (!m) {
          return newstr;
        } else {
          tagstr = m.join("");
        }
        m = newstr.match(/^(.*[^\s])*(\s+)$/);
        if (m) {
          m[1] = m[1] ? m[1] : "";
          newstr = m[1] + tagstr + m[2];
        } else {
          newstr = newstr + tagstr;
        }
        return newstr;
      };
      CSL2.Util.Names.tagonly = function(state, str) {
        var m = str.match(/(?:<[^>]+>)+/);
        if (!m) {
          return str;
        } else {
          return m.join("");
        }
      };
      CSL2.Util.Names.doNormalize = function(state, namelist, terminator) {
        var i, ilen;
        terminator = terminator ? terminator : "";
        var isAbbrev = [];
        for (i = 0, ilen = namelist.length; i < ilen; i += 1) {
          if (this.notag(namelist[i]).length > 1 && this.notag(namelist[i]).slice(-1) === ".") {
            namelist[i] = namelist[i].replace(/^(.*)\.(.*)$/, "$1$2");
            isAbbrev.push(true);
          } else if (namelist[i].length === 1 && namelist[i].toUpperCase() === namelist[i]) {
            isAbbrev.push(true);
          } else {
            isAbbrev.push(false);
          }
        }
        for (i = 0, ilen = namelist.length; i < ilen; i += 2) {
          if (isAbbrev[i]) {
            if (i < namelist.length - 2) {
              namelist[i + 1] = this.tagonly(state, namelist[i + 1]);
              if (!isAbbrev[i + 2]) {
                namelist[i + 1] = this.tagonly(state, namelist[i + 1]) + " ";
              }
              if (namelist[i + 2].length > 1) {
                namelist[i + 1] = terminator.replace(/\ufeff$/, "") + namelist[i + 1];
              } else {
                namelist[i + 1] = this.mergetag(state, namelist[i + 1], terminator);
              }
            }
            if (i === namelist.length - 1) {
              namelist[i] = namelist[i] + terminator;
            }
          }
        }
        return namelist.join("").replace(/[\u0009\u000a\u000b\u000c\u000d\u0020\ufeff\u00a0]+$/, "").replace(/\s*\-\s*/g, "-").replace(/[\u0009\u000a\u000b\u000c\u000d\u0020]+/g, " ");
      };
      CSL2.Util.Names.doInitialize = function(state, namelist, terminator) {
        var i, ilen, m, j, jlen, lst, n;
        for (i = 0, ilen = namelist.length; i < ilen; i += 2) {
          n = namelist[i];
          if (!n) {
            continue;
          }
          m = n.match(CSL2.NAME_INITIAL_REGEXP);
          if (!m && (!n.match(CSL2.STARTSWITH_ROMANESQUE_REGEXP) && n.length > 1 && terminator.match("%s"))) {
            m = n.match(/(.)(.*)/);
          }
          if (m && m[2] && m[3]) {
            m[1] = m[1] + m[2];
            m[2] = "";
          }
          if (m && m[1].slice(0, 1) === m[1].slice(0, 1).toUpperCase()) {
            var extra = "";
            if (m[2]) {
              var s = "";
              lst = m[2].split("");
              for (j = 0, jlen = lst.length; j < jlen; j += 1) {
                var c = lst[j];
                if (c === c.toUpperCase()) {
                  s += c;
                } else {
                  break;
                }
              }
              if (s.length < m[2].length) {
                extra = CSL2.toLocaleLowerCase.call(state, s);
              }
            }
            namelist[i] = m[1] + extra;
            if (i < ilen - 1) {
              if (terminator.match("%s")) {
                namelist[i] = terminator.replace("%s", namelist[i]);
              } else {
                if (namelist[i + 1].indexOf("-") > -1) {
                  namelist[i + 1] = this.mergetag(state, namelist[i + 1].replace("-", ""), terminator) + "-";
                } else {
                  namelist[i + 1] = this.mergetag(state, namelist[i + 1], terminator);
                }
              }
            } else {
              if (terminator.match("%s")) {
                namelist[i] = terminator.replace("%s", namelist[i]);
              } else {
                namelist.push(terminator);
              }
            }
          } else if (n.match(CSL2.ROMANESQUE_REGEXP) && (!m || !m[3])) {
            namelist[i] = " " + n;
          }
        }
        var ret = namelist.join("");
        ret = ret.replace(/[\u0009\u000a\u000b\u000c\u000d\u0020\ufeff\u00a0]+$/, "").replace(/\s*\-\s*/g, "-").replace(/[\u0009\u000a\u000b\u000c\u000d\u0020]+/g, " ");
        return ret;
      };
      CSL2.Util.Names.getRawName = function(name) {
        var ret = [];
        if (name.literal) {
          ret.push(name.literal);
        } else {
          if (name.given) {
            ret.push(name.given);
          }
          if (name.family) {
            ret.push(name.family);
          }
        }
        return ret.join(" ");
      };
      CSL2.Util.Dates = {};
      CSL2.Util.Dates.year = {};
      CSL2.Util.Dates.year["long"] = function(state, num) {
        if (!num) {
          if ("boolean" === typeof num) {
            num = "";
          } else {
            num = 0;
          }
        }
        return num.toString();
      };
      CSL2.Util.Dates.year.imperial = function(state, num, end) {
        var year = "";
        if (!num) {
          if ("boolean" === typeof num) {
            num = "";
          } else {
            num = 0;
          }
        }
        end = end ? "_end" : "";
        var month = state.tmp.date_object["month" + end];
        month = month ? "" + month : "1";
        while (month.length < 2) {
          month = "0" + month;
        }
        var day = state.tmp.date_object["day" + end];
        day = day ? "" + day : "1";
        while (day.length < 2) {
          day = "0" + day;
        }
        var date = parseInt(num + month + day, 10);
        var label;
        var offset;
        if (date >= 18680908 && date < 19120730) {
          label = "\u660E\u6CBB";
          offset = 1867;
        } else if (date >= 19120730 && date < 19261225) {
          label = "\u5927\u6B63";
          offset = 1911;
        } else if (date >= 19261225 && date < 19890108) {
          label = "\u662D\u548C";
          offset = 1925;
        } else if (date >= 19890108) {
          label = "\u5E73\u6210";
          offset = 1988;
        }
        if (label && offset) {
          var normalizedKey = label;
          if (state.sys.normalizeAbbrevsKey) {
            normalizedKey = state.sys.normalizeAbbrevsKey("number", label);
          }
          if (!state.transform.abbrevs["default"]["number"][normalizedKey]) {
            state.transform.loadAbbreviation("default", "number", normalizedKey, null);
          }
          if (state.transform.abbrevs["default"]["number"][normalizedKey]) {
            label = state.transform.abbrevs["default"]["number"][normalizedKey];
          }
          year = label + (num - offset);
        }
        return year;
      };
      CSL2.Util.Dates.year["short"] = function(state, num) {
        num = num.toString();
        if (num && num.length === 4) {
          return num.substr(2);
        }
      };
      CSL2.Util.Dates.year.numeric = function(state, num) {
        var m, pre;
        num = "" + num;
        var m = num.match(/([0-9]*)$/);
        if (m) {
          pre = num.slice(0, m[1].length * -1);
          num = m[1];
        } else {
          pre = num;
          num = "";
        }
        while (num.length < 4) {
          num = "0" + num;
        }
        return pre + num;
      };
      CSL2.Util.Dates.normalizeMonth = function(num, useSeason) {
        var ret;
        if (!num) {
          num = 0;
        }
        num = "" + num;
        if (!num.match(/^[0-9]+$/)) {
          num = 0;
        }
        num = parseInt(num, 10);
        if (useSeason) {
          var res = { stub: "month-", num };
          if (res.num < 1 || res.num > 24) {
            res.num = 0;
          } else {
            while (res.num > 16) {
              res.num = res.num - 4;
            }
            if (res.num > 12) {
              res.stub = "season-";
              res.num = res.num - 12;
            }
          }
          ret = res;
        } else {
          if (num < 1 || num > 12) {
            num = 0;
          }
          ret = num;
        }
        return ret;
      };
      CSL2.Util.Dates.month = {};
      CSL2.Util.Dates.month.numeric = function(state, num) {
        var num = CSL2.Util.Dates.normalizeMonth(num);
        if (!num) {
          num = "";
        }
        return num;
      };
      CSL2.Util.Dates.month["numeric-leading-zeros"] = function(state, num) {
        var num = CSL2.Util.Dates.normalizeMonth(num);
        if (!num) {
          num = "";
        } else {
          num = "" + num;
          while (num.length < 2) {
            num = "0" + num;
          }
        }
        return num;
      };
      CSL2.Util.Dates.month["long"] = function(state, num, gender, forceDefaultLocale) {
        var res = CSL2.Util.Dates.normalizeMonth(num, true);
        var num = res.num;
        if (!num) {
          num = "";
        } else {
          num = "" + num;
          while (num.length < 2) {
            num = "0" + num;
          }
          num = state.getTerm(res.stub + num, "long", 0, 0, false, forceDefaultLocale);
        }
        return num;
      };
      CSL2.Util.Dates.month["short"] = function(state, num, gender, forceDefaultLocale) {
        var res = CSL2.Util.Dates.normalizeMonth(num, true);
        var num = res.num;
        if (!num) {
          num = "";
        } else {
          num = "" + num;
          while (num.length < 2) {
            num = "0" + num;
          }
          num = state.getTerm(res.stub + num, "short", 0, 0, false, forceDefaultLocale);
        }
        return num;
      };
      CSL2.Util.Dates.day = {};
      CSL2.Util.Dates.day.numeric = function(state, num) {
        return num.toString();
      };
      CSL2.Util.Dates.day["long"] = CSL2.Util.Dates.day.numeric;
      CSL2.Util.Dates.day["numeric-leading-zeros"] = function(state, num) {
        if (!num) {
          num = 0;
        }
        num = num.toString();
        while (num.length < 2) {
          num = "0" + num;
        }
        return num.toString();
      };
      CSL2.Util.Dates.day.ordinal = function(state, num, gender) {
        return state.fun.ordinalizer.format(num, gender);
      };
      CSL2.Util.Sort = {};
      CSL2.Util.Sort.strip_prepositions = function(str) {
        var m;
        if ("string" === typeof str) {
          m = str.match(/^(([aA]|[aA][nN]|[tT][hH][eE])\s+)/);
        }
        if (m) {
          str = str.substr(m[1].length);
        }
        return str;
      };
      CSL2.Util.substituteStart = function(state, target) {
        var element_trace, display, bib_first, func, choose_start, if_start, nodetypes;
        func = function(state2, Item, item) {
          for (var i = 0, ilen = this.decorations.length; i < ilen; i += 1) {
            if ("@strip-periods" === this.decorations[i][0] && "true" === this.decorations[i][1]) {
              state2.tmp.strip_periods += 1;
              break;
            }
          }
        };
        this.execs.push(func);
        if (this.decorations && state.opt.development_extensions.csl_reverse_lookup_support) {
          this.decorations.reverse();
          this.decorations.push(["@showid", "true", this.cslid]);
          this.decorations.reverse();
        }
        nodetypes = ["number", "date", "names"];
        if ("text" === this.name && !this.postponed_macro || nodetypes.indexOf(this.name) > -1) {
          element_trace = function(state2, Item, item) {
            if (state2.tmp.element_trace.value() === "author" || "names" === this.name) {
              if (!state2.tmp.just_looking && item && item["author-only"] && state2.tmp.area !== "intext") {
                if (!state2.tmp.probably_rendered_something) {
                } else {
                  state2.tmp.element_trace.push("suppress-me");
                }
              }
              if (!state2.tmp.just_looking && item && item["suppress-author"]) {
                if (!state2.tmp.probably_rendered_something) {
                  state2.tmp.element_trace.push("suppress-me");
                }
              }
            } else if ("date" === this.name) {
              if (!state2.tmp.just_looking && item && item["author-only"] && state2.tmp.area !== "intext") {
                if (state2.tmp.probably_rendered_something) {
                  state2.tmp.element_trace.push("suppress-me");
                }
              }
            } else {
              if (!state2.tmp.just_looking && item && item["author-only"] && state2.tmp.area !== "intext") {
                if (!state2.tmp.probably_rendered_something && state2.tmp.can_block_substitute) {
                } else {
                  state2.tmp.element_trace.push("suppress-me");
                }
              } else if (item && item["suppress-author"]) {
                state2.tmp.element_trace.push("do-not-suppress-me");
              }
            }
          };
          this.execs.push(element_trace);
        }
        display = this.strings.cls;
        this.strings.cls = false;
        if (state.build.render_nesting_level === 0) {
          if (state.build.area === "bibliography" && state.bibliography.opt["second-field-align"]) {
            bib_first = new CSL2.Token("group", CSL2.START);
            bib_first.decorations = [["@display", "left-margin"]];
            func = function(state2, Item) {
              if (!state2.tmp.render_seen) {
                bib_first.strings.first_blob = Item.id;
                state2.output.startTag("bib_first", bib_first);
              }
            };
            bib_first.execs.push(func);
            target.push(bib_first);
          } else if (CSL2.DISPLAY_CLASSES.indexOf(display) > -1) {
            bib_first = new CSL2.Token("group", CSL2.START);
            bib_first.decorations = [["@display", display]];
            func = function(state2, Item) {
              bib_first.strings.first_blob = Item.id;
              state2.output.startTag("bib_first", bib_first);
            };
            bib_first.execs.push(func);
            target.push(bib_first);
          }
          state.build.cls = display;
        }
        state.build.render_nesting_level += 1;
        if (state.build.substitute_level.value() === 1) {
          choose_start = new CSL2.Token("choose", CSL2.START);
          CSL2.Node.choose.build.call(choose_start, state, target);
          if_start = new CSL2.Token("if", CSL2.START);
          func = function() {
            if (state.tmp.can_substitute.value()) {
              return true;
            }
            return false;
          };
          if_start.tests ? {} : if_start.tests = [];
          if_start.tests.push(func);
          if_start.test = state.fun.match.any(this, state, if_start.tests);
          target.push(if_start);
        }
        if (state.sys.variableWrapper && this.variables_real && this.variables_real.length) {
          func = function(state2, Item, item) {
            if (!state2.tmp.just_looking && !state2.tmp.suppress_decorations) {
              var variable_entry = new CSL2.Token("text", CSL2.START);
              variable_entry.decorations = [["@showid", "true"]];
              state2.output.startTag("variable_entry", variable_entry);
              var position = null;
              if (item) {
                position = item.position;
              }
              if (!position) {
                position = 0;
              }
              var positionMap = [
                "first",
                "container-subsequent",
                "subsequent",
                "ibid",
                "ibid-with-locator"
              ];
              var noteNumber = 0;
              if (item && item.noteIndex) {
                noteNumber = item.noteIndex;
              }
              var firstReferenceNoteNumber = 0;
              if (item && item["first-reference-note-number"]) {
                firstReferenceNoteNumber = item["first-reference-note-number"];
              }
              var firstContainerReferenceNoteNumber = 0;
              if (item && item["first-container-reference-note-number"]) {
                firstContainerReferenceNoteNumber = item["first-container-reference-note-number"];
              }
              var citationNumber = 0;
              if (item && item["citation-number"]) {
                citationNumber = item["citation-number"];
              }
              var index = 0;
              if (item && item.index) {
                index = item.index;
              }
              var params = {
                itemData: Item,
                variableNames: this.variables,
                context: state2.tmp.area,
                xclass: state2.opt.xclass,
                position: positionMap[position],
                "note-number": noteNumber,
                "first-reference-note-number": firstReferenceNoteNumber,
                "first-container-reference-note-number": firstContainerReferenceNoteNumber,
                "citation-number": citationNumber,
                "index": index,
                "mode": state2.opt.mode
              };
              state2.output.current.value().params = params;
            }
          };
          this.execs.push(func);
        }
      };
      CSL2.Util.substituteEnd = function(state, target) {
        var func, bib_first_end, bib_other, if_end, choose_end, author_substitute, str;
        if (state.sys.variableWrapper && (this.hasVariable || this.variables_real && this.variables_real.length)) {
          func = function(state2) {
            if (!state2.tmp.just_looking && !state2.tmp.suppress_decorations) {
              state2.output.endTag("variable_entry");
            }
          };
          this.execs.push(func);
        }
        func = function(state2) {
          for (var i = 0, ilen = this.decorations.length; i < ilen; i += 1) {
            if ("@strip-periods" === this.decorations[i][0] && "true" === this.decorations[i][1]) {
              state2.tmp.strip_periods += -1;
              break;
            }
          }
        };
        this.execs.push(func);
        state.build.render_nesting_level += -1;
        if (state.build.render_nesting_level === 0) {
          if (state.build.cls) {
            func = function(state2) {
              state2.output.endTag("bib_first");
            };
            this.execs.push(func);
            state.build.cls = false;
          } else if (state.build.area === "bibliography" && state.bibliography.opt["second-field-align"]) {
            bib_first_end = new CSL2.Token("group", CSL2.END);
            func = function(state2) {
              if (!state2.tmp.render_seen) {
                state2.output.endTag("bib_first");
              }
            };
            bib_first_end.execs.push(func);
            target.push(bib_first_end);
            bib_other = new CSL2.Token("group", CSL2.START);
            bib_other.decorations = [["@display", "right-inline"]];
            func = function(state2) {
              if (!state2.tmp.render_seen) {
                state2.tmp.render_seen = true;
                state2.output.startTag("bib_other", bib_other);
              }
            };
            bib_other.execs.push(func);
            target.push(bib_other);
          }
        }
        if (state.build.substitute_level.value() === 1) {
          if_end = new CSL2.Token("if", CSL2.END);
          target.push(if_end);
          choose_end = new CSL2.Token("choose", CSL2.END);
          CSL2.Node.choose.build.call(choose_end, state, target);
        }
        if ("names" === this.name || "text" === this.name && this.variables_real !== "title") {
          author_substitute = new CSL2.Token("text", CSL2.SINGLETON);
          var substitution_name = this.name;
          func = function(state2, Item) {
            if (state2.tmp.area !== "bibliography") {
              return;
            }
            if ("string" !== typeof state2.bibliography.opt["subsequent-author-substitute"]) {
              return;
            }
            if (this.variables_real && !Item[this.variables_real]) {
              return;
            }
            if (this.variables_real && substitution_name === "names") {
              return;
            }
            var subrule = state2.bibliography.opt["subsequent-author-substitute-rule"];
            var i, ilen;
            var printing = !state2.tmp.suppress_decorations;
            if (printing && state2.tmp.subsequent_author_substitute_ok) {
              if (state2.tmp.rendered_name) {
                if ("partial-each" === subrule || "partial-first" === subrule) {
                  var dosub = true;
                  var rendered_name = [];
                  for (i = 0, ilen = state2.tmp.name_node.children.length; i < ilen; i += 1) {
                    var name = state2.tmp.rendered_name[i];
                    if (dosub && state2.tmp.last_rendered_name && state2.tmp.last_rendered_name.length > i - 1 && name && !name.localeCompare(state2.tmp.last_rendered_name[i])) {
                      str = new CSL2.Blob(state2[state2.tmp.area].opt["subsequent-author-substitute"]);
                      state2.tmp.name_node.children[i].blobs = [str];
                      if ("partial-first" === subrule) {
                        dosub = false;
                      }
                    } else {
                      dosub = false;
                    }
                    rendered_name.push(name);
                  }
                  state2.tmp.last_rendered_name = rendered_name;
                } else if ("complete-each" === subrule) {
                  var rendered_name = state2.tmp.rendered_name.join(",");
                  if (rendered_name) {
                    if (state2.tmp.last_rendered_name && !rendered_name.localeCompare(state2.tmp.last_rendered_name)) {
                      for (i = 0, ilen = state2.tmp.name_node.children.length; i < ilen; i += 1) {
                        str = new CSL2.Blob(state2[state2.tmp.area].opt["subsequent-author-substitute"]);
                        state2.tmp.name_node.children[i].blobs = [str];
                      }
                    }
                    state2.tmp.last_rendered_name = rendered_name;
                  }
                } else {
                  var rendered_name = state2.tmp.rendered_name.join(",");
                  if (rendered_name) {
                    if (state2.tmp.last_rendered_name && !rendered_name.localeCompare(state2.tmp.last_rendered_name)) {
                      str = new CSL2.Blob(state2[state2.tmp.area].opt["subsequent-author-substitute"]);
                      if (state2.tmp.label_blob) {
                        state2.tmp.name_node.top.blobs = [str, state2.tmp.label_blob];
                      } else if (state2.tmp.name_node.top.blobs.length) {
                        state2.tmp.name_node.top.blobs[0].blobs = [str];
                      } else {
                        state2.tmp.name_node.top.blobs = [str];
                      }
                      state2.tmp.substituted_variable = substitution_name;
                    }
                    state2.tmp.last_rendered_name = rendered_name;
                  }
                }
                state2.tmp.subsequent_author_substitute_ok = false;
              }
            }
          };
          this.execs.push(func);
        }
        if ("text" === this.name && !this.postponed_macro || ["number", "date", "names"].indexOf(this.name) > -1) {
          func = function(state2, Item) {
            if (state2.tmp.element_trace.mystack.length > 1) {
              state2.tmp.element_trace.pop();
            }
          };
          this.execs.push(func);
        }
      };
      CSL2.Util.padding = function(num) {
        var m = num.match(/\s*(-{0,1}[0-9]+)/);
        if (m) {
          num = parseInt(m[1], 10);
          if (num < 0) {
            num = 1e20 + num;
          }
          num = "" + num;
          while (num.length < 20) {
            num = "0" + num;
          }
        }
        return num;
      };
      CSL2.Util.LongOrdinalizer = function() {
      };
      CSL2.Util.LongOrdinalizer.prototype.init = function(state) {
        this.state = state;
      };
      CSL2.Util.LongOrdinalizer.prototype.format = function(num, gender) {
        if (num < 10) {
          num = "0" + num;
        }
        var ret = CSL2.Engine.getField(
          CSL2.LOOSE,
          this.state.locale[this.state.opt.lang].terms,
          "long-ordinal-" + num,
          "long",
          0,
          gender
        );
        if (!ret) {
          ret = this.state.fun.ordinalizer.format(num, gender);
        }
        this.state.tmp.cite_renders_content = true;
        return ret;
      };
      CSL2.Util.Ordinalizer = function(state) {
        this.state = state;
        this.suffixes = {};
      };
      CSL2.Util.Ordinalizer.prototype.init = function() {
        if (!this.suffixes[this.state.opt.lang]) {
          this.suffixes[this.state.opt.lang] = {};
          for (var i = 0, ilen = 3; i < ilen; i += 1) {
            var gender = [void 0, "masculine", "feminine"][i];
            this.suffixes[this.state.opt.lang][gender] = [];
            for (var j = 1; j < 5; j += 1) {
              var ordinal = this.state.getTerm("ordinal-0" + j, "long", false, gender);
              if ("undefined" === typeof ordinal) {
                delete this.suffixes[this.state.opt.lang][gender];
                break;
              }
              this.suffixes[this.state.opt.lang][gender].push(ordinal);
            }
          }
        }
      };
      CSL2.Util.Ordinalizer.prototype.format = function(num, gender) {
        var str;
        num = parseInt(num, 10);
        str = "" + num;
        var suffix = "";
        var trygenders = [];
        if (gender) {
          trygenders.push(gender);
        }
        trygenders.push("neuter");
        if (this.state.locale[this.state.opt.lang].ord["1.0.1"]) {
          suffix = this.state.getTerm("ordinal", false, 0, gender);
          var trygender;
          for (var i = 0, ilen = trygenders.length; i < ilen; i += 1) {
            trygender = trygenders[i];
            var ordinfo = this.state.locale[this.state.opt.lang].ord["1.0.1"];
            if (ordinfo["whole-number"][str] && ordinfo["whole-number"][str][trygender]) {
              suffix = this.state.getTerm(this.state.locale[this.state.opt.lang].ord["1.0.1"]["whole-number"][str][trygender], false, 0, gender);
            } else if (ordinfo["last-two-digits"][str.slice(str.length - 2)] && ordinfo["last-two-digits"][str.slice(str.length - 2)][trygender]) {
              suffix = this.state.getTerm(this.state.locale[this.state.opt.lang].ord["1.0.1"]["last-two-digits"][str.slice(str.length - 2)][trygender], false, 0, gender);
            } else if (ordinfo["last-digit"][str.slice(str.length - 1)] && ordinfo["last-digit"][str.slice(str.length - 1)][trygender]) {
              suffix = this.state.getTerm(this.state.locale[this.state.opt.lang].ord["1.0.1"]["last-digit"][str.slice(str.length - 1)][trygender], false, 0, gender);
            }
            if (suffix) {
              break;
            }
          }
        } else {
          if (!gender) {
            gender = void 0;
          }
          this.state.fun.ordinalizer.init();
          if (num / 10 % 10 === 1 || num > 10 && num < 20) {
            suffix = this.suffixes[this.state.opt.lang][gender][3];
          } else if (num % 10 === 1 && num % 100 !== 11) {
            suffix = this.suffixes[this.state.opt.lang][gender][0];
          } else if (num % 10 === 2 && num % 100 !== 12) {
            suffix = this.suffixes[this.state.opt.lang][gender][1];
          } else if (num % 10 === 3 && num % 100 !== 13) {
            suffix = this.suffixes[this.state.opt.lang][gender][2];
          } else {
            suffix = this.suffixes[this.state.opt.lang][gender][3];
          }
        }
        str = str += suffix;
        return str;
      };
      CSL2.Util.Romanizer = function() {
      };
      CSL2.Util.Romanizer.prototype.format = function(num) {
        var ret, pos, n, numstr, len;
        ret = "";
        if (num < 6e3) {
          numstr = num.toString().split("");
          numstr.reverse();
          pos = 0;
          n = 0;
          len = numstr.length;
          for (pos = 0; pos < len; pos += 1) {
            n = parseInt(numstr[pos], 10);
            ret = CSL2.ROMAN_NUMERALS[pos][n] + ret;
          }
        }
        return ret;
      };
      CSL2.Util.Suffixator = function(slist) {
        if (!slist) {
          slist = CSL2.SUFFIX_CHARS;
        }
        this.slist = slist.split(",");
      };
      CSL2.Util.Suffixator.prototype.format = function(N) {
        var X;
        N += 1;
        var key = "";
        do {
          X = N % 26 === 0 ? 26 : N % 26;
          var key = this.slist[X - 1] + key;
          N = (N - X) / 26;
        } while (N !== 0);
        return key;
      };
      CSL2.Engine.prototype.processNumber = function(node, ItemObject, variable) {
        var val;
        var me = this;
        var realVariable = variable;
        variable = variable === "page-first" ? "page" : variable;
        var fullformAnd = ",\\s+and\\s+|\\s+and\\s+";
        if (this.opt.lang.slice(0, 2) !== "en") {
          fullformAnd += "|,\\s+" + this.getTerm("and") + "\\s+|\\s+" + this.getTerm("and") + "\\s+";
        }
        var symbolAnd = "\\s*&\\s*";
        var andRex = new RegExp("^" + symbolAnd + "$");
        var joinerMatchRex = new RegExp("(" + symbolAnd + "|" + fullformAnd + "|;\\s+|,\\s+|\\s*\\\\*[\\-\\u2013]+\\s*)", "g");
        var joinerSplitRex = new RegExp("(?:" + symbolAnd + "|" + fullformAnd + "|;\\s+|,\\s+|\\s*\\\\*[\\-\\u2013]+\\s*)");
        var localeAnd = this.getTerm("and");
        var localeAmpersand = this.getTerm("and", "symbol");
        if (localeAnd === localeAmpersand) {
          localeAmpersand = "&";
        }
        function normalizeFieldValue(str) {
          str = str.trim();
          var m = str.match(/^([^ ]+)/);
          if (m && !CSL2.STATUTE_SUBDIV_STRINGS[m[1]]) {
            var embeddedLabel = null;
            if (["locator", "locator-extra", "page"].indexOf(variable) > -1) {
              if (ItemObject.label) {
                embeddedLabel = CSL2.STATUTE_SUBDIV_STRINGS_REVERSE[ItemObject.label];
              } else {
                embeddedLabel = "p.";
              }
            } else {
              embeddedLabel = CSL2.STATUTE_SUBDIV_STRINGS_REVERSE[variable];
            }
            if (embeddedLabel) {
              str = embeddedLabel + " " + str;
            }
          }
          return str;
        }
        function composeNumberInfo(origLabel, label, val2, joiningSuffix, parsePosition) {
          joiningSuffix = joiningSuffix ? joiningSuffix : "";
          var info2 = {};
          if (!label && !CSL2.STATUTE_SUBDIV_STRINGS_REVERSE[variable]) {
            label = "var:" + variable;
          }
          if (label) {
            var m = label.match(/(\s*)([^\s]+)(\s*)/);
            if (realVariable === "page" && parsePosition === 0 && ["p.", "pp."].indexOf(m[2]) === -1) {
              info2.gotosleepability = true;
              info2.labelVisibility = true;
            } else {
              info2.labelVisibility = false;
            }
            info2.label = m[2];
            info2.origLabel = origLabel;
            info2.labelSuffix = m[3] ? m[3] : "";
            info2.plural = 0;
          }
          var m = val2.match(/^([0-9]*[a-zA-Z]+0*)?([0-9]+(?:[a-zA-Z]*|[-,a-zA-Z]+))$/);
          if (m) {
            info2.particle = m[1] ? m[1] : "";
            info2.value = m[2];
          } else {
            info2.particle = "";
            info2.value = val2;
          }
          info2.joiningSuffix = joiningSuffix.replace(/\s*-\s*/, "-");
          return info2;
        }
        function fixupSubsections(elems) {
          for (var i = elems.length - 2; i > -1; i -= 2) {
            if (elems[i] === "-" && elems[i - 1].match(/^(?:(?:[a-z]|[a-z][a-z]|[a-z][a-z][a-z]|[a-z][a-z][a-z][a-z])\.  *)*[0-9]+[,a-zA-Z]+$/) && elems[i + 1].match(/^[,a-zA-Z]+$/)) {
              elems[i - 1] = elems.slice(i - 1, i + 2).join("");
              elems = elems.slice(0, i).concat(elems.slice(i + 2));
            }
          }
          return elems;
        }
        function parseString(str, defaultLabel2) {
          defaultLabel2 = defaultLabel2 ? defaultLabel2 : "";
          str = normalizeFieldValue(str, defaultLabel2);
          var jmrex, jsrex, mystr;
          if ("page" === variable) {
            if (str.indexOf("\u2013") > -1) {
              str = str.replace(/\u2013/g, "-");
            }
          }
          if (str.indexOf("\\-") > -1) {
            jmrex = new RegExp(joinerMatchRex.source.replace("\\-", ""));
            jsrex = new RegExp(joinerSplitRex.source.replace("\\-", ""));
            var lst = str.split("\\-");
            for (var i = 0, ilen = lst.length; i < ilen; i++) {
              lst[i] = lst[i].replace(/\-/g, "\u2013");
            }
            mystr = lst.join("\\-");
            mystr = mystr.replace(/\\/g, "");
          } else {
            jmrex = joinerMatchRex;
            jsrex = joinerSplitRex;
            mystr = str;
          }
          var elems = [];
          var m = mystr.match(jmrex);
          if (m) {
            var lst = mystr.split(jsrex);
            for (var i = 0, ilen = m.length; i < ilen; i++) {
              if (m[i].match(andRex)) {
                if (lst[i].match(/[a-zA-Z]$/) && lst[i].match(/^[a-zA-Z]/)) {
                  m[i] = localeAmpersand;
                } else {
                  m[i] = " " + localeAmpersand + " ";
                }
              }
            }
            var recombine = false;
            for (var i in lst) {
              if (("" + lst[i]).replace(/^[a-z]\.\s+/, "").match(/[^\s0-9ivxlcmIVXLCM]/)) {
                break;
              }
            }
            if (recombine) {
              elems = [mystr];
            } else {
              for (var i = 0, ilen = lst.length - 1; i < ilen; i++) {
                elems.push(lst[i]);
                elems.push(m[i]);
              }
              elems.push(lst[lst.length - 1]);
              elems = fixupSubsections(elems);
            }
          } else {
            var elems = [mystr];
          }
          var values2 = [];
          var label = defaultLabel2;
          var origLabel = "";
          for (var i = 0, ilen = elems.length; i < ilen; i += 2) {
            var m = elems[i].match(/((?:^| )(?:[a-z]|[a-z][a-z]|[a-z][a-z][a-z]|[a-z][a-z][a-z][a-z]|subpara|subch|amend|bibliog|annot|illus|princ|intro|sched|subdiv|subsec)(?:\.| ) *)/g);
            if (m) {
              var lst = elems[i].split(/(?:(?:^| )(?:[a-z]|[a-z][a-z]|[a-z][a-z][a-z]|[a-z][a-z][a-z][a-z]|subpara|subch|amend|bibliog|annot|illus|princ|intro|sched|subdiv|subsec)(?:\.| ) *)/);
              for (var j = lst.length - 1; j > 0; j--) {
                if (lst[j - 1] && (!lst[j].match(/^[0-9]+([-;,:a-zA-Z]*)$/) || !lst[j - 1].match(/^[0-9]+([-;,:a-zA-Z]*)$/))) {
                  lst[j - 1] = lst[j - 1] + m[j - 1] + lst[j];
                  lst = lst.slice(0, j).concat(lst.slice(j + 1));
                  m = m.slice(0, j - 1).concat(m.slice(j));
                }
              }
              if (m.length > 0) {
                var slug = m[0].trim();
                var notAlabel = !CSL2.STATUTE_SUBDIV_STRINGS[slug] || "undefined" === typeof me.getTerm(CSL2.STATUTE_SUBDIV_STRINGS[slug]) || ["locator", "number", "locator-extra", "page"].indexOf(variable) === -1 && CSL2.STATUTE_SUBDIV_STRINGS[slug] !== variable;
                if (notAlabel) {
                  if (i === 0) {
                    m = m.slice(1);
                    lst[0] = lst[0] + " " + slug + " " + lst[1];
                    lst = lst.slice(0, 1).concat(lst.slice(2));
                  }
                } else {
                  origLabel = slug;
                }
              }
              for (var j = 0, jlen = lst.length; j < jlen; j++) {
                if (lst[j] || j === lst.length - 1) {
                  var filteredOrigLabel;
                  label = m[j - 1] ? m[j - 1] : label;
                  if (origLabel === label.trim()) {
                    filteredOrigLabel = "";
                  } else {
                    filteredOrigLabel = origLabel;
                  }
                  mystr = lst[j] ? lst[j].trim() : "";
                  if (j === lst.length - 1) {
                    values2.push(composeNumberInfo(filteredOrigLabel, label, mystr, elems[i + 1], i));
                  } else {
                    values2.push(composeNumberInfo(filteredOrigLabel, label, mystr, null, i));
                  }
                }
              }
            } else {
              var filteredOrigLabel;
              if (origLabel === label.trim()) {
                filteredOrigLabel = "";
              } else {
                filteredOrigLabel = origLabel;
              }
              values2.push(composeNumberInfo(filteredOrigLabel, label, elems[i], elems[i + 1]));
            }
          }
          return values2;
        }
        function setSpaces(values2) {
          for (var i = 0, ilen = values2.length - 1; i < ilen; i++) {
            if (!values2[i].joiningSuffix && values2[i + 1].label) {
              values2[i].joiningSuffix = " ";
            }
          }
        }
        function fixNumericAndCount(values2, i, currentLabelInfo) {
          var master = values2[currentLabelInfo.pos];
          var val2 = values2[i].value;
          var isEscapedHyphen = master.joiningSuffix === "\\-";
          if (val2.particle && val2.particle !== master.particle) {
            currentLabelInfo.collapsible = false;
          }
          var mVal = val2.match(/^[0-9]+([-,:a-zA-Z]*)$/);
          var mCurrentLabel = master.value.match(/^(?:[0-9]+|[ixv]+)([-,:a-zA-Z]*|\-[\-0-9]+)$/);
          if (!val2 || !mVal || !mCurrentLabel || isEscapedHyphen) {
            currentLabelInfo.collapsible = false;
            if (!val2 || !mCurrentLabel) {
              currentLabelInfo.numeric = false;
            }
            if (isEscapedHyphen) {
              currentLabelInfo.count--;
            }
          }
          if (mVal && mVal[1] || mCurrentLabel && mCurrentLabel[1]) {
            currentLabelInfo.collapsible = false;
          }
          if (void 0 === values2[i].collapsible) {
            for (var j = i, jlen = i + currentLabelInfo.count; j < jlen; j++) {
              if (isNaN(parseInt(values2[j].value)) && !values2[j].value.match(/^[ivxlcmIVXLCM]+$/)) {
                values2[j].collapsible = false;
              } else {
                values2[j].collapsible = true;
              }
            }
            currentLabelInfo.collapsible = values2[i].collapsible;
          }
          var isCollapsible = currentLabelInfo.collapsible;
          for (var j = currentLabelInfo.pos, jlen = currentLabelInfo.pos + currentLabelInfo.count; j < jlen; j++) {
            if (currentLabelInfo.count > 1 && isCollapsible) {
              values2[j].plural = 1;
            }
            values2[j].numeric = currentLabelInfo.numeric;
            values2[j].collapsible = currentLabelInfo.collapsible;
          }
        }
        function fixLabelVisibility(values2, groupStartPos, currentLabelInfo) {
          if (currentLabelInfo.label.slice(0, 4) !== "var:") {
            if (currentLabelInfo.pos === 0) {
              if (["locator", "number", "locator-extra", "page"].indexOf(variable) > -1) {
                if ("undefined" === typeof me.getTerm(CSL2.STATUTE_SUBDIV_STRINGS[currentLabelInfo.label])) {
                  values2[currentLabelInfo.pos].labelVisibility = true;
                }
              }
              if (["locator", "number", "locator-extra", "page"].indexOf(variable) === -1) {
                if (CSL2.STATUTE_SUBDIV_STRINGS[currentLabelInfo.label] !== variable) {
                  values2[0].labelVisibility = true;
                }
              }
            } else {
              values2[currentLabelInfo.pos].labelVisibility = true;
            }
          }
        }
        function setPluralsAndNumerics(values2) {
          if (values2.length === 0) {
            return;
          }
          var groupStartPos = 0;
          var groupCount = 1;
          for (var i = 1, ilen = values2.length; i < ilen; i++) {
            var lastVal = values2[i - 1];
            var thisVal = values2[i];
            if (lastVal.label === thisVal.label && lastVal.particle === lastVal.particle) {
              groupCount++;
            } else {
              var currentLabelInfo = JSON.parse(JSON.stringify(values2[groupStartPos]));
              currentLabelInfo.pos = groupStartPos;
              currentLabelInfo.count = groupCount;
              currentLabelInfo.numeric = true;
              fixNumericAndCount(values2, groupStartPos, currentLabelInfo);
              if (lastVal.label !== thisVal.label) {
                fixLabelVisibility(values2, groupStartPos, currentLabelInfo);
              }
              groupStartPos = i;
              groupCount = 1;
            }
          }
          var currentLabelInfo = JSON.parse(JSON.stringify(values2[groupStartPos]));
          currentLabelInfo.pos = groupStartPos;
          currentLabelInfo.count = groupCount;
          currentLabelInfo.numeric = true;
          fixNumericAndCount(values2, groupStartPos, currentLabelInfo);
          fixLabelVisibility(values2, groupStartPos, currentLabelInfo);
          if (values2.length && values2[0].numeric && variable.slice(0, 10) === "number-of-") {
            if (parseInt(ItemObject[realVariable], 10) > 1) {
              values2[0].plural = 1;
            }
          }
        }
        function stripHyphenBackslash(joiningSuffix) {
          return joiningSuffix.replace("\\-", "-");
        }
        function setStyling(values2) {
          var masterNode = CSL2.Util.cloneToken(node);
          var masterStyling = new CSL2.Token();
          if (!me.tmp.just_looking) {
            masterStyling.decorations = masterNode.decorations;
            masterNode.decorations = [];
            masterStyling.strings.prefix = masterNode.strings.prefix;
            masterNode.strings.prefix = "";
            masterStyling.strings.suffix = masterNode.strings.suffix;
            masterNode.strings.suffix = "";
          }
          var masterLabel = values2.length ? values2[0].label : null;
          if (values2.length) {
            for (var i = 0, ilen = values2.length; i < ilen; i++) {
              var val2 = values2[i];
              var newnode = CSL2.Util.cloneToken(masterNode);
              newnode.gender = node.gender;
              if (masterLabel === val2.label) {
                newnode.formatter = node.formatter;
              }
              if (val2.numeric) {
                newnode.successor_prefix = val2.successor_prefix;
              }
              newnode.strings.suffix = newnode.strings.suffix + stripHyphenBackslash(val2.joiningSuffix);
              val2.styling = newnode;
            }
            if (!me.tmp.just_looking) {
              if (values2[0].value.slice(0, 1) === '"' && values2[values2.length - 1].value.slice(-1) === '"') {
                values2[0].value = values2[0].value.slice(1);
                values2[values2.length - 1].value = values2[values2.length - 1].value.slice(0, -1);
                masterStyling.decorations.push(["@quotes", true]);
              }
            }
          }
          return masterStyling;
        }
        function checkTerm(variable2, val2) {
          var ret = true;
          if (["locator", "locator-extra", "page"].indexOf(variable2) > -1) {
            var label;
            if (val2.origLabel) {
              label = val2.origLabel;
            } else {
              label = val2.label;
            }
            ret = !!me.getTerm(CSL2.STATUTE_SUBDIV_STRINGS[label]);
          }
          return ret;
        }
        function checkPage(variable2, val2) {
          return "page" === variable2 || ["locator", "locator-extra"].indexOf(variable2) > -1 && (["p."].indexOf(val2.label) > -1 || ["p."].indexOf(val2.origLabel) > -1);
        }
        function fixupRangeDelimiter(variable2, val2, rangeDelimiter, isNumeric) {
          var isPage = checkPage(variable2, val2);
          var hasTerm = checkTerm(variable2, val2);
          if (hasTerm && rangeDelimiter === "-") {
            if (isNumeric) {
              if (isPage || ["locator", "locator-extra", "issue", "volume", "edition", "number"].indexOf(variable2) > -1) {
                rangeDelimiter = me.getTerm("page-range-delimiter");
                if (!rangeDelimiter) {
                  rangeDelimiter = "\u2013";
                }
              }
              if (variable2 === "collection-number") {
                rangeDelimiter = me.getTerm("year-range-delimiter");
                if (!rangeDelimiter) {
                  rangeDelimiter = "\u2013";
                }
              }
            }
          }
          return rangeDelimiter;
        }
        function manglePageNumbers(values2, i, currentInfo) {
          if (i < 1) {
            return;
          }
          if (currentInfo.count !== 2) {
            return;
          }
          if (values2[i - 1].particle !== values2[i].particle) {
            return;
          }
          if (values2[i - 1].joiningSuffix !== "-") {
            currentInfo.count = 1;
            return;
          }
          if (!me.opt["page-range-format"] && parseInt(values2[i - 1].value, 10) > parseInt(values2[i].value, 10)) {
            values2[i - 1].joiningSuffix = fixupRangeDelimiter(variable, values2[i], values2[i - 1].joiningSuffix, true);
            return;
          }
          var val2 = values2[i];
          var isPage = checkPage(variable, val2);
          var str;
          if (isPage && !isNaN(parseInt(values2[i - 1].value)) && !isNaN(parseInt(values2[i].value))) {
            str = values2[i - 1].particle + values2[i - 1].value + " - " + values2[i].particle + values2[i].value;
            str = me.fun.page_mangler(str);
          } else {
            if (("" + values2[i - 1].value).match(/^([0-9]+|[ivxlcmIVXLCM]+)$/) && ("" + values2[i].value).match(/^([0-9]+|[ivxlcmIVXLCM]+)$/)) {
              values2[i - 1].joiningSuffix = me.getTerm("page-range-delimiter");
            }
            str = values2[i - 1].value + stripHyphenBackslash(values2[i - 1].joiningSuffix) + values2[i].value;
          }
          var m = str.match(/^((?:[0-9]*[a-zA-Z]+0*))?([0-9]+[a-z]*)(\s*[^0-9]+\s*)([-,a-zA-Z]?0*)([0-9]+[a-z]*)$/);
          if (m) {
            var rangeDelimiter = m[3];
            rangeDelimiter = fixupRangeDelimiter(variable, val2, rangeDelimiter, values2[i].numeric);
            values2[i - 1].particle = m[1];
            values2[i - 1].value = m[2];
            values2[i - 1].joiningSuffix = rangeDelimiter;
            values2[i].particle = m[4];
            values2[i].value = m[5];
          }
          currentInfo.count = 0;
        }
        function fixRanges(values2) {
          if (!node) {
            return;
          }
          if (["page", "chapter-number", "collection-number", "edition", "issue", "number", "number-of-pages", "number-of-volumes", "volume", "locator", "locator-extra"].indexOf(variable) === -1) {
            return;
          }
          var currentInfo = {
            count: 0,
            label: null,
            lastHadRangeDelimiter: false
          };
          for (var i = 0, ilen = values2.length; i < ilen; i++) {
            var val2 = values2[i];
            if (!val2.collapsible) {
              currentInfo.count = 0;
              currentInfo.label = null;
              var isNumeric = val2.numeric;
              val2.joiningSuffix = fixupRangeDelimiter(variable, val2, val2.joiningSuffix, isNumeric);
            } else if (currentInfo.label === val2.label && val2.joiningSuffix === "-") {
              currentInfo.count = 1;
            } else if (currentInfo.label === val2.label && val2.joiningSuffix !== "-") {
              currentInfo.count++;
              if (currentInfo.count === 2) {
                manglePageNumbers(values2, i, currentInfo);
              }
            } else if (currentInfo.label !== val2.label) {
              currentInfo.label = val2.label;
              currentInfo.count = 1;
            } else {
              currentInfo.count = 1;
              currentInfo.label = val2.label;
            }
          }
          if (currentInfo.count === 2) {
            manglePageNumbers(values2, values2.length - 1, currentInfo);
          }
        }
        function setVariableParams(shadow_numbers, realVariable2, values2) {
          var obj2 = shadow_numbers[realVariable2];
          if (values2.length) {
            obj2.numeric = values2[0].numeric;
            obj2.collapsible = values2[0].collapsible;
            obj2.plural = values2[0].plural;
            obj2.label = CSL2.STATUTE_SUBDIV_STRINGS[values2[0].label];
            if (variable === "number" && obj2.label === "issue" && me.getTerm("number")) {
              obj2.label = "number";
            }
          }
        }
        if (node && this.tmp.shadow_numbers[realVariable] && this.tmp.shadow_numbers[realVariable].values.length) {
          var values = this.tmp.shadow_numbers[realVariable].values;
          fixRanges(values);
          this.tmp.shadow_numbers[realVariable].masterStyling = setStyling(values);
          return;
        }
        if (!this.tmp.shadow_numbers[realVariable]) {
          this.tmp.shadow_numbers[realVariable] = {
            values: []
          };
        }
        if (!ItemObject) {
          return;
        }
        var languageRole = CSL2.LangPrefsMap[variable];
        if (languageRole) {
          var localeType = this.opt["cite-lang-prefs"][languageRole][0];
          val = this.transform.getTextSubField(ItemObject, realVariable, "locale-" + localeType, true);
          val = val.name;
        } else {
          val = ItemObject[realVariable];
        }
        if (val && realVariable === "number" && ItemObject.type === "legal_case") {
          val = val.replace(/[\\]*-/g, "\\-");
        }
        if (val && this.sys.getAbbreviation) {
          if (this.sys.normalizeAbbrevsKey) {
            var normval = this.sys.normalizeAbbrevsKey(realVariable, val);
          } else {
            var normval = val;
          }
          var jurisdiction = this.transform.loadAbbreviation(ItemObject.jurisdiction, "number", normval, ItemObject.language);
          if (this.transform.abbrevs[jurisdiction].number) {
            if (this.transform.abbrevs[jurisdiction].number[normval]) {
              val = this.transform.abbrevs[jurisdiction].number[normval];
            } else {
              if ("undefined" !== typeof this.transform.abbrevs[jurisdiction].number[normval]) {
                delete this.transform.abbrevs[jurisdiction].number[normval];
              }
            }
          }
        }
        if ("undefined" !== typeof val && ("string" === typeof val || "number" === typeof val)) {
          if ("number" === typeof val) {
            val = "" + val;
          }
          var defaultLabel = CSL2.STATUTE_SUBDIV_STRINGS_REVERSE[variable];
          if (this.tmp.shadow_numbers[realVariable].values.length === 0) {
            var values = parseString(val, defaultLabel);
            setSpaces(values);
            setPluralsAndNumerics(values);
            for (var obj of values) {
              if (!obj.numeric) obj.plural = 0;
            }
            this.tmp.shadow_numbers[realVariable].values = values;
            if (node) {
              fixRanges(values);
              this.tmp.shadow_numbers[realVariable].masterStyling = setStyling(values);
            }
            setVariableParams(this.tmp.shadow_numbers, realVariable, values);
          }
          var info = this.tmp.shadow_numbers[realVariable];
          if (variable === "number") {
            if (info.values.length === 1 && info.values[0].value.indexOf("|") > -1) {
              info.values[0].value = info.values[0].value.replace(/\|/g, ", ");
              info.values[0].numeric = true;
              info.values[0].plural = 1;
              info.values[0].collapsible = false;
              info.numeric = true;
              info.plural = 1;
              info.collapsible = false;
            }
          }
          if (info.values.length === 1) {
            if (info.values[0].value.match(/^[0-9]+(?:\/[0-9]+)+$/)) {
              info.values[0].numeric = true;
              info.values[0].plural = 0;
              info.values[0].collapsible = false;
              info.numeric = true;
              info.plural = 0;
              info.collapsible = false;
            }
          }
          if (variable === "page") {
            if (info.values.length > 0) {
              if (info.values[0].gotosleepability) {
                info.labelForm = "short";
              }
            }
          }
        }
      };
      CSL2.Util.outputNumericField = function(state, varname, itemID) {
        state.output.openLevel(state.tmp.shadow_numbers[varname].masterStyling);
        var masterStyling = state.tmp.shadow_numbers[varname].masterStyling;
        var nums = state.tmp.shadow_numbers[varname].values;
        var masterLabel = nums.length ? nums[0].label : null;
        var labelForm = state.tmp.shadow_numbers[varname].labelForm;
        var tryStatic = state.tmp.group_context.tip.label_static;
        var embeddedLabelForm;
        if (labelForm) {
          embeddedLabelForm = labelForm;
        } else {
          embeddedLabelForm = "short";
        }
        var labelCapitalizeIfFirst = state.tmp.shadow_numbers[varname].labelCapitalizeIfFirst;
        var labelDecorations = state.tmp.shadow_numbers[varname].labelDecorations;
        var lastLabelName = null;
        for (var i = 0, ilen = nums.length; i < ilen; i++) {
          var num = nums[i];
          var label = "";
          var labelName;
          if (num.label) {
            if ("var:" === num.label.slice(0, 4)) {
              labelName = num.label.slice(4);
            } else {
              labelName = CSL2.STATUTE_SUBDIV_STRINGS[num.label];
            }
            if (labelName) {
              if (num.label === masterLabel) {
                if (tryStatic) {
                  label = state.getTerm(labelName, "static", num.plural);
                  if (label.indexOf("%s") === -1) {
                    label = "";
                  }
                }
                if (!label) {
                  label = state.getTerm(labelName, labelForm, num.plural);
                }
              } else {
                if (tryStatic) {
                  label = state.getTerm(labelName, "static", num.plural);
                  if (label.indexOf("%s") === -1) {
                    label = "";
                  }
                }
                if (!label) {
                  label = state.getTerm(labelName, embeddedLabelForm, num.plural);
                }
              }
              if (labelCapitalizeIfFirst) {
                label = CSL2.Output.Formatters["capitalize-first"](state, label);
              }
            }
          }
          var labelPlaceholderPos = -1;
          if (label) {
            labelPlaceholderPos = label.indexOf("%s");
          }
          var numStyling = CSL2.Util.cloneToken(num.styling);
          numStyling.formatter = num.styling.formatter;
          numStyling.type = num.styling.type;
          numStyling.num = num.styling.num;
          numStyling.gender = num.styling.gender;
          if (labelPlaceholderPos > 0 && labelPlaceholderPos < label.length - 2) {
            numStyling.strings.prefix += label.slice(0, labelPlaceholderPos);
            numStyling.strings.suffix = label.slice(labelPlaceholderPos + 2) + numStyling.strings.suffix;
          } else if (num.labelVisibility) {
            if (!label) {
              label = num.label;
              labelName = num.label;
            }
            if (labelPlaceholderPos > 0) {
              var prefixLabelStyling = new CSL2.Token();
              prefixLabelStyling.decorations = labelDecorations;
              state.output.append(label.slice(0, labelPlaceholderPos), prefixLabelStyling);
            } else if (labelPlaceholderPos === label.length - 2 || labelPlaceholderPos === -1) {
              state.output.append(label + num.labelSuffix, "empty");
            }
          }
          CSL2.UPDATE_GROUP_CONTEXT_CONDITION(state, masterStyling.strings.prefix, null, masterStyling, `${num.particle}${num.value}`);
          if (num.collapsible) {
            var blob;
            if (num.value.match(/^[1-9][0-9]*$/) && Number.isSafeInteger(parseInt(num.value, 10))) {
              blob = new CSL2.NumericBlob(state, num.particle, parseInt(num.value, 10), numStyling, itemID);
            } else {
              blob = new CSL2.NumericBlob(state, num.particle, num.value, numStyling, itemID);
            }
            if ("undefined" === typeof blob.gender) {
              blob.gender = state.locale[state.opt.lang]["noun-genders"][varname];
            }
            state.output.append(blob, "literal");
          } else {
            state.output.append(num.particle + num.value, numStyling);
          }
          if (labelPlaceholderPos === 0 && labelPlaceholderPos < label.length - 2) {
            if (lastLabelName === null) {
              lastLabelName = labelName;
            }
            if (labelName !== lastLabelName || i === nums.length - 1) {
              var suffixLabelStyling = new CSL2.Token();
              suffixLabelStyling.decorations = labelDecorations;
              state.output.append(label.slice(labelPlaceholderPos + 2), suffixLabelStyling);
            }
          }
          lastLabelName = labelName;
          state.tmp.term_predecessor = true;
        }
        state.output.closeLevel();
      };
      CSL2.Util.PageRangeMangler = {};
      CSL2.Util.PageRangeMangler.getFunction = function(state, rangeType) {
        var rangerex, pos, len, stringify, listify, expand, minimize, minimize_internal, chicago15, chicago16, lst, m, b, e, ret, begin, end, ret_func;
        var range_delimiter = state.getTerm(rangeType + "-range-delimiter");
        rangerex = /([0-9]*[a-zA-Z]+0*)?([0-9]+[a-z]*)\s*(?:\u2013|-)\s*([0-9]*[a-zA-Z]+0*)?([0-9]+[a-z]*)/;
        stringify = function(lst2) {
          len = lst2.length;
          for (pos = 1; pos < len; pos += 2) {
            if ("object" === typeof lst2[pos]) {
              lst2[pos] = lst2[pos].join("");
            }
          }
          var ret2 = lst2.join("");
          ret2 = ret2.replace(/([^\\])\-/g, "$1" + state.getTerm(rangeType + "-range-delimiter"));
          return ret2;
        };
        listify = function(str) {
          var m2, lst2, ret2;
          var hyphens = "\\s+\\-\\s+";
          var this_range_delimiter = range_delimiter === "-" ? "" : range_delimiter;
          var delimRex = new RegExp("([^\\\\])[-" + this_range_delimiter + "\\u2013]", "g");
          str = str.replace(delimRex, "$1 - ").replace(/\s+-\s+/g, " - ");
          var rexm = new RegExp("((?:[0-9]*[a-zA-Z]+0*)?[0-9]+[a-z]*" + hyphens + "(?:[0-9]*[a-zA-Z]+0*)?[0-9]+[a-z]*)", "g");
          var rexlst = new RegExp("(?:[0-9]*[a-zA-Z]+0*)?[0-9]+[a-z]*" + hyphens + "(?:[0-9]*[a-zA-Z]+0*)?[0-9]+[a-z]*");
          m2 = str.match(rexm);
          lst2 = str.split(rexlst);
          if (lst2.length === 0) {
            ret2 = m2;
          } else {
            ret2 = [lst2[0]];
            for (pos = 1, len = lst2.length; pos < len; pos += 1) {
              ret2.push(m2[pos - 1].replace(/\s*\-\s*/g, "-"));
              ret2.push(lst2[pos]);
            }
          }
          return ret2;
        };
        expand = function(str) {
          str = "" + str;
          lst = listify(str);
          len = lst.length;
          for (pos = 1; pos < len; pos += 2) {
            m = lst[pos].match(rangerex);
            if (m) {
              if (!m[3] || m[1] === m[3]) {
                if (m[4].length < m[2].length) {
                  m[4] = m[2].slice(0, m[2].length - m[4].length) + m[4];
                }
                if (parseInt(m[2], 10) < parseInt(m[4], 10)) {
                  m[3] = range_delimiter + (m[1] ? m[1] : "");
                  lst[pos] = m.slice(1);
                }
              }
            }
            if ("string" === typeof lst[pos]) {
              lst[pos] = lst[pos].replace(/\-/g, range_delimiter);
            }
          }
          return lst;
        };
        minimize = function(lst2, minchars, isyear) {
          len = lst2.length;
          for (var i = 1, ilen = lst2.length; i < ilen; i += 2) {
            if ("object" === typeof lst2[i]) {
              lst2[i][3] = minimize_internal(lst2[i][1], lst2[i][3], minchars, isyear);
              if (lst2[i][2].slice(1) === lst2[i][0]) {
                lst2[i][2] = range_delimiter;
              }
            }
          }
          return stringify(lst2);
        };
        minimize_internal = function(begin2, end2, minchars, isyear) {
          if (!minchars) {
            minchars = 0;
          }
          b = ("" + begin2).split("");
          e = ("" + end2).split("");
          ret = e.slice();
          ret.reverse();
          if (b.length === e.length) {
            for (var i = 0, ilen = b.length; i < ilen; i += 1) {
              if (b[i] === e[i] && ret.length > minchars) {
                ret.pop();
              } else {
                if (minchars && isyear && ret.length === 3) {
                  var front = b.slice(0, i);
                  front.reverse();
                  ret = ret.concat(front);
                }
                break;
              }
            }
          }
          ret.reverse();
          return ret.join("");
        };
        chicago15 = function(lst2) {
          len = lst2.length;
          for (pos = 1; pos < len; pos += 2) {
            if ("object" === typeof lst2[pos]) {
              m = lst2[pos];
              begin = parseInt(m[1], 10);
              end = parseInt(m[3], 10);
              if (begin > 100 && begin % 100 && parseInt(begin / 100, 10) === parseInt(end / 100, 10)) {
                m[3] = "" + end % 100;
              } else if (begin >= 1e4) {
                m[3] = "" + end % 1e3;
              }
            }
            if (m[2].slice(1) === m[0]) {
              m[2] = range_delimiter;
            }
          }
          return stringify(lst2);
        };
        chicago16 = function(lst2) {
          len = lst2.length;
          for (pos = 1; pos < len; pos += 2) {
            if ("object" === typeof lst2[pos]) {
              m = lst2[pos];
              begin = parseInt(m[1], 10);
              end = parseInt(m[3], 10);
              e = "" + end;
              if (begin > 100 && begin % 100) {
                for (var i = 2; i < e.length; i++) {
                  var divisor = Math.pow(10, i);
                  if (Math.floor(begin / divisor) === Math.floor(end / divisor)) {
                    m[3] = "" + end % divisor;
                    break;
                  }
                }
              }
            }
            if (m[2].slice(1) === m[0]) {
              m[2] = range_delimiter;
            }
          }
          return stringify(lst2);
        };
        var sniff = function(str, func, minchars, isyear) {
          var ret2;
          str = "" + str;
          var lst2 = expand(str);
          var ret2 = func(lst2, minchars, isyear);
          return ret2;
        };
        if (!state.opt[rangeType + "-range-format"]) {
          ret_func = function(str) {
            return sniff(str, stringify);
          };
        } else if (state.opt[rangeType + "-range-format"] === "expanded") {
          ret_func = function(str) {
            return sniff(str, stringify);
          };
        } else if (state.opt[rangeType + "-range-format"] === "minimal") {
          ret_func = function(str) {
            return sniff(str, minimize);
          };
        } else if (state.opt[rangeType + "-range-format"] === "minimal-two") {
          ret_func = function(str, isyear) {
            return sniff(str, minimize, 2, isyear);
          };
        } else if (state.opt[rangeType + "-range-format"] === "chicago") {
          ret_func = function(str) {
            return sniff(str, chicago15);
          };
        } else if (state.opt[rangeType + "-range-format"] === "chicago-15") {
          ret_func = function(str) {
            return sniff(str, chicago15);
          };
        } else if (state.opt[rangeType + "-range-format"] === "chicago-16") {
          ret_func = function(str) {
            return sniff(str, chicago16);
          };
        }
        return ret_func;
      };
      CSL2.Util.FlipFlopper = function(state) {
        var _nestingState = [];
        var _nestingData = {
          '<span class="nocase">': {
            type: "nocase",
            opener: '<span class="nocase">',
            closer: "</span>",
            attr: null,
            outer: null,
            flipflop: null
          },
          '<span class="nodecor">': {
            type: "nodecor",
            opener: '<span class="nodecor">',
            closer: "</span>",
            attr: "@class",
            outer: "nodecor",
            flipflop: {
              "nodecor": "nodecor"
            }
          },
          '<span style="font-variant:small-caps;">': {
            type: "tag",
            opener: '<span style="font-variant:small-caps;">',
            closer: "</span>",
            attr: "@font-variant",
            outer: "small-caps",
            flipflop: {
              "small-caps": "normal",
              "normal": "small-caps"
            }
          },
          "<sc>": {
            type: "tag",
            opener: "<sc>",
            closer: "</sc>",
            attr: "@font-variant",
            outer: "small-caps",
            flipflop: {
              "small-caps": "normal",
              "normal": "small-caps"
            }
          },
          "<i>": {
            type: "tag",
            opener: "<i>",
            closer: "</i>",
            attr: "@font-style",
            outer: "italic",
            flipflop: {
              "italic": "normal",
              "normal": "italic"
            }
          },
          "<b>": {
            type: "tag",
            opener: "<b>",
            closer: "</b>",
            attr: "@font-weight",
            outer: "bold",
            flipflop: {
              "bold": "normal",
              "normal": "bold"
            }
          },
          "<sup>": {
            type: "tag",
            opener: "<sup>",
            closer: "</sup>",
            attr: "@vertical-align",
            outer: "sup",
            flipflop: {
              "sub": "sup",
              "sup": "sup"
            }
          },
          "<sub>": {
            type: "tag",
            opener: "<sub>",
            closer: "</sub>",
            attr: "@vertical-align",
            outer: "sub",
            flipflop: {
              "sup": "sub",
              "sub": "sub"
            }
          },
          ' "': {
            type: "quote",
            opener: ' "',
            closer: '"',
            attr: "@quotes",
            outer: "true",
            flipflop: {
              "true": "inner",
              "inner": "true",
              "false": "true"
            }
          },
          " '": {
            type: "quote",
            opener: " '",
            closer: "'",
            attr: "@quotes",
            outer: "inner",
            flipflop: {
              "true": "inner",
              "inner": "true",
              "false": "true"
            }
          }
        };
        _nestingData['("'] = _nestingData[' "'];
        _nestingData["('"] = _nestingData[" '"];
        var localeOpenQuote = state.getTerm("open-quote");
        var localeCloseQuote = state.getTerm("close-quote");
        var localeOpenInnerQuote = state.getTerm("open-inner-quote");
        var localeCloseInnerQuote = state.getTerm("close-inner-quote");
        if (localeOpenQuote && localeCloseQuote && [' "', " '", '"', "'"].indexOf(localeOpenQuote) === -1) {
          _nestingData[localeOpenQuote] = JSON.parse(JSON.stringify(_nestingData[' "']));
          _nestingData[localeOpenQuote].opener = localeOpenQuote;
          _nestingData[localeOpenQuote].closer = localeCloseQuote;
        }
        if (localeOpenInnerQuote && localeCloseInnerQuote && [' "', " '", '"', "'"].indexOf(localeOpenInnerQuote) === -1) {
          _nestingData[localeOpenInnerQuote] = JSON.parse(JSON.stringify(_nestingData[" '"]));
          _nestingData[localeOpenInnerQuote].opener = localeOpenInnerQuote;
          _nestingData[localeOpenInnerQuote].closer = localeCloseInnerQuote;
        }
        function _setOuterQuoteForm(quot) {
          var flip = {
            " '": ' "',
            ' "': " '",
            '("': "('",
            "('": '("'
          };
          _nestingData[quot].outer = "true";
          _nestingData[flip[quot]].outer = "inner";
        }
        function _getNestingOpenerParams(opener) {
          var openers = [];
          var keys = Object.keys(_nestingData);
          for (var i = 0, l = keys.length; i < l; i++) {
            var key = keys[i];
            if (_nestingData[opener].type !== "quote" || !_nestingData[opener]) {
              openers.push(key);
            }
          }
          var ret = _nestingData[opener];
          ret.opener = new RegExp("^(?:" + openers.map(function(str) {
            return str.replace("(", "\\(");
          }).join("|") + ")");
          return ret;
        }
        var _nestingParams = (function() {
          var ret = {};
          var keys = Object.keys(_nestingData);
          for (var i = 0, l = keys.length; i < l; i++) {
            var key = keys[i];
            ret[key] = _getNestingOpenerParams(key);
          }
          return ret;
        })();
        var _tagRex = (function() {
          var openers = [];
          var closers = [];
          var vals = {};
          for (var opener in _nestingParams) {
            openers.push(opener);
            vals[_nestingParams[opener].closer] = true;
          }
          var keys = Object.keys(vals);
          for (var i = 0, l = keys.length; i < l; i++) {
            var closer = keys[i];
            closers.push(closer);
          }
          var all = openers.concat(closers).map(function(str) {
            return str.replace("(", "\\(");
          }).join("|");
          return {
            matchAll: new RegExp("((?:" + all + "))", "g"),
            splitAll: new RegExp("(?:" + all + ")", "g"),
            open: new RegExp("(^(?:" + openers.map(function(str) {
              return str.replace("(", "\\(");
            }).join("|") + ")$)"),
            close: new RegExp("(^(?:" + closers.join("|") + ")$)")
          };
        })();
        function _tryOpen(tag, pos) {
          var params = _nestingState[_nestingState.length - 1];
          if (!params || tag.match(params.opener)) {
            _nestingState.push({
              type: _nestingParams[tag].type,
              opener: _nestingParams[tag].opener,
              closer: _nestingParams[tag].closer,
              pos
            });
            return false;
          } else {
            _nestingState.pop();
            _nestingState.push({
              type: _nestingParams[tag].type,
              opener: _nestingParams[tag].opener,
              closer: _nestingParams[tag].closer,
              pos
            });
            return {
              fixtag: params.pos
            };
          }
        }
        function _tryClose(tag, pos) {
          var params = _nestingState[_nestingState.length - 1];
          if (params && tag === params.closer) {
            _nestingState.pop();
            if (params.type === "nocase") {
              return {
                nocase: {
                  open: params.pos,
                  close: pos
                }
              };
            } else {
              return false;
            }
          } else {
            if (params) {
              return {
                fixtag: params.pos
              };
            } else {
              return {
                fixtag: pos
              };
            }
          }
        }
        function _pushNestingState(tag, pos) {
          if (tag.match(_tagRex.open)) {
            return _tryOpen(tag, pos);
          } else {
            return _tryClose(tag, pos);
          }
        }
        function _doppelString(str) {
          var forcedSpaces = [];
          str = str.replace(/(<span)\s+(style=\"font-variant:)\s*(small-caps);?\"[^>]*(>)/g, '$1 $2$3;"$4');
          str = str.replace(/(<span)\s+(class=\"no(?:case|decor)\")[^>]*(>)/g, "$1 $2$3");
          var match = str.match(_tagRex.matchAll);
          if (!match) {
            return {
              tags: [],
              strings: [str],
              forcedSpaces: []
            };
          }
          var split = str.split(_tagRex.splitAll);
          for (var i = 0, ilen = match.length - 1; i < ilen; i++) {
            if (_nestingData[match[i]]) {
              if (split[i + 1] === "" && ['"', "'"].indexOf(match[i + 1]) > -1) {
                match[i + 1] = " " + match[i + 1];
                forcedSpaces.push(true);
              } else {
                forcedSpaces.push(false);
              }
            }
          }
          return {
            tags: match,
            strings: split,
            forcedSpaces
          };
        }
        var TagReg = function(blob) {
          var _stack = [];
          this.set = function(tag) {
            var attr = _nestingData[tag].attr;
            var decor = null;
            for (var i = _stack.length - 1; i > -1; i--) {
              var _decor = _stack[i];
              if (_decor[0] === attr) {
                decor = _decor;
                break;
              }
            }
            if (!decor) {
              var allTheDecor = [state[state.tmp.area].opt.layout_decorations].concat(blob.alldecor);
              outer:
                for (var i = allTheDecor.length - 1; i > -1; i--) {
                  var decorset = allTheDecor[i];
                  if (!decorset) {
                    continue;
                  }
                  for (var j = decorset.length - 1; j > -1; j--) {
                    var _decor = decorset[j];
                    if (_decor[0] === attr) {
                      decor = _decor;
                      break outer;
                    }
                  }
                }
            }
            if (!decor) {
              decor = [attr, _nestingData[tag].outer];
            } else {
              decor = [attr, _nestingData[tag].flipflop[decor[1]]];
            }
            _stack.push(decor);
          };
          this.pair = function() {
            return _stack[_stack.length - 1];
          };
          this.pop = function() {
            _stack.pop();
          };
        };
        function _apostropheForce(tag, str) {
          if (tag === "'") {
            if (str && str.match(/^[^\,\.\?\:\;\ ]/)) {
              return "\u2019";
            }
          } else if (tag === " '" && str && str.match(/^[\ ]/)) {
            return " \u2019";
          }
          return false;
        }
        function _undoppelToQueue(blob, doppel, leadingSpace) {
          var firstString = true;
          var tagReg = new TagReg(blob);
          blob.blobs = [];
          function Stack(blob2) {
            this.stack = [blob2];
            this.latest = blob2;
            this.addStyling = function(str2, decor) {
              if (firstString) {
                if (str2.slice(0, 1) === " ") {
                  str2 = str2.slice(1);
                }
                if (str2.slice(0, 1) === " ") {
                  str2 = str2.slice(1);
                }
                firstString = false;
              }
              this.latest = this.stack[this.stack.length - 1];
              if (decor) {
                if ("string" === typeof this.latest.blobs) {
                  var child = new CSL2.Blob();
                  child.blobs = this.latest.blobs;
                  child.alldecor = this.latest.alldecor.slice();
                  this.latest.blobs = [child];
                }
                var tok = new CSL2.Token();
                var newblob = new CSL2.Blob(null, tok);
                newblob.alldecor = this.latest.alldecor.slice();
                if (decor[0] === "@class" && decor[1] === "nodecor") {
                  var newdecorset = [];
                  var seen = {};
                  var allTheDecor = [state[state.tmp.area].opt.layout_decorations].concat(newblob.alldecor);
                  for (var i2 = allTheDecor.length - 1; i2 > -1; i2--) {
                    var _decorset = allTheDecor[i2];
                    if (!_decorset) {
                      continue;
                    }
                    for (var j = _decorset.length - 1; j > -1; j--) {
                      var _olddecor = _decorset[j];
                      if (["@font-weight", "@font-style", "@font-variant"].indexOf(_olddecor[0]) > -1 && !seen[_olddecor[0]]) {
                        if (decor[1] !== "normal") {
                          newblob.decorations.push([_olddecor[0], "normal"]);
                          newdecorset.push([_olddecor[0], "normal"]);
                        }
                        seen[_olddecor[0]] = true;
                      }
                    }
                  }
                  newblob.alldecor.push(newdecorset);
                } else {
                  newblob.decorations.push(decor);
                  newblob.alldecor.push([decor]);
                }
                this.latest.blobs.push(newblob);
                this.stack.push(newblob);
                this.latest = newblob;
                if (str2) {
                  var tok = new CSL2.Token();
                  var newblob = new CSL2.Blob(null, tok);
                  newblob.blobs = str2;
                  newblob.alldecor = this.latest.alldecor.slice();
                  this.latest.blobs.push(newblob);
                }
              } else {
                if (str2) {
                  var child = new CSL2.Blob();
                  child.blobs = str2;
                  child.alldecor = this.latest.alldecor.slice();
                  this.latest.blobs.push(child);
                }
              }
            };
            this.popStyling = function() {
              this.stack.pop();
            };
          }
          var stack = new Stack(blob);
          if (doppel.strings.length) {
            var str = doppel.strings[0];
            if (leadingSpace) {
              str = " " + str;
            }
            stack.addStyling(str);
          }
          for (var i = 0, ilen = doppel.tags.length; i < ilen; i++) {
            var tag = doppel.tags[i];
            var str = doppel.strings[i + 1];
            if (tag.match(_tagRex.open)) {
              tagReg.set(tag);
              stack.addStyling(str, tagReg.pair());
            } else {
              tagReg.pop();
              stack.popStyling();
              stack.addStyling(str);
            }
          }
        }
        this.processTags = function(blob) {
          var str = blob.blobs;
          var leadingSpace = false;
          if (str.slice(0, 1) === " " && !str.match(/^\s+[\'\"]/)) {
            leadingSpace = true;
          }
          var rex = new RegExp("(" + CSL2.ROMANESQUE_REGEXP.source + ")\u2019(" + CSL2.ROMANESQUE_REGEXP.source + ")", "g");
          var str = " " + str.replace(rex, "$1'$2");
          var doppel = _doppelString(str);
          if (doppel.tags.length === 0) {
            return;
          }
          var quoteFormSeen = false;
          for (var i = 0, ilen = doppel.tags.length; i < ilen; i++) {
            var tag = doppel.tags[i];
            var str = doppel.strings[i + 1];
            var apostrophe = _apostropheForce(tag, str);
            if (apostrophe) {
              doppel.strings[i + 1] = apostrophe + doppel.strings[i + 1];
              doppel.tags[i] = "";
            } else {
              var tagInfo;
              while (true) {
                tagInfo = _pushNestingState(tag, i);
                if (tagInfo) {
                  if (Object.keys(tagInfo).indexOf("fixtag") > -1) {
                    if (tag.match(_tagRex.close) && tag === "'") {
                      doppel.strings[i + 1] = "\u2019" + doppel.strings[i + 1];
                      doppel.tags[i] = "";
                    } else {
                      var failedTag = doppel.tags[tagInfo.fixtag];
                      if (doppel.forcedSpaces[tagInfo.fixtag - 1]) {
                        failedTag = failedTag.slice(1);
                      }
                      doppel.strings[tagInfo.fixtag + 1] = failedTag + doppel.strings[tagInfo.fixtag + 1];
                      doppel.tags[tagInfo.fixtag] = "";
                    }
                    if (_nestingState.length > 0) {
                      if (tag !== "'") {
                        _nestingState.pop();
                      } else {
                        break;
                      }
                    } else {
                      break;
                    }
                  } else if (tagInfo.nocase) {
                    doppel.tags[tagInfo.nocase.open] = "";
                    doppel.tags[tagInfo.nocase.close] = "";
                    break;
                  } else {
                    break;
                  }
                } else {
                  break;
                }
              }
              if (tagInfo && (tagInfo.fixtag || tagInfo.fixtag === 0)) {
                doppel.strings[i + 1] = doppel.tags[i] + doppel.strings[i + 1];
                doppel.tags[i] = "";
              }
            }
          }
          for (var i = _nestingState.length - 1; i > -1; i--) {
            var tagPos = _nestingState[i].pos;
            var tag = doppel.tags[tagPos];
            if (tag === " '" || tag === "'") {
              doppel.strings[tagPos + 1] = " \u2019" + doppel.strings[tagPos + 1];
            } else {
              doppel.strings[tagPos + 1] = doppel.tags[tagPos] + doppel.strings[tagPos + 1];
            }
            doppel.tags[tagPos] = "";
            _nestingState.pop();
          }
          for (var i = doppel.tags.length - 1; i > -1; i--) {
            if (!doppel.tags[i]) {
              doppel.tags = doppel.tags.slice(0, i).concat(doppel.tags.slice(i + 1));
              doppel.strings[i] = doppel.strings[i] + doppel.strings[i + 1];
              doppel.strings = doppel.strings.slice(0, i + 1).concat(doppel.strings.slice(i + 2));
            }
          }
          for (var i = 0, ilen = doppel.tags.length; i < ilen; i++) {
            var tag = doppel.tags[i];
            var forcedSpace = doppel.forcedSpaces[i - 1];
            if ([' "', " '", '("', "('"].indexOf(tag) > -1) {
              if (!quoteFormSeen) {
                _setOuterQuoteForm(tag);
                quoteFormSeen = true;
              }
              if (!forcedSpace) {
                doppel.strings[i] += tag.slice(0, 1);
              }
            }
          }
          _undoppelToQueue(blob, doppel, leadingSpace);
        };
      };
      CSL2.Output.Formatters = (function() {
        var rexStr = `(?:\u2018|\u2019|\u201C|\u201D| "| '|"|'|[-\u2013\u2014/.,;?!:]|\\[|\\]|\\(|\\)|<span style="font-variant: small-caps;">|<span class="no(?:case|decor)">|</span>|</?(?:i|sc|b|sub|sup)>)`;
        var tagDoppel = new CSL2.Doppeler(rexStr, function(str) {
          return str.replace(/(<span)\s+(class=\"no(?:case|decor)\")[^>]*(>)/g, "$1 $2$3").replace(/(<span)\s+(style=\"font-variant:)\s*(small-caps);?(\")[^>]*(>)/g, "$1 $2 $3;$4$5");
        });
        var rexNameStr = '(?:[-\\s]*<\\/*(?:spans+class="no(?:case|decor)"|i|sc|b|sub|sup)>[-\\s]*|[-\\s]+)';
        var nameDoppel = new CSL2.Doppeler(rexNameStr);
        var wordDoppel = new CSL2.Doppeler("(?:[\xA0 \xA0\u2000-\u200B\u205F\u3000]+)");
        var _tagParams = {
          '<span style="font-variant: small-caps;">': "</span>",
          '<span class="nocase">': "</span>",
          '<span class="nodecor">': "</span>",
          "<sc>": "</sc>",
          "<sub>": "</sub>",
          "<sup>": "</sup>"
        };
        function _capitalise(word) {
          var m = word.match(/(^\s*)((?:[\0-\t\x0B\f\x0E-\u2027\u202A-\uD7FF\uE000-\uFFFF]|[\uD800-\uDBFF][\uDC00-\uDFFF]|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?:[^\uD800-\uDBFF]|^)[\uDC00-\uDFFF]))(.*)/);
          if (m && !(m[2].match(/^[\u0370-\u03FF]$/) && !m[3])) {
            return m[1] + CSL2.toLocaleUpperCase.call(this, m[2]) + m[3];
          }
          return word;
        }
        function _textcaseEngine(config, string) {
          if (!string) {
            return "";
          }
          config.doppel = tagDoppel.split(string);
          var quoteParams = {
            ' "': {
              opener: " '",
              closer: '"'
            },
            " '": {
              opener: ' "',
              closer: "'"
            },
            "\u2018": {
              opener: "\u2018",
              closer: "\u2019"
            },
            "\u201C": {
              opener: "\u201C",
              closer: "\u201D"
            }
          };
          function tryOpen(tag2, pos) {
            if (config.quoteState.length === 0 || tag2 === config.quoteState[config.quoteState.length - 1].opener) {
              config.quoteState.push({
                opener: quoteParams[tag2].opener,
                closer: quoteParams[tag2].closer,
                pos
              });
              return false;
            } else {
              var prevPos = config.quoteState[config.quoteState.length - 1].pos;
              config.quoteState.pop();
              config.quoteState.push({
                opener: quoteParams[tag2].opener,
                closer: quoteParams[tag2].closer,
                positions: pos
              });
              return prevPos;
            }
          }
          function tryClose(tag2, pos) {
            if (config.quoteState.length > 0 && tag2 === config.quoteState[config.quoteState.length - 1].closer) {
              config.quoteState.pop();
            } else {
              return pos;
            }
          }
          function pushQuoteState(tag2, pos) {
            var isOpener = ["\u201C", "\u2018", ' "', " '"].indexOf(tag2) > -1 ? true : false;
            if (isOpener) {
              return tryOpen(tag2, pos);
            } else {
              return tryClose(tag2, pos);
            }
          }
          function quoteFix(tag2, positions) {
            var m = tag2.match(/(^(?:\u2018|\u2019|\u201C|\u201D|\"|\')|(?: \"| \')$)/);
            if (m) {
              return pushQuoteState(m[1], positions);
            }
          }
          if (config.doppel.strings.length && config.doppel.strings[0].trim()) {
            config.doppel.strings[0] = config.capitaliseWords(config.doppel.strings[0], 0, config.doppel.tags[0]);
          }
          for (var i = 0, ilen = config.doppel.tags.length; i < ilen; i++) {
            var tag = config.doppel.tags[i];
            var str = config.doppel.strings[i + 1];
            if (config.tagState !== null) {
              if (_tagParams[tag]) {
                config.tagState.push(_tagParams[tag]);
              } else if (config.tagState.length && tag === config.tagState[config.tagState.length - 1]) {
                config.tagState.pop();
              }
            }
            if (config.afterPunct !== null) {
              if (tag.match(/[\!\?\:]$/)) {
                config.afterPunct = true;
              }
            }
            if (config.tagState.length === 0) {
              config.doppel.strings[i + 1] = config.capitaliseWords(str, i + 1, config.doppel, config.doppel.tags[i + 1]);
            } else if (config.doppel.strings[i + 1].trim()) {
              config.lastWordPos = null;
            }
            if (config.quoteState !== null) {
              var quotePos = quoteFix(tag, i);
              if (quotePos || quotePos === 0) {
                var origChar = config.doppel.origStrings[quotePos + 1].slice(0, 1);
                config.doppel.strings[quotePos + 1] = origChar + config.doppel.strings[quotePos + 1].slice(1);
                config.lastWordPos = null;
              }
            }
            if (config.isFirst) {
              if (str.trim()) {
                config.isFirst = false;
              }
            }
            if (config.afterPunct) {
              if (str.trim()) {
                config.afterPunct = false;
              }
            }
          }
          if (config.quoteState) {
            for (var i = 0, ilen = config.quoteState.length; i < ilen; i++) {
              var quotePos = config.quoteState[i].pos;
              if (typeof quotePos !== "undefined") {
                var origChar = config.doppel.origStrings[quotePos + 1].slice(0, 1);
                config.doppel.strings[quotePos + 1] = origChar + config.doppel.strings[quotePos + 1].slice(1);
              }
            }
          }
          if (config.lastWordPos) {
            var lastWords = wordDoppel.split(config.doppel.strings[config.lastWordPos.strings]);
            var lastWord = lastWords.strings[config.lastWordPos.words];
            if (lastWord.length > 1 && CSL2.toLocaleLowerCase.call(this, lastWord).match(config.skipWordsRex)) {
              lastWord = _capitalise.call(this, lastWord);
              lastWords.strings[config.lastWordPos.words] = lastWord;
            }
            config.doppel.strings[config.lastWordPos.strings] = wordDoppel.join(lastWords);
          }
          return tagDoppel.join(config.doppel);
        }
        function passthrough(state, str) {
          return str;
        }
        function lowercase(state, string) {
          var config = {
            quoteState: null,
            capitaliseWords: function(str) {
              var words = str.split(" ");
              for (var i = 0, ilen = words.length; i < ilen; i++) {
                var word = words[i];
                if (word) {
                  words[i] = CSL2.toLocaleLowerCase.call(state, word);
                }
              }
              return words.join(" ");
            },
            skipWordsRex: null,
            tagState: [],
            afterPunct: null,
            isFirst: null
          };
          return _textcaseEngine.call(state, config, string);
        }
        function uppercase(state, string) {
          var config = {
            quoteState: null,
            capitaliseWords: function(str) {
              var words = str.split(" ");
              for (var i = 0, ilen = words.length; i < ilen; i++) {
                var word = words[i];
                if (word) {
                  words[i] = CSL2.toLocaleUpperCase.call(state, word);
                }
              }
              return words.join(" ");
            },
            skipWordsRex: null,
            tagState: [],
            afterPunct: null,
            isFirst: null
          };
          return _textcaseEngine.call(state, config, string);
        }
        function sentence(state, string) {
          var config = {
            quoteState: [],
            capitaliseWords: function(str) {
              var words = str.split(" ");
              for (var i = 0, ilen = words.length; i < ilen; i++) {
                var word = words[i];
                if (word) {
                  if (config.isFirst) {
                    words[i] = _capitalise.call(state, word);
                    config.isFirst = false;
                  } else {
                    words[i] = CSL2.toLocaleLowerCase.call(state, word);
                  }
                }
              }
              return words.join(" ");
            },
            skipWordsRex: null,
            tagState: [],
            afterPunct: null,
            isFirst: true
          };
          return _textcaseEngine.call(state, config, string);
        }
        function title(state, string) {
          var config = {
            quoteState: [],
            capitaliseWords: function(str, i, followingTag) {
              if (str.trim()) {
                var wordle = wordDoppel.split(str);
                var words = wordle.strings;
                for (var j = 0, jlen = words.length; j < jlen; j++) {
                  var word = words[j];
                  if (!word) {
                    continue;
                  }
                  let lcase = CSL2.toLocaleLowerCase.call(state, word);
                  let capitalize = false;
                  if (word.length > 1 && !lcase.match(config.skipWordsRex)) {
                    capitalize = true;
                  } else if (j === words.length - 1 && followingTag === "-") {
                    capitalize = true;
                  } else if (config.isFirst) {
                    capitalize = true;
                  } else if (config.afterPunct) {
                    capitalize = true;
                  }
                  if (capitalize && word === lcase) {
                    words[j] = _capitalise.call(state, word);
                  }
                  config.afterPunct = false;
                  config.isFirst = false;
                  config.lastWordPos = {
                    strings: i,
                    words: j
                  };
                }
                str = wordDoppel.join(wordle);
              }
              return str;
            },
            skipWordsRex: state.locale[state.opt.lang].opts["skip-words-regexp"],
            tagState: [],
            afterPunct: false,
            isFirst: true
          };
          return _textcaseEngine.call(state, config, string);
        }
        function capitalizeFirst(state, string) {
          var config = {
            quoteState: [],
            capitaliseWords: function(str) {
              var wordle = wordDoppel.split(str);
              var words = wordle.strings;
              for (var i = 0, ilen = words.length; i < ilen; i++) {
                var word = words[i];
                if (word) {
                  if (config.isFirst) {
                    if (word === CSL2.toLocaleLowerCase.call(state, word)) {
                      words[i] = _capitalise.call(state, word);
                    }
                    config.isFirst = false;
                    break;
                  }
                }
              }
              return wordDoppel.join(wordle);
            },
            skipWordsRex: null,
            tagState: [],
            afterPunct: null,
            isFirst: true
          };
          return _textcaseEngine.call(state, config, string);
        }
        function capitalizeAll(state, string) {
          var config = {
            quoteState: [],
            capitaliseWords: function(str) {
              var wordle = wordDoppel.split(str);
              var words = wordle.strings;
              for (var i = 0, ilen = words.length; i < ilen; i++) {
                var word = words[i];
                if (word) {
                  if (word === CSL2.toLocaleLowerCase.call(state, word)) {
                    words[i] = _capitalise.call(state, word);
                  }
                }
              }
              return wordDoppel.join(wordle);
            },
            skipWordsRex: null,
            tagState: [],
            afterPunct: null,
            isFirst: null
          };
          return _textcaseEngine.call(state, config, string);
        }
        return {
          nameDoppel,
          passthrough,
          lowercase,
          uppercase,
          sentence,
          title,
          "capitalize-first": capitalizeFirst,
          "capitalize-all": capitalizeAll
        };
      })();
      CSL2.Output.Formats = function() {
      };
      CSL2.Output.Formats.prototype.html = {
        //
        // text_escape: Format-specific function for escaping text destined
        // for output.  Takes the text to be escaped as sole argument.  Function
        // will be run only once across each portion of text to be escaped, it
        // need not be idempotent.
        //
        "text_escape": function(text) {
          if (!text) {
            text = "";
          }
          return text.replace(/&/g, "&#38;").replace(/</g, "&#60;").replace(/>/g, "&#62;").replace(/\s\s/g, "\xA0 ").replace(
            CSL2.SUPERSCRIPTS_REGEXP,
            function(aChar) {
              return "<sup>" + CSL2.SUPERSCRIPTS[aChar] + "</sup>";
            }
          );
        },
        "bibstart": '<div class="csl-bib-body">\n',
        "bibend": "</div>",
        "@font-style/italic": "<i>%%STRING%%</i>",
        "@font-style/oblique": "<em>%%STRING%%</em>",
        "@font-style/normal": '<span style="font-style:normal;">%%STRING%%</span>',
        "@font-variant/small-caps": '<span style="font-variant:small-caps;">%%STRING%%</span>',
        "@passthrough/true": CSL2.Output.Formatters.passthrough,
        "@font-variant/normal": '<span style="font-variant:normal;">%%STRING%%</span>',
        "@font-weight/bold": "<b>%%STRING%%</b>",
        "@font-weight/normal": '<span style="font-weight:normal;">%%STRING%%</span>',
        "@font-weight/light": false,
        "@text-decoration/none": '<span style="text-decoration:none;">%%STRING%%</span>',
        "@text-decoration/underline": '<span style="text-decoration:underline;">%%STRING%%</span>',
        "@vertical-align/sup": "<sup>%%STRING%%</sup>",
        "@vertical-align/sub": "<sub>%%STRING%%</sub>",
        "@vertical-align/baseline": '<span style="baseline">%%STRING%%</span>',
        "@strip-periods/true": CSL2.Output.Formatters.passthrough,
        "@strip-periods/false": CSL2.Output.Formatters.passthrough,
        "@quotes/true": function(state, str) {
          if ("undefined" === typeof str) {
            return state.getTerm("open-quote");
          }
          return state.getTerm("open-quote") + str + state.getTerm("close-quote");
        },
        "@quotes/inner": function(state, str) {
          if ("undefined" === typeof str) {
            return "\u2019";
          }
          return state.getTerm("open-inner-quote") + str + state.getTerm("close-inner-quote");
        },
        "@quotes/false": false,
        //"@bibliography/body": function (state,str){
        //    return "<div class=\"csl-bib-body\">\n"+str+"</div>";
        //},
        "@cite/entry": function(state, str) {
          return state.sys.wrapCitationEntry(str, this.item_id, this.locator_txt, this.suffix_txt);
        },
        "@bibliography/entry": function(state, str) {
          var insert = "";
          if (state.sys.embedBibliographyEntry) {
            insert = state.sys.embedBibliographyEntry(this.item_id) + "\n";
          }
          return '  <div class="csl-entry">' + str + "</div>\n" + insert;
        },
        "@display/block": function(state, str) {
          return '\n\n    <div class="csl-block">' + str + "</div>\n";
        },
        "@display/left-margin": function(state, str) {
          return '\n    <div class="csl-left-margin">' + str + "</div>";
        },
        "@display/right-inline": function(state, str) {
          return '<div class="csl-right-inline">' + str + "</div>\n  ";
        },
        "@display/indent": function(state, str) {
          return '<div class="csl-indent">' + str + "</div>\n  ";
        },
        "@showid/true": function(state, str, cslid) {
          if (!state.tmp.just_looking && !state.tmp.suppress_decorations) {
            if (cslid) {
              return '<span class="' + state.opt.nodenames[cslid] + '" cslid="' + cslid + '">' + str + "</span>";
            } else if (this.params && "string" === typeof str) {
              var prePunct = "";
              if (str) {
                var m = str.match(CSL2.VARIABLE_WRAPPER_PREPUNCT_REX);
                prePunct = m[1];
                str = m[2];
              }
              var postPunct = "";
              if (str && CSL2.SWAPPING_PUNCTUATION.indexOf(str.slice(-1)) > -1) {
                postPunct = str.slice(-1);
                str = str.slice(0, -1);
              }
              return state.sys.variableWrapper(this.params, prePunct, str, postPunct);
            } else {
              return str;
            }
          } else {
            return str;
          }
        },
        "@URL/true": function(state, str) {
          return '<a href="' + str + '">' + str + "</a>";
        },
        "@DOI/true": function(state, str) {
          var doiurl = str;
          if (!str.match(/^https?:\/\//)) {
            doiurl = "https://doi.org/" + str;
          }
          return '<a href="' + doiurl + '">' + str + "</a>";
        }
      };
      CSL2.Output.Formats.prototype.text = {
        //
        // text_escape: Format-specific function for escaping text destined
        // for output.  Takes the text to be escaped as sole argument.  Function
        // will be run only once across each portion of text to be escaped, it
        // need not be idempotent.
        //
        "text_escape": function(text) {
          if (!text) {
            text = "";
          }
          return text;
        },
        "bibstart": "",
        "bibend": "",
        "@font-style/italic": false,
        "@font-style/oblique": false,
        "@font-style/normal": false,
        "@font-variant/small-caps": false,
        "@passthrough/true": CSL2.Output.Formatters.passthrough,
        "@font-variant/normal": false,
        "@font-weight/bold": false,
        "@font-weight/normal": false,
        "@font-weight/light": false,
        "@text-decoration/none": false,
        "@text-decoration/underline": false,
        "@vertical-align/baseline": false,
        "@vertical-align/sup": false,
        "@vertical-align/sub": false,
        "@strip-periods/true": CSL2.Output.Formatters.passthrough,
        "@strip-periods/false": CSL2.Output.Formatters.passthrough,
        "@quotes/true": function(state, str) {
          if ("undefined" === typeof str) {
            return state.getTerm("open-quote");
          }
          return state.getTerm("open-quote") + str + state.getTerm("close-quote");
        },
        "@quotes/inner": function(state, str) {
          if ("undefined" === typeof str) {
            return "\u2019";
          }
          return state.getTerm("open-inner-quote") + str + state.getTerm("close-inner-quote");
        },
        "@quotes/false": false,
        //"@bibliography/body": function (state,str){
        //    return "<div class=\"csl-bib-body\">\n"+str+"</div>";
        //},
        "@cite/entry": function(state, str) {
          return state.sys.wrapCitationEntry(str, this.item_id, this.locator_txt, this.suffix_txt);
        },
        "@bibliography/entry": function(state, str) {
          return str + "\n";
        },
        "@display/block": function(state, str) {
          return "\n" + str;
        },
        "@display/left-margin": function(state, str) {
          return str + " ";
        },
        "@display/right-inline": function(state, str) {
          return str;
        },
        "@display/indent": function(state, str) {
          return "\n    " + str;
        },
        "@showid/true": function(state, str) {
          return str;
        },
        "@URL/true": function(state, str) {
          return str;
        },
        "@DOI/true": function(state, str) {
          return str;
        }
      };
      CSL2.Output.Formats.prototype.rtf = {
        //
        // text_escape: Format-specific function for escaping text destined
        // for output.  Takes the text to be escaped as sole argument.  Function
        // will be run only once across each portion of text to be escaped, it
        // need not be idempotent.
        //
        "text_escape": function(text) {
          if (!text) {
            text = "";
          }
          return text.replace(/([\\{}])/g, "\\$1").replace(
            CSL2.SUPERSCRIPTS_REGEXP,
            function(aChar) {
              return "\\super " + CSL2.SUPERSCRIPTS[aChar] + "\\nosupersub{}";
            }
          ).replace(
            /[\u007F-\uFFFF]/g,
            function(aChar) {
              return "\\uc0\\u" + aChar.charCodeAt(0).toString() + "{}";
            }
          ).split("	").join("\\tab{}");
        },
        "@passthrough/true": CSL2.Output.Formatters.passthrough,
        "@font-style/italic": "{\\i{}%%STRING%%}",
        "@font-style/normal": "{\\i0{}%%STRING%%}",
        "@font-style/oblique": "{\\i{}%%STRING%%}",
        "@font-variant/small-caps": "{\\scaps %%STRING%%}",
        "@font-variant/normal": "{\\scaps0{}%%STRING%%}",
        "@font-weight/bold": "{\\b{}%%STRING%%}",
        "@font-weight/normal": "{\\b0{}%%STRING%%}",
        "@font-weight/light": false,
        "@text-decoration/none": false,
        "@text-decoration/underline": "{\\ul{}%%STRING%%}",
        "@vertical-align/baseline": false,
        "@vertical-align/sup": "\\super %%STRING%%\\nosupersub{}",
        "@vertical-align/sub": "\\sub %%STRING%%\\nosupersub{}",
        "@strip-periods/true": CSL2.Output.Formatters.passthrough,
        "@strip-periods/false": CSL2.Output.Formatters.passthrough,
        "@quotes/true": function(state, str) {
          if ("undefined" === typeof str) {
            return CSL2.Output.Formats.rtf.text_escape(state.getTerm("open-quote"));
          }
          return CSL2.Output.Formats.rtf.text_escape(state.getTerm("open-quote")) + str + CSL2.Output.Formats.rtf.text_escape(state.getTerm("close-quote"));
        },
        "@quotes/inner": function(state, str) {
          if ("undefined" === typeof str) {
            return CSL2.Output.Formats.rtf.text_escape("\u2019");
          }
          return CSL2.Output.Formats.rtf.text_escape(state.getTerm("open-inner-quote")) + str + CSL2.Output.Formats.rtf.text_escape(state.getTerm("close-inner-quote"));
        },
        "@quotes/false": false,
        "bibstart": "{\\rtf ",
        "bibend": "}",
        "@display/block": "\\line{}%%STRING%%\\line\r\n",
        "@cite/entry": function(state, str) {
          return state.sys.wrapCitationEntry(str, this.item_id, this.locator_txt, this.suffix_txt);
        },
        "@bibliography/entry": function(state, str) {
          return str;
        },
        "@display/left-margin": function(state, str) {
          return str + "\\tab ";
        },
        "@display/right-inline": function(state, str) {
          return str + "\r\n";
        },
        "@display/indent": function(state, str) {
          return "\n\\tab " + str + "\\line\r\n";
        },
        "@showid/true": function(state, str) {
          if (!state.tmp.just_looking && !state.tmp.suppress_decorations) {
            var prePunct = "";
            if (str) {
              var m = str.match(CSL2.VARIABLE_WRAPPER_PREPUNCT_REX);
              prePunct = m[1];
              str = m[2];
            }
            var postPunct = "";
            if (str && CSL2.SWAPPING_PUNCTUATION.indexOf(str.slice(-1)) > -1) {
              postPunct = str.slice(-1);
              str = str.slice(0, -1);
            }
            return state.sys.variableWrapper(this.params, prePunct, str, postPunct);
          } else {
            return str;
          }
        },
        "@URL/true": function(state, str) {
          return str;
        },
        "@DOI/true": function(state, str) {
          return str;
        }
      };
      CSL2.Output.Formats.prototype.asciidoc = {
        "text_escape": function(text) {
          if (!text) {
            text = "";
          }
          return text.replace("*", "pass:[*]", "g").replace("_", "pass:[_]", "g").replace("#", "pass:[#]", "g").replace("^", "pass:[^]", "g").replace("~", "pass:[~]", "g").replace("[[", "pass:[[[]", "g").replace("  ", "&#160; ", "g").replace(CSL2.SUPERSCRIPTS_REGEXP, function(aChar) {
            return "^" + CSL2.SUPERSCRIPTS[aChar] + "^";
          });
        },
        "bibstart": "",
        "bibend": "",
        "@passthrough/true": CSL2.Output.Formatters.passthrough,
        "@font-style/italic": "__%%STRING%%__",
        "@font-style/oblique": "__%%STRING%%__",
        "@font-style/normal": false,
        "@font-variant/small-caps": "[small-caps]#%%STRING%%#",
        "@font-variant/normal": false,
        "@font-weight/bold": "**%%STRING%%**",
        "@font-weight/normal": false,
        "@font-weight/light": false,
        "@text-decoration/none": false,
        "@text-decoration/underline": "[underline]##%%STRING%%##",
        "@vertical-align/sup": "^^%%STRING%%^^",
        "@vertical-align/sub": "~~%%STRING%%~~",
        "@vertical-align/baseline": false,
        "@strip-periods/true": CSL2.Output.Formatters.passthrough,
        "@strip-periods/false": CSL2.Output.Formatters.passthrough,
        "@quotes/true": function(state, str) {
          if ("undefined" === typeof str) {
            return "``";
          }
          return "``" + str + "''";
        },
        "@quotes/inner": function(state, str) {
          if ("undefined" === typeof str) {
            return "`";
          }
          return "`" + str + "'";
        },
        "@quotes/false": false,
        "@cite/entry": function(state, str) {
          return state.sys.wrapCitationEntry(str, this.item_id, this.locator_txt, this.suffix_txt);
        },
        "@bibliography/entry": function(state, str) {
          return str + "\n";
        },
        "@display/block": function(state, str) {
          return str;
        },
        "@display/left-margin": function(state, str) {
          return str;
        },
        "@display/right-inline": function(state, str) {
          return " " + str;
        },
        "@display/indent": function(state, str) {
          return " " + str;
        },
        "@showid/true": function(state, str) {
          if (!state.tmp.just_looking && !state.tmp.suppress_decorations && this.params && "string" === typeof str) {
            var prePunct = "";
            if (str) {
              var m = str.match(CSL2.VARIABLE_WRAPPER_PREPUNCT_REX);
              prePunct = m[1];
              str = m[2];
            }
            var postPunct = "";
            if (str && CSL2.SWAPPING_PUNCTUATION.indexOf(str.slice(-1)) > -1) {
              postPunct = str.slice(-1);
              str = str.slice(0, -1);
            }
            return state.sys.variableWrapper(this.params, prePunct, str, postPunct);
          } else {
            return str;
          }
        },
        "@URL/true": function(state, str) {
          return str;
        },
        "@DOI/true": function(state, str) {
          var doiurl = str;
          if (!str.match(/^https?:\/\//)) {
            doiurl = "https://doi.org/" + str;
          }
          return doiurl + "[" + str + "]";
        }
      };
      CSL2.Output.Formats.prototype.fo = {
        "text_escape": function(text) {
          if (!text) {
            text = "";
          }
          return text.replace(/&/g, "&#38;").replace(/</g, "&#60;").replace(/>/g, "&#62;").replace("  ", "&#160; ", "g").replace(CSL2.SUPERSCRIPTS_REGEXP, function(aChar) {
            return '<fo:inline vertical-align="super">' + CSL2.SUPERSCRIPTS[aChar] + "</fo:inline>";
          });
        },
        "bibstart": "",
        "bibend": "",
        "@passthrough/true": CSL2.Output.Formatters.passthrough,
        "@font-style/italic": '<fo:inline font-style="italic">%%STRING%%</fo:inline>',
        "@font-style/oblique": '<fo:inline font-style="oblique">%%STRING%%</fo:inline>',
        "@font-style/normal": '<fo:inline font-style="normal">%%STRING%%</fo:inline>',
        "@font-variant/small-caps": '<fo:inline font-variant="small-caps">%%STRING%%</fo:inline>',
        "@font-variant/normal": '<fo:inline font-variant="normal">%%STRING%%</fo:inline>',
        "@font-weight/bold": '<fo:inline font-weight="bold">%%STRING%%</fo:inline>',
        "@font-weight/normal": '<fo:inline font-weight="normal">%%STRING%%</fo:inline>',
        "@font-weight/light": '<fo:inline font-weight="lighter">%%STRING%%</fo:inline>',
        "@text-decoration/none": '<fo:inline text-decoration="none">%%STRING%%</fo:inline>',
        "@text-decoration/underline": '<fo:inline text-decoration="underline">%%STRING%%</fo:inline>',
        "@vertical-align/sup": '<fo:inline vertical-align="super">%%STRING%%</fo:inline>',
        "@vertical-align/sub": '<fo:inline vertical-align="sub">%%STRING%%</fo:inline>',
        "@vertical-align/baseline": '<fo:inline vertical-align="baseline">%%STRING%%</fo:inline>',
        "@strip-periods/true": CSL2.Output.Formatters.passthrough,
        "@strip-periods/false": CSL2.Output.Formatters.passthrough,
        "@quotes/true": function(state, str) {
          if ("undefined" === typeof str) {
            return state.getTerm("open-quote");
          }
          return state.getTerm("open-quote") + str + state.getTerm("close-quote");
        },
        "@quotes/inner": function(state, str) {
          if ("undefined" === typeof str) {
            return "\u2019";
          }
          return state.getTerm("open-inner-quote") + str + state.getTerm("close-inner-quote");
        },
        "@quotes/false": false,
        "@cite/entry": function(state, str) {
          return state.sys.wrapCitationEntry(str, this.item_id, this.locator_txt, this.suffix_txt);
        },
        "@bibliography/entry": function(state, str) {
          var indent = "";
          if (state.bibliography && state.bibliography.opt && state.bibliography.opt.hangingindent) {
            var hi = state.bibliography.opt.hangingindent;
            indent = ' start-indent="' + hi + 'em" text-indent="-' + hi + 'em"';
          }
          var insert = "";
          if (state.sys.embedBibliographyEntry) {
            insert = state.sys.embedBibliographyEntry(this.item_id) + "\n";
          }
          return '<fo:block id="' + this.system_id + '"' + indent + ">" + str + "</fo:block>\n" + insert;
        },
        "@display/block": function(state, str) {
          return "\n  <fo:block>" + str + "</fo:block>\n";
        },
        "@display/left-margin": function(state, str) {
          return '\n  <fo:table table-layout="fixed" width="100%">\n    <fo:table-column column-number="1" column-width="$$$__COLUMN_WIDTH_1__$$$"/>\n    <fo:table-column column-number="2" column-width="proportional-column-width(1)"/>\n    <fo:table-body>\n      <fo:table-row>\n        <fo:table-cell>\n          <fo:block>' + str + "</fo:block>\n        </fo:table-cell>\n        ";
        },
        "@display/right-inline": function(state, str) {
          return "<fo:table-cell>\n          <fo:block>" + str + "</fo:block>\n        </fo:table-cell>\n      </fo:table-row>\n    </fo:table-body>\n  </fo:table>\n";
        },
        "@display/indent": function(state, str) {
          return '<fo:block margin-left="2em">' + str + "</fo:block>\n";
        },
        "@showid/true": function(state, str) {
          if (!state.tmp.just_looking && !state.tmp.suppress_decorations && this.params && "string" === typeof str) {
            var prePunct = "";
            if (str) {
              var m = str.match(CSL2.VARIABLE_WRAPPER_PREPUNCT_REX);
              prePunct = m[1];
              str = m[2];
            }
            var postPunct = "";
            if (str && CSL2.SWAPPING_PUNCTUATION.indexOf(str.slice(-1)) > -1) {
              postPunct = str.slice(-1);
              str = str.slice(0, -1);
            }
            return state.sys.variableWrapper(this.params, prePunct, str, postPunct);
          } else {
            return str;
          }
        },
        "@URL/true": function(state, str) {
          return `<fo:basic-link external-destination="url('` + str + `')">` + str + "</fo:basic-link>";
        },
        "@DOI/true": function(state, str) {
          var doiurl = str;
          if (!str.match(/^https?:\/\//)) {
            doiurl = "https://doi.org/" + str;
          }
          return `<fo:basic-link external-destination="url('` + doiurl + `')">` + str + "</fo:basic-link>";
        }
      };
      CSL2.Output.Formats.prototype.latex = {
        "text_escape": function(text) {
          if (!text) {
            text = "";
          }
          return text;
        },
        "bibstart": "\\begin{thebibliography}{4}",
        "bibend": "\\end{thebibliography}",
        "@font-style/italic": "{\\em %%STRING%%}",
        "@font-style/oblique": false,
        "@font-style/normal": false,
        "@font-variant/small-caps": false,
        "@passthrough/true": CSL2.Output.Formatters.passthrough,
        "@font-variant/normal": false,
        "@font-weight/bold": "{\\bf %%STRING%%}",
        "@font-weight/normal": false,
        "@font-weight/light": false,
        "@text-decoration/none": false,
        "@text-decoration/underline": false,
        "@vertical-align/baseline": false,
        "@vertical-align/sup": false,
        "@vertical-align/sub": false,
        "@strip-periods/true": CSL2.Output.Formatters.passthrough,
        "@strip-periods/false": CSL2.Output.Formatters.passthrough,
        "@quotes/true": function(state, str) {
          if ("undefined" === typeof str) {
            return state.getTerm("open-quote");
          }
          return state.getTerm("open-quote") + str + state.getTerm("close-quote");
        },
        "@quotes/inner": function(state, str) {
          if ("undefined" === typeof str) {
            return "\u2019";
          }
          return state.getTerm("open-inner-quote") + str + state.getTerm("close-inner-quote");
        },
        "@quotes/false": false,
        //"@bibliography/body": function (state,str){
        //    return "<div class=\"csl-bib-body\">\n"+str+"</div>";
        //},
        "@cite/entry": function(state, str) {
          return state.sys.wrapCitationEntry(str, this.item_id, this.locator_txt, this.suffix_txt);
        },
        "@bibliography/entry": function(state, str) {
          return "\\bibitem{" + state.sys.embedBibliographyEntry(this.item_id) + "}\n";
        },
        "@display/block": function(state, str) {
          return "\n" + str;
        },
        "@display/left-margin": function(state, str) {
          return str;
        },
        "@display/right-inline": function(state, str) {
          return str;
        },
        "@display/indent": function(state, str) {
          return "\n    " + str;
        },
        "@showid/true": function(state, str, cslid) {
          return str;
        },
        "@URL/true": function(state, str) {
          return str;
        },
        "@DOI/true": function(state, str) {
          return str;
        }
      };
      CSL2.Output.Formats = new CSL2.Output.Formats();
      CSL2.Registry = function(state) {
        this.debug = false;
        this.state = state;
        this.registry = {};
        this.reflist = [];
        this.refhash = {};
        this.namereg = new CSL2.Registry.NameReg(state);
        this.citationreg = new CSL2.Registry.CitationReg(state);
        this.authorstrings = {};
        this.masterMap = {};
        this.mylist = [];
        this.myhash = {};
        this.deletes = [];
        this.inserts = [];
        this.uncited = {};
        this.refreshes = {};
        this.akeys = {};
        this.oldseq = {};
        this.return_data = {};
        this.ambigcites = {};
        this.ambigresets = {};
        this.sorter = new CSL2.Registry.Comparifier(state, "bibliography_sort");
        this.getSortedIds = function() {
          var ret = [];
          for (var i = 0, ilen = this.reflist.length; i < ilen; i += 1) {
            ret.push("" + this.reflist[i].id);
          }
          return ret;
        };
        this.getSortedRegistryItems = function() {
          var ret = [];
          for (var i = 0, ilen = this.reflist.length; i < ilen; i += 1) {
            ret.push(this.reflist[i]);
          }
          return ret;
        };
      };
      CSL2.Registry.prototype.init = function(itemIDs, uncited_flag) {
        var i, ilen;
        this.oldseq = {};
        if (uncited_flag) {
          this.uncited = {};
          for (var i = 0, ilen = itemIDs.length; i < ilen; i += 1) {
            if (!this.myhash[itemIDs[i]]) {
              this.mylist.push("" + itemIDs[i]);
            }
            this.uncited[itemIDs[i]] = true;
            this.myhash[itemIDs[i]] = true;
          }
        } else {
          for (var key in this.uncited) {
            itemIDs.push(key);
          }
          var myhash = {};
          for (i = itemIDs.length - 1; i > -1; i += -1) {
            if (myhash[itemIDs[i]]) {
              itemIDs = itemIDs.slice(0, i).concat(itemIDs.slice(i + 1));
            } else {
              myhash[itemIDs[i]] = true;
            }
          }
          this.mylist = itemIDs;
          this.myhash = myhash;
        }
        this.refreshes = {};
        this.touched = {};
        this.ambigsTouched = {};
        this.ambigresets = {};
      };
      CSL2.Registry.prototype.dopurge = function(myhash) {
        for (var i = this.mylist.length - 1; i > -1; i += -1) {
          if (this.citationreg.citationsByItemId) {
            if ((!this.citationreg.citationsByItemId || !this.citationreg.citationsByItemId[this.mylist[i]]) && !myhash[this.mylist[i]]) {
              delete this.myhash[this.mylist[i]];
              delete this.uncited[this.mylist[i]];
              this.mylist = this.mylist.slice(0, i).concat(this.mylist.slice(i + 1));
            }
          }
        }
        this.dodeletes(this.myhash);
      };
      CSL2.Registry.prototype.dodeletes = function(myhash) {
        var otheritems, key, ambig, pos, len, items, kkey, mypos, id;
        if ("string" === typeof myhash) {
          var key = myhash;
          myhash = {};
          myhash[key] = true;
        }
        for (var key in this.registry) {
          if (!myhash[key]) {
            if (this.uncited[key]) {
              continue;
            }
            otheritems = this.namereg.delitems(key);
            for (kkey in otheritems) {
              this.refreshes[kkey] = true;
            }
            ambig = this.registry[key].ambig;
            mypos = this.ambigcites[ambig].indexOf(key);
            if (mypos > -1) {
              items = this.ambigcites[ambig].slice();
              this.ambigcites[ambig] = items.slice(0, mypos).concat(items.slice(mypos + 1, items.length));
              this.ambigresets[ambig] = this.ambigcites[ambig].length;
            }
            len = this.ambigcites[ambig].length;
            for (pos = 0; pos < len; pos += 1) {
              id = "" + this.ambigcites[ambig][pos];
              this.refreshes[id] = true;
            }
            if (this.registry[key].siblings) {
              if (this.registry[key].siblings.length == 1) {
                var loneSiblingID = this.registry[key].siblings[0];
                if (this.registry[loneSiblingID].siblings) {
                  this.registry[loneSiblingID].siblings.pop();
                  this.registry[loneSiblingID].master = true;
                }
              } else if (this.registry[key].siblings.length > 1) {
                var removeIDs = [key];
                if (this.registry[key].master) {
                  var newmasterID = this.registry[key].siblings[0];
                  var newmaster = this.registry[newmasterID];
                  newmaster.master = true;
                  removeIDs.push(newmasterID);
                }
                var buffer = [];
                for (var k = this.registry[key].siblings.length - 1; k > -1; k += -1) {
                  var siblingID = this.registry[key].siblings.pop();
                  if (removeIDs.indexOf(siblingID) === -1) {
                    buffer.push(siblingID);
                  }
                }
                for (var k = buffer.length - 1; k > -1; k += -1) {
                  this.registry[key].siblings.push(buffer[k]);
                }
              }
            }
            for (var i = this.reflist.length - 1; i > -1; i--) {
              if (this.reflist[i].id === key) {
                this.reflist = this.reflist.slice(0, i).concat(this.reflist.slice(i + 1));
              }
            }
            delete this.registry[key];
            delete this.refhash[key];
            this.return_data.bibchange = true;
          }
        }
      };
      CSL2.Registry.prototype.doinserts = function(mylist) {
        var item, Item, akey, newitem, abase, i, ilen;
        if ("string" === typeof mylist) {
          mylist = [mylist];
        }
        for (var i = 0, ilen = mylist.length; i < ilen; i += 1) {
          item = mylist[i];
          if (!this.registry[item]) {
            Item = this.state.retrieveItem(item);
            akey = CSL2.getAmbiguousCite.call(this.state, Item);
            this.ambigsTouched[akey] = true;
            if (!Item.legislation_id) {
              this.akeys[akey] = true;
            }
            newitem = {
              "id": "" + item,
              "seq": 0,
              "offset": 0,
              "sortkeys": false,
              "ambig": false,
              "rendered": false,
              "disambig": false,
              "ref": Item,
              "newItem": true
            };
            this.registry[item] = newitem;
            if (this.citationreg.citationsByItemId && this.citationreg.citationsByItemId[item]) {
              this.registry[item]["first-reference-note-number"] = this.citationreg.citationsByItemId[item][0].properties.noteIndex;
            }
            abase = CSL2.getAmbigConfig.call(this.state);
            this.registerAmbigToken(akey, item, abase);
            this.touched[item] = true;
            this.return_data.bibchange = true;
          }
        }
      };
      CSL2.Registry.prototype.rebuildlist = function(nosort) {
        var len, pos, item, Item;
        if (!nosort) {
          this.reflist_inserts = [];
          len = this.mylist.length;
          for (pos = 0; pos < len; pos += 1) {
            item = this.mylist[pos];
            Item = this.registry[item];
            if (Item.newItem) {
              this.reflist_inserts.push(Item);
            }
            this.oldseq[item] = this.registry[item].seq;
            this.registry[item].seq = pos + 1;
          }
        } else {
          this.reflist = [];
          len = this.mylist.length;
          for (pos = 0; pos < len; pos += 1) {
            item = this.mylist[pos];
            Item = this.registry[item];
            this.reflist.push(Item);
            this.oldseq[item] = this.registry[item].seq;
            this.registry[item].seq = pos + 1;
          }
        }
      };
      CSL2.Registry.prototype.dorefreshes = function() {
        var key, regtoken, Item, akey, abase;
        for (var key in this.refreshes) {
          regtoken = this.registry[key];
          if (!regtoken) {
            continue;
          }
          regtoken.sortkeys = void 0;
          Item = this.state.refetchItem(key);
          var akey = regtoken.ambig;
          if ("undefined" === typeof akey) {
            this.state.tmp.disambig_settings = false;
            akey = CSL2.getAmbiguousCite.call(this.state, Item);
            abase = CSL2.getAmbigConfig.call(this.state);
            this.registerAmbigToken(akey, key, abase);
          }
          for (var akkey in this.ambigresets) {
            if (this.ambigresets[akkey] === 1) {
              var loneKey = this.ambigcites[akey][0];
              var Item = this.state.refetchItem(loneKey);
              this.registry[loneKey].disambig = new CSL2.AmbigConfig();
              this.state.tmp.disambig_settings = false;
              var akey = CSL2.getAmbiguousCite.call(this.state, Item);
              var abase = CSL2.getAmbigConfig.call(this.state);
              this.registerAmbigToken(akey, loneKey, abase);
            }
          }
          this.state.tmp.taintedItemIDs[key] = true;
          this.ambigsTouched[akey] = true;
          if (!Item.legislation_id) {
            this.akeys[akey] = true;
          }
          this.touched[key] = true;
        }
      };
      CSL2.Registry.prototype.setdisambigs = function() {
        for (var akey in this.ambigsTouched) {
          this.state.disambiguate.run(akey);
        }
        this.ambigsTouched = {};
        this.akeys = {};
      };
      CSL2.Registry.prototype.renumber = function() {
        var len, pos, item;
        if (this.state.bibliography_sort.opt.citation_number_sort_direction === CSL2.DESCENDING) {
          this.state.bibliography_sort.tmp.citation_number_map = {};
        }
        len = this.reflist.length;
        for (pos = 0; pos < len; pos += 1) {
          item = this.reflist[pos];
          item.seq = pos + 1;
          if (this.state.bibliography_sort.opt.citation_number_sort_direction === CSL2.DESCENDING) {
            this.state.bibliography_sort.tmp.citation_number_map[item.seq] = this.reflist.length - item.seq + 1;
          }
          if (this.state.opt.update_mode === CSL2.NUMERIC && item.seq != this.oldseq[item.id]) {
            this.state.tmp.taintedItemIDs[item.id] = true;
          }
          if (item.seq != this.oldseq[item.id]) {
            this.return_data.bibchange = true;
          }
        }
      };
      CSL2.Registry.prototype.setsortkeys = function() {
        var key;
        for (var i = 0, ilen = this.mylist.length; i < ilen; i += 1) {
          var key = this.mylist[i];
          if (this.touched[key] || this.state.tmp.taintedItemIDs[key] || !this.registry[key].sortkeys) {
            this.registry[key].sortkeys = CSL2.getSortKeys.call(this.state, this.state.retrieveItem(key), "bibliography_sort");
          }
        }
      };
      CSL2.Registry.prototype._insertItem = function(element, array) {
        array.splice(this._locationOf(element, array) + 1, 0, element);
        return array;
      };
      CSL2.Registry.prototype._locationOf = function(element, array, start, end) {
        if (array.length === 0) {
          return -1;
        }
        start = start || 0;
        end = end || array.length;
        var pivot = start + end >> 1;
        var c = this.sorter.compareKeys(element, array[pivot]);
        if (end - start <= 1) {
          return c == -1 ? pivot - 1 : pivot;
        }
        switch (c) {
          case -1:
            return this._locationOf(element, array, start, pivot);
          case 0:
            return pivot;
          case 1:
            return this._locationOf(element, array, pivot, end);
        }
      };
      CSL2.Registry.prototype.sorttokens = function(nosort) {
        var len, item, Item, pos;
        if (!nosort) {
          this.reflist_inserts = [];
          len = this.mylist.length;
          for (pos = 0; pos < len; pos += 1) {
            item = this.mylist[pos];
            Item = this.registry[item];
            if (Item.newItem) {
              this.reflist_inserts.push(Item);
            }
          }
          for (var key in this.state.tmp.taintedItemIDs) {
            if (this.registry[key] && !this.registry[key].newItem) {
              for (var i = this.reflist.length - 1; i > -1; i--) {
                if (this.reflist[i].id === key) {
                  this.reflist_inserts.push(this.reflist[i]);
                  this.reflist = this.reflist.slice(0, i).concat(this.reflist.slice(i + 1));
                }
              }
            }
          }
          for (var i = 0, ilen = this.reflist_inserts.length; i < ilen; i++) {
            var Item = this.reflist_inserts[i];
            delete Item.newItem;
            this.reflist = this._insertItem(Item, this.reflist);
          }
          for (pos = 0; pos < len; pos += 1) {
            item = this.mylist[pos];
            Item = this.registry[item];
            this.registry[item].seq = pos + 1;
          }
        }
      };
      CSL2.Registry.Comparifier = function(state, keyset) {
        var sort_directions, len, pos, compareKeys;
        var sortCompare = CSL2.getSortCompare.call(state, state.opt["default-locale-sort"]);
        sort_directions = state[keyset].opt.sort_directions;
        this.compareKeys = function(a, b) {
          len = a.sortkeys ? a.sortkeys.length : 0;
          for (pos = 0; pos < len; pos += 1) {
            var cmp = 0;
            if (a.sortkeys[pos] === b.sortkeys[pos]) {
              cmp = 0;
            } else if ("undefined" === typeof a.sortkeys[pos]) {
              cmp = sort_directions[pos][1];
            } else if ("undefined" === typeof b.sortkeys[pos]) {
              cmp = sort_directions[pos][0];
            } else {
              cmp = sortCompare(a.sortkeys[pos], b.sortkeys[pos]);
            }
            if (0 < cmp) {
              return sort_directions[pos][1];
            } else if (0 > cmp) {
              return sort_directions[pos][0];
            }
          }
          if (a.seq > b.seq) {
            return 1;
          } else if (a.seq < b.seq) {
            return -1;
          }
          return 0;
        };
        compareKeys = this.compareKeys;
        this.compareCompositeKeys = function(a, b) {
          return compareKeys(a[1], b[1]);
        };
      };
      CSL2.Registry.prototype.compareRegistryTokens = function(a, b) {
        if (a.seq > b.seq) {
          return 1;
        } else if (a.seq < b.seq) {
          return -1;
        }
        return 0;
      };
      CSL2.Registry.prototype.registerAmbigToken = function(akey, id, ambig_config) {
        if (!this.registry[id]) {
          CSL2.debug("Warning: unregistered item: itemID=(" + id + "), akey=(" + akey + ")");
        }
        if (this.registry[id] && this.registry[id].disambig && this.registry[id].disambig.names) {
          for (var i = 0, ilen = ambig_config.names.length; i < ilen; i += 1) {
            var new_names_params = ambig_config.names[i];
            var old_names_params = this.registry[id].disambig.names[i];
            if (new_names_params !== old_names_params) {
              this.state.tmp.taintedItemIDs[id] = true;
            } else if (ambig_config.givens[i]) {
              for (var j = 0, jlen = ambig_config.givens[i].length; j < jlen; j += 1) {
                var new_gnames_params = ambig_config.givens[i][j];
                var old_gnames_params = this.registry[id].disambig.givens[i][j];
                if (new_gnames_params !== old_gnames_params) {
                  this.state.tmp.taintedItemIDs[id] = true;
                }
              }
            }
          }
        }
        if (!this.ambigcites[akey]) {
          this.ambigcites[akey] = [];
        }
        if (this.ambigcites[akey].indexOf("" + id) === -1) {
          this.ambigcites[akey].push("" + id);
        }
        this.registry[id].ambig = akey;
        this.registry[id].disambig = CSL2.cloneAmbigConfig(ambig_config);
      };
      CSL2.getSortKeys = function(Item, key_type) {
        var area, root, extension, strip_prepositions, len, pos;
        if (false) {
          CSL2.debug("KEY TYPE: " + key_type);
        }
        area = this.tmp.area;
        root = this.tmp.root;
        extension = this.tmp.extension;
        strip_prepositions = CSL2.Util.Sort.strip_prepositions;
        this.tmp.area = key_type;
        this.tmp.root = key_type.indexOf("_") > -1 ? key_type.slice(0, -5) : key_type;
        this.tmp.extension = "_sort";
        this.tmp.disambig_override = true;
        this.tmp.disambig_request = false;
        this.tmp.suppress_decorations = true;
        CSL2.getCite.call(this, Item);
        this.tmp.suppress_decorations = false;
        this.tmp.disambig_override = false;
        len = this[key_type].keys.length;
        for (pos = 0; pos < len; pos += 1) {
          this[key_type].keys[pos] = strip_prepositions(this[key_type].keys[pos]);
        }
        if (false) {
          CSL2.debug("sort keys (" + key_type + "): " + this[key_type].keys);
        }
        this.tmp.area = area;
        this.tmp.root = root;
        this.tmp.extension = extension;
        return this[key_type].keys;
      };
      CSL2.Registry.NameReg = function(state) {
        var pkey, ikey, skey, dagopt, gdropt, items, strip_periods, set_keys, evalname, delitems, addname, myitems;
        this.state = state;
        this.namereg = {};
        this.nameind = {};
        this.nameindpkeys = {};
        this.itemkeyreg = {};
        strip_periods = function(str) {
          if (!str) {
            str = "";
          }
          return str.replace(/\./g, " ").replace(/\s+/g, " ").replace(/\s+$/, "");
        };
        set_keys = function(state2, itemid, nameobj) {
          pkey = strip_periods(nameobj.family);
          if (state2.opt["demote-non-dropping-particle"] === "never" && nameobj["non-dropping-particle"] && nameobj["family"]) {
            pkey = `${pkey} ${nameobj["non-dropping-particle"]}`;
          }
          skey = strip_periods(nameobj.given);
          var m = skey.match(/[,\!]* ([^,]+)$/);
          if (m && m[1] === m[1].toLowerCase()) {
            skey = skey.replace(/[,\!]* [^,]+$/, "");
          }
          ikey = CSL2.Util.Names.initializeWith(state2, skey, "%s");
          if (state2.citation.opt["givenname-disambiguation-rule"] === "by-cite") {
            pkey = "" + itemid + pkey;
          }
        };
        evalname = function(item_id, nameobj, namenum, request_base, form, initials) {
          var param;
          if (state.tmp.area.slice(0, 12) === "bibliography" && !form) {
            if ("string" === typeof initials) {
              return 1;
            } else {
              return 2;
            }
          }
          var res = state.nameOutput.getName(nameobj, "locale-translit", true);
          nameobj = res.name;
          set_keys(this.state, "" + item_id, nameobj);
          param = 2;
          dagopt = state.opt["disambiguate-add-givenname"];
          gdropt = state.citation.opt["givenname-disambiguation-rule"];
          var gdropt_orig = gdropt;
          if (gdropt === "by-cite") {
            gdropt = "all-names";
          }
          if ("short" === form) {
            param = 0;
          } else if ("string" === typeof initials) {
            param = 1;
          }
          if ("undefined" === typeof this.namereg[pkey] || "undefined" === typeof this.namereg[pkey].ikey[ikey]) {
            return param;
          }
          if (gdropt_orig === "by-cite" && param <= request_base) {
            return request_base;
          }
          if (!dagopt) {
            return param;
          }
          if ("string" === typeof gdropt && gdropt.slice(0, 12) === "primary-name" && namenum > 0) {
            return param;
          }
          if (!gdropt || gdropt === "all-names" || gdropt === "primary-name") {
            if (this.namereg[pkey].count > 1) {
              param = 1;
            }
            if (this.namereg[pkey].ikey && this.namereg[pkey].ikey[ikey].count > 1 || this.namereg[pkey].count > 1 && "string" !== typeof initials) {
              param = 2;
            }
          } else if (gdropt === "all-names-with-initials" || gdropt === "primary-name-with-initials") {
            if (this.namereg[pkey].count > 1) {
              param = 1;
            } else {
              param = 0;
            }
          }
          if (!state.registry.registry[item_id]) {
            if (form == "short") {
              return 0;
            } else if ("string" == typeof initials) {
              return 1;
            }
          } else {
            return param;
          }
        };
        delitems = function(ids) {
          var pos, len, posB, id, fullkey;
          if ("string" === typeof ids || "number" === typeof ids) {
            ids = ["" + ids];
          }
          var ret = {};
          len = ids.length;
          for (pos = 0; pos < len; pos += 1) {
            id = "" + ids[pos];
            if (!this.nameind[id]) {
              continue;
            }
            for (fullkey in this.nameind[id]) {
              if (this.nameind[id].hasOwnProperty(fullkey)) {
                var key = fullkey.split("::");
                pkey = key[0];
                ikey = key[1];
                skey = key[2];
                if ("undefined" === typeof this.namereg[pkey]) {
                  continue;
                }
                items = this.namereg[pkey].items;
                if (skey && this.namereg[pkey].ikey[ikey] && this.namereg[pkey].ikey[ikey].skey[skey]) {
                  myitems = this.namereg[pkey].ikey[ikey].skey[skey].items;
                  posB = myitems.indexOf("" + id);
                  if (posB > -1) {
                    this.namereg[pkey].ikey[ikey].skey[skey].items = myitems.slice(0, posB).concat(myitems.slice([posB + 1]));
                  }
                  if (this.namereg[pkey].ikey[ikey].skey[skey].items.length === 0) {
                    delete this.namereg[pkey].ikey[ikey].skey[skey];
                    this.namereg[pkey].ikey[ikey].count += -1;
                    if (this.namereg[pkey].ikey[ikey].count < 2) {
                      for (var i = 0, ilen = this.namereg[pkey].ikey[ikey].items.length; i < ilen; i += 1) {
                        state.tmp.taintedItemIDs[this.namereg[pkey].ikey[ikey].items[i]] = true;
                      }
                    }
                  }
                }
                if (ikey && this.namereg[pkey].ikey[ikey]) {
                  posB = this.namereg[pkey].ikey[ikey].items.indexOf("" + id);
                  if (posB > -1) {
                    items = this.namereg[pkey].ikey[ikey].items.slice();
                    this.namereg[pkey].ikey[ikey].items = items.slice(0, posB).concat(items.slice([posB + 1]));
                  }
                  if (this.namereg[pkey].ikey[ikey].items.length === 0) {
                    delete this.namereg[pkey].ikey[ikey];
                    this.namereg[pkey].count += -1;
                    if (this.namereg[pkey].count < 2) {
                      for (var i = 0, ilen = this.namereg[pkey].items.length; i < ilen; i += 1) {
                        state.tmp.taintedItemIDs[this.namereg[pkey].items[i]] = true;
                      }
                    }
                  }
                }
                if (pkey) {
                  posB = this.namereg[pkey].items.indexOf("" + id);
                  if (posB > -1) {
                    items = this.namereg[pkey].items.slice();
                    this.namereg[pkey].items = items.slice(0, posB).concat(items.slice([posB + 1], items.length));
                  }
                  if (this.namereg[pkey].items.length < 2) {
                    delete this.namereg[pkey];
                  }
                }
                delete this.nameind[id][fullkey];
              }
            }
            delete this.nameind[id];
            delete this.nameindpkeys[id];
          }
          return ret;
        };
        addname = function(item_id, nameobj, pos) {
          var i, ilen;
          var res = state.nameOutput.getName(nameobj, "locale-translit", true);
          nameobj = res.name;
          if (state.citation.opt["givenname-disambiguation-rule"] && state.citation.opt["givenname-disambiguation-rule"].slice(0, 8) === "primary-" && pos !== 0) {
            return;
          }
          set_keys(this.state, "" + item_id, nameobj);
          if (pkey) {
            if ("undefined" === typeof this.namereg[pkey]) {
              this.namereg[pkey] = {};
              this.namereg[pkey].count = 0;
              this.namereg[pkey].ikey = {};
              this.namereg[pkey].items = [item_id];
            } else if (this.namereg[pkey].items.indexOf(item_id) === -1) {
              this.namereg[pkey].items.push(item_id);
            }
          }
          if (pkey && ikey) {
            if ("undefined" === typeof this.namereg[pkey].ikey[ikey]) {
              this.namereg[pkey].ikey[ikey] = {};
              this.namereg[pkey].ikey[ikey].count = 0;
              this.namereg[pkey].ikey[ikey].skey = {};
              this.namereg[pkey].ikey[ikey].items = [item_id];
              this.namereg[pkey].count += 1;
              if (this.namereg[pkey].count === 2) {
                for (var i = 0, ilen = this.namereg[pkey].items.length; i < ilen; i += 1) {
                  state.tmp.taintedItemIDs[this.namereg[pkey].items[i]] = true;
                }
              }
            } else if (this.namereg[pkey].ikey[ikey].items.indexOf(item_id) === -1) {
              this.namereg[pkey].ikey[ikey].items.push(item_id);
            }
          }
          if (pkey && ikey && skey) {
            if ("undefined" === typeof this.namereg[pkey].ikey[ikey].skey[skey]) {
              this.namereg[pkey].ikey[ikey].skey[skey] = {};
              this.namereg[pkey].ikey[ikey].skey[skey].items = [item_id];
              this.namereg[pkey].ikey[ikey].count += 1;
              if (this.namereg[pkey].ikey[ikey].count === 2) {
                for (var i = 0, ilen = this.namereg[pkey].ikey[ikey].items.length; i < ilen; i += 1) {
                  state.tmp.taintedItemIDs[this.namereg[pkey].ikey[ikey].items[i]] = true;
                }
              }
            } else if (this.namereg[pkey].ikey[ikey].skey[skey].items.indexOf(item_id) === -1) {
              this.namereg[pkey].ikey[ikey].skey[skey].items.push(item_id);
            }
          }
          if ("undefined" === typeof this.nameind[item_id]) {
            this.nameind[item_id] = {};
            this.nameindpkeys[item_id] = {};
          }
          if (pkey) {
            this.nameind[item_id][pkey + "::" + ikey + "::" + skey] = true;
            this.nameindpkeys[item_id][pkey] = this.namereg[pkey];
          }
        };
        this.addname = addname;
        this.delitems = delitems;
        this.evalname = evalname;
      };
      CSL2.Registry.CitationReg = function() {
        this.citationById = {};
        this.citationByIndex = [];
      };
      CSL2.Disambiguation = function(state) {
        this.state = state;
        this.sys = this.state.sys;
        this.registry = state.registry.registry;
        this.ambigcites = state.registry.ambigcites;
        this.configModes();
        this.debug = false;
      };
      CSL2.Disambiguation.prototype.run = function(akey) {
        if (!this.modes.length) {
          return;
        }
        if (this.debug) {
          this.state.sys.print("[A] === RUN ===");
        }
        this.akey = akey;
        if (this.initVars(akey)) {
          this.runDisambig();
        }
      };
      CSL2.Disambiguation.prototype.runDisambig = function() {
        var ismax;
        if (this.debug) {
          this.state.sys.print("[C] === runDisambig() ===");
        }
        this.initGivens = true;
        while (this.lists.length) {
          this.gnameset = 0;
          this.gname = 0;
          this.clashes = [1, 0];
          while (this.lists[0][1].length) {
            this.listpos = 0;
            if (!this.base) {
              this.base = this.lists[0][0];
            }
            ismax = this.incrementDisambig();
            this.scanItems(this.lists[0]);
            this.evalScan(ismax);
          }
          this.lists = this.lists.slice(1);
        }
      };
      CSL2.Disambiguation.prototype.scanItems = function(list) {
        var pos, len, otherItem;
        if (this.debug) {
          this.state.sys.print("[2] === scanItems() ===");
        }
        this.Item = list[1][0];
        this.ItemCite = CSL2.getAmbiguousCite.call(this.state, this.Item, this.base, true);
        this.scanlist = list[1];
        this.partners = [];
        this.partners.push(this.Item);
        this.nonpartners = [];
        var clashes = 0;
        for (var pos = 1, len = list[1].length; pos < len; pos += 1) {
          otherItem = list[1][pos];
          var otherItemCite = CSL2.getAmbiguousCite.call(this.state, otherItem, this.base, true);
          if (this.debug) {
            if (pos > 1) {
              this.state.sys.print("  -----------");
            }
          }
          if (this.ItemCite === otherItemCite) {
            if (this.debug) {
              this.state.sys.print("  [CLASH]--> " + this.Item.id + ": " + this.ItemCite);
              this.state.sys.print("             " + otherItem.id + ": " + otherItemCite);
            }
            clashes += 1;
            this.partners.push(otherItem);
          } else {
            if (this.debug) {
              this.state.sys.print("  [clear]--> " + this.Item.id + ": " + this.ItemCite);
              this.state.sys.print("             " + otherItem.id + ": " + otherItemCite);
            }
            this.nonpartners.push(otherItem);
          }
        }
        this.clashes[0] = this.clashes[1];
        this.clashes[1] = clashes;
      };
      CSL2.Disambiguation.prototype.evalScan = function(maxed) {
        this[this.modes[this.modeindex]](maxed);
        if (maxed) {
          if (this.modeindex < this.modes.length - 1) {
            this.modeindex += 1;
          } else {
            this.lists[this.listpos + 1] = [this.base, []];
          }
        }
      };
      CSL2.Disambiguation.prototype.disNames = function(ismax) {
        var i, ilen;
        if (this.debug) {
          this.state.sys.print("[3] == disNames() ==");
        }
        if (this.clashes[1] === 0 && this.nonpartners.length === 1) {
          this.captureStepToBase();
          if (this.debug) {
            this.state.sys.print("  ** RESOLUTION [a]: lone partner, one nonpartner");
            this.state.sys.print("  registering " + this.partners[0].id + " and " + this.nonpartners[0].id);
          }
          this.state.registry.registerAmbigToken(this.akey, "" + this.nonpartners[0].id, this.betterbase);
          this.state.registry.registerAmbigToken(this.akey, "" + this.partners[0].id, this.betterbase);
          this.lists[this.listpos] = [this.betterbase, []];
        } else if (this.clashes[1] === 0) {
          this.captureStepToBase();
          if (this.debug) {
            this.state.sys.print("  ** RESOLUTION [b]: lone partner, unknown number of remaining nonpartners");
            this.state.sys.print("  registering " + this.partners[0].id);
          }
          this.state.registry.registerAmbigToken(this.akey, "" + this.partners[0].id, this.betterbase);
          this.lists[this.listpos] = [this.betterbase, this.nonpartners];
          if (this.nonpartners.length) {
            this.initGivens = true;
          }
        } else if (this.nonpartners.length === 1) {
          this.captureStepToBase();
          if (this.debug) {
            this.state.sys.print("  ** RESOLUTION [c]: lone nonpartner, unknown number of partners remaining");
            this.state.sys.print("  registering " + this.nonpartners[0].id);
          }
          this.state.registry.registerAmbigToken(this.akey, "" + this.nonpartners[0].id, this.betterbase);
          this.lists[this.listpos] = [this.betterbase, this.partners];
        } else if (this.clashes[1] < this.clashes[0]) {
          this.captureStepToBase();
          if (this.debug) {
            this.state.sys.print("  ** RESOLUTION [d]: better result, but no entries safe to register");
          }
          this.lists[this.listpos] = [this.betterbase, this.partners];
          this.lists.push([this.betterbase, this.nonpartners]);
        } else {
          if (this.debug) {
            this.state.sys.print("  ** RESOLUTION [e]: no improvement, and clashes remain");
          }
          if (ismax) {
            this.lists[this.listpos] = [this.betterbase, this.nonpartners];
            this.lists.push([this.betterbase, this.partners]);
            if (this.modeindex === this.modes.length - 1) {
              if (this.debug) {
                this.state.sys.print("     (registering clashing entries because we've run out of options)");
              }
              for (var i = 0, ilen = this.partners.length; i < ilen; i += 1) {
                this.state.registry.registerAmbigToken(this.akey, "" + this.partners[i].id, this.betterbase);
              }
              this.lists[this.listpos] = [this.betterbase, []];
            }
          }
        }
      };
      CSL2.Disambiguation.prototype.disExtraText = function() {
        if (this.debug) {
          this.state.sys.print("[3] === disExtraText ==");
        }
        var done = false;
        if (this.clashes[1] === 0 && this.nonpartners.length < 2) {
          done = true;
        }
        if (!done && (!this.base.disambiguate || this.state.tmp.disambiguate_count !== this.state.tmp.disambiguate_maxMax)) {
          this.modeindex = 0;
          this.base.disambiguate = this.state.tmp.disambiguate_count;
          this.betterbase.disambiguate = this.state.tmp.disambiguate_count;
          if (!this.base.disambiguate) {
            this.initGivens = true;
            this.base.disambiguate = 1;
            for (var i = 0, ilen = this.lists[this.listpos][1].length; i < ilen; i += 1) {
              this.state.tmp.taintedItemIDs[this.lists[this.listpos][1][i].id] = true;
            }
          } else {
            this.disNames();
          }
        } else if (done || this.state.tmp.disambiguate_count === this.state.tmp.disambiguate_maxMax) {
          if (done || this.modeindex === this.modes.length - 1) {
            var base = this.lists[this.listpos][0];
            for (var i = 0, ilen = this.lists[this.listpos][1].length; i < ilen; i += 1) {
              this.state.tmp.taintedItemIDs[this.lists[this.listpos][1][i].id] = true;
              this.state.registry.registerAmbigToken(this.akey, "" + this.lists[this.listpos][1][i].id, base);
            }
            this.lists[this.listpos] = [this.betterbase, []];
          } else {
            this.modeindex = this.modes.length - 1;
            var base = this.lists[this.listpos][0];
            base.disambiguate = true;
            for (var i = 0, ilen = this.lists[this.listpos][1].length; i < ilen; i += 1) {
              this.state.tmp.taintedItemIDs[this.lists[this.listpos][1][i].id] = true;
              this.state.registry.registerAmbigToken(this.akey, "" + this.lists[this.listpos][1][i].id, base);
            }
          }
        }
      };
      CSL2.Disambiguation.prototype.disYears = function() {
        var pos, len, tokens, token;
        if (this.debug) {
          this.state.sys.print("[3] === disYears ==");
        }
        tokens = [];
        var base = this.lists[this.listpos][0];
        if (this.clashes[1]) {
          for (var i = 0, ilen = this.state.registry.mylist.length; i < ilen; i += 1) {
            var origid = this.state.registry.mylist[i];
            for (var j = 0, jlen = this.lists[this.listpos][1].length; j < jlen; j += 1) {
              var token = this.lists[this.listpos][1][j];
              if (token.id == origid) {
                tokens.push(this.registry[token.id]);
                break;
              }
            }
          }
        }
        tokens.sort(this.state.registry.sorter.compareKeys);
        for (var pos = 0, len = tokens.length; pos < len; pos += 1) {
          base.year_suffix = "" + pos;
          var oldBase = this.state.registry.registry[tokens[pos].id].disambig;
          this.state.registry.registerAmbigToken(this.akey, "" + tokens[pos].id, base);
          if (CSL2.ambigConfigDiff(oldBase, base)) {
            this.state.tmp.taintedItemIDs[tokens[pos].id] = true;
          }
        }
        this.lists[this.listpos] = [this.betterbase, []];
      };
      CSL2.Disambiguation.prototype.incrementDisambig = function() {
        if (this.debug) {
          this.state.sys.print("\n[1] === incrementDisambig() ===");
        }
        if (this.initGivens) {
          this.initGivens = false;
          return false;
        }
        var maxed = false;
        var increment_names = true;
        if ("disNames" === this.modes[this.modeindex]) {
          increment_names = false;
          if ("number" !== typeof this.givensMax) {
            increment_names = true;
          }
          var increment_namesets = false;
          if ("number" !== typeof this.namesMax) {
            increment_namesets = true;
          }
          if ("number" === typeof this.givensMax) {
            if (this.base.givens.length && this.base.givens[this.gnameset][this.gname] < this.givensMax) {
              this.base.givens[this.gnameset][this.gname] += 1;
            } else {
              increment_names = true;
            }
          }
          if ("number" === typeof this.namesMax && increment_names) {
            if (this.state.opt["disambiguate-add-names"]) {
              increment_namesets = false;
              if (this.gname < this.namesMax) {
                this.base.names[this.gnameset] += 1;
                this.gname += 1;
              } else {
                increment_namesets = true;
              }
            } else {
              increment_namesets = true;
            }
          }
          if ("number" === typeof this.namesetsMax && increment_namesets) {
            if (this.gnameset < this.namesetsMax) {
              this.gnameset += 1;
              this.base.names[this.gnameset] = 1;
              this.gname = 0;
            }
          }
          if (this.debug) {
            this.state.sys.print("    ------------------");
            this.state.sys.print("    incremented values");
            this.state.sys.print("    ------------------");
            this.state.sys.print("    | gnameset: " + this.gnameset);
            this.state.sys.print("    | gname: " + this.gname);
            this.state.sys.print("    | names value: " + this.base.names[this.gnameset]);
            if (this.base.givens.length) {
              this.state.sys.print("    | givens value: " + this.base.givens[this.gnameset][this.gname]);
            } else {
              this.state.sys.print("    | givens value: nil");
            }
            this.state.sys.print("    | namesetsMax: " + this.namesetsMax);
            this.state.sys.print("    | namesMax: " + this.namesMax);
            this.state.sys.print("    | givensMax: " + this.givensMax);
          }
          if (("number" !== typeof this.namesetsMax || this.namesetsMax === -1 || this.gnameset === this.namesetsMax) && (!this.state.opt["disambiguate-add-names"] || "number" !== typeof this.namesMax || this.gname === this.namesMax) && ("number" != typeof this.givensMax || "undefined" === typeof this.base.givens[this.gnameset] || "undefined" === typeof this.base.givens[this.gnameset][this.gname] || this.base.givens[this.gnameset][this.gname] === this.givensMax)) {
            maxed = true;
            if (this.debug) {
              this.state.sys.print("    MAXED");
            }
          }
        } else if ("disExtraText" === this.modes[this.modeindex]) {
          this.base.disambiguate += 1;
          this.betterbase.disambiguate += 1;
        }
        return maxed;
      };
      CSL2.Disambiguation.prototype.initVars = function(akey) {
        var i, ilen, myIds, myItemBundles, myItems;
        if (this.debug) {
          this.state.sys.print("[B] === initVars() ===");
        }
        this.lists = [];
        this.base = false;
        this.betterbase = false;
        this.akey = akey;
        this.maxNamesByItemId = {};
        myItemBundles = [];
        myIds = this.ambigcites[akey];
        if (!myIds || !myIds.length) {
          return false;
        }
        var myItem = this.state.refetchItem("" + myIds[0]);
        this.getCiteData(myItem);
        this.base = CSL2.getAmbigConfig.call(this.state);
        if (myIds && myIds.length > 1) {
          myItemBundles.push([this.maxNamesByItemId[myItem.id], myItem]);
          for (var i = 1, ilen = myIds.length; i < ilen; i += 1) {
            myItem = this.state.refetchItem("" + myIds[i]);
            this.getCiteData(myItem, this.base);
            myItemBundles.push([this.maxNamesByItemId[myItem.id], myItem]);
          }
          myItemBundles.sort(
            function(a, b) {
              if (a[0] > b[0]) {
                return 1;
              } else if (a[0] < b[0]) {
                return -1;
              } else {
                if (a[1].id > b[1].id) {
                  return 1;
                } else if (a[1].id < b[1].id) {
                  return -1;
                } else {
                  return 0;
                }
              }
            }
          );
          myItems = [];
          for (var i = 0, ilen = myItemBundles.length; i < ilen; i += 1) {
            myItems.push(myItemBundles[i][1]);
          }
          this.lists.push([this.base, myItems]);
          this.Item = this.lists[0][1][0];
        } else {
          this.Item = this.state.refetchItem("" + myIds[0]);
        }
        this.modeindex = 0;
        if (this.state.citation.opt["disambiguate-add-names"] || true) {
          this.namesMax = this.maxNamesByItemId[this.Item.id][0];
        } else {
          var namesMax = this.base.names[0];
          for (var i = 1, ilen = this.base.names.length; i < ilen; i += 1) {
            namesMax = Math.max(namesMax, this.base.names.names[i]);
          }
        }
        this.padBase(this.base);
        this.padBase(this.betterbase);
        this.base.year_suffix = false;
        this.base.disambiguate = false;
        this.betterbase.year_suffix = false;
        this.betterbase.disambiguate = false;
        if (this.state.citation.opt["givenname-disambiguation-rule"] === "by-cite" && this.state.opt["disambiguate-add-givenname"]) {
          this.givensMax = 2;
        }
        return true;
      };
      CSL2.Disambiguation.prototype.padBase = function(base) {
        for (var i = 0, ilen = base.names.length; i < ilen; i += 1) {
          if (!base.givens[i]) {
            base.givens[i] = [];
          }
          for (var j = 0, jlen = base.names[i]; j < jlen; j += 1) {
            if (!base.givens[i][j]) {
              base.givens[i][j] = 0;
            }
          }
        }
      };
      CSL2.Disambiguation.prototype.configModes = function() {
        var dagopt, gdropt;
        this.modes = [];
        dagopt = this.state.opt["disambiguate-add-givenname"];
        gdropt = this.state.citation.opt["givenname-disambiguation-rule"];
        if (this.state.opt["disambiguate-add-names"] || dagopt && gdropt === "by-cite") {
          this.modes.push("disNames");
        }
        if (this.state.opt.development_extensions.prioritize_disambiguate_condition) {
          if (this.state.opt.has_disambiguate) {
            this.modes.push("disExtraText");
          }
          if (this.state.opt["disambiguate-add-year-suffix"]) {
            this.modes.push("disYears");
          }
        } else {
          if (this.state.opt["disambiguate-add-year-suffix"]) {
            this.modes.push("disYears");
          }
          if (this.state.opt.has_disambiguate) {
            this.modes.push("disExtraText");
          }
        }
      };
      CSL2.Disambiguation.prototype.getCiteData = function(Item, base) {
        if (!this.maxNamesByItemId[Item.id]) {
          CSL2.getAmbiguousCite.call(this.state, Item, base);
          base = CSL2.getAmbigConfig.call(this.state);
          this.maxNamesByItemId[Item.id] = CSL2.getMaxVals.call(this.state);
          this.state.registry.registry[Item.id].disambig.givens = this.state.tmp.disambig_settings.givens.slice();
          for (var i = 0, ilen = this.state.registry.registry[Item.id].disambig.givens.length; i < ilen; i += 1) {
            this.state.registry.registry[Item.id].disambig.givens[i] = this.state.tmp.disambig_settings.givens[i].slice();
          }
          this.namesetsMax = this.state.registry.registry[Item.id].disambig.names.length - 1;
          if (!this.base) {
            this.base = base;
            this.betterbase = CSL2.cloneAmbigConfig(base);
          }
          if (base.names.length < this.base.names.length) {
            this.base = base;
          }
          for (var i = 0, ilen = base.names.length; i < ilen; i += 1) {
            if (base.names[i] > this.base.names[i]) {
              this.base.givens[i] = base.givens[i].slice();
              this.base.names[i] = base.names[i];
              this.betterbase.names = this.base.names.slice();
              this.betterbase.givens = this.base.givens.slice();
              this.padBase(this.base);
              this.padBase(this.betterbase);
            }
          }
          this.betterbase.givens = this.base.givens.slice();
          for (var j = 0, jlen = this.base.givens.length; j < jlen; j += 1) {
            this.betterbase.givens[j] = this.base.givens[j].slice();
          }
        }
      };
      CSL2.Disambiguation.prototype.captureStepToBase = function() {
        if (this.state.citation.opt["givenname-disambiguation-rule"] === "by-cite" && this.base.givens && this.base.givens.length) {
          if ("undefined" !== typeof this.base.givens[this.gnameset][this.gname]) {
            if (this.betterbase.givens.length < this.base.givens.length) {
              this.betterbase.givens = JSON.parse(JSON.stringify(this.base.givens));
            }
            this.betterbase.givens[this.gnameset][this.gname] = this.base.givens[this.gnameset][this.gname];
          }
        }
        this.betterbase.names[this.gnameset] = this.base.names[this.gnameset];
      };
      CSL2.Engine.prototype.getJurisdictionList = function(jurisdiction) {
        var jurisdictionList = [];
        var jurisdictionElems = jurisdiction.split(":");
        for (var j = jurisdictionElems.length; j > 0; j--) {
          var composedID = jurisdictionElems.slice(0, j).join(":");
          jurisdictionList.push(composedID);
          if (this.opt.jurisdiction_fallbacks[composedID]) {
            var fallback = this.opt.jurisdiction_fallbacks[composedID];
            jurisdictionList.push(fallback);
          }
        }
        if (jurisdictionList.indexOf("us") === -1) {
          jurisdictionList.push("us");
        }
        return jurisdictionList;
      };
      CSL2.Engine.prototype.loadStyleModule = function(jurisdiction, xmlSource, skipFallback) {
        var myFallback = null;
        var macroCount = 0;
        this.juris[jurisdiction] = {};
        var myXml = CSL2.setupXml(xmlSource);
        myXml.addMissingNameNodes(myXml.dataObj);
        myXml.addInstitutionNodes(myXml.dataObj);
        myXml.insertPublisherAndPlace(myXml.dataObj);
        myXml.flagDateMacros(myXml.dataObj);
        var myNodes = myXml.getNodesByName(myXml.dataObj, "law-module");
        for (var i = 0, ilen = myNodes.length; i < ilen; i++) {
          var myTypes = myXml.getAttributeValue(myNodes[i], "types");
          if (myTypes) {
            this.juris[jurisdiction].types = {};
            myTypes = myTypes.split(/\s+/);
            for (var j = 0, jlen = myTypes.length; j < jlen; j++) {
              this.juris[jurisdiction].types[myTypes[j]] = true;
            }
          }
          if (!skipFallback) {
            myFallback = myXml.getAttributeValue(myNodes[i], "fallback");
            if (myFallback) {
              if (jurisdiction !== "us") {
                this.opt.jurisdiction_fallbacks[jurisdiction] = myFallback;
              }
            }
          }
        }
        var lang = this.opt.lang ? this.opt.lang : this.opt["default-locale"][0];
        CSL2.SET_COURT_CLASSES(this, lang, myXml, myXml.dataObj);
        if (!this.juris[jurisdiction].types) {
          this.juris[jurisdiction].types = CSL2.MODULE_TYPES;
        }
        var myNodes = myXml.getNodesByName(myXml.dataObj, "macro");
        for (var i = 0, ilen = myNodes.length; i < ilen; i++) {
          var myName = myXml.getAttributeValue(myNodes[i], "name");
          if (!CSL2.MODULE_MACROS[myName]) {
            CSL2.debug('CSL: skipping non-modular macro name "' + myName + '" in module context');
            continue;
          }
          macroCount++;
          this.juris[jurisdiction][myName] = [];
          this.buildTokenLists(myNodes[i], this.juris[jurisdiction][myName]);
          this.configureTokenList(this.juris[jurisdiction][myName]);
        }
        return myFallback;
      };
      CSL2.Engine.prototype.retrieveAllStyleModules = function(jurisdictionList) {
        var ret = {};
        var preferences = this.locale[this.opt.lang].opts["jurisdiction-preference"];
        preferences = preferences ? preferences : [];
        preferences = [""].concat(preferences);
        for (var i = preferences.length - 1; i > -1; i--) {
          var preference = preferences[i];
          for (var j = 0, jlen = jurisdictionList.length; j < jlen; j++) {
            var jurisdiction = jurisdictionList[j];
            if (this.opt.jurisdictions_seen[jurisdiction]) {
              continue;
            }
            var res = this.sys.retrieveStyleModule(jurisdiction, preference);
            if (!res && !preference || res) {
              this.opt.jurisdictions_seen[jurisdiction] = true;
            }
            if (!res) {
              continue;
            }
            ret[jurisdiction] = res;
          }
        }
        return ret;
      };
      CSL2.ParticleList = /* @__PURE__ */ (function() {
        var always_dropping_1 = [[[0, 1], null]];
        var always_dropping_3 = [[[0, 3], null]];
        var always_non_dropping_1 = [[null, [0, 1]]];
        var always_non_dropping_2 = [[null, [0, 2]]];
        var always_non_dropping_3 = [[null, [0, 3]]];
        var either_1 = [[null, [0, 1]], [[0, 1], null]];
        var either_2 = [[null, [0, 2]], [[0, 2], null]];
        var either_1_dropping_best = [[[0, 1], null], [null, [0, 1]]];
        var either_2_dropping_best = [[[0, 2], null], [null, [0, 2]]];
        var either_3_dropping_best = [[[0, 3], null], [null, [0, 3]]];
        var non_dropping_2_alt_dropping_1_non_dropping_1 = [[null, [0, 2]], [[0, 1], [1, 2]]];
        var PARTICLES = [
          ["'s", always_non_dropping_1],
          ["'s-", always_non_dropping_1],
          ["'t", always_non_dropping_1],
          ["a", always_non_dropping_1],
          ["aan 't", always_non_dropping_2],
          ["aan de", always_non_dropping_2],
          ["aan den", always_non_dropping_2],
          ["aan der", always_non_dropping_2],
          ["aan het", always_non_dropping_2],
          ["aan t", always_non_dropping_2],
          ["aan", always_non_dropping_1],
          ["ad-", either_1],
          ["adh-", either_1],
          ["af", either_1],
          ["al", either_1],
          ["al-", either_1],
          ["am de", always_non_dropping_2],
          ["am", always_non_dropping_1],
          ["an-", either_1],
          ["ar-", either_1],
          ["as-", either_1],
          ["ash-", either_1],
          ["at-", either_1],
          ["ath-", either_1],
          ["auf dem", either_2_dropping_best],
          ["auf den", either_2_dropping_best],
          ["auf der", either_2_dropping_best],
          ["auf ter", always_non_dropping_2],
          ["auf", either_1_dropping_best],
          ["aus 'm", either_2_dropping_best],
          ["aus dem", either_2_dropping_best],
          ["aus den", either_2_dropping_best],
          ["aus der", either_2_dropping_best],
          ["aus m", either_2_dropping_best],
          ["aus", either_1_dropping_best],
          ["aus'm", either_2_dropping_best],
          ["az-", either_1],
          ["a\u0161-", either_1],
          ["a\u1E0D-", either_1],
          ["a\u1E0F-", either_1],
          ["a\u1E63-", either_1],
          ["a\u1E6D-", either_1],
          ["a\u1E6F-", either_1],
          ["a\u1E93-", either_1],
          ["ben", always_non_dropping_1],
          ["bij 't", always_non_dropping_2],
          ["bij de", always_non_dropping_2],
          ["bij den", always_non_dropping_2],
          ["bij het", always_non_dropping_2],
          ["bij t", always_non_dropping_2],
          ["bij", always_non_dropping_1],
          ["bin", always_non_dropping_1],
          ["boven d", always_non_dropping_2],
          ["boven d'", always_non_dropping_2],
          ["d", always_non_dropping_1],
          ["d'", either_1],
          ["da", either_1],
          ["dal", always_non_dropping_1],
          ["dal'", always_non_dropping_1],
          ["dall'", always_non_dropping_1],
          ["dalla", always_non_dropping_1],
          ["das", either_1],
          ["de die le", always_non_dropping_3],
          ["de die", always_non_dropping_2],
          ["de l", always_non_dropping_2],
          ["de l'", always_non_dropping_2],
          ["de la", non_dropping_2_alt_dropping_1_non_dropping_1],
          ["de las", non_dropping_2_alt_dropping_1_non_dropping_1],
          ["de le", always_non_dropping_2],
          ["de li", either_2],
          ["de van der", always_non_dropping_3],
          ["de", either_1],
          ["de'", either_1],
          ["deca", always_non_dropping_1],
          ["degli", either_1],
          ["dei", either_1],
          ["del", either_1],
          ["dela", always_dropping_1],
          ["dell'", either_1],
          ["della", either_1],
          ["delle", either_1],
          ["dello", either_1],
          ["den", either_1],
          ["der", either_1],
          ["des", either_1],
          ["di", either_1],
          ["die le", always_non_dropping_2],
          ["do", always_non_dropping_1],
          ["don", always_non_dropping_1],
          ["dos", either_1],
          ["du", either_1],
          ["ed-", either_1],
          ["edh-", either_1],
          ["el", either_1],
          ["el-", either_1],
          ["en-", either_1],
          ["er-", either_1],
          ["es-", either_1],
          ["esh-", either_1],
          ["et-", either_1],
          ["eth-", either_1],
          ["ez-", either_1],
          ["e\u0161-", either_1],
          ["e\u1E0D-", either_1],
          ["e\u1E0F-", either_1],
          ["e\u1E63-", either_1],
          ["e\u1E6D-", either_1],
          ["e\u1E6F-", either_1],
          ["e\u1E93-", either_1],
          ["het", always_non_dropping_1],
          ["i", always_non_dropping_1],
          ["il", always_dropping_1],
          ["im", always_non_dropping_1],
          ["in 't", always_non_dropping_2],
          ["in de", always_non_dropping_2],
          ["in den", always_non_dropping_2],
          ["in der", either_2],
          ["in het", always_non_dropping_2],
          ["in t", always_non_dropping_2],
          ["in", always_non_dropping_1],
          ["l", always_non_dropping_1],
          ["l'", always_non_dropping_1],
          ["la", always_non_dropping_1],
          ["las", always_non_dropping_1],
          ["le", always_non_dropping_1],
          ["les", either_1],
          ["lo", either_1],
          ["los", always_non_dropping_1],
          ["lou", always_non_dropping_1],
          ["of", always_non_dropping_1],
          ["onder 't", always_non_dropping_2],
          ["onder de", always_non_dropping_2],
          ["onder den", always_non_dropping_2],
          ["onder het", always_non_dropping_2],
          ["onder t", always_non_dropping_2],
          ["onder", always_non_dropping_1],
          ["op 't", always_non_dropping_2],
          ["op de", either_2],
          ["op den", always_non_dropping_2],
          ["op der", always_non_dropping_2],
          ["op gen", always_non_dropping_2],
          ["op het", always_non_dropping_2],
          ["op t", always_non_dropping_2],
          ["op ten", always_non_dropping_2],
          ["op", always_non_dropping_1],
          ["over 't", always_non_dropping_2],
          ["over de", always_non_dropping_2],
          ["over den", always_non_dropping_2],
          ["over het", always_non_dropping_2],
          ["over t", always_non_dropping_2],
          ["over", always_non_dropping_1],
          ["s", always_non_dropping_1],
          ["s'", always_non_dropping_1],
          ["sen", always_dropping_1],
          ["t", always_non_dropping_1],
          ["te", always_non_dropping_1],
          ["ten", always_non_dropping_1],
          ["ter", always_non_dropping_1],
          ["tho", always_non_dropping_1],
          ["thoe", always_non_dropping_1],
          ["thor", always_non_dropping_1],
          ["to", always_non_dropping_1],
          ["toe", always_non_dropping_1],
          ["tot", always_non_dropping_1],
          ["uijt 't", always_non_dropping_2],
          ["uijt de", always_non_dropping_2],
          ["uijt den", always_non_dropping_2],
          ["uijt te de", always_non_dropping_3],
          ["uijt ten", always_non_dropping_2],
          ["uijt", always_non_dropping_1],
          ["uit 't", always_non_dropping_2],
          ["uit de", always_non_dropping_2],
          ["uit den", always_non_dropping_2],
          ["uit het", always_non_dropping_2],
          ["uit t", always_non_dropping_2],
          ["uit te de", always_non_dropping_3],
          ["uit ten", always_non_dropping_2],
          ["uit", always_non_dropping_1],
          ["unter", always_non_dropping_1],
          ["v", always_non_dropping_1],
          ["v.", always_non_dropping_1],
          ["v.d.", always_non_dropping_1],
          ["van 't", always_non_dropping_2],
          ["van de l", always_non_dropping_3],
          ["van de l'", always_non_dropping_3],
          ["van de", always_non_dropping_2],
          ["van de", always_non_dropping_2],
          ["van den", always_non_dropping_2],
          ["van der", always_non_dropping_2],
          ["van gen", always_non_dropping_2],
          ["van het", always_non_dropping_2],
          ["van la", always_non_dropping_2],
          ["van t", always_non_dropping_2],
          ["van ter", always_non_dropping_2],
          ["van van de", always_non_dropping_3],
          ["van", either_1],
          ["vander", always_non_dropping_1],
          ["vd", always_non_dropping_1],
          ["ver", always_non_dropping_1],
          ["vom und zum", always_dropping_3],
          ["vom", either_1],
          ["von 't", always_non_dropping_2],
          ["von dem", either_2_dropping_best],
          ["von den", either_2_dropping_best],
          ["von der", either_2_dropping_best],
          ["von t", always_non_dropping_2],
          ["von und zu", either_3_dropping_best],
          ["von zu", either_2_dropping_best],
          ["von", either_1_dropping_best],
          ["voor 't", always_non_dropping_2],
          ["voor de", always_non_dropping_2],
          ["voor den", always_non_dropping_2],
          ["voor in 't", always_non_dropping_3],
          ["voor in t", always_non_dropping_3],
          ["voor", always_non_dropping_1],
          ["vor der", either_2_dropping_best],
          ["vor", either_1_dropping_best],
          ["z", always_dropping_1],
          ["ze", always_dropping_1],
          ["zu", either_1_dropping_best],
          ["zum", either_1],
          ["zur", either_1]
        ];
        return PARTICLES;
      })();
      CSL2.parseParticles = /* @__PURE__ */ (function() {
        function splitParticles(nameValue, firstNameFlag, caseOverride) {
          var origNameValue = nameValue;
          nameValue = caseOverride ? nameValue.toLowerCase() : nameValue;
          var particleList = [];
          var rex;
          var hasParticle;
          if (firstNameFlag) {
            nameValue = nameValue.split("").reverse().join("");
            rex = CSL2.PARTICLE_GIVEN_REGEXP;
          } else {
            rex = CSL2.PARTICLE_FAMILY_REGEXP;
          }
          var m = nameValue.match(rex);
          while (m) {
            var m1 = firstNameFlag ? m[1].split("").reverse().join("") : m[1];
            var firstChar = m ? m1 : false;
            var firstChar = firstChar ? m1.replace(/^[-\'\u02bb\u2019\s]*(.).*$/, "$1") : false;
            hasParticle = firstChar ? firstChar.toUpperCase() !== firstChar : false;
            if (!hasParticle) {
              break;
            }
            if (firstNameFlag) {
              particleList.push(origNameValue.slice(m1.length * -1));
              origNameValue = origNameValue.slice(0, m1.length * -1);
            } else {
              particleList.push(origNameValue.slice(0, m1.length));
              origNameValue = origNameValue.slice(m1.length);
            }
            nameValue = m[2];
            m = nameValue.match(rex);
          }
          if (firstNameFlag) {
            nameValue = nameValue.split("").reverse().join("");
            particleList.reverse();
            for (var i = 1, ilen = particleList.length; i < ilen; i++) {
              if (particleList[i].slice(0, 1) == " ") {
                particleList[i - 1] += " ";
              }
            }
            for (var i = 0, ilen = particleList.length; i < ilen; i++) {
              if (particleList[i].slice(0, 1) == " ") {
                particleList[i] = particleList[i].slice(1);
              }
            }
            nameValue = origNameValue.slice(0, nameValue.length);
          } else {
            nameValue = origNameValue.slice(nameValue.length * -1);
          }
          return [hasParticle, nameValue, particleList];
        }
        function trimLast(str) {
          var lastChar = str.slice(-1);
          str = str.trim();
          if (lastChar === " " && ["'", "\u2019"].indexOf(str.slice(-1)) > -1) {
            str += " ";
          }
          return str;
        }
        function parseSuffix(nameObj) {
          if (!nameObj.suffix && nameObj.given) {
            var m = nameObj.given.match(/(\s*,!*\s*)/);
            if (m) {
              var idx = nameObj.given.indexOf(m[1]);
              var possible_suffix = nameObj.given.slice(idx + m[1].length);
              var possible_comma = nameObj.given.slice(idx, idx + m[1].length).replace(/\s*/g, "");
              if (possible_suffix.replace(/\./g, "") === "et al" && !nameObj["dropping-particle"]) {
                nameObj["dropping-particle"] = possible_suffix;
                nameObj["comma-dropping-particle"] = ",";
              } else {
                if (possible_comma.length === 2) {
                  nameObj["comma-suffix"] = true;
                }
                nameObj.suffix = possible_suffix;
              }
              nameObj.given = nameObj.given.slice(0, idx);
            }
          }
        }
        return function(nameObj) {
          var res = splitParticles(nameObj.family);
          var lastNameValue = res[1];
          var lastParticleList = res[2];
          nameObj.family = lastNameValue;
          var nonDroppingParticle = trimLast(lastParticleList.join(""));
          if (nonDroppingParticle) {
            nameObj["non-dropping-particle"] = nonDroppingParticle;
          }
          parseSuffix(nameObj);
          var res = splitParticles(nameObj.given, true);
          var firstNameValue = res[1];
          var firstParticleList = res[2];
          nameObj.given = firstNameValue;
          var droppingParticle = firstParticleList.join("").trim();
          if (droppingParticle) {
            nameObj["dropping-particle"] = droppingParticle;
          }
        };
      })();
      module.exports = CSL2;
    }
  });

  // swiftlib-citeproc-entry.js
  var import_citeproc = __toESM(require_citeproc_commonjs());
  var styleXmlCache = /* @__PURE__ */ new Map();
  var localeXmlCache = /* @__PURE__ */ new Map();
  var citeItemById = /* @__PURE__ */ new Map();
  var engineByStyleId = /* @__PURE__ */ new Map();
  var itemBag = { map: {} };
  var cachedLocaleXml = "";
  var NAMED_ENTITIES = {
    amp: "&",
    lt: "<",
    gt: ">",
    quot: '"',
    apos: "'",
    nbsp: "\xA0",
    ndash: "\u2013",
    mdash: "\u2014",
    lsquo: "\u2018",
    rsquo: "\u2019",
    ldquo: "\u201C",
    rdquo: "\u201D",
    bull: "\u2022",
    hellip: "\u2026",
    trade: "\u2122",
    copy: "\xA9",
    reg: "\xAE",
    deg: "\xB0",
    times: "\xD7",
    divide: "\xF7",
    minus: "\u2212",
    ensp: "\u2002",
    emsp: "\u2003",
    thinsp: "\u2009",
    zwj: "\u200D",
    zwnj: "\u200C"
  };
  function decodeHTMLEntities(text) {
    if (!text) return "";
    return text.replace(
      /&(#x([0-9a-fA-F]+)|#(\d+)|([a-zA-Z]+));/g,
      (match, _full, hex, dec, named) => {
        if (hex) return String.fromCodePoint(parseInt(hex, 16));
        if (dec) return String.fromCodePoint(parseInt(dec, 10));
        if (named) {
          const lower = named.toLowerCase();
          if (NAMED_ENTITIES[lower] !== void 0) return NAMED_ENTITIES[lower];
        }
        return match;
      }
    );
  }
  function decodeHTMLEntitiesTwice(text) {
    const first = decodeHTMLEntities(text);
    return decodeHTMLEntities(first);
  }
  function stripTagsOneLine(html) {
    if (!html) return "";
    let text = html.replace(/<script[\s\S]*?<\/script>/gi, "").replace(/<style[\s\S]*?<\/style>/gi, "").replace(/<[^>]+>/g, " ");
    text = decodeHTMLEntitiesTwice(text);
    text = text.replace(/\u00A0/g, " ");
    text = text.replace(/\s+/g, " ").trim();
    return text;
  }
  function plainBibliographyFromBibResult(bib) {
    if (!bib || !bib[1] || !bib[1].length) return "";
    const entries = bib[1].map((h) => stripTagsOneLine(h)).filter((e) => e.length > 0);
    if (!entries.length) return "";
    return entries.join("\n");
  }
  function makeSys() {
    return {
      retrieveLocale: () => cachedLocaleXml,
      retrieveItem: (id) => itemBag.map[String(id)] || false
    };
  }
  async function getCachedStyleXml(base, styleId) {
    if (styleXmlCache.has(styleId)) return styleXmlCache.get(styleId);
    const styleUrl = `${base}/api/csl?id=${encodeURIComponent(styleId)}`;
    const _h = window.__SWIFTLIB_TOKEN ? { "Authorization": "Bearer " + window.__SWIFTLIB_TOKEN } : {};
    const r = await fetch(styleUrl, { headers: _h });
    if (!r.ok) throw new Error(`CSL ${r.status}`);
    const xml = await r.text();
    styleXmlCache.set(styleId, xml);
    return xml;
  }
  async function getCachedLocaleXml(base, localeId) {
    const id = localeId || "en-US";
    if (localeXmlCache.has(id)) return localeXmlCache.get(id);
    const localeUrl = `${base}/api/locale?id=${encodeURIComponent(id)}`;
    const _h = window.__SWIFTLIB_TOKEN ? { "Authorization": "Bearer " + window.__SWIFTLIB_TOKEN } : {};
    const r = await fetch(localeUrl, { headers: _h });
    if (!r.ok) throw new Error(`locale ${r.status}`);
    const xml = await r.text();
    localeXmlCache.set(id, xml);
    return xml;
  }
  async function getCachedCiteItems(base, allIds) {
    const ids = [...new Set((allIds || []).filter((n) => Number.isInteger(n)))];
    if (!ids.length) return [];
    const missing = ids.filter((id) => !citeItemById.has(id));
    if (missing.length) {
      const key = missing.slice().sort((a, b) => a - b).join(",");
      const _h = window.__SWIFTLIB_TOKEN ? { "Authorization": "Bearer " + window.__SWIFTLIB_TOKEN } : {};
      const r = await fetch(`${base}/api/cite-items?ids=${key}`, { headers: _h });
      if (!r.ok) throw new Error(`cite-items ${r.status}`);
      const items = await r.json();
      for (const it of items) {
        const numId = Number(it.id);
        if (!isNaN(numId)) citeItemById.set(numId, it);
      }
    }
    return ids.map((id) => citeItemById.get(id)).filter(Boolean);
  }
  function getOrCreateEngine(styleId, styleXml) {
    let engine = engineByStyleId.get(styleId);
    if (!engine) {
      engine = new import_citeproc.default.Engine(makeSys(), styleXml);
      engineByStyleId.set(styleId, engine);
    }
    return engine;
  }
  function emptyCitationFormatting() {
    return {
      bold: null,
      italic: null,
      underline: null,
      superscript: null,
      subscript: null,
      smallCaps: null
    };
  }
  function hasCitationFormatting(formatting) {
    return !!formatting && Object.values(formatting).some((value) => value !== null && value !== void 0);
  }
  function applyDecorationToCitationFormatting(formatting, key, rawValue) {
    if (!formatting || !key || rawValue == null) return;
    const value = String(rawValue).trim().toLowerCase();
    switch (key) {
      case "@font-style":
        if (value === "italic" || value === "oblique") formatting.italic = true;
        else if (value === "normal") formatting.italic = false;
        break;
      case "@font-weight":
        if (value === "bold") formatting.bold = true;
        else if (value === "normal" || value === "light") formatting.bold = false;
        break;
      case "@text-decoration":
        if (value === "underline") formatting.underline = true;
        else if (value === "none") formatting.underline = false;
        break;
      case "@font-variant":
        if (value === "small-caps") formatting.smallCaps = true;
        else if (value === "normal") formatting.smallCaps = false;
        break;
      case "@vertical-align":
        if (value === "sup") {
          formatting.superscript = true;
          formatting.subscript = false;
        } else if (value === "sub") {
          formatting.subscript = true;
          formatting.superscript = false;
        } else if (value === "baseline" || value === "normal") {
          formatting.superscript = false;
          formatting.subscript = false;
        }
        break;
      default:
        break;
    }
  }
  function citationFormattingFromStyleXml(styleXml) {
    if (!styleXml) return null;
    const formatting = emptyCitationFormatting();
    const attrNames = [
      "vertical-align",
      "font-style",
      "font-weight",
      "font-variant",
      "text-decoration"
    ];
    try {
      if (typeof DOMParser !== "undefined") {
        const doc = new DOMParser().parseFromString(styleXml, "application/xml");
        const citations = doc.getElementsByTagNameNS("*", "citation");
        for (let i = 0; i < citations.length; i++) {
          const layouts = citations[i].getElementsByTagNameNS("*", "layout");
          for (let j = 0; j < layouts.length; j++) {
            for (const attrName of attrNames) {
              const attrValue = layouts[j].getAttribute(attrName);
              if (attrValue != null) {
                applyDecorationToCitationFormatting(formatting, `@${attrName}`, attrValue);
              }
            }
            return hasCitationFormatting(formatting) ? formatting : null;
          }
        }
      }
    } catch (_) {
    }
    const layoutMatch = styleXml.match(/<citation\b[\s\S]*?<layout\b([^>]*)>/i);
    if (!layoutMatch) return null;
    for (const attrName of attrNames) {
      const attrPattern = new RegExp(`${attrName}\\s*=\\s*["']([^"']+)["']`, "i");
      const attrMatch = layoutMatch[1].match(attrPattern);
      if (attrMatch) {
        applyDecorationToCitationFormatting(formatting, `@${attrName}`, attrMatch[1]);
      }
    }
    return hasCitationFormatting(formatting) ? formatting : null;
  }
  function citationFormattingFromDecorations(decors, styleXml) {
    const formatting = citationFormattingFromStyleXml(styleXml) || emptyCitationFormatting();
    for (const decor of decors || []) {
      if (Array.isArray(decor) && decor.length >= 2) {
        applyDecorationToCitationFormatting(formatting, decor[0], decor[1]);
      }
    }
    return hasCitationFormatting(formatting) ? formatting : null;
  }
  async function preloadStyleAndLocale(styleId, opts) {
    const base = opts?.baseURL ?? "";
    const localeId = opts?.localeId || "en-US";
    const styleXml = await getCachedStyleXml(base, styleId);
    cachedLocaleXml = await getCachedLocaleXml(base, localeId);
    getOrCreateEngine(styleId, styleXml);
  }
  function clearCiteprocCaches() {
    styleXmlCache.clear();
    localeXmlCache.clear();
    citeItemById.clear();
    engineByStyleId.clear();
    itemBag.map = {};
    cachedLocaleXml = "";
  }
  async function renderDocumentPayload(styleId, scan, opts) {
    const base = opts?.baseURL ?? "";
    const localeId = opts?.localeId || "en-US";
    const allIds = [...new Set((scan.citations || []).flatMap((c) => c.ids || []))];
    if (!allIds.length) {
      return {
        citationTexts: {},
        superscriptCitationIDs: [],
        bibliographyText: "",
        bibliographyHtml: ""
      };
    }
    const [styleXml, locXml] = await Promise.all([
      getCachedStyleXml(base, styleId),
      getCachedLocaleXml(base, localeId)
    ]);
    cachedLocaleXml = locXml;
    const items = await getCachedCiteItems(base, allIds);
    const idToItem = {};
    for (const it of items) {
      idToItem[String(it.id)] = it;
    }
    itemBag.map = idToItem;
    const engine = getOrCreateEngine(styleId, styleXml);
    const citationObjs = (scan.citations || []).map((c) => ({
      citationID: c.citationID,
      citationItems: (c.ids || []).map((id) => ({ id: String(id) })),
      properties: { noteIndex: 0 }
    }));
    const triples = engine.rebuildProcessorState(citationObjs, "text");
    const citationTexts = {};
    for (let i = 0; i < (triples?.length || 0); i++) {
      const t = triples[i];
      if (!t) continue;
      citationTexts[t[0]] = t[2] || "";
    }
    engine.setOutputFormat("html");
    const bib = engine.makeBibliography();
    let bibliographyHtml = "";
    if (bib && bib[0] && bib[1]?.length) {
      const params = bib[0];
      const entries = bib[1];
      bibliographyHtml = (params.bibstart || "") + entries.join("") + (params.bibend || "");
    }
    const bibliographyText = plainBibliographyFromBibResult(bib);
    const decors = engine.citation?.opt?.layout_decorations || [];
    const citationFormatting = citationFormattingFromDecorations(decors, styleXml);
    const superscriptCitationIDs = [];
    if (citationFormatting?.superscript) {
      superscriptCitationIDs.push(...Object.keys(citationTexts));
    }
    return {
      citationTexts,
      citationFormatting,
      superscriptCitationIDs,
      bibliographyText,
      bibliographyHtml
    };
  }
  globalThis.SwiftLibCiteproc = {
    renderDocumentPayload,
    preloadStyleAndLocale,
    clearCiteprocCaches
  };
  globalThis.CSL = import_citeproc.default;
})();
