import Testing

import OpenPathCore

/// パースエラーのテストケース。入力と、期待する位置・種別の組。
struct TOMLErrorCase: Sendable, CustomTestStringConvertible {
    let source: String
    let expected: TOMLParseError

    init(_ source: String, line: Int, column: Int, _ kind: TOMLParseError.Kind) {
        self.source = source
        self.expected = TOMLParseError(line: line, column: column, kind: kind)
    }

    /// テスト結果に入力が読める形で出るよう、制御文字をエスケープして表示する
    var testDescription: String { source.debugDescription }

    /// 入力をパースし、期待どおりのエラーになることを検証する
    func verify(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(throws: expected, sourceLocation: sourceLocation) {
            try TOMLParser.parse(source)
        }
    }
}
