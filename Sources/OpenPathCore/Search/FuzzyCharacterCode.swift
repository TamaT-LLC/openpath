import Foundation
import os

/// 正規化後の 1 文字（Character）を表す整数コード。
///
/// 候補インデックスは候補数 × 文字数ぶんの文字を常駐させるため、1 文字 16 バイトの Character ではなく
/// このコードで持つ（DSN-002 §8 の常駐メモリ）。比較も整数の比較になる。
/// ASCII はスカラー値をそのまま使い、それ以外はプロセス内で初出順に採番する。
/// 同じ Character（正準等価を含む）には常に同じコードが付くため、コードの一致は Character の一致と等しい。
struct FuzzyCharacterCode: Hashable, Sendable {
    /// `FuzzyTargetElement` に詰めるときのビット幅。採番できる上限を決める
    static let bitWidth: UInt32 = 24
    private static let limit: UInt32 = 1 << bitWidth

    private static let asciiLimit: UInt32 = 0x80
    private static let table = OSAllocatedUnfairLock(initialState: CodeTable(nextCode: asciiLimit))

    let rawValue: UInt32

    /// 各文字のコード。未採番の文字には新しいコードを付ける。
    ///
    /// クエリも対象と同じく採番する。クエリを先に前処理してから対象を前処理する使い方
    /// （`FuzzyMatcher.score(query:in:)`）でも、同じ文字が同じコードになるようにするため。
    static func codes(of characters: [Character]) -> [FuzzyCharacterCode] {
        // 候補の大半は ASCII のみで、表（ロック）を引かずに済む
        let asciiCodes = characters.map(asciiCode(of:))
        if !asciiCodes.contains(nil) {
            return asciiCodes.compactMap { $0.map(FuzzyCharacterCode.init(rawValue:)) }
        }
        return table.withLock { state in
            zip(characters, asciiCodes).map { character, asciiCode in
                FuzzyCharacterCode(rawValue: asciiCode ?? state.code(of: character))
            }
        }
    }

    private static func asciiCode(of character: Character) -> UInt32? {
        let scalars = character.unicodeScalars
        guard let scalar = scalars.first, scalars.dropFirst().isEmpty, scalar.value < asciiLimit else {
            return nil
        }
        return scalar.value
    }

    /// ASCII 以外の文字とコードの対応。表の大きさは候補とクエリに現れた文字の種類数（通常は数千）で頭打ちになる。
    private struct CodeTable: Sendable {
        /// Character を鍵にするため、NFC と NFD のように正準等価な文字は同じ鍵になる
        var codes: [Character: UInt32] = [:]
        var nextCode: UInt32

        mutating func code(of character: Character) -> UInt32 {
            if let code = codes[character] {
                return code
            }
            let code = Self.asciiEquivalent(of: character) ?? issueCode()
            codes[character] = code
            return code
        }

        /// ASCII と正準等価な非 ASCII の文字（U+037E GREEK QUESTION MARK と `;` など）は ASCII と同じコードにする。
        /// 既定の正規化（NFC 合成済み）では現れないが、他の正規化でも Character の一致と揃えるため
        private static func asciiEquivalent(of character: Character) -> UInt32? {
            let composed = String(character).precomposedStringWithCanonicalMapping
            guard composed.count == 1, let composedCharacter = composed.first else { return nil }
            return FuzzyCharacterCode.asciiCode(of: composedCharacter)
        }

        private mutating func issueCode() -> UInt32 {
            // 採番の上限（約 1,600 万種）には現実のパスでは届かないため、到達はプログラムの誤りとして扱う
            precondition(nextCode < FuzzyCharacterCode.limit, "FuzzyCharacterCode を採番し尽くした")
            defer { nextCode += 1 }
            return nextCode
        }
    }
}

/// 前処理済みの対象の 1 文字。文字コードと位置ボーナスを 4 バイトに詰める。
struct FuzzyTargetElement: Sendable {
    private static let codeMask: UInt32 = (1 << FuzzyCharacterCode.bitWidth) - 1
    private let rawValue: UInt32

    /// - Parameter bonus: 0...255。`FuzzyScoring` のボーナスはこの範囲に収まる
    init(code: FuzzyCharacterCode, bonus: Int) {
        rawValue = UInt32(UInt8(bonus)) << FuzzyCharacterCode.bitWidth | code.rawValue
    }

    var code: FuzzyCharacterCode {
        FuzzyCharacterCode(rawValue: rawValue & Self.codeMask)
    }

    /// この文字に一致したときの位置ボーナス
    var bonus: Int {
        Int(rawValue >> FuzzyCharacterCode.bitWidth)
    }
}
