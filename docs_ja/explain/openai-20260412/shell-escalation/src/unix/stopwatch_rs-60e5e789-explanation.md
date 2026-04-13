# shell-escalation/src/unix/stopwatch.rs コード解説

## 0. ざっくり一言

`Stopwatch` は、Tokio 上で動作する「一時停止可能なタイムアウト計測器」を提供し、指定した制限時間に達したら `CancellationToken` をキャンセルする非同期ストップウォッチです。（`pause_for` で処理中は時間を進めない）  
（`Stopwatch`, `StopwatchState`, `cancellation_token`, `pause_for` など: `shell-escalation/src/unix/stopwatch.rs:L10-15,L17-22,L24-128`）

---

## 1. このモジュールの役割

### 1.1 概要

- このモジュールは **非同期処理の「有効実行時間」に基づくタイムアウト管理** を行うために存在し、  
  **制限時間付き／無制限のストップウォッチと、そのストップウォッチに連動した `CancellationToken`** を提供します。  
  （`Stopwatch::new`, `Stopwatch::unlimited`, `cancellation_token`: `shell-escalation/src/unix/stopwatch.rs:L24-47,L49-91`）
- ストップウォッチは `pause_for` により、特定の `Future` 実行中は「時間を止める」ことができます。ネストや並行する一時停止は参照カウントで管理され、すべての一時停止が解除されたときにのみ再開します。  
  （`pause_for`, `pause`, `resume`, `active_pauses`: `shell-escalation/src/unix/stopwatch.rs:L17-22,L93-105,L107-128`）

### 1.2 アーキテクチャ内での位置づけ

このファイル単体で見ると、主な依存関係は以下です。

- 外部呼び出し元（任意の非同期コード）が `Stopwatch` を生成し、`cancellation_token` と `pause_for` を使用します。（`Stopwatch` の `pub` メソッド: `shell-escalation/src/unix/stopwatch.rs:L10-15,L24-47,L49-105`）
- 内部状態は `StopwatchState` を `Arc<tokio::sync::Mutex<_>>` で共有・保護します。（`inner` フィールド: `shell-escalation/src/unix/stopwatch.rs:L12-14,L17-22,L27-31,L39-43`）
- タイムアウト通知には `tokio_util::sync::CancellationToken`、状態変化の通知には `tokio::sync::Notify` を用います。（`use tokio::sync::Notify;`, `notify` フィールド, `CancellationToken`: `shell-escalation/src/unix/stopwatch.rs:L7-8,L14,L32,L44,L49-51,L88-90`）
- 非同期タイマーとタスク実行には Tokios (`tokio::spawn`, `tokio::time::sleep`, `tokio::select!`) を利用します。（`cancellation_token` 内部: `shell-escalation/src/unix/stopwatch.rs:L57-89`）

```mermaid
flowchart LR
    Caller["呼び出し元タスク (外部)\nStopwatch 利用側"] 
    SW["Stopwatch 構造体\n(L10-15,24-128)"]
    State["StopwatchState\n内部状態\n(L17-22)"]
    Mutex["Arc<tokio::sync::Mutex<_>>\n排他制御\n(L6,L12-13,L27-31,L39-43,L60,L108,L119)"]
    Notify["tokio::sync::Notify\n状態変化通知\n(L7,L14,L32,L44,L73-75,L84,L114,L126)"]
    Token["tokio_util::CancellationToken\n(L8,L49-51,L88-90)"]
    Tokio["Tokio ランタイム\nspawn/sleep/select\n(L57-89)"]

    Caller -->|new/unlimited\ncancellation_token\npause_for| SW
    SW -->|保持| State
    SW -->|共有 & 排他| Mutex
    SW -->|通知| Notify
    SW -->|生成 & cancel()| Token
    Token -->|cancelled().await| Caller
    SW -->|バックグラウンド\n監視タスク起動| Tokio
```

（依存関係図の情報は `shell-escalation/src/unix/stopwatch.rs:L1-8,L10-15,L17-22,L24-47,L49-91,L107-128` に基づきます）

### 1.3 設計上のポイント

- **共有可能なストップウォッチ**  
  `Stopwatch` は `Clone` 可能で、内部に `Arc<Mutex<StopwatchState>>` と `Arc<Notify>` を保持します。クローンしても同じ内部状態を共有し、どのクローンからの操作も同じストップウォッチに作用します。  
  （`#[derive(Clone, Debug)]`, `inner: Arc<Mutex<...>>`, `notify: Arc<Notify>`: `shell-escalation/src/unix/stopwatch.rs:L10-15,L27-31,L39-43,L55-56,L153-162,L181-201`）
- **制限時間の有無を `Option<Duration>` で管理**  
  `limit: Option<Duration>` により有限タイムアウトと無制限を切り替えます。`unlimited` では `limit: None` とし、`cancellation_token` は新しいトークンを返すだけで監視タスクを起動しません。  
  （`limit` フィールド, `unlimited`, `cancellation_token` の `let Some(limit) = self.limit else { return token; };`: `shell-escalation/src/unix/stopwatch.rs:L12,L24-35,L37-47,L49-53`）
- **非同期・スレッドセーフな内部状態管理**  
  内部状態へのアクセスはすべて `tokio::sync::Mutex` を介して `await` 付きで行われ、スレッドではなくタスク単位で安全に同期されます。`StopwatchState` は `Duration`, `Instant`, `u32` のみから成り、`Send` なデータだけを含みます。  
  （`Mutex` の使用箇所: `shell-escalation/src/unix/stopwatch.rs:L6,L12-13,L27-31,L39-43,L60,L108,L119`）
- **一時停止の参照カウント管理**  
  `active_pauses: u32` によってネスト・重複する `pause_for` 呼び出しを管理し、`active_pauses` が 0 から 1 に変わる瞬間のみ実時間を `elapsed` に加算し、1 から 0 に戻る瞬間のみ再開します。  
  （`StopwatchState` と `pause`, `resume`: `shell-escalation/src/unix/stopwatch.rs:L17-22,L107-116,L118-128`）
- **時間計測は単調時計 `Instant` ベース**  
  経過時間は `Instant::now()` と `Instant::elapsed()` の差分で管理され、システム時刻の変更の影響を受けません。  
  （`running_since: Option<Instant>`, `Instant::now()`, `since.elapsed()`: `shell-escalation/src/unix/stopwatch.rs:L3-4,L20,L29,L41,L60-65,L111-113,L125`）
- **キャンセル監視はバックグラウンドタスク**  
  `cancellation_token` は `tokio::spawn` で監視タスクを起動し、`Notify` による状態変化と `sleep` による時間経過を `select!` で待ち合わせて、制限時間に達したとき `CancellationToken::cancel()` を呼びます。  
  （監視ループ: `shell-escalation/src/unix/stopwatch.rs:L57-89`）

---

## 2. 主要な機能一覧

このモジュールが提供する主な機能です。

- 制限時間付きストップウォッチの生成: `Stopwatch::new(limit: Duration)`  
  （`shell-escalation/src/unix/stopwatch.rs:L24-35`）
- 無制限ストップウォッチの生成: `Stopwatch::unlimited()`  
  （`shell-escalation/src/unix/stopwatch.rs:L37-47`）
- 残り時間に応じてキャンセルされる `CancellationToken` の生成: `Stopwatch::cancellation_token(&self)`  
  （`shell-escalation/src/unix/stopwatch.rs:L49-91`）
- 任意の `Future` 実行中だけストップウォッチを一時停止するラッパー: `Stopwatch::pause_for<F, T>(&self, fut: F)`  
  （`shell-escalation/src/unix/stopwatch.rs:L93-105`）
- 一時停止・再開の内部制御: `pause`, `resume`（外部からは直接呼べず、`pause_for` 経由で使用）  
  （`shell-escalation/src/unix/stopwatch.rs:L107-128`）

---

## 3. 公開 API と詳細解説

### 3.1 型一覧（構造体・列挙体など）

#### 構造体インベントリー

| 名前 | 種別 | 公開範囲 | 役割 / 用途 | 定義位置 |
|------|------|----------|-------------|----------|
| `Stopwatch` | 構造体 | `pub` | タイムアウト制限と一時停止機能を持つストップウォッチ本体。共有可能で、`CancellationToken` を生成する。 | `shell-escalation/src/unix/stopwatch.rs:L10-15,L24-128` |
| `StopwatchState` | 構造体 | モジュール内のみ | 内部状態（累積経過時間 `elapsed`、現在走行開始時刻 `running_since`、一時停止カウント `active_pauses`）を保持する。`Mutex` でガードされる。 | `shell-escalation/src/unix/stopwatch.rs:L17-22` |

#### 関数インベントリー

| 名称 | 所属 | シグネチャ（概略） | 公開範囲 | 役割 | 定義位置 |
|------|------|--------------------|----------|------|----------|
| `new` | `Stopwatch` | `pub fn new(limit: Duration) -> Self` | 公開 | 制限時間付きストップウォッチを生成して即時スタートする。 | `shell-escalation/src/unix/stopwatch.rs:L24-35` |
| `unlimited` | `Stopwatch` | `pub fn unlimited() -> Self` | 公開 | 無制限ストップウォッチを生成する。`cancellation_token` はキャンセルされないトークンを返す。 | `shell-escalation/src/unix/stopwatch.rs:L37-47` |
| `cancellation_token` | `Stopwatch` | `pub fn cancellation_token(&self) -> CancellationToken` | 公開 | 制限時間に達するとキャンセルされる `CancellationToken` を生成し、監視タスクを起動する（有限の場合）。 | `shell-escalation/src/unix/stopwatch.rs:L49-91` |
| `pause_for` | `Stopwatch` | `pub async fn pause_for<F, T>(&self, fut: F) -> T` | 公開 | 渡された `Future` 実行中だけストップウォッチを一時停止し、完了時に再開するヘルパー。 | `shell-escalation/src/unix/stopwatch.rs:L93-105` |
| `pause` | `Stopwatch` | `async fn pause(&self)` | 非公開 | `active_pauses` を増やし、初回一時停止時に実時間を `elapsed` に取り込んで走行を止める。 | `shell-escalation/src/unix/stopwatch.rs:L107-116` |
| `resume` | `Stopwatch` | `async fn resume(&self)` | 非公開 | `active_pauses` を減らし、すべての一時停止が解除されたときだけ走行を再開する。 | `shell-escalation/src/unix/stopwatch.rs:L118-128` |
| `cancellation_receiver_fires_after_limit` | `tests` | `async fn ...()` | テスト | 制限時間後に `CancellationToken` がキャンセルされることを確認。 | `shell-escalation/src/unix/stopwatch.rs:L139-146` |
| `pause_prevents_timeout_until_resumed` | `tests` | `async fn ...()` | テスト | `pause_for` 中はキャンセルが発火しないことを確認。 | `shell-escalation/src/unix/stopwatch.rs:L148-173` |
| `overlapping_pauses_only_resume_once` | `tests` | `async fn ...()` | テスト | 重複した `pause_for` でも最後の解除時にのみ再開されることを確認。 | `shell-escalation/src/unix/stopwatch.rs:L175-224` |
| `unlimited_stopwatch_never_cancels` | `tests` | `async fn ...()` | テスト | 無制限ストップウォッチの `CancellationToken` がキャンセルされないことを確認。 | `shell-escalation/src/unix/stopwatch.rs:L226-236` |

### 3.2 重要な関数の詳細

#### `Stopwatch::new(limit: Duration) -> Self`

**概要**

- 制限時間 `limit`（`Duration`）を持つ新しい `Stopwatch` を生成し、生成時点から計測を開始します。  
  （`elapsed = 0`, `running_since = Some(Instant::now())` をセット）  
  （`shell-escalation/src/unix/stopwatch.rs:L24-35`）

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `limit` | `Duration` | 許容される合計「走行時間」。この時間に達すると `cancellation_token` がキャンセルされます。 |

**戻り値**

- 新しい `Stopwatch` インスタンス。内部状態は共有用に `Arc<Mutex<StopwatchState>>` でラップされています。  
  （`inner: Arc::new(Mutex::new(...))`: `shell-escalation/src/unix/stopwatch.rs:L27-31`）

**内部処理の流れ**

1. `StopwatchState` を初期化: `elapsed = Duration::ZERO`, `running_since = Some(Instant::now())`, `active_pauses = 0`。  
   （`shell-escalation/src/unix/stopwatch.rs:L27-31`）
2. `StopwatchState` を `Mutex` で包み、それを `Arc` で共有可能にします。  
   （`Arc::new(Mutex::new(...))`: `shell-escalation/src/unix/stopwatch.rs:L27-31`）
3. `notify` に新しい `Notify` を設定し、`limit` に引数の `Duration` を格納します。  
   （`notify: Arc::new(Notify::new()), limit: Some(limit)`: `shell-escalation/src/unix/stopwatch.rs:L32-34`）

**Examples（使用例）**

```rust
use std::time::Duration;
use shell_escalation::unix::Stopwatch; // 実際のパス名はプロジェクト構成に依存（このチャンクには不明）

#[tokio::main]
async fn main() {
    // 5秒の制限時間を持つストップウォッチを作成する
    let stopwatch = Stopwatch::new(Duration::from_secs(5));

    // キャンセル用トークンを取得
    let token = stopwatch.cancellation_token();

    // 何らかの処理と並行して、キャンセルを待つ
    tokio::select! {
        _ = token.cancelled() => {
            eprintln!("タイムアウトしました");
        }
        // 他の処理...
    }
}
```

**Errors / Panics**

- この関数は `Result` を返さず、`unwrap` なども使用していないため、通常はパニックを発生させません。  
  （`shell-escalation/src/unix/stopwatch.rs:L24-35`）

**Edge cases（エッジケース）**

- `limit` が 0 の場合  
  - `cancellation_token` を呼ぶと、監視タスク内で `elapsed >= limit` 判定が即座に真となり、ほぼすぐにキャンセルされます。  
    （`if elapsed >= limit { break; }`: `shell-escalation/src/unix/stopwatch.rs:L61-67`）
- 非常に長い `Duration` を与えた場合  
  - 内部的には `Duration` と `Instant` の通常の範囲で扱われます。特別なケアはありませんが、Rust 標準の制限内で動作します。  
  （`Duration` と `Instant` の利用: `shell-escalation/src/unix/stopwatch.rs:L3-4,L17-22`）

**使用上の注意点**

- `Stopwatch` は生成直後から「走行中」状態になります。すぐに時間計測を止めたい場合は、`pause_for` などで明示的に一時停止する必要があります。  
  （`running_since: Some(Instant::now())`: `shell-escalation/src/unix/stopwatch.rs:L29`）

---

#### `Stopwatch::unlimited() -> Self`

**概要**

- 制限時間を持たないストップウォッチを生成します。`cancellation_token` はキャンセルされない `CancellationToken` を返すようになります。  
  （`limit: None`: `shell-escalation/src/unix/stopwatch.rs:L37-47,L51-53`）

**引数**

- なし。

**戻り値**

- 無制限ストップウォッチ。内部状態は `new` と同様に初期化されますが、`limit` が `None` になっています。  
  （`elapsed = 0`, `running_since = Some(Instant::now())`, `active_pauses = 0`, `limit: None`: `shell-escalation/src/unix/stopwatch.rs:L39-45`）

**内部処理の流れ**

1. `StopwatchState` を `new` と同一の初期値で生成します。  
   （`shell-escalation/src/unix/stopwatch.rs:L39-43`）
2. `notify` も新たに生成し、`limit` を `None` に設定します。  
   （`limit: None`: `shell-escalation/src/unix/stopwatch.rs:L45`）

**Examples（使用例）**

```rust
use std::time::Duration;
use shell_escalation::unix::Stopwatch;

#[tokio::main]
async fn main() {
    let stopwatch = Stopwatch::unlimited();
    let token = stopwatch.cancellation_token();

    // 無制限なので、タイムアウトは発生しない
    let res = tokio::time::timeout(Duration::from_millis(30), token.cancelled()).await;
    assert!(res.is_err(), "このトークンはキャンセルされないはずです");
}
```

（挙動はテスト `unlimited_stopwatch_never_cancels` により確認されています: `shell-escalation/src/unix/stopwatch.rs:L226-236`）

**Errors / Panics**

- `new` と同様、パニックを起こす要素はありません。  
  （`shell-escalation/src/unix/stopwatch.rs:L37-47`）

**Edge cases**

- `cancellation_token` を繰り返し呼んでも、いずれも決してキャンセルされないトークンが返されます（監視タスクも起動されません）。  
  （`let Some(limit) = self.limit else { return token; };`: `shell-escalation/src/unix/stopwatch.rs:L49-53`）

**使用上の注意点**

- 無制限ストップウォッチから得た `CancellationToken` に対して `cancelled().await` を待機しても完了しないため、`tokio::time::timeout` などでラップしないとタスクがブロックし続けます。  
  （`unlimited_stopwatch_never_cancels` テスト: `shell-escalation/src/unix/stopwatch.rs:L226-236`）

---

#### `Stopwatch::cancellation_token(&self) -> CancellationToken`

**概要**

- ストップウォッチの制限時間に達したタイミングでキャンセルされる `CancellationToken` を返します（有限の場合）。  
- 有限 `limit` のときは内部で監視用タスクを `tokio::spawn` し、`Notify` とタイマーを使って残り時間を監視します。  
  （`shell-escalation/src/unix/stopwatch.rs:L49-91`）

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `&self` | `&Stopwatch` | 同じ内部状態を共有する任意の `Stopwatch` インスタンスから呼び出せます。 |

**戻り値**

- `CancellationToken`（`tokio_util::sync::CancellationToken`）  
  - `limit: Some(_)` の場合: バックグラウンド監視タスクによって、制限時間に達すると `cancel()` されます。  
  - `limit: None` の場合: 監視タスクは起動せず、トークンは自然にはキャンセルされません。  
  （`shell-escalation/src/unix/stopwatch.rs:L49-53,L57-89`）

**内部処理の流れ（アルゴリズム）**

1. 新しい `CancellationToken` を生成します。  
   （`let token = CancellationToken::new();`: `shell-escalation/src/unix/stopwatch.rs:L49-50`）
2. `self.limit` を評価し、`None` であれば監視タスクを起動せずにそのまま `token` を返します。  
   （`let Some(limit) = self.limit else { return token; };`: `shell-escalation/src/unix/stopwatch.rs:L51-53`）
3. `inner`（状態）と `notify`、そしてトークンのクローン `cancel` をクローンしてバックグラウンドタスク内にムーブします。  
   （`Arc::clone(&self.inner)`, `Arc::clone(&self.notify)`, `let cancel = token.clone();`: `shell-escalation/src/unix/stopwatch.rs:L54-56`）
4. `tokio::spawn` で監視タスクを起動し、以下を繰り返します。  
   （`shell-escalation/src/unix/stopwatch.rs:L57-89`）
   1. `inner.lock().await` で状態を読み取り、現在の累積経過時間を計算。  
      `elapsed = guard.elapsed + running_since.map(|since| since.elapsed()).unwrap_or_default()`  
      （`shell-escalation/src/unix/stopwatch.rs:L60-65`）
   2. `elapsed >= limit` ならループを抜ける（=タイムアウト）。  
      （`shell-escalation/src/unix/stopwatch.rs:L66-67`）
   3. そうでなければ `remaining = limit - elapsed` を計算し、ストップウォッチが「走行中かどうか」を `running = guard.running_since.is_some()` で判定。  
      （`shell-escalation/src/unix/stopwatch.rs:L69-70`）
   4. `running == false` なら（＝一時停止中）、`notify.notified().await` で状態変化まで待機し、ループを先頭からやり直す。  
      （`shell-escalation/src/unix/stopwatch.rs:L72-75`）
   5. `running == true` なら、`tokio::time::sleep(remaining)` を開始し、`Notify` による状態変化と `select!` で待ち合わせる。  
      （`sleep` と `tokio::select!`: `shell-escalation/src/unix/stopwatch.rs:L77-86`）
      - `sleep` 完了 → `break`。  
      - `notify.notified()` → ループを続行し、最新の状態で `remaining` を再計算。
5. ループを抜けたら `cancel.cancel()` を呼び出し、トークンをキャンセルします。  
   （`shell-escalation/src/unix/stopwatch.rs:L88`）

**Examples（使用例）**

```rust
use std::time::Duration;
use shell_escalation::unix::Stopwatch;
use tokio::time::{sleep, timeout};

#[tokio::main]
async fn main() {
    let stopwatch = Stopwatch::new(Duration::from_millis(50));
    let token = stopwatch.cancellation_token();

    // 途中で pause_for で時間を止める例
    let sw2 = stopwatch.clone();
    tokio::spawn(async move {
        sw2.pause_for(async {
            // この sleep 中は制限時間が進まない
            sleep(Duration::from_millis(100)).await;
        }).await;
    });

    // 30ms 以内にはキャンセルされない（テストと同じ挙動）
    assert!(timeout(Duration::from_millis(30), token.cancelled()).await.is_err());

    // いずれはキャンセルされる
    token.cancelled().await;
}
```

（挙動はテスト `pause_prevents_timeout_until_resumed` などで確認されています: `shell-escalation/src/unix/stopwatch.rs:L148-173,L175-224`）

**Errors / Panics**

- 関数本体に `unwrap` や `expect` はなく、通常の実行ではパニックしません。  
  （`shell-escalation/src/unix/stopwatch.rs:L49-91`）
- バックグラウンドタスクの `tokio::spawn` から返る `JoinHandle` は保持しておらず、失敗時のエラー処理は行っていません。  
  ただし、起動自体がパニックすることは通常ありません。  
  （`shell-escalation/src/unix/stopwatch.rs:L57-89`）

**Edge cases**

- `limit` にごく短い `Duration`（0 など）を指定した場合、監視タスクの最初のループで即座に `elapsed >= limit` となり、キャンセルがほぼ即時に発火します。  
  （`shell-escalation/src/unix/stopwatch.rs:L61-67`）
- `Stopwatch` 本体をドロップしても、`inner` は監視タスクが `Arc` を保持しているため、制限時間到達までは残り続けます。その後 `cancel.cancel()` 実行後に参照がなくなれば解放されます。  
  （`inner` と `notify` のクローン: `shell-escalation/src/unix/stopwatch.rs:L54-56,L57-89`）

**使用上の注意点**

- `cancellation_token` を複数回呼び出すと、そのたびに新しい監視タスクが起動します（有限の場合）。どのトークンも同じ制限時間に達するとキャンセルされますが、監視タスクが増えすぎるとオーバーヘッドが増える可能性があります。  
  （`tokio::spawn` が毎回呼ばれる: `shell-escalation/src/unix/stopwatch.rs:L49-57`）
- 監視タスクはキャンセル用トークンを `clone` して保持しているため、返されたトークンをすべてドロップしても監視タスク側の `cancel` は生きており、制限時間到達時に `cancel()` を呼び出します。

---

#### `Stopwatch::pause_for<F, T>(&self, fut: F) -> T`

**概要**

- 渡された `Future` を実行している間だけストップウォッチを一時停止し、完了したら自動的に再開します。  
- `pause_for` のネストや並行呼び出しは参照カウント（`active_pauses`）で管理され、すべての一時停止が解除されたときにのみ再開します。  
  （doc コメントと実装: `shell-escalation/src/unix/stopwatch.rs:L93-105,L107-128`）

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `fut` | `F` where `F: Future<Output = T>` | 一時停止したい区間を表す非同期処理。`fut.await` の間、ストップウォッチの時間は進みません。 |

**戻り値**

- `fut` の `Output` 値をそのまま返します。  
  （`let result = fut.await; ... result`: `shell-escalation/src/unix/stopwatch.rs:L101-104`）

**内部処理の流れ**

1. 内部メソッド `pause().await` を呼び出し、一時停止カウントを増やして走行を止めます（必要な場合のみ）。  
   （`self.pause().await;`: `shell-escalation/src/unix/stopwatch.rs:L101`）
2. 引数 `fut` を `await` し、その結果を `result` として一時変数に保存します。  
   （`let result = fut.await;`: `shell-escalation/src/unix/stopwatch.rs:L102`）
3. `self.resume().await` を呼び出し、一時停止カウントを減らし、必要であれば走行を再開します。  
   （`self.resume().await;`: `shell-escalation/src/unix/stopwatch.rs:L103`）
4. 最後に `result` を返します。  
   （`result`: `shell-escalation/src/unix/stopwatch.rs:L104`）

**Examples（使用例）**

テストと同様の使い方です。

```rust
use std::time::Duration;
use shell_escalation::unix::Stopwatch;
use tokio::time::{sleep, timeout};

#[tokio::main]
async fn main() {
    let stopwatch = Stopwatch::new(Duration::from_millis(50));
    let token = stopwatch.cancellation_token();

    // 100ms の処理中は時間を止める
    let sw2 = stopwatch.clone();
    let handle = tokio::spawn(async move {
        sw2.pause_for(async {
            sleep(Duration::from_millis(100)).await;
        }).await;
    });

    // 30ms ではキャンセルしない（時間は止まっている）
    assert!(timeout(Duration::from_millis(30), token.cancelled()).await.is_err());

    handle.await.unwrap();

    // 一時停止解除後、制限時間に達するとキャンセルされる
    token.cancelled().await;
}
```

（`pause_prevents_timeout_until_resumed` テストを簡略化した例: `shell-escalation/src/unix/stopwatch.rs:L148-173`）

**Errors / Panics**

- `pause_for` 自体はパニックを起こすコードを含みませんが、**`fut` がパニックした場合には `resume()` が呼ばれず、`active_pauses` が減らないままになる**可能性があります。  
  その場合、ストップウォッチは永続的に一時停止状態のままになり、タイムアウトが発生しなくなる可能性があります。  
  （`resume()` が `fut.await` の後にしか呼ばれない: `shell-escalation/src/unix/stopwatch.rs:L101-103`）

**Edge cases**

- `fut` が非常に短時間で完了する場合  
  - `pause` と `resume` がほぼ連続で呼ばれますが、`active_pauses` により正しく計数され、計測誤差は `Instant::elapsed()` の精度に依存します。  
  （`shell-escalation/src/unix/stopwatch.rs:L107-116,L118-128`）
- `pause_for` をネストまたは並行に呼び出した場合  
  - 内部の `active_pauses` は 1,2,... と増加し、すべての `pause_for` が完了して `active_pauses` が 0 になったときにだけ再開されます。  
  （`overlapping_pauses_only_resume_once` テスト: `shell-escalation/src/unix/stopwatch.rs:L175-224`）

**使用上の注意点**

- `fut` 内でパニックが起きると、一時停止カウントがデクリメントされず、ストップウォッチが再開されない可能性があります。  
  パニックが発生しないか、あるいは回復後に `Stopwatch` を作り直すなどの対策が必要です。  
  （`shell-escalation/src/unix/stopwatch.rs:L97-105`）
- `pause_for` の中でさらに `pause_for` を使うことは可能ですが、計測ロジックが複雑になるため、一時停止の粒度を整理して使うことが望ましいです（設計上の注意）。

---

#### `Stopwatch::pause(&self)`

**概要**

- 一時停止カウント `active_pauses` を増やし、初めての一時停止（`active_pauses` が 1 に変化したとき）のみ、現在までの走行時間を `elapsed` に加算して走行を停止します。  
  （`shell-escalation/src/unix/stopwatch.rs:L107-116`）

**引数**

- `&self`: 内部状態共有のための参照。

**戻り値**

- なし（`async fn`, 戻り値は `()`）。

**内部処理の流れ**

1. `inner.lock().await` で内部状態へのロックを取る。  
   （`let mut guard = self.inner.lock().await;`: `shell-escalation/src/unix/stopwatch.rs:L108`）
2. `active_pauses` をインクリメント。  
   （`guard.active_pauses += 1;`: `shell-escalation/src/unix/stopwatch.rs:L109`）
3. `active_pauses == 1` かつ `running_since` が `Some(since)` の場合にのみ、  
   - `since.elapsed()` を `elapsed` に加算し、  
   - `running_since` を `None` にし（`take()`）、  
   - `notify.notify_waiters()` で待機中のタスクを起こす。  
   （`shell-escalation/src/unix/stopwatch.rs:L110-115`）
4. それ以外の場合（2回目以降の一時停止など）は、追加の処理を行わず終了。

**Examples（使用例）**

- この関数は非公開であり、外部からは `pause_for` を通じてのみ利用されます。  
  （`pause_for` 内でのみ呼び出される: `shell-escalation/src/unix/stopwatch.rs:L101`）

**Errors / Panics**

- `pause` 自体はパニックする操作を含みません。  
  （`shell-escalation/src/unix/stopwatch.rs:L107-116`）

**Edge cases**

- すでに一時停止中（`running_since` が `None`）の状態で呼び出された場合、`active_pauses` は増えますが、`elapsed` の加算や `notify` の呼び出しは行われません。  
  （`active_pauses == 1` のときのみ処理: `shell-escalation/src/unix/stopwatch.rs:L110-112`）

**使用上の注意点**

- `pause` を直接呼び出せるのはモジュール内部だけです。外部利用時は `pause_for` を使用する想定の設計になっています。  
  （`async fn pause` が `pub` でないこと: `shell-escalation/src/unix/stopwatch.rs:L107`）

---

#### `Stopwatch::resume(&self)`

**概要**

- 一時停止カウント `active_pauses` を減らし、それが 0 になったときにだけ `running_since` を現在時刻に設定し直して走行を再開します。再開時には `notify` で待ち受けタスクを起こします。  
  （`shell-escalation/src/unix/stopwatch.rs:L118-128`）

**引数**

- `&self`: 内部状態共有のための参照。

**戻り値**

- なし（`async fn`, 戻り値は `()`）。

**内部処理の流れ**

1. `inner.lock().await` で内部状態へのロックを取る。  
   （`let mut guard = self.inner.lock().await;`: `shell-escalation/src/unix/stopwatch.rs:L119`）
2. `active_pauses == 0` のときは何もせず即 return。  
   （不均衡な `resume` 呼び出しを無害化: `shell-escalation/src/unix/stopwatch.rs:L120-122`）
3. `active_pauses` をデクリメント。  
   （`guard.active_pauses -= 1;`: `shell-escalation/src/unix/stopwatch.rs:L123`）
4. `active_pauses == 0` かつ `running_since.is_none()` の場合のみ、  
   - `running_since = Some(Instant::now())` に設定しなおし、  
   - `notify.notify_waiters()` で待機中タスクに再開を通知。  
   （`shell-escalation/src/unix/stopwatch.rs:L124-127`）

**Examples（使用例）**

- こちらも非公開であり、外部からは `pause_for` 経由でのみ利用されます。  
  （`pause_for` 内での呼び出し: `shell-escalation/src/unix/stopwatch.rs:L103`）

**Errors / Panics**

- `resume` 自体はパニックする操作を含みません。  
  （`shell-escalation/src/unix/stopwatch.rs:L118-128`）

**Edge cases**

- `pause` を呼んでいない状態で `resume` を呼ぶ（`active_pauses == 0`）と、単に何もせずに戻ります。  
  これにより「`resume` の呼びすぎ」による負のカウンタが防がれています。  
  （`if guard.active_pauses == 0 { return; }`: `shell-escalation/src/unix/stopwatch.rs:L120-122`）
- `running_since` がすでに `Some(_)`（すでに走行中）の状態で `active_pauses` が 0 になった場合、`running_since` の再セットは行われず、`notify` も呼ばれません。  
  （`running_since.is_none()` 条件: `shell-escalation/src/unix/stopwatch.rs:L124`）

**使用上の注意点**

- `resume` が確実に `pause` と同数だけ呼ばれることを前提とした設計ですが、余分な `resume` を呼んでも副作用がないように防御的に実装されています。  
  （`shell-escalation/src/unix/stopwatch.rs:L120-123`）

---

### 3.3 その他の関数

上記以外の関数は、すべてテストコード内 (`mod tests`) の非公開テスト関数であり、公開 API ではありません。  
（`#[tokio::test]` が付いた 4 関数: `shell-escalation/src/unix/stopwatch.rs:L139-146,L148-173,L175-224,L226-236`）

---

## 4. データフロー

### 4.1 代表的なシナリオ概要

代表的な処理シナリオとして、以下を取り上げます。

1. 呼び出し元が制限時間付き `Stopwatch` を生成し、`cancellation_token` を取得する。  
2. `cancellation_token` により、バックグラウンド監視タスクが起動する。  
3. 別タスクが `pause_for` を使って、ある区間の処理中は時間を一時停止する。  
4. 一時停止中は監視タスクが `Notify` を待機し、再開時に残り時間タイマーをセットし直す。  
5. 残り時間が経過すると `CancellationToken::cancel()` が呼ばれ、呼び出し元の `cancelled().await` が完了する。

この流れは主に `cancellation_token`, `pause_for`, `pause`, `resume` とテスト `pause_prevents_timeout_until_resumed` によって確認できます。  
（`shell-escalation/src/unix/stopwatch.rs:L49-91,L93-105,L107-128,L148-173`）

### 4.2 シーケンス図

```mermaid
sequenceDiagram
    participant Caller as "呼び出し元タスク\n(テストなど)"
    participant SW as "Stopwatch\n(L10-15,24-128)"
    participant CTTask as "監視タスク\n(cancellation_token 内)\n(L57-89)"
    participant Fut as "一時停止対象 Future\n(pause_for 内)\n(L97-105)"
    participant Tok as "CancellationToken\n(L49-51,L88-90)"

    Caller->>SW: new(limit)\n(L25-35)
    Caller->>SW: cancellation_token()\n(L49-91)
    activate SW
    SW-->>Caller: token (Tok)
    SW->>CTTask: tokio::spawn(...)\n(L57-89)
    deactivate SW
    activate CTTask
    CTTask->>SW: inner.lock().await\n(L60)
    SW-->>CTTask: (elapsed, running)\n(L61-70)
    alt elapsed >= limit
        CTTask->>Tok: cancel()\n(L88)
        deactivate CTTask
    else まだ時間あり
        opt running == false
            CTTask->>Notify: notified().await\n(L72-75)
        end
        opt running == true
            CTTask->>CTTask: sleep(remaining)\n(L77-81)
            CTTask->>Notify: notified().await\n(L83-85)
        end
    end

    par 一時停止区間
        Caller->>SW: pause_for(Fut)\n(L97-105)
        activate SW
        SW->>SW: pause().await\n(L101,107-116)
        SW-->>CTTask: notify_waiters()\n(L114)
        deactivate SW
        activate Fut
        Fut-->>Caller: 実行完了\n(L157-160)
        deactivate Fut
        Caller->>SW: resume().await\n(L103,118-128)
        SW-->>CTTask: notify_waiters()\n(L126)
        deactivate SW
    and キャンセル待ち
        Caller->>Tok: cancelled().await
        Tok-->>Caller: キャンセル完了
    end
```

（このシーケンスは `shell-escalation/src/unix/stopwatch.rs:L24-35,L49-91,L93-105,L107-128,L148-173` に基づきます）

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

制限時間付きで処理を実行し、途中で一時停止区間を設けたい場合の典型的なコード例です。

```rust
use std::time::Duration;
use shell_escalation::unix::Stopwatch;
use tokio::time::{sleep};
use tokio_util::sync::CancellationToken;

#[tokio::main]
async fn main() {
    // 50ms の有効実行時間を持つストップウォッチを作成する
    let stopwatch = Stopwatch::new(Duration::from_millis(50)); // L24-35

    // このストップウォッチに紐づく CancellationToken を取得する
    let token: CancellationToken = stopwatch.cancellation_token(); // L49-91

    // 途中で時間を止めたい処理
    let sw2 = stopwatch.clone();
    let pause_task = tokio::spawn(async move {
        sw2.pause_for(async {
            // この sleep 中は時間が進まない
            sleep(Duration::from_millis(100)).await;
        }).await; // L93-105
    });

    // 別の処理と、タイムアウトを並行に待つ
    tokio::select! {
        _ = token.cancelled() => {
            eprintln!("タイムアウトしました");
        }
        _ = async {
            // 実際の処理
            // ...
        } => {
            eprintln!("処理が先に終わりました");
        }
    }

    pause_task.await.unwrap();
}
```

（`Stopwatch::new`, `cancellation_token`, `pause_for` の基本的な使い方を組み合わせた例です）

### 5.2 よくある使用パターン

1. **単純なタイムアウト（停止区間なし）**

   ```rust
   let stopwatch = Stopwatch::new(Duration::from_secs(10));
   let token = stopwatch.cancellation_token();

   tokio::select! {
       _ = token.cancelled() => {
           // 10秒経過
       }
       _ = do_work() => {
           // 処理完了
       }
   }
   ```

   （停止機能を使わず、単純な「経過時間ベースのタイムアウト」として利用: `shell-escalation/src/unix/stopwatch.rs:L24-35,L49-91`）

2. **複数の一時停止区間（重複あり）**

   ```rust
   let stopwatch = Stopwatch::new(Duration::from_millis(50));
   let token = stopwatch.cancellation_token();

   // 長い一時停止
   let sw1 = stopwatch.clone();
   let pause1 = tokio::spawn(async move {
       sw1.pause_for(async {
           sleep(Duration::from_millis(80)).await;
       }).await;
   });

   // 短い一時停止（前半が重複）
   let sw2 = stopwatch.clone();
   let pause2 = tokio::spawn(async move {
       sw2.pause_for(async {
           sleep(Duration::from_millis(30)).await;
       }).await;
   });

   // ... (テスト `overlapping_pauses_only_resume_once` と同様) ...
   ```

   （重複一時停止の挙動はテストで検証済み: `shell-escalation/src/unix/stopwatch.rs:L175-224`）

3. **タイムアウト無効化のための無制限ストップウォッチ**

   ```rust
   let stopwatch = Stopwatch::unlimited();
   let token = stopwatch.cancellation_token();

   // この token は永遠にキャンセルされない
   let res = tokio::time::timeout(Duration::from_millis(30), token.cancelled()).await;
   assert!(res.is_err());
   ```

   （`unlimited_stopwatch_never_cancels` テスト: `shell-escalation/src/unix/stopwatch.rs:L226-236`）

### 5.3 よくある間違い

```rust
use std::time::Duration;
use shell_escalation::unix::Stopwatch;
use tokio::time::sleep;

// 間違い例: pause_for を await しない
async fn wrong_usage() {
    let stopwatch = Stopwatch::new(Duration::from_secs(1));

    // pause_for 自体を await しないと即座に resume されるタスクが走るだけ
    let _ = stopwatch.pause_for(async {
        sleep(Duration::from_millis(100)).await;
    }); // ← await がない
}

// 正しい例: pause_for を await する（あるいは spawn したタスク側で await）
async fn correct_usage() {
    let stopwatch = Stopwatch::new(Duration::from_secs(1));

    stopwatch.pause_for(async {
        sleep(Duration::from_millis(100)).await;
    }).await;
}
```

- `pause_for` は `async fn` なので、**`await` しないと一時停止区間が意図通りにならない**点に注意が必要です。  
  （`pause_for` のシグネチャ: `shell-escalation/src/unix/stopwatch.rs:L97-105`）

また、以下のような誤解も起こり得ます。

- **誤解**: `Stopwatch::unlimited()` の `CancellationToken` も将来どこかでキャンセルされる。  
  **実際**: `limit: None` の場合、監視タスクは起動せず、トークンはキャンセルされません。  
  （`shell-escalation/src/unix/stopwatch.rs:L49-53,L226-236`）

### 5.4 使用上の注意点（まとめ）

- **非同期ランタイム前提**  
  - `pause_for`, `cancellation_token` の内部で `tokio::spawn`, `Mutex::lock().await`, `Notify::notified().await`, `tokio::time::sleep` などを使用しているため、Tokio ランタイム上で利用する前提の設計になっています。  
    （`shell-escalation/src/unix/stopwatch.rs:L6-7,L57-89,L107-128`）
- **パニック時の一時停止解除**  
  - `pause_for` 内で渡した `Future` がパニックすると `resume()` が呼ばれず、`active_pauses` が減らないままになる可能性があります。その場合、一度も再開されずタイムアウトが発生しなくなります。  
    （`resume` 呼び出し位置: `shell-escalation/src/unix/stopwatch.rs:L101-103`）
- **監視タスクの数**  
  - `cancellation_token` を呼ぶたびに新しい監視タスクが起動します。大量に生成するとバックグラウンドタスク数が増えるため、必要以上に乱発しない設計が望ましいです。  
    （`tokio::spawn` が毎回呼ばれる: `shell-escalation/src/unix/stopwatch.rs:L49-57`）
- **セキュリティ上の注意**  
  - このモジュールは外部入力のパースやプロセス起動などを行わず、メモリ操作もすべて安全な Rust と Tokio プリミティブに依存しており、直接的なセキュリティリスクとなる操作は含まれていません。  
    （`unsafe` キーワードが存在しないこと: `shell-escalation/src/unix/stopwatch.rs:L1-237`）

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

このモジュールの構造から見て、以下のような拡張が自然です。

- **現在の経過時間を読み出す API を追加したい場合**
  1. `impl Stopwatch` ブロック内に、新しい `pub async fn elapsed(&self) -> Duration` のようなメソッドを追加します。  
     （`impl Stopwatch` の位置: `shell-escalation/src/unix/stopwatch.rs:L24-128`）
  2. メソッド内で `inner.lock().await` し、`StopwatchState` と同じロジックで `elapsed + running_since.map(|s| s.elapsed()).unwrap_or_default()` を計算して返します。  
     （同ロジックは `cancellation_token` 内に存在: `shell-escalation/src/unix/stopwatch.rs:L60-65`）
- **リセット機能（経過時間を 0 に戻す）を追加したい場合**
  1. 同じく `impl Stopwatch` 内に `pub async fn reset(&self)` を追加し、`inner.lock().await` を取得します。  
  2. `elapsed = Duration::ZERO`, `running_since = Some(Instant::now())`, `active_pauses = 0` のように内部状態を再初期化します。  
     （初期化ロジックは `new`, `unlimited` にすでに存在: `shell-escalation/src/unix/stopwatch.rs:L27-31,L39-43`）

※上記はコード中の既存パターンを再利用する観点からの説明であり、実際に追加するかどうかは設計次第です。

### 6.2 既存の機能を変更する場合

変更の影響範囲を考える際のポイントです。

- **`StopwatchState` のフィールドを変更する場合**
  - `StopwatchState` を参照している箇所は `new`, `unlimited`, `cancellation_token`, `pause`, `resume` です。  
    変更時はこれらすべてを確認する必要があります。  
    （`shell-escalation/src/unix/stopwatch.rs:L24-47,L49-91,L107-128`）
- **一時停止ロジック（`pause` / `resume`）を変更する場合**
  - `pause_for` の挙動とテスト `pause_prevents_timeout_until_resumed`, `overlapping_pauses_only_resume_once` の仕様に直結します。  
    テストを更新し、期待する動作を再定義する必要があります。  
    （`shell-escalation/src/unix/stopwatch.rs:L93-105,L148-173,L175-224`）
- **キャンセル条件やタイミングを変更する場合**
  - `cancellation_token` 内の監視ループが唯一のキャンセル判定ロジックです。  
    `elapsed >= limit` の条件や `sleep`/`Notify` の使い方を変えると、すべての利用箇所に影響します。  
    （`shell-escalation/src/unix/stopwatch.rs:L57-89`）
- **テストの確認**
  - 挙動変更後は、4つのテスト（特にタイミングに関する 3 つのテスト）を必ず確認する必要があります。  
    （`shell-escalation/src/unix/stopwatch.rs:L139-146,L148-173,L175-224,L226-236`）

---

## 7. 関連ファイル

このチャンク内で参照されている主な外部依存や関連モジュールです。

| パス / クレート | 役割 / 関係 |
|-----------------|------------|
| `tokio::sync::Mutex` | 内部状態 `StopwatchState` への非同期排他アクセスを提供します。`Stopwatch` のメソッドはこれを通して状態を更新します。 (`shell-escalation/src/unix/stopwatch.rs:L6,L12-13,L27-31,L39-43,L60,L108,L119`) |
| `tokio::sync::Notify` | 一時停止／再開など、状態が変化したことを監視タスクへ通知するために使用されます。 (`shell-escalation/src/unix/stopwatch.rs:L7,L14,L32,L44,L73-75,L84,L114,L126`) |
| `tokio_util::sync::CancellationToken` | タイムアウトの発火を表現するキャンセルトークンです。`cancellation_token` で生成され、制限時間達成時に `cancel()` されます。 (`shell-escalation/src/unix/stopwatch.rs:L8,L49-51,L88-90`) |
| `tokio::time::{sleep, timeout, Instant, Duration}` | テストおよび内部ロジックで時間制御に使われます。 (`shell-escalation/src/unix/stopwatch.rs:L3-4,L134-137,L139-146,L148-173,L175-236`) |
| `mod tests` | このモジュール専用のテスト群で、`Stopwatch` のタイムアウト発火、一時停止、重複一時停止、無制限挙動を検証します。 (`shell-escalation/src/unix/stopwatch.rs:L131-236`) |

このチャンクには、同一クレート内の別モジュール（例: 他の `unix` モジュール）から `Stopwatch` がどのように利用されているかは現れていません。そのため、プロジェクト全体における `Stopwatch` の具体的な利用箇所はこの情報だけでは特定できません。
