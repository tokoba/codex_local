# config/src/diagnostics.rs コード解説

## 0. ざっくり一言

- TOML 形式の設定ファイルの **パース／型付きデシリアライズエラーをファイル中の位置にひも付けて、人間が読みやすいエラーメッセージとして整形する** モジュールです（`config/src/diagnostics.rs`）。  
- 複数レイヤー（system/user/project など）から構成される設定スタックの中で、**最初に発生した具体的なファイル単位のエラー**を検出する非同期ヘルパも提供します。

（根拠: ファイル先頭コメントと公開 API 群 `ConfigError`, `config_error_from_toml`, `config_error_from_typed_toml`, `first_layer_config_error`, `format_config_error` など  
`config/src/diagnostics.rs:L1-2, L35-40, L97-107, L109-135, L137-152, L219-252`）

---

## 1. このモジュールの役割

### 1.1 概要

このモジュールは主に次の問題を解決します。

- TOML の構文エラー／型エラーを、**ファイルパス＋行・列範囲** にマッピングする（`ConfigError` と関連関数）。  
- Serde 経由で型付きデシリアライズした際に得られる **フィールドパス (`serde_path_to_error::Path`) から TOML 内のスパン（byte range）を逆引きする**。  
- 設定レイヤースタック（`ConfigLayerStack`）の各ファイルを走査し、**最初に失敗するレイヤーの `ConfigError` を取得する非同期関数**を提供する。  
- 上記エラー情報を、ソースコード風の **一行メッセージ＋該当行＋キャレット（^）によるハイライト** 形式の文字列に整形する。

（根拠: `ConfigError`, `ConfigLoadError`, `config_error_from_toml`, `config_error_from_typed_toml`, `first_layer_config_error_for_entries`, `span_for_config_path`, `format_config_error`  
`config/src/diagnostics.rs:L35-40, L52-87, L97-107, L109-135, L161-191, L317-347, L219-252`）

### 1.2 アーキテクチャ内での位置づけ

このモジュールは「設定読み込み／検証」処理の中で、**エラーをユーザーフレンドリにする責務**を担います。外部との主な依存関係は以下です。

```mermaid
graph TD
    A[diagnostics.rs<br>設定エラーの位置特定と整形]:::mod
    B[ConfigLayerStack<br>(外部クレート内)]:::ext
    C[ConfigLayerEntry<br>(外部クレート内)]:::ext
    D[ConfigLayerSource<br>レイヤー種別]:::ext
    E[tokio::fs::read_to_string<br>非同期ファイル読み込み]:::ext
    F[serde / toml<br>デシリアライズとエラー]:::ext
    G[serde_path_to_error<br>型パス付きエラー]:::ext
    H[toml_edit<br>TOML AST と span]:::ext
    I[AbsolutePathBufGuard<br>(パス関連ガード)]:::ext

    B -->|get_layers| A
    C --> A
    D --> A
    A -->|read_to_string| E
    A -->|DeserializeOwned, toml::de::Error| F
    A -->|Path, Segment| G
    A -->|Document, Item など| H
    A -->|new(parent)| I

    classDef mod fill:#eef,stroke:#333,stroke-width:1px;
    classDef ext fill:#fefefe,stroke:#666,stroke-width:1px,stroke-dasharray: 3 3;
```

- `ConfigLayerStack`, `ConfigLayerEntry`, `ConfigLayerSource`, `AbsolutePathBufGuard` の実装は **このチャンクには現れません**。名前と使用方法から「設定レイヤー管理」「パスガード」に関する型であると推測できますが、詳細な振る舞いは不明です。

### 1.3 設計上のポイント

- **責務の分離**
  - エラー内容・位置を保持する型 (`TextPosition`, `TextRange`, `ConfigError`) と、それを IO エラーにラップする型 (`ConfigLoadError`) を分離しています（`L22-40, L52-56`）。
  - TOML パース→位置計算→文字列表現生成を、それぞれ別関数で担当しています（`config_error_from_toml`, `text_range_from_span`, `position_for_offset`, `format_config_error` など `L97-107, L208-217, L262-291, L219-252`）。
- **状態レス設計**
  - グローバル／内部状態は持たず、すべての関数は入力引数と外部クレートにのみ依存します。  
    （例: `first_layer_config_error_for_entries` は `layers` とファイルシステムからの内容にだけ依存 `L161-191`）
- **エラーハンドリング方針**
  - TOML パースエラーは `ConfigError` で表現しつつ、`ConfigLoadError` でラップして `io::Error` としても扱えるようにしています（`L52-87, L89-95`）。
  - 設定ファイルが見つからない (`io::ErrorKind::NotFound`) 場合は **スキップして次のレイヤーを探す** というポリシーです（`L172-175`）。
  - それ以外の IO エラーは `tracing::debug!` でログに残しつつスキップします（`L175-178`）。
- **安全性への配慮**
  - 文字位置計算では、バイトインデックスが範囲外となる可能性に備えて `saturating_sub` と `min` を用い、UTF-8 の不正な境界に対しても `from_utf8` エラーを捕捉してフォールバックしています（`L262-285`）。
  - 外部ライブラリのパースエラーは `ok()?` や `Option` を使って安全に無視／フォールバックしています（`L307-309, L332-336`）。

---

## 2. 主要な機能一覧

このモジュールが提供する主な機能は次のとおりです。

- `ConfigError` 型: 設定ファイルのパス・テキスト範囲・メッセージをまとめたエラー表現（`L35-40`）。
- `ConfigLoadError` 型: `ConfigError` と元の `toml::de::Error` を保持し、`io::Error` 経由で伝播できるラッパー（`L52-87`）。
- `io_error_from_config_error`: `ConfigError` を `io::Error` に変換する（`L89-95`）。
- `config_error_from_toml`: TOML 構文エラー (`toml::de::Error`) から `ConfigError` を生成する（`L97-107`）。
- `config_error_from_typed_toml`: 型 `T` へのデシリアライズエラーから、可能ならフィールドパスに基づいた位置情報つき `ConfigError` を生成する（`L109-135`）。
- `first_layer_config_error`: `ConfigLayerStack` 全体の中で、最初に起きるレイヤーごとの型付き TOML エラーを見つける非同期関数（`L137-152`）。
- `first_layer_config_error_from_entries`: 任意の `ConfigLayerEntry` スライスから同様の探索を行う非同期関数（`L154-159`）。
- `format_config_error`: `ConfigError` とファイル内容から、1 行メッセージ＋エラー行＋キャレットによるハイライトを含む文字列を生成する（`L219-252`）。
- `format_config_error_with_source`: `ConfigError` の `path` から実際のファイル内容を読み込み、`format_config_error` で整形する（`L255-259`）。
- TOML AST（`toml_edit`）を使った path→span 逆引き:
  - `span_for_config_path`, `span_for_path`, `node_for_path`, `map_child`, `seq_child` など（`L307-396`）。
- 特殊ケース `features` テーブル向けの span 解決:
  - `is_features_table_path`, `span_for_features_value`（`L326-347`）。

---

## 3. 公開 API と詳細解説

### 3.1 型一覧（構造体・列挙体など）

| 名前 | 種別 | 公開 | 役割 / 用途 | 定義位置 |
|------|------|------|-------------|----------|
| `TextPosition` | 構造体 | 公開 | テキスト中の 1 行・1 列始まりの位置を表す（行・列は 1 始まり） | `config/src/diagnostics.rs:L22-26` |
| `TextRange` | 構造体 | 公開 | 開始・終了の `TextPosition` をまとめたテキスト範囲 | `config/src/diagnostics.rs:L29-33` |
| `ConfigError` | 構造体 | 公開 | 設定ファイルのパス・エラーメッセージ・文字範囲を保持するエラー情報 | `config/src/diagnostics.rs:L35-40` |
| `ConfigLoadError` | 構造体 | 公開 | `ConfigError` と元の `toml::de::Error` をまとめるエラー型。`Display` と `Error` を実装 | `config/src/diagnostics.rs:L52-56, L68-87` |
| `TomlNode<'a>` | 列挙体 | 非公開 | TOML AST のノード（`Item`, `Table`, `Value`）をまとめて扱うための内部ヘルパ型 | `config/src/diagnostics.rs:L301-305` |

`ConfigError` には `pub fn new` があり、`ConfigLoadError` には `pub fn new`, `pub fn config_error` が定義されています（`L42-49, L58-65`）。

### 3.2 関数詳細（最大 7 件）

以下では特に重要と思われる関数を詳しく解説します。

---

#### `ConfigError::new(path: PathBuf, range: TextRange, message: impl Into<String>) -> ConfigError`

**概要**

- 単純なコンストラクタです。設定ファイルパス・エラー範囲・メッセージから `ConfigError` を生成します（`L42-49`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `path` | `PathBuf` | エラーが発生した設定ファイルの絶対/相対パス |
| `range` | `TextRange` | エラー位置を表すテキスト範囲 |
| `message` | `impl Into<String>` | エラーメッセージ（`String` へ変換可能な型） |

**戻り値**

- `ConfigError`: 引数をそのままフィールドに格納した新しいエラーオブジェクト。

**内部処理の流れ**

1. `message.into()` を呼び出して `String` に変換します（`L47-48`）。
2. フィールド `path`, `range`, `message` に格納して `Self` を返します（`L44-48`）。

**Examples（使用例）**

```rust
use std::path::PathBuf;
use crate::config::diagnostics::{ConfigError, TextPosition, TextRange};

fn make_example_error() -> ConfigError {
    let path = PathBuf::from("config.toml");                           // エラー対象のファイル
    let range = TextRange {
        start: TextPosition { line: 3, column: 5 },                    // 3行目5列から
        end: TextPosition { line: 3, column: 10 },                     // 3行目10列まで
    };
    ConfigError::new(path, range, "無効な値です")                      // メッセージ付きで生成
}
```

**Errors / Panics**

- パニックやエラーを起こす要素はありません。`Into<String>` 実装がパニックすることも通常はありません。

**Edge cases（エッジケース）**

- `message` が空文字でも問題なく生成されます。
- `range.start` と `range.end` の整合性（開始 ≤ 終了）は呼び出し側が保証する必要があります（この関数内ではチェックしません）。

**使用上の注意点**

- 行・列は 1 始まりである前提で後続処理（`format_config_error` など）が動くため、その前提を守る必要があります。  

---

#### `config_error_from_toml(path: impl AsRef<Path>, contents: &str, err: toml::de::Error) -> ConfigError`

**概要**

- TOML の構文解析エラー (`toml::de::Error`) から、可能ならそのエラー位置を計算して `ConfigError` を生成します（`L97-107`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `path` | `impl AsRef<Path>` | エラーが発生した設定ファイルパス |
| `contents` | `&str` | ファイルの中身（TOML 文字列） |
| `err` | `toml::de::Error` | TOML デシリアライザからの構文エラー |

**戻り値**

- `ConfigError`: エラーメッセージと、`err.span()` またはデフォルト位置 `(1,1)` を持つエラー。

**内部処理の流れ**

1. `err.span()` でバイト範囲 (`Range<usize>`) を取得します（取得できない場合は `None`）（`L102-103`）。
2. 取得できた場合 `text_range_from_span(contents, span)` で `TextRange` へ変換します（`L104`）。
3. 取得できない場合は `default_range()` を用いて `(1,1)-(1,1)` を範囲とします（`L105`）。
4. `ConfigError::new(path.as_ref().to_path_buf(), range, err.message())` を返します（`L106`）。

**Examples（使用例）**

```rust
use std::path::Path;
use crate::config::diagnostics::{config_error_from_toml};

fn handle_parse_error(path: &Path, contents: &str, err: toml::de::Error) {
    let config_error = config_error_from_toml(path, contents, err);  // ConfigError に変換
    eprintln!("{}", config_error.message);                           // メッセージを表示するなど
}
```

**Errors / Panics**

- `text_range_from_span` → `position_for_offset` 内で UTF-8 文字列処理をしていますが、内部で `from_utf8` のエラーを捕捉してフォールバックしているためパニックは発生しません（`L282-285`）。
- `path.as_ref().to_path_buf()` は通常パニックしません。

**Edge cases**

- `err.span()` が `None` の場合、位置は常に 1 行 1 列に設定されます（`L102-105`）。
- `contents` が空文字列の場合でも `position_for_offset` が `(1,1)` を返すため、安全です（`L262-266`）。

**使用上の注意点**

- `err` が構文エラーではなく他の種類のエラー（例えば内部エラー）でも `message()` と `span()` が定義されていれば動作します。
- `contents` は **実際に `path` が指すファイル内容と一致している必要がある** ことに注意する必要があります。そうでない場合、位置情報がずれる可能性があります。

---

#### `config_error_from_typed_toml<T: DeserializeOwned>(path: impl AsRef<Path>, contents: &str) -> Option<ConfigError>`

**概要**

- 型 `T` への TOML デシリアライズを試み、**型検証に失敗した場合に `ConfigError` を返す** 関数です（`L109-135`）。
- `serde_path_to_error` を利用し、エラーが発生したフィールドパスから TOML 内の適切なスパンを推定します（`L118-127, L317-323`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `path` | `impl AsRef<Path>` | 設定ファイルのパス |
| `contents` | `&str` | TOML 文字列全体 |

**戻り値**

- `Option<ConfigError>`:
  - `None`: デシリアライズに成功した場合。
  - `Some(ConfigError)`: デシリアライズまたは構文エラーが発生した場合。

**内部処理の流れ**

1. `toml::de::Deserializer::parse(contents)` を呼び出し、構文レベルの TOML デシリアライザを生成（`L113-116`）。
   - ここで構文エラーが出た場合は `config_error_from_toml` で `ConfigError` を生成し `Some(...)` を返して終了（`L115`）。
2. 成功した場合、`serde_path_to_error::deserialize` で型 `T` へのデシリアライズを行い、フィールドパスつきの結果を受け取る（`L118`）。
3. `match result` で成功/失敗を分岐（`L119-134`）。
   - `Ok(_)` → `None` を返す（`L120`）。
   - `Err(err)` の場合:
     1. `let path_hint = err.path().clone();` でフィールドパスを取得（`L122`）。
     2. `let toml_err: toml::de::Error = err.into_inner();` で元の TOML エラーを取得（`L123`）。
     3. `span_for_config_path(contents, &path_hint)` でフィールドパスから TOML スパンを推定（`L124`）。
     4. それが `None` の場合は `toml_err.span()` にフォールバック（`L125`）。
     5. さらにそれが `None` の場合は `default_range()` を使用（`L126-127`）。
     6. 最終的な範囲を `text_range_from_span` で `TextRange` に変換し、`ConfigError::new` を返す（`L124-127, L128-132`）。

**Examples（使用例）**

```rust
use serde::Deserialize;
use std::path::Path;
use crate::config::diagnostics::config_error_from_typed_toml;

#[derive(Deserialize)]
struct AppConfig {
    port: u16,                     // 例: 正の整数を期待
}

fn validate_config(path: &Path, contents: &str) {
    if let Some(err) = config_error_from_typed_toml::<AppConfig>(path, contents) {
        // 型検証エラーが発生した場合
        eprintln!("設定エラー: {}", err.message);
    } else {
        // パース＋型検証が成功
        println!("設定は有効です");
    }
}
```

**Errors / Panics**

- 構文エラーや型エラーは `ConfigError` として戻り値で表現され、**パニックは発生しません**。
- 内部で使用している `toml_edit::Document` のパースに失敗した場合は `ok()?` で `None` を返し、最終的には `toml_err.span()` または `default_range()` にフォールバックします（`span_for_path`, `span_for_config_path` `L307-309, L317-323`）。

**Edge cases**

- `T` に対して TOML 構造が完全に一致しない場合（フィールド不足・型不一致など）、`path_hint` によって **「どのフィールドで失敗したか」** がわかり、そのフィールドにできるだけ近い TOML スパンが計算されます（`L122-127, L349-375`）。
- フィールドパスから TOML スパンを求められない場合（例えば `features` テーブルの特殊ケースや、複雑なマッピングがある場合）は、元の `toml_err.span()` か `(1,1)` にフォールバックします（`L124-127`）。
- `contents` と実際のファイル内容が不一致な場合、計算される位置は実ファイルとずれる可能性があります。

**使用上の注意点**

- `T` は `DeserializeOwned` を要求されます。ライフタイムを引き回さない素直な設定構造体を想定した設計です（`L109`）。
- この関数は **エラーを返すのではなく `Option` を返す** ため、「成功」か「何らかのエラーがあったか」の 2 値判定専用です。エラー内容の詳細が必要な場合は `ConfigError.message` を参照します。
- `features` テーブルについては `span_for_config_path` で特別扱いがあり、`features` 自体のスパンではなく、最初の非 boolean 値のスパンを返そうとします（`L317-323, L332-347`）。

---

#### `first_layer_config_error<T: DeserializeOwned>(layers: &ConfigLayerStack, config_toml_file: &str) -> Option<ConfigError>` （非同期）

**概要**

- 設定レイヤースタック（例: system → user → project）の各レイヤーを順に調べ、**最初に型付き TOML 検証エラーが発生するレイヤーの `ConfigError` を返す** 非同期関数です（`L137-152`）。
- 「マージされた設定全体のエラー」ではなく、「具体的な設定ファイル」の位置をユーザーに示すことを目的としています（コメント `L141-143`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `layers` | `&ConfigLayerStack` | 設定レイヤーのスタック（外部定義。`get_layers` メソッドを持つ） |
| `config_toml_file` | `&str` | Project レイヤー用に `dot_codex_folder` に結合する TOML ファイル名 |

**戻り値**

- `Option<ConfigError>`:
  - `Some(ConfigError)`: どこかのレイヤーで `config_error_from_typed_toml` が `Some` を返した場合。
  - `None`: すべてのレイヤーで型付き検証が成功するか、ファイルが見つからなかった／読み込み失敗した場合。

**内部処理の流れ**

1. `layers.get_layers(ConfigLayerStackOrdering::LowestPrecedenceFirst, false)` を呼び出して、レイヤーのイテレータを取得（`L145-148`）。
2. 内部ヘルパ `first_layer_config_error_for_entries` を呼び出し、結果をそのまま返します（`L144-151, L161-191`）。

`first_layer_config_error_for_entries` の具体的な処理（`L161-191`）:

1. `for layer in layers` で各 `ConfigLayerEntry` を走査。
2. `config_path_for_layer(layer, config_toml_file)` でレイヤー種別ごとのファイルパスを取得。`None` のレイヤーはスキップ（`L168-171, L194-205`）。
3. `tokio::fs::read_to_string(&path).await` でファイル内容を読み込み（`L172-179`）。
   - `NotFound` の場合はスキップ。
   - その他の IO エラーは `tracing::debug!` でログを残してスキップ。
4. `path.parent()`（親ディレクトリ）が取れない場合はデバッグログを出してスキップ（`L181-184`）。
5. `AbsolutePathBufGuard::new(parent)` を生成し `_guard` として保持（スコープ終了時に drop）（`L185`）。
6. `config_error_from_typed_toml::<T>(&path, &contents)` を呼び、`Some(error)` なら即座に `Some(error)` を返して終了（`L186-188`）。
7. すべてのレイヤーで `Some` が得られなかった場合は `None` を返す（`L191`）。

**Examples（使用例: 疑似コード）**

※ `ConfigLayerStack` や `ConfigLayerEntry` の定義はこのチャンクにないため、概念的な例になります。

```rust
use serde::Deserialize;
use crate::config::diagnostics::first_layer_config_error;

// 設定構造体
#[derive(Deserialize)]
struct AppConfig {
    // ...
}

async fn validate_layers(layers: &ConfigLayerStack) {
    if let Some(err) = first_layer_config_error::<AppConfig>(layers, "config.toml").await {
        // 最初に失敗したレイヤーの ConfigError
        eprintln!("{}", crate::config::diagnostics::format_config_error_with_source(&err));
    } else {
        println!("すべてのレイヤーで設定は有効です");
    }
}
```

**Errors / Panics**

- IO エラーは **呼び出し元に返さず、内部でログしてスキップ** します（`L172-179`）。
  - ファイルが存在しない場合: スキップ。
  - 読み込み権限がない／I/O 障害など: `tracing::debug!` ログに残してスキップ。
- `AbsolutePathBufGuard::new(parent)` の実装が不明なため、その内部でパニックする可能性についてはこのチャンクからは分かりません（`L185`）。
- それ以外に明示的な `unwrap` や `expect` は使用されていません。

**Edge cases**

- すべてのレイヤーに対応するファイルが存在しない場合は `None` が返されます。
- `ConfigLayerSource::Mdm`, `SessionFlags`, `LegacyManagedConfigTomlFromMdm` のレイヤーは `config_path_for_layer` で `None` を返し、**そもそもファイルチェックの対象外**です（`L194-205`）。
- `path.parent()` が `None`（例: ルートディレクトリ直下のファイルや相対パスの特殊ケース）の場合もスキップされます（`L181-184`）。

**使用上の注意点**

- 非同期関数なので、`tokio` などの非同期ランタイム上で `.await` する必要があります（`tokio::fs::read_to_string` を使用 `L172`）。
- 「一番最初に検出された型エラーだけ」が返るため、複数レイヤーや複数箇所のエラーを一覧で報告する用途には向きません。
- `config_toml_file` は Project レイヤーで `dot_codex_folder.join(config_toml_file)` に使用されます（`L198-200`）。この文字列にディレクトリトラバーサル要素（`../` など）を含めるかどうかは呼び出し側のポリシーに依存します。このモジュールでは追加の検証はしていません。

---

#### `io_error_from_config_error(kind: io::ErrorKind, error: ConfigError, source: Option<toml::de::Error>) -> io::Error`

**概要**

- `ConfigError` と、任意の元 `toml::de::Error` を `ConfigLoadError` でラップし、それを `io::Error` として返すためのヘルパーです（`L89-95`）。
- 「設定読み込み失敗」を `io::Error` として扱いたい呼び出し元向けのユーティリティと解釈できます。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `kind` | `io::ErrorKind` | 呼び出し側が指定する I/O エラーの種別 |
| `error` | `ConfigError` | ファイルパス・範囲・メッセージを含むエラー |
| `source` | `Option<toml::de::Error>` | 元の TOML デシリアライズエラー（あれば） |

**戻り値**

- `io::Error`: `ConfigLoadError` を内部エラーとして持つ `io::Error` インスタンス。

**内部処理の流れ**

1. `ConfigLoadError::new(error, source)` でラッパーエラーを生成（`L94`）。
2. `io::Error::new(kind, ConfigLoadError)` で `io::Error` を生成して返す（`L94`）。

**Errors / Panics**

- パニックは起こしません。`io::Error::new` は通常、どの `Error` 型に対してもパニックしません。

**使用上の注意点**

- `ConfigLoadError` は `std::error::Error` を実装しているため、`io_error_from_config_error` から得られた `io::Error` の `source()` をたどることで、元の `toml::de::Error` にアクセスできます（`L81-86`）。
- `kind` の値は呼び出し側のポリシーに依存します。例: `io::ErrorKind::InvalidData` など。

---

#### `format_config_error(error: &ConfigError, contents: &str) -> String`

**概要**

- `ConfigError` とファイル内容から、以下の形式のエラー表示を生成する関数です（`L219-252`）。
  - `path:line:column: message`
  - エラー行
  - キャレット (`^`) によるハイライト

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `error` | `&ConfigError` | エラー情報（パス・範囲・メッセージ） |
| `contents` | `&str` | エラー行を抽出するためのファイル内容 |

**戻り値**

- `String`: 改行を含むエラーメッセージ全体。

例:

```text
config.toml:3:5: 無効な値です
  |
3 | key = "value"
  |     ^^^
```

**内部処理の流れ**

1. 冒頭行 `"{path}:{line}:{column}: {message}\n"` を書き込み（`L221-229`）。
2. `line_index = start.line.saturating_sub(1)` で 0 ベース行インデックスを取得（`L231`）。
3. `contents.lines().nth(line_index)` で該当行文字列を取得。見つからなければここまでの出力を返して終了（`L232-235`）。
4. 行番号の桁数を `gutter` として計算し、`"   |"` のようなガター行と、`"3 | {line}"` を出力（`L237-240`）。
5. ハイライト幅 `highlight_len` を計算（開始・終了が同じ行なら列差+1、異なる場合は 1）（`L242-247`）。
6. `spaces = " ".repeat(start.column.saturating_sub(1))` と `carets = "^".repeat(highlight_len.max(1))` でキャレット行を作成し出力（`L249-251`）。
7. 末尾の改行を `trim_end()` で削除して返す（`L252`）。

**Examples（使用例）**

```rust
use crate::config::diagnostics::{ConfigError, TextPosition, TextRange, format_config_error};

fn print_error() {
    let contents = r#"
[server]
port = "not a number"
"#;
    let error = ConfigError::new(
        "config.toml".into(),
        TextRange {
            start: TextPosition { line: 3, column: 8 },
            end: TextPosition { line: 3, column: 20 },
        },
        "port は整数である必要があります",
    );

    let msg = format_config_error(&error, contents);
    println!("{msg}");
}
```

**Errors / Panics**

- `contents.lines().nth(line_index)` が `None` の場合は、ヘッダ行だけ出力して安全に終了します（`L232-235`）。
- `repeat`/`saturating_sub` を使っているため、負の値などによるパニックはありません。

**Edge cases**

- `error.range.start.line` が `contents` の行数より大きい場合: 2 行目以降（ガターやキャレット）は出力されません。
- `start.column` が行の長さよりも大きい場合でも、`spaces` が長くなるだけでパニックせず、キャレットは行末より右側に表示されます。
- `error.range.end` が `start` より前の位置の場合でも、`highlight_len.max(1)` によって少なくとも 1 文字分のキャレットが表示されます（`L242-247, L250`）。

**使用上の注意点**

- `contents` は `error.path` が指すファイル内容と対応している必要があります。`format_config_error_with_source` はこれを自動で行います（`L255-259`）。
- 出力はデバッグ用途・ユーザー表示用としてそのまま使用できますが、機械可読なフォーマットが必要な場合は `ConfigError` フィールドを直接利用する方が適しています。

---

#### `position_for_offset(contents: &str, index: usize) -> TextPosition`

**概要**

- ファイル内容 `contents` とバイトオフセット `index` から、**1 始まりの行・列番号 (`TextPosition`) を計算する**内部関数です（`L262-291`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `contents` | `&str` | テキスト全体 |
| `index` | `usize` | バイトオフセット（0 始まり） |

**戻り値**

- `TextPosition`: 1 始まりの行・列位置。

**内部処理の流れ（UTF-8 安全性を考慮）**

1. `bytes = contents.as_bytes()` を取得。空なら `(1,1)` を返す（`L262-266`）。
2. `safe_index = index.min(bytes.len().saturating_sub(1))` で、範囲外アクセスを防ぐ（`L268`）。
3. `column_offset = index.saturating_sub(safe_index)` とし、指定 index が末尾より大きい場合の「超過分」を保持（`L269`）。
4. `line_start` を、`safe_index` より前の最後の `'\n'` の位置＋1とする（`L272-276`）。
5. `line` を `bytes[..line_start]` 中の改行数として計算（`L277-280`）。
6. `bytes[line_start..=safe_index]` を UTF-8 として文字列化し、`chars().count().saturating_sub(1)` で列の 0 始まり位置を計算。`from_utf8` が失敗した場合はバイト数の差を使用（`L282-284`）。
7. 上記列に `column_offset` を加え、最終的な列番号（1 始まり）を計算（`L285, L288-289`）。
8. 行番号は `line + 1` を使用（`L287-289`）。

**Errors / Panics**

- インデックスが範囲外でも `min` と `saturating_sub` によりパニックしません。
- UTF-8 の途中バイトを指している場合も、`from_utf8` エラーを捕捉してフォールバックしているためパニックしません（`L282-285`）。

**Edge cases**

- `index == 0` の場合: 行=1, 列=1。
- `index` が `contents.len()` より大きい場合: 末尾の文字位置から列だけ増えた扱いになります（`column_offset` の加算 `L269, L285`）。
  - これはスパン終端などで `end` が 1 文字先を指す場合に対する緩やかな補正と考えられます（設計意図の詳細はコードからは断定できません）。

**使用上の注意点**

- 公開関数ではありませんが、`text_range_from_span` 経由で `ConfigError` の範囲計算に使われるため、文字列が UTF-8 である前提です。

---

### 3.3 その他の関数（インベントリー）

主要な公開関数以外のヘルパーを一覧で示します。

| 関数名 / メソッド | 公開 | 役割（1 行） | 定義位置 |
|-------------------|------|--------------|----------|
| `ConfigLoadError::new(error, source)` | 公開 | `ConfigError` と元 `toml::de::Error` をまとめたラッパーを構築 | `config/src/diagnostics.rs:L58-61` |
| `ConfigLoadError::config_error(&self)` | 公開 | 内部に保持する `ConfigError` への参照を返す | `config/src/diagnostics.rs:L63-65` |
| `impl Display for ConfigLoadError::fmt` | - | `path:line:column: message` 形式の文字列表現を実装 | `config/src/diagnostics.rs:L68-78` |
| `impl Error for ConfigLoadError::source` | - | 元の `toml::de::Error` を `source()` として返す | `config/src/diagnostics.rs:L81-86` |
| `first_layer_config_error_from_entries<T>` | 公開・非同期 | 任意の `&[ConfigLayerEntry]` から最初の `ConfigError` を探索 | `config/src/diagnostics.rs:L154-159` |
| `first_layer_config_error_for_entries<'a, T, I>` | 非公開・非同期 | 実際のレイヤー反復ロジック（ファイル読み込み＋ `config_error_from_typed_toml`） | `config/src/diagnostics.rs:L161-191` |
| `config_path_for_layer(layer, config_toml_file)` | 非公開 | レイヤー種別 (`ConfigLayerSource`) から設定ファイルの `PathBuf` を構築 | `config/src/diagnostics.rs:L194-205` |
| `text_range_from_span(contents, span)` | 非公開 | バイト範囲を `TextRange`（開始・終了位置）に変換 | `config/src/diagnostics.rs:L208-217` |
| `format_config_error_with_source(error)` | 公開 | `error.path` からファイル内容を読み込んで `format_config_error` を呼ぶ | `config/src/diagnostics.rs:L255-259` |
| `default_range()` | 非公開 | `(1,1)-(1,1)` のデフォルト `TextRange` を返す | `config/src/diagnostics.rs:L293-299` |
| `span_for_path(contents, path)` | 非公開 | Serde の `Path` から TOML AST 内のノードを探し、その `span` を返す | `config/src/diagnostics.rs:L307-315` |
| `span_for_config_path(contents, path)` | 非公開 | `features` テーブルの特殊処理を行った上で `span_for_path` を呼ぶ | `config/src/diagnostics.rs:L317-323` |
| `is_features_table_path(path)` | 非公開 | Serde パスが `features` テーブルそのものを指すか判定 | `config/src/diagnostics.rs:L326-330` |
| `span_for_features_value(contents)` | 非公開 | `features` テーブル内の最初の非 boolean 値（あるいはテーブル等）の `span` を返す | `config/src/diagnostics.rs:L332-347` |
| `node_for_path(item, path)` | 非公開 | Serde の `Path` を辿って TOML AST 内の `TomlNode` を特定 | `config/src/diagnostics.rs:L349-375` |
| `map_child(node, key)` | 非公開 | テーブル/インラインテーブルから指定キーの子ノードを取得 | `config/src/diagnostics.rs:L378-387` |
| `seq_child(node, index)` | 非公開 | 配列／Array-of-Tables から指定インデックスの子ノードを取得 | `config/src/diagnostics.rs:L390-396` |

---

## 4. データフロー

ここでは、`first_layer_config_error` 呼び出し時の典型的なデータフローを示します。

### 4.1 レイヤー検証時のフロー

処理の要点:

1. 呼び出し側が `ConfigLayerStack` と設定型 `T` を指定して `first_layer_config_error::<T>` を呼ぶ。
2. スタックからレイヤー一覧を取得し、1 レイヤーずつファイルパス→内容読み込み→型付き検証を行う。
3. 最初にエラーとなったレイヤーで `ConfigError` を生成し、それを返す。
4. `ConfigError` は `format_config_error_with_source` でユーザーフレンドリなテキストに変換される。

```mermaid
sequenceDiagram
    %% この図は diagnostics.rs 内のコード範囲を示します
    participant Caller as 呼び出し側
    participant Stack as ConfigLayerStack<br>(外部)
    participant F1 as first_layer_config_error<br>(L137-152)
    participant F2 as first_layer_config_error_for_entries<br>(L161-191)
    participant PathFn as config_path_for_layer<br>(L194-205)
    participant FS as tokio::fs::read_to_string<br>(外部)
    participant Guard as AbsolutePathBufGuard::new<br>(L185)
    participant Typed as config_error_from_typed_toml<br>(L109-135)
    participant Span as span_for_config_path<br>(L317-323)
    participant Format as format_config_error_with_source<br>(L255-259)

    Caller->>F1: first_layer_config_error::<T>(&Stack, "config.toml")
    F1->>Stack: get_layers(LowestPrecedenceFirst, false)
    F1->>F2: first_layer_config_error_for_entries(iter, "config.toml")
    loop 各 ConfigLayerEntry
        F2->>PathFn: config_path_for_layer(layer, "config.toml")
        alt Some(path)
            F2->>FS: read_to_string(path).await
            alt OK(contents)
                F2->>Guard: AbsolutePathBufGuard::new(parent(path))
                F2->>Typed: config_error_from_typed_toml::<T>(&path, &contents)
                alt Some(ConfigError)
                    F2-->>F1: Some(ConfigError)
                    F1-->>Caller: Some(ConfigError)
                    break
                else None
                    note right of F2: 次のレイヤーへ
                end
            else NotFound/Other IO Error
                note right of F2: スキップ or debug ログ
            end
        else None (Mdm/SessionFlagsなど)
            note right of F2: スキップ
        end
    end
    Caller->>Format: format_config_error_with_source(&ConfigError)
    Format-->>Caller: 整形済みエラーメッセージ
```

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

1. 設定構造体 `T` に `Deserialize` を実装する。
2. 設定レイヤースタック `ConfigLayerStack` を準備する（定義はこのチャンクにはありません）。
3. `first_layer_config_error::<T>` を呼んで最初のレイヤーエラーを取得する。
4. `format_config_error_with_source` で人間向けメッセージに整形する。

```rust
use serde::Deserialize;
use crate::config::diagnostics::{
    first_layer_config_error,
    format_config_error_with_source,
};

#[derive(Deserialize)]
struct AppConfig {
    // ...
}

async fn check_config_layers(layers: &ConfigLayerStack) {
    if let Some(err) = first_layer_config_error::<AppConfig>(layers, "config.toml").await {
        // エラー内容をファイルから読み込んで整形
        let msg = format_config_error_with_source(&err);
        eprintln!("{msg}");
    } else {
        println!("設定に問題はありません");
    }
}
```

（`first_layer_config_error`, `format_config_error_with_source` の実装に基づく使用例  
`config/src/diagnostics.rs:L137-152, L255-259`）

### 5.2 よくある使用パターン

1. **単一ファイルの構文・型検証**

   - `config_error_from_typed_toml::<T>` を直接使い、1 つの TOML ファイルの妥当性を検証する。

   ```rust
   use std::fs;
   use std::path::Path;
   use serde::Deserialize;
   use crate::config::diagnostics::{
       config_error_from_typed_toml,
       format_config_error,
   };

   #[derive(Deserialize)]
   struct AppConfig {
       // ...
   }

   fn validate_single_file(path: &Path) {
       let contents = fs::read_to_string(path).expect("読み込み失敗");
       if let Some(err) = config_error_from_typed_toml::<AppConfig>(path, &contents) {
           let msg = format_config_error(&err, &contents);
           eprintln!("{msg}");
       }
   }
   ```

2. **IO エラーとして上位へ伝播**

   - `io_error_from_config_error` で `io::Error` に変換して、より外側の API で統一的に扱う。

   ```rust
   use std::io;
   use crate::config::diagnostics::{io_error_from_config_error};

   fn convert_to_io_error(err: crate::config::diagnostics::ConfigError) -> io::Error {
       io_error_from_config_error(io::ErrorKind::InvalidData, err, None)
   }
   ```

### 5.3 よくある間違い

```rust
// 間違い例: contents と実際のファイル内容が一致していない
let err = config_error_from_toml("config.toml", some_other_contents, parse_err);
// format_config_error_with_source は error.path から内容を読み直すが、
// config_error_from_toml に渡した contents とズレている可能性がある

// 正しい例: path に対応する内容を常に一貫して使う
let contents = std::fs::read_to_string("config.toml")?;
let parse_err = /* toml::de::Error を取得 */;
let err = config_error_from_toml("config.toml", &contents, parse_err);
let msg = format_config_error(&err, &contents);
```

```rust
// 間違い例: 非同期コンテキストでない場所で first_layer_config_error を呼ぶ
// let result = first_layer_config_error::<AppConfig>(&layers, "config.toml"); // コンパイルエラー

// 正しい例: async 関数内で .await する
async fn run(layers: &ConfigLayerStack) {
    let result = first_layer_config_error::<AppConfig>(layers, "config.toml").await;
}
```

### 5.4 使用上の注意点（まとめ）

- **非同期実行**: `first_layer_config_error` / `_from_entries` は `async fn` であり、`tokio` などのランタイム上で `.await` する必要があります（`L137-152, L154-159, L172`）。
- **エラーの扱い**
  - IO エラーや一部の TOML パース失敗は **このモジュール内で飲み込まれ、`Option::None` として扱われる** ケースがあります（`L172-179, L307-309`）。
  - すべてのエラーを詳細に把握したい場合は、より下位の API（`toml::de` 直接呼び出しなど）を利用する必要があります。
- **パスの安全性**
  - `config_path_for_layer` は `dot_codex_folder.join(config_toml_file)` をそのまま使うため、`config_toml_file` によるディレクトリトラバーサル制御はこのモジュール外の責務です（`L198-200`）。
- **UTF-8 前提**
  - `position_for_offset` や `format_config_error` は `contents` が UTF-8 エンコードされた Rust の `&str` である前提です。バイナリや別エンコーディングのデータには使用できません。

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

例: JSON 版の設定ファイル診断機能を追加したい場合の考え方。

1. **データ構造の再利用**
   - 位置情報やエラー表現は `TextPosition`, `TextRange`, `ConfigError` をそのまま再利用できます（`L22-40`）。
2. **フォーマット固有ロジックの追加**
   - TOML 固有の処理 (`span_for_config_path`, `node_for_path` など `L317-375`) と切り離し、JSON など別形式用のヘルパー関数を別ファイル／別モジュールに追加するのが自然です。
3. **公開 API の設計**
   - `config_error_from_typed_toml` と同様に、`config_error_from_typed_json` のような関数を追加し、`ConfigError` を返すインターフェースを揃えると一貫します。

### 6.2 既存の機能を変更する場合

- **影響範囲の確認**
  - `ConfigError` のフィールドや表現形式を変更する場合、`ConfigLoadError`, `format_config_error`, `format_config_error_with_source` などが影響を受けます（`L35-40, L52-87, L219-259`）。
- **契約の維持**
  - `first_layer_config_error` は「最初のエラーのみ」を返すという前提で呼ばれている可能性が高いため、戻り値の意味を変える場合は呼び出し側全体の確認が必要です（`L137-152, L161-191`）。
  - `config_error_from_typed_toml` はエラー時に `Some` を返すという契約を持っています。`Result` への変更などは API 互換性を壊すため、慎重な検討が必要です。
- **テストと使用箇所**
  - このチャンク内にはテストコードが存在しないため、テストの所在は不明です。変更時にはリポジトリ全体から `ConfigError`, `first_layer_config_error`, `format_config_error` などの使用箇所とテストを検索する必要があります。

---

## 7. 関連ファイル

このモジュールと密接に関連するであろう型やファイル（ただし、このチャンクには定義が現れないもの）を列挙します。

| パス / 型名 | 役割 / 関係 |
|-------------|------------|
| `crate::ConfigLayerStack` | レイヤー化された設定のスタック。`first_layer_config_error` から `get_layers` が呼び出される（`config/src/diagnostics.rs:L137-148`）。このチャンクには定義がありません。 |
| `crate::ConfigLayerEntry` | 個々の設定レイヤーを表すエントリ。`first_layer_config_error_for_entries` のイテレート対象（`L161-191`）。定義はこのチャンクには現れません。 |
| `codex_app_server_protocol::ConfigLayerSource` | レイヤーの種類を表す列挙体。`config_path_for_layer` の `match` 対象（`L194-205`）。 |
| `codex_utils_absolute_path::AbsolutePathBufGuard` | 親ディレクトリをもとに何らかのパス関連ガードとして使われている（`L185`）。挙動はこのチャンクでは不明です。 |
| `toml_edit::{Document, Item, Table, Value}` | TOML AST を表現する型群。`span_for_path`, `span_for_features_value`, `node_for_path` などで使用（`L307-347, L349-396`）。 |
| `serde_path_to_error::{Path, Segment}` | デシリアライズ時のフィールドパス情報を表す型。`config_error_from_typed_toml`, `span_for_config_path`, `node_for_path` で使用（`L109-135, L317-330, L349-373`）。 |

---

### Bugs / Security / その他の注意点（まとめ）

- **潜在的なバグ懸念**
  - `position_for_offset` で `index` が文字列長より大きい場合、末尾文字の位置に基づきつつ列だけ増やす挙動になります（`L268-269, L285`）。大きく外れたインデックスでもパニックしない一方、直感と異なる位置が返る可能性があります。
- **セキュリティ上の観点**
  - このモジュールはファイルパスの検証を行わず、引数で与えられたパスや `config_toml_file` をそのまま使用します（`L194-205`）。パスの安全性（パストラバーサル防止など）は呼び出し元の責務となります。
  - ファイル読み込み失敗時に `tracing::debug!` レベルでのみログを出し、上位にエラーを返さないため、権限不足などの問題がユーザーから見えにくくなる可能性があります（`L172-179`）。
- **テスト**
  - このチャンクにはテストコードが含まれていません。位置計算や span 解決はエッジケースが多いため、変更時には専用のテストが必須です。
