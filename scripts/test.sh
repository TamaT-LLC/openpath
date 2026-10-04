#!/usr/bin/env bash
# `swift test` のラッパー。引数はそのまま `swift test` に渡す。
#
# Command Line Tools のみの環境では、Swift Testing を動かすために次の 3 点を補う必要がある。
# Xcode 使用時は SwiftPM が自動で解決するので何もしない。
#
# 1. SwiftPM が CLT 同梱の Testing.framework をフレームワーク検索パス (-F) として渡さず、
#    `no such module 'Testing'` で失敗する。テストターゲット側（Package.swift）で補っても
#    SwiftPM が生成するテストランナーには効かず、テストが 0 件のまま成功扱いになるため、
#    ビルド全体に -F と rpath を渡す。
# 2. CLT 同梱の _Testing_Foundation.framework にモジュール定義が含まれておらず、
#    Foundation と Testing を同じファイルで import すると `no such module '_Testing_Foundation'`
#    で失敗する。このオーバーレイは添付ファイル等の補助機能のみのため、cross-import overlay を無効化する。
# 3. Swift 6.3 以降の CLT では、Testing.framework が `@rpath/lib_TestingInterop.dylib` に依存する。
#    この dylib は Frameworks ではなく usr/lib にあるため、rpath に足さないと、テストバンドルの読み込みで
#    `Library not loaded` となり、テストが 1 件も実行されないまま異常終了する。
#    Swift 6.2 以前の CLT にはこの dylib が無いので、存在するときだけ rpath を足す。
#
# OPENPATH_TEST_CLT_DIR: CLT の場所を差し替える。引数の組み立てを scripts/release_ci_test.py で確かめるための
#   仕組みで、通常は設定しない。
set -euo pipefail

readonly CLT_DIR="${OPENPATH_TEST_CLT_DIR:-/Library/Developer/CommandLineTools}"
readonly CLT_FRAMEWORKS_DIR="${CLT_DIR}/Library/Developer/Frameworks"
readonly CLT_USR_LIB_DIR="${CLT_DIR}/Library/Developer/usr/lib"
readonly TESTING_INTEROP_DYLIB="${CLT_USR_LIB_DIR}/lib_TestingInterop.dylib"

developer_dir="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"

extra_args=()
if [[ "${developer_dir}" == "${CLT_DIR}"* && -d "${CLT_FRAMEWORKS_DIR}/Testing.framework" ]]; then
  extra_args=(
    -Xswiftc -F -Xswiftc "${CLT_FRAMEWORKS_DIR}"
    -Xlinker -rpath -Xlinker "${CLT_FRAMEWORKS_DIR}"
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays
  )
  if [[ -f "${TESTING_INTEROP_DYLIB}" ]]; then
    extra_args+=(-Xlinker -rpath -Xlinker "${CLT_USR_LIB_DIR}")
  fi
fi

cd "$(dirname "$0")/.."
# macOS 標準の bash 3.2 では空配列の展開が set -u でエラーになるため、要素がある場合のみ展開する
exec swift test ${extra_args[@]+"${extra_args[@]}"} "$@"
