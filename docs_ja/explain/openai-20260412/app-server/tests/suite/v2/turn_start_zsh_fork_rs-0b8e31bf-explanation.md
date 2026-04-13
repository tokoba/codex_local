# app-server/tests/suite/v2/turn_start_zsh_fork.rs コード解説

## 0. ざっくり一言

zsh フォークベースのシェル実行機能（`ShellZshFork`）について、v2 Turn API からのコマンド実行・承認フロー・サンドボックス挙動を検証する統合テスト群です（非 Windows 限定）。  
主に「zsh フォーク経由でどんなコマンドが起動されるか」「承認の Accept/Decline/Cancel がどのような最終ステータスになるか」を確認します。

---

## 1. このモジュールの役割

### 1.1 概要

このテストモジュールは、Codex アプリサーバの v2 Turn API 上で、zsh フォーク機能によるシェルコマンドの実行と承認フローが仕様通りであることを検証します。

- zsh フォークが生成する実コマンドライン（ラッパー `/bin/sh -c ...` や待機ループなど）を検証します。  
  （`turn_start_shell_zsh_fork_executes_command_v2`, L48–175）
- コマンド実行承認リクエストに対する `Accept` / `Decline` / `Cancel` が、`CommandExecutionStatus` や `TurnStatus` にどう反映されるかを検証します。  
  （L177–441, L444–740）
- EXEC_WRAPPER を用いた zsh のサブコマンドインターセプトが、親コマンドのステータスや aggregated_output にどう影響するかを検証します。  
  （L444–740, L818–828）

### 1.2 アーキテクチャ内での位置づけ

このファイル単体で見ると、以下のコンポーネントが登場します：

- テストコード（本ファイル）
- `McpProcess`（アプリサーバのテスト用プロセスラッパ）  
  （`McpProcess::new_with_env`, L742–745）
- モック「レスポンスサーバ」（SSE ベースのモックモデルプロバイダ）  
  （`create_mock_responses_server_sequence*`, L87, L206, L339, L498）
- zsh 実行ファイル（DotSlash 経由で取得）  
  （`find_test_zsh_path`, L798–816）
- zsh フォークされたシェルコマンド（`ThreadItem::CommandExecution` として通知）  
  （L140–169 など）

これらの関係を概略図で表すと、次のようになります。

```mermaid
flowchart LR
    subgraph Test["このファイルのテスト群 (L48-740)"]
        T1["tokio::test\nturn_start_*_v2"]
    end

    subgraph Proc["McpProcess (app_test_support, L742-745)"]
        MCP["App サーバ子プロセス\n+ JSON-RPC ストリーム"]
    end

    subgraph MockSrv["モック responses サーバ\n(create_mock_responses_*, L72-87, 193-207, 329-340, 480-498)"]
        RESP["SSE /responses エンドポイント"]
    end

    subgraph Shell["zsh フォークされたシェル"]
        ZSH["zsh 実行ファイル\n(find_test_zsh_path, L798-816)"]
        CMD["実行中の shell command\n(ThreadItem::CommandExecution,\n例: call-zsh-fork)"]
    end

    T1 -->|config.toml 作成\n(create_config_toml, L747-796)| MCP
    T1 -->|モック SSE シナリオ\n(create_*_sse_response)| MockSrv
    MCP <--> |HTTP /v1/responses| MockSrv
    MCP --> |EXEC_WRAPPER 等環境変数\n(ZDOTDIR)| ZSH
    ZSH --> |/bin/sh -c ... や\n/bin/rm ...| CMD
    MCP --> |JSON-RPC 通知\nThreadItem::CommandExecution| T1
```

### 1.3 設計上のポイント

コードから読み取れる設計上の特徴を挙げます。

- **ネットワーク依存テストの安全なスキップ**  
  すべてのテストは `skip_if_no_network!` マクロでガードされており、ネットワーク非利用環境では自動的にスキップされます。（L50, L179, L315, L446）

- **外部バイナリのテスト依存**  
  - DotSlash で vendored な zsh を取得し、なければテストをスキップします。（`find_test_zsh_path`, L798–816）
  - 一部テストは EXEC_WRAPPER によるインターセプトが効く zsh だけを対象にします。（`supports_exec_wrapper_intercept`, L818–828, 使用箇所 L458–463）

- **モックモデルプロバイダとの疎結合**  
  create_*_sse_response 系ヘルパと `create_mock_responses_server_sequence{_unchecked}` を使い、実モデルではなく SSE 駆動のモックサーバで挙動を固定しています。（L72–87, L193–207, L329–340, L480–498）

- **JSON-RPC ストリームの逐次監視**  
  `McpProcess` 経由で、レスポンス (`read_stream_until_response_message`) と通知 (`read_stream_until_notification_message`) を待ち、期待するイベントまでループし続ける設計です。（L140–151, L272–287, L405–420, L643–660）

- **タイムアウトによるハング防止**  
  すべての待ち受けは `tokio::time::timeout` でラップされ、テストが無限待ちで固まらないようになっています。（例: L101–114, L133–137, L140–152 他）

- **プラットフォーム差異と zsh ビルド差異への耐性**  
  - Windows はビルドレベルで除外。（`#![cfg(not(windows))]`, L1, `DEFAULT_READ_TIMEOUT`, L43–46）
  - `turn_start_shell_zsh_fork_subcommand_decline_marks_parent_declined_v2` では、zsh 実装やサンドボックスによる挙動の差（親 `item/completed` が来ない等）を考慮した分岐を持ちます。（L663–737）

---

## 2. 主要な機能一覧

このファイルが提供する主要なテスト機能とヘルパを列挙します（行番号は根拠の範囲です）。

- `turn_start_shell_zsh_fork_executes_command_v2`: zsh フォークによるシェルコマンド起動内容を検証するテスト。（L48–175）
- `turn_start_shell_zsh_fork_exec_approval_decline_v2`: 承認リクエストに対する `Decline` が、コマンドを実行せず `CommandExecutionStatus::Declined` となることを検証。（L177–311）
- `turn_start_shell_zsh_fork_exec_approval_cancel_v2`: 承認リクエストに対する `Cancel` が、コマンドを `Declined` とし、Turn 全体を `Interrupted` にすることを検証。（L313–441）
- `turn_start_shell_zsh_fork_subcommand_decline_marks_parent_declined_v2`: EXEC_WRAPPER 経由のサブコマンドインターセプトにおいて、サブコマンドの Decline/Cancel が親コマンドを `Declined` とすることを検証。（L444–740）
- `create_zsh_test_mcp_process`: `ZDOTDIR` を指定して `McpProcess` を生成するヘルパ。（L742–745）
- `create_config_toml`: テスト用 `config.toml` を生成し、モックモデルプロバイダや feature flags を設定するヘルパ。（L747–796）
- `find_test_zsh_path`: DotSlash を利用してテスト用 zsh の実行パスを解決するヘルパ。（L798–816）
- `supports_exec_wrapper_intercept`: 指定 zsh が `EXEC_WRAPPER` による exec インターセプトをサポートしているかを実行時に判定するヘルパ。（L818–828）

---

## 3. 公開 API と詳細解説

このファイル自体はテストモジュールであり「公開 API」はありませんが、他テストでも流用しうるヘルパ関数がいくつか定義されています。また、プロトコル層の型を多用しているため、それらも簡単に整理します。

### 3.1 型一覧（構造体・列挙体など）

このファイル内で定義はされていませんが、頻出する外部型を整理します（用途はすべて本ファイルの使用箇所に基づいています）。

| 名前 | 種別 | 出典 | 役割 / 用途 | 根拠 |
|------|------|------|-------------|------|
| `McpProcess` | 構造体 | `app_test_support` | テスト用に Codex アプリサーバ子プロセスを起動・制御し、JSON-RPC ストリーム送受信を行うラッパ。（`new_with_env`, `initialize`, `send_*`, `read_stream_*` などを使用） | L10, L100–101, L219–221, L352–353, L511–512 他 |
| `ThreadStartParams` | 構造体 | `codex_app_server_protocol` | スレッド開始リクエストのパラメータ。ここでは `model`, `cwd` を設定して使用。（L104–107, L223–227, L356–359, L515–519） |
| `ThreadStartResponse` | 構造体 | 同上 | `send_thread_start_request` に対するレスポンス。`thread` フィールドを取り出して ID を利用。（L115, L234, L367, L526） |
| `TurnStartParams` | 構造体 | 同上 | Turn 開始リクエストのパラメータ。`thread_id`, `input`, `cwd`, `approval_policy`, `sandbox_policy`, `model` などを設定。（L118–130, L237–244, L370–377, L529–547） |
| `TurnStartResponse` | 構造体 | 同上 | Turn 開始レスポンス。`turn` を取得し ID やステータス確認に使う。（L138–139, L550–555） |
| `V2UserInput` (`UserInput`) | 列挙体 | 同上 | ユーザー入力。ここでは `Text { text, text_elements }` バリアントのみ使用。（L120–123, L239–242, L372–375, L531–534） |
| `ThreadItem` | 列挙体 | 同上 | Turn 内の「アイテム」（メッセージ、コマンド実行など）。ここでは `CommandExecution { ... }` バリアントをパターンマッチしています。（L147–161, L283–297, L416–423, L654–657, L665–672） |
| `ItemStartedNotification` | 構造体 | 同上 | `"item/started"` 通知のペイロード。`item` を通じて `ThreadItem` を取得。（L145–148） |
| `ItemCompletedNotification` | 構造体 | 同上 | `"item/completed"` 通知のペイロード。`item` から完了した `ThreadItem` を取得。（L277–285, L410–417, L648–657） |
| `TurnCompletedNotification` | 構造体 | 同上 | `"turn/completed"` 通知のペイロード。`thread_id`, `turn.id`, `turn.status` を検証。（L433–439, L691–701, L725–735） |
| `CommandExecutionStatus` | 列挙体 | 同上 | コマンド実行の状態。ここでは `InProgress`, `Declined` を検証。（L164, L300, L426, L675） |
| `CommandExecutionApprovalDecision` | 列挙体 | 同上 | 承認リクエストへの応答内容。`Accept`, `Decline`, `Cancel` を使用。（L267, L400, L561–562, L621, L625） |
| `CommandExecutionRequestApprovalResponse` | 構造体 | 同上 | 承認リクエストへの JSON-RPC レスポンスボディ。`decision` フィールドを設定して送信。（L266–268, L399–401, L629） |
| `CommandAction` | 列挙体 | 同上 | コマンド解析結果の一部。ここでは `Read { name, .. }` や `Unknown { command }` をパターンマッチし、「rm」に関するアクションかどうかを判定。（L588–593） |

### 3.2 関数詳細（7件）

#### `turn_start_shell_zsh_fork_executes_command_v2() -> Result<()>`

**概要**

zsh フォーク機能が、期待されるラッパーコマンド（`/bin/sh -c "while ... sleep 0.01 ..."`) を起動し、`ThreadItem::CommandExecution` として `InProgress` 状態で通知されることを検証する非同期テストです。（L48–175）

**引数**

なし（`#[tokio::test]` によりテストランナーから呼ばれます）。

**戻り値**

- `Result<()>` (`anyhow::Result`):  
  テストに失敗があれば `Err`、成功すれば `Ok(())` を返します。（L174）

**内部処理の流れ**

1. **ネットワークチェックと作業ディレクトリの準備**  
   - `skip_if_no_network!(Ok(()));` でネットワーク非利用環境では即時 `Ok(())` を返してスキップ。（L50）
   - `TempDir` を作り、その中に `codex_home` と `workspace` ディレクトリを作成。（L52–56）
   - `workspace.join("interrupt-release")` で、後でコマンド文字列に含めるパスを生成。（L57）

2. **zsh 実行ファイルの解決**  
   - `find_test_zsh_path()?` でテスト用 zsh のパスを取得。見つからなければメッセージを出してテストをスキップ。（L59–63, 実装は L798–816）

3. **モック SSE レスポンスサーバのセットアップ**  
   - `release_marker_escaped` をシェル文字列中で安全に使えるよう、単一引用符をエスケープして生成。（L69–71）
   - `create_shell_command_sse_response` で、  
     `["/bin/sh", "-c", "while [ ! -f '...']; do sleep 0.01; done"]` を実行する tool call (`call-zsh-fork`) を返す SSE レスポンスを構築。（L72–77）
   - no-op SSE レスポンスを追加し、`create_mock_responses_server_sequence_unchecked` でサーバ起動。（L78–87）

4. **config.toml の生成**  
   - `create_config_toml` を用いて、`ShellZshFork` を有効、`UnifiedExec`/`ShellSnapshot` を無効とする設定を `codex_home/config.toml` に書き込み。（L88–98, 実装 L747–796）

5. **McpProcess の起動とスレッド／ターン開始**  
   - `create_zsh_test_mcp_process` で `ZDOTDIR` を workspace に設定して `McpProcess` を生成。（L100–101, 実装 L742–745）
   - `initialize()` を `timeout(DEFAULT_READ_TIMEOUT, ...)` でラップして初期化。（L101）
   - `send_thread_start_request` でスレッド開始、`ThreadStartResponse` から `thread.id` を取得。（L103–115）
   - `"run echo hi"` というテキスト入力で `send_turn_start_request` を行い、`TurnStartResponse` から `turn` を取得。（L117–139）

6. **`item/started` 通知から CommandExecution アイテムを取得**  
   - `timeout(DEFAULT_READ_TIMEOUT, async { loop { ... } })` で `"item/started"` 通知を待ち、`ThreadItem::CommandExecution` が来るまでループ。（L140–152）
   - 取得した `ThreadItem::CommandExecution` から `id`, `status`, `command`, `cwd` を取り出し、期待値を検証。（L153–169）

7. **ターンの中断**  
   - `mcp.interrupt_turn_and_wait_for_aborted(thread.id, turn.id, DEFAULT_READ_TIMEOUT)` を呼び、実行中コマンドが存在する状態で turn を中断できることまで確認。（L171–172）

**Examples（使用例）**

このテスト自体は自動で実行されますが、「同様のパターンで zsh フォーク付きの MCP テストを書く」例としては次のようになります。

```rust
// 新しいテストの骨格イメージ
#[tokio::test]
async fn my_zsh_fork_test() -> anyhow::Result<()> {
    skip_if_no_network!(Ok(())); // ネットワーク前提のテストを安全にスキップ

    let tmp = TempDir::new()?;
    let codex_home = tmp.path().join("codex_home");
    std::fs::create_dir(&codex_home)?;
    let workspace = tmp.path().join("workspace");
    std::fs::create_dir(&workspace)?;

    let Some(zsh_path) = find_test_zsh_path()? else {
        return Ok(()); // zsh がなければスキップ
    };

    // モデルレスポンスシナリオを構築（今回は省略）
    let server = create_mock_responses_server_sequence_unchecked(vec![/* ... */]).await;

    create_config_toml(
        &codex_home,
        &server.uri(),
        "never",
        &BTreeMap::from([(Feature::ShellZshFork, true)]),
        &zsh_path,
    )?;

    let mut mcp = create_zsh_test_mcp_process(&codex_home, &workspace).await?;
    timeout(DEFAULT_READ_TIMEOUT, mcp.initialize()).await??;

    // ThreadStart / TurnStart を送って JSON-RPC 通知を検証する...
    Ok(())
}
```

**Errors / Panics**

- `?` が付いている箇所で発生しうるエラー:
  - 一時ディレクトリ作成や `std::fs::create_dir`/`std::fs::write` 失敗。（L52–56）
  - DotSlash 経由での zsh 取得 (`find_test_zsh_path`) の失敗。（L59）
  - モックサーバ生成や config.toml 書き込み失敗。（L72–98）
  - MCP プロセス起動・ JSON-RPC 通信失敗。（L100–172）
- `panic!`:
  - `serde_json::from_value(...).expect("item/started params")` が `None` を返した場合。（L145–146）
  - `unreachable!` 分岐（CommandExecution 以外のアイテムでループを抜けた場合）が起きた場合。（L160–161）

**Edge cases（エッジケース）**

- **zsh が見つからない場合**: `find_test_zsh_path` が `Ok(None)` を返すとテストはスキップされます（L59–63）。
- **ネットワーク不可の場合**: `skip_if_no_network!` によりテスト全体が実行されません（L50）。
- **モックサーバが期待通りの SSE を返さない場合**:  
  `read_stream_until_response_message` や `read_stream_until_notification_message` がタイムアウトし、`timeout` の `Err` 経由でテストが失敗します（例: L140–152）。
- **非常に高速なコマンド**: コメントにもある通り、本来 `echo hi` のようなコマンドだと即終了してしまうため、`while [ ! -f ... ]` ループで「中断されるまで実行中」状態を保証しています（L65–71）。

**使用上の注意点**

- このテストは「コマンドライン文字列がどう構成されるか」を検証するため、環境依存で `/bin/sh` のパスや `sleep` の利用などが変わる場合はテストが失敗する可能性があります。
- `create_mock_responses_server_sequence_unchecked` を用いることで、余分な `/responses` POST を許容しています（L86–87）。正確なリクエスト数を検証したい別種のテストでは `unchecked` ではない方を使うべきです。

---

#### `turn_start_shell_zsh_fork_exec_approval_decline_v2() -> Result<()>`

**概要**

`approval_policy = "untrusted"` の設定下で、zsh フォークされたコマンドに対する承認リクエストに `Decline` で応答したとき、コマンドが `CommandExecutionStatus::Declined` となり、exit code と aggregated_output が `None` のままであることを検証します。（L177–311）

**引数 / 戻り値**

- 引数: なし
- 戻り値: `Result<()>`（L310）

**内部処理の流れ**

1. 一時ディレクトリと `codex_home`/`workspace` を準備。（L181–185）
2. zsh パスを取得。なければスキップ。（L187–191）
3. モック SSE シナリオを構築: `python3 -c "print(42)"` を実行する shell_command SSE と、最後の assistant メッセージを返す SSE を用意。（L193–205）
4. `create_config_toml` で `approval_policy = "untrusted"` を設定し、`ShellZshFork` を有効化。（L207–217）
5. MCP を起動して初期化し、スレッドとターンを開始（入力 `"run python"`）。TurnStartResponse の内容は特に利用しません。（L219–251）
6. サーバからの JSON-RPC リクエストを待ち、`ServerRequest::CommandExecutionRequestApproval` であることを確認し、`item_id` と `thread_id` を検証。（L253–262）
7. `CommandExecutionRequestApprovalResponse { decision: Decline }` を送信。（L264–270）
8. `"item/completed"` 通知をループで待ち、`ThreadItem::CommandExecution` を取得して、`id`, `status`, `exit_code`, `aggregated_output` を検証。（L272–302）
9. `"turn/completed"` 通知を待ってからテスト終了。（L304–308）

**Examples**

承認リクエストに対して Decline を返す最小コード例は次のようになります（テストからの抜粋、L253–270）。

```rust
let server_req = timeout(
    DEFAULT_READ_TIMEOUT,
    mcp.read_stream_until_request_message(),
).await??;

let ServerRequest::CommandExecutionRequestApproval { request_id, params } = server_req else {
    panic!("expected CommandExecutionRequestApproval request");
};

assert_eq!(params.item_id, "call-zsh-fork-decline");

mcp.send_response(
    request_id,
    serde_json::to_value(CommandExecutionRequestApprovalResponse {
        decision: CommandExecutionApprovalDecision::Decline, // コマンドを拒否
    })?,
).await?;
```

**Errors / Panics**

- JSON パース (`serde_json::from_value`) の失敗や IO エラーなどは `?` により `Err` としてテスト失敗に繋がります（L272–287）。
- `panic!`:
  - 最初の JSON-RPC リクエストが `CommandExecutionRequestApproval` 以外の場合。（L258–260）
  - `"item/completed"` 通知の `params` が `None` の場合の `expect`。（L277–282）
  - CommandExecution 以外でループを抜けた場合の `unreachable!`。（L295–297）

**Edge cases**

- Decline した場合でも、ターン自体は `"turn/completed"` 通知で通常終了し得ます（L304–308）。Cancel との違いは turn のステータス（Interrupted かどうか）に現れます。
- exit_code と aggregated_output が `None` であることから、「一切実行されなかった」ことを間接的に検証しています（L299–302）。

**使用上の注意点**

- `approval_policy = "untrusted"` では、コマンドごとに承認が要求されることがこのテストから読み取れますが、ポリシーの詳細仕様自体はこのファイルからは分かりません。  
- 他テストで承認フローを扱う際も、`ServerRequest::CommandExecutionRequestApproval` が必ず最初に飛んでくるとは限らない（ログインシェルのフック等）ことに注意が必要です。これを考慮したのがサブコマンドのテストです（L623–625）。

---

#### `turn_start_shell_zsh_fork_exec_approval_cancel_v2() -> Result<()>`

**概要**

承認リクエストに `Cancel` で応答した場合に、コマンドが `Declined` と扱われ、Turn 全体のステータスが `TurnStatus::Interrupted` になることを検証するテストです。（L313–441）

**内部処理の流れ（要点）**

1. 基本的なセットアップ（TempDir, codex_home, workspace, zsh 検出）は Decline テストと同様。（L317–327）
2. モック SSE シナリオは単一の shell_command（`call-zsh-fork-cancel`）のみ。（L329–338）
3. `approval_policy = "untrusted"` で config.toml を生成。（L340–350）
4. MCP 初期化後、スレッドと `"run python"` ターンを開始。（L352–384）
5. 最初の承認リクエストを受け取り、`item_id`/`thread_id` を検証後、`decision: Cancel` を返す。（L386–403）
6. `"item/completed"` 通知から `ThreadItem::CommandExecution` を取得し、`status == Declined` であることを検証。（L405–427）
7. `"turn/completed"` 通知を受け取り、`TurnStatus::Interrupted` であることを確認。（L428–439）

**Edge cases / 注意点**

- `Cancel` が「承認フロー全体のキャンセル」として扱われ、コマンド自体は `Declined` になり turn は `Interrupted` になる、という仕様が読み取れます（L425–426, L438–439）。
- ここでは exit_code や aggregated_output を検証していません。Decline テストとの差分のみを確認する設計になっています。

---

#### `turn_start_shell_zsh_fork_subcommand_decline_marks_parent_declined_v2() -> Result<()>`

**概要**

zsh の EXEC_WRAPPER を利用してサブコマンドをインターセプトする環境で、親シェルコマンドが複数の `/bin/rm` サブコマンドを含むとき、サブコマンドごとの承認（Accept / Cancel）がどのように送られ、最終的に親コマンドが `CommandExecutionStatus::Declined` となるかを検証するテストです。（L444–740）

**引数 / 戻り値**

- 引数: なし
- 戻り値: `Result<()>`（L739）

**内部処理の流れ（アルゴリズム）**

1. **前提チェックとテストファイルの準備**  
   - zsh パスを取得し、`supports_exec_wrapper_intercept(&zsh_path)` が true でなければテストをスキップ。（L454–463, L818–828）
   - `workspace` に `first.txt` と `second.txt` を作成。（L466–469）
   - `/bin/rm first && /bin/rm second` という `shell_command` を組み立てる。（L470–474）

2. **ツール呼び出し SSE シナリオの作成**  
   - `tool_call_arguments` として `{"command": shell_command, "workdir": null, "timeout_ms": 5000}` を JSON 文字列化。（L475–479）
   - `ev_function_call("call-zsh-fork-subcommand-decline", "shell_command", &tool_call_arguments)` を含む SSE を構築。（L480–488）
   - 余分な `/responses` POST に対応する no-op SSE を追加し、`create_mock_responses_server_sequence_unchecked` でサーバ起動。（L489–498）

3. **MCP 起動、スレッド／ターン開始**  
   - `approval_policy = "untrusted"`、`ShellZshFork` 有効で config.toml を生成。（L499–509）
   - MCP 初期化 → スレッド開始 → `"remove both files"` として TurnStart。（L511–555）
   - TurnStartResponse から `turn` を取得。（L550–555）

4. **承認リクエストの分類と応答**  
   - 承認リクエストを処理するループを回す（L568–632）。ループ条件は  
     `target_decision_index < target_decisions.len() || !saw_parent_approval` で、  
     *2 つのターゲットサブコマンドに対してそれぞれ Accept / Cancel を返し、かつ親シェルコマンドの承認も 1 度観測するまで続けます。（L560–567）
   - 各 `ServerRequest::CommandExecutionRequestApproval` について:
     - `approval_command` 文字列から、`first_file`/`second_file` を含むかどうか、`/bin/rm` または `/usr/bin/rm` を含むかどうかを調べる。（L580–587）
     - `params.command_actions` があれば、その中に `CommandAction::Read { name == "rm" }` または `CommandAction::Unknown { command.contains("rm") }` があるかを確認。（L588–593）
     - 「片方のファイルだけ含み、かつ rm アクションや rm バイナリが示されている」ものをターゲットサブコマンドとみなす。（L595–596）
       - その場合、`approval_id` を `approved_subcommand_ids` に保存し、コマンド文字列を `approved_subcommand_strings` に保存。（L598–605）
       - `target_decisions = [Accept, Cancel]` の順に決定を返す。（L560–563, L611–614）
     - 親シェルコマンドと判断する条件: `approval_command` に zsh パスが含まれ、かつ  
       `shell_command` 全体か、両方のファイルか、`"&& first_file"` が含まれること。（L607–610）
       - その場合 `saw_parent_approval = true` として `Accept` を返す。（L615–621）
     - その他の承認リクエスト（ログインシェルのスタートアップヘルパ等）はすべて `Accept`。（L622–625）

5. **承認結果の整合性チェック**  
   - ループ終了後、親承認が 1 度は観測されたこと、サブコマンド ID が 2 つであり互いに異なること、文字列的に `first_file`/`second_file` をそれぞれ含むことを検証。（L634–642）

6. **親 CommandExecution の完了アイテムの扱い**  
   - `"item/completed"` 通知から、`id == "call-zsh-fork-subcommand-decline"` の `ThreadItem::CommandExecution` を待つ `timeout(...).await` を行い、その結果 `parent_completed_command_execution` を `match` で分岐。（L643–661, L663–737）

   a. `Ok(Ok(item))`：親完了アイテムが取得できた場合（L663–713）  
   - `status == Declined` を検証。（L674–675）  
   - `aggregated_output` が `Some` なら、  
     - 文字列が `"exec command rejected by user"` と一致、または  
     - `"sandbox denied exec error"` を含むことを検証。（L676–681）  
   - `turn/completed` 通知の取得を試み、成功すれば `thread_id`, `turn.id`、`turn.status` が `Interrupted` または `Completed` であることを確認。  
     タイムアウトした場合は `interrupt_turn_and_wait_for_aborted` で明示的に中断。（L684–712）

   b. `Ok(Err(error))`：通知読み取り中にエラーが発生した場合はそのまま Err を返す。（L713–714）

   c. `Err(_)`：親完了アイテム待ちがタイムアウトした場合（L715–736）  
   - 一部の zsh ビルドやサンドボックスでは親 `item/completed` が出ずに turn が終了するケースを考慮し、直接 `turn/completed` 通知を待ってステータスを `Interrupted` または `Completed` と確認。（L716–735）

**Examples（承認フローの抽象化例）**

サブコマンドと親コマンドを見分けて承認するロジックの骨格を、簡略化して示します。

```rust
// approval_command: 文字列化されたコマンド
// has_first_file, has_second_file, has_rm_action, mentions_rm_binary は上記テストと同様の判定

let is_target_subcommand =
    (has_first_file != has_second_file) && (has_rm_action || mentions_rm_binary);

let is_parent_approval = approval_command.contains(&zsh_path.display().to_string())
    && (approval_command.contains(&shell_command)
        || (has_first_file && has_second_file));

let decision = if is_target_subcommand {
    // サブコマンドごとに Accept / Cancel を切り替える
    CommandExecutionApprovalDecision::Accept
} else if is_parent_approval {
    // 親シェルコマンドは Accept
    CommandExecutionApprovalDecision::Accept
} else {
    // その他は Accept
    CommandExecutionApprovalDecision::Accept
};
```

**Errors / Panics**

- `fetch_dotslash_file` やファイル IO の失敗、JSON パースなどで `?` が伝播し、テストが失敗し得ます。（L468–479, L511–555 等）
- `panic!`:
  - 各承認リクエストが `CommandExecutionRequestApproval` でなかった場合。（L574–577）
  - サブコマンド承認に `approval_id` が付与されていない場合の `expect`。（L601–603）

**Edge cases / 使用上の注意点**

- 親 `item/completed` が来ない可能性を考慮し、turn の完了だけでテストを成功とするパスも用意されています（L715–735）。  
  これは zsh のビルドや Linux サンドボックスの挙動差異を吸収するためです。
- `CommandAction` が存在しない場合でも、コマンド文字列に `/bin/rm` などが含まれていればサブコマンド判定を行います（L587–596）。  
  したがって `command_actions` を完全に信頼しているわけではありません。
- `target_decisions` の順序（最初 Accept、次 Cancel）はテストにとって重要であり、対応する `approved_subcommand_ids` も 2 つあることを検証しています（L560–563, L638–642）。

---

#### `create_zsh_test_mcp_process(codex_home: &Path, zdotdir: &Path) -> Result<McpProcess>`

**概要**

`codex_home` と `ZDOTDIR` 環境変数を設定した状態で `McpProcess` を生成するヘルパ関数です。（L742–745）

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `codex_home` | `&Path` | Codex のホームディレクトリパス。設定ファイル `config.toml` などが置かれる場所。（L742, L770–771） |
| `zdotdir` | `&Path` | zsh の設定ディレクトリ (`ZDOTDIR`) として使うパス。ここでは workspace が渡されています。（L742, 呼び出し側 L100, L219, L352, L511） |

**戻り値**

- `Result<McpProcess>`: 成功時には初期化前の `McpProcess` インスタンス。（L743–745）

**内部処理**

1. `zdotdir.to_string_lossy().into_owned()` で UTF-8 文字列へ変換。（L743）
2. `McpProcess::new_with_env(codex_home, &[("ZDOTDIR", Some(zdotdir.as_str()))]).await` を呼び出し、その結果を返す。（L744–745）

**使用例**

```rust
let mut mcp = create_zsh_test_mcp_process(&codex_home, &workspace).await?;
timeout(DEFAULT_READ_TIMEOUT, mcp.initialize()).await??;
```

（L100–101 など）

**Errors / Edge cases**

- `McpProcess::new_with_env` がエラーを返した場合、そのまま `Result` として伝播します（L744–745）。
- `zdotdir` に非 UTF-8 文字が含まれていた場合でも `to_string_lossy` が「lossy」変換を行うため、テスト上はエラーにならず、代替文字で環境変数に設定されます。この挙動を意図しているかどうかは、このファイルだけからは分かりません。

---

#### `create_config_toml(...) -> std::io::Result<()>`

**概要**

`codex_home` 以下に `config.toml` を生成し、テスト用のモデルプロバイダ設定・feature flags・zsh パス・承認ポリシーを記述するヘルパ関数です。（L747–796）

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `codex_home` | `&Path` | `config.toml` を作成するディレクトリ。（L747, L770–771） |
| `server_uri` | `&str` | モックモデルプロバイダのベース URI（`http://...`）。`"{server_uri}/v1"` として使用。（L749, L787） |
| `approval_policy` | `&str` | `approval_policy` 設定値。 `"never"` や `"untrusted"` など。（L750, L776） |
| `feature_flags` | `&BTreeMap<Feature, bool>` | 有効/無効にしたい Feature のフラグ集合。（L751, L755–757） |
| `zsh_path` | `&Path` | zsh 実行ファイルの絶対パス。`zsh_path = "...“` として書き込まれます。（L752, L778, L792–793） |

**戻り値**

- `std::io::Result<()>`: ファイル書き込みエラーなどを表現します。（L753, L771–795）

**内部処理の流れ**

1. `features` マップを `RemoteModels: false` で初期化。（L754）
2. 渡された `feature_flags` の内容を `features` にマージ。（L755–757）
3. `FEATURES` テーブルから各 `Feature` に対する `key` を検索し、`"{key} = {enabled}"` 形式の行を生成。  
   これを `"\n"` で結合して `feature_entries` とする。（L758–769）
4. `config.toml` パス（`codex_home.join("config.toml")`）を作成し、`std::fs::write` で Raw 文字列テンプレートから生成された設定内容を書き込む。（L770–795）

**生成される config.toml の例**

例として `approval_policy = "never"`, `zsh_path = "/usr/local/bin/zsh"` の場合、概ね次のようになります（L773–791）。

```toml
model = "mock-model"
approval_policy = "never"
sandbox_mode = "read-only"
zsh_path = "/usr/local/bin/zsh"

model_provider = "mock_provider"

[features]
shell_zsh_fork = true
unified_exec = false
shell_snapshot = false
remote_models = false

[model_providers.mock_provider]
name = "Mock provider for test"
base_url = "http://localhost:1234/v1"
wire_api = "responses"
request_max_retries = 0
stream_max_retries = 0
```

※ `FEATURES` 内の `key` 名はこのファイルからは判別できないため、上記は形のみの例です。

**Errors / Panics**

- `FEATURES.iter().find(|spec| spec.id == feature)` が見つからない場合、`panic!("missing feature key for {feature:?}")` が発生します。（L761–765）
- `std::fs::write` の失敗は `Err(std::io::Error)` として呼び出し元に伝播します。（L771–795）

**使用上の注意点**

- `Feature` が `FEATURES` に登録されていないと `panic!` になるため、新機能を追加するときは `FEATURES` への登録が必須です。
- `sandbox_mode = "read-only"` は固定で書かれており、テストごとに変更されていない点に注意が必要です。（サンドボックスの実挙動は `sandbox_policy` パラメータでも制御されています, L536–543）

---

#### `find_test_zsh_path() -> Result<Option<std::path::PathBuf>>`

**概要**

リポジトリルートから DotSlash 形式で配置された zsh 実行ファイルを探し、必要なら DotSlash 経由でフェッチして、そのパスを返すヘルパ関数です。（L798–816）

**内部処理の流れ**

1. `codex_utils_cargo_bin::repo_root()` でリポジトリルートパスを取得。（L799）
2. `repo_root.join("codex-rs/app-server/tests/suite/zsh")` を `dotslash_zsh` として計算。（L800）
3. `dotslash_zsh.is_file()` が false なら、メッセージを出力して `Ok(None)` を返す。（L801–807）
4. `core_test_support::fetch_dotslash_file(&dotslash_zsh, None)` を実行。（L808）
   - 成功時: `Ok(Some(path))` を返す。（L809）
   - 失敗時: エラーメッセージを出力し、最終的に `Ok(None)` を返す。（L810–815）

**使用例**

各テストの先頭で次のように使用されています（例: L59–63）。

```rust
let Some(zsh_path) = find_test_zsh_path()? else {
    eprintln!("skipping zsh fork test: no zsh executable found");
    return Ok(());
};
```

このように、「取得できなければテストをスキップ」というパターンになっています。

---

#### `supports_exec_wrapper_intercept(zsh_path: &Path) -> bool`

**概要**

指定した zsh バイナリが、`EXEC_WRAPPER` 環境変数を用いた exec インターセプトをサポートしているかを、簡易的に判定する関数です。（L818–828）

**内部処理**

- `Command::new(zsh_path)` に `-fc /usr/bin/true` を渡し、`EXEC_WRAPPER=/usr/bin/false` を環境に設定して実行。（L819–823）
- 正常に実行できた場合、`!status.success()` を返す。つまり、  
  `/usr/bin/true` を実行しているにもかかわらず非ゼロ終了コードになる → EXEC_WRAPPER によるインターセプトが効いている、とみなしています。（L824–825）
- プロセス起動自体が失敗した場合は `false` を返す。（L826–827）

**使用例**

サブコマンド Decline テストで、zsh がこの機能をサポートしていない場合テストをスキップするために使われます。（L458–463）

---

### 3.3 その他の関数

主要ロジック以外の単純な関数や定数をまとめます。

| 名前 | 種別 | 役割（1 行） | 根拠 |
|------|------|--------------|------|
| `DEFAULT_READ_TIMEOUT` | `const std::time::Duration` | JSON-RPC 応答・通知待ちのタイムアウト時間（Windows 15 秒、他 10 秒）。（L43–46） | `app-server/tests/suite/v2/turn_start_zsh_fork.rs:L43-46` |

---

## 4. データフロー

代表的なシナリオとして、`turn_start_shell_zsh_fork_executes_command_v2` のデータフローを示します。

### 処理の要点

1. テストが config とモック SSE サーバを準備し、`McpProcess` を起動。（L72–101）
2. テストが JSON-RPC で `thread/start` → `turn/start` を送信。（L103–132）
3. MCP（アプリサーバ）がモック SSE サーバから tool call シナリオを取得し、zsh フォーク経由で `/bin/sh -c "while ..."` コマンドを起動。（L72–77 と CommandExecution アイテム, L153–169）
4. MCP が `"item/started"` 通知として `ThreadItem::CommandExecution` をテスト側に送信。テストはこれを検証。（L140–169）
5. 最後にテストが `interrupt_turn_and_wait_for_aborted` を使って turn を中断。（L171–172）

### シーケンス図（turn_start_shell_zsh_fork_executes_command_v2, L48–175）

```mermaid
sequenceDiagram
    participant Test as Testコード\n(turn_start_shell_zsh_fork_executes_command_v2\nL48-175)
    participant MCP as McpProcess\n(app サーバ)
    participant Mock as モック responses サーバ
    participant Zsh as zsh フォーク済みシェル
    participant Sh as /bin/sh -c ... コマンド

    Test->>Mock: create_mock_responses_server_sequence_unchecked(...)\n(SSE シナリオ, L72-87)
    Test->>Test: create_config_toml(codex_home, Mock.uri(), ...)\n(L88-98)
    Test->>MCP: create_zsh_test_mcp_process(...)\n(L100-101)
    Test->>MCP: initialize() with timeout\n(L101)
    Test->>MCP: send_thread_start_request(ThreadStartParams)\n(L103-109)
    MCP-->>Test: ThreadStartResponse(thread)\n(L110-115)
    Test->>MCP: send_turn_start_request(TurnStartParams)\n(L117-132)
    MCP->>Mock: HTTP /v1/responses ...\n(SSE 取得)
    Mock-->>MCP: SSE: shell_command tool call\n("call-zsh-fork")
    MCP->>Zsh: 起動 (zsh_path, ZDOTDIR=workspace)\n(L153-169)
    Zsh->>Sh: /bin/sh -c "while [ ! -f '...']; do sleep 0.01; done"
    MCP-->>Test: JSON-RPC notif "item/started"\n(ThreadItem::CommandExecution)\n(L140-152)
    Test->>Test: command 文字列や cwd を検証\n(L163-169)
    Test->>MCP: interrupt_turn_and_wait_for_aborted(...)\n(L171-172)
```

---

## 5. 使い方（How to Use）

このファイルはテスト用ですので、直接アプリケーションから呼び出すことは想定されていません。ただし、「McpProcess で zsh フォーク機能をテストする際の典型パターン」として参考になります。

### 5.1 基本的な使用方法（テストパターン）

1. **一時ディレクトリ・config の用意**  
   `TempDir` を作り、その中に `codex_home` と `workspace` を作成。`create_config_toml` で config.toml を生成します。（L52–56, L88–98）

2. **zsh パスの解決と前提条件チェック**  
   - `find_test_zsh_path` で zsh 実行ファイルを取得。なければテストをスキップ。（L59–63, L187–191, L323–327, L454–457）
   - 必要に応じて `supports_exec_wrapper_intercept` で EXEC_WRAPPER 対応をチェック。（L458–463）

3. **モック SSE レスポンスサーバの準備**  
   `create_shell_command_sse_response` や `responses::ev_function_call` を使い、期待する tool call シナリオを構成します。（L72–81, L193–205, L329–338, L480–488）

4. **MCP 起動・スレッド/ターン開始**  
   - `create_zsh_test_mcp_process` ＋ `initialize`。（L100–101, L219–221, L352–353, L511–512）
   - `send_thread_start_request` → `send_turn_start_request`。（L103–132, L222–246, L355–379, L514–549）

5. **JSON-RPC ストリーム監視と検証**  
   - `read_stream_until_response_message` で Thread/Turn 開始応答を待つ。（L110–115, L229–235, L362–367, L521–526, L550–555）
   - `read_stream_until_request_message` で承認リクエストを取得。（L253–257, L386–390, L569–573）
   - `read_stream_until_notification_message` で `"item/started"`, `"item/completed"`, `"turn/completed"` 通知を取得し、`serde_json::from_value` でパースして検証。（L142–147, L274–283, L408–417, L646–653, L684–702, L720–735）

### 5.2 よくある使用パターン

- **承認付きツール呼び出し**  
  - `approval_policy = "untrusted"` とし、`ServerRequest::CommandExecutionRequestApproval` を待ってから `CommandExecutionRequestApprovalResponse` を返すパターン。（L207–217, L253–270, L340–350, L386–403, L568–632）

- **サンドボックス制約付きのシェル実行**  
  - `SandboxPolicy::WorkspaceWrite` を設定し、workspace 以外の書き込みが制限される状況で `/bin/rm` を実行するパターン。（L536–543）

### 5.3 よくある間違い（このコードから推測されるもの）

```rust
// 間違い例: approval_policy を未設定のままにして、
// テストが期待通りに承認リクエストを受け取れないケース
let turn_id = mcp.send_turn_start_request(TurnStartParams {
    thread_id: thread.id.clone(),
    input: vec![/* ... */],
    cwd: Some(workspace.clone()),
    // approval_policy: None, // ← 明示しない
    ..Default::default()
}).await?;
```

```rust
// 正しい例: テストの目的に応じて approval_policy を明示する
let turn_id = mcp.send_turn_start_request(TurnStartParams {
    thread_id: thread.id.clone(),
    input: vec![/* ... */],
    cwd: Some(workspace.clone()),
    approval_policy: Some(codex_app_server_protocol::AskForApproval::UnlessTrusted),
    // もしくは "never"/"untrusted" を config.toml 側で設定（L776）
    ..Default::default()
}).await?;
```

### 5.4 使用上の注意点（まとめ）

- **外部コマンド実行**  
  `supports_exec_wrapper_intercept` では `/usr/bin/true` や `/usr/bin/false` が実行されます（L819–823）。テスト環境にこれらが存在しない場合、結果が意図したものにならない可能性があります。

- **非同期 + タイムアウト**  
  `tokio::time::timeout` を通さずに `read_stream_*` を直接待つと、アプリサーバ側の問題でテストが無限待ちになる危険があります。このファイルではすべて timeout を付けています（L101–152, L229–251, L362–384, L643–661 など）。

- **環境依存のスキップ**  
  DotSlash に依存しているため、`fetch_dotslash_file` が失敗する環境では zsh 関連のテストはすべてスキップされます（L808–815）。この挙動自体はテスト設計として意図的なものと思われますが、CI などで zsh を確実にテストしたい場合は DotSlash 設定が必須です。

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合（例: 新しい承認パターンのテスト）

1. **モック SSE シナリオの追加**  
   `responses::sse` や `create_*_sse_response` を使って、新しい tool call や assistant メッセージのシーケンスを定義します。（参考: L193–205, L329–338, L480–488）

2. **config.toml の調整**  
   必要な feature flag を `create_config_toml` 呼び出しの `feature_flags` に追加／変更します。（L88–98, L207–217, L340–350, L499–509）

3. **承認フローの検証ロジック実装**  
   - 新しい `#[tokio::test]` 関数を作成し、既存テストと同様に `send_thread_start_request` / `send_turn_start_request` を呼びます。
   - `read_stream_until_request_message` で必要な種類の承認リクエストを待ち、`CommandExecutionRequestApprovalResponse` を返します。

4. **通知の検証**  
   `"item/started"`, `"item/completed"`, `"turn/completed"` の通知を必要に応じて検証します。既存テストをコピー＆調整するのが分かりやすいです。

### 6.2 既存の機能を変更する場合

- **影響範囲の確認**  
  - `create_config_toml` のテンプレートを変更する場合は、この関数を呼んでいるすべてのテスト（本ファイル内 4 テスト）に影響します。（L88–98, L207–217, L340–350, L499–509）
  - `find_test_zsh_path` のパスロジックを変更すると、すべての zsh テストのスキップ条件が変わります。（L59–63, L187–191, L323–327, L454–457）

- **契約（前提条件・返り値の意味）の注意**  
  - `supports_exec_wrapper_intercept` は「true = EXEC_WRAPPER が効いているとみなせる」という前提でサブコマンドテストが書かれています。判定ロジックを変更すると、テストが期待する前提が変わるため要注意です。（L458–463, L818–828）
  - `CommandExecutionStatus::Declined` が `Decline` と `Cancel` の両方で用いられていることをテストが前提にしているため、プロトコルの仕様を変える場合はテストも合わせて変更する必要があります。（L300, L426, L675）

- **テスト追加後の確認**  
  変更した機能に依存する他のテスト（別ファイルを含む）の動作も確認することが望ましいです。特に `create_config_toml` のような共通ヘルパは依存範囲が広くなりがちです。

---

## 7. 関連ファイル

このモジュールと密接に関係するであろうファイル・ディレクトリ（名前はコード中の参照から判断）をまとめます。

| パス | 役割 / 関係 |
|------|------------|
| `codex-rs/app-server/tests/suite/zsh` | DotSlash 経由で取得される zsh 実行ファイルの元となるパス。`find_test_zsh_path` で参照。（L800） |
| `core_test_support`（モジュール） | `skip_if_no_network!` や `responses`, `fetch_dotslash_file` を提供し、ネットワーク前提テストや SSE レスポンスの構築を支援。（L35–36, L808） |
| `app_test_support`（モジュール） | `McpProcess` と SSE レスポンス生成ヘルパ (`create_shell_command_sse_response` など) を提供。（L10–15, L72–77） |
| `codex_app_server_protocol`（クレート） | Thread/Turn/CommandExecution/Approval などの JSON-RPC プロトコル型の定義元。（L16–32） |
| `codex_features`（クレート） | `Feature` 列挙体と `FEATURES` テーブルを提供し、feature flags のキー解決に使用。（L33–34, L754–767） |
| `codex_utils_cargo_bin`（クレート） | `repo_root()` によりリポジトリルートパスを解決。（L799） |

このファイルは「zsh フォーク + Turn v2 + 承認フロー」の統合テストとして、zsh 実行ファイル・モックモデルサーバ・McpProcess といった複数コンポーネントの連携を確認する位置づけになっています。
