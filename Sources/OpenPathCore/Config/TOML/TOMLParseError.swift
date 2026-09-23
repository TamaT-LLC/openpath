/// TOML のパースエラー。位置は 1 始まりの行番号と列番号（Unicode スカラー単位）。
public struct TOMLParseError: Error, Equatable, Sendable {
    public let line: Int
    public let column: Int
    public let kind: Kind

    public init(line: Int, column: Int, kind: Kind) {
        self.line = line
        self.column = column
        self.kind = kind
    }

    public enum Kind: Equatable, Sendable {
        /// 同じテーブル内でキー、またはテーブル名が重複している
        case duplicateKey(String)
        case unterminatedString
        case unterminatedArray
        case unterminatedTableHeader
        /// 未定義のエスケープ、または `\u` / `\U` の値が不正
        case invalidEscapeSequence
        case invalidKey
        case missingEqualsSign
        case missingValue
        /// 値として解釈できない語（クォートしていない文字列など）
        case invalidValue
        /// 整数が `Int` の範囲を超えている
        case integerOutOfRange
        case missingCommaOrClosingBracket
        /// 値の後ろの余分な文字や、文字列・コメント内の制御文字
        case unexpectedCharacter(Unicode.Scalar)
        /// TOML としては正しいが、このパーサがサポートしない構文
        case unsupported(UnsupportedFeature)
    }

    public enum UnsupportedFeature: Equatable, Sendable {
        /// `[a.b]`
        case nestedTable
        /// `[[a]]`
        case arrayOfTables
        /// `{ key = value }`
        case inlineTable
        /// `a.b = value`
        case dottedKey
        case float
        case dateTime
        /// `"""` / `'''`
        case multilineString
        /// `0x` / `0o` / `0b`
        case nonDecimalInteger
        /// 文字列以外（整数・真偽値・配列など）を要素に持つ配列
        case nonStringArrayElement
    }
}

extension TOMLParseError: CustomStringConvertible {
    public var description: String {
        "\(line) 行 \(column) 列: \(kind.message)"
    }
}

private extension TOMLParseError.Kind {
    var message: String {
        switch self {
        case .duplicateKey(let key): "キー '\(key)' が重複しています"
        case .unterminatedString: "文字列が閉じられていません"
        case .unterminatedArray: "配列が閉じられていません"
        case .unterminatedTableHeader: "テーブルヘッダが ']' で閉じられていません"
        case .invalidEscapeSequence: "不正なエスケープシーケンスです"
        case .invalidKey: "キーが不正です"
        case .missingEqualsSign: "キーの後に '=' が必要です"
        case .missingValue: "値がありません"
        case .invalidValue: "値を解釈できません"
        case .integerOutOfRange: "整数が範囲外です"
        case .missingCommaOrClosingBracket: "配列の要素の後に ',' または ']' が必要です"
        // 制御文字をそのまま出すとログが崩れるためエスケープする
        case .unexpectedCharacter(let scalar): "予期しない文字 '\(scalar.escaped(asASCII: false))' があります"
        case .unsupported(let feature): "サポートしていない構文です（\(feature.message)）"
        }
    }
}

private extension TOMLParseError.UnsupportedFeature {
    var message: String {
        switch self {
        case .nestedTable: "ネストしたテーブル [a.b]"
        case .arrayOfTables: "テーブルの配列 [[a]]"
        case .inlineTable: "インラインテーブル { ... }"
        case .dottedKey: "ドット区切りのキー a.b = ..."
        case .float: "浮動小数点数"
        case .dateTime: "日付・時刻"
        case .multilineString: "複数行文字列 \"\"\" / '''"
        case .nonDecimalInteger: "10 進数以外の整数 0x / 0o / 0b"
        case .nonStringArrayElement: "文字列以外の配列要素"
        }
    }
}
