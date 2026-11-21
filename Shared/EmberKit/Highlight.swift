import Foundation

// Code highlighting for the 12 languages the web highlights with highlight.js (apps/web/src/lib/highlight.ts):
// bash, css, diff, go, java, javascript, json, python, ruby, rust, sql and xml, by a block's `data-language`
// or an alias of one, and otherwise in whichever of them reads best. A light lexer per language marks the
// parts a theme colors: keywords, strings, comments, numbers, literals, types, tags and attributes.

public struct HighlightToken: Sendable, Hashable {
  public enum Kind: String, Sendable, Hashable {
    case keyword, string, comment, number, literal, type, builtIn, tag, attribute, meta, addition, deletion, variable
  }

  public var text: String
  /** Nil for text the lexer doesn't mark. */
  public var kind: Kind?

  public init(_ text: String, _ kind: Kind?) {
    self.text = text
    self.kind = kind
  }
}

public enum Highlight {
  public static let languages = ["bash", "css", "diff", "go", "java", "javascript", "json", "python", "ruby", "rust", "sql", "xml"]

  static let aliases: [String: String] = [
    "sh": "bash", "zsh": "bash", "shell": "bash", "console": "bash", "js": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript",
    "py": "python", "gyp": "python", "ipython": "python", "rb": "ruby", "gemspec": "ruby", "podspec": "ruby", "thor": "ruby", "irb": "ruby",
    "rs": "rust", "html": "xml", "xhtml": "xml", "rss": "xml", "atom": "xml", "xjb": "xml", "xsd": "xml", "xsl": "xml", "plist": "xml",
    "svg": "xml", "golang": "go", "patch": "diff", "jsp": "java", "jsonc": "json",
  ]

  /** C's block comment marks, spelled so they don't read as one here. */
  static let blockOpen = "/" + "*"
  static let blockClose = "*" + "/"

  /** The language `name` names, as highlight.js's `getLanguage` finds it, or nil for one it doesn't know. */
  public static func language(named name: String?) -> String? {
    guard let name else { return nil }
    let lowered = name.lowercased()
    if languages.contains(lowered) { return lowered }
    return aliases[lowered]
  }

  /** `code` highlighted in `language` when it's one of the 12, and otherwise in whichever reads best. */
  public static func highlight(_ code: String, language: String?) -> [HighlightToken] {
    tokens(code, Self.language(named: language) ?? detect(code))
  }

  /** The language that marks the most of `code` as its own (`highlightAuto`). */
  public static func detect(_ code: String) -> String {
    var best = ("bash", -1)
    for language in languages {
      let score = relevance(code, language)
      if score > best.1 { best = (language, score) }
    }
    return best.0
  }

  static let tells: [String: [String]] = [
    "xml": ["</", "/>", "<?xml", "<!DOCTYPE"], "json": ["\":", "{\n", "[\n"], "diff": ["\n@@ ", "--- ", "+++ ", "@@ -"],
    "python": ["def ", "import ", "self", "elif ", ":\n"], "ruby": ["end\n", "def ", "puts ", "do |", "@"], "rust": ["fn ", "let mut", "::", "impl ", "-> "],
    "go": ["func ", ":=", "package ", "fmt."], "java": ["public class", "System.out", "void ", "private "], "javascript": ["const ", "=>", "function", "console."],
    "css": ["{\n", ": ", ";\n", "px", "#"], "sql": ["SELECT", "FROM", "WHERE", "select ", "from ", "INSERT"], "bash": ["$ ", "echo ", "| ", "#!/", "sudo "],
  ]

  static func relevance(_ code: String, _ language: String) -> Int {
    var score = 0
    for token in tokens(code, language) {
      switch token.kind {
      case .keyword?, .builtIn?, .type?: score += 2
      case .tag?, .attribute?, .addition?, .deletion?, .meta?: score += 3
      case .comment?: score += 1
      default: break
      }
    }
    for tell in tells[language] ?? [] where code.contains(tell) { score += 4 }
    let first = code.trimmingCharacters(in: .whitespacesAndNewlines).first
    if language == "json", first != "{", first != "[" { score = 0 }
    if language == "diff", !code.contains("\n+"), !code.contains("\n-"), !code.hasPrefix("+"), !code.hasPrefix("-") { score = 0 }
    if language == "xml", !code.contains("<") { score = 0 }
    if language == "css", !code.contains("{") || code.contains("<") { score = 0 }
    return score
  }

  // MARK: - Lexers

  struct Grammar {
    var keywords: Set<String> = []
    var literals: Set<String> = []
    var builtIns: Set<String> = []
    var types: Set<String> = []
    var lineComments: [String] = []
    var blockComments = false
    var quotes: Set<Character> = ["\"", "'"]
    var caseInsensitive = false
    var variables = false
    var capitalizedTypes = false
  }

  static let grammars: [String: Grammar] = [
    "bash": Grammar(
      keywords: ["if", "then", "else", "elif", "fi", "for", "while", "in", "do", "done", "case", "esac", "function", "select", "until", "return", "local", "export", "readonly"],
      literals: ["true", "false"],
      builtIns: ["echo", "cd", "ls", "cat", "grep", "sed", "awk", "curl", "sudo", "exit", "set", "unset", "source", "printf", "read", "test", "eval", "exec", "mkdir", "rm", "cp", "mv", "git", "npm", "brew"],
      lineComments: ["#"], quotes: ["\"", "'", "`"], variables: true),
    "go": Grammar(
      keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var"],
      literals: ["true", "false", "nil", "iota"],
      builtIns: ["append", "cap", "close", "complex", "copy", "delete", "imag", "len", "make", "new", "panic", "print", "println", "real", "recover"],
      types: ["bool", "byte", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr"],
      lineComments: ["//"], blockComments: true, quotes: ["\"", "'", "`"]),
    "java": Grammar(
      keywords: ["abstract", "assert", "break", "case", "catch", "class", "const", "continue", "default", "do", "else", "enum", "extends", "final", "finally", "for", "goto", "if", "implements", "import", "instanceof", "interface", "native", "new", "package", "private", "protected", "public", "return", "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "transient", "try", "volatile", "while", "var", "record", "yield"],
      literals: ["true", "false", "null"],
      types: ["boolean", "byte", "char", "double", "float", "int", "long", "short", "void", "String"],
      lineComments: ["//"], blockComments: true, capitalizedTypes: true),
    "javascript": Grammar(
      keywords: ["as", "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export", "extends", "finally", "for", "from", "function", "get", "if", "import", "in", "instanceof", "let", "new", "of", "return", "set", "static", "super", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield"],
      literals: ["true", "false", "null", "undefined", "NaN", "Infinity"],
      builtIns: ["console", "window", "document", "Math", "JSON", "Promise", "Object", "Array", "String", "Number", "Boolean", "Symbol", "Map", "Set", "require", "module", "process"],
      lineComments: ["//"], blockComments: true, quotes: ["\"", "'", "`"]),
    "python": Grammar(
      keywords: ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield", "match", "case"],
      literals: ["True", "False", "None"],
      builtIns: ["print", "len", "range", "str", "int", "float", "dict", "list", "set", "tuple", "open", "super", "self", "isinstance", "enumerate", "zip", "map", "filter", "sorted"],
      lineComments: ["#"]),
    "ruby": Grammar(
      keywords: ["alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end", "ensure", "for", "if", "in", "module", "next", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then", "undef", "unless", "until", "when", "while", "yield", "require", "include", "attr_accessor", "attr_reader", "private", "protected", "public"],
      literals: ["true", "false", "nil"],
      builtIns: ["puts", "print", "p", "raise", "lambda", "proc", "new"],
      lineComments: ["#"], variables: true, capitalizedTypes: true),
    "rust": Grammar(
      keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "type", "unsafe", "use", "where", "while"],
      literals: ["true", "false", "None", "Some", "Ok", "Err"],
      builtIns: ["println!", "print!", "vec!", "format!", "panic!", "assert!", "assert_eq!"],
      types: ["i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize", "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box"],
      lineComments: ["//"], blockComments: true, quotes: ["\""], capitalizedTypes: true),
    "sql": Grammar(
      keywords: ["select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete", "create", "table", "drop", "alter", "add", "index", "join", "inner", "left", "right", "outer", "on", "as", "group", "by", "order", "having", "limit", "offset", "distinct", "union", "all", "in", "is", "like", "between", "exists", "case", "when", "then", "else", "end", "primary", "key", "foreign", "references", "default", "with", "returning", "asc", "desc", "begin", "commit", "rollback"],
      literals: ["null", "true", "false"],
      builtIns: ["count", "sum", "avg", "min", "max", "coalesce", "now", "lower", "upper", "length", "cast"],
      types: ["int", "integer", "text", "varchar", "char", "boolean", "date", "timestamp", "real", "blob", "numeric", "bigint", "serial"],
      lineComments: ["--"], blockComments: true, caseInsensitive: true),
  ]

  static func tokens(_ code: String, _ language: String) -> [HighlightToken] {
    switch language {
    case "diff": return diff(code)
    case "xml": return xml(code)
    case "css": return css(code)
    case "json": return json(code)
    default:
      guard let grammar = grammars[language] else { return [HighlightToken(code, nil)] }
      return generic(code, grammar)
    }
  }

  /** Joins neighbouring tokens of a kind, so a theme draws runs rather than characters. */
  static func merged(_ tokens: [HighlightToken]) -> [HighlightToken] {
    var out: [HighlightToken] = []
    for token in tokens where !token.text.isEmpty {
      if let last = out.last, last.kind == token.kind {
        out[out.count - 1].text += token.text
      } else {
        out.append(token)
      }
    }
    return out
  }

  static func isIdentifierStart(_ c: Character) -> Bool { c.isLetter || c == "_" }
  static func isIdentifier(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

  static func starts(_ s: [Character], _ prefix: String, at j: Int) -> Bool {
    let p = Array(prefix)
    guard j + p.count <= s.count else { return false }
    return Array(s[j..<(j + p.count)]) == p
  }

  /** Up to and past `close`, from `start`. */
  static func through(_ s: [Character], _ close: String, from start: Int) -> Int {
    var j = start
    while j < s.count, !starts(s, close, at: j) { j += 1 }
    return min(s.count, j + close.count)
  }

  static func generic(_ code: String, _ grammar: Grammar) -> [HighlightToken] {
    let s = Array(code)
    var out: [HighlightToken] = []
    var i = 0
    while i < s.count {
      let c = s[i]
      let afterDollar = i > 0 && s[i - 1] == "$"
      if grammar.lineComments.contains(where: { starts(s, $0, at: i) }), !(grammar.variables && afterDollar) {
        var j = i
        while j < s.count, s[j] != "\n" { j += 1 }
        out.append(HighlightToken(String(s[i..<j]), .comment))
        i = j
        continue
      }
      if grammar.blockComments, starts(s, blockOpen, at: i) {
        let j = through(s, blockClose, from: i + 2)
        out.append(HighlightToken(String(s[i..<j]), .comment))
        i = j
        continue
      }
      if grammar.quotes.contains(c) {
        var j = i + 1
        while j < s.count, s[j] != c {
          if s[j] == "\\" { j += 1 }
          if c != "`", j < s.count, s[j] == "\n" { break }
          j += 1
        }
        j = min(s.count, j + 1)
        out.append(HighlightToken(String(s[i..<j]), .string))
        i = j
        continue
      }
      if c.isNumber, i == 0 || !isIdentifier(s[i - 1]) {
        var j = i
        while j < s.count, s[j].isHexDigit || s[j] == "." || s[j] == "_" || s[j] == "x" || s[j] == "X" { j += 1 }
        out.append(HighlightToken(String(s[i..<j]), .number))
        i = j
        continue
      }
      if grammar.variables, c == "$" || c == "@", i + 1 < s.count, isIdentifierStart(s[i + 1]) || s[i + 1] == "{" || s[i + 1] == "@" {
        var j = i + 1
        while j < s.count, isIdentifier(s[j]) || s[j] == "{" || s[j] == "}" || s[j] == "@" { j += 1 }
        out.append(HighlightToken(String(s[i..<j]), .variable))
        i = j
        continue
      }
      if isIdentifierStart(c) {
        var j = i
        while j < s.count, isIdentifier(s[j]) { j += 1 }
        let bare = String(s[i..<j])
        let marked = j < s.count && (s[j] == "!" || s[j] == "?") ? bare + String(s[j]) : nil
        func kind(of word: String) -> HighlightToken.Kind? {
          let key = grammar.caseInsensitive ? word.lowercased() : word
          if grammar.keywords.contains(key) { return .keyword }
          if grammar.literals.contains(key) { return .literal }
          if grammar.builtIns.contains(key) { return .builtIn }
          if grammar.types.contains(key) { return .type }
          return nil
        }
        if let marked, let markedKind = kind(of: marked) {
          out.append(HighlightToken(marked, markedKind))
          i = j + 1
          continue
        }
        let bareKind = kind(of: bare) ?? (grammar.capitalizedTypes && bare.first?.isUppercase == true ? .type : nil)
        out.append(HighlightToken(bare, bareKind))
        i = j
        continue
      }
      out.append(HighlightToken(String(c), nil))
      i += 1
    }
    return merged(out)
  }

  static func diff(_ code: String) -> [HighlightToken] {
    var out: [HighlightToken] = []
    let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
    for (index, line) in lines.enumerated() {
      let text = String(line) + (index < lines.count - 1 ? "\n" : "")
      if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("@@") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
        out.append(HighlightToken(text, .meta))
      } else if line.hasPrefix("+") || line.hasPrefix(">") {
        out.append(HighlightToken(text, .addition))
      } else if line.hasPrefix("-") || line.hasPrefix("<") {
        out.append(HighlightToken(text, .deletion))
      } else {
        out.append(HighlightToken(text, nil))
      }
    }
    return merged(out)
  }

  static func xml(_ code: String) -> [HighlightToken] {
    let s = Array(code)
    var out: [HighlightToken] = []
    var i = 0
    while i < s.count {
      guard s[i] == "<" else {
        out.append(HighlightToken(String(s[i]), nil))
        i += 1
        continue
      }
      if starts(s, "<!--", at: i) {
        let j = through(s, "-->", from: i + 4)
        out.append(HighlightToken(String(s[i..<j]), .comment))
        i = j
        continue
      }
      var j = i + 1
      let special = j < s.count && (s[j] == "?" || s[j] == "!")
      if j < s.count, s[j] == "/" || special { j += 1 }
      while j < s.count, isIdentifier(s[j]) || s[j] == "-" || s[j] == ":" { j += 1 }
      out.append(HighlightToken(String(s[i..<j]), special ? .meta : .tag))
      i = j
      while i < s.count, s[i] != ">" {
        if s[i] == "\"" || s[i] == "'" {
          let quote = s[i]
          var k = i + 1
          while k < s.count, s[k] != quote { k += 1 }
          k = min(s.count, k + 1)
          out.append(HighlightToken(String(s[i..<k]), .string))
          i = k
        } else if isIdentifierStart(s[i]) {
          var k = i
          while k < s.count, isIdentifier(s[k]) || s[k] == "-" || s[k] == ":" { k += 1 }
          out.append(HighlightToken(String(s[i..<k]), .attribute))
          i = k
        } else {
          out.append(HighlightToken(String(s[i]), s[i] == "/" || s[i] == "?" ? .tag : nil))
          i += 1
        }
      }
      if i < s.count {
        out.append(HighlightToken(">", .tag))
        i += 1
      }
    }
    return merged(out)
  }

  static func css(_ code: String) -> [HighlightToken] {
    let s = Array(code)
    var out: [HighlightToken] = []
    var i = 0
    var depth = 0
    while i < s.count {
      let c = s[i]
      if starts(s, blockOpen, at: i) {
        let j = through(s, blockClose, from: i + 2)
        out.append(HighlightToken(String(s[i..<j]), .comment))
        i = j
        continue
      }
      if c == "\"" || c == "'" {
        var j = i + 1
        while j < s.count, s[j] != c { j += 1 }
        j = min(s.count, j + 1)
        out.append(HighlightToken(String(s[i..<j]), .string))
        i = j
        continue
      }
      if c == "{" { depth += 1 }
      if c == "}" { depth = max(0, depth - 1) }
      let starter = c == "@" || c.isNumber || (depth == 0 && (isIdentifierStart(c) || c == "." || c == "#")) || (depth > 0 && (isIdentifierStart(c) || c == "#"))
      guard starter else {
        out.append(HighlightToken(String(c), nil))
        i += 1
        continue
      }
      var j = i + 1
      while j < s.count, isIdentifier(s[j]) || s[j] == "-" || s[j] == "%" || (c.isNumber && s[j] == ".") { j += 1 }
      let word = String(s[i..<j])
      var kind: HighlightToken.Kind?
      if c == "@" {
        kind = .keyword
      } else if c.isNumber || (c == "#" && depth > 0) {
        kind = .number
      } else if depth == 0 {
        kind = .tag
      } else {
        var k = j
        while k < s.count, s[k] == " " { k += 1 }
        kind = k < s.count && s[k] == ":" ? .attribute : nil
      }
      out.append(HighlightToken(word, kind))
      i = j
    }
    return merged(out)
  }

  static func json(_ code: String) -> [HighlightToken] {
    let s = Array(code)
    var out: [HighlightToken] = []
    var i = 0
    while i < s.count {
      let c = s[i]
      if c == "\"" {
        var j = i + 1
        while j < s.count, s[j] != "\"" {
          if s[j] == "\\" { j += 1 }
          j += 1
        }
        j = min(s.count, j + 1)
        var k = j
        while k < s.count, s[k] == " " { k += 1 }
        out.append(HighlightToken(String(s[i..<j]), k < s.count && s[k] == ":" ? .attribute : .string))
        i = j
        continue
      }
      if c.isNumber || c == "-" {
        var j = i + 1
        while j < s.count, s[j].isNumber || s[j] == "." || s[j] == "e" || s[j] == "E" || s[j] == "+" || s[j] == "-" { j += 1 }
        out.append(HighlightToken(String(s[i..<j]), .number))
        i = j
        continue
      }
      if c.isLetter {
        var j = i
        while j < s.count, s[j].isLetter { j += 1 }
        let word = String(s[i..<j])
        out.append(HighlightToken(word, ["true", "false", "null"].contains(word) ? .literal : nil))
        i = j
        continue
      }
      out.append(HighlightToken(String(c), nil))
      i += 1
    }
    return merged(out)
  }
}
