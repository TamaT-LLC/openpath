/// TOML のテーブル（キーと値の対応）。ドキュメント全体（ルートテーブル）もこの型で表す。
public typealias TOMLTable = [String: TOMLValue]

/// `TOMLParser` がサポートする範囲の TOML の値。
/// ConfigStore が設定値へ変換するまでの中間表現として使う。
public enum TOMLValue: Sendable, Equatable {
    case string(String)
    case bool(Bool)
    /// 符号付き 10 進整数（64 bit）
    case integer(Int)
    /// 要素がすべて文字列の配列
    case stringArray([String])
    /// `[name]` で定義したテーブル。パーサは 1 階層までしか生成しないため、中にテーブルは入らない
    case table(TOMLTable)
}

public extension TOMLValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var integerValue: Int? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    var stringArrayValue: [String]? {
        guard case .stringArray(let value) = self else { return nil }
        return value
    }

    var tableValue: TOMLTable? {
        guard case .table(let value) = self else { return nil }
        return value
    }
}
