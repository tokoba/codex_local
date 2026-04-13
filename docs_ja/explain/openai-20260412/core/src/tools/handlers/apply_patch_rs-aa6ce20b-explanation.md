# core/src/tools/handlers/apply_patch.rs

## 0. ざっくり一言

`apply_patch` ツールのハンドラと、`exec_command` 経由の `apply_patch` 呼び出しをフックして専用ツールに委譲するためのロジックを実装するモジュールです。パッチ内容の検証・対象ファイルの抽出・サンドボックス権限の計算・実行オーケストレーションを行います。  
（例: `ApplyPatchHandler::handle`・`intercept_apply_patch` など。`core/src/tools/handlers/apply_patch.rs:L37-261, L265-357`）

---

## 1. このモジュールの役割

### 1.1 概要

- 問題: モデルが「ファイルへのパッチ適用」を要求したときに、安全な権限管理のもとでパッチを検証・適用する必要があります。
- 機能:
  - `apply_patch` ツール用の `ToolHandler` 実装（`ApplyPatchHandler`）を提供します（`L37, L127-262`）。
  - シェルコマンドとして `apply_patch` が実行されそうな場合に介入し、専用ツールとして扱うインターセプタを提供します（`intercept_apply_patch`、`L265-357`）。
  - パッチの変更対象ファイルから必要なファイルシステム権限を計算します（`file_paths_for_action`, `write_permissions_for_paths`, `effective_patch_permissions`、`L39-125`）。

### 1.2 アーキテクチャ内での位置づけ

このモジュールは「ツールハンドラ層」に属し、`codex_apply_patch` クレートのパッチパーサや、`ToolOrchestrator` / `ApplyPatchRuntime` などの実行ランタイムと連携しています。

```mermaid
graph TD
  subgraph "apply_patch handler\n(core/src/tools/handlers/apply_patch.rs)"
    H[ApplyPatchHandler::handle\n(L145-261)]
    I[intercept_apply_patch\n(L265-357)]
    F[file_paths_for_action\n(L39-57)]
    W[write_permissions_for_paths\n(L63-93)]
    E[effective_patch_permissions\n(L95-125)]
  end

  H --> E
  I --> E
  E --> F
  E --> W

  H --> PA[apply_patch::apply_patch\n(別モジュール)]
  I --> PA
  H --> MP[codex_apply_patch::maybe_parse_apply_patch_verified\n(外部クレート)]
  I --> MP
  H --> RT[ToolOrchestrator::run +\nApplyPatchRuntime\n(別モジュール)]
  I --> RT
  H --> EM[ToolEmitter/ToolEventCtx\n(L193-201,233-239)]
  I --> EM[ToolEmitter/ToolEventCtx\n(L297-305,336-342)]
```

- 上位層からは `ApplyPatchHandler` が `ToolHandler` として登録され、ツール呼び出し時に `handle` が実行されると解釈できます（インターフェースからの推測、`L127-132, L145-261`）。
- `intercept_apply_patch` は `exec_command` 相当の処理から呼ばれ、`apply_patch` コマンドっぽい呼び出しを検出したときだけパッチツールへ転送します（`L265-357`）。

### 1.3 設計上のポイント

コードから読み取れる設計上の特徴は次の通りです。

- **責務分割**  
  - パッチ対象ファイルの抽出: `file_paths_for_action`（`L39-57`）  
  - 追加ファイル権限の計算: `write_permissions_for_paths`（`L63-93`）  
  - 効力を持つパーミッションとサンドボックスポリシーの確定: `effective_patch_permissions`（`L95-125`）  
  - 実際のツールハンドリング: `ApplyPatchHandler::handle`（`L145-261`）  
  - `exec` 経由のパッチ呼び出しのインターセプト: `intercept_apply_patch`（`L265-357`）
- **状態管理**  
  - ローカル状態はほぼ持たず、`Session` / `TurnContext` を引数として受け取る形で動作します（`L145-154, L270-273`）。
- **エラーハンドリング方針**  
  - 失敗は `FunctionCallError::RespondToModel` としてモデルにフィードバックされます（`L163-165, L174-176, L245-247, L251-253, L347-350`）。
  - パッチの検証段階でのエラーと、シェルパースエラー／`apply_patch` ではない入力を区別しています（`L181-259, L276-356`）。
- **安全性・サンドボックス**  
  - 実際に変更しようとするパス群にもとづいて、書き込み権限がないディレクトリのみを追加権限として要求します（`write_permissions_for_paths`, `L68-77, L84-90`）。
  - `effective_file_system_sandbox_policy` と `apply_granted_turn_permissions` により、既存の許可と新規追加許可を合成しています（`L105-112, L113-118`）。
- **並行性**  
  - 主要な処理はすべて `async fn` として記述され、`Session` / `TurnContext` は `Arc` 経由で共有されます（`L95, L270-272, L275, L145`）。
  - 内部でスレッド生成は行っていませんが、非同期ランタイム上で安全に並列実行できる設計になっています。

---

## 2. 主要な機能一覧

このモジュールが提供する主要機能を整理します。

- `ApplyPatchHandler`: `apply_patch` ツールのハンドラ（`ToolHandler` 実装）を提供する（`L37, L127-262`）
- `ApplyPatchHandler::handle`: モデルからの `apply_patch` 呼び出しを処理し、パッチを検証・適用または Exec ランタイムに委譲する（`L145-261`）
- `intercept_apply_patch`: `exec_command` 経由の `apply_patch` 風コマンドを検出し、専用ツールとして処理する（`L265-357`）
- `effective_patch_permissions`: パッチで変更されるパスにもとづき、必要な追加権限とサンドボックスポリシーを計算する（`L95-125`）
- `write_permissions_for_paths`: パッチが書き込みを行う可能性のあるディレクトリに対し、追加の書き込み権限プロファイルを生成する（`L63-93`）
- `file_paths_for_action`: `ApplyPatchAction` から変更対象の絶対パス一覧を抽出する（移動先も含む）（`L39-57`）

---

## 3. 公開 API と詳細解説

### 3.1 型一覧（構造体・列挙体など）

| 名前 | 種別 | 可視性 | 定義位置 | 役割 / 用途 |
|------|------|--------|----------|-------------|
| `ApplyPatchHandler` | 構造体（フィールドなし） | `pub` | `core/src/tools/handlers/apply_patch.rs:L37` | `ToolHandler` トレイトを実装し、`apply_patch` ツール呼び出しを処理するエントリポイント |

※ このファイル内で外部に公開されている型は `ApplyPatchHandler` のみです（`pub struct`、`L37`）。`intercept_apply_patch` は `pub(crate)` でクレート内専用です（`L265`）。

### 3.1.1 `ToolHandler` 実装

`ApplyPatchHandler` は以下のメソッドを実装しています（`L127-143`）。

- `type Output = ApplyPatchToolOutput;`（`L128`）
- `fn kind(&self) -> ToolKind`（`L130-132`）  
  → `ToolKind::Function` を返すため、このハンドラは「関数ツール」として扱われます。
- `fn matches_kind(&self, payload: &ToolPayload) -> bool`（`L134-139`）  
  → `ToolPayload::Function` または `ToolPayload::Custom` のみを受け付けます。
- `async fn is_mutating(&self, _invocation: &ToolInvocation) -> bool`（`L141-143`）  
  → 常に `true` を返し、このツールが状態（ファイルシステム）を変更することを示します。

これにより、ツールオーケストレータは「ファイルを書き換える可能性がある関数ツール」として `apply_patch` を扱うことができます。

---

### 3.2 関数詳細（主要 6 件）

#### 3.2.1 `ApplyPatchHandler::handle(&self, invocation: ToolInvocation) -> Result<ApplyPatchToolOutput, FunctionCallError>`

**概要**

`apply_patch` ツールへの呼び出しを処理するメイン関数です。  
ペイロードからパッチテキストを取得し、`codex_apply_patch` で検証・解析したうえで、パッチ適用か Exec ランタイムへの委譲を行います（`L145-261`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `self` | `&ApplyPatchHandler` | ツールハンドラ自身 |
| `invocation` | `ToolInvocation` | セッション・ターン・ペイロードなどを含むツール呼び出しコンテキスト（`L145-154`） |

※ `ToolInvocation` の詳細定義はこのチャンクには現れませんが、分解されて `session`, `turn`, `tracker`, `call_id`, `tool_name`, `payload` が利用されています（`L147-153`）。

**戻り値**

- `Ok(ApplyPatchToolOutput)`  
  - ツールのテキスト出力を含む成功結果（`L187-190, L239-240`）。
- `Err(FunctionCallError)`  
  - 不正ペイロード、環境未設定、パッチ検証エラーなど各種エラーを表します（`L163-165, L174-176, L245-247, L251-253, L255-258`）。

**内部処理の流れ（アルゴリズム）**

1. **`ToolInvocation` の分解**  
   - `session`, `turn`, `tracker`, `call_id`, `tool_name`, `payload` を取り出します（`L147-153`）。

2. **パッチ入力の抽出**（`payload` の種類に応じて分岐）  
   - `ToolPayload::Function { arguments }` の場合  
     - `parse_arguments(&arguments)?` で `ApplyPatchToolArgs` にパースし（`L157-158`）、`args.input` をパッチ文字列として使用します（`L159`）。
   - `ToolPayload::Custom { input }` の場合  
     - `input` をそのままパッチ文字列として使用します（`L161`）。
   - その他のペイロードはサポート外として `FunctionCallError::RespondToModel` でエラー返却します（`L162-167`）。

3. **環境チェックとコマンドベクタ構築**  
   - `cwd` を `turn.cwd.clone()` から取得します（`L171`）。
   - CLI 風のコマンドベクタ `["apply_patch", patch_input]` を組み立てます（`L172`）。
   - `turn.environment.as_ref()` がなければ「このセッションでは apply_patch が利用できない」としてエラー返却します（`L173-177`）。
   - `environment.get_filesystem()` でファイルシステム実装を取得します（`L178`）。

4. **パッチの検証と解析**  
   - `codex_apply_patch::maybe_parse_apply_patch_verified(&command, &cwd, fs.as_ref()).await` を呼び出します（`L179-180`）。
   - 戻り値 `MaybeApplyPatchVerified` に応じて分岐します（`L181-259`）
     - `Body(changes)` の場合のみパッチ処理に進みます（`L181-243`）。

5. **権限計算とサンドボックスポリシーの決定**  
   - `effective_patch_permissions(session.as_ref(), turn.as_ref(), &changes).await` を呼び出し、  
     `file_paths`, `effective_additional_permissions`, `file_system_sandbox_policy` を取得します（`L182-183`）。  
     これにより、パッチ対象ファイルにもとづいた追加権限などが算出されます。

6. **パッチ適用 or Exec ランタイムへの委譲**  
   - `apply_patch::apply_patch(turn.as_ref(), &file_system_sandbox_policy, changes).await` を実行します（`L184-185`）。
   - 戻り値 `InternalApplyPatchInvocation` に応じて分岐します（`L186-242`）:
     - `Output(item)` の場合  
       - `item?` で `Result` をアンラップし、テキストを `ApplyPatchToolOutput::from_text(content)` に変換して返却します（`L187-190`）。
     - `DelegateToExec(apply)` の場合  
       1. プロトコル形式の変更一覧 `changes` を `convert_apply_patch_to_protocol(&apply.action)` で生成（`L192`）。
       2. `ToolEmitter::apply_patch(changes.clone(), apply.auto_approved)` でツールイベント用のエミッタを生成し（`L193-194`）、`ToolEventCtx` を組み立てて `begin` イベントを送信します（`L195-201`）。
       3. `ApplyPatchRequest` を構築し、`file_paths`, `changes`, `exec_approval_requirement`, `additional_permissions`, `permissions_preapproved`, `timeout_ms: None` を設定します（`L203-213`）。
       4. `ToolOrchestrator::new()` と `ApplyPatchRuntime::new()` を用意し、`ToolCtx`（`session`, `turn`, `call_id`, `tool_name.display()`）を構築します（`L215-222`）。
       5. `orchestrator.run(&mut runtime, &req, &tool_ctx, turn.as_ref(), turn.approval_policy.value()).await` で実行し、`result.output` を取り出します（`L223-232`）。
       6. `ToolEventCtx` を再構築し、`emitter.finish(event_ctx, out).await?` で完了イベントとともに最終出力を取得します（`L233-239`）。
       7. `ApplyPatchToolOutput::from_text(content)` として返却します（`L239-240`）。

7. **その他の `MaybeApplyPatchVerified` ケース**  
   - `CorrectnessError(parse_error)` → `"apply_patch verification failed: {parse_error}"` としてエラー返却（`L244-247`）。
   - `ShellParseError(error)` → `tracing::trace!` でログ出力しつつ、 `"apply_patch handler received invalid patch input"` としてエラー返却（`L249-253`）。
   - `NotApplyPatch` → `"apply_patch handler received non-apply_patch input"` としてエラー返却（`L255-258`）。

**Examples（使用例）**

以下は、このハンドラを直接呼び出す最小イメージ例です（`ToolInvocation` の構築詳細は別モジュールのため省略します）。

```rust
use crate::tools::handlers::apply_patch::ApplyPatchHandler;
use crate::tools::context::ToolInvocation;

// どこかの非同期コンテキスト内
async fn run_apply_patch(invocation: ToolInvocation) -> Result<(), FunctionCallError> {
    let handler = ApplyPatchHandler;                    // フィールド無しのハンドラを生成
    let output = handler.handle(invocation).await?;     // パッチ適用を実行
    println!("{}", output.text());                      // 取得したテキスト出力を利用（仮のメソッド名）
    Ok(())
}
```

`ToolInvocation` の実際の作り方はこのチャンクには現れませんが、実際にはセッションやターン情報、ペイロードとして `ToolPayload::Function` か `ToolPayload::Custom` を含める必要があります（`L156-162`）。

**Errors / Panics**

- `FunctionCallError::RespondToModel` が返される条件:
  - ペイロードが `Function` / `Custom` 以外（`L156-167`）。
  - `turn.environment` が `None` の場合（`L173-177`）。
  - `maybe_parse_apply_patch_verified` が `CorrectnessError` を返した場合（`L244-247`）。
  - `maybe_parse_apply_patch_verified` が `ShellParseError` を返した場合（`L249-253`）。
  - `maybe_parse_apply_patch_verified` が `NotApplyPatch` を返した場合（`L255-258`）。
  - `InternalApplyPatchInvocation::Output(item)` の `item` が `Err` の場合（`L187-188`）。
  - `emitter.finish(event_ctx, out).await` が `Err` の場合（`L239`）。

- パニックの可能性:
  - 本関数内で `unwrap` / `expect` は使用されておらず、外部関数がパニックしない限り、ハンドラ自身はパニックしない構造です。

**Edge cases（エッジケース）**

- ペイロードがサポートされない種類 → 即座にエラー（`L156-167`）。
- `environment` が未設定のターン → `apply_patch is unavailable in this session` でエラー（`L173-177`）。
- 入力が `apply_patch` ではないシェルコマンド文字列 → `NotApplyPatch` としてエラー（`L255-258`）。
- パッチとして構文上は `apply_patch` だが、正当性検証に失敗するケース → `CorrectnessError` → エラー返却（`L244-247`）。
- `ApplyPatchRuntime` 実行中にオーケストレータがエラーを返した場合 → `emitter.finish(...)` 内部から `Err` が返る可能性があります（`L233-239`）。

**使用上の注意点**

- 非同期関数なので、`tokio` などの非同期ランタイム上で `.await` する必要があります（`async fn handle`、`L145`）。
- ファイルシステムに書き込みを行うため、ツールが「ミューテーティング」であることを前提に呼び出すべきです（`is_mutating` が常に `true`、`L141-143`）。
- セッション／ターンに設定されたサンドボックスポリシーと既存権限に応じて、パッチ適用が拒否される可能性があります（`effective_patch_permissions`, `L95-125`）。

---

#### 3.2.2 `intercept_apply_patch(...) -> Result<Option<FunctionToolOutput>, FunctionCallError>`

```rust
pub(crate) async fn intercept_apply_patch(
    command: &[String],
    cwd: &AbsolutePathBuf,
    fs: &dyn ExecutorFileSystem,
    timeout_ms: Option<u64>,
    session: Arc<Session>,
    turn: Arc<TurnContext>,
    tracker: Option<&SharedTurnDiffTracker>,
    call_id: &str,
    tool_name: &str,
) -> Result<Option<FunctionToolOutput>, FunctionCallError>
```

（`core/src/tools/handlers/apply_patch.rs:L265-275`）

**概要**

`exec_command` のような仕組みで任意のコマンドが実行される前に呼び出され、  
そのコマンドが `apply_patch` であれば、このハンドラでパッチ処理を行い、`FunctionToolOutput` として結果を返します。  
そうでなければ `Ok(None)` を返して何もせずに元の処理に戻します（`L276-357`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `command` | `&[String]` | 実行されようとしているコマンドライン引数列（`L266`） |
| `cwd` | `&AbsolutePathBuf` | 実行時のカレントディレクトリ（`L267`） |
| `fs` | `&dyn ExecutorFileSystem` | パッチ検証に使用するファイルシステム実装（`L268`） |
| `timeout_ms` | `Option<u64>` | Exec 委譲時に使用されるタイムアウト（ミリ秒）（`L269, L315`） |
| `session` | `Arc<Session>` | セッションコンテキスト（`L270`） |
| `turn` | `Arc<TurnContext>` | ターンコンテキスト（`L271`） |
| `tracker` | `Option<&SharedTurnDiffTracker>` | 差分トラッキング用オプション参照（`L272, L302, L340`） |
| `call_id` | `&str` | 呼び出し ID（`L273`） |
| `tool_name` | `&str` | このコマンドを発行したツール名（`L274`） |

**戻り値**

- `Ok(Some(FunctionToolOutput))`  
  - `apply_patch` として扱えるコマンドを検出し、パッチ適用または Exec 委譲が成功した場合（`L291-293, L342-343`）。
- `Ok(None)`  
  - `apply_patch` ではない / シェルパースエラーで `apply_patch` として扱えなかった場合（`L353-356`）。
- `Err(FunctionCallError)`  
  - `CorrectnessError`（論理的検証エラー）の場合（`L347-350`）など。

**内部処理の流れ**

1. **パッチコマンドの検証・解析**  
   - `codex_apply_patch::maybe_parse_apply_patch_verified(command, cwd, fs).await` を実行し、  
     シェルコマンドが `apply_patch` として解釈できるか、および正当性を検証します（`L276`）。

2. **`Body(changes)` の場合**（パッチとして認識・検証 OK）  
   - モデルに警告を記録:  
     `session.record_model_warning("apply_patch was requested via {tool_name}. Use the apply_patch tool instead of exec_command.", turn.as_ref()).await`（`L278-285`）。
   - `effective_patch_permissions(session.as_ref(), turn.as_ref(), &changes).await` を呼び出し、  
     `approval_keys`（＝対象ファイルパス）、`effective_additional_permissions`, `file_system_sandbox_policy` を取得します（`L286-287`）。
   - `apply_patch::apply_patch(...)` を呼び出し（`L288-289`）、戻り値に応じて分岐:
     - `Output(item)` → テキストを取り出し、`FunctionToolOutput::from_text(content, Some(true))` で返却（`L291-293`）。
     - `DelegateToExec(apply)` → 以下の Exec 委譲フローへ（`L295-345`）。

3. **Exec 委譲フロー** (`DelegateToExec` の場合)  
   1. プロトコル形式の `changes` を生成（`L296`）。
   2. `ToolEmitter::apply_patch` でエミッタ作成し、`ToolEventCtx` を組み立てて `begin` イベントを送出（`L297-305`）。
   3. `ApplyPatchRequest` を構築し、`file_paths: approval_keys`, `additional_permissions`, `permissions_preapproved`, `timeout_ms` などを設定（`L306-315`）。
   4. `ToolOrchestrator` / `ApplyPatchRuntime` / `ToolCtx` を準備し（`L318-325`）、  
      `run(...)` を実行して `result.output` を取得（`L326-335`）。
   5. `ToolEventCtx` を再度構築し、`emitter.finish(event_ctx, out).await?` で最終出力を取得（`L336-342`）。
   6. `FunctionToolOutput::from_text(content, Some(true))` として返却（`L342-343`）。

4. **その他の `MaybeApplyPatchVerified` ケース**  
   - `CorrectnessError(parse_error)` → 検証エラーとして `Err(FunctionCallError::RespondToModel(...))`（`L347-350`）。
   - `ShellParseError(error)` → `tracing::trace!` でログを残し、`Ok(None)` を返却（`L352-355`）。
   - `NotApplyPatch` → `Ok(None)`（`L356`）。

**Examples（使用例）**

以下は、`exec_command` 相当の実装から `intercept_apply_patch` を利用するイメージです。

```rust
use crate::tools::handlers::apply_patch::intercept_apply_patch;

async fn maybe_intercept_exec(
    command: &[String],
    cwd: &AbsolutePathBuf,
    fs: &dyn ExecutorFileSystem,
    session: Arc<Session>,
    turn: Arc<TurnContext>,
) -> Result<(), FunctionCallError> {
    // 実際には call_id, tool_name, tracker, timeout_ms なども渡す必要があります
    let result = intercept_apply_patch(
        command,
        cwd,
        fs,
        None,                   // タイムアウトはとりあえず未指定
        session,
        turn,
        None,
        "call-123",
        "exec_command",
    ).await?;

    if let Some(tool_output) = result {
        // apply_patch として処理された
        println!("{}", tool_output.text());  // 仮のメソッド
        Ok(())
    } else {
        // apply_patch ではないので通常の exec 処理へ
        // run_exec_command(command, cwd, fs).await?;
        Ok(())
    }
}
```

**Errors / Panics**

- `Err(FunctionCallError)` になる主な条件:
  - 検証段階で `CorrectnessError` が返ってきた場合（`L347-350`）。
  - `apply_patch::apply_patch` が `Err` を含む `Output(item)` を返した場合（`L291-292`）。
  - `emitter.finish(...)` が `Err` を返した場合（`L342`）。
- パニック: この関数内での `unwrap` / `expect` はなく、外部呼び出しがパニックしない限りはパニックしない構造です。

**Edge cases**

- コマンド列が `apply_patch` ではない → `MaybeApplyPatchVerified::NotApplyPatch` → `Ok(None)`（`L276, L356`）。
- `apply_patch` 風ではあるがシェルパースに失敗 → `ShellParseError` → トレースログのみ出して `Ok(None)`（`L352-355`）。
- 正当性検証エラー → モデル向けエラーメッセージとして返却（`L347-350`）。
- Exec 委譲がタイムアウトする可能性があり、その場合の詳細挙動は `ApplyPatchRuntime` / `ToolOrchestrator` 側に依存します（`timeout_ms` を渡している、`L306-315`）。

**使用上の注意点**

- この関数は「`apply_patch` っぽいコマンドだけをツール経由に乗り換える」ためのフックです。  
  普通の `exec_command` のすべてに対して呼び、`Ok(None)` なら元の処理を続行する、という運用が想定されます（戻り値仕様より、`L275-276, L353-356`）。
- `session.record_model_warning` により、「apply_patch は専用ツールを使うべき」という警告が記録される点が特徴です（`L278-285`）。

---

#### 3.2.3 `effective_patch_permissions(...) -> (Vec<AbsolutePathBuf>, EffectiveAdditionalPermissions, FileSystemSandboxPolicy)`

```rust
async fn effective_patch_permissions(
    session: &Session,
    turn: &TurnContext,
    action: &ApplyPatchAction,
) -> (
    Vec<AbsolutePathBuf>,
    crate::tools::handlers::EffectiveAdditionalPermissions,
    codex_protocol::permissions::FileSystemSandboxPolicy,
)
```

（`L95-103`）

**概要**

パッチが影響するファイルパス一覧と、それに基づく追加権限情報、および最終的なファイルシステムサンドボックスポリシーを計算する関数です。`ApplyPatchHandler::handle` と `intercept_apply_patch` の両方で使用されます（`L182-183, L286-287`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `session` | `&Session` | セッション単位で付与された権限を取得するために使用（`L96, L105-107`） |
| `turn` | `&TurnContext` | ターン固有のサンドボックスポリシーと権限を取得するために使用（`L97, L109-112, L116-117`） |
| `action` | `&ApplyPatchAction` | パッチ内容（変更対象ファイルなど）を表すオブジェクト（`L98, L104`） |

**戻り値**

タプル:

1. `Vec<AbsolutePathBuf>`: パッチが操作するファイルの絶対パス一覧（`file_paths`、`L104, L120-121`）
2. `EffectiveAdditionalPermissions`: 追加権限と「事前承認済みかどうか」の情報（別モジュール定義、`L101, L113-118, L208-211, L311-314`）
3. `FileSystemSandboxPolicy`: 実効的なファイルシステムサンドボックスポリシー（`L102, L109-112, L123-124`）

**内部処理の流れ**

1. `file_paths_for_action(action)` でファイルパス一覧を生成（`L104`）。
2. `session.granted_session_permissions().await` と `session.granted_turn_permissions().await` を取得し（`L105-107`）、`merge_permission_profiles` で統合（`L105-108`）。
3. `effective_file_system_sandbox_policy(&turn.file_system_sandbox_policy, granted_permissions.as_ref())` によって、ターンのサンドボックスポリシーと統合済み権限から実効ポリシーを計算（`L109-112`）。
4. `write_permissions_for_paths(&file_paths, &file_system_sandbox_policy, &turn.cwd)` で必要な追加書き込み権限（`PermissionProfile`）を計算し（`L116`）、  
   それを `apply_granted_turn_permissions` に渡して `EffectiveAdditionalPermissions` を得る（`L113-118`）。
5. `(file_paths, effective_additional_permissions, file_system_sandbox_policy)` を返却（`L120-124`）。

**使用上の注意点**

- 追加権限の算出は `write_permissions_for_paths` が `Option<PermissionProfile>` を返す設計になっているため（`L63-93`）、  
  何らかの理由でパス変換に失敗した場合には「追加権限なし」として扱われる可能性があります（`ok()?` による早期 `None`、`L81-82`）。
- セッション・ターンの権限取得は `await` を伴うため、この関数自体も `async` になっています（`L95`）。

---

#### 3.2.4 `write_permissions_for_paths(file_paths, file_system_sandbox_policy, cwd) -> Option<PermissionProfile>`

**概要**

パッチで書き込みが行われる可能性のあるファイル群から、  
「現状のサンドボックスポリシーでは書き込めないディレクトリ」のみを抽出し、  
それらに対する追加権限 `PermissionProfile` を生成する関数です（`L63-93`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `file_paths` | `&[AbsolutePathBuf]` | パッチで操作されるファイルの絶対パス（`L64, L68`） |
| `file_system_sandbox_policy` | `&FileSystemSandboxPolicy` | 現在のサンドボックスポリシー（`L65, L75-77`） |
| `cwd` | `&AbsolutePathBuf` | カレントディレクトリ（`L66, L76-77`） |

**戻り値**

- `Some(PermissionProfile)`  
  - 少なくとも一つのディレクトリが追加書き込み権限を必要とすると判断された場合（`L84-90`）。
- `None`  
  - 追加権限が不要、またはパス変換・正規化の過程で失敗した場合（`L81-82, L84`）。

**内部処理の流れ**

1. `file_paths` をイテレートし、各パスの親ディレクトリを取得（`path.parent()`、`L70-73`）。
   - 親が存在しない場合は自身を使います（`unwrap_or_else(|| path.clone())`、`L71-72`）。
2. 各ディレクトリについて、`file_system_sandbox_policy.can_write_path_with_cwd(path.as_path(), cwd.as_path())` で書き込み可否を判定し、書き込み不可なものだけを残します（`L75-77`）。
3. 重複を `BTreeSet` で排除しつつ収集（`L78-79`）。
4. 各ディレクトリを `AbsolutePathBuf::from_absolute_path` で `AbsolutePathBuf` に変換し（`L80`）、  
   `collect::<Result<Vec<_>, _>>().ok()?` によってエラー時は `None` を返します（`L80-82`）。
5. 非空であれば `PermissionProfile { file_system: Some(FileSystemPermissions { read: Some(vec![]), write: Some(write_paths) }), ..Default::default() }` を生成し（`L84-89`）、  
   `normalize_additional_permissions(permissions).ok()` を通して正規化した結果を返します（`L92`）。

**Edge cases**

- `file_paths` が空 → `write_paths` も空となり、`(!write_paths.is_empty())` が `false` のため `None` を返します（`L68-69, L84`）。
- すべてのパスがすでに書き込み可能 → フィルタにより `write_paths` が空となり、やはり `None`（`L75-77, L84`）。
- `AbsolutePathBuf::from_absolute_path` が一つでも失敗 → `.ok()?` により即 `None`（`L80-82`）。
- `normalize_additional_permissions` がエラー → `.ok()` により `None`（`L92`）。

**使用上の注意点**

- `None` は「追加権限が不要」なケースと、「追加権限の計算に失敗した」ケースの両方を含むことに注意が必要です（`L81-82, L92`）。
- 返される `PermissionProfile` は `file_system.write` にのみパスが設定され、`read` は空リスト（`Some(vec![])`）になっています（`L85-87`）。

---

#### 3.2.5 `file_paths_for_action(action: &ApplyPatchAction) -> Vec<AbsolutePathBuf>`

**概要**

`ApplyPatchAction` に含まれる変更セットから、  
パッチの適用対象ファイル（ソースと移動先）を絶対パスとして列挙します（`L39-57`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `action` | `&ApplyPatchAction` | パッチ内容（カレントディレクトリ `cwd` や変更一覧を含む）（`L39-41`） |

**戻り値**

- 対象ファイルの絶対パスを `Vec<AbsolutePathBuf>` で返します（`L39, L56`）。

**内部処理の流れ**

1. `keys` という空の `Vec` を作成（`L40`）。
2. `cwd` を `&action.cwd` から取得（`L41`）。
3. `action.changes()` をイテレートし、`(path, change)` それぞれについて（`L43`）:
   - `to_abs_path(cwd, path)` で元パスを絶対パスに変換し、`Some(key)` なら `keys.push(key)`（`L44-45`）。
   - さらに、`change` が `ApplyPatchFileChange::Update { move_path, .. }` であり、`move_path` が `Some(dest)` の場合、  
     `to_abs_path(cwd, dest)` で移動先パスも `keys` に追加（`L48-53`）。
4. 最終的な `keys` を返却（`L56`）。

**使用上の注意点**

- `to_abs_path` は現状常に `Some(...)` を返す実装ですが（`L59-61`）、`file_paths_for_action` 側では安全のため `Option` をチェックしています（`L44-45, L50-51`）。
- `ApplyPatchFileChange` の他のバリアント（追加・削除など）がある場合、それらは `action.changes()` の戻り値の内容に依存しますが、このチャンクでは詳細は分かりません。

---

#### 3.2.6 `to_abs_path(cwd: &AbsolutePathBuf, path: &Path) -> Option<AbsolutePathBuf>`

**概要**

`cwd` と相対パス（または絶対パス）から、`AbsolutePathBuf` を生成する薄いラッパー関数です（`L59-61`）。

**実装**

- `AbsolutePathBuf::resolve_path_against_base(path, cwd)` を呼び出し、その結果を `Some(...)` で包んで返します（`L60`）。
- 現在のコードでは `None` になることはありませんが、呼び出し側では `Option` として扱っています（`L44-45, L50-51`）。

---

### 3.3 その他の関数

| 関数名 | シグネチャ（抜粋） | 位置 | 役割（1 行） |
|--------|--------------------|------|--------------|
| `ApplyPatchHandler::kind` | `fn kind(&self) -> ToolKind` | `L130-132` | ハンドラ種別として `ToolKind::Function` を返す |
| `ApplyPatchHandler::matches_kind` | `fn matches_kind(&self, payload: &ToolPayload) -> bool` | `L134-139` | `Function` / `Custom` ペイロードのときのみ対応することを示す |
| `ApplyPatchHandler::is_mutating` | `async fn is_mutating(&self, _invocation: &ToolInvocation) -> bool` | `L141-143` | このツールが状態を変更する（ファイルを書き換える）ことを表明する |

---

## 4. データフロー

ここでは代表的な 2 つのシナリオについて、データフローを整理します。

### 4.1 apply_patch ツール呼び出し（ApplyPatchHandler::handle）

このシナリオでは、モデルが `apply_patch` ツールを直接呼び出したときの流れを示します。

```mermaid
sequenceDiagram
  participant M as モデル
  participant T as ツール層
  participant H as ApplyPatchHandler::handle<br/>(L145-261)
  participant V as maybe_parse_apply_patch_verified
  participant P as apply_patch::apply_patch
  participant R as ToolOrchestrator.run<br/>+ ApplyPatchRuntime
  participant E as ToolEmitter

  M->>T: apply_patch ツール呼び出し
  T->>H: ToolInvocation<br/>(session, turn, payload, ...)
  H->>H: payload から patch_input 抽出 (L156-162)
  H->>V: maybe_parse_apply_patch_verified(command, cwd, fs) (L179-180)
  V-->>H: MaybeApplyPatchVerified::{Body, ...} (L181-259)

  alt Body(changes)
    H->>H: effective_patch_permissions(...) 計算 (L182-183)
    H->>P: apply_patch(turn, policy, changes) (L184-185)
    alt Output(item)
      P-->>H: InternalApplyPatchInvocation::Output(item) (L186-190)
      H-->>T: ApplyPatchToolOutput (L187-190)
    else DelegateToExec(apply)
      P-->>H: InternalApplyPatchInvocation::DelegateToExec(apply) (L191-242)
      H->>E: E = ToolEmitter::apply_patch(...); E.begin(...) (L193-201)
      H->>R: run(runtime, ApplyPatchRequest, ToolCtx, ...) (L203-213,223-232)
      R-->>H: result.output (L223-232)
      H->>E: E.finish(event_ctx, out) (L233-239)
      E-->>H: content
      H-->>T: ApplyPatchToolOutput (L239-240)
    end
  else その他 (CorrectnessError, ShellParseError, NotApplyPatch)
    H-->>T: Err(FunctionCallError) (L244-258)
  end
```

この図から分かるポイント:

- パッチは常に `maybe_parse_apply_patch_verified` で検証されてから適用されます（`L179-181`）。
- 直接適用できる場合 (`Output`) と、Exec ランタイムへの委譲が必要な場合 (`DelegateToExec`) の 2 パターンがあります（`L186-242`）。
- Exec 委譲時は `ToolEmitter` による開始・終了イベントが必ず発行されます（`L193-201, L233-239`）。

### 4.2 exec_command 経由の apply_patch 呼び出し（intercept_apply_patch）

こちらは、一般の `exec_command` 呼び出しから `apply_patch` を検出し、インターセプトするシナリオです。

```mermaid
sequenceDiagram
  participant E as exec_command 呼び出し元
  participant I as intercept_apply_patch<br/>(L265-357)
  participant V as maybe_parse_apply_patch_verified
  participant S as Session
  participant P as apply_patch::apply_patch
  participant R as ToolOrchestrator.run<br/>+ ApplyPatchRuntime
  participant EM as ToolEmitter

  E->>I: command, cwd, fs, session, turn, ...
  I->>V: maybe_parse_apply_patch_verified(command, cwd, fs) (L276)
  V-->>I: MaybeApplyPatchVerified::{Body, ...} (L277-357)

  alt Body(changes)
    I->>S: record_model_warning("apply_patch was requested via ...") (L278-285)
    I->>I: effective_patch_permissions(...) (L286-287)
    I->>P: apply_patch(turn, policy, changes) (L288-289)
    alt Output(item)
      P-->>I: InternalApplyPatchInvocation::Output(item) (L291-293)
      I-->>E: Some(FunctionToolOutput) (L291-293)
    else DelegateToExec(apply)
      P-->>I: InternalApplyPatchInvocation::DelegateToExec(apply) (L295-345)
      I->>EM: ToolEmitter::apply_patch(...); EM.begin(...) (L297-305)
      I->>R: run(runtime, ApplyPatchRequest, ToolCtx, ...) (L306-315,326-335)
      R-->>I: result.output (L326-335)
      I->>EM: EM.finish(event_ctx, out) (L336-342)
      EM-->>I: content
      I-->>E: Some(FunctionToolOutput) (L342-343)
    end
  else ShellParseError or NotApplyPatch
    I-->>E: Ok(None) (L352-356)
  else CorrectnessError
    I-->>E: Err(FunctionCallError) (L347-350)
  end
```

ここから:

- `exec_command` 系の呼び出しは、`apply_patch` であるかどうかに関わらず `intercept_apply_patch` に渡される設計が想定されます（`戻り値 Option`、`L275-276`）。
- `apply_patch` と判定された場合のみ `Some(FunctionToolOutput)` を返し、同時にモデルに警告を記録します（`L278-285, L291-293, L342-343`）。

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

#### ApplyPatchHandler をツールとして利用する

`ApplyPatchHandler` は `ToolHandler` トレイトを実装しているため、ツールレジストリ・オーケストレータに登録して利用する形が想定されます（`L127-143`）。

```rust
use crate::tools::handlers::apply_patch::ApplyPatchHandler;
use crate::tools::registry::{ToolHandler, ToolKind};
// use crate::tools::context::ToolInvocation;

fn register_tools(registry: &mut ToolRegistry) {
    let handler = ApplyPatchHandler;                   // フィールド不要のハンドラ
    registry.register("apply_patch", Box::new(handler));
}

// 実行時にはオーケストレータが ToolInvocation を構築して handle を呼ぶイメージ
```

`ToolInvocation` の具体的な生成方法はこのチャンクにはありませんが、`ApplyPatchHandler::handle` 内で利用しているフィールドから、少なくとも `session`, `turn`, `payload` 等が必要なことが分かります（`L147-153`）。

### 5.2 よくある使用パターン

1. **モデルが apply_patch ツールを直接呼ぶパターン**  
   - `ToolPayload::Function` として JSON 形式の `arguments` を渡し、`ApplyPatchToolArgs` でパースされます（`L157-159`）。
   - これが最も推奨されるパターンと考えられます（`intercept_apply_patch` で警告している文言からの推測、`L278-285`）。

2. **exec_command で apply_patch コマンドを書いてしまうパターン**  
   - `intercept_apply_patch` がこのコマンドを検出し、同じパッチ機構に乗せ替えます（`L276-357`）。
   - その際、モデルに「apply_patch ツールを使うように」という警告が記録されます（`L278-285`）。

### 5.3 よくある間違い

```rust
// 間違い例: apply_patch ツールではなく、exec_command から apply_patch を実行し続ける
// => intercept_apply_patch が毎回警告を記録し、ログがノイズになる可能性がある
exec_command("apply_patch", vec![patch_body]).await;

// 正しい例: apply_patch 専用ツールを使う (payload は Function か Custom として渡す)
let invocation = ToolInvocation {
    // ...
    tool_name: "apply_patch".into(),
    payload: ToolPayload::Function { arguments: /* ApplyPatchToolArgs 相当 */ },
};
let handler = ApplyPatchHandler;
let output = handler.handle(invocation).await?;
```

上記のように、`apply_patch` 専用ツールを使うことで、権限管理やイベント発行などの処理が一貫して適用されます（`L145-261`）。

### 5.4 使用上の注意点（まとめ）

- **前提条件**
  - `turn.environment` が設定されていること（`L173-177`）。
  - `Session` / `TurnContext` に適切なサンドボックスポリシー・権限が設定されていること（`L105-112`）。
- **エラー時の挙動**
  - パッチ検証エラー (`CorrectnessError`) はモデル向けメッセージで即座に返却されます（`L244-247, L347-350`）。
  - シェルパースエラーや非 apply_patch コマンドは、ツールハンドラではなく元の exec 処理にフォールバックさせる設計です（`L249-253, L352-356`）。
- **並行性**
  - すべての処理は非同期で、`Session` / `TurnContext` は `Arc` 共有されるため、同一セッション内で複数の `apply_patch` を並列実行することが可能な設計です（`L270-272, L217-220`）。
- **観測性**
  - `ToolEmitter::apply_patch` と `ToolEventCtx` により、開始・終了イベントが発行され、UI やログから apply_patch 実行状況を追跡しやすくなっています（`L193-201, L233-239, L297-305, L336-342`）。

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

このファイルのコードから読み取れる範囲で、変更の入口を整理します。

- **権限計算ロジックを変更したい場合**
  - 参照すべき箇所:  
    - `file_paths_for_action`（対象パスの抽出、`L39-57`）  
    - `write_permissions_for_paths`（追加書き込み権限の生成、`L63-93`）  
    - `effective_patch_permissions`（既存権限とのマージ、`L95-125`）
  - 例: 「読み取り権限も追加したい」などの要件がある場合は、`FileSystemPermissions { read, write }` を構築している箇所（`L84-88`）を変更することになります。

- **Exec 委譲時のタイムアウトやオプションを拡張したい場合**
  - `ApplyPatchRequest` に `timeout_ms` やその他フィールドを設定している箇所を確認します（`L203-213, L306-315`）。
  - `ToolCtx` や `ToolOrchestrator::run` に渡している引数を増やす必要がある場合、ここを起点に辿るのが自然です（`L215-222, L326-333`）。

### 6.2 既存の機能を変更する場合

- **影響範囲の確認**
  - `ApplyPatchHandler::handle` と `intercept_apply_patch` の両方が `effective_patch_permissions` および `apply_patch::apply_patch` を呼び出しているため（`L182-185, L286-289`）、  
    これらの関数の仕様を変更すると、両方の経路に影響します。
- **契約（前提条件・返り値の意味）**
  - `effective_patch_permissions` は「`file_paths`, `EffectiveAdditionalPermissions`, `FileSystemSandboxPolicy`」という 3 要素を返す契約になっており、  
    呼び出し元では `file_paths` を承認キーとして利用しています（`ApplyPatchRequest.file_paths`、`L205, L308`）。
  - `write_permissions_for_paths` が `None` を返すのは「追加不要」または「計算失敗」の両方を意味するため、  
    ここを厳密に区別したい場合はインターフェース変更が必要になります（`L81-82, L84, L92`）。
- **テスト確認**
  - このファイルには `mod tests;` があり、`apply_patch_tests.rs` にテストが存在することが示されています（`L360-362`）。  
    テスト内容の詳細はこのチャンクには現れませんが、変更時にはこのテストモジュールを確認・更新する必要があります。

---

## 7. 関連ファイル

このモジュールと密接に関係するファイル・モジュールを一覧にします（名称と使用され方からの推測を含みます。詳細実装はこのチャンクには現れません）。

| パス / モジュール | 役割 / 関係 |
|-------------------|------------|
| `crate::apply_patch` | `apply_patch::apply_patch` 関数と `InternalApplyPatchInvocation` 型を提供し、実際のパッチ適用および Exec 委譲の分岐を行います（`L3-5, L184-191, L288-296`）。 |
| `crate::apply_patch::convert_apply_patch_to_protocol` | `ApplyPatchAction` をプロトコルレベルの変更表現に変換する関数で、イベントおよび Exec 実行時に利用されます（`L5, L192, L296`）。 |
| `codex_apply_patch` クレート | `ApplyPatchAction`, `ApplyPatchFileChange`, `maybe_parse_apply_patch_verified`, `MaybeApplyPatchVerified` など、パッチのパースと検証ロジックを提供します（`L24-25, L179-181, L276-277`）。 |
| `crate::tools::runtimes::apply_patch::{ApplyPatchRequest, ApplyPatchRuntime}` | Exec ランタイムで `apply_patch` を実行するためのリクエスト構造体とランタイム実装であり、`ToolOrchestrator::run` と組み合わせて使用されます（`L21-22, L203-213, L306-315, L215-217, L318-320`）。 |
| `crate::tools::orchestrator::ToolOrchestrator` | ツールランタイムを実行し、結果を返すオーケストレータです（`L18, L215-216, L318-319, L223-232, L326-335`）。 |
| `crate::tools::events::{ToolEmitter, ToolEventCtx}` | ツール実行開始・終了などのイベントを発行し、UI やログに連携するために使用されます（`L14-15, L193-201, L233-239, L297-305, L336-342`）。 |
| `crate::tools::context::{ApplyPatchToolOutput, FunctionToolOutput, SharedTurnDiffTracker, ToolInvocation, ToolPayload}` | ツールハンドラとオーケストレータ間でやりとりされるコンテキスト・出力型・差分トラッカーなどを定義するモジュールです（`L9-13, L11-12, L147-153, L270-272`）。 |
| `codex_protocol::models::{PermissionProfile, FileSystemPermissions}` | 追加権限を表現するモデル型で、`write_permissions_for_paths` にて使用されています（`L27-28, L84-88`）。 |
| `codex_sandboxing::policy_transforms::{effective_file_system_sandbox_policy, merge_permission_profiles, normalize_additional_permissions}` | セッション/ターンの権限プロファイルを統合し、サンドボックスポリシーや追加権限を正規化する関数群です（`L29-31, L105-112, L92`）。 |
| `codex_exec_server::ExecutorFileSystem` | パッチ検証プロセスで用いるファイルシステム抽象化であり、`intercept_apply_patch` と `handle` から利用されます（`L26, L178, L268`）。 |
| `core/src/tools/handlers/apply_patch_tests.rs` | `#[cfg(test)]` でインクルードされているテストモジュール。具体的なテストケースはこのチャンクには現れません（`L360-362`）。 |

---

以上が `core/src/tools/handlers/apply_patch.rs` の構造とデータフロー、主要 API の動き、および安全性・エラーハンドリング・並行性の観点を含めた解説です。
