# config/src/config_toml.rs コード解説

## 0. ざっくり一言

Codex 全体の `config.toml` をデシリアライズするための **スキーマ定義モジュール**です。  
サンドボックスポリシー、モデルプロバイダ設定、エージェント設定など、多数の機能設定を型安全に扱うための構造体・補助関数を提供します。

---

## 1. このモジュールの役割

### 1.1 概要

- このモジュールは **Codex の設定ファイル (`~/.codex/config.toml`) のスキーマ**を定義し、`serde` によるデシリアライズ／シリアライズに対応した Rust 型として表現します（`ConfigToml` など `config/src/config_toml.rs:L65-396`）。
- サンドボックスモードと実際の `SandboxPolicy` の対応付け、プロジェクトごとの信頼レベル解決、モデルプロバイダ設定検証など、**設定値から実行時設定への変換ロジック**も含みます（`derive_sandbox_policy`, `get_active_project`, `validate_model_providers` など）。
- `schemars` による JSON Schema 生成向けメタ情報を併用し、CLI や外部ツールが設定スキーマを機械可読に扱えるようにしています（多くの型に `#[schemars(deny_unknown_fields)]` が付与されています）。

### 1.2 アーキテクチャ内での位置づけ

このファイルの主要な型・関数と、外部モジュールとの関係を簡略化して示します。

```mermaid
%% config/src/config_toml.rs: 全体依存関係 (L59-797)
graph TD
    subgraph config_toml_rs
        A[ConfigToml<br/>(L65-396)]
        B[ProjectConfig<br/>(L423-427)]
        C[Realtime*Toml/Config<br/>(L439-490,465-483)]
        D[ToolsToml<br/>(L492-504)]
        E[AgentsToml / AgentRoleToml<br/>(L531-572)]
        F[GhostSnapshotToml<br/>(L583-595)]
        G[derive_sandbox_policy<br/>(L599-675)]
        H[get_active_project<br/>(L677-705)]
        I[get_config_profile<br/>(L708-726)]
        J[validate_model_providers<br/>(L760-769)]
        K[validate_oss_provider<br/>(L783-797)]
    end

    A --> G
    A --> H
    A --> I

    H --> B
    H --> L(project_trust_key<br/>(L733-737))
    H --> M(resolve_root_git_project_for_trust<br/>from codex_git_utils)

    A --> N(Types in crate::types<br/>McpServerConfig, Tui, ...)

    A --> O(SandboxMode / SandboxPolicy / ReadOnlyAccess<br/>from codex_protocol)
    G --> O

    A --> P(ModelProviderInfo<br/>from codex_model_provider_info)
    J --> P

    A --> Q(ToolsToml)
    Q --> R[From<ToolsToml> for Tools<br/>(L574-580)]
    R --> S(Tools<br/>from codex_app_server_protocol)

    A --> E
    A --> F
    A --> C
```

- **上流**: `ConfigToml` は CLI 起動時の設定読込処理から利用されることが想定されます（このチャンクには読込処理自体は含まれません）。
- **下流**:
  - 実行時ポリシー (`SandboxPolicy`) の決定（`derive_sandbox_policy`）。
  - アプリケーションサーバプロトコル向けの設定 (`UserSavedConfig`, `Tools`) への変換（`impl From<ConfigToml> for UserSavedConfig`, `impl From<ToolsToml> for Tools`）。
  - モデルプロバイダ設定や OSS プロバイダ ID の検証（`validate_model_providers`, `validate_oss_provider`）。

### 1.3 設計上のポイント

- **スキーマ主導の設定定義**  
  - 多くの構造体に `#[derive(Serialize, Deserialize, JsonSchema)]` と `#[schemars(deny_unknown_fields)]` が付与されており、未知フィールドをエラーとして扱う設計になっています（例: `ConfigToml` `config/src/config_toml.rs:L65-68`, `ProjectConfig` `L423-425`, `AgentsToml` `L531-533`）。
- **オプションとデフォルト値の多用**  
  - 設定ファイルからの指定が任意の項目は `Option<T>` として定義され、`#[serde(default)]` により TOML からの省略時にもデシリアライズ可能になっています（例: `ConfigToml::permissions` `L114-116`, `ConfigToml::profiles` `L221-223`）。
- **カスタムデシリアライズでのバリデーション組み込み**
  - `model_providers` フィールドは `deserialize_model_providers` で読み込み時に即時検証されます（`ConfigToml::model_providers` `L191-194`, `deserialize_model_providers` `L772-781`）。
  - `ToolsToml::web_search` は `deserialize_optional_web_search_tool_config` によって、`bool` と設定オブジェクトの 2 形態の入力を受け付ける設計です（`L492-504`, `L506-511`, `L513-529`）。
- **プロジェクト信頼レベルとサンドボックスの連動**
  - `ConfigToml::get_active_project` と `project_trust_key` を通じてカレントディレクトリの信頼レベルを解決し、それを `derive_sandbox_policy` でデフォルトの `SandboxMode` 決定に利用します（`L597-675`, `L677-705`, `L733-737`）。
- **セキュリティ関連の配慮**
  - Windows かつサンドボックス無効 (`WindowsSandboxLevel::Disabled`) の場合、`WorkspaceWrite` ポリシーを強制的に `ReadOnly` にダウングレードする処理があります（`downgrade_workspace_write_if_unsupported` 内 `L651-658`）。
  - `sandbox_policy_constraint` による上位の制約 (`Constrained<SandboxPolicy>`) を満たさない場合、警告ログを出した上で必須デフォルトにフォールバックします（`L663-673`）。
  - モデルプロバイダ ID の予約語チェック (`validate_reserved_model_provider_ids` `L740-757`) や OSS プロバイダ検証 (`validate_oss_provider` `L783-797`) により、危険または不正な設定を早期に検出します。

---

## 2. 主要な機能一覧

- 全体設定 `ConfigToml` の定義と JSON Schema メタ情報（`L65-396`）。
- `ConfigToml` からユーザ保存設定 `UserSavedConfig` への変換（`impl From<ConfigToml> for UserSavedConfig` `L398-421`）。
- プロジェクト単位の信頼設定 `ProjectConfig` と信頼／不信頼チェックメソッド（`L423-437`）。
- Realtime 音声・セッション関連の TOML 構造体定義（`RealtimeConfig`, `RealtimeToml`, `RealtimeAudioToml`, `RealtimeAudioConfig` `L439-473`, `L485-490`）。
- `ToolsToml` とアプリケーションサーバ側 `Tools` との変換（`L492-504`, `L574-580`）。
- エージェント設定 (`AgentsToml` / `AgentRoleToml`) の構造定義（`L531-572`）。
- ゴーストスナップショット設定 (`GhostSnapshotToml`) の定義（`L583-595`）。
- サンドボックスモードから実行ポリシー `SandboxPolicy` を導出する関数（`ConfigToml::derive_sandbox_policy` `L599-675`）。
- カレントディレクトリに対応するプロジェクト設定の解決（`ConfigToml::get_active_project` `L677-705`）。
- プロファイル名から `ConfigProfile` を取得するユーティリティ（`ConfigToml::get_config_profile` `L708-726`）。
- モデルプロバイダ設定の検証 (`validate_model_providers`, `validate_reserved_model_provider_ids`, `deserialize_model_providers` `L740-781`)。
- OSS プロバイダ ID の検証 (`validate_oss_provider` `L783-797`)。

---

## 3. 公開 API と詳細解説

### 3.1 型一覧（構造体・列挙体など）

主要な公開型のインベントリーです。

| 名前 | 種別 | 行範囲 | 役割 / 用途 |
|------|------|--------|-------------|
| `ConfigToml` | 構造体 | `config/src/config_toml.rs:L65-396` | 全体の `config.toml` を表現するメイン設定構造体。モデル・サンドボックス・エージェント・アプリ・Windows など多数のサブ設定を内包します。 |
| `ProjectConfig` | 構造体 | `L423-427` | プロジェクト単位の信頼レベル (`TrustLevel`) を保持します。 |
| `RealtimeAudioConfig` | 構造体 | `L439-443` | 実行時のリアルタイム音声設定（マイク・スピーカー名）。設定 TOML と対になるロジック向け構造体です。 |
| `RealtimeWsMode` | 列挙体 | `L445-451` | Realtime WebSocket セッションのモード（会話 / 文字起こし）を表します。snake_case でシリアライズされます。 |
| `RealtimeTransport` | 列挙体 | `L453-460` | Realtime セッションのトランスポート種別（`webrtc` / `websocket`）。 |
| `RealtimeWsVersion` | 型再エクスポート | `L462` | `codex_protocol::protocol::RealtimeConversationVersion` の別名。設定ファイルからバージョンを指定するために使用されます。 |
| `RealtimeVoice` | 型再エクスポート | `L463` | Realtime 音声プロファイルの型を外部に再公開します。 |
| `RealtimeConfig` | 構造体 | `L465-473` | 実行時に使う Realtime 設定 (`version`, `session_type`, `transport`, `voice`)。 |
| `RealtimeToml` | 構造体 | `L475-483` | TOML 用の Realtime 設定（すべて `Option`）。未指定時にデフォルトを適用しやすくするための形。 |
| `RealtimeAudioToml` | 構造体 | `L485-490` | TOML 用の Realtime 音声設定。 |
| `ToolsToml` | 構造体 | `L492-504` | `tools` セクションの設定。Web 検索ツールと `view_image` の有効化を制御します。 |
| `WebSearchToolConfigInput` | 列挙体 | `L506-511` | `tools.web_search` の入力形態（`bool` または `WebSearchToolConfig`）を表す内部用 enum。 |
| `AgentsToml` | 構造体 | `L531-557` | エージェント機能のスレッド数・ネスト深さ・ジョブ実行時間などの制限と、ユーザ定義ロールのマップを保持します。 |
| `AgentRoleToml` | 構造体 | `L559-572` | 単一エージェントロールの説明・追加設定ファイル・ニックネーム候補を持ちます。 |
| `GhostSnapshotToml` | 構造体 | `L583-595` | ゴーストスナップショット（undo 用）のサイズ・ディレクトリ数・警告抑制設定を保持します。 |
| `RealtimeAudioConfig` | 構造体 | `L439-443` | 実行時用の音声設定（TOML ではなくロジック側で利用）。 |
| `RESERVED_MODEL_PROVIDER_IDS` | 定数 | `L59-63` | 上書き禁止のモデルプロバイダ ID のリスト。検証関数で利用します。 |

#### 関数インベントリー

主要な関数・メソッドの一覧です。

| 関数名 | 可視性 | 戻り値 | 行範囲 | 概要 |
|--------|--------|--------|--------|------|
| `ConfigToml::derive_sandbox_policy` | `pub` | `SandboxPolicy` | `L599-675` | サンドボックスモードやプロジェクト信頼レベルから実際の `SandboxPolicy` を決定します。 |
| `ConfigToml::get_active_project` | `pub` | `Option<ProjectConfig>` | `L677-705` | カレントディレクトリまたはその Git ルートに対応する `ProjectConfig` を探索します。 |
| `ConfigToml::get_config_profile` | `pub` | `Result<ConfigProfile, std::io::Error>` | `L708-726` | 指定またはデフォルトのプロファイル名から `ConfigProfile` を取得します。 |
| `impl From<ConfigToml> for UserSavedConfig::from` | `pub`（impl） | `UserSavedConfig` | `L398-421` | ユーザ保存用の設定構造体へ値を抽出・変換します。 |
| `ProjectConfig::is_trusted` | `pub` | `bool` | `L430-432` | `trust_level` が Trusted かどうかを判定します。 |
| `ProjectConfig::is_untrusted` | `pub` | `bool` | `L434-436` | `trust_level` が Untrusted かどうかを判定します。 |
| `impl From<ToolsToml> for Tools::from` | `pub`（impl） | `Tools` | `L574-580` | `ToolsToml` からプロトコル用 `Tools` へ変換します。 |
| `deserialize_optional_web_search_tool_config` | private | `Result<Option<WebSearchToolConfig>, D::Error>` | `L513-529` | `tools.web_search` を `bool` または `WebSearchToolConfig` としてデシリアライズします。 |
| `project_trust_key` | private | `String` | `L733-737` | パスを正規化してプロジェクト信頼マップのキー文字列を生成します。 |
| `validate_reserved_model_provider_ids` | `pub` | `Result<(), String>` | `L740-757` | `model_providers` に予約済み ID が含まれないか検証します。 |
| `validate_model_providers` | `pub` | `Result<(), String>` | `L760-769` | 各 `ModelProviderInfo` の自己検証と予約 ID 検証を行います。 |
| `deserialize_model_providers` | private | `Result<HashMap<String, ModelProviderInfo>, D::Error>` | `L772-781` | TOML から `model_providers` を読み込み、同時に検証します。 |
| `validate_oss_provider` | `pub` | `std::io::Result<()>` | `L783-797` | `oss_provider` フィールド用に許可された OSS プロバイダ ID かどうか検査します。 |

### 3.2 関数詳細（最大 7 件）

以下では特に重要な 7 関数（および関連 impl）を詳しく解説します。

---

#### `ConfigToml::derive_sandbox_policy(&self, sandbox_mode_override: Option<SandboxMode>, profile_sandbox_mode: Option<SandboxMode>, windows_sandbox_level: WindowsSandboxLevel, resolved_cwd: &Path, sandbox_policy_constraint: Option<&crate::Constrained<SandboxPolicy>>) -> SandboxPolicy`

**概要**

- サンドボックスモード関連の複数の情報（明示オーバーライド、プロファイル設定、グローバル設定、プロジェクト信頼レベル、Windows サンドボックス状態、外部制約）から、最終的な実行ポリシー `SandboxPolicy` を算出します（`config/src/config_toml.rs:L599-675`）。
- **安全性／セキュリティ上の中核ロジック**であり、Windows 上でサンドボックスが無効な場合の自動ダウングレードや、外部制約の強制などが含まれています。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `sandbox_mode_override` | `Option<SandboxMode>` | 呼び出し元が明示的に指定する一時的なサンドボックスモード。 |
| `profile_sandbox_mode` | `Option<SandboxMode>` | プロファイルに紐付いたサンドボックスモード（`ConfigProfile` 由来）。 |
| `windows_sandbox_level` | `WindowsSandboxLevel` | Windows 上でのサンドボックスレベル（有効／無効など）。 |
| `resolved_cwd` | `&Path` | 実行時のカレントディレクトリ。プロジェクト信頼設定の解決に使われます。 |
| `sandbox_policy_constraint` | `Option<&crate::Constrained<SandboxPolicy>>` | 上位から課された「必須サンドボックス条件」。デフォルトポリシーが条件を満たさない場合、強制的に制約に従わせます。 |

**戻り値**

- `SandboxPolicy`  
  - `SandboxMode` やプロジェクト信頼、Windows サンドボックス状態などを加味して決定された **実行時のサンドボックスポリシー**です。具体的なバリアントは `SandboxPolicy` 型の実装に依存し、このファイルには詳細は現れません。

**内部処理の流れ**

1. **明示指定の有無を記録**  
   - `sandbox_mode_override`, `profile_sandbox_mode`, `self.sandbox_mode` のいずれかが `Some` なら「明示的にモードが指定された」とみなします（`sandbox_mode_was_explicit` `L607-609`）。
2. **サンドボックスモードの解決**  
   - 優先順位は `sandbox_mode_override` → `profile_sandbox_mode` → `self.sandbox_mode` → プロジェクト信頼レベルからの自動決定 → `SandboxMode::default()` です（`L610-631`）。
   - プロジェクト信頼レベルが Trusted/Untrusted で、かつ `sandbox_mode` 未指定のとき:
     - Windows かつ `windows_sandbox_level == WindowsSandboxLevel::Disabled` なら `ReadOnly`、それ以外なら `WorkspaceWrite` をデフォルトとします（`L614-625`）。
3. **`SandboxMode` から `SandboxPolicy` を構築**  
   - `match resolved_sandbox_mode` で 3 バリアントをポリシーに変換します（`L632-650`）:
     - `ReadOnly` → `SandboxPolicy::new_read_only_policy()`。
     - `WorkspaceWrite` → `SandboxWorkspaceWrite` が設定されていればその値を複製して `SandboxPolicy::WorkspaceWrite` を構築、なければ `SandboxPolicy::new_workspace_write_policy()`。
     - `DangerFullAccess` → `SandboxPolicy::DangerFullAccess`。
4. **Windows 非サンドボックス環境でのダウングレード**  
   - ローカルクロージャ `downgrade_workspace_write_if_unsupported` を定義し（`L651-658`）、Windows かつ `windows_sandbox_level == WindowsSandboxLevel::Disabled` で、ポリシーが `WorkspaceWrite` の場合は `ReadOnly` に置き換えます。
   - `resolved_sandbox_mode` が `WorkspaceWrite` のときに一度適用します（`L660-662`）。
5. **外部制約 (`Constrained<SandboxPolicy>`) の適用**  
   - サンドボックスモードが明示的に指定されていない場合に限り（`!sandbox_mode_was_explicit`）、`constraint.can_set(&sandbox_policy)` を呼びます（`L663-666`）。
   - `Err(err)` の場合:
     - `tracing::warn!` で警告ログを出力し（`L667-670`）、`sandbox_policy = constraint.get().clone()` により必須デフォルトにフォールバックします（`L671`）。
     - その後、再度 `downgrade_workspace_write_if_unsupported` を適用して Windows 非サンドボックス環境に対応します（`L672`）。
6. **最終ポリシーを返却**  
   - 以上を踏まえた `sandbox_policy` を返します（`L674`）。

**Examples（使用例）**

```rust
use std::path::Path;
use codex_protocol::config_types::{SandboxMode, WindowsSandboxLevel};
use codex_protocol::protocol::SandboxPolicy;

// `config` はすでに TOML からデシリアライズされた ConfigToml とする
fn derive_policy_example(config: &crate::config_toml::ConfigToml) -> SandboxPolicy {
    let cwd = Path::new("/path/to/project");
    // sandbox_mode_override/profile は未指定、制約もなし
    config.derive_sandbox_policy(
        None,
        None,
        WindowsSandboxLevel::Disabled, // 例: Windows でサンドボックス無効
        cwd,
        None,
    )
}
```

**Errors / Panics**

- この関数自身は `Result` を返さず、`panic!` も使用していないため、**直接的なエラーやパニックは発生しません**。
- ただし内部で呼び出している `self.get_active_project` や `tracing::warn!`、`Constrained::can_set` はそれぞれの実装に依存します（このチャンクには詳細は現れません）。

**Edge cases（エッジケース）**

- すべてのサンドボックスモード引数が `None` で、かつ該当プロジェクトに信頼設定がない場合は、`SandboxMode::default()` に依存したモードが選択されます（`L610-631`）。
- Windows かつ `WindowsSandboxLevel::Disabled` の場合は、`WorkspaceWrite` から `ReadOnly` への強制ダウングレードが行われる可能性があります（`L651-658`）。
- `sandbox_policy_constraint` が設定されていても、**ユーザが明示的にモードを指定した場合**（`sandbox_mode_was_explicit == true`）には `constraint.can_set` チェックは行われません（`L663-666`）。

**使用上の注意点**

- 安全側に倒すため、Windows でサンドボックスが無効な場合には `WorkspaceWrite` が自動的に `ReadOnly` に変わりうる点を前提にする必要があります。
- `sandbox_policy_constraint` によりデフォルトポリシーが上書きされるのは「モードが明示されていないとき」に限定されるため、**強制したい制約がある場合は、明示モードと組み合わせ方を設計**する必要があります。

---

#### `ConfigToml::get_active_project(&self, resolved_cwd: &Path) -> Option<ProjectConfig>`

**概要**

- カレントディレクトリ `resolved_cwd` から、`self.projects` に登録された `ProjectConfig` を探索します（`config/src/config_toml.rs:L677-705`）。
- 直接キー一致が見つからない場合は、Git リポジトリのルートディレクトリに対応するエントリを探し、**Git ワークツリーが親プロジェクトの信頼設定を継承できるように**しています。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `resolved_cwd` | `&Path` | すでに解決済みのカレントディレクトリパス。 |

**戻り値**

- `Option<ProjectConfig>`  
  - 一致するプロジェクト設定があれば `Some(ProjectConfig)`（クローンされた値）、見つからなければ `None` を返します。

**内部処理の流れ**

1. `self.projects.clone().unwrap_or_default()` でプロジェクトマップを取得します（`L680`）。`None` の場合は空のマップが使われます。
2. `project_trust_key(resolved_cwd)` で正規化したキー文字列を作成しつつ、`resolved_cwd.to_string_lossy().to_string()` で生の文字列キーも作ります（`L682-683`）。
3. `projects.get(&resolved_cwd_key).or_else(|| projects.get(&resolved_cwd_raw_key))` で、正規化キー → 生キー の順に探索します（`L684-687`）。
4. 見つかれば `Some(project_config.clone())` を返します（`L688`）。
5. 見つからない場合は `resolve_root_git_project_for_trust(resolved_cwd)` を呼び出し、カレントディレクトリを含む Git リポジトリの「ルートプロジェクトパス」を取得します（`L694`）。
6. ルートパスが取得できた場合は同様に `project_trust_key` と `to_string_lossy` の 2 つのキーで `projects` を検索し、見つかれば `Some` を返します（`L695-702`）。
7. いずれも見つからなければ `None` を返します（`L705`）。

**Examples（使用例）**

```rust
use std::path::Path;
use crate::config_toml::ConfigToml;

fn check_project_trust(config: &ConfigToml, cwd: &Path) -> Option<bool> {
    config.get_active_project(cwd).map(|proj| proj.is_trusted())
}
```

**Errors / Panics**

- `get_active_project` 自体は `Result` を返さず、`panic!` も使用していません。
- `project_trust_key` 内で `dunce::canonicalize` を使っていますが、失敗時は `unwrap_or_else` で元のパスにフォールバックするためパニックは発生しません（`L733-737`）。

**Edge cases（エッジケース）**

- `self.projects` が `None` または空の場合、常に `None` を返します（`L680`）。
- `project_trust_key` がエラーになり、元のパスと canonicalized パスが異なる表記ゆれでも、設定ファイル側がどちらか一方しか登録していないと一致しない可能性があります。
- Git リポジトリに属さないディレクトリでは、後半の「ルートプロジェクト検索」はスキップされます（`resolve_root_git_project_for_trust` が `None` を返す場合）。

**使用上の注意点**

- マップ (`self.projects`) を都度 `clone` しているため、非常に大きなマップを頻繁に扱う場合にはコストがかかる可能性があります。
- キーは文字列パスで比較するため、**設定ファイル内のキー表記（シンボリックリンク・大文字小文字・UNC など）と実際の `resolved_cwd` の形が一致するように意識**する必要があります。

---

#### `ConfigToml::get_config_profile(&self, override_profile: Option<String>) -> Result<ConfigProfile, std::io::Error>`

**概要**

- 明示的な `override_profile` または `self.profile` に基づいて、`profiles` マップから `ConfigProfile` を取得します（`config/src/config_toml.rs:L708-726`）。
- 指定されたプロファイル名が存在しない場合には `std::io::ErrorKind::NotFound` の `Err` を返します。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `override_profile` | `Option<String>` | 呼び出し側から渡されるプロファイル名のオーバーライド。`None` の場合は `self.profile` を使用。 |

**戻り値**

- `Result<ConfigProfile, std::io::Error>`  
  - 成功時: 対応する `ConfigProfile` のクローン。  
  - 失敗時: `ErrorKind::NotFound` と `"config profile \`{key}\` not found"` というメッセージを持つ `std::io::Error`。

**内部処理の流れ**

1. `let profile = override_profile.or_else(|| self.profile.clone());` で最終的なプロファイル名候補を決定します（`L712`）。
2. `match profile` で分岐します（`L714`）:
   - `Some(key)`:
     - `self.profiles.get(key.as_str())` を検索し、あれば `Ok(profile.clone())` を返します（`L715-718`）。
     - 見つからなければ `std::io::ErrorKind::NotFound` とエラーメッセージを持つ `Err` を構築して返します（`L720-723`）。
   - `None`:
     - プロファイル未指定とみなし、`Ok(ConfigProfile::default())` を返します（`L725`）。

**Examples（使用例）**

```rust
use crate::config_toml::ConfigToml;

fn load_profile(config: &ConfigToml) -> std::io::Result<crate::profile_toml::ConfigProfile> {
    // コマンドライン引数などで override_profile を与えていない場合
    config.get_config_profile(None)
}
```

**Errors / Panics**

- プロファイル名が設定ファイルに存在しない場合には、`ErrorKind::NotFound` の `Err` を返します（`L720-723`）。
- パニックを引き起こすコードはありません。

**Edge cases（エッジケース）**

- `override_profile` が `Some` でも `self.profiles` に存在しない場合は、`self.profile` にフォールバックせず即座に `Err` になります。
- `self.profile` が `Some` でも `profiles` に対応エントリがない場合は同様に `Err` を返します。
- `override_profile` も `self.profile` も `None` の場合は、常に `ConfigProfile::default()` が返ります。

**使用上の注意点**

- エラーが `NotFound` のときにどの名前が見つからなかったかはエラーメッセージ文字列に含まれますが、型レベルでは区別されません。
- プロファイルを追加・削除したときは、`self.profile` や CLI 側のデフォルト値が既存プロファイルを指しているか確認する必要があります。

---

#### `impl From<ConfigToml> for UserSavedConfig { fn from(config_toml: ConfigToml) -> UserSavedConfig }`

**概要**

- 設定全体 `ConfigToml` から、ユーザレベルで保存されるサブセット `UserSavedConfig` を構築します（`config/src/config_toml.rs:L398-421`）。
- 主に UI やアプリケーションサーバ側で必要とされる項目のみを抽出します。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `config_toml` | `ConfigToml` | 所有権付きの設定構造体。ここで消費され、フィールドが `UserSavedConfig` に移されます。 |

**戻り値**

- `UserSavedConfig`  
  - `approval_policy`, `sandbox_mode`, `sandbox_settings`, `forced_chatgpt_workspace_id`, `forced_login_method`, `model`, `model_reasoning_effort`, `model_reasoning_summary`, `model_verbosity`, `tools`, `profile`, `profiles` を含みます（`L406-418`）。

**内部処理の流れ**

1. `config_toml.profiles.into_iter().map(|(k, v)| (k, v.into())).collect()` で、各 `ConfigProfile` を `Into` 変換して新しいマップ `profiles` を作成します（`L400-404`）。
2. 構造体リテラルで `UserSavedConfig` を構築し、上記と一部のフィールドを代入します（`L406-418`）。
3. `tools` については `config_toml.tools.map(From::from)` を使用し、`Option<ToolsToml>` が `Option<Tools>` に変換されます（`L416`）。

**Examples（使用例）**

```rust
use crate::config_toml::ConfigToml;
use codex_app_server_protocol::UserSavedConfig;

fn to_user_saved(config: ConfigToml) -> UserSavedConfig {
    config.into() // From<ConfigToml> for UserSavedConfig が使われる
}
```

**Errors / Panics**

- 単純なフィールド移動と `Into` による変換のみであり、エラーやパニックを発生させるコードは含まれていません（このチャンクでは `Into` 実装の詳細は不明です）。

**Edge cases**

- `profiles` が空でも、`into_iter()` → `collect()` により空マップとして `UserSavedConfig` に設定されます。
- 各 `ConfigProfile` の `Into` 変換が失敗する可能性は型システム上ありません（`Into` はパニックしない前提ですが、実装内容はこのチャンクには現れません）。

**使用上の注意点**

- `ConfigToml` の所有権を消費するため、この変換後に同じインスタンスを再利用することはできません。必要なら事前に `clone` が必要です。
- `UserSavedConfig` に含まれない設定値（例: `agents`, `apps`, `features` など）は破棄される点を前提に設計する必要があります。

---

#### `impl From<ToolsToml> for Tools { fn from(tools_toml: ToolsToml) -> Tools }`

**概要**

- `config.toml` の `tools` セクション (`ToolsToml`) を、アプリケーションサーバ側の設定型 `Tools` に変換します（`config/src/config_toml.rs:L574-580`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `tools_toml` | `ToolsToml` | 設定からデシリアライズされた `tools` セクション。 |

**戻り値**

- `Tools`（`codex_app_server_protocol`）  
  - `web_search`: `tools_toml.web_search.is_some().then_some(true)` により、`Some(true)` または `None` が設定されます（`L576`）。
  - `view_image`: `tools_toml.view_image` をそのままコピーします（`L577`）。

**内部処理の流れ**

1. `tools_toml.web_search.is_some().then_some(true)`  
   - `Some(config)` の場合: `Some(true)`。  
   - `None` の場合: `None`。  
   - ここで `config` の中身（`WebSearchToolConfig`）は `Tools` 側には渡されません。
2. `view_image` フィールドはそのままコピーされます。

**Examples（使用例）**

```rust
use crate::config_toml::ToolsToml;
use codex_app_server_protocol::Tools;

fn to_server_tools(tools_toml: ToolsToml) -> Tools {
    Tools::from(tools_toml)
}
```

**Errors / Panics**

- フィールド代入のみであり、エラーやパニックを発生させません。

**Edge cases**

- `tools.web_search` が TOML で設定されていても、その形によって `Tools.web_search` の値が変わります:
  - `tools.web_search = { ... }` のようにテーブル形式で設定 → `Tools.web_search = Some(true)`（`ToolsToml.web_search = Some(config)` となるため）。
  - `tools.web_search = true` / `false` のような boolean 形式 → カスタムデシリアライザ `deserialize_optional_web_search_tool_config` が `None` を返すため、`ToolsToml.web_search = None` となり、`Tools.web_search` も `None` になります（`L513-529` を参照）。
- したがって、**現在のコードからは、boolean 指定は `Tools` には反映されず、「未指定」と同じ扱いになる**ことが読み取れます。

**使用上の注意点**

- `Tools` 側で Web 検索の有効／無効を判定するロジックが `Some(true)`／`None` の解釈に依存しているはずですが、その詳細はこのチャンクには現れません。  
  Web 検索機能を確実に有効化したい場合は、`WebSearchToolConfig` テーブル形式で設定する必要があると解釈できます（ただし仕様の意図は外部ドキュメントを要確認です）。

---

#### `fn deserialize_optional_web_search_tool_config<'de, D>(deserializer: D) -> Result<Option<WebSearchToolConfig>, D::Error> where D: Deserializer<'de>`

**概要**

- `ToolsToml.web_search` フィールド用のカスタムデシリアライザです（`config/src/config_toml.rs:L513-529`）。
- `tools.web_search` が TOML 上で `bool` または `WebSearchToolConfig` のどちらの形でも書けるようにしつつ、`ToolsToml.web_search` には **設定オブジェクトのみ**を残す挙動になっています。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `deserializer` | `D` | `serde` のデシリアライザ。 |

**戻り値**

- `Result<Option<WebSearchToolConfig>, D::Error>`  
  - `Ok(None)` または `Ok(Some(WebSearchToolConfig))`。  
  - `bool` 入力の場合は `Ok(None)`、テーブル形式の場合は `Ok(Some(config))` となります。

**内部処理の流れ**

1. `let value = Option::<WebSearchToolConfigInput>::deserialize(deserializer)?;` で `Option` を許容しつつ、`WebSearchToolConfigInput`（`Enabled(bool)` or `Config(WebSearchToolConfig)`）として読み込みます（`L519`）。
2. `match value` で分岐します（`L521-528`）:
   - `None` → `Ok(None)`。
   - `Some(WebSearchToolConfigInput::Enabled(enabled))` → `let _ = enabled;` として値を無視し、`Ok(None)` を返します（`L523-525`）。
   - `Some(WebSearchToolConfigInput::Config(config))` → `Ok(Some(config))` を返します（`L527`）。

**Examples（使用例）**

TOML での想定される書き方:

```toml
[tools]
# boolean 形式（現在の実装では ToolsToml.web_search は None になる）
web_search = true

# または設定オブジェクト形式
# [tools.web_search]
# mode = "live"
# provider = "some-provider"
```

**Errors / Panics**

- デシリアライズプロセスで型が合わない場合（例: 文字列が来るなど）は、`serde` の通常のエラーとして `D::Error` が返ります。
- パニックを引き起こすコードはありません。

**Edge cases**

- `web_search = true` と `web_search = false` はともに `ToolsToml.web_search = None` になります（`L523-525`）。  
  これは「単純な有効／無効フラグを設定しても、`ToolsToml` では区別されない」挙動です。
- `tools.web_search` セクション自体を省略した場合も `None` になるため、boolean 指定と省略が区別されない点に注意が必要です。

**使用上の注意点**

- この関数の挙動により、「細かい Web 検索設定をしたいときだけ `WebSearchToolConfig` テーブルを使う」というパターンが実現されていますが、単純に on/off したいだけならアプリケーション側で別の設定を用いる必要がある場合があります（`Tools` や他モジュールの処理はこのチャンクにはありません）。

---

#### `pub fn validate_model_providers(model_providers: &HashMap<String, ModelProviderInfo>) -> Result<(), String>`

**概要**

- `ConfigToml.model_providers` に対して、予約済み ID の不正上書きと各 `ModelProviderInfo` の自己検証を行います（`config/src/config_toml.rs:L760-769`）。
- **設定ロード時のバリデーションの中心**であり、`deserialize_model_providers` から呼び出されます（`L772-781`）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `model_providers` | `&HashMap<String, ModelProviderInfo>` | ユーザ定義のモデルプロバイダ定義マップ。 |

**戻り値**

- `Result<(), String>`  
  - 成功時: `Ok(())`。  
  - 失敗時: エラー内容を人間可読なメッセージ文字列で返します。

**内部処理の流れ**

1. `validate_reserved_model_provider_ids(model_providers)?;` を呼び出し、予約済み ID の上書きがないかチェックします（`L763`）。
2. `for (key, provider) in model_providers { ... }` で各エントリを走査し、`provider.validate()` を呼びます（`L764-767`）。
3. `provider.validate()` が `Err(message)` を返した場合は、`format!("model_providers.{key}: {message}")` によりキー付きエラーメッセージに変換し、その `Err` を返します（`L765-767`）。
4. すべて成功すれば `Ok(())` を返します（`L769`）。

**Examples（使用例）**

```rust
use std::collections::HashMap;
use codex_model_provider_info::ModelProviderInfo;

fn check_providers(map: &HashMap<String, ModelProviderInfo>) -> Result<(), String> {
    crate::config_toml::validate_model_providers(map)
}
```

**Errors / Panics**

- 予約 ID チェックに失敗した場合: `"model_providers contains reserved built-in provider IDs: ..."` 形式のエラー文字列を返します（`L740-757`）。
- 各 `ModelProviderInfo::validate()` が `Err` の場合: `"model_providers.{key}: {message}"` 形式のエラー文字列を返します（`L765-767`）。
- パニックを引き起こすコードはありません。

**Edge cases**

- `model_providers` が空の場合、`validate_reserved_model_provider_ids` はそのまま `Ok(())` を返し、ループもスキップされます。
- 同じ予約済み ID が複数回使われていても、エラーメッセージにはソート済み・ユニークなキー一覧が含まれます（`conflicts.sort_unstable()` `L748`）。

**使用上の注意点**

- `deserialize_model_providers` 経由で TOML から読み込む場合、この関数は自動的に実行されますが、プログラム内で `HashMap<String, ModelProviderInfo>` を手動構築する場合には、同様の検証を明示的に呼び出す必要がある場合があります。

---

#### `pub fn validate_oss_provider(provider: &str) -> std::io::Result<()>`

**概要**

- `ConfigToml.oss_provider` フィールドに設定された OSS プロバイダ ID が、許可された一覧に含まれるかを検証します（`config/src/config_toml.rs:L783-797`）。
- 旧 `OLLAMA` チャットプロバイダの ID は、専用エラーメッセージとともに拒否します。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `provider` | `&str` | 検証対象の OSS プロバイダ ID。 |

**戻り値**

- `std::io::Result<()>`  
  - 成功時: `Ok(())`。  
  - 失敗時: `ErrorKind::InvalidInput` と詳細メッセージを持つ `Err`。

**内部処理の流れ**

1. `match provider` で分岐します（`L784-796`）:
   - `LMSTUDIO_OSS_PROVIDER_ID` または `OLLAMA_OSS_PROVIDER_ID` → `Ok(())`（`L785`）。
   - `LEGACY_OLLAMA_CHAT_PROVIDER_ID` → `Err(std::io::Error::new(InvalidInput, OLLAMA_CHAT_PROVIDER_REMOVED_ERROR))`（`L786-789`）。
   - その他 → `Err(std::io::Error::new(InvalidInput, format!("Invalid OSS provider '{provider}'. Must be one of: ...")))`（`L790-795`）。

**Examples（使用例）**

```rust
use crate::config_toml::validate_oss_provider;

fn set_oss_provider(id: &str) -> std::io::Result<()> {
    validate_oss_provider(id)?;
    // ここで id を設定に保存するなど
    Ok(())
}
```

**Errors / Panics**

- 許可されていない ID の場合は必ず `ErrorKind::InvalidInput` の `Err` が返されます。
- パニックするコードはありません。

**Edge cases**

- `provider` が空文字列でも、いずれの `match` アームにも該当しないため、「Invalid OSS provider '...'」のエラーになります。
- 許可された ID かどうかは **完全一致** で判定されます。前方一致や大文字・小文字の違いなどは許容されません（コードからそのような処理は読み取れません）。

**使用上の注意点**

- この関数は `std::io::Result` を返すため、呼び出し側で `?` 演算子を利用すると I/O 系エラーと同じハンドリングパスに混在することになります。  
  論理エラーと I/O エラーを分けたい場合は、呼び出し側でメッセージに基づいて扱いを分ける必要があります。

---

### 3.3 その他の関数

補助的な関数やメソッドを一覧します。

| 関数名 | 役割（1 行） | 行範囲 |
|--------|--------------|--------|
| `ProjectConfig::is_trusted(&self) -> bool` | `trust_level` が `Some(Trusted)` かを判定します。 | `config/src/config_toml.rs:L430-432` |
| `ProjectConfig::is_untrusted(&self) -> bool` | `trust_level` が `Some(Untrusted)` かを判定します。 | `L434-436` |
| `project_trust_key(project_path: &Path) -> String` | パスを正規化（`dunce::canonicalize`）し、信頼マップのキーとして使う文字列に変換します。エラー時は元のパスを使用します。 | `L733-737` |
| `validate_reserved_model_provider_ids(model_providers: &HashMap<String, ModelProviderInfo>) -> Result<(), String>` | 予約済みプロバイダ ID がユーザ設定で上書きされていないかを検証します。 | `L740-757` |
| `deserialize_model_providers<'de, D>(deserializer: D) -> Result<HashMap<String, ModelProviderInfo>, D::Error>` | TOML から `model_providers` を読み込みつつ `validate_model_providers` で検証します。 | `L772-781` |

---

## 4. データフロー

ここでは、代表的なシナリオとして **サンドボックスポリシーの決定** のデータフローを説明します。

1. アプリケーションが `ConfigToml` を TOML からデシリアライズ済みとする。
2. 実行時に、CLI や UI が現在のカレントディレクトリとユーザ指定の sandbox オプションをもとに `ConfigToml::derive_sandbox_policy` を呼び出す（`L599-675`）。
3. `derive_sandbox_policy` 内部で、必要に応じて `get_active_project`（`L677-705`）と `project_trust_key`（`L733-737`）、`resolve_root_git_project_for_trust`（外部モジュール）を呼び出し、信頼レベルを取得する。
4. 得られた信頼レベルと Windows の sandbox 状態、`SandboxMode` の設定値を組み合わせて `SandboxPolicy` を導出する。
5. `sandbox_policy_constraint` が存在する場合は、デフォルトポリシーが許容されるかをチェックし、必要に応じてフォールバックとログ出力を行う。

```mermaid
%% config/src/config_toml.rs: derive_sandbox_policy (L599-675)
sequenceDiagram
    participant Caller as 呼び出し側
    participant Cfg as ConfigToml
    participant Proj as ConfigToml::get_active_project
    participant Git as resolve_root_git_project_for_trust
    participant Con as Constrained&lt;SandboxPolicy&gt;

    Caller->>Cfg: derive_sandbox_policy(override, profile_mode,\nwindows_sandbox_level, resolved_cwd, constraint)
    activate Cfg

    Cfg->>Cfg: resolve sandbox_mode\n(override → profile → self.sandbox_mode)
    alt sandbox_mode 未設定
        Cfg->>Proj: get_active_project(resolved_cwd)
        activate Proj
        Proj->>Proj: project_trust_key(resolved_cwd)
        Proj-->>Cfg: Option<ProjectConfig>
        deactivate Proj

        alt プロジェクト未検出
            Cfg->>Git: resolve_root_git_project_for_trust(resolved_cwd)
            Git-->>Cfg: Option<repo_root>
            Cfg->>Proj: get_active_project(repo_root)
            Proj-->>Cfg: Option<ProjectConfig>
        end

        Cfg->>Cfg: プロジェクト信頼レベルから\nSandboxMode デフォルト決定
    end

    Cfg->>Cfg: SandboxMode から SandboxPolicy 構築
    Cfg->>Cfg: downgrade_workspace_write_if_unsupported()

    alt !sandbox_mode_was_explicit && constraint.is_some()
        Cfg->>Con: can_set(&sandbox_policy)
        alt Err(err)
            Cfg-->>Caller: warn!(error=err,...)
            Cfg->>Con: get().clone()
            Cfg->>Cfg: sandbox_policy = constrained_default
            Cfg->>Cfg: downgrade_workspace_write_if_unsupported()
        end
    end

    Cfg-->>Caller: SandboxPolicy
    deactivate Cfg
```

この図からわかるポイント:

- **信頼レベル解決の経路**: `get_active_project` → `project_trust_key` → `resolve_root_git_project_for_trust` の順で探索します。
- **Windows と制約の影響**: ポリシー決定後にも `downgrade_workspace_write_if_unsupported` および `Constrained` による上書きが入るため、呼び出し側が期待するモードと実際のポリシーが異なる場合があります。

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

`ConfigToml` を TOML ファイルから読み込んで、プロファイルとサンドボックスポリシーを取得する一連の流れの例です（周辺コードは簡略化しています）。

```rust
use std::fs;
use std::path::Path;
use serde::Deserialize;
use crate::config_toml::ConfigToml;
use codex_protocol::config_types::WindowsSandboxLevel;

fn load_config_from_file(path: &Path) -> anyhow::Result<ConfigToml> {
    let text = fs::read_to_string(path)?;                  // TOML ファイルを読み込む
    let config: ConfigToml = toml::from_str(&text)?;       // ConfigToml にデシリアライズ
    Ok(config)
}

fn example_flow(config: &ConfigToml, cwd: &Path) -> anyhow::Result<()> {
    // プロファイルを取得（CLI からの override はここで渡す）
    let profile = config.get_config_profile(None)?;        // L708-726

    // サンドボックスポリシーを導出
    let policy = config.derive_sandbox_policy(
        None,                                              // sandbox_mode_override
        profile.sandbox_mode,                              // プロファイル側モード（仮のフィールド名）
        WindowsSandboxLevel::Disabled,                     // 環境情報
        cwd,
        None,                                              // 制約なし
    );

    // ここで policy を使ってコマンド実行環境を構築するなど
    println!("Derived sandbox policy: {:?}", policy);
    Ok(())
}
```

### 5.2 よくある使用パターン

1. **プロジェクト信頼レベルに応じたサンドボックスモードの自動決定**

```rust
use std::path::Path;
use crate::config_toml::ConfigToml;

fn check_trust_and_policy(config: &ConfigToml, cwd: &Path) {
    if let Some(project) = config.get_active_project(cwd) {        // L677-705
        println!("Trusted? {}", project.is_trusted());             // L430-432
    }

    // プロジェクト信頼レベルを考慮したデフォルトポリシー
    let policy = config.derive_sandbox_policy(
        None,
        None,
        codex_protocol::config_types::WindowsSandboxLevel::Disabled,
        cwd,
        None,
    );
    // policy を使用...
}
```

1. **ユーザ定義モデルプロバイダの検証**

```rust
use std::collections::HashMap;
use codex_model_provider_info::ModelProviderInfo;
use crate::config_toml::validate_model_providers;

fn validate_providers(map: &HashMap<String, ModelProviderInfo>) -> Result<(), String> {
    validate_model_providers(map)                                // L760-769
}
```

1. **OSS プロバイダ ID のチェック**

```rust
use crate::config_toml::validate_oss_provider;

fn set_oss_provider(id: &str) -> Result<(), std::io::Error> {
    validate_oss_provider(id)?;                                  // L783-797
    // 有効な id と確認できたので保存するなど
    Ok(())
}
```

### 5.3 よくある間違い

```rust
use crate::config_toml::{ConfigToml, validate_oss_provider};

// 間違い例: oss_provider を検証せずにそのまま使用してしまう
fn use_oss_provider_without_validation(config: &ConfigToml) {
    if let Some(ref id) = config.oss_provider {
        // `id` が無効な値でもそのまま使ってしまう可能性がある
        println!("Using OSS provider: {}", id);
    }
}

// 正しい例: validate_oss_provider で事前にチェックする
fn use_oss_provider_with_validation(config: &ConfigToml) -> std::io::Result<()> {
    if let Some(ref id) = config.oss_provider {
        validate_oss_provider(id)?;                           // InvalidInput の可能性あり
        println!("Using validated OSS provider: {}", id);
    }
    Ok(())
}
```

```rust
use crate::config_toml::ConfigToml;

// 間違い例: プロファイル名が存在しない可能性を考慮しない
fn get_profile_unchecked(config: &ConfigToml) {
    let _profile = config.get_config_profile(Some("nonexistent".to_string())).unwrap();
    // 存在しない場合、unwrap() によりパニックする
}

// 正しい例: Result をハンドリングする
fn get_profile_checked(config: &ConfigToml) {
    match config.get_config_profile(Some("nonexistent".into())) {
        Ok(profile) => println!("Got profile: {:?}", profile),
        Err(e) => eprintln!("Failed to get profile: {}", e),
    }
}
```

### 5.4 使用上の注意点（まとめ）

- **エラー処理**
  - `get_config_profile` や `validate_oss_provider`, `validate_model_providers` は `Result` を返すため、**呼び出し側での適切なエラーハンドリングが必須**です。
  - `validate_model_providers` は文字列ベースのエラーを返すため、ユーザ表示には適していますがエラー型に構造を持たせたい場合はラップが必要です。
- **サンドボックスとプラットフォーム依存**
  - Windows のサンドボックスレベルが無効な場合、`WorkspaceWrite` モードは自動的に `ReadOnly` に変わる可能性があります。  
    セキュリティ上の措置として、**書き込み権限が想定より制限されるケース**がある点に注意します。
- **設定スキーマの厳密さ**
  - `#[schemars(deny_unknown_fields)]` が付与された構造体は、未知のフィールドをエラーとして扱います。設定項目を追加／変更するときは、スキーマを更新しないとユーザの設定が読み込めなくなる可能性があります。
- **このチャンク内にテストコードは存在しません**  
  - 関数の挙動確認は、外部のテストモジュールまたは統合テストに依存していると考えられます（コード上の事実として、`#[cfg(test)]` などは現れません）。

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

例として、`ConfigToml` に新しい設定フィールドを追加し、それを `UserSavedConfig` にも反映させたい場合の流れを示します。

1. **`ConfigToml` にフィールドを追加**  
   - `pub struct ConfigToml` 内の適切な位置に `pub new_field: Option<NewType>,` を追加します（`L65-396` のいずれか）。
   - 必要に応じて `#[serde(default)]` や `#[schemars(...)]` を付与します。
2. **関連するサブ構造体の追加**  
   - 新しい設定が複雑であれば、同じファイル内に専用の構造体を定義するか、`crate::types` 側に型を定義して `use` します（`L7-28` の import 群を参照）。
3. **`UserSavedConfig` への反映**  
   - `impl From<ConfigToml> for UserSavedConfig` の構造体リテラルに、新フィールドを追記します（`L406-418`）。
4. **バリデーションが必要な場合**  
   - `validate_model_providers` のような専用バリデーション関数を追加し、必要であれば `deserialize_*` カスタムデシリアライザ経由で読み込み時に実行する形にします（`L772-781` のパターンを参考）。

### 6.2 既存の機能を変更する場合

- **影響範囲の確認**
  - 変更するフィールドや関数がどこから呼び出されているかを、IDE 等で参照検索して確認します。特に:
    - `derive_sandbox_policy`（`L599-675`）はサンドボックス挙動の中心であり、CLI・UI・サーバなど多くの呼び出し元が想定されます。
    - `validate_model_providers`（`L760-769`）・`validate_oss_provider`（`L783-797`）は設定ロードパスで使われている可能性が高いため、エラーメッセージや戻り値の意味を変えると下流の処理に影響します。
- **契約（前提条件・返り値の意味）の維持**
  - `get_config_profile` のように `NotFound` を返すことが前提になっているコードがあれば、その契約を維持するか、変更する場合は呼び出し側のロジックも更新する必要があります。
  - `validate_*` 系の関数が「設定ファイルが不正な場合にエラーを返す」という契約を持っている点を踏まえ、**例外的に黙って無視する挙動に変える場合は慎重な検討が必要**です。
- **テスト・検証**
  - このファイル内にテストはないため、変更後は外部のテストコードや手動テストで:
    - 正常な設定が問題なく読み込めること。
    - 不正な設定に対して適切なエラーが報告されること。
    - サンドボックスポリシーの変更が意図したとおりに反映されること。
    を確認する必要があります。

---

## 7. 関連ファイル

このモジュールと密接に関係する他ファイル・外部クレートです（コード中の `use` から読み取れる範囲のみ）。

| パス / クレート | 役割 / 関係 |
|-----------------|------------|
| `crate::permissions_toml` (`PermissionsToml`) | `ConfigToml.permissions` で使用される権限プロファイル定義。`config/src/config_toml.rs:L7` |
| `crate::profile_toml` (`ConfigProfile`) | プロファイル設定。`ConfigToml.profiles` と `get_config_profile` で使用されます（`L8`, `L221-223`, `L708-726`）。 |
| `crate::types::*` | `AnalyticsConfigToml`, `McpServerConfig`, `MemoriesToml`, `Notice`, `PluginConfig` など多くのサブ設定型を提供します（`L9-28`）。 |
| `codex_app_server_protocol::Tools` / `UserSavedConfig` | `ToolsToml` と `ConfigToml` からの `From` 実装の出力先となる実行時プロトコル用設定型です（`L29-30`, `L398-421`, `L574-580`）。 |
| `codex_features::FeaturesToml` | `ConfigToml.features` フィールド向けの新しい機能フラグ設定（`L31`, `L333-337`）。 |
| `codex_git_utils::resolve_root_git_project_for_trust` | プロジェクト信頼レベル解決で Git ルートを検索する関数。`get_active_project` から呼ばれます（`L32`, `L694`）。 |
| `codex_model_provider_info::*` | モデルプロバイダ ID や情報 (`ModelProviderInfo`) の型と、OSS プロバイダ検証のための定数を提供します（`L33-38`, `L59-63`, `L760-769`, `L783-797`）。 |
| `codex_protocol::config_types::*` | `SandboxMode`, `ServiceTier`, `TrustLevel`, `WebSearchMode` など、多数の設定列挙体を提供します（`L39-48`）。 |
| `codex_protocol::protocol::*` | `SandboxPolicy`, `ReadOnlyAccess`, `AskForApproval`, `RealtimeConversationVersion`, `RealtimeVoice` など実行時プロトコル型を提供します（`L50-52`, `L462-463`）。 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 設定内の絶対パス表現に使われる型。`ConfigToml` の多くのパスフィールドで使用されています（`L53`, `L142`, `L209-217` など）。 |
| `crate::schema::*` | `mcp_servers_schema` や `features_schema` を通じて JSON Schema のカスタム定義を提供します（`L170`, `L336`）。 |

このファイルは、これらの型・関数をまとめて **設定スキーマと実行時設定の橋渡し**を行う役割を持つモジュールとして位置づけられます。
