/// ファジーマッチのスコア規則（DSN-002 §5）
enum FuzzyScoring {
    static let noBonus = 0
    static let headBonus = 16
    static let separatorBonus = 12
    static let camelCaseBonus = 8
    static let consecutiveBonus = 6
    static let gapPenaltyPerCharacter = 3
    /// 区切り直後・CamelCase 境界に着地するギャップは頭文字入力の意図とみなし、軽く罰する。
    /// 1 文字 -3 のままだと `sda` で `system-doc-agent`（ギャップ 9 文字）が `sdasd` に勝てない。
    static let gapPenaltyPerCharacterBeforeBoundary = 1
    /// クエリが対象全体と一致した場合の加点。先頭一致同士（`fern` と `fernet-config`）の同点を解く
    static let exactMatchBonus = 16
    /// マッチした場合の下限。総合順位は frecency との乗算なので、0 以下だと順位が反転する
    static let minimumMatchScore = 1
    static let nameBonusPercent = 20
    static let percentBase = 100

    static let separators: Set<Character> = ["/", "-", "_", "."]

    /// 2 文字目以降の一致で得られる位置ボーナスの最大値。走査の打ち切り判定に使う。
    /// 先頭ボーナスは正規化後の位置 0 にしか付かず、2 文字目以降の一致は位置 1 以降になるため含めない
    static let maxInnerPositionalBonus = max(separatorBonus, camelCaseBonus)

    /// 元の文字列の各 Character に一致したときの位置ボーナス
    static func positionalBonuses(of characters: [Character]) -> [Int] {
        characters.indices.map { index in
            guard index > characters.startIndex else { return headBonus }
            let previous = characters[index - 1]
            let current = characters[index]
            if separators.contains(previous), !separators.contains(current) {
                return separatorBonus
            }
            if previous.isLowercase, current.isUppercase {
                return camelCaseBonus
            }
            return noBonus
        }
    }

    /// 直前の一致位置 `previous` から `index` に一致させたときの加点（位置ボーナス + 連続 or ギャップ）
    static func transitionGain(from previous: Int, to index: Int, bonus: Int) -> Int {
        let gapLength = index - previous - 1
        if gapLength == 0 {
            return bonus + consecutiveBonus
        }
        let landsOnBoundary = bonus > noBonus
        let penaltyPerCharacter = landsOnBoundary ? gapPenaltyPerCharacterBeforeBoundary : gapPenaltyPerCharacter
        return bonus - gapLength * penaltyPerCharacter
    }

    /// 直前の一致位置から `gapLength`（1 以上）文字空けた位置で得られる加点の上限
    static func maxGain(atGapOf gapLength: Int) -> Int {
        maxInnerPositionalBonus - gapLength * gapPenaltyPerCharacterBeforeBoundary
    }

    static func applyingNameBonus(to score: Int) -> Int {
        score + score * nameBonusPercent / percentBase
    }
}
