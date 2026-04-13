# exec/tests/suite/ephemeral.rs コード解説

## 0. ざっくり一言

`exec/tests/suite/ephemeral.rs` は、CLI ツールが「通常モード」と「ephemeral モード」で実行されたときに、`sessions` ディレクトリにセッションのロールアウトファイル（`.jsonl`）を生成するかどうかを検証するテストモジュールです（`#[test]` 関数と補助関数から構成）（exec/tests/suite/ephemeral.rs:L8-52）。

---

## 1. このモジュールの役割

### 1.1 概要

- このモジュールは、CLI 実行時の **セッションロールアウトファイルの永続化有無** を確認するために存在し、テスト用ハーネスとファイルシステム検査ロジックを提供します（exec/tests/suite/ephemeral.rs:L8-20, L22-52）。
- 通常モードでは `.jsonl` ファイルが 1 つ生成されること、`--ephemeral` フラグ付き実行では生成されないことをテストで検証します（exec/tests/suite/ephemeral.rs:L22-36, L38-52）。

### 1.2 アーキテクチャ内での位置づけ

このモジュールはテストコードであり、以下のコンポーネントに依存しています。

- テストハーネスを構築する `test_codex_exec`（外部クレート `core_test_support`）（exec/tests/suite/ephemeral.rs:L4-5, L24, L40）。
- テスト用フィクスチャファイルへのパスを解決するマクロ `find_resource!`（クレート `codex_utils_cargo_bin`）（exec/tests/suite/ephemeral.rs:L4, L25, L41）。
- `sessions` ディレクトリ以下の `.jsonl` ファイルを再帰的に数えるための `walkdir::WalkDir`（exec/tests/suite/ephemeral.rs:L6, L14-19）。
- CLI 本体（`test.cmd()` でラップされている外部プロセス; 型名や実装はこのチャンクには現れません）（exec/tests/suite/ephemeral.rs:L27-32, L43-49）。

これらの関係を簡略化した依存関係図は以下の通りです。

```mermaid
graph TD
    subgraph "ephemeral.rs (L1-52)"
        E[テストモジュール<br/>ephemeral.rs]
        F1[関数<br/>session_rollout_count (L8-20)]
        T1[テスト<br/>persists_rollout_file_by_default (L22-36)]
        T2[テスト<br/>does_not_persist_rollout_file_in_ephemeral_mode (L38-52)]
    end

    T1 -->|呼び出し| F1
    T2 -->|呼び出し| F1

    E -->|use| FindRes[マクロ find_resource!<br/>(codex_utils_cargo_bin)]
    E -->|use| HarnessCtor[test_codex_exec<br/>(core_test_support)]
    F1 -->|use| WD[WalkDir<br/>(walkdir)]

    T1 -->|呼び出し| HarnessCtor
    T2 -->|呼び出し| HarnessCtor

    HarnessCtor --> Harness[テストハーネス<br/>(戻り値; 型名不明)]
    Harness -->|cmd()| Cmd[CLI コマンドオブジェクト]
    Cmd -->|env/arg/assert/code| CLI[CLI プロセス<br/>(外部; 実装不明)]

    F1 --> FS[ファイルシステム<br/>home_path()/sessions]
```

### 1.3 設計上のポイント

- **ファイルシステム操作を補助関数に集約**  
  `session_rollout_count` により、`sessions` ディレクトリ中の `.jsonl` ファイル数取得ロジックを一箇所にまとめています（exec/tests/suite/ephemeral.rs:L8-20）。
- **テストハーネス経由で CLI を外部プロセスとして扱う**  
  `test_codex_exec().cmd().env().arg().assert().code(0)` という形で、CLI プロセスを黒箱として扱い、終了コードのみを検証しています（exec/tests/suite/ephemeral.rs:L24, L27-32, L40, L43-49）。
- **エラー処理は Result とアサーションに委任**  
  テスト関数は `anyhow::Result<()>` を返し、リソース解決には `?` を用います。一方で CLI の終了コードやファイル数は `assert!` 系マクロで検証し、失敗時にはテストが panic する設計です（exec/tests/suite/ephemeral.rs:L23, L25, L35, L39, L41, L52）。
- **プラットフォーム条件付き**  
  ファイル先頭で `#![cfg(not(target_os = "windows"))]` が指定されており、このテストは Windows ではコンパイル／実行されません（exec/tests/suite/ephemeral.rs:L1）。

---

## 2. 主要な機能一覧

### 2.1 コンポーネントインベントリー（関数）

| 名前 | 種別 | 定義位置 | 役割 / 概要 |
|------|------|----------|-------------|
| `session_rollout_count` | 関数 | exec/tests/suite/ephemeral.rs:L8-20 | 指定された `home_path` 配下の `sessions` ディレクトリ中にある `.jsonl` ファイルの数を数える補助関数です。 |
| `persists_rollout_file_by_default` | テスト関数 (`#[test]`) | exec/tests/suite/ephemeral.rs:L22-36 | デフォルトモードで CLI を実行すると `.jsonl` ロールアウトファイルが 1 つ保存されることを検証します。 |
| `does_not_persist_rollout_file_in_ephemeral_mode` | テスト関数 (`#[test]`) | exec/tests/suite/ephemeral.rs:L38-52 | `--ephemeral` フラグ付きで実行した場合、ロールアウトファイルが保存されないことを検証します。 |

このファイル内で新たに定義されている構造体や列挙体はありません（exec/tests/suite/ephemeral.rs:L8-52）。

### 2.2 主要な機能（箇条書き）

- セッションファイル数カウント: `home_path/sessions` 以下の `.jsonl` ファイルを再帰的に数えます（exec/tests/suite/ephemeral.rs:L8-20）。
- デフォルトの永続化挙動テスト: 通常モードで CLI を実行したときに、セッションファイルが 1 つ存在することを確認します（exec/tests/suite/ephemeral.rs:L22-36）。
- ephemeral モードの非永続化テスト: `--ephemeral` 指定時にセッションファイルが生成されないことを確認します（exec/tests/suite/ephemeral.rs:L38-52）。

---

## 3. 公開 API と詳細解説

### 3.1 型一覧（構造体・列挙体など）

このファイル内には、新しく定義された構造体・列挙体・型エイリアスはありません（関数定義と `use` のみ）（exec/tests/suite/ephemeral.rs:L4-6, L8-52）。

### 3.2 関数詳細

#### `session_rollout_count(home_path: &std::path::Path) -> usize`

**概要**

- 引数で与えられた `home_path` の下にある `sessions` ディレクトリ配下の `.jsonl` ファイルを再帰的に列挙し、その数を返す補助関数です（exec/tests/suite/ephemeral.rs:L8-20）。
- ディレクトリが存在しない場合は 0 を返し、エラーにはなりません（exec/tests/suite/ephemeral.rs:L9-12）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `home_path` | `&std::path::Path` | テストハーネスが使用するホームディレクトリへのパスです。この関数はその配下の `sessions` サブディレクトリを対象とします（exec/tests/suite/ephemeral.rs:L8-9, L34, L51）。 |

**戻り値**

- 型: `usize`（exec/tests/suite/ephemeral.rs:L8, L19）。
- 意味: `home_path.join("sessions")` 以下に存在する、ファイルタイプかつファイル名が `.jsonl` で終わるエントリの個数です（exec/tests/suite/ephemeral.rs:L9, L14-19）。

**内部処理の流れ**

1. `home_path.join("sessions")` で `sessions` ディレクトリへのパスを生成します（exec/tests/suite/ephemeral.rs:L9）。
2. 該当ディレクトリが存在しない場合は、早期に `0` を返します（exec/tests/suite/ephemeral.rs:L10-12）。
3. 存在する場合、`WalkDir::new(sessions_dir)` で再帰ディレクトリイテレータを作成します（exec/tests/suite/ephemeral.rs:L14）。
4. `.into_iter()` でイテレータ化し、`.filter_map(Result::ok)` で `Result<DirEntry, Error>` から成功したエントリのみを取り出します（エラーは無視されます）（exec/tests/suite/ephemeral.rs:L15-16）。
5. `.filter(|entry| entry.file_type().is_file())` でファイルだけを残し、ディレクトリやその他のエントリを除外します（exec/tests/suite/ephemeral.rs:L17）。
6. `.filter(|entry| entry.file_name().to_string_lossy().ends_with(".jsonl"))` でファイル名が `.jsonl` で終わるものだけを残します（exec/tests/suite/ephemeral.rs:L18）。
7. `.count()` でフィルタリング後のエントリ数（`usize`）を返します（exec/tests/suite/ephemeral.rs:L19）。

**Examples（使用例）**

テスト関数内での典型的な使用例です。

```rust
// テストハーネスを初期化する
let test = test_codex_exec();                                   // exec/tests/suite/ephemeral.rs:L24, L40

// CLI を実行した後、ホームディレクトリを取得する
let home = test.home_path();                                    // exec/tests/suite/ephemeral.rs:L34, L51（呼び出し元）

// sessions ディレクトリ配下の .jsonl ファイル数を数える
let count = session_rollout_count(home);                        // exec/tests/suite/ephemeral.rs:L34, L51

assert_eq!(count, 1);                                           // 期待されるファイル数と比較（例）
```

この例のように、`home_path` にはテストハーネスから得られるディレクトリを渡し、結果は `assert_eq!` などで検証します。

**Errors / Panics**

- この関数は `Result` を返さず、内部でも `unwrap` 等を使用していません（exec/tests/suite/ephemeral.rs:L8-20）。  
  Rust の観点では、明示的なエラー伝播は行われず、基本的に panic もしない構造になっています。
- ただし、`WalkDir::new` のイテレーションで発生した I/O エラーは `filter_map(Result::ok)` により黙殺されます（exec/tests/suite/ephemeral.rs:L15-16）。  
  そのため、一部のファイルが読み取れない場合でもエラーにならず、単にカウントから除外されます。

**Edge cases（エッジケース）**

- `sessions` ディレクトリが存在しない場合: `0` を返します（exec/tests/suite/ephemeral.rs:L9-12）。
- ディレクトリは存在するが `.jsonl` ファイルが 1 つもない場合: フィルタ後の `.count()` が 0 となり、`0` を返します（exec/tests/suite/ephemeral.rs:L14-19）。
- `.jsonl` 以外の拡張子（例: `.txt`, `.log` 等）のファイルはカウントされません（exec/tests/suite/ephemeral.rs:L18）。
- サブディレクトリ内の `.jsonl` も、`WalkDir` により再帰的にカウント対象になります（`WalkDir` の仕様に基づく; 再帰であること自体は `WalkDir::new(...)` から推測できますが、このチャンク内に明示的な設定コードはありません）（exec/tests/suite/ephemeral.rs:L14）。

**使用上の注意点**

- エラーを無視してカウントするため、ファイルシステムエラーを検知したい用途では不足する可能性があります。テスト目的（「0 か 1 か」を見る）には簡潔ですが、一般用途への転用には注意が必要です（exec/tests/suite/ephemeral.rs:L15-16）。
- 過去のセッションファイルもすべてカウントされます。そのため、同じ `home_path` を複数のテストで共有し、古い `.jsonl` が残る場合にはテスト結果に影響する可能性があります。ただし、`home_path` がテストごとに分離されているかどうかは、このチャンクからは分かりません（exec/tests/suite/ephemeral.rs:L34, L51）。

---

#### `persists_rollout_file_by_default() -> anyhow::Result<()>`

**概要**

- デフォルトモードで CLI を実行した際に、セッションロールアウトファイルが 1 つ作成されることを検証するテストです（exec/tests/suite/ephemeral.rs:L22-36）。
- SSE 形式のレスポンスフィクスチャファイルを環境変数 `CODEX_RS_SSE_FIXTURE` で CLI に渡すことで、外部依存を固定しています（exec/tests/suite/ephemeral.rs:L25, L28）。

**引数**

- なし（テスト関数であり、引数は取りません）（exec/tests/suite/ephemeral.rs:L23）。

**戻り値**

- 型: `anyhow::Result<()>`（exec/tests/suite/ephemeral.rs:L23）。
- 意味: テスト内での I/O やリソース解決に失敗した場合に、そのエラーを呼び出し元（テストランナー）に返します。正常終了時は `Ok(())` を返します（exec/tests/suite/ephemeral.rs:L25, L35）。

**内部処理の流れ（アルゴリズム）**

1. テスト用 CLI ハーネスを生成します。  
   `let test = test_codex_exec();`（exec/tests/suite/ephemeral.rs:L24）。
2. テストで使用する SSE フィクスチャファイルのパスを `find_resource!` マクロで取得します。  
   `let fixture = find_resource!("tests/fixtures/cli_responses_fixture.sse")?;`（exec/tests/suite/ephemeral.rs:L25）。  
   `?` により、失敗時は即座に `Err` を返します。
3. ハーネスから CLI コマンドオブジェクトを取得し、環境変数と引数を設定して実行します（exec/tests/suite/ephemeral.rs:L27-32）。
   - `.env("CODEX_RS_SSE_FIXTURE", &fixture)` でフィクスチャパスを環境変数として設定。
   - `.arg("--skip-git-repo-check")` で Git リポジトリチェックをスキップ。
   - `.arg("default persistence behavior")` で CLI へのコマンド／プロンプト文字列を指定。
   - `.assert().code(0)` でプロセスの終了コードが 0 であることを検証。
4. 実行後、`session_rollout_count(test.home_path())` を呼び出し、セッションファイル数が 1 であることを `assert_eq!` で確認します（exec/tests/suite/ephemeral.rs:L34）。
5. `Ok(())` を返してテストを成功終了します（exec/tests/suite/ephemeral.rs:L35）。

**Examples（使用例）**

このテスト関数自体が使用例です。構造を抽象化すると次のようになります。

```rust
#[test]
fn example_persists_behavior() -> anyhow::Result<()> {
    // 1. テストハーネスを用意
    let test = test_codex_exec(); // exec/tests/suite/ephemeral.rs:L24

    // 2. フィクスチャファイルパスを取得
    let fixture = find_resource!("tests/fixtures/cli_responses_fixture.sse")?; // L25

    // 3. CLI を実行
    test.cmd()                                     // CLI コマンドオブジェクトを取得
        .env("CODEX_RS_SSE_FIXTURE", &fixture)     // 環境変数を設定
        .arg("--skip-git-repo-check")             // Git チェックをスキップ
        .arg("default persistence behavior")      // コマンド／プロンプト
        .assert()                                  // 実行＆アサーション準備
        .code(0);                                  // 終了コード 0 を期待（L27-32）

    // 4. セッションファイルが 1 つ生成されていることを検証
    assert_eq!(session_rollout_count(test.home_path()), 1); // L34

    Ok(()) // L35
}
```

**Errors / Panics**

- `find_resource!` 呼び出しでエラーが発生すると、`?` により `Err` が返され、テストが失敗します（exec/tests/suite/ephemeral.rs:L25）。
- `.assert().code(0)` で終了コードが 0 以外だった場合、内部で panic することが一般的です（`assert_cmd` に類似した API であると推測できますが、このチャンクには具体的な実装は現れません）（exec/tests/suite/ephemeral.rs:L27-32）。
- `assert_eq!(...)` が失敗した場合も panic し、テスト失敗となります（exec/tests/suite/ephemeral.rs:L34）。
- Rust 言語の観点では、I/O エラーは `Result` で扱い、論理的な期待値違反は `assert` による panic で表現されています。

**Edge cases（エッジケース）**

- フィクスチャファイルが見つからない／アクセス不能: `find_resource!` がエラーを返すと考えられ、それが `?` によりテスト失敗になります（exec/tests/suite/ephemeral.rs:L25）。  
  具体的なエラー型・条件はこのチャンクには現れません。
- CLI が異常終了（終了コード ≠ 0）した場合: `.code(0)` で検出され、テストが失敗します（exec/tests/suite/ephemeral.rs:L27-32）。
- `session_rollout_count` が 1 以外を返す場合（ファイルが 0 または 2 以上）: `assert_eq!` が失敗し、テスト失敗となります（exec/tests/suite/ephemeral.rs:L34）。

**使用上の注意点**

- このテストは、`home_path` の初期状態にセッションファイルが存在しない前提で書かれています（そうでない場合、カウントが 1 を超える可能性があります）。`home_path` の初期化方法は `test_codex_exec` の実装に依存しており、このチャンクからは確認できません（exec/tests/suite/ephemeral.rs:L24, L34）。
- `CODEX_RS_SSE_FIXTURE` 環境変数を設定しているため、CLI はこのフィクスチャに依存した動作をします。環境変数を設定し忘れるとテストパターンと異なる挙動になる可能性がありますが、その詳細はこのチャンクからは分かりません（exec/tests/suite/ephemeral.rs:L28）。

---

#### `does_not_persist_rollout_file_in_ephemeral_mode() -> anyhow::Result<()>`

**概要**

- `--ephemeral` フラグ付きで CLI を実行した場合に、セッションロールアウトファイルが生成されない（ファイル数が 0）の挙動を検証するテストです（exec/tests/suite/ephemeral.rs:L38-52）。

**引数**

- なし（テスト関数）（exec/tests/suite/ephemeral.rs:L39）。

**戻り値**

- 型: `anyhow::Result<()>`（exec/tests/suite/ephemeral.rs:L39）。
- 意味: フィクスチャ解決などの失敗を `Err` として返し、成功時は `Ok(())` を返します（exec/tests/suite/ephemeral.rs:L41, L52）。

**内部処理の流れ**

1. `test_codex_exec()` でテストハーネスを生成します（exec/tests/suite/ephemeral.rs:L40）。
2. `find_resource!` で SSE フィクスチャファイルパスを取得し、`?` でエラーを伝播します（exec/tests/suite/ephemeral.rs:L41）。
3. `test.cmd()` から CLI コマンドオブジェクトを取得し、以下を設定して実行します（exec/tests/suite/ephemeral.rs:L43-49）。
   - `.env("CODEX_RS_SSE_FIXTURE", &fixture)` でフィクスチャ指定。
   - `.arg("--skip-git-repo-check")` で Git チェックをスキップ。
   - `.arg("--ephemeral")` で ephemeral モードを有効化。
   - `.arg("ephemeral behavior")` でコマンド／プロンプトを指定。
   - `.assert().code(0)` で終了コード 0 を期待。
4. 実行後、`session_rollout_count(test.home_path())` が 0 を返すことを `assert_eq!` で検証します（exec/tests/suite/ephemeral.rs:L51）。
5. `Ok(())` を返して終了します（exec/tests/suite/ephemeral.rs:L52）。

**Examples（使用例）**

このテストを抽象化した例です。

```rust
#[test]
fn example_ephemeral_does_not_persist() -> anyhow::Result<()> {
    let test = test_codex_exec(); // L40
    let fixture = find_resource!("tests/fixtures/cli_responses_fixture.sse")?; // L41

    test.cmd()
        .env("CODEX_RS_SSE_FIXTURE", &fixture)
        .arg("--skip-git-repo-check")
        .arg("--ephemeral")                  // ephemeral モードを有効化（L46）
        .arg("ephemeral behavior")
        .assert()
        .code(0);                            // L43-49

    assert_eq!(session_rollout_count(test.home_path()), 0); // L51
    Ok(())
}
```

**Errors / Panics**

- `find_resource!` によるエラーは `?` で伝播します（exec/tests/suite/ephemeral.rs:L41）。
- CLI の終了コードが 0 でない場合、`.code(0)` のアサーションが失敗して panic します（exec/tests/suite/ephemeral.rs:L43-49）。
- `session_rollout_count` が 0 以外を返した場合、`assert_eq!` が失敗して panic します（exec/tests/suite/ephemeral.rs:L51）。

**Edge cases（エッジケース）**

- ephemeral モードにもかかわらず `.jsonl` ファイルが残る場合: テストが失敗し、ephemeral モードの仕様に反する挙動を検知できます（exec/tests/suite/ephemeral.rs:L46, L51）。
- `sessions` ディレクトリ自体が作られないケース: `session_rollout_count` により 0 が返るため、このテストは成功します（exec/tests/suite/ephemeral.rs:L9-12, L51）。

**使用上の注意点**

- このテストは、「ephemeral モードでは `.jsonl` が 1 つも存在しない」という挙動を仕様として固定します。将来的に「一時的なファイルは作るが終了時に削除する」など仕様が変わる場合、このテストの期待値を変更する必要があります（exec/tests/suite/ephemeral.rs:L46, L51）。
- `--ephemeral` 以外の追加フラグの組み合わせによる影響は、このテストからは分かりません。新しいオプションを導入する場合は、別途テストを追加するのが自然です。

---

### 3.3 その他の関数

- このファイルには、上記 3 つ以外の関数定義はありません（exec/tests/suite/ephemeral.rs:L8-52）。

---

## 4. データフロー

ここでは、`persists_rollout_file_by_default` テスト実行時の代表的なデータフローを示します（exec/tests/suite/ephemeral.rs:L22-36）。`does_not_persist_rollout_file_in_ephemeral_mode` もほぼ同様で、違いは CLI 引数に `--ephemeral` が追加される点です（exec/tests/suite/ephemeral.rs:L38-52）。

```mermaid
sequenceDiagram
    participant Runner as テストランナー
    participant T1 as persists_rollout_file_by_default<br/>(L22-36)
    participant HarnessCtor as test_codex_exec<br/>(外部; L24)
    participant Harness as テストハーネス<br/>(型名不明)
    participant Cmd as cmd() 戻り値<br/>CLI コマンド
    participant CLI as CLI プロセス<br/>(外部)
    participant Counter as session_rollout_count<br/>(L8-20)
    participant FS as ファイルシステム<br/>home_path()/sessions

    Runner ->> T1: テスト関数を実行
    T1 ->> HarnessCtor: test_codex_exec() 呼び出し (L24)
    HarnessCtor -->> T1: ハーネスを返す (Harness)

    T1 ->> T1: find_resource!(フィクスチャパス) (L25)

    T1 ->> Harness: 参照を保持 (test)
    T1 ->> Harness: cmd() 呼び出し (L27)
    Harness -->> Cmd: コマンドオブジェクトを返す

    T1 ->> Cmd: env(CODEX_RS_SSE_FIXTURE, fixture) (L28)
    T1 ->> Cmd: arg("--skip-git-repo-check") (L29)
    T1 ->> Cmd: arg("default persistence behavior") (L30)
    T1 ->> Cmd: assert().code(0) (L31-32)
    Cmd ->> CLI: プロセス起動 & 実行

    CLI ->> FS: home_path()/sessions に書き込み（推定; このチャンクには実装なし）

    T1 ->> Harness: home_path() を取得 (L34)
    T1 ->> Counter: session_rollout_count(home_path) 呼び出し (L34)
    Counter ->> FS: WalkDir で .jsonl ファイル数をカウント (L14-19)
    Counter -->> T1: カウント値 (期待: 1)

    T1 ->> T1: assert_eq!(count, 1) (L34)
    T1 -->> Runner: Ok(())
```

要点:

- CLI の具体的な実装はこのファイルには現れませんが、テストは「CLI 実行後に `home_path()/sessions` に `.jsonl` ファイルが存在するかどうか」を `session_rollout_count` 経由で検証しています（exec/tests/suite/ephemeral.rs:L34, L51）。
- ephemeral テストでは、上記フローの `arg("--ephemeral")` の有無と、最終的なカウント値の期待（1 vs 0）が異なります（exec/tests/suite/ephemeral.rs:L46, L51）。

---

## 5. 使い方（How to Use）

このモジュールはテストコードであるため、「使い方」は主に **同様のテストを追加する際のパターン** という意味になります。

### 5.1 基本的な使用方法

新しい CLI 挙動（例えば別のフラグによるセッションファイルの扱い）をテストしたい場合の基本フローは、既存テストと同様です。

```rust
#[test]
fn new_behavior_example() -> anyhow::Result<()> {
    // 1. テストハーネスを用意する
    let test = test_codex_exec(); // ハーネス作成（exec/tests/suite/ephemeral.rs:L24, L40）

    // 2. フィクスチャファイルのパスを取得する
    let fixture = find_resource!("tests/fixtures/cli_responses_fixture.sse")?; // L25, L41

    // 3. CLI を実行する
    test.cmd()                                      // CLI コマンドオブジェクト
        .env("CODEX_RS_SSE_FIXTURE", &fixture)      // SSE フィクスチャを環境変数で指定
        .arg("--skip-git-repo-check")              // 既存テストと同じ前提を維持
        .arg("--some-new-flag")                    // 新しいフラグ
        .arg("some behavior")                      // コマンド／プロンプト
        .assert()
        .code(0);                                  // 成功終了を期待

    // 4. セッションファイル数を検証する
    let count = session_rollout_count(test.home_path());
    // 期待値に応じてアサート
    assert_eq!(count, 1); // 例: 新フラグでもファイルを 1 つ保存する仕様

    Ok(())
}
```

### 5.2 よくある使用パターン

- **永続化有無の比較テスト**  
  - デフォルトモード: `assert_eq!(session_rollout_count(test.home_path()), 1);`（exec/tests/suite/ephemeral.rs:L34）。
  - ephemeral モード: `assert_eq!(session_rollout_count(test.home_path()), 0);`（exec/tests/suite/ephemeral.rs:L51）。
- **同一フィクスチャ＋異なるフラグ**  
  両テストとも同じ SSE フィクスチャを使用し、CLI 引数だけを変えることで挙動の差分を検証しています（exec/tests/suite/ephemeral.rs:L25, L28-30, L41, L43-47）。

### 5.3 よくある間違い

このファイルから推測できる範囲で、起こり得る誤用と、その対策を示します。

```rust
// 誤り例: フィクスチャ環境変数を設定しない
test.cmd()
    // .env("CODEX_RS_SSE_FIXTURE", &fixture) // 抜けている
    .arg("--skip-git-repo-check")
    .arg("some behavior")
    .assert()
    .code(0);

// 正しい例: 既存テストと同様にフィクスチャを設定する
test.cmd()
    .env("CODEX_RS_SSE_FIXTURE", &fixture) // exec/tests/suite/ephemeral.rs:L28, L44
    .arg("--skip-git-repo-check")
    .arg("some behavior")
    .assert()
    .code(0);
```

- フィクスチャ環境変数を設定しないと、CLI がどのような外部リソースに依存するかはこのチャンクからは分かりませんが、既存テストとは前提条件が変わってしまいます（exec/tests/suite/ephemeral.rs:L28, L44）。
- `session_rollout_count` に `test.home_path()` 以外のパスを渡すと、このテストスイートが前提とするディレクトリ構造と異なる場所を数えることになり、意図通りの検証にならない可能性があります（exec/tests/suite/ephemeral.rs:L34, L51）。

### 5.4 使用上の注意点（まとめ）

- このモジュールのテストは、`home_path` がテスト毎に分離されている、あるいは毎回クリーンな状態から始まることを前提としているように見えますが、その保証は `test_codex_exec` の実装に依存しており、このチャンクからは確認できません（exec/tests/suite/ephemeral.rs:L24, L34, L40, L51）。
- `session_rollout_count` はファイルシステムエラーを無視してカウントするため、「ファイルが存在しない」のか「I/O エラーで読めなかった」のかを区別しません。テストとしては単純ですが、問題切り分けの観点ではログなど他の情報が必要になる可能性があります（exec/tests/suite/ephemeral.rs:L15-16）。
- Rust の並行テスト実行（`cargo test` のデフォルト）は、同じディレクトリを共有するテスト同士で競合を引き起こす可能性があります。このファイルからは、`test_codex_exec` がディレクトリをどう分離しているかは分かりません。複数テストが同じ `home_path` を共有する設計変更を行う場合は、ファイル競合に注意する必要があります（exec/tests/suite/ephemeral.rs:L24, L40）。

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

ephemeral 以外のモードやフラグに関連する機能をテストしたい場合の基本的な手順です。

1. **新しいテスト関数を追加する**  
   `ephemeral.rs` に `#[test]` 関数を追加し、既存の 2 つのテストを参考に、`test_codex_exec` からハーネスを作成します（exec/tests/suite/ephemeral.rs:L22-36, L38-52）。
2. **フィクスチャと環境変数を設定する**  
   既存テストと同様に `find_resource!` と `CODEX_RS_SSE_FIXTURE` 環境変数を使うことで、外部依存を固定できます（exec/tests/suite/ephemeral.rs:L25, L28, L41, L44）。
3. **CLI 引数に新しいフラグやサブコマンドを指定する**  
   `.arg("--your-new-flag")` 等を挿入し、期待する挙動を再現します（exec/tests/suite/ephemeral.rs:L29-30, L45-47）。
4. **`session_rollout_count` で期待値を検証する**  
   ロールアウトファイルの期待数に応じて `assert_eq!(session_rollout_count(test.home_path()), expected)` を記述します（exec/tests/suite/ephemeral.rs:L34, L51）。

### 6.2 既存の機能を変更する場合

- **`session_rollout_count` の変更時の注意**  
  - `sessions` ディレクトリ名や `.jsonl` 拡張子を変更すると、既存テストの意味が変わります（exec/tests/suite/ephemeral.rs:L9, L18）。  
    これらは「セッションファイルは `sessions` ディレクトリ下の `.jsonl`」という暗黙の契約になっています。
  - 再帰性をやめる（`WalkDir` から `std::fs::read_dir` に変更するなど）と、サブディレクトリ内のファイルがカウント対象から外れます。現在サブディレクトリを使っているかどうかは、このチャンクからは分かりませんが、テストの意味が変わる可能性があります（exec/tests/suite/ephemeral.rs:L14-19）。
- **テスト期待値を変更する場合**  
  - 例えば「ephemeral モードでも特定の条件では 1 ファイル作成する」仕様に変更する場合、`assert_eq!(..., 0)` を `1` 等に修正する必要があります（exec/tests/suite/ephemeral.rs:L51）。
  - 同様に、デフォルトモードでのファイル数仕様変更（例: 複数ファイル生成）に合わせて、`assert_eq!(..., 1)` の期待値を更新する必要があります（exec/tests/suite/ephemeral.rs:L34）。
- **影響範囲の確認方法**  
  - `session_rollout_count` はこのファイル内でのみ使用されています（exec/tests/suite/ephemeral.rs:L34, L51）。他ファイルでの利用は、このチャンクからは確認できません。
  - CLI 側のセッション保存ロジックを変更した場合、本テストを含む「sessions ディレクトリと `.jsonl` ファイル」を前提とするすべてのテストを検索して確認する必要がありますが、それらがどこにあるかはこのチャンクには現れません。

---

## 7. 関連ファイル

このモジュールと密接に関係する外部ファイル・モジュールを、コードから読み取れる範囲で整理します。

| パス / シンボル | 役割 / 関係 |
|----------------|-------------|
| `tests/fixtures/cli_responses_fixture.sse` | SSE 形式のレスポンスフィクスチャファイル。`find_resource!` 経由でパスを取得し、環境変数 `CODEX_RS_SSE_FIXTURE` として CLI に渡されます（exec/tests/suite/ephemeral.rs:L25, L28, L41, L44）。 |
| `codex_utils_cargo_bin::find_resource` / `find_resource!` | リソースファイルのパスを解決するマクロ／関数。実体の定義ファイルパスはこのチャンクには現れませんが、テストフィクスチャの取得に使用されています（exec/tests/suite/ephemeral.rs:L4, L25, L41）。 |
| `core_test_support::test_codex_exec::test_codex_exec` | CLI 用テストハーネスを構築する関数。戻り値は `.cmd()` や `.home_path()` メソッドを持つ型ですが、型名や実装はこのチャンクには現れません（exec/tests/suite/ephemeral.rs:L5, L24, L34, L40, L51）。 |
| `walkdir::WalkDir` | ディレクトリエントリを再帰的に走査するための外部クレートの型。`session_rollout_count` 内で `.jsonl` ファイルのカウントに使用されています（exec/tests/suite/ephemeral.rs:L6, L14-19）。 |

---

### Bugs / Security に関する補足（このファイルから読み取れる範囲）

- **潜在的なテスト脆さ**  
  `session_rollout_count` が `sessions` 以下のすべての `.jsonl` を数えるため、同じ `home_path` を共有する複数テストが存在すると、期待値との不一致を引き起こす可能性があります（exec/tests/suite/ephemeral.rs:L14-19, L34, L51）。`test_codex_exec` がディレクトリを隔離していれば問題は起きませんが、このチャンクからは確認できません。
- **セキュリティ面**  
  このファイルはテスト用であり、外部から入力を直接受け取るコードは含んでいません。ファイルシステムアクセスも `WalkDir` に限定されており、任意パスの入力などはありません（exec/tests/suite/ephemeral.rs:L8-20）。したがって、このモジュール単体から直接的なセキュリティリスクは読み取れません。
