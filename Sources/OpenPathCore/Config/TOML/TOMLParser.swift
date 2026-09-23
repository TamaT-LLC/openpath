/// config.toml に必要な範囲だけをサポートする最小の TOML パーサ。
///
/// サポートする構文: 1 行の basic / literal string、真偽値、符号付き 10 進整数、文字列の配列（複数行・末尾カンマ可）、
/// 1 階層のテーブル（`[name]`）、コメント、空行。
/// TOML として正しくてもサポートしない構文は、誤読せずに `TOMLParseError.Kind.unsupported` として報告する。
public enum TOMLParser {
    public static func parse(_ source: String) throws(TOMLParseError) -> TOMLTable {
        var parser = TOMLDocumentParser(source: source)
        return try parser.parse()
    }
}

/// 行単位の構文（キーと値の組、テーブルヘッダ、コメント、空行）を解釈してテーブルを組み立てる
struct TOMLDocumentParser {
    private static let bareKeyPunctuation: Set<Unicode.Scalar> = ["_", "-"]

    private var cursor: TOMLCursor
    private var rootTable: TOMLTable = [:]
    /// `[name]` で定義したテーブル。ルートのキーとの重複はヘッダの時点で検査するため、最後にルートへ合流させる
    private var subtables: [String: TOMLTable] = [:]
    /// キーの追加先のテーブル名。nil ならルート
    private var currentSubtableName: String?

    init(source: String) {
        cursor = TOMLCursor(source: source)
    }

    mutating func parse() throws(TOMLParseError) -> TOMLTable {
        while !cursor.isAtEnd {
            try parseLine()
        }
        var document = rootTable
        for (name, subtable) in subtables {
            document[name] = .table(subtable)
        }
        return document
    }

    private mutating func parseLine() throws(TOMLParseError) {
        cursor.skipWhitespace()
        if cursor.current == "[" {
            try parseTableHeader()
        } else if !cursor.isAtLineEnd && cursor.current != "#" {
            try parseKeyValue()
        }
        try finishLine()
    }

    /// 行末までに空白とコメントしか無いことを確かめ、改行を消費する
    private mutating func finishLine() throws(TOMLParseError) {
        cursor.skipWhitespace()
        try cursor.skipComment()
        guard let scalar = cursor.current else { return }
        guard !cursor.consumeNewline() else { return }
        throw TOMLParseError(.unexpectedCharacter(scalar), at: cursor.position)
    }

    // MARK: - テーブルヘッダ

    private mutating func parseTableHeader() throws(TOMLParseError) {
        let headerStart = cursor.position
        cursor.advance()
        if cursor.current == "[" {
            throw TOMLParseError(.unsupported(.arrayOfTables), at: headerStart)
        }

        cursor.skipWhitespace()
        let namePosition = cursor.position
        let name = try readKey()
        cursor.skipWhitespace()

        guard let scalar = cursor.current, !cursor.isAtNewline, scalar != "#" else {
            throw TOMLParseError(.unterminatedTableHeader, at: headerStart)
        }
        switch scalar {
        case "]":
            cursor.advance()
        case ".":
            throw TOMLParseError(.unsupported(.nestedTable), at: headerStart)
        default:
            throw TOMLParseError(.unexpectedCharacter(scalar), at: cursor.position)
        }
        try defineSubtable(named: name, at: namePosition)
    }

    private mutating func defineSubtable(named name: String, at position: TOMLSourcePosition) throws(TOMLParseError) {
        guard rootTable[name] == nil, subtables[name] == nil else {
            throw TOMLParseError(.duplicateKey(name), at: position)
        }
        subtables[name] = [:]
        currentSubtableName = name
    }

    // MARK: - キーと値

    private mutating func parseKeyValue() throws(TOMLParseError) {
        let keyPosition = cursor.position
        let key = try readKey()
        cursor.skipWhitespace()

        if cursor.current == "." {
            throw TOMLParseError(.unsupported(.dottedKey), at: keyPosition)
        }
        guard cursor.current == "=" else {
            throw TOMLParseError(.missingEqualsSign, at: cursor.position)
        }
        cursor.advance()
        cursor.skipWhitespace()

        let value = try cursor.readValue()
        try insert(value, forKey: key, at: keyPosition)
    }

    /// ベアキーまたはクォートしたキーを 1 つ読む。ドット区切りは呼び出し側で検出する
    private mutating func readKey() throws(TOMLParseError) -> String {
        switch cursor.current {
        case "\"":
            return try cursor.readBasicString()
        case "'":
            return try cursor.readLiteralString()
        default:
            break
        }

        let keyStart = cursor.position
        var key = String.UnicodeScalarView()
        while let scalar = cursor.current, Self.isBareKeyScalar(scalar) {
            key.append(scalar)
            cursor.advance()
        }
        guard !key.isEmpty else {
            throw TOMLParseError(.invalidKey, at: keyStart)
        }
        return String(key)
    }

    private mutating func insert(
        _ value: TOMLValue,
        forKey key: String,
        at position: TOMLSourcePosition
    ) throws(TOMLParseError) {
        let duplicateKeyError = TOMLParseError(.duplicateKey(key), at: position)
        guard let tableName = currentSubtableName else {
            guard rootTable[key] == nil else { throw duplicateKeyError }
            rootTable[key] = value
            return
        }
        guard subtables[tableName]?[key] == nil else { throw duplicateKeyError }
        subtables[tableName, default: [:]][key] = value
    }

    /// ベアキーに使える文字は ASCII の英数字・`_`・`-` のみ
    private static func isBareKeyScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "A"..."Z", "a"..."z", "0"..."9":
            true
        default:
            bareKeyPunctuation.contains(scalar)
        }
    }
}
