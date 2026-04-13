# tui/tests/suite/no_panic_on_startup.rs

## 0. ざっくり一言

Codex CLI の TUI を疑似端末（PTY）上で起動し、「ルールディレクトリが壊れている（ファイルになっている）」状態でも **パニックせずに適切なエラーで終了すること** を検証する非同期統合テストと、そのための CLI 起動ヘルパー関数を定義するファイルです（`tui/tests/suite/no_panic_on_startup.rs:L7-49, L56-127`）。

---

## 1. このモジュールの役割

### 1.1 概要

- Codex CLI の回帰テストとして、Issue #8803 に関連する「起動時のパニックが発生しないこと」を検証します（`tui/tests/suite/no_panic_on_startup.rs:L7-10`）。
- `CODEx_HOME` 下の `rules` を**ディレクトリではなくファイル**として用意し、その状態で CLI を起動したときに、  
  - 非ゼロ終了コードで終了すること  
  - 期待するエラーメッセージを出力すること  
  を確認します（`L16-21, L38-47`）。
- CLI を対話的な TUI 環境に近い形で起動するため、疑似端末（PTY）上でプロセスを起動し、カーソル位置問い合わせ（ESC[6n）に応答して TUI をブロックさせないようにしています（`L68-75, L87-99`）。

### 1.2 アーキテクチャ内での位置づけ

このファイルは「テスト層」に位置し、実際の `codex` バイナリを外部プロセスとして起動して振る舞いを検証します（`L56-76`）。

```mermaid
graph TD
  subgraph "no_panic_on_startup.rs (L10-127)"
    T["malformed_rules_should_not_panic テスト (L10-49)"]
    R["run_codex_cli ヘルパー (L56-127)"]
    O["CodexCliOutput 構造体 (L51-54)"]
  end

  T --> R
  R --> O

  R --> C["codex_utils_cargo_bin::cargo_bin(\"codex\")\n(外部クレート, L60)"]
  R --> P["codex_utils_pty::spawn_pty_process\n(外部クレート, L68-76)"]
  R --> M["tokio::time::timeout / select!\n(非同期制御, L87-108, L91-105)"]
  R --> B["codex バイナリ (外部プロセス)"]

  P --> B
```

- テスト関数 `malformed_rules_should_not_panic` がこのファイルのエントリポイントであり（`L10-49`）、実際の CLI プロセス起動は `run_codex_cli` に委譲されています（`L38-39, L56-127`）。
- `run_codex_cli` は `codex_utils_cargo_bin` と `codex_utils_pty` という外部ユーティリティクレートに依存しており、それぞれテスト対象バイナリのパス解決と PTY 上のプロセス起動を行っていると推測されます（命名と使用箇所からの推測であり、詳細な実装はこのファイルからは分かりません。`L60, L68-76`）。

### 1.3 設計上のポイント

- **非同期テスト**  
  - `#[tokio::test]` により Tokio ランタイム上で動作する非同期テストとして実装されています（`L8-10`）。
- **プラットフォーム依存性の分離**  
  - Windows では PTY まわりの制約により `run_codex_cli` が動作しないため、テスト自体をスキップする設計になっています（`L11-14`）。
- **外部プロセスの堅牢な制御**  
  - PTY 経由で CLI を起動し、標準出力・標準エラーを統合して読みつつ（`L78-85`）、`tokio::select!` と `timeout` で  
    - 出力の読み取り  
    - プロセスの終了通知  
    を同時に待ち、ハング・フリーズを防ぐ構造になっています（`L87-108, L91-105`）。
- **TUI 初期化のためのプロトコル対応**  
  - 出力ストリーム中にカーソル位置問い合わせシーケンス `ESC[6n` が含まれていた場合に、`ESC[1;1R` で応答して TUI を進行させる処理が入っています（`L94-99`）。
- **エラーハンドリングの明示**  
  - `anyhow::Result` を利用し、ファイル I/O、プロセス起動、タイムアウト、エンコードなど様々なエラーを 1 つの戻り値型で扱っています（`L10, L56-59, L87-116`）。

---

## 2. 主要な機能一覧

このファイルで提供される主要な機能は次の通りです。

- **壊れたルールディレクトリでの CLI 起動テスト**  
  - `malformed_rules_should_not_panic`: `rules` がファイルである `CODEx_HOME` で Codex CLI を起動し、起動時にパニックせず、期待するエラーメッセージを出力することを確認します（`L10-21, L38-47`）。
- **Codex CLI 起動ヘルパー**  
  - `run_codex_cli`: 指定した `codex_home` とカレントディレクトリ `cwd`、環境変数、引数を設定して `codex` バイナリを PTY 上で起動し、  
    - TUI からのカーソル位置問い合わせに応答しながら  
    - 出力をすべて収集し  
    - 終了コードと出力を `CodexCliOutput` として返す非同期関数です（`L56-127`）。

---

## 3. 公開 API と詳細解説

### 3.1 型一覧（構造体・列挙体など）

このファイル内で定義される主な型と、使用している外部型の一覧です。

#### このファイルで定義される型

| 名前 | 種別 | 役割 / 用途 | 根拠 |
|------|------|-------------|------|
| `CodexCliOutput` | 構造体 | `codex` CLI 実行結果の終了コードと結合された出力文字列を保持します。 | `tui/tests/suite/no_panic_on_startup.rs:L51-54, L123-126` |

- `CodexCliOutput` には `exit_code: i32` と `output: String` の 2 フィールドがあります（`L51-54`）。

#### このファイルで使用される主な外部型（定義は別ファイル）

| 名前 | 種別 | 役割 / 用途（このファイルから分かる範囲） | 根拠 |
|------|------|-------------------------------------------|------|
| `codex_utils_pty::SpawnedProcess` | 構造体 | `spawn_pty_process` の戻り値であり、`session`・`stdout_rx`・`stderr_rx`・`exit_rx` をフィールドとして持つ PTY 上のプロセスハンドルです。 | 構造体パターンでの分解から（`L78-83`） |
| `codex_utils_pty::TerminalSize` | 構造体 | PTY の端末サイズ設定に使用されるデフォルト値。詳細は不明です。 | `TerminalSize::default()` 呼び出し（`L74-75`） |
| `tokio::sync::broadcast::Receiver<T>` | 構造体 | `stdout_rx`・`stderr_rx`・`exit_rx` の型と推測されるブロードキャスト受信チャネル。`RecvError::Closed` や `Lagged` が扱われていることから推測されます。具体的な型パラメータはこのファイルからは特定できません。 | `RecvError::Closed` 等の使用（`L101-102`） |

> 外部型の詳細なフィールドやメソッド、正確な型パラメータはこのチャンクには現れないため不明です。

---

### 3.2 関数詳細

このファイルには 2 つの関数（うち 1 つはテスト関数）が定義されています。

#### `malformed_rules_should_not_panic() -> anyhow::Result<()>`

**概要**

- Codex CLI の回帰テストであり、`CODEx_HOME` の `rules` が**誤ってファイルになっている**状態でも、CLI が起動時にパニックせず、適切なエラーを表示して終了することを検証します（`L7-10, L18-21, L38-47`）。

**属性**

- 非同期テスト: `#[tokio::test]` により Tokio ランタイム下で実行されます（`L8-10`）。
- フレークテストとして一時的に無効化: `#[ignore = "TODO(mbolin): flaky"]` により、通常の `cargo test` 実行ではスキップされます（`L9`）。

**引数**

- なし。

**戻り値**

- `anyhow::Result<()>`（`L10`）  
  - `Ok(())`: テストが正常に完了し、すべてのアサーションが通った場合。  
  - `Err(_)`: テスト中に発生した I/O エラーや `run_codex_cli` の失敗などをラップしたエラー。

**内部処理の流れ（アルゴリズム）**

1. **Windows 環境では即座に成功扱いで終了**  
   - `run_codex_cli()` が Windows 上では PTY の制約により動かないため、`cfg!(windows)` が真であれば `Ok(())` を返します（`L11-14`）。
2. **一時ディレクトリの作成と `CODEx_HOME` の設定**  
   - `tempfile::tempdir()` で一時ディレクトリを作成し、そのパスを `codex_home` として使用します（`L16-17`）。
3. **壊れたルール構成の作成**  
   - `codex_home/rules` に文字列 `"rules should be a directory not a file"` を書き込みます。  
     `rules` は本来ディレクトリであるべきところ、あえてファイルとして作成しています（`L18-21`）。
4. **設定ファイル `config.toml` の生成**  
   - 実行時のカレントディレクトリ `cwd` を取得（`L25`）。  
   - `model_provider = "ollama"`（ローカルプロバイダ）と、現在のプロジェクトを `trusted` とする設定を含む TOML を組み立てます（`L26-35`）。  
     コメントにより、OpenAI 認証プロンプトを出さないためのローカルプロバイダ選択であることが示されています（`L28-29`）。  
   - この内容を `codex_home/config.toml` に書き込みます（`L36`）。
5. **CLI の起動と結果の取得**  
   - `run_codex_cli(codex_home, cwd).await?` を呼び出し、終了コードと出力を `CodexCliOutput` として受け取ります（`L38-39`）。
6. **終了コードとエラーメッセージの検証**  
   - 終了コードが 0 ではないこと（非ゼロ終了）をアサートします（`L38-39`）。  
   - 出力に  
     - `"ERROR: Failed to initialize codex:"`  
     - `"failed to read rules files"`  
     の 2 つの文字列が含まれていることを `assert!` で検証します（`L40-47`）。
7. **テスト成功**  
   - すべてのアサーションが通れば `Ok(())` を返します（`L48`）。

**Examples（使用例）**

この関数自体は `#[tokio::test]` によりテストランナーから直接呼び出されます。利用者が明示的に呼び出すケースは想定されていません（`L8-10`）。

**Errors / Panics**

- `Err` を返しうる状況（いずれも `?` 演算子で伝播）:
  - 一時ディレクトリ作成の失敗（`tempfile::tempdir()`、`L16`）。
  - ファイル書き込み失敗（`std::fs::write` 2箇所、`L18-21, L36`）。
  - カレントディレクトリ取得失敗（`std::env::current_dir()`、`L25`）。
  - `run_codex_cli` 内で発生するあらゆる `anyhow::Error`（`L38-39`）。
- パニックの可能性:
  - この関数内に `unwrap` や `expect` はなく、明示的な `panic!` も存在しないため、このテスト自体がパニックを起こすのは通常 `assert!` / `assert_ne!` によるテスト失敗時のみです（`L39-47`）。

**Edge cases（エッジケース）**

- **Windows 環境**: 即座に `Ok(())` を返し、`run_codex_cli` は呼ばれません（`L11-14`）。
- **`codex` バイナリ不在 / 起動不能**: `run_codex_cli` が `Err` を返し、テストは失敗します（`L38-39, L60, L68-76`）。
- **CLI がメッセージを変更した場合**: 期待する文字列が出力に含まれなくなり、`assert!` が失敗します（`L40-47`）。

**使用上の注意点**

- この関数はテスト用であり、ライブラリコードから呼び出すことは想定されていません。
- 実行には `codex` バイナリと PTY サポート、Tokio ランタイムが必要です（`L8-10, L60, L68-76`）。
- 出力の検証は文字列部分一致で行っているため、メッセージが変化しやすい実装ではテストのメンテナンスが必要になります（`L40-47`）。

---

#### `run_codex_cli(codex_home: impl AsRef<Path>, cwd: impl AsRef<Path>) -> anyhow::Result<CodexCliOutput>`

**概要**

- 指定された `codex_home` とカレントディレクトリ `cwd` を用いて `codex` CLI バイナリを PTY 上で起動し、  
  - PTY からの標準出力・標準エラーを統合して収集し  
  - TUI が発行するカーソル位置問い合わせ（ESC[6n）に応答し  
  - プロセス終了まで監視した上で  
  終了コードと結合された出力を `CodexCliOutput` として返す非同期ヘルパー関数です（`L56-127`）。

**引数**

| 引数名 | 型 | 説明 | 根拠 |
|--------|----|------|------|
| `codex_home` | `impl AsRef<Path>` | `CODEX_HOME` 環境変数として CLI に渡されるディレクトリパス。`AsRef<Path>` により `&Path` や `PathBuf` など柔軟な型を受け取れます。 | `tui/tests/suite/no_panic_on_startup.rs:L56-58, L61-65` |
| `cwd` | `impl AsRef<Path>` | CLI プロセスのカレントディレクトリとして利用されるパス。テストでは実行時の `current_dir` が渡されています。 | `L56-59, L25, L38` |

**戻り値**

- `anyhow::Result<CodexCliOutput>`（`L56-59, L123-126`）  
  - `Ok(CodexCliOutput { exit_code, output })`  
    - `exit_code`: `codex` プロセスの終了コード（`L109-111, L123-125`）。  
    - `output`: プロセスの標準出力と標準エラーを結合し、UTF-8 としてデコードした文字列（`L77-85, L117-120, L122-126`）。
  - `Err(_)`: プロセス起動失敗、PTy 操作の失敗、タイムアウトなどを含む様々なエラー。

**内部処理の流れ（アルゴリズム）**

1. **`codex` バイナリのパス取得**  
   - `codex_utils_cargo_bin::cargo_bin("codex")?` で `codex` 実行ファイルへのパスを取得し、失敗時は `Err` を返します（`L60`）。
2. **環境変数マップの構築**  
   - 空の `HashMap<String, String>` を作り（`L61`）、  
     `CODEX_HOME` を `codex_home` の文字列表現で設定します（`L62-65`）。
3. **CLI 起動引数の設定**  
   - `args = ["-c", "analytics.enabled=false"]` を作成し、起動時に CLI に渡します（`L67`）。  
     設定キーから、解析ログなどの analytics を無効化していると推測されますが、実際の意味はこのファイルからは断定できません。
4. **PTY 上で `codex` プロセスを起動**  
   - `codex_utils_pty::spawn_pty_process` に  
     - バイナリパス  
     - 引数  
     - カレントディレクトリ `cwd`  
     - 環境変数マップ `env`  
     - `None`（追加設定用オプションと思われますが詳細不明）  
     - 端末サイズのデフォルト値 `TerminalSize::default()`  
     を渡して非同期起動し、`SpawnedProcess` を受け取ります（`L68-76`）。
5. **出力バッファとチャネルの準備**  
   - バイト列を蓄積する `Vec<u8>` を `output` として初期化（`L77`）。  
   - `SpawnedProcess` を分解して `session`, `stdout_rx`, `stderr_rx`, `exit_rx` を取得（`L78-83`）。  
   - 標準出力と標準エラーの受信チャネルを `combine_output_receivers` で統合し、`output_rx` とします（`L84`）。  
   - 終了コード通知用チャネル `exit_rx` をミュータブル変数として保持します（`L85`）。  
   - TUI への書き込み用送信ハンドル `writer_tx` を `session.writer_sender()` から取得します（`L86`）。
6. **タイムアウト付きでプロセス終了を待つ（非同期ループ）**  
   - `timeout(Duration::from_secs(10), async { ... }).await` で、最大 10 秒間プロセスの終了を待ちつつ出力を読みます（`L87-88, L108`）。  
   - 非同期ブロック内では `loop` と `tokio::select!` を使って  
     - `output_rx.recv()`（新しい出力チャンク）  
     - `exit_rx`（プロセス終了通知）  
     を同時に待ちます（`L90-105`）。
7. **出力チャンクの処理と TUI プロトコル応答**  
   - `output_rx.recv()` が成功した場合（`Ok(chunk)`）:  
     - `chunk.windows(4).any(|w| w == b"\x1b[6n")` で、チャンク内に ESC[6n（カーソル位置問い合わせ）シーケンスが含まれるか検出（`L92-97`）。  
     - 含まれていれば、`writer_tx.send(b"\x1b[1;1R".to_vec()).await` で `ESC[1;1R` を送り、カーソルが `1;1` にいると応答します（`L97-98`）。  
       コメントにより、これが TUI 初期化をブロックしないための応答であることが分かります（`L88-89, L94-96`）。  
     - 受け取った `chunk` を `output` バッファに追記します（`L99-100`）。
   - `output_rx.recv()` が `Err(RecvError::Closed)` の場合:  
     - 出力チャネルが閉じたことを意味するため、`break exit_rx.await` で終了通知の受信に切り替え、ループを抜けます（`L101`）。
   - `output_rx.recv()` が `Err(RecvError::Lagged(_))` の場合:  
     - 過去のメッセージを取りこぼしただけなので、何もせずループ継続します（`L102`）。
   - `exit_rx` が先に解決した場合:  
     - `break result` で終了コード（またはエラー）を持ってループを抜けます（`L104-105`）。
8. **タイムアウト・チャネルエラーの処理**  
   - `exit_code_result` は  
     - `Ok(Ok(code))`: 正常に終了コードを取得できた場合（`L109-110`）。  
     - `Ok(Err(err))`: 終了チャネルでエラーが発生した場合。（`L111`）。  
     - `Err(_)`: 10 秒タイムアウトに到達した場合（`L112-115`）。  
   - マッチで処理:  
     - `Ok(Ok(code))` の場合のみ `exit_code` に `code` をセット（`L109-110`）。  
     - `Ok(Err(err))` は `Err(err.into())` として戻り値のエラーにします（`L111`）。  
     - `Err(_)`（タイムアウト）では `session.terminate()` でプロセスを強制終了し、`anyhow::bail!` で「timed out waiting for codex CLI to exit」というエラーを返します（`L112-115`）。
9. **終了直前に残っている出力のドレイン**  
   - 終了通知と競合して遅れて到着したチャンクを `output_rx.try_recv()` で非ブロッキングに読み尽くし、`output` に追記します（`L117-120`）。
10. **バイト列から UTF-8 文字列への変換と結果構築**  
    - `String::from_utf8_lossy(&output)` で UTF-8 へのデコードを行い、無効なバイト列は置換文字に変換します（`L122`）。  
    - `CodexCliOutput { exit_code, output: output.to_string() }` を `Ok` で返します（`L123-126`）。

**Examples（使用例）**

ファイル内での実際の使用例（テストからの呼び出し）がそのまま代表的です。

```rust
// テスト関数から run_codex_cli を呼び出して CLI の振る舞いを検証する例
async fn example_use() -> anyhow::Result<()> {
    // 一時ディレクトリなどを用意した上で codex_home と cwd を決める
    let tmp = tempfile::tempdir()?;                                      // 一時ディレクトリを作成
    let codex_home = tmp.path();                                         // CODEX_HOME に使うパス
    let cwd = std::env::current_dir()?;                                  // プロセスのカレントディレクトリ

    // Codex CLI を PTY 上で起動し、終了コードと出力を取得
    let CodexCliOutput { exit_code, output } =
        run_codex_cli(codex_home, cwd).await?;                           // 非同期で CLI を実行

    // 終了コードや出力内容をテストする
    println!("exit_code = {exit_code}, output = {output}");
    Ok(())
}
```

> 上記は `malformed_rules_should_not_panic` の呼び出しパターン（`L38-39`）を簡略化した例です。

**Errors / Panics**

- `Err` を返しうる主な状況:
  - `codex_utils_cargo_bin::cargo_bin("codex")` の失敗（`codex` バイナリが存在しない/実行不可などと推測されますが、このファイルからは詳細不明）（`L60`）。
  - `codex_utils_pty::spawn_pty_process` の失敗（PTY 起動失敗等）（`L68-76`）。
  - 出力ループ内での `exit_rx` の `Err(err)`（具体的なエラー内容は不明）（`L111`）。
  - 10 秒以内に CLI が終了しなかった場合のタイムアウト（`L87-88, L112-115`）。
- パニックの可能性:
  - コード中に `unwrap` や `expect` はなく、標準ライブラリ呼び出しも通常の使用範囲にあるため、パニックを引き起こす明示的な箇所は見当たりません。

**Edge cases（エッジケース）**

- **出力が非常に少ない / 空の場合**  
  - `chunk.windows(4)` は長さ 4 未満のスライスに対しても空イテレータを返すため、安全に `any` を呼び出せます（`L96`）。  
  - 出力がなくても `exit_rx` から終了コードが届けば正常に終了します（`L91-105, L109-110`）。
- **出力チャネルのクローズ**  
  - `stdout`/`stderr` のブロードキャストチャネルが閉じた場合は、`RecvError::Closed` として検出し、`exit_rx.await` に切り替えてからループを抜けます（`L101`）。
- **出力のロス (`RecvError::Lagged`)**  
  - メッセージの「取りこぼし」は `RecvError::Lagged(_)` で検出されますが、特に補償せず無視してループを継続します（`L102`）。  
  - そのため、非常に大量の出力があった場合、一部は `output` に蓄積されない可能性があります。
- **プロセスがハングする場合**  
  - 10 秒間終了コードが届かないとタイムアウトとみなし、`session.terminate()` でプロセスを強制終了します（`L87-88, L112-114`）。
- **UTF-8 でない出力**  
  - `String::from_utf8_lossy(&output)` により、UTF-8 として不正なバイトは置換文字に変換されます（`L122`）。  
  - その結果、バイナリデータなどは正確に再現されませんが、このテストではテキストメッセージの包含チェックのみを行っているため、実質的な影響は少ないと考えられます（`L40-47`）。

**使用上の注意点**

- 呼び出し元は **Tokio ランタイム** 上にいる必要があります（`async fn` かつ内部で `tokio::select!` や `timeout` を使用しているため、`L56-59, L87-108`）。
- `codex` バイナリがパス上に存在し、`codex_utils_cargo_bin::cargo_bin("codex")` で解決可能であることが前提です（`L60`）。
- `codex_home` の中身（`rules` ディレクトリや `config.toml` など）は呼び出し前に整備しておく必要があります。関数自体はそれらを作成しません（このファイルではテスト側で作成しています、`L18-21, L36`）。
- 出力が非常に大量になるユースケースでは、  
  - `RecvError::Lagged` によるロス  
  - `Vec<u8>` によるバッファのメモリ使用量  
  への配慮が必要です（`L77, L92-103`）。

---

### 3.3 その他の関数

このファイルには、上記以外の補助的な関数は定義されていません。

---

## 4. データフロー

このテストにおける典型的なデータフローを、Codex CLI の起動から結果検証までのシーケンスとして整理します。

```mermaid
sequenceDiagram
    participant Test as malformed_rules_should_not_panic (L10-49)
    participant Run as run_codex_cli (L56-127)
    participant CargoBin as cargo_bin("codex") (外部, L60)
    participant PTY as spawn_pty_process (外部, L68-76)
    participant Session as session (PTY セッション, L78-86)
    participant CLI as codex バイナリ (外部プロセス)
    participant TUI as TUI 内部 (カーソル問い合わせ, L94-98)

    Test->>Test: 一時ディレクトリ作成・rules ファイル作成 (L16-21)
    Test->>Test: config.toml 作成 (L25-36)
    Test->>Run: run_codex_cli(codex_home, cwd).await (L38-39)

    Run->>CargoBin: cargo_bin("codex") (L60)
    CargoBin-->>Run: codex バイナリパス (L60)

    Run->>PTY: spawn_pty_process(path, args, cwd, env, None, TerminalSize::default()) (L68-76)
    PTY->>CLI: codex プロセスを PTY 上で起動
    PTY-->>Run: SpawnedProcess { session, stdout_rx, stderr_rx, exit_rx } (L78-83)

    Run->>Run: stdout/stderr を combine_output_receivers で統合 (L84)
    loop Run->>Run: select! で output_rx.recv() と exit_rx を待機 (L91-105)
        alt 出力チャンク受信 (Ok(chunk)) (L92-100)
            CLI->>TUI: ESC[6n (カーソル位置問い合わせ) を出力
            Run->>Run: chunk 内に ESC[6n があるか windows(4) で検査 (L96)
            alt ESC[6n が含まれる
                Run->>Session: writer_tx.send(ESC[1;1R) でカーソル位置を応答 (L97-98)
            end
            Run->>Run: chunk を output バッファに追記 (L99-100)
        else 出力チャネルクローズ (Closed) (L101)
            Run->>Run: exit_rx.await してループ終了 (L101)
        else 出力ロス (Lagged) (L102)
            Run->>Run: 何もせずループ継続
        else exit_rx に終了コードが届く (L104-105)
            Run->>Run: result を受信してループ終了
        end
    end

    Run->>Run: timeout(10秒) により exit_code_result を判定 (L87-88, L109-116)
    alt 正常終了 (Ok(Ok(code))) (L109-110)
        Run->>Run: exit_code に code をセット
    else 終了チャネルエラー (Ok(Err(err))) (L111)
        Run-->>Test: Err(err) として早期リターン
    else タイムアウト (Err(_)) (L112-115)
        Run->>Session: session.terminate() でプロセス強制終了 (L113)
        Run-->>Test: Err("timed out ...") を返す (L114-115)
    end

    Run->>Run: output_rx.try_recv() で残り出力をドレイン (L117-120)
    Run->>Run: String::from_utf8_lossy(&output) で文字列化 (L122)
    Run-->>Test: CodexCliOutput { exit_code, output } (L123-126)

    Test->>Test: exit_code と output に対してアサーション (L38-47)
```

この図から分かるポイント:

- **非同期並行処理**: `tokio::select!` により、「出力の受信」と「終了コードの受信」を並行で待ちます（`L91-105`）。
- **TUI プロトコル対応**: 出力中に ESC[6n が含まれる場合にのみ ESC[1;1R を返しているため、必要最小限の TUI プロトコル実装に留めています（`L94-99`）。
- **タイムアウト安全性**: CLI がハングした場合でも 10 秒でタイムアウトし、プロセスを強制終了することでテスト自体が無限にブロックしない設計です（`L87-88, L112-115`）。

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

`run_codex_cli` を用いて CLI を起動し、その結果を検証する典型的なフローは次のようになります（`L38-39, L56-127`）。

```rust
// Tokio ランタイム上で動作する非同期関数の例
async fn test_codex_cli() -> anyhow::Result<()> {
    // CODEX_HOME 用に一時ディレクトリを作成する
    let tmp = tempfile::tempdir()?;                                      // 一時ディレクトリ
    let codex_home = tmp.path();                                         // CODEX_HOME のパス

    // CLI を実行するカレントディレクトリを決める
    let cwd = std::env::current_dir()?;                                  // プロジェクトルートなど

    // 必要に応じて codex_home 内に設定ファイルやルールを作成する
    // （本ファイルのテストでは rules ファイルや config.toml を作成しています, L18-21, L36）

    // Codex CLI を PTY 上で実行し、終了コードと出力を取得する
    let CodexCliOutput { exit_code, output } =
        run_codex_cli(codex_home, cwd).await?;                           // 非同期呼び出し

    // 結果を検証する
    assert_eq!(0, exit_code, "CLI should exit successfully.");           // 終了コードをチェック
    assert!(output.contains("some expected message"),                    // 出力メッセージをチェック
            "unexpected output: {output}");

    Ok(())
}
```

### 5.2 よくある使用パターン

1. **特定のエラーパスの検証**

   - `codex_home` の中身（`rules` の構造や `config.toml`）を意図的に壊した状態で `run_codex_cli` を呼び出し、エラーコードやエラーメッセージを検証する。  
     本ファイルのテストもこのパターンです（`L18-21, L36, L38-47`）。

2. **正常起動のスモークテスト**

   - 正しい `rules` ディレクトリと `config.toml` を用意し、起動時に TUI が初期化され、一定のメッセージ（例: ヘルプやバージョン情報）が現れることを確認するために利用する、という形も考えられます。  
     ただし、そのようなテストはこのチャンクには現れません。

3. **長時間実行するコマンドの検証**

   - 現状の実装では 10 秒でタイムアウトするため（`L87-88`）、長時間実行されるコマンドを検証したい場合はタイムアウト値の調整や外からの終了トリガーが必要になる可能性があります。

### 5.3 よくある間違い

この関数を再利用するときに起こり得る誤用と、その修正例です。

```rust
// 間違い例: Tokio ランタイム外で .await を使おうとしている
//
// fn wrong_use() {
//     let tmp = tempfile::tempdir().unwrap();
//     let codex_home = tmp.path();
//     let cwd = std::env::current_dir().unwrap();
//
//     // コンパイルエラー: 非 async 関数内で .await は使えない
//     let result = run_codex_cli(codex_home, cwd).await;
// }

// 正しい例: Tokio ランタイム上の async コンテキストから呼び出す
#[tokio::test]
async fn correct_use() -> anyhow::Result<()> {
    let tmp = tempfile::tempdir()?;                                      // 一時ディレクトリ
    let codex_home = tmp.path();
    let cwd = std::env::current_dir()?;

    let CodexCliOutput { exit_code, output } =
        run_codex_cli(codex_home, cwd).await?;                           // async コンテキストで await

    // 必要な検証を行う
    assert_ne!(0, exit_code);
    Ok(())
}
```

その他の注意:

- `run_codex_cli` は `codex_home` の中身を整える責務を持たないため、事前に必要なファイルを用意しないとテストが意図しない理由で失敗する可能性があります（`L18-21, L36`）。
- Windows では PTY の制約があるため、このテストと同様に OS 依存でスキップするロジックを用意する必要があるかもしれません（`L11-14`）。

### 5.4 使用上の注意点（まとめ）

- **前提条件**
  - Tokio ランタイム上で実行されること（`#[tokio::test]` など）（`L8-10, L56-59`）。
  - `codex` バイナリがテスト環境でビルドされており、`codex_utils_cargo_bin::cargo_bin("codex")` から参照可能であること（`L60`）。
  - `codex_home` の内容（`rules`、`config.toml` など）がテストの意図に沿って準備されていること（`L18-21, L36`）。

- **禁止事項 / 避けるべきパターン**
  - `run_codex_cli` を同期コンテキストから `.await` せずに呼び出すこと。
  - 極端に長時間実行する CLI コマンドに対してタイムアウト値を調整せずに使うこと（10 秒で強制終了されます、`L87-88, L112-115`）。

- **エラー・パニック条件**
  - PTY 起動失敗、CLI バイナリ不在、タイムアウトなど多くのケースで `Err` が返され、テストは失敗します（`L60, L68-76, L87-88, L109-116`）。
  - テスト内の `assert!` 失敗はパニックとして扱われますが、これは通常のテスト失敗です（`L39-47`）。

- **パフォーマンス上の注意**
  - 出力はすべて `Vec<u8>` に蓄積してから文字列化するため、非常に大量の出力を行うテストではメモリ使用量に注意が必要です（`L77, L117-122`）。
  - 非同期のループと `select!` により CPU バウンドではなく I/O バウンドな設計になっており、通常のテスト規模では特段の問題は想定しにくい構造です（`L87-105`）。

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

例として、「他の起動エラーケース」を検証するテストを追加する場合の大まかな手順です。

1. **新しいテスト関数の追加**
   - `malformed_rules_should_not_panic` と同じファイルに `#[tokio::test]` を付与した新しい関数を追加します（`L8-10` を参考）。
2. **`codex_home` と `cwd` の準備**
   - `tempfile::tempdir()` と `std::env::current_dir()` を利用して、テストのシナリオに応じたディレクトリ構造を用意します（`L16-17, L25`）。
3. **`codex_home` 内のファイル/ディレクトリセットアップ**
   - `std::fs::write` や他のファイル操作を使い、テスト対象の構成（正常系/異常系）を構築します（`L18-21, L36`）。
4. **`run_codex_cli` の呼び出し**
   - 作成した `codex_home` と `cwd` を渡して `run_codex_cli` を呼び、`CodexCliOutput` を取得します（`L38-39`）。
5. **結果の検証**
   - `exit_code` と `output` に対して `assert_eq!` や `assert!` でシナリオに応じた検証を行います（`L39-47`）。

### 6.2 既存の機能を変更する場合

`run_codex_cli` やテストの振る舞いを変更する際に注意すべき点です。

- **`run_codex_cli` のタイムアウト値を変更したい場合**
  - `Duration::from_secs(10)` を他の値に変えることになりますが（`L87`）、テスト全体の実行時間と CLI の起動時間のバランスを考慮する必要があります。
- **TUI のプロトコル応答を拡張/変更したい場合**
  - 現在は ESC[6n のみを検出し ESC[1;1R で応答しています（`L94-99`）。  
    他の制御シーケンスに対応する場合は、`chunk` の解析ロジックを増やすことになります。  
    この際、処理コストと複雑さが増えるため、テストが重くなりすぎないよう注意が必要です。
- **出力ロス（`RecvError::Lagged`）の扱いを変えたい場合**
  - 現在は無視していますが（`L102`）、ロスを許容しないテストでは警告ログを出す、テスト失敗にするなどの方針に変更することもできます。
- **契約（前提条件・返り値の意味）の確認**
  - `run_codex_cli` は「終了コードと出力を返す」ことが契約です（`L109-111, L123-126`）。  
    ここを変更する場合は、これを前提としているすべてのテスト（`malformed_rules_should_not_panic` を含む）の修正が必要になります（`L38-39`）。

---

## 7. 関連ファイル

このファイルと密接に関係する（または、利用している）外部コンポーネントを整理します。

| パス / シンボル | 役割 / 関係 | 根拠 |
|----------------|------------|------|
| `codex_utils_cargo_bin::cargo_bin` | `"codex"` バイナリへのパスを取得するヘルパー関数と推測されます。`run_codex_cli` はこれを通じてテスト対象の CLI を起動します。実装はこのチャンクには現れません。 | 呼び出しと戻り値の扱いから（`tui/tests/suite/no_panic_on_startup.rs:L60`） |
| `codex_utils_pty::spawn_pty_process` | 指定したプログラムを PTY 上で起動し、`SpawnedProcess` を返す関数です（と解釈されます）。このテストでは Codex CLI の TUI を擬似端末上で動かすために使用されています。 | 呼び出し引数と戻り値分解から（`L68-76, L78-83`） |
| `codex_utils_pty::combine_output_receivers` | 標準出力と標準エラーの受信チャネルをまとめるユーティリティ関数と推測されます。 | 使用箇所から（`L84`） |
| `tokio` クレート (`#[tokio::test]`, `select!`, `time::timeout`) | 非同期テストランナーと非同期制御の基盤を提供します。 | デコレータとマクロ呼び出しから（`L8, L4-5, L87-88, L91-105`） |
| `tempfile` クレート | 一時ディレクトリの作成に使用され、`CODEx_HOME` のベースパスとして利用されています。 | `tempfile::tempdir()` 呼び出しから（`L16`） |
| その他の TUI/CLI 実装ファイル | Codex CLI 自体の実装（TUI 部分やルール読み取りロジックなど）は、このチャンクには現れません。そのため、ルールディレクトリの詳細な仕様や TUI の内部動作は不明です。 | 該当コードが存在しないため「不明」と明示 |

このファイルは、あくまで「統合テスト」と「CLI 起動のヘルパー」であり、Codex 本体のロジックには直接関与していない点に注意が必要です。
