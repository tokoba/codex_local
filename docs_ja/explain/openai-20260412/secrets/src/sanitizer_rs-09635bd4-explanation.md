# secrets/src/sanitizer.rs コード解説

## 0. ざっくり一言

このモジュールは、文字列中に含まれる OpenAI API キーや AWS アクセスキー、Bearer トークン、各種「password/token/api key」風の値を正規表現で検出し、`[REDACTED_SECRET]` に置き換えるためのユーティリティです（`redact_secrets` 関数, sanitizer.rs:L13-21）。

---

## 1. このモジュールの役割

### 1.1 概要

- このモジュールは、ログやエラーメッセージなどに **秘密情報が含まれた文字列を直接出力しない** ために存在し、秘密情報を検知してマスクする機能を提供します（sanitizer.rs:L13-21）。
- OpenAI キー、AWS Access Key ID、Bearer トークン、`api_key` や `password` などの設定値らしき部分を正規表現で検出し、それぞれを固定文字列に置き換えます（sanitizer.rs:L4-11, L16-19）。
- 正規表現コンパイルは `LazyLock<Regex>` を使い、**スレッドセーフに一度だけ** 実行されます（sanitizer.rs:L2, L4-11, L24-30）。

### 1.2 アーキテクチャ内での位置づけ

このファイル単体から分かる関係のみを示します。他モジュールからの呼び出し元はこのチャンクには現れないため不明です。

- 依存:
  - 外部クレート `regex::Regex`（sanitizer.rs:L1）
  - 標準ライブラリ `std::sync::LazyLock`（sanitizer.rs:L2）
- 提供:
  - 公開 API: `redact_secrets(input: String) -> String`（sanitizer.rs:L15-21）
- 内部ヘルパ:
  - `compile_regex(pattern: &str) -> Regex`（sanitizer.rs:L24-30）
- テスト:
  - `tests::load_regex` により全ての正規表現がコンパイルできることを確認（sanitizer.rs:L32-40）

Mermaid で依存関係を表します（各ノードに行番号を明記しています）。

```mermaid
flowchart LR
    Caller["他モジュールの呼び出し元（不明）"]
    Redact["redact_secrets (L15-21)"]
    OpenAI["OPENAI_KEY_REGEX (L4)"]
    AWS["AWS_ACCESS_KEY_ID_REGEX (L5-6)"]
    Bearer["BEARER_TOKEN_REGEX (L7-8)"]
    Assign["SECRET_ASSIGNMENT_REGEX (L9-11)"]
    Compile["compile_regex (L24-30)"]
    Test["tests::load_regex (L37-40)"]

    Caller --> Redact
    Redact --> OpenAI
    Redact --> AWS
    Redact --> Bearer
    Redact --> Assign
    OpenAI --> Compile
    AWS --> Compile
    Bearer --> Compile
    Assign --> Compile
    Test --> Redact
```

### 1.3 設計上のポイント

- **正規表現の事前コンパイルと共有**
  - 4 種類の `Regex` を `static` な `LazyLock<Regex>` として定義し、初回アクセス時にのみコンパイルします（sanitizer.rs:L4-11）。
  - これにより、複数スレッドからの利用でもコンパイルコストを抑えつつスレッドセーフに共有できます（`LazyLock` の設計上の性質）。

- **ベストエフォートなマスク**
  - ドキュメントコメントには「best effort basis」と書かれており（sanitizer.rs:L13-14）、すべての秘密を網羅的に検出することは前提とされていません。

- **エラー処理方針**
  - 正規表現のコンパイルに失敗した場合は `panic!` します（sanitizer.rs:L24-30）。
  - コメントに「Panic is ok thanks to `load_regex` test」とあり（sanitizer.rs:L27-28）、テストでコンパイル成功を担保することで、実運用時のパニックは「パターンを変更した際のバグ検出」として受け入れる設計になっています。

- **状態のない純粋関数**
  - `redact_secrets` は入力 `String` を受け取り、新しい `String` を返すだけで、内部に状態を持ちません（sanitizer.rs:L15-21）。

---

## 2. 主要な機能一覧

- 秘密情報のマスキング: 文字列中の各種キーやトークンを検出し、`[REDACTED_SECRET]` に置き換えます（`redact_secrets`, sanitizer.rs:L15-21）。
- 正規表現のコンパイル: 与えられたパターン文字列から `Regex` を生成し、失敗した場合はパニックします（`compile_regex`, sanitizer.rs:L24-30）。
- 正規表現パターンの定義:
  - OpenAI API キー検出用（sanitizer.rs:L4）
  - AWS Access Key ID 検出用（sanitizer.rs:L5-6）
  - Bearer トークン検出用（sanitizer.rs:L7-8）
  - `api_key`/`token`/`secret`/`password` の代入検出用（sanitizer.rs:L9-11）

### 2.1 コンポーネントインベントリー

| 名前 | 種別 | 役割 / 用途 | 定義位置 |
|------|------|-------------|----------|
| `OPENAI_KEY_REGEX` | `static LazyLock<Regex>` | OpenAI API キー (`sk-` で始まり英数字 20 文字以上) を検出する正規表現 | sanitizer.rs:L4 |
| `AWS_ACCESS_KEY_ID_REGEX` | `static LazyLock<Regex>` | AWS Access Key ID (`AKIA` + 英数字 16文字) を検出する正規表現 | sanitizer.rs:L5-6 |
| `BEARER_TOKEN_REGEX` | `static LazyLock<Regex>` | `Bearer <token>` 形式（大文字小文字無視、16 文字以上）のトークンを検出する正規表現 | sanitizer.rs:L7-8 |
| `SECRET_ASSIGNMENT_REGEX` | `static LazyLock<Regex>` | `api_key`/`token`/`secret`/`password` などの代入文を検出し、値だけをマスクする正規表現 | sanitizer.rs:L9-11 |
| `redact_secrets` | 公開関数 | 入力文字列中の秘密情報を上記の正規表現で検出しマスクした新しい文字列を返す | sanitizer.rs:L15-21 |
| `compile_regex` | 非公開関数 | パターン文字列から `Regex` を作成し、コンパイル失敗時にパニックするヘルパ関数 | sanitizer.rs:L24-30 |
| `tests::load_regex` | テスト関数 | `redact_secrets` を一度呼び出して、全ての正規表現がコンパイル可能であることを確認 | sanitizer.rs:L32-40 |

---

## 3. 公開 API と詳細解説

### 3.1 型一覧（構造体・列挙体など）

このファイル内では、独自の構造体や列挙体は定義されていません（sanitizer.rs 全体）。  
使用される主な型は外部クレート `regex::Regex` と標準の `String`、`LazyLock` です（sanitizer.rs:L1-2, L15-21, L24-30）。

### 3.2 関数詳細

#### `pub fn redact_secrets(input: String) -> String`（L15-21）

**概要**

- 入力された文字列中の秘密情報を検出し、プレースホルダ文字列に置き換えた新しい文字列を返します（sanitizer.rs:L15-21）。
- 「best effort」であり、正規表現で検出できるパターンのみが対象です（sanitizer.rs:L13-14）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `input` | `String` | マスク対象の元文字列。所有権を関数に移動します（sanitizer.rs:L15）。 |

**戻り値**

- `String`  
  秘密情報候補が `[REDACTED_SECRET]` または `Bearer [REDACTED_SECRET]` に置き換えられた文字列を返します（sanitizer.rs:L21）。

**内部処理の流れ（アルゴリズム）**

1. `OPENAI_KEY_REGEX` で `input` 中の OpenAI キーにマッチし、`[REDACTED_SECRET]` に置き換えます（sanitizer.rs:L16）。
2. 1 の結果に対して `AWS_ACCESS_KEY_ID_REGEX` を適用し、AWS Access Key ID を `[REDACTED_SECRET]` に置き換えます（sanitizer.rs:L17）。
3. 2 の結果に対して `BEARER_TOKEN_REGEX` を適用し、マッチした部分全体を `"Bearer [REDACTED_SECRET]"` に置き換えます（sanitizer.rs:L18）。
   - 正規表現は `(?i)` 付きなので `bearer`/`Bearer` など大文字小文字を問わず検出しますが、置換結果は常に `"Bearer"` という表記に正規化されます。
4. 3 の結果に対して `SECRET_ASSIGNMENT_REGEX` を適用し、  
   - グループ1: `api_key` / `token` / `secret` / `password` などのキー名（sanitizer.rs:L9-10）
   - グループ2: `:` や `=` などの区切りと周辺の空白
   - グループ3: 開始クォート（任意）
   を維持したまま、値の部分を `[REDACTED_SECRET]` に置き換えます（置換文字列 `$1$2$3[REDACTED_SECRET]`, sanitizer.rs:L19）。
5. 最後に得られた `Cow<str>` を `to_string()` で `String` に変換して返します（sanitizer.rs:L21）。

**Examples（使用例）**

基本的な利用例です。

```rust
use secrets::sanitizer::redact_secrets; // 仮のパス。実際のクレート名はこのチャンクには現れません

fn main() {
    // 秘密情報を含む文字列を用意する
    let raw = r#"OpenAI key: sk-ABCDEFGHIJKLMNOPQRSTUV1234
AWS: AKIA1234567890ABCD
Authorization: Bearer abc.def-ghi_jklmnopqrst
db_password = "supersecretpassword""#.to_string();

    // 秘密情報をマスクする
    let redacted = redact_secrets(raw);

    // 結果を出力する
    println!("{redacted}");
}
```

この例では、OpenAI キー、AWS キー、Bearer トークン、`db_password` の値がそれぞれ `[REDACTED_SECRET]` でマスクされた文字列が出力されます。

**Errors / Panics**

- `redact_secrets` 自体は `Result` を返さず、関数内部に `panic!` もありません（sanitizer.rs:L15-21）。
- ただし内部で使用している `LazyLock<Regex>` の初期化時に `compile_regex` が呼ばれ（sanitizer.rs:L4-11, L24-30）、そこで `Regex::new` がエラーを返した場合にはパニックが発生します。
  - 通常はアプリケーションの起動直後または初回呼び出し時に発生し得ます。

**Edge cases（エッジケース）**

- **空文字列**: `input` が空文字列でも全ての `replace_all` は何も置換せず、そのまま空文字列が返ります（sanitizer.rs:L16-21 の `replace_all` の性質）。
- **対象パターンが存在しない**: どの正規表現にもマッチしない場合、入力と同じ文字列が返ります（`replace_all` はマッチ無しの場合に元の文字列をそのまま返す挙動）。
- **複数種の秘密情報を含む場合**: OpenAI → AWS → Bearer → SECRET_ASSIGNMENT の順で置換が適用されます（sanitizer.rs:L16-19）。
- **短い値**: `SECRET_ASSIGNMENT_REGEX` は値部分が 8 文字以上である場合のみマッチします（`{8,}`, sanitizer.rs:L10）。それ未満の長さの値はマスクされません。
- **Bearer の大小文字**: `(?i)` フラグにより `bearer` でもマッチしますが、置換後は `Bearer [REDACTED_SECRET]` という大文字小文字固定の文字列になります（sanitizer.rs:L7-8, L18）。

**使用上の注意点**

- この関数は **ベストエフォート** であり、全ての種類の秘密情報を検出することは保証されません（sanitizer.rs:L13-14）。
- `input` の所有権を消費するため、呼び出し元で元の文字列を再利用したい場合は、事前に `clone()` するか `&str` ベースの API を別途用意する必要があります（関数シグネチャより, sanitizer.rs:L15）。
- 非常に長い文字列や高頻度の呼び出しでは、正規表現マッチングにより CPU 負荷が高くなり得ます。`LazyLock` でコンパイルコストは抑えられていますが、マッチングコストは残ります（sanitizer.rs:L4-11, L16-19）。
- 複数スレッドから同時に呼び出しても、`LazyLock` と `Regex` はスレッドセーフなため（標準ライブラリと `regex` の設計上の性質）、データ競合は発生しません。

---

#### `fn compile_regex(pattern: &str) -> Regex`（L24-30）

**概要**

- 与えられたパターン文字列を `regex::Regex` にコンパイルする内部ヘルパ関数です（sanitizer.rs:L24-30）。
- コンパイルに失敗した場合は `panic!` を発生させます（sanitizer.rs:L27-28）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `pattern` | `&str` | コンパイルしたい正規表現パターン文字列（sanitizer.rs:L24）。 |

**戻り値**

- `Regex`  
  成功した場合、コンパイル済みの `Regex` オブジェクトを返します（sanitizer.rs:L25-26）。

**内部処理の流れ**

1. `Regex::new(pattern)` を呼び出し、`Result<Regex, regex::Error>` を得ます（sanitizer.rs:L25）。
2. `match` で結果を分岐し、`Ok(regex)` の場合はそのまま `regex` を返します（sanitizer.rs:L25-26）。
3. `Err(err)` の場合は `panic!("invalid regex pattern`{pattern}`: {err}")` を実行し、パニックします（sanitizer.rs:L27-28）。

**Examples（使用例）**

通常は `LazyLock::new(|| compile_regex(...))` からのみ呼び出されます（sanitizer.rs:L4-11）。  
参考として、この関数単体を使った例です（実際には非公開関数のため、同一モジュール内からのみ呼び出し可能です）。

```rust
fn example() {
    // 有効な正規表現パターン
    let regex = compile_regex(r"\d+"); // 数字列にマッチ

    assert!(regex.is_match("123"));
    assert!(!regex.is_match("abc"));
}
```

**Errors / Panics**

- `Regex::new(pattern)` がエラーを返した場合、`panic!` が発生します（sanitizer.rs:L25-28）。
  - これにより、無効なパターンが埋め込まれている場合は **起動時または初回利用時に即座にクラッシュ** し、不正な状態での継続実行を防ぎます。
- パニックはスレッドスタックのアンワインドまたはアボートを引き起こしますが、メモリ安全性は Rust の仕組みにより保たれます（ここでは `unsafe` は使用されていません）。

**Edge cases（エッジケース）**

- **空文字列のパターン**: `Regex::new("")` は許可されており、空文字列にマッチする正規表現になります。これはパニックを引き起こしません。
- **不正なパターン**: 括弧が閉じていないなどの文法エラーを含むパターンは `Err` になり、それによりパニックが発生します。

**使用上の注意点**

- この関数はパニックを起こし得るため、外部 API ではなく内部の `LazyLock` 初期化に限定して利用されています（sanitizer.rs:L4-11, L24-30）。
- 正規表現パターンを変更する際は、テスト `load_regex` を実行してコンパイルに成功することを確認する前提になっています（sanitizer.rs:L32-40）。

### 3.3 その他の関数

| 関数名 | 役割（1 行） | 定義位置 |
|--------|--------------|----------|
| `tests::load_regex` | `redact_secrets("secret".to_string())` を呼び出し、全ての正規表現がコンパイル可能かどうかを確認するテスト | sanitizer.rs:L37-40 |

---

## 4. データフロー

ここでは、`redact_secrets` が呼び出されたときの処理の流れを示します。

### 4.1 `redact_secrets` のデータフロー

```mermaid
sequenceDiagram
    autonumber
    participant C as 呼び出し元
    participant R as redact_secrets (L15-21)
    participant O as OPENAI_KEY_REGEX (L4)
    participant A as AWS_ACCESS_KEY_ID_REGEX (L5-6)
    participant B as BEARER_TOKEN_REGEX (L7-8)
    participant S as SECRET_ASSIGNMENT_REGEX (L9-11)

    C->>R: input: String
    Note right of R: 入力文字列を受け取る
    R->>O: replace_all(&input, "[REDACTED_SECRET]")
    O-->>R: 中間文字列1
    R->>A: replace_all(&中間文字列1, "[REDACTED_SECRET]")
    A-->>R: 中間文字列2
    R->>B: replace_all(&中間文字列2, "Bearer [REDACTED_SECRET]")
    B-->>R: 中間文字列3
    R->>S: replace_all(&中間文字列3, "$1$2$3[REDACTED_SECRET]")
    S-->>R: 最終文字列 (Cow<str>)
    R-->>C: 最終文字列.to_string()
```

- 初回実行時には、各 `LazyLock<Regex>` が内部で `compile_regex` を通じて `Regex` をコンパイルします（sanitizer.rs:L4-11, L24-30）。
- 以降の呼び出しでは既にコンパイル済みの `Regex` が再利用されます。
- テスト `load_regex` は、少なくとも `redact_secrets("secret")` 実行時に全ての正規表現がコンパイルされパニックしないことを検証します（sanitizer.rs:L37-40）。

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

ログ出力前に秘密情報をマスクする典型的な使用例です。

```rust
use secrets::sanitizer::redact_secrets; // 実際のパスはこのチャンクには現れないため、例として記載

fn main() {
    // ユーザー入力や外部サービスから取得したペイロード
    let payload = r#"Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456
api_key = "my-very-secret-key""#.to_string(); // String を作成

    // ログに出す前に秘密情報をマスクする
    let safe_payload = redact_secrets(payload); // 所有権を渡し、マスク済み文字列を得る

    // マスク済みの内容だけをログに出力する
    println!("{safe_payload}");
}
```

### 5.2 よくある使用パターン

1. **ログフィルタとして利用**

   ```rust
   fn log_request(body: &str) {
       // &str から String に変換してマスク
       let redacted = redact_secrets(body.to_string());
       println!("request body: {redacted}");
   }
   ```

2. **エラーメッセージのマスキング**

   ```rust
   fn handle_error(error_message: String) {
       // そのまま `redact_secrets` に渡してマスク
       let safe_message = redact_secrets(error_message);
       eprintln!("error: {safe_message}");
   }
   ```

### 5.3 よくある間違い

```rust
// 間違い例: &str をそのまま渡そうとしてコンパイルエラーになる
// let redacted = redact_secrets("api_key=secret");

// 正しい例: &str から String に変換して渡す
let redacted = redact_secrets("api_key=secret".to_string());
```

```rust
// 間違い例: 秘密情報をそのままログに出力してしまう
println!("request body: {}", body);

// 正しい例: 出力前に必ずマスクする
println!("request body: {}", redact_secrets(body.to_string()));
```

### 5.4 使用上の注意点（まとめ）

- **完全な秘匿は保証されない**  
  - 対応していない形式の秘密情報はマスクされません（sanitizer.rs:L13-14, L4-11）。  
  - 特に、`SECRET_ASSIGNMENT_REGEX` は値が 8 文字未満の場合や、キー名が正規表現で列挙されていない場合にはマッチしません（sanitizer.rs:L9-10）。

- **パニックの可能性**  
  - 正規表現パターンに文法エラーがあると、`compile_regex` 内の `panic!` によりプロセスがクラッシュします（sanitizer.rs:L24-30）。  
  - 現在の定義済みパターンは `load_regex` テストで検証されていますが、新たに追加・変更する場合はテスト実行が必須です（sanitizer.rs:L32-40）。

- **並行性**  
  - `LazyLock` と `Regex` はスレッドセーフなため、複数スレッドから `redact_secrets` を同時に呼び出してもデータ競合は発生しません（sanitizer.rs:L2, L4-11）。  
  - 初期化は一度のみ行われ、残りは読み取り専用なので、並行性能は良好です。

- **パフォーマンス**  
  - 正規表現によるマッチングは文字列長に比例してコストが増加します。大きなログや高頻度の呼び出しではボトルネックになる可能性があります（sanitizer.rs:L16-19）。  
  - ただし、パターンのコンパイルは `LazyLock` により一度だけなので、コンパイルコストは問題になりにくい設計です（sanitizer.rs:L4-11）。

- **情報の正規化**  
  - Bearer トークンの置換結果は常に `"Bearer [REDACTED_SECRET]"` であり、元の大文字小文字の形は失われます（sanitizer.rs:L7-8, L18）。  
  - これは通常問題になりませんが、出力内容を厳密に比較するテストを書く場合は注意が必要です。

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合（例: 新種の秘密情報の検出）

1. **新しい正規表現の追加**
   - 既存の `static ..._REGEX` と同様に、新しい `LazyLock<Regex>` を定義します（sanitizer.rs:L4-11 を参考）。
   - 例:

     ```rust
     static CUSTOM_SECRET_REGEX: LazyLock<Regex> =
         LazyLock::new(|| compile_regex(r"your-pattern-here"));
     ```

2. **`redact_secrets` への適用追加**
   - `redact_secrets` 内で他の置換と同様に `replace_all` を追加します（sanitizer.rs:L16-19）。

     ```rust
     let redacted = CUSTOM_SECRET_REGEX.replace_all(&redacted, "[REDACTED_SECRET]");
     ```

3. **テストの更新**
   - `tests` モジュールに、新しいパターンがコンパイルされること・期待通りにマスクされることを確認するテストケースを追加します（既存の `load_regex` はコンパイル確認のみ, sanitizer.rs:L37-40）。
   - 特に誤検出（false positive）や未検出（false negative）の可能性が高い境界ケースを含めると安全です。

### 6.2 既存の機能を変更する場合

- **影響範囲の確認**
  - 正規表現定義（sanitizer.rs:L4-11）と `redact_secrets` 内部の置換処理（sanitizer.rs:L16-19）が主な変更対象です。
  - 外部からは `redact_secrets` のシグネチャは変えない限り影響は限定的ですが、置換結果の文字列が変わるため、ログフォーマット等に依存している部分があれば影響します（呼び出し元はこのチャンクには現れないため不明）。

- **契約（前提条件・返り値の意味）**
  - `redact_secrets` は「元の文字列の一部をマスクした新しい文字列を返す」という契約のもとで使われていると考えられます（シグネチャと名前からの推測、sanitizer.rs:L15-21）。  
  - これを破る（例: 空文字を返す、フォーマットを大きく変える）と呼び出し側の期待を裏切る可能性が高いため注意が必要です。

- **正規表現と置換文字列の整合性**
  - `SECRET_ASSIGNMENT_REGEX` は 3 つのキャプチャグループを持ち、置換文字列で `$1$2$3` を参照しています（sanitizer.rs:L9-10, L19）。
  - グループ構造を変更する場合は、置換文字列も必ず合わせて更新する必要があります。整合しないとランタイムエラーにはなりませんが、期待しない文字列になり得ます。

- **テスト・使用箇所の再確認**
  - 正規表現の変更は予期せぬマッチ範囲の変更を招くことがあるため、境界値テストや代表的なログを用いたテストを追加・更新することが望ましいです（既存の `load_regex` はコンパイル確認のみ, sanitizer.rs:L37-40）。

---

## 7. 関連ファイル

このチャンクには、他のファイルやモジュールとの明示的な関連は現れません。  
分かる範囲で、同一ファイル内の関連コンポーネントをまとめます。

| パス | 役割 / 関係 |
|------|------------|
| `secrets/src/sanitizer.rs` | 本ドキュメント対象。`redact_secrets` と正規表現定義、`compile_regex`、テスト `tests::load_regex` を含む（sanitizer.rs:L1-41）。 |
| `secrets/src/sanitizer.rs` 内 `mod tests` | 正規表現がコンパイル可能であることを確認するユニットテストを提供（sanitizer.rs:L32-40）。 |

その他のモジュール（`lib.rs` や呼び出し元のコードなど）が存在するかどうか、このチャンクには現れないため不明です。
