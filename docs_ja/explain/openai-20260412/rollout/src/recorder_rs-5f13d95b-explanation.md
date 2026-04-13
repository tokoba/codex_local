## 0. ざっくり一言

Codex の「セッションロールアウト」（会話ストリーム）を JSONL ファイルとして永続化し、  
一覧・再開・メタデータ更新を行うための非同期レコーダと、そのバックグラウンドライタタスクを実装したモジュールです。  
（根拠: `rollout/src/recorder.rs:L1-1253`）

---

## 1. このモジュールの役割

### 1.1 概要

- このモジュールは **セッション中の RolloutItem 群を安全かつ非同期にディスクへ保存**し、  
  後から **一覧・検索・再開（resume）** できるようにするために存在します。
- JSONL ファイルを単なるログとして書くだけでなく、SQLite ベースの `state_db` と同期し、  
  セッション一覧・メタデータ更新を DB 側と整合させる役割も持ちます。  
  （根拠: `RolloutRecorder`・`rollout_writer`・`sync_thread_state_after_write` の定義  
  `rollout/src/recorder.rs:L1-1253`）

### 1.2 アーキテクチャ内での位置づけ

主なコンポーネント間の関係を簡易に図示します。

```mermaid
flowchart LR
    subgraph Client["呼び出し側コード"]
        A["RolloutRecorder インスタンス"]
    end

    subgraph RecorderMod["recorder.rs (rollout/src/recorder.rs:L1-1253)"]
        A -->|RolloutCmd (mpsc)| B["rollout_writer タスク"]
        B -->|JsonlWriter| C["ロールアウト JSONL ファイル"]
        B -->|apply_rollout_items / touch_thread_updated_at| D["state_db (SQLite)"]
    end

    subgraph ListMod["list モジュール (super::list)"]
        E["get_threads / get_threads_in_root"] --> A
    end

    subgraph MetadataMod["metadata モジュール"]
        F["builder_from_session_meta / builder_from_items"] --> D
    end
```

- `RolloutRecorder` は、呼び出し側から `record_items` / `persist` / `flush` / `shutdown` などの API で操作されます。
- 実際の I/O（ファイル書き込み・DB 更新）は、Tokio タスク `rollout_writer` 内で行われます。
- スレッド一覧や検索は `super::list` 系関数に委譲しつつ、必要に応じて `state_db` へ read-repair や fallback を行います。  
  （根拠: `list_threads_with_db_fallback`, `rollout_writer`, `sync_thread_state_after_write`  
  `rollout/src/recorder.rs:L1-1253`）

### 1.3 設計上のポイント

- **非同期・バックグラウンド I/O**
  - 呼び出し元スレッドでは I/O を行わず、`mpsc::Sender<RolloutCmd>` 経由でコマンドを送り、  
    バックグラウンドの Tokio タスク `rollout_writer` が実際のファイル書き込みを担当します。  
    （`RolloutRecorder::new`・`rollout_writer`）
- **バッファリングとリカバリ**
  - `RolloutWriterState.pending_items` に一旦キューし、書き込み成功後にだけ削除します。
  - I/O エラー発生時はファイルハンドルを破棄して「リカバリモード」に入り、  
    次回の `persist` / `flush` / `shutdown` で再オープンして再試行します。  
    （`write_pending_with_recovery`, `enter_recovery_mode`）
- **メタデータと DB 同期**
  - 最初の `SessionMeta` をファイルと DB の両方に書き込み、  
    以降の `RolloutItem` に応じて `state_db::apply_rollout_items` / `touch_thread_updated_at` を呼び出します。
- **状態観測 (observability)**
  - `RolloutWriterTask` が `terminal_failure` を保持し、以後の API 呼び出しで  
    「バックグラウンドタスクが落ちた」ことをエラーとして返せるようになっています。  
    （`RolloutWriterTask::terminal_failure`, 各 API の `map_err` 部）
- **EventPersistenceMode による情報削減**
  - `EventPersistenceMode::Extended` の場合、`ExecCommandEnd` の aggregated_output を所定サイズでトリムし、  
    そのほかの大きなフィールドは破棄してストレージ負荷を抑えます。  
    （`sanitize_rollout_item_for_persistence`）

（すべての根拠: `rollout/src/recorder.rs:L1-1253`）

---

## 2. 主要な機能一覧とコンポーネントインベントリー

### 2.1 主要な機能

- **セッションロールアウトの記録**
  - `RolloutRecorder::record_items` による `RolloutItem` の非同期記録。
- **ロールアウトファイルの永続化とフラッシュ**
  - `persist` / `flush` / `shutdown` によるバリア操作と、  
    I/O エラー時の再オープン・再試行。
- **ロールアウト履歴の再読み込み**
  - `load_rollout_items`・`get_rollout_history` による JSONL からの履歴復元。
- **スレッド一覧・検索・最新スレッドの探索**
  - `list_threads` / `list_archived_threads` / `find_latest_thread_path`。
- **既存ロールアウトへの単発追記**
  - `append_rollout_item_to_path` によるメタデータ更新のための追記。
- **SQLite ベースの state_db との同期**
  - `sync_thread_state_after_write` を通じた DB 更新・`updated_at` の更新。  

（根拠: 各関数定義 `rollout/src/recorder.rs:L1-1253`）

### 2.2 型コンポーネント一覧（公開・内部）

| 型名 | 種別 | 公開範囲 | 役割 / 用途 | 定義位置 |
|------|------|----------|------------|----------|
| `RolloutRecorder` | 構造体 | `pub` | セッションロールアウトの高レベル録画 API。非同期タスクへのコマンド送信とパス/DB ハンドル保持。 | `rollout/src/recorder.rs:L1-1253` |
| `RolloutRecorderParams` | 列挙体 | `#[derive(Clone)] pub` | レコーダ生成時のモード: 新規作成 (`Create`) または既存ロールアウトからの再開 (`Resume`)。 | 同上 |
| `RolloutCmd` | 列挙体 | モジュール内 | `AddItems`/`Persist`/`Flush`/`Shutdown` など、バックグラウンドタスクに送るコマンド。 | 同上 |
| `RolloutWriterTask` | 構造体 | モジュール内 | バックグラウンドタスクの `JoinHandle` と、タスク終了時の `terminal_failure` を保持する観測用オブジェクト。 | 同上 |
| `LogFileInfo` | 構造体 | モジュール内 | ロールアウトファイルのフルパス、セッション ID、開始時刻を保持する情報。新規セッション用。 | 同上 |
| `RolloutWriterState` | 構造体 | モジュール内 | `rollout_writer` タスク内のミュータブル状態。ファイルハンドル、ペンディングアイテム、メタデータ、DB コンテキストなどを保持。 | 同上 |
| `JsonlWriter` | 構造体 | モジュール内 | `tokio::fs::File` に対する JSONL 行の書き込みユーティリティ。 | 同上 |
| `RolloutLineRef<'a>` | 構造体 | モジュール内 (`serde::Serialize`) | JSONL 一行ぶんのシリアライズ用ビュー。タイムスタンプ + `RolloutItem`。 | 同上 |

※ 行番号はファイル全体に対する範囲として示しています（このチャンクには個別行番号情報が含まれていません）。

### 2.3 関数コンポーネント一覧（概要）

> 公開 API を中心に列挙し、内部ヘルパーはグルーピングしています。

#### 公開メソッド / 関数

| 名前 | 所属 | 役割 / 概要 | 定義位置 |
|------|------|------------|----------|
| `RolloutRecorder::list_threads` | impl | Codex ホーム配下の通常セッション一覧を返す。state_db を使い FS と DB を組み合わせて取得。 | `rollout/src/recorder.rs:L1-1253` |
| `RolloutRecorder::list_archived_threads` | impl | アーカイブセッション一覧を返す。 | 同上 |
| `RolloutRecorder::find_latest_thread_path` | impl | （フィルタ条件に合う）最新スレッドのロールアウトファイルパスを返す。DB→FS の順に探索。 | 同上 |
| `RolloutRecorder::new` | impl | 新規作成または再開モードでレコーダを生成し、バックグラウンド writer タスクを spawn する。 | 同上 |
| `RolloutRecorder::rollout_path` | impl | ロールアウトファイルの `Path` 参照を返す。 | 同上 |
| `RolloutRecorder::state_db` | impl | 内部に保持している `StateDbHandle`（Option）をクローンして返す。 | 同上 |
| `RolloutRecorder::record_items` | impl | `RolloutItem` 配列をフィルタ・サニタイズし、`AddItems` コマンドとして非同期送信する。 | 同上 |
| `RolloutRecorder::persist` | impl | `Persist` コマンドを送り、書き込み完了まで待機。ファイルの materialize と保留アイテムの書き込みを行う。 | 同上 |
| `RolloutRecorder::flush` | impl | `Flush` コマンドを送り、ペンディングアイテムの書き込み完了まで待機。 | 同上 |
| `RolloutRecorder::load_rollout_items` | impl | ロールアウト JSONL ファイルを読み込み、`Vec<RolloutItem>` と `ThreadId`・パース失敗数を返す。 | 同上 |
| `RolloutRecorder::get_rollout_history` | impl | ロールアウトファイルを読み出し、`InitialHistory::New` または `InitialHistory::Resumed` を返す。 | 同上 |
| `RolloutRecorder::shutdown` | impl | `Shutdown` コマンドを送り、ペンディングアイテムの書き込み完了とタスク終了を待機する。 | 同上 |
| `RolloutRecorderParams::new` | impl | `Create` バリアントを生成するコンストラクタ。 | 同上 |
| `RolloutRecorderParams::resume` | impl | `Resume` バリアントを生成するコンストラクタ。 | 同上 |
| `append_rollout_item_to_path` | free fn | 既存ロールアウトファイルに 1 つの `RolloutItem` を追記するユーティリティ。 | 同上 |
| `impl From<codex_state::ThreadsPage> for ThreadsPage` | impl | DB 側のページ構造から表示用 `ThreadsPage` への変換（フィールドマッピングと JSON デコード）。 | 同上 |

#### 主な内部ヘルパー（グルーピング）

- スレッド一覧・再開補助
  - `list_threads_with_db_fallback`
  - `truncate_fs_page`
  - `select_resume_path`
  - `select_resume_path_from_db_page`
  - `resume_candidate_matches_cwd`
  - `cwd_matches`
- ファイルパス生成・オープン
  - `precompute_log_file_info`
  - `open_log_file`
- バックグラウンド writer タスク
  - `rollout_writer`
  - `RolloutWriterState::{new, add_items, flush_if_materialized, persist, flush, shutdown, write_pending_with_recovery, is_deferred, enter_recovery_mode, ensure_writer_open, write_session_meta_if_needed, write_pending_once, write_pending_items_once}`
  - `write_session_meta`
  - `sync_thread_state_after_write`
  - `JsonlWriter::{write_rollout_item, write_line}`
  - `sanitize_rollout_item_for_persistence`
  - `clone_io_error`

（根拠: すべて `rollout/src/recorder.rs:L1-1253`）

---

## 3. 公開 API と詳細解説（主要 7 件）

### 3.1 型一覧（公開主要型）

| 名前 | 種別 | 役割 / 用途 | 主なフィールド / バリアント | 根拠 |
|------|------|-------------|-----------------------------|------|
| `RolloutRecorder` | 構造体 | セッションロールアウト記録のフロントエンド。バックグラウンド writer タスクへのコマンド送信、ロールアウトパスと DB ハンドル保持。 | `tx: Sender<RolloutCmd>`, `writer_task: Arc<RolloutWriterTask>`, `rollout_path: PathBuf`, `state_db: Option<StateDbHandle>`, `event_persistence_mode: EventPersistenceMode` | `rollout/src/recorder.rs:L1-1253` |
| `RolloutRecorderParams` | 列挙体 | レコーダ生成時のモード指定。新規作成 (`Create`) / 再開 (`Resume`) の 2 種類。 | `Create { conversation_id, forked_from_id, source, base_instructions, dynamic_tools, event_persistence_mode }` / `Resume { path, event_persistence_mode }` | 同上 |

### 3.2 関数詳細（7 件）

#### 1. `RolloutRecorder::new(...) -> std::io::Result<RolloutRecorder>`

**概要**

- 新規セッションまたは既存ロールアウトからの再開のための `RolloutRecorder` を構築し、  
  バックグラウンドの writer タスク (`rollout_writer`) を spawn します。  
  （根拠: `rollout/src/recorder.rs:L1-1253`）

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `config` | `&impl RolloutConfigView` | Codex ホームディレクトリ、CWD、モデルプロバイダなどの設定ビュー。 |
| `params` | `RolloutRecorderParams` | `Create` or `Resume`。前者は新規ファイルのパスと SessionMeta を事前計算、後者は既存ファイルを開く。 |
| `state_db_ctx` | `Option<StateDbHandle>` | SQLite state DB へのハンドル。ない場合はファイルシステムのみで動作。 |
| `state_builder` | `Option<ThreadMetadataBuilder>` | スレッドメタデータの初期構築用ビルダ。 |

**戻り値**

- `Ok(RolloutRecorder)` : writer タスクの spawn に成功し、初期化できた場合。
- `Err(IoError)` : ファイルオープン等で I/O エラーがあった場合。

**内部処理の流れ**

1. `params` をマッチ:
   - `Create`:
     - `precompute_log_file_info` で `LogFileInfo{path, conversation_id, timestamp}` を生成。
     - `SessionMeta` を組み立て（cwd, originator, cli_version, agent 情報, model_provider, base_instructions, dynamic_tools, memory_mode など）。
     - この段階ではファイルはまだ作成せず、`deferred_log_file_info` として保持。
   - `Resume`:
     - `tokio::fs::OpenOptions::new().append(true).open(&path)` で既存ファイルを開き `file: Some(tokio::fs::File)` とする。
2. `mpsc::channel::<RolloutCmd>(256)` を作成し、`tx` と `rx` を得る。
3. `RolloutWriterTask::new()` により writer タスク観測用の状態を作成。
4. `tokio::task::spawn` で `rollout_writer` を起動し、`RolloutWriterState::new` に初期状態を渡す。
5. spawn した `JoinHandle` を `writer_task.set_handle` により保持。
6. `RolloutRecorder` インスタンスを返す。

**Examples（使用例）**

```rust
async fn start_session(config: &impl RolloutConfigView,
                       thread_id: ThreadId,
                       source: SessionSource) -> std::io::Result<RolloutRecorder> {
    // 新規セッション作成パラメータを構築                       // Create モードで実行
    let params = RolloutRecorderParams::new(
        thread_id,
        None,                                       // forked_from_id
        source,
        BaseInstructions::default(),               // ここではダミー
        Vec::new(),                                // dynamic_tools なし
        EventPersistenceMode::Extended,
    );

    // state_db を使う場合                                             // SQLite コンテキストを取得
    let state_db_ctx = crate::state_db::get_state_db(config).await;

    // レコーダを生成                                                   // バックグラウンド writer が spawn される
    RolloutRecorder::new(config, params, state_db_ctx, None).await
}
```

**Errors / Panics**

- `Resume` モードでの `tokio::fs::OpenOptions::open` 失敗時、`Err(IoError)` を返します。
- `Create` モードでは `OffsetDateTime::now_local` や `format` の失敗により `IoError::other` が返る可能性があります。
- Mutex ロック時には `unwrap_or_else(PoisonError::into_inner)` が使われており、  
  ロック毒化時も panic ではなく中身を取り出して継続します。  
  （根拠: `RolloutWriterTask::set_handle` 他）

**Edge cases（エッジケース）**

- `state_db_ctx == None` の場合でも正常に動作し、後続の処理で FS ベースの挙動にフォールバックします。
- `Create` モードで `dynamic_tools` が空なら `dynamic_tools: None` として保存されます。

**使用上の注意点**

- `RolloutRecorder::new` は **非同期** 関数なので必ず `await` が必要です。
- レコーダ生成後、プロセス終了前に `shutdown` を呼び、書き込みが完了していることを保証するのが安全です。

---

#### 2. `RolloutRecorder::record_items(&self, items: &[RolloutItem]) -> std::io::Result<()>`

**概要**

- 渡された `RolloutItem` 配列から、ポリシー的に永続化対象となるものだけをフィルタし、  
  必要に応じてサニタイズしたうえで `RolloutCmd::AddItems` として writer タスクへ送信します。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `items` | `&[RolloutItem]` | セッション中に発生したイベント等のリスト。 |

**戻り値**

- `Ok(())` : コマンド送信に成功した場合。
- `Err(IoError)` : チャネル送信に失敗し、writer タスクの terminal_failure もしくは新規 IoError が得られた場合。

**内部処理**

1. `filtered: Vec<RolloutItem>` を作成。
2. 各 `item` について
   - `is_persisted_response_item(item, self.event_persistence_mode)` でフィルタ。
   - 通過したものは `sanitize_rollout_item_for_persistence(item.clone(), mode)` にかけてから `filtered` に push。
3. `filtered` が空なら何もせず `Ok(())`。
4. `self.tx.send(RolloutCmd::AddItems(filtered)).await` を実行。
   - 失敗した場合、`writer_task.terminal_failure()` を確認し、あればそれを返す。
   - なければ `"failed to queue rollout items: {e}"` を含む `IoError::other` を返す。

**安全性・並行性のポイント**

- `RolloutRecorder` は `#[derive(Clone)]` であり、複数クローンが同じ `tx` と `writer_task` を共有します。
- `mpsc::Sender` はスレッド安全であり、複数タスクから同時に `record_items` を呼び出しても問題ありません。
- チャネル容量は 256 で、満杯になると `send().await` が待ちになるため、  
  バックプレッシャーにより無制限のメモリ消費を避けています。

**Errors / Panics**

- `send` 失敗（`receiver` がドロップされているなど）時に `Err(IoError)`。
- panic は行いません。

**Edge cases**

- `items` が空、もしくはすべてポリシーで棄却された場合は、一切 I/O せずに `Ok(())` を返します。
- `EventPersistenceMode::Extended` の場合、`ExecCommandEnd` イベントの `aggregated_output` が最大 `10_000` バイトにトリムされ、  
  `stdout` / `stderr` / `formatted_output` はクリアされます。  
  （`PERSISTED_EXEC_AGGREGATED_OUTPUT_MAX_BYTES` と `sanitize_rollout_item_for_persistence`）

**使用上の注意点**

- `record_items` を呼んだだけでは、必ずしも即座にディスクへ書き込まれるわけではありません（バッファリングされます）。
- 確実にディスクへ反映させたいタイミングで `persist` / `flush` / `shutdown` を呼び出す必要があります。

---

#### 3. `RolloutRecorder::persist(&self) -> std::io::Result<()>`

**概要**

- バックグラウンド writer に `Persist` コマンドを送り、  
  **ロールアウトファイルの materialize（必要ならオープン）とすべてのペンディングアイテムの書き込み完了** を待機します。

**内部処理の流れ**

1. `oneshot::channel()` で `ack: Sender<Result<(), IoError>>` を作成。
2. `self.tx.send(RolloutCmd::Persist { ack })` を `await`。
3. 送信失敗時は `writer_task.terminal_failure()` を優先的に返し、なければエラーメッセージ付き `IoError`。

4. `rx.await` で writer 側からの結果を待つ。
   - `Err(recv_err)` の場合も同様に `terminal_failure` を優先。
   - `Ok(result)` で `result` が `Err` ならそのまま返す。

**Errors / Panics**

- チャネル送信・oneshot 受信のいずれか失敗で `Err(IoError)`。
- writer 側で I/O エラーが発生した場合、その `IoError` がここに伝播します。

**Edge cases**

- `Create` モードでまだファイルが存在しない場合、`ensure_writer_open` によって初めてファイルが作成されます。
- `pending_items` が空であっても、`SessionMeta` が未書き込みであればそれは書き込まれます。

**使用上の注意点**

- 「セッション開始直後に一度だけ persist して、ロールアウトファイルを確実に作っておきたい」といった用途に使えます。
- `flush` と違い、`is_deferred && pending_items.is_empty()` の場合でも  
  SessionMeta の書き込みを含めた処理が行われる点に注意が必要です。  

---

#### 4. `RolloutRecorder::flush(&self) -> std::io::Result<()>`

**概要**

- 現在キューされているすべての `pending_items` をディスクに書き込むよう writer に指示し、  
  完了を待機します。`persist` と似ていますが、「ファイル未 materialize でアイテムもない」場合は何もしません。

**処理**

`persist` とほぼ同様で、`RolloutCmd::Flush { ack }` を送る点だけ異なります。  
writer 側では `RolloutWriterState::flush` が呼ばれます。

**Edge cases**

- `is_deferred() && pending_items.is_empty()` の場合、`flush` は即座に `Ok(())` を返します（`persist` はファイル作成も行う）。
- 最初の書き込みで I/O エラーが発生した場合、内部でリトライが 1 回行われ、それでも失敗したときだけエラーとして返されます。  
  （`write_pending_with_recovery("flush")`）

**使用上の注意点**

- 長時間動作するプロセスで、ある程度の間隔でディスクへの永続化を保証したいときに呼び出すことが想定されます。

---

#### 5. `RolloutRecorder::shutdown(&self) -> std::io::Result<()>`

**概要**

- ペンディングアイテムをすべて書き込んだ後、バックグラウンド writer タスクを停止させるための API です。

**内部処理**

1. `oneshot::channel()` を作成。
2. `RolloutCmd::Shutdown { ack }` を送信。
3. writer 側では `RolloutWriterState::shutdown()` を呼び出してすべてを書き込んだ後、`ack.send(Ok(()))` し、ループを抜けてタスク終了。
4. 送信失敗時
   - `terminal_failure` があればそれを返す。
   - なければ、送信失敗自体をラップした `IoError` を返す。

**Errors / Edge cases**

- writer タスクがすでにエラー終了している場合、`terminal_failure` を返します。
- `Shutdown` コマンド送信が成功しても、writer での I/O エラーにより `Err(IoError)` が返る可能性があります。

**使用上の注意点**

- プロセス終了前や、レコーダをもはや使わないタイミングで呼び出すことが前提です。
- `shutdown` が `Err` を返した場合、いくつかの `RolloutItem` がディスクに書き込まれていない可能性があります。

---

#### 6. `RolloutRecorder::load_rollout_items(path: &Path) -> std::io::Result<(Vec<RolloutItem>, Option<ThreadId>, usize)>`

**概要**

- ロールアウト JSONL ファイルを読み込み、行ごとに JSON をパースして `RolloutItem` のベクタを復元します。
- 最初に現れた `SessionMeta.meta.id` をスレッド ID とみなし、パースエラーの件数も返します。

**戻り値**

- `Ok((items, thread_id, parse_errors))`
  - `items`: パースできた全アイテム。
  - `thread_id`: 最初に見つかったスレッド ID（見つからない場合 `None`）。
  - `parse_errors`: 各行での JSON パースエラー数の合計。
- `Err(IoError)`:
  - ファイル読み込み失敗。
  - ファイルが空または空白のみ (`"empty session file"`)。

**内部処理**

1. `tokio::fs::read_to_string(path).await?`。
2. 空白を除いて空なら `Err("empty session file")`。
3. 行ごとにループ:
   - 空行をスキップ。
   - `serde_json::from_str::<Value>` でまず JSON としてパース。
   - `serde_json::from_value::<RolloutLine>(v.clone())` で構造化。
   - `rollout_line.item` を `match` して `items` に push。`SessionMeta` の場合は `thread_id` を初回のみ設定。
   - パースエラーは `parse_errors` をインクリメントし、ログ出力のみ。

**Edge cases**

- 一部の行が壊れていても、他の行は保持されます（ベストエフォートで復元）。
- `SessionMeta` が全くないファイルは `thread_id == None` になります。

**使用上の注意点**

- 全ファイルを一度に `String` として読み込むため、大きなファイルではメモリ使用量が増加します。
- ローカルの `warn!` ログで **パースに失敗した行の内容をそのまま出力** するため、  
  ログ出力先にプライベートな情報が残る可能性があります（運用上の注意点）。

---

#### 7. `RolloutRecorder::list_threads_with_db_fallback(...) -> std::io::Result<ThreadsPage>`（内部だがコア）

**概要**

- スレッド一覧取得の中核ロジックです。
- 可能なら SQLite `state_db` を使い、そうでない・または失敗した場合には  
  ファイルシステムベースの一覧 (`get_threads` / `get_threads_in_root`) にフォールバックします。

**主要な処理の分岐**

1. **検索モード（`search_term.is_some()`）** かつ **state_db が使える** 場合:
   - `state_db::list_threads_db(...)` を呼び、結果が
     - アイテム非空、または cursor が指定済みなら、そのページを `ThreadsPage` に変換して返す。
2. **ファイルシステムベースの一覧**
   - `fs_page_size = page_size * 2`（過剰取得）を計算。
   - `archived` に応じて `get_threads_in_root` or `get_threads` を呼び、`fs_page` を得る。
3. **state_db がない場合**
   - `truncate_fs_page(fs_page, page_size, sort_key)` して返す。
4. **state_db がある場合**
   - `fs_page.items` それぞれに対して `state_db::read_repair_rollout_path(...)` を呼び、  
     DB の rollout_path を修復。
   - その後もう一度 `state_db::list_threads_db` を試みる。
     - 成功したらそれを返す。
     - 失敗したら `error` / `warn` ログを出しつつ `truncate_fs_page(fs_page, ...)` を返す。

**使用上の注意点**

- 「ファイルシステム→DB の順でウォームアップしつつ、最終的には DB ベースの一覧を返す」挙動であり、  
  大量のセッションがある場合、初回呼び出しはやや重くなり得ます。
- 検索 (`search_term`) が指定されている場合は最初から DB を試みるため、  
  FS スキャンを減らせます。

---

### 3.3 その他の関数（概要一覧）

上記以外の関数は、主に以下の役割に分類されます。

| 関数名 | 役割（1 行） | 根拠 |
|--------|--------------|------|
| `sanitize_rollout_item_for_persistence` | `ExecCommandEnd` の aggregated_output をトリムし、冗長なフィールドを削除してストレージ負荷を下げる。 | `rollout/src/recorder.rs:L1-1253` |
| `truncate_fs_page` | FS ベースの一覧ページから `page_size` までにアイテム数を切り詰め、`next_cursor` を計算。 | 同上 |
| `precompute_log_file_info` | 会話 ID と現在時刻からロールアウトファイルのパスを生成（`~/.codex/sessions/YYYY/MM/DD/...`）。 | 同上 |
| `open_log_file` | 親ディレクトリを作成しつつロールアウトファイルを `append + create` で開く。 | 同上 |
| `rollout_writer` | `mpsc::Receiver<RolloutCmd>` を受け取り、`RolloutWriterState` 上で各コマンドを処理するバックグラウンドループ。 | 同上 |
| `write_session_meta` | SessionMeta と Git 情報を取得し、最初の `RolloutItem::SessionMeta` として書き込みつつ state_db に反映。 | 同上 |
| `sync_thread_state_after_write` | 書き込まれた RolloutItem 群に応じて `state_db::apply_rollout_items` または `touch_thread_updated_at` を呼び出す。 | 同上 |
| `select_resume_path` / `select_resume_path_from_db_page` | スレッド一覧から、cwd 条件に合う再開候補の rollout_path を選択する。 | 同上 |
| `resume_candidate_matches_cwd` | キャッシュされた cwd、Rollout 内の TurnContext、メタデータから cwd を推定して比較する。 | 同上 |
| `cwd_matches` | `paths_match_after_normalization` を使ってパスを正規化したうえで比較する。 | 同上 |
| `JsonlWriter::write_rollout_item` / `write_line` | RolloutItem に現在時刻のタイムスタンプを付けて JSONL 行として書き込む。 | 同上 |
| `append_rollout_item_to_path` | 任意の RolloutItem を既存ファイルへ 1 行追記する（DB 同期は行わない）。 | 同上 |

---

## 4. データフロー

### 4.1 典型シナリオ：新規セッションの記録

1. クライアントは `RolloutRecorder::new(Create...)` でレコーダを生成。
2. セッション中に何度か `record_items` を呼び、`RolloutCmd::AddItems` が writer に送られる。
3. 一定タイミングで `persist` / `flush` を呼び、バックグラウンド writer がペンディングアイテムをファイルに書き込む。
4. 書き込みごとに `sync_thread_state_after_write` が呼ばれ、SQLite `state_db` に最新のメタデータが反映される。
5. セッション終了時に `shutdown` を呼び、残りをすべて書いてから writer タスクを終了。

### 4.2 シーケンス図

```mermaid
sequenceDiagram
    %% rollout/src/recorder.rs:L1-1253
    participant Client as 呼び出し側
    participant RR as RolloutRecorder
    participant Writer as rollout_writer タスク
    participant File as JSONLファイル
    participant DB as state_db

    Client->>RR: new(Create params)
    activate RR
    RR->>Writer: spawn(rollout_writer)
    deactivate RR

    loop セッション中
        Client->>RR: record_items(&[RolloutItem])
        RR->>Writer: RolloutCmd::AddItems(items)
        Writer->>Writer: pending_items に追加
        alt writer が materialized なら
            Writer->>File: JsonlWriter::write_rollout_item(...)
            Writer->>DB: sync_thread_state_after_write(...)
        end
    end

    Client->>RR: persist()/flush()
    RR->>Writer: RolloutCmd::Persist/Flush
    Writer->>File: ensure_writer_open + write_session_meta_if_needed
    Writer->>File: write_pending_items_once
    Writer->>DB: sync_thread_state_after_write(...)
    Writer-->>RR: Result<(), IoError>

    Client->>RR: shutdown()
    RR->>Writer: RolloutCmd::Shutdown
    Writer->>File: 最後の pending_items を書き込み
    Writer->>DB: sync_thread_state_after_write(...)
    Writer-->>RR: Ok(())
    deactivate Writer
```

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

新規セッションを開始してロールアウトを記録し、終了時に shutdown する例です。

```rust
use std::path::Path;
use codex_protocol::{ThreadId, protocol::RolloutItem};
use crate::recorder::{RolloutRecorder, RolloutRecorderParams};
use crate::config::RolloutConfigView;
use crate::state_db;

async fn run_session(config: &impl RolloutConfigView,
                     thread_id: ThreadId)
    -> std::io::Result<()>
{
    // Create モードのパラメータを構築                  // セッションメタ情報などを含む
    let params = RolloutRecorderParams::new(
        thread_id,
        None,                                           // forked_from_id
        SessionSource::Cli,                             // 例
        BaseInstructions::default(),
        Vec::new(),
        EventPersistenceMode::Extended,
    );

    // state_db コンテキストを取得（なければ None）    // SQLite 利用
    let state_db_ctx = state_db::get_state_db(config).await;

    // レコーダを生成                                   // writer タスクが spawn される
    let recorder = RolloutRecorder::new(config, params, state_db_ctx, None).await?;

    // セッション中のどこかで RolloutItem を記録       // 非同期送信のみ
    let items: Vec<RolloutItem> = vec![/* ... */];
    recorder.record_items(&items).await?;

    // 必要なら早期に persist                          // ファイル materialize + 書き込み
    recorder.persist().await?;

    // セッション終了時に shutdown                     // 残りの pending_items をすべて書き込み
    recorder.shutdown().await?;

    Ok(())
}
```

### 5.2 よくある使用パターン

1. **最新セッションの再開**

```rust
async fn resume_latest(config: &impl RolloutConfigView)
    -> std::io::Result<Option<RolloutRecorder>>
{
    let page_size = 20;
    let path_opt = RolloutRecorder::find_latest_thread_path(
        config,
        page_size,
        None,
        ThreadSortKey::UpdatedAt,
        &[SessionSource::Cli, SessionSource::Agent],
        None,
        config.model_provider_id(),
        Some(config.cwd()),
    ).await?;

    let Some(path) = path_opt else { return Ok(None); };

    let params = RolloutRecorderParams::resume(path.clone(), EventPersistenceMode::Extended);
    let state_db_ctx = state_db::get_state_db(config).await;
    let recorder = RolloutRecorder::new(config, params, state_db_ctx, None).await?;
    Ok(Some(recorder))
}
```

1. **ロールアウト履歴のみを読みたい場合**

```rust
async fn load_history(path: &Path) -> std::io::Result<InitialHistory> {
    RolloutRecorder::get_rollout_history(path).await
}
```

1. **メタデータ更新だけを行う（ロールアウト未ロード）**

```rust
async fn append_meta(path: &Path, item: &RolloutItem) -> std::io::Result<()> {
    // 注意: この関数は state_db との同期を行わない            // コメントで明示
    append_rollout_item_to_path(path, item).await
}
```

### 5.3 よくある間違いと注意点

```rust
// 間違い例: レコーダを作っただけで終了してしまう
async fn bad() -> std::io::Result<()> {
    let recorder = /* ... */ RolloutRecorder::new(/*...*/).await?;
    recorder.record_items(&[/*...*/]).await?;
    // プロセス終了。shutdown や flush を呼んでいないため      // pending_items がディスクに出ない可能性
    Ok(())
}

// 正しい例: 明示的に shutdown を呼ぶ
async fn good() -> std::io::Result<()> {
    let recorder = /* ... */ RolloutRecorder::new(/*...*/).await?;
    recorder.record_items(&[/*...*/]).await?;
    recorder.shutdown().await?;                              // ここで書き込み完了を保証
    Ok(())
}
```

### 5.4 使用上の注意点（まとめ）

- **前提条件**
  - `RolloutRecorder` の各メソッド（`record_items` / `persist` / `flush` / `shutdown`）は **Tokio ランタイム上の async コンテキスト** から呼び出す必要があります。
- **エラー処理**
  - 送信・oneshot 受信の失敗は `IoError` として表現され、`terminal_failure` がある場合はそれが優先されます。
  - これらのエラーが返された場合、バックグラウンド writer がすでに停止している可能性が高く、その後の呼び出しも失敗することが多いです。
- **並行性**
  - `RolloutRecorder` はクローン可能であり、複数タスクから同時に `record_items` を呼んでも安全です（MPSC チャネルが順序を保証）。
- **パフォーマンス**
  - `JsonlWriter::write_line` は各行ごとに `flush()` を呼ぶため、小さな書き込みが非常に頻繁な場合はディスク I/O が多くなります。
  - `load_rollout_items` はファイル全体をメモリに読み込むため、大きなセッションファイルではメモリ使用量に注意が必要です。
- **セキュリティ / プライバシー**
  - JSON パースに失敗した行の内容を `warn!` でログに出力しているため（`load_rollout_items`）、  
    ログ出力先が信頼できる場所であることを前提に運用する必要があります。
  - `sanitize_rollout_item_for_persistence` は `ExecCommandEnd` の一部フィールドのみを削減するため、  
    その他のイベントには機密情報がそのまま保持される可能性があります。  

（根拠: `rollout/src/recorder.rs:L1-1253`）

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

例: 新しい種類の `RolloutItem` を追加し、それを state_db にも反映させたい場合。

1. **プロトコル側の拡張**
   - `codex_protocol::protocol::RolloutItem` に新しいバリアントを追加（本ファイル外）。
2. **永続化ロジックの更新**
   - `sanitize_rollout_item_for_persistence` に新バリアントの扱いが必要か検討し、必要ならサニタイズ処理を追加。
3. **読み出しロジックの更新**
   - `load_rollout_items` 内の `match rollout_line.item` パターンに新バリアントを追加し、  
     `items.push(...)` する。
4. **state_db 同期**
   - `codex_state::rollout_item_affects_thread_metadata` 側（別モジュール）の更新が必要か確認。
   - 影響がある場合 `apply_rollout_items` で新バリアントを扱えるようにする。
5. **テスト**
   - `#[cfg(test)] mod tests;` で参照される `recorder_tests.rs` に、新バリアントの round-trip テストなどを追加。

### 6.2 既存の機能を変更する場合

例: `EventPersistenceMode::Extended` のトリミングサイズを変更する。

- 変更箇所:
  - `PERSISTED_EXEC_AGGREGATED_OUTPUT_MAX_BYTES` の値。
- 影響範囲の確認:
  - `sanitize_rollout_item_for_persistence` のみがこの定数を使っていますが、  
    これに依存している上位のコンポーネント（UI 上の表示長さなど）がないか別モジュールで確認する必要があります。
- 契約・前提条件:
  - トリミング後も JSON としての構造を保つため、中間を削るだけで先頭・末尾は残す `truncate_middle_chars` が利用されています。
- テスト:
  - 既存のテスト（`recorder_tests.rs`）に依存している値がないか確認し、  
    必要なら期待値を更新します。

---

## 7. 関連ファイル

| パス / モジュール | 役割 / 関係 |
|-------------------|------------|
| `super::list` (`get_threads`, `get_threads_in_root`, `ThreadsPage`, など) | セッション一覧表示用のユーティリティ。`list_threads_with_db_fallback` や `find_latest_thread_path` から利用されます。 |
| `super::metadata` | Rollout からスレッドメタデータを抽出するヘルパー。`write_session_meta` / `resume_candidate_matches_cwd` などが利用。 |
| `super::policy` (`EventPersistenceMode`, `is_persisted_response_item`) | どの `RolloutItem` をどの程度の情報量で保存するかというポリシーを定義。 |
| `crate::state_db` / `codex_state` | SQLite ベースのセッション状態管理。`apply_rollout_items`, `touch_thread_updated_at`, `list_threads_db` などを通じて `recorder.rs` と連携。 |
| `codex_protocol::protocol` | `RolloutItem`, `SessionMeta`, `RolloutLine`, `InitialHistory` など、ロールアウトの基本データ型を定義。 |
| `codex_git_utils::collect_git_info` | `write_session_meta` で Git 情報を取得するために使用。 |
| `codex_utils_path` (`path_utils`) | `cwd_matches` でパスを正規化して比較するために使用。 |
| `rollout/src/recorder_tests.rs` | 本モジュールのテスト。内容はこのチャンクには含まれていませんが、挙動の検証に利用されます。 |

---

### テスト・バグ・セキュリティに関する補足

- **テスト**
  - `#[cfg(test)] #[path = "recorder_tests.rs"] mod tests;` が存在し、  
    専用のテストファイルで挙動が検証されていることがわかりますが、  
    このチャンクにはテスト内容は含まれていません。
- **潜在的なバグ / 注意点（読み取れる範囲）**
  - `JsonlWriter::write_line` が各行ごとに `flush()` を呼び、さらに `RolloutWriterState::write_pending_once` でも `flush()` が呼ばれているため、  
    フラッシュが二重になっている可能性があります（性能面の注意点）。
  - `open_log_file` は同期的な `std::fs` を使っており、Tokio の worker スレッド上で呼び出されるため、  
    大量に呼ばれる状況では一時的なブロッキングが発生し得ます。
- **セキュリティ / プライバシー**
  - ログに Rollout の内容（パース失敗行）が出る点は、運用上のプライバシー配慮が必要な部分です。
  - ロールアウトパスは `RolloutConfigView::codex_home` と会話 ID から組み立てられており、  
    外部から任意のパスを直接指定しているわけではないため、パストラバーサル等は発生しにくい構造になっています（会話 ID のフォーマットに依存）。

（すべての根拠: `rollout/src/recorder.rs:L1-1253`。このチャンクには個別の行番号情報が含まれていないため、範囲指定はファイル全体としています。）
