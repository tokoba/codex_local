# core/src/skills_watcher.rs

## 0. ざっくり一言

- 汎用的な `FileWatcher` の上に、「スキルファイルの変更」を検知して配信するための薄いアダプタ層です（根拠: `core/src/skills_watcher.rs:L1,L13-18,L27-35`）。
- Tokio のブロードキャストチャネルを使って、複数のコンポーネントに対してスキル変更イベントを配信します（根拠: `L8,L32-35,L40,L53-55,L77-83`）。

---

## 1. このモジュールの役割

### 1.1 概要

- このモジュールは、汎用的な `FileWatcher` からのファイル変更イベントを受け取り、「スキル関連のファイル変更」として扱いやすい `SkillsWatcherEvent` に変換して配信する役割を持ちます（根拠: `L1,L13-18,L27-30,L77-83`）。
- スキルの検索ルートは設定 (`Config`)、プラグイン (`PluginsManager`)、スキル管理 (`SkillsManager`) から導出され、まとめて `FileWatcher` に登録されます（根拠: `L11-12,L19-20,L57-75`）。
- ファイルイベントは `ThrottledWatchReceiver` によって間引き（スロットリング）され、その結果だけがブロードキャストされます（根拠: `L16,L22-25,L77-83`）。

### 1.2 アーキテクチャ内での位置づけ

主な依存関係とデータの流れを簡略化して図示します。

```mermaid
graph TD
    C["Config (外部, L11, L57-65)"]
    PM["PluginsManager (外部, L19, L61-64)"]
    SM["SkillsManager (外部, L11, L60-67)"]
    FW["FileWatcher (外部, L13, L38-40)"]
    FWS["FileWatcherSubscriber (外部, L14, L32-34, L74)"]
    SW["SkillsWatcher (L32-88)"]
    SWE["SkillsWatcherEvent (L27-30)"]
    RT["Tokio Runtime Handle (L7, L79-84)"]
    SUB["Broadcast subscribers (subscribe, L53-55)"]

    C --> PM
    C --> SW
    PM --> SW
    SM --> SW
    FW -->|add_subscriber| SW
    SW -->|register_config: register_paths| FWS
    FW -->|ファイルイベント| SW
    SW -->|broadcast::Sender| SUB
    RT -->|spawn_event_loop (L77-84)| SW
    SW --> SWE
```

- 構成:
  - `SkillsWatcher` は `FileWatcherSubscriber` と `broadcast::Sender<SkillsWatcherEvent>` を内部に持ちます（根拠: `L32-35`）。
  - 生成時に `FileWatcher::add_subscriber` で購読を開始し、Tokio ランタイム上でイベントループを非同期タスクとして起動します（根拠: `L38-40,L77-84`）。
  - 利用側は `SkillsWatcher::register_config` で監視対象パスを登録し、`SkillsWatcher::subscribe` で `SkillsWatcherEvent` を受け取る構造です（根拠: `L53-55,L57-75`）。

### 1.3 設計上のポイント

- **汎用 watcher からのアダプタ**  
  - 汎用 `FileWatcher` を直接使わず、スキル領域に特化した `SkillsWatcherEvent` に変換して配信する薄い層になっています（根拠: `L1,L27-30,L77-83`）。
- **ブロードキャストによる多重購読**  
  - `tokio::sync::broadcast` を使うことで、複数のコンポーネントが同じスキル変更イベントを同時に購読できます（根拠: `L8,L32-35,L40,L53-55,L77-83`）。
- **スロットリング（イベント間引き）**  
  - `ThrottledWatchReceiver::new` と `WATCHER_THROTTLE_INTERVAL` により、一定時間内のイベントをまとめる／間引く設計になっています（根拠: `L16,L22-25,L77-79`）。
- **Tokio ランタイム存在チェック**  
  - `Handle::try_current()` により、現在スレッドに Tokio ランタイムがある場合のみイベントループを起動し、なければ警告ログを出してスキップします（根拠: `L7,L79-87`）。
- **エラーのサイレント無視**  
  - `broadcast::Sender::send` の戻り値は無視されており、チャネル切断やラグによるエラーはログ等には出ません（根拠: `L82` の `let _ = tx.send(...)`）。

---

## 2. 主要な機能一覧

- スキル変更イベント型 `SkillsWatcherEvent` の定義と公開（根拠: `L27-30`）
- スキル用ファイルウォッチャ `SkillsWatcher` の生成 (`new`, `noop`)（根拠: `L32-35,L38-51`）
- ブロードキャスト購読インターフェース `subscribe` の提供（根拠: `L53-55`）
- 設定・プラグイン・スキル管理を元に監視対象パスを登録する `register_config`（根拠: `L57-75`）
- Tokio 上でファイルイベントを `SkillsWatcherEvent` に変換して配信するイベントループ `spawn_event_loop`（根拠: `L77-88`）

### 2.1 コンポーネントインベントリー（内部）

| 名前 | 種別 | 役割 / 用途 | 定義 / 実装行 |
|------|------|-------------|---------------|
| `WATCHER_THROTTLE_INTERVAL` | `const Duration` | ファイルイベントのスロットリング間隔（本番: 10 秒、テスト: 50ms） | `core/src/skills_watcher.rs:L22-25` |
| `SkillsWatcherEvent` | `enum` | スキル関連のファイル変更イベントを表す（現状は `SkillsChanged { paths }` のみ） | `L27-30` |
| `SkillsWatcher` | `struct` | `FileWatcher` からのイベントを購読し、`SkillsWatcherEvent` をブロードキャストする中心コンポーネント | `L32-35` |
| `SkillsWatcher::new` | 関数（関連関数） | `FileWatcher` にサブスクライブし、イベントループとブロードキャストチャネルを構成する | `L38-47` |
| `SkillsWatcher::noop` | 関数（関連関数） | `FileWatcher::noop` を用いたノーオペレーション版 watcher を生成するヘルパー | `L49-51` |
| `SkillsWatcher::subscribe` | メソッド | `SkillsWatcherEvent` を購読する `broadcast::Receiver` を新規に返す | `L53-55` |
| `SkillsWatcher::register_config` | メソッド | `Config` / `SkillsManager` / `PluginsManager` から監視ルートを導出し、`FileWatcherSubscriber` に登録する | `L57-75` |
| `SkillsWatcher::spawn_event_loop` | 関数（プライベート） | `Receiver` をスロットリングしつつ非同期に読み出し、`SkillsWatcherEvent` をブロードキャストするループ | `L77-88` |

### 2.2 コンポーネントインベントリー（外部依存：このファイルからの利用）

| 名前 / モジュール | 役割（このファイルから見た用途） | 使用行 |
|-------------------|----------------------------------|--------|
| `crate::file_watcher::FileWatcher` | ファイルシステムイベントのソースとなる汎用 watcher | `L13,L38-40,L49-51,L100-101` |
| `crate::file_watcher::FileWatcherSubscriber` | `FileWatcher` に対するサブスクライバ。監視パス登録とイベント `Receiver` を提供 | `L14,L32-34,L38-40,L74,L103-105` |
| `crate::file_watcher::Receiver` | `FileWatcher` からのイベントを受信するチャネル型 | `L15,L77` |
| `crate::file_watcher::ThrottledWatchReceiver` | イベントをスロットリングするラッパー | `L16,L77-79` |
| `crate::file_watcher::WatchPath` | 監視パスと再帰フラグを表す型 | `L17,L69-72` |
| `crate::file_watcher::WatchRegistration` | 監視登録のハンドル（解除などに使うと推測されるが、このチャンクには詳細なし） | `L18,L62,L74` |
| `crate::SkillsManager` | スキルのルートパスを決定する管理コンポーネント | `L11,L60-67` |
| `crate::plugins::PluginsManager` | プラグインを元に実効的なスキルルートを決定する | `L19,L61-64` |
| `crate::config::Config` | 設定情報。プラグイン選択やスキル入力の元データ | `L12,L57-60,L63-65` |
| `crate::skills_load_input_from_config` | `Config` とプラグイン情報からスキルロードの入力を生成する関数 | `L20,L65` |
| `tokio::runtime::Handle` | 現在の Tokio ランタイムへのハンドル。イベントループ spawn に利用 | `L7,L79-84` |
| `tokio::sync::broadcast` | スキル変更イベントを複数コンシューマに配信するチャネル | `L8,L34,L40,L53-55,L77-83` |
| `tracing::warn` | ランタイム未存在時に警告を記録するロガー | `L9,L85-86` |

---

## 3. 公開 API と詳細解説

### 3.1 型一覧（構造体・列挙体など）

| 名前 | 種別 | 可視性 | 役割 / 用途 | 定義行 |
|------|------|--------|-------------|--------|
| `SkillsWatcherEvent` | 列挙体 (`enum`) | `pub` | スキルファイルに関する変更イベントを表現する。現状は `SkillsChanged { paths: Vec<PathBuf> }` のみを持ち、変更されたパス一覧を通知する | `L27-30` |
| `SkillsWatcher` | 構造体 | `pub(crate)` | `FileWatcher` と連携し、`SkillsWatcherEvent` をブロードキャストする watcher。内部に `FileWatcherSubscriber` と `broadcast::Sender` を保持する | `L32-35` |

> 備考: `SkillsWatcherEvent` は crate 外からも使用可能ですが、`SkillsWatcher` 自体は `pub(crate)` のため、この crate 内部向けのコンポーネントです（根拠: `L27,L32` の可視性修飾子）。

---

### 3.2 関数詳細

#### `SkillsWatcher::new(file_watcher: &Arc<FileWatcher>) -> SkillsWatcher`  （L38-47）

**概要**

- 既存の `FileWatcher` にサブスクライブし、スキル変更イベント用のブロードキャストチャネルとイベントループをセットアップして `SkillsWatcher` を生成します（根拠: `L38-47,L77-83`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `file_watcher` | `&Arc<FileWatcher>` | 監視の基盤となる汎用 `FileWatcher` インスタンスへの共有参照。`add_subscriber` を呼び出してイベント購読を開始するために使用します（根拠: `L38-40`）。 |

**戻り値**

- `SkillsWatcher`  
  - 内部に `FileWatcherSubscriber` と `broadcast::Sender<SkillsWatcherEvent>` を持つ watcher インスタンスです（根拠: `L32-35,L41-44`）。

**内部処理の流れ**

1. `file_watcher.add_subscriber()` を呼び出し、ファイルイベント受信チャネル (`rx`) と、監視パス登録用の `FileWatcherSubscriber` を取得します（根拠: `L38-40`）。
2. `broadcast::channel(128)` でバッファ 128 のブロードキャストチャネルを作成し、送信側 `tx` を得ます（根拠: `L8,L40`）。
3. `SkillsWatcher` インスタンスに `subscriber` と `tx.clone()` を格納します（送信用 `Sender` を内部に保持）（根拠: `L32-35,L41-44`）。
4. `Self::spawn_event_loop(rx, tx)` を呼び出し、ファイルイベント受信チャネルと送信用 `Sender` を渡して非同期イベントループを起動します（根拠: `L45,L77-83`）。
5. 構築した `skills_watcher` を返します（根拠: `L46`）。

**Examples（使用例）**

`SkillsWatcher` を既存の `FileWatcher` から生成し、購読を開始する基本的な例です。

```rust
use std::sync::Arc;
use core::file_watcher::FileWatcher;          // 実際のパスは crate 構成に依存（このチャンクには未記載）
use core::skills_watcher::SkillsWatcher;      // このモジュール

// Tokio ランタイム上で動作する前提の例
#[tokio::main]
async fn main() {
    // FileWatcher のインスタンスを共有参照付きで作成する
    let file_watcher = Arc::new(FileWatcher::new(/* パラメータなど */));

    // SkillsWatcher を FileWatcher から構築する
    let skills_watcher = SkillsWatcher::new(&file_watcher);

    // スキル変更イベントを購読する
    let mut rx = skills_watcher.subscribe();

    // 以降、rx.recv().await で SkillsWatcherEvent を待ち受ける ...
}
```

> `FileWatcher::new` のシグネチャやパラメータはこのチャンクには現れないため、上記は擬似的な例です。

**Errors / Panics**

- この関数内で明示的な `Result` や `panic!` は使われていません（根拠: `L38-47`）。
- 間接的に発生しうるエラーは以下の通りですが、いずれもこの関数ではハンドリングされていません。
  - `file_watcher.add_subscriber()` 内部でのエラー: このチャンクには実装が現れないため挙動は不明です（根拠: `L39`）。
  - `broadcast::channel(128)` は通常 `Result` を返さず、パニックもしないため、ここではエラー要因にはなりません（Tokio の仕様による一般知識）。

**Edge cases（エッジケース）**

- **Tokio ランタイムが存在しない場合**  
  - `new()` 自体は成功し `SkillsWatcher` を返しますが、`spawn_event_loop` が内部でランタイム未存在を検出するとイベントループは起動しません（根拠: `L45,L79-87`）。
  - 結果として、`subscribe` で購読してもイベントは届かない状態になりますが、API 上はエラーにはなりません（根拠: `L79-87`）。
- **ブロードキャストバッファ溢れ**  
  - バッファサイズ 128 を超えてイベントが溜まると `tx.send` は `Err` を返し得ますが、`spawn_event_loop` 側で戻り値が無視されるため、この関数の呼び出し側には伝わりません（根拠: `L40,L82`）。

**使用上の注意点**

- **Tokio ランタイム前提**  
  - `SkillsWatcher::new` を呼び出すときは、同じスレッド上で Tokio ランタイムが動作していることが実質的な前提条件です（`spawn_event_loop` がランタイム前提）（根拠: `L79-87`）。
- **ライフタイム**  
  - `file_watcher` は `SkillsWatcher` よりも長く生きる必要があります。`new` は `&Arc<FileWatcher>` を受け取るため、呼び出し側が `Arc` の所有権を保持し続ける必要があります（根拠: `L38-40`）。

---

#### `SkillsWatcher::noop() -> SkillsWatcher`  （L49-51）

**概要**

- `FileWatcher::noop()` を内部的に生成し、それを用いて `SkillsWatcher` を構築するヘルパーです。主にテストや監視を行わない環境で利用される想定です（根拠: `L49-51,L100-101`）。

**引数**

- なし。

**戻り値**

- `SkillsWatcher`  
  - `FileWatcher::noop()` に基づいた watcher です（根拠: `L49-51`）。

**内部処理の流れ**

1. `FileWatcher::noop()` を呼び出し、その結果を新たな `Arc` に包みます（根拠: `L49-50`）。
2. その参照を `SkillsWatcher::new` に渡して通常の初期化処理を行います（根拠: `L49-51`）。

**Examples（使用例）**

テストや監視不要なコンテキストでの使用例です。

```rust
use core::skills_watcher::SkillsWatcher;

// 監視を行わない SkillsWatcher を生成する例
fn create_test_watcher() -> SkillsWatcher {
    // FileWatcher::noop を内部で使用して SkillsWatcher を構築する
    SkillsWatcher::noop()
}
```

**Errors / Panics**

- この関数自体は `Result` を返さず、`panic!` も行っていません（根拠: `L49-51`）。
- `FileWatcher::noop()` の挙動はこのチャンクには現れないため、そこでのエラー可能性は不明です（根拠: `L49-50`）。

**Edge cases / 使用上の注意点**

- `FileWatcher::noop()` の実装が「イベントを一切発生させない」ものであるかどうかはこのチャンクからは分かりません。テストでは実際に `send_paths_for_test` によりイベントを送っており、`noop` とテスト用 send の関係もこのチャンクには現れません（根拠: `L100-109`）。

---

#### `SkillsWatcher::subscribe(&self) -> broadcast::Receiver<SkillsWatcherEvent>`  （L53-55）

**概要**

- `SkillsWatcherEvent` を購読するための `broadcast::Receiver` を生成して返します。呼び出すたびに独立した新しいレシーバが作られます（根拠: `L53-55`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `&self` | `&SkillsWatcher` | 既存の watcher インスタンスへの参照です。内部の `broadcast::Sender` を用いて購読を開始します。 |

**戻り値**

- `broadcast::Receiver<SkillsWatcherEvent>`  
  - スキル変更イベントを `recv().await` で受信できるレシーバです（根拠: `L53-55`）。

**内部処理の流れ**

1. 内部フィールド `tx` に対して `self.tx.subscribe()` を呼び出します（根拠: `L32-35,L53-55`）。
2. 得られた `Receiver` をそのまま返します。

**Examples（使用例）**

```rust
use std::sync::Arc;
use core::skills_watcher::{SkillsWatcher, SkillsWatcherEvent};
use tokio::task;

// Tokio ランタイム上での例
#[tokio::main]
async fn main() {
    let file_watcher = Arc::new(FileWatcher::new(/* ... */));
    let skills_watcher = SkillsWatcher::new(&file_watcher);

    // スキル変更イベントを購読
    let mut rx = skills_watcher.subscribe();

    // 別タスクでイベントを待ち受ける
    task::spawn(async move {
        while let Ok(event) = rx.recv().await {
            match event {
                SkillsWatcherEvent::SkillsChanged { paths } => {
                    println!("スキルファイルが更新されました: {:?}", paths);
                }
            }
        }
    });

    // 以降、ファイル変更に応じてイベントが流れてくる
}
```

**Errors / Panics**

- `subscribe` 自体は `Result` を返さず、エラーも発生しません（根拠: `L53-55`）。
- 返された `Receiver` の `recv()` は、送信側がすべてドロップされた場合などにエラーを返し得ますが、その挙動は `tokio::sync::broadcast` の仕様に従います（外部仕様）。

**Edge cases / 使用上の注意点**

- `SkillsWatcher` がドロップされ、内部の `Sender` もすべて破棄された場合、`recv()` は将来的にエラーを返すようになります。これは `broadcast` の仕様であり、このファイルには明示されていませんが、一般的な挙動です（根拠: `L32-35,L40,L53-55`）。

---

#### `SkillsWatcher::register_config(&self, config: &Config, skills_manager: &SkillsManager, plugins_manager: &PluginsManager) -> WatchRegistration`  （L57-75）

**概要**

- `Config` とプラグイン・スキル管理の情報から「監視すべきスキルのルートパス」を導出し、それらを `FileWatcherSubscriber` に登録します（根拠: `L57-75`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `&self` | `&SkillsWatcher` | 監視登録を行う `SkillsWatcher` インスタンスへの参照です。内部の `subscriber` を利用します（根拠: `L32-35,L74`）。 |
| `config` | `&Config` | 設定オブジェクト。プラグイン選択やスキル設定の元になる情報を持ちます（根拠: `L57-60,L63-65`）。 |
| `skills_manager` | `&SkillsManager` | 設定やプラグインからスキルルートパスを導出するコンポーネント（根拠: `L60-67`）。 |
| `plugins_manager` | `&PluginsManager` | 設定からプラグイン情報を取得し、実効的なスキルルート情報を持つオブジェクトを返すコンポーネント（根拠: `L61-64`）。 |

**戻り値**

- `WatchRegistration`  
  - 登録した監視設定に対応するハンドルです。具体的な機能（解除など）は `WatchRegistration` の実装に依存し、このチャンクには現れません（根拠: `L18,L62,L74`）。

**内部処理の流れ（アルゴリズム）**

1. `plugins_manager.plugins_for_config(config)` を呼び出して、設定に対応するプラグインの結果 `plugin_outcome` を取得します（根拠: `L63`）。
2. `plugin_outcome.effective_skill_roots()` を呼び出し、プラグインを考慮した「実効的なスキルルート」を取得します（根拠: `L64`）。
3. `skills_load_input_from_config(config, effective_skill_roots)` を呼び出し、スキルロード処理の入力 `skills_input` を生成します（根拠: `L65`）。
4. `skills_manager.skill_roots_for_config(&skills_input)` で、実際に監視対象とするスキルルートのリストを取得します（根拠: `L66-67`）。
5. その各要素に対して `WatchPath { path: root.path, recursive: true }` を構築し、`Vec<WatchPath>` 等のコレクションに `collect()` します（根拠: `L66-73`）。
6. `self.subscriber.register_paths(roots)` を呼び出し、監視パスを `FileWatcher` に登録し、その戻り値 `WatchRegistration` を返します（根拠: `L32-35,L74`）。

**Examples（使用例）**

典型的な設定登録の流れの例です。ここでは `SkillsManager` や `PluginsManager` の詳細は省略します。

```rust
use std::sync::Arc;
use core::skills_watcher::SkillsWatcher;
use core::config::Config;
use core::SkillsManager;
use core::plugins::PluginsManager;

fn setup_skill_watcher(
    file_watcher: Arc<FileWatcher>,
    config: Config,
    skills_manager: SkillsManager,
    plugins_manager: PluginsManager,
) {
    // SkillsWatcher を構築
    let skills_watcher = SkillsWatcher::new(&file_watcher);

    // 設定に基づきスキルの監視ルートを登録
    let registration = skills_watcher.register_config(
        &config,
        &skills_manager,
        &plugins_manager,
    );

    // registration を保持しておけば、必要に応じて監視解除などが行える可能性があります
    // （WatchRegistration の API はこのチャンクには現れません）
}
```

**Errors / Panics**

- メソッド自体は `Result` を返しておらず、明示的なパニックもありません（根拠: `L57-75`）。
- 間接的なエラー要因:
  - `plugins_manager.plugins_for_config` / `skills_manager.skill_roots_for_config` / `skills_load_input_from_config` が内部でエラーを起こす可能性はありますが、このメソッドでは扱われていません（根拠: `L63-66`）。
  - `subscriber.register_paths(roots)` のエラー処理もここでは行っておらず、戻り値は常に `WatchRegistration` として扱われます（根拠: `L74`）。

**Edge cases（エッジケース）**

- **スキルルートが空の場合**  
  - `skill_roots_for_config` が空リストを返した場合、`roots` も空になり、そのまま `register_paths` に渡されます（根拠: `L66-74`）。
  - `register_paths` が空入力時にどう振る舞うかはこのチャンクでは不明です。
- **パス情報の不足**  
  - `WatchPath` への変換では `root.path` フィールドのみ参照され、それ以外のメタ情報は捨てられています（根拠: `L69-71`）。`root` の型や他フィールドはこのチャンクには現れません。

**使用上の注意点**

- 設定変更ごとに再度 `register_config` を呼び出すことで監視対象を更新できる可能性がありますが、既存登録との関係（別 registration として共存するのか、上書きされるのか）は `FileWatcherSubscriber::register_paths` の仕様次第で、このチャンクからは分かりません（根拠: `L74`）。
- `Config` / `SkillsManager` / `PluginsManager` の整合性が取れていない場合、意図した監視パスにならない可能性があります。

---

#### `SkillsWatcher::spawn_event_loop(rx: Receiver, tx: broadcast::Sender<SkillsWatcherEvent>)`  （L77-88）

**概要**

- `FileWatcher` からのイベント `rx` を一定間隔でスロットリングしながら非同期に受信し、それを `SkillsWatcherEvent::SkillsChanged` としてブロードキャストするバックグラウンドタスクを起動します（根拠: `L77-83`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `rx` | `Receiver` | `FileWatcher` からの生イベントを受け取るチャネル。型の詳細は別モジュールにありますが、このファイルでは `event.paths` フィールドが参照されます（根拠: `L15,L77,L81-82`）。 |
| `tx` | `broadcast::Sender<SkillsWatcherEvent>` | スキル変更イベントを各サブスクライバに配信するためのブロードキャスト送信チャネル（根拠: `L34,L40,L77-83`）。 |

**戻り値**

- なし（`()`）。  
  - 副作用として、可能であれば Tokio ランタイム上に非同期タスクが一つ起動されます（根拠: `L79-84`）。

**内部処理の流れ**

1. `ThrottledWatchReceiver::new(rx, WATCHER_THROTTLE_INTERVAL)` でスロットリング付きのレシーバを生成します（根拠: `L16,L22-25,L77-79`）。
2. `Handle::try_current()` を呼び、現在のスレッドに Tokio ランタイムが紐付いているかを確認します（根拠: `L7,L79`）。
3. ランタイムが取得できた場合:
   1. `handle.spawn(async move { ... })` で非同期タスクを起動します（根拠: `L79-80`）。
   2. タスク内で `while let Some(event) = rx.recv().await` ループを回し、イベントを逐次受信します（根拠: `L80-82`）。
   3. 各イベントについて `SkillsWatcherEvent::SkillsChanged { paths: event.paths }` を構築し、`tx.send` でブロードキャストします（根拠: `L27-30,L81-82`）。
   4. `tx.send` の戻り値は無視されており、エラーはログ等に出ません（根拠: `L82`）。
4. ランタイムが取得できなかった場合:
   - `warn!("skills watcher listener skipped: no Tokio runtime available")` を出力し、イベントループは起動しません（根拠: `L85-87`）。

**Examples（使用例）**

- 通常は `SkillsWatcher::new` から内部的に呼び出されるため、直接呼び出す必要はありません（根拠: `L45,L77`）。

**Errors / Panics**

- 関数自体には `Result` や `panic!` はありません（根拠: `L77-88`）。
- 内部で発生しうるエラーとその扱い:
  - `Handle::try_current()` のエラーは `else` 節で `warn!` によってログ出力されますが、呼び出し元への通知は行われません（根拠: `L79-87`）。
  - `rx.recv().await` が `None` を返した場合（送信側が完全にクローズした場合）はループが終了し、そのままタスクも終了します（この挙動は `while let Some(...)` から読み取れます）（根拠: `L81-82`）。
  - `tx.send(...)` の結果は `let _ =` に捨てられており、エラー情報は無視されます（根拠: `L82`）。

**Edge cases（エッジケース）**

- **Tokio ランタイム不在**  
  - ランタイムがない状態で `SkillsWatcher::new` を呼び出すと、`spawn_event_loop` 内で警告が出るだけでイベントループが起動せず、以降イベントが配信されません（根拠: `L79-87`）。
- **イベントチャネルのクローズ**  
  - `Receiver` が `None` を返すような状態（送信側終了など）になると、`while let Some(event)` の条件が false となりループが終了します（根拠: `L81-82`）。
- **イベントの多重送信失敗**  
  - サブスクライバのラグやチャネルクローズにより `tx.send` が `Err` になるケースは無視されるため、イベントロスを検知できません（根拠: `L82`）。

**使用上の注意点**

- **観測可能性**  
  - イベントループの起動失敗は `tracing::warn` のログにしか出ず、API からは分かりません。そのため、観測にはログを必ず収集する前提が必要です（根拠: `L85-87`）。
- **テストと本番での挙動差**  
  - スロットリング間隔は本番で 10 秒、テストで 50ms に切り替わります（`#[cfg(test)]` / `#[cfg(not(test))]`）（根拠: `L22-25`）。短い間隔で頻繁にイベントが期待される場合、この値に注意が必要です。

---

### 3.3 その他の関数

このファイル内では、テスト専用の関数が 1 つ定義されています。

| 関数名 | 役割（1 行） | 定義行 |
|--------|--------------|--------|
| `forwards_file_watcher_events` | `FileWatcher` から送られたテスト用イベントが、そのまま `SkillsWatcherEvent::SkillsChanged` として購読側に届くことを検証する非同期テスト | `L98-121` |

---

## 4. データフロー

### 4.1 代表的な処理シナリオ

ここでは、「設定を登録してファイル変更イベントが購読側に届く」までの流れを示します。

1. アプリケーションが `FileWatcher` と `SkillsWatcher` を生成します（根拠: `L38-47`）。
2. アプリケーションが `register_config` を呼び出し、設定に基づいてスキルルートパスを `FileWatcherSubscriber` に登録します（根拠: `L57-75`）。
3. `FileWatcher` が監視対象パスでのファイル変更を検知し、内部チャネル `Receiver` にイベントを送信します（送信側の実装はこのチャンクには現れません）。
4. `spawn_event_loop` が Tokio タスクとして動作し、`Receiver` からイベントを受信し、`SkillsWatcherEvent::SkillsChanged` に変換して `broadcast::Sender` 経由で配信します（根拠: `L77-83`）。
5. `subscribe` で取得した `broadcast::Receiver` を持つコンポーネントは、`recv().await` によってイベントを受け取ります（根拠: `L53-55,L98-121`）。

### 4.2 シーケンス図

```mermaid
sequenceDiagram
    participant App as "アプリケーション"
    participant FW as "FileWatcher (外部, L13)"
    participant SW as "SkillsWatcher (L32-88)"
    participant Loop as "spawn_event_loop (L77-88)"
    participant Sub as "Subscriber (broadcast, subscribe L53-55)"

    Note over App,SW: SkillsWatcher::new (L38-47)
    App->>FW: add_subscriber() 呼び出し (L39)
    FW-->>App: (subscriber, rx) を返す
    App->>SW: SkillsWatcher::new(&Arc<FileWatcher>) (L38-47)
    SW->>Loop: spawn_event_loop(rx, tx) を呼び出し (L45,L77-83)
    Loop->>Loop: Tokio::Handle::spawn で非同期タスク起動 (L79-84)

    Note over App,SW: register_config (L57-75)
    App->>SW: register_config(config, skills_manager, plugins_manager) (L57-75)
    SW->>FW: subscriber.register_paths(roots) (L74)

    Note over FW,Loop: ファイル変更検知
    FW-->>Loop: rx にファイルイベントを送信
    Loop->>Loop: while let Some(event) = rx.recv().await (L81)
    Loop->>Sub: tx.send(SkillsWatcherEvent::SkillsChanged { paths: event.paths }) (L82)

    Note over App,Sub: 購読開始
    App->>SW: subscribe() (L53-55)
    SW-->>App: broadcast::Receiver<SkillsWatcherEvent> を返す
    App->>Sub: rx.recv().await でイベントを待機 (テスト例 L111-114)
```

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

以下は、典型的な使用フロー（初期化 → 監視登録 → イベント購読）をまとめた例です。

```rust
use std::sync::Arc;
use core::file_watcher::FileWatcher;           // 実際のモジュールパスは crate に依存
use core::skills_watcher::{SkillsWatcher, SkillsWatcherEvent};
use core::config::Config;
use core::SkillsManager;
use core::plugins::PluginsManager;

#[tokio::main] // Tokio ランタイムを起動する
async fn main() {
    // 1. 基盤となる FileWatcher を用意する
    let file_watcher = Arc::new(FileWatcher::new(/* ... */)); // FileWatcher 実装はこのチャンクには現れない

    // 2. SkillsWatcher を生成する（内部で spawn_event_loop が起動される）
    let skills_watcher = SkillsWatcher::new(&file_watcher);   // L38-47

    // 3. Config / SkillsManager / PluginsManager を用意する
    let config = Config::load(/* ... */);                     // 仮の API。実装はこのチャンク外
    let skills_manager = SkillsManager::new(/* ... */);       // 仮
    let plugins_manager = PluginsManager::new(/* ... */);     // 仮

    // 4. 設定に基づきスキル監視ルートを登録する
    let _registration = skills_watcher.register_config(       // L57-75
        &config,
        &skills_manager,
        &plugins_manager,
    );

    // 5. スキル変更イベントを購読する
    let mut rx = skills_watcher.subscribe();                  // L53-55

    // 6. イベントを待ち受ける（例: メインタスク内でループ）
    while let Ok(event) = rx.recv().await {
        match event {
            SkillsWatcherEvent::SkillsChanged { paths } => {
                println!("スキルファイルが更新されました: {:?}", paths);
            }
        }
    }
}
```

### 5.2 よくある使用パターン

1. **テスト用に noop watcher を使う**

   - 実際のファイル監視を行わず、`FileWatcher::send_paths_for_test` のような API 経由で人工イベントを送るテストに利用できます（根拠: テストコード `L100-109`）。

   ```rust
   use std::sync::Arc;
   use core::file_watcher::FileWatcher;
   use core::skills_watcher::{SkillsWatcher, SkillsWatcherEvent};

   #[tokio::test]
   async fn test_skill_event_flow() {
       // noop な FileWatcher を使用
       let file_watcher = Arc::new(FileWatcher::noop());        // L100
       let skills_watcher = SkillsWatcher::new(&file_watcher);  // L101
       let mut rx = skills_watcher.subscribe();                 // L102

       // 監視対象パスを登録（テストでは subscriber に直接アクセス） L103-105
       let _registration = skills_watcher
           .subscriber
           .register_path("/tmp/skill".into(), true);

       // テスト用 API でイベントを送信（実装はこのチャンクには現れない） L107-109
       file_watcher
           .send_paths_for_test(vec!["/tmp/skill/SKILL.md".into()])
           .await;

       // SkillsWatcherEvent 経由で受信できるか確認
       if let Ok(event) = rx.recv().await {
           match event {
               SkillsWatcherEvent::SkillsChanged { paths } => {
                   assert_eq!(paths[0].to_str().unwrap(), "/tmp/skill/SKILL.md");
               }
           }
       }
   }
   ```

2. **複数コンポーネントからの購読**

   - `subscribe()` を複数回呼び出すことで、異なるコンポーネントが各自 `Receiver` を持ってスキル変更イベントを監視できます（根拠: `L53-55`）。

### 5.3 よくある間違い

```rust
// 間違い例: Tokio ランタイム外で SkillsWatcher::new を呼ぶ
fn main() {
    let file_watcher = Arc::new(FileWatcher::new());
    let skills_watcher = SkillsWatcher::new(&file_watcher); // L38-47

    // spawn_event_loop 内で Handle::try_current() が失敗し、
    // warn ログだけ出てイベントループが起動しない（L79-87）。
    let mut rx = skills_watcher.subscribe();
    // この rx にイベントは届かない可能性が高い。
}

// 正しい例: Tokio ランタイム内で初期化する
#[tokio::main]
async fn main() {
    let file_watcher = Arc::new(FileWatcher::new());
    let skills_watcher = SkillsWatcher::new(&file_watcher); // L38-47

    let mut rx = skills_watcher.subscribe(); // L53-55

    // ここで rx.recv().await によりイベントを受け取れる
}
```

### 5.4 使用上の注意点（まとめ）

- **Tokio ランタイムの必須性**
  - `spawn_event_loop` は `Handle::try_current()` に依存しており、ランタイムが存在しない場合はログを出して何もしません（根拠: `L79-87`）。  
    そのため、`SkillsWatcher::new` は **必ず Tokio ランタイム内で呼び出す** ことが望ましいです。
- **イベントロスの可能性**
  - `broadcast::Sender::send` の戻り値を無視しているため、バッファ溢れや購読側のラグによる `Lagged` エラーなどが検知されません（根拠: `L40,L82`）。
- **スロットリング**
  - 本番では 10 秒間隔でイベントがスロットリングされます（根拠: `L22-23`）。高速な変更検知が必要なユースケースでは、この値が影響します。
- **監視パスの重複や空リスト**
  - `register_config` は単純に `WatchPath` を生成して `register_paths` に渡すだけであり、重複排除や空入力時の特別な分岐はありません（根拠: `L66-74`）。  
    その扱いは `FileWatcherSubscriber` に委ねられています。

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

例: スキル変更の種類（作成・更新・削除など）を区別したい場合。

1. **イベント型の拡張**
   - `SkillsWatcherEvent` に新しいバリアントやフィールドを追加します（根拠: 現在は `SkillsChanged { paths }` のみ `L27-30`）。
2. **イベントループでのマッピング変更**
   - `spawn_event_loop` 内で `event` からより詳細な情報（作成/更新/削除など）を引き出し、新しい `SkillsWatcherEvent` の形に変換します（根拠: 現在は `paths` のみ `L81-82`）。
3. **購読側の対応**
   - `SkillsWatcherEvent` をマッチしている呼び出し側コードを拡張し、新しいバリアントに対応させます（根拠: テストの `match event` `L115-120`）。

### 6.2 既存の機能を変更する場合

- **スロットリング間隔を変更したい場合**
  - `WATCHER_THROTTLE_INTERVAL` の定数値を変更します（根拠: `L22-25`）。
  - テストと本番での挙動差が変わるため、`#[cfg(test)]` ブロックの値も併せて確認します。
- **イベントループのエラーハンドリングを強化したい場合**
  - `spawn_event_loop` 内の `let _ = tx.send(...)` を `match` などで結果確認し、ログやメトリクスを追加します（根拠: `L82`）。
- **監視パスの決定ロジックを変更したい場合**
  - `register_config` の内部で呼んでいる `skills_load_input_from_config` や `skills_manager.skill_roots_for_config` 周辺を修正します（根拠: `L63-67`）。
  - 変更時は `WatchPath` の生成（`recursive: true` の固定値など）も見直す必要があります（根拠: `L69-72`）。

変更時に注意すべき点:

- `SkillsWatcherEvent` の形を変えると、crate 外からも参照されている可能性があるため、後方互換性に注意が必要です（可視性 `pub`、根拠: `L27`）。
- `SkillsWatcher` は `pub(crate)` なので crate 内のみの利用ですが、テストからフィールド `subscriber` に直接アクセスしているため（根拠: `L103-105`）、フィールド名や可視性変更はテストへの影響も考える必要があります。

---

## 7. 関連ファイル

このモジュールと密接に関係するモジュール（ファイルパスはモジュール名から推測し、正確なディスク上パスはこのチャンクには現れません）。

| パス / モジュール | 役割 / 関係 |
|-------------------|------------|
| `crate::file_watcher` | `FileWatcher`, `FileWatcherSubscriber`, `Receiver`, `ThrottledWatchReceiver`, `WatchPath`, `WatchRegistration` を提供する。`SkillsWatcher` はここからイベントを受け取り、監視パスを登録します（根拠: `L13-18,L38-40,L69-74`）。 |
| `crate::SkillsManager` | スキルに関するルートパスを決定するコンポーネント。`register_config` で監視対象パスの候補を取得するために使用されます（根拠: `L11,L60-67`）。 |
| `crate::plugins::PluginsManager` | `Config` に基づき、どのプラグインが有効か、および実効スキルルートを決定するコンポーネント（根拠: `L19,L61-64`）。 |
| `crate::config::Config` | 設定情報を保持するコンポーネント。プラグイン・スキル入力の基礎データとして利用されます（根拠: `L12,L57-60,L63-65`）。 |
| `crate::skills_load_input_from_config` | `Config` とプラグイン情報からスキルロード入力を生成するユーティリティ関数（根拠: `L20,L65`）。 |

---

### テスト・バグ・セキュリティ・エッジケースの補足

- **テスト**  
  - `forwards_file_watcher_events` テストは、`FileWatcher::send_paths_for_test` で送信したパスが `SkillsWatcherEvent::SkillsChanged` としてそのまま購読側に届くことを検証しています（根拠: `L98-121`）。  
    これにより、`spawn_event_loop` の基本的な配線（paths フィールドのコピー）が保証されています。
- **潜在的なバグ / セキュリティ観点**
  - エラーを無視しているため、イベントロスが静かに発生する可能性があります（`tx.send` の結果無視、根拠: `L82`）。
  - パス値 `PathBuf` は外部入力に由来する可能性があるため、購読側で使用する際はパス検証やサニタイズが必要な場合がありますが、その責任はこのモジュールでは負いません（根拠: `SkillsWatcherEvent` が単に `paths` を持つのみ `L27-30`）。
- **契約 / エッジケース**
  - `SkillsWatcher` は「Tokio ランタイムが存在する前提」「`FileWatcher` が正しくイベントを送る前提」で動作するコンポーネントであり、これらが満たされない場合の挙動はログに限られます（根拠: `L38-47,L77-88`）。
