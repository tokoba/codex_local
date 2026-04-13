# network-proxy/src/config.rs

## 0. ざっくり一言

- ネットワークプロキシの設定を表現し、JSON などからの読み書きと、「設定値 → 実際にバインドする `SocketAddr`」への解決処理を提供するモジュールです。
- ドメイン/UNIX ソケットの許可リスト、HTTP メソッド制限、ループバック強制などの安全性ポリシーもここで定義されています。

---

## 1. このモジュールの役割

### 1.1 概要

- このモジュールは **ローカル HTTP/SOCKS プロキシの設定を安全に扱う** ために存在し、次の機能を提供します。
  - Serde 経由でシリアライズ/デシリアライズされる設定構造体群（`NetworkProxyConfig` / `NetworkProxySettings` など）の定義 (config.rs:L16-20, L119-142)。
  - ドメインごとの Allow/Deny 設定と、その優先度（Deny が勝つ）を計算するロジック (config.rs:L22-41, L72-101)。
  - UNIX ソケットパスのバリデーション（絶対パスのみ許可） (config.rs:L368-397, L400-405)。
  - 設定から実際にバインドする HTTP/SOCKS アドレスを導出し、ループバック強制などの安全策を適用する `resolve_runtime` (config.rs:L408-421)。

### 1.2 アーキテクチャ内での位置づけ

このファイル内の依存関係（他ファイルとの関係はこのチャンクには現れません）を簡略化すると次のようになります。

```mermaid
graph TD
    Cfg["NetworkProxyConfig (L16-20)"]
    Settings["NetworkProxySettings (L119-142)"]
    Runtime["resolve_runtime (L408-421)"]
    ValidateUS["validate_unix_socket_allowlist_paths (L400-405)"]
    VUS["ValidatedUnixSocketPath::parse (L383-397)"]
    Addr["resolve_addr (L423-433)"]
    PHP["parse_host_port (L466-501)"]
    PHPF["parse_host_port_fallback (L503-552)"]
    Clamp["clamp_bind_addrs (L322-361)"]
    CNon["clamp_non_loopback (L299-320)"]

    Cfg -->|field network| Settings
    Cfg --> Runtime
    Runtime --> ValidateUS
    ValidateUS --> Settings
    ValidateUS --> VUS
    Runtime --> Addr
    Addr --> PHP
    PHP --> PHPF
    Runtime --> Clamp
    Clamp --> CNon
```

- `NetworkProxyConfig` はアプリ全体の設定の一部としてロードされることが想定され、その `network` フィールドが `NetworkProxySettings` です (config.rs:L16-20, L119-142)。
- `resolve_runtime` がこのモジュールのエントリポイントとなり、設定から `RuntimeConfig`（HTTP/SOCKS のバインドアドレス）を計算します (config.rs:L408-421)。
- 途中で UNIX ソケットホワイトリストのバリデーション、URL/ホスト名のパース、非ループバックアドレスのクランプなどを行います。

### 1.3 設計上のポイント

- **設定のデフォルト値を構造体側で保持**  
  - `NetworkProxySettings` は `#[serde(default)]` と `Default` 実装の両方を持ち、欠損フィールドは構造体のデフォルト値で補われます (config.rs:L117-142, L144-161, L595-611)。
- **ドメイン許可/拒否の優先度は列挙体の順序で表現**  
  - `NetworkDomainPermission` の順序 `None < Allow < Deny` を `PartialOrd/Ord` で利用し、重複パターンでは Deny が勝つように `effective_entries` が実装されています (config.rs:L22-30, L72-101)。
- **UNIX ソケットの安全性**  
  - 許可リストは絶対パス（OS ネイティブ or Unix 風）だけを受け付け、相対パスはエラーにします (config.rs:L383-397, L400-405, L839-867)。
- **バインドアドレスの安全性**  
  - 明示的に危険フラグを立てない限り非ループバックへのバインドを禁止し、UNIX ソケットプロキシが有効な場合は常にループバックにクランプします (config.rs:L299-320, L322-361, L793-837)。
- **エラーハンドリング**  
  - すべての失敗可能な処理は `anyhow::Result` を介してエラーを返し、文脈情報を `with_context` で付加しています (config.rs:L383-389, L400-405, L408-415, L466-470, L491-493)。
- **並行性**  
  - `unsafe` は一切使われておらず、設定オブジェクトの変更メソッドは `&mut self` を受けるだけの純粋な同期コードです。共有可変状態やスレッド操作はこのファイル内にはありません。

---

## 2. 主要な機能一覧

- プロキシ設定構造体の定義とデフォルト値の管理（`NetworkProxyConfig`, `NetworkProxySettings`）(config.rs:L16-20, L119-142, L144-161)
- ドメイン許可/拒否ルールの管理と序列付きマージ（`NetworkDomainPermissions::effective_entries`）(config.rs:L38-41, L72-101)
- UNIX ソケット許可リストの管理とシリアライズ（`NetworkUnixSocketPermissions` と関連メソッド）(config.rs:L111-115, L187-201, L229-266)
- 利用モードごとの HTTP メソッド制限（`NetworkMode::allows_method`）(config.rs:L269-280, L282-288)
- プロキシの HTTP/SOCKS バインドアドレスの解決と安全なクランプ（`resolve_runtime`, `resolve_addr`, `clamp_bind_addrs`）(config.rs:L408-421, L423-433, L322-361)
- ホスト/ポート文字列のパースと整形（`parse_host_port`, `parse_host_port_fallback`, `host_and_port_from_network_addr`）(config.rs:L466-552, L436-457)
- UNIX ソケットパスの妥当性検証（`ValidatedUnixSocketPath::parse`, `validate_unix_socket_allowlist_paths`）(config.rs:L383-397, L400-405)

---

## 3. 公開 API と詳細解説

### 3.1 型一覧（構造体・列挙体など）

#### 設定/ランタイム関連

| 名前 | 種別 | 可視性 | 行範囲 | 役割 / 用途 |
|------|------|--------|--------|-------------|
| `NetworkProxyConfig` | 構造体 | `pub` | config.rs:L16-20 | アプリ全体の設定のうち「network」セクションを保持するラッパー。 |
| `NetworkProxySettings` | 構造体 | `pub` | config.rs:L119-142 | プロキシの詳細設定（URL、モード、ドメイン/UNIX ソケット許可リストなど）を保持。Serde デフォルト対応。 |
| `RuntimeConfig` | 構造体 | `pub` | config.rs:L363-366 | 実行時にプロキシがバインドすべき HTTP/SOCKS の `SocketAddr` を保持。`resolve_runtime` の戻り値。 |
| `NetworkMode` | 列挙体 | `pub` | config.rs:L271-280 | ネットワークアクセスモード（`Limited`/`Full`）。`allows_method` で HTTP メソッド制御を提供。 |

#### ドメイン/UNIX ソケット許可関連

| 名前 | 種別 | 可視性 | 行範囲 | 役割 / 用途 |
|------|------|--------|--------|-------------|
| `NetworkDomainPermission` | 列挙体 | `pub` | config.rs:L26-30 | ドメインのアクセス許可状態（`None`/`Allow`/`Deny`）。順序付けにより Deny 優先を実現。 |
| `NetworkDomainPermissionEntry` | 構造体 | `pub` | config.rs:L33-36 | パターン文字列と許可種別を 1 件分保持するエントリ。 |
| `NetworkDomainPermissions` | 構造体 | `pub` | config.rs:L38-41 | ドメイン許可/拒否ルールの集合。独自の Serialize/Deserialize 実装でマップ風 JSON として表現。 |
| `NetworkUnixSocketPermission` | 列挙体 | `pub` | config.rs:L106-109 | UNIX ソケットパスの許可状態（`Allow`/`None`）。 |
| `NetworkUnixSocketPermissions` | 構造体 | `pub` | config.rs:L111-115 | UNIX ソケットパス → Permission のマップ。`#[serde(flatten)]` で素のマップとしてシリアライズ。 |

#### 内部ユーティリティ型

| 名前 | 種別 | 可視性 | 行範囲 | 役割 / 用途 |
|------|------|--------|--------|-------------|
| `UnixStyleAbsolutePath` | 構造体 | `pub(crate)` | config.rs:L368-375 | `/path/to.sock` のような Unix 風絶対パスをラップする内部表現。OS ネイティブ絶対パスとは区別。 |
| `ValidatedUnixSocketPath` | 列挙体 | `pub(crate)` | config.rs:L377-381 | 正規化済み UNIX ソケットパスのバリアント（ネイティブ / Unix 風）。バリデーション結果として利用。 |
| `SocketAddressParts` | 構造体 | `private` | config.rs:L460-464 | ホスト名とポート番号を一時的に保持するための内部構造体。`parse_host_port` で使用。 |

### 3.2 重要な関数の詳細

ここでは特に重要な 7 個の関数/メソッドについて詳しく説明します。

---

#### `resolve_runtime(cfg: &NetworkProxyConfig) -> Result<RuntimeConfig>`  

（config.rs:L408-421）

**概要**

- `NetworkProxyConfig` から実行時用の `RuntimeConfig`（HTTP/SOCKS のバインドアドレス）を生成します。
- UNIX ソケット許可リストの妥当性チェック、URL/ホストのパース、ループバッククランプなど、安全性ポリシーを一括して適用します。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `cfg` | `&NetworkProxyConfig` | 事前にロード済みの設定。`cfg.network` に `NetworkProxySettings` が入っている。 |

**戻り値**

- `Ok(RuntimeConfig)`  
  - `http_addr`: HTTP プロキシがバインドするアドレス (config.rs:L363-366)。  
  - `socks_addr`: SOCKS5 プロキシがバインドするアドレス。
- `Err(anyhow::Error)`  
  - UNIX ソケットパスが不正な場合、あるいは `proxy_url`/`socks_url` の形式が不正な場合にエラー。

**内部処理の流れ**

1. `validate_unix_socket_allowlist_paths(cfg)?` で `network.allow_unix_sockets()` の各エントリを `ValidatedUnixSocketPath::parse` で検証 (config.rs:L400-405)。
2. `resolve_addr(&cfg.network.proxy_url, 3128)` で HTTP 用アドレスをパースし、文脈 `"invalid network.proxy_url: ..."` を付加 (config.rs:L411-412)。
3. 同様に、`resolve_addr(&cfg.network.socks_url, 8081)` で SOCKS 用アドレスをパース (config.rs:L413-414)。
4. `clamp_bind_addrs(http_addr, socks_addr, &cfg.network)` でループバック強制などのクランプを適用 (config.rs:L415, L322-361)。
5. `RuntimeConfig { http_addr, socks_addr }` を返す (config.rs:L417-420)。

```mermaid
sequenceDiagram
    participant Caller
    participant Cfg as NetworkProxyConfig
    participant RT as resolve_runtime (L408-421)
    participant VUS as validate_unix_socket_allowlist_paths (L400-405)
    participant Addr as resolve_addr (L423-433)
    participant HP as parse_host_port (L466-501)
    participant Clamp as clamp_bind_addrs (L322-361)

    Caller->>RT: &cfg
    RT->>VUS: validate_unix_socket_allowlist_paths(cfg)
    VUS-->>RT: Result<()>
    RT->>Addr: resolve_addr(proxy_url, 3128)
    Addr->>HP: parse_host_port(...)
    HP-->>Addr: SocketAddressParts
    Addr-->>RT: SocketAddr
    RT->>Addr: resolve_addr(socks_url, 8081)
    Addr-->>RT: SocketAddr
    RT->>Clamp: clamp_bind_addrs(http_addr, socks_addr, &cfg.network)
    Clamp-->>RT: (http_addr, socks_addr)
    RT-->>Caller: Result<RuntimeConfig>
```

**Examples（使用例）**

```rust
use network_proxy::config::{NetworkProxyConfig, NetworkProxySettings, resolve_runtime};

fn main() -> anyhow::Result<()> {
    // 1. デフォルト設定をベースに一部だけ上書きする                         // NetworkProxySettings のデフォルトを取得
    let mut settings = NetworkProxySettings::default();                        // enabled=false, ローカルのみ (L144-161)
    settings.enabled = true;                                                   // プロキシを有効化
    settings.proxy_url = "0.0.0.0:3128".to_string();                           // 全インターフェイスで HTTP を受けたい
    settings.socks_url = "127.0.0.1:8081".to_string();                         // SOCKS はループバック

    // 危険フラグを ON にしない限り 0.0.0.0 は後でループバックにクランプされる // clamp_non_loopback の動作 (L299-320)

    let cfg = NetworkProxyConfig { network: settings };                        // NetworkProxyConfig にラップ (L16-20)

    // 2. ランタイム設定に解決する
    let runtime = resolve_runtime(&cfg)?;                                      // HTTP/SOCKS の SocketAddr を解決 (L408-421)

    // 3. 実際のサーバコードで runtime.http_addr / runtime.socks_addr を使用 // ここでは println! で表示のみ
    println!("HTTP bind: {}", runtime.http_addr);
    println!("SOCKS bind: {}", runtime.socks_addr);

    Ok(())
}
```

**Errors / Panics**

- エラーになる条件:
  - `cfg.network.allow_unix_sockets()` に相対パスが含まれる場合（`ValidatedUnixSocketPath::parse` が `bail!`）  
    → エラーメッセージに `network.allow_unix_sockets[index]` が含まれる (config.rs:L383-397, L400-405, L839-856)。
  - `proxy_url` / `socks_url` が空文字やホスト欠落など、`parse_host_port` でエラーになる場合 (config.rs:L466-470, L545-547)。
- この関数内では `panic!` を発生させていません。テストコード内にのみ `panic!` が存在します (config.rs:L845-849)。

**Edge cases（エッジケース）**

- `allow_unix_sockets` が空 / 未設定の場合:
  - `validate_unix_socket_allowlist_paths` は何も検証せず成功します (config.rs:L400-405)。
- `proxy_url` / `socks_url` がホスト名（例: `"http://example.com:5555"`）の場合:
  - `resolve_addr` 内で IP パースに失敗し、`127.0.0.1:<port>` にフォールバックします (config.rs:L423-433, L785-789)。
- バインドアドレスに非ループバックを指定しても、`dangerously_allow_non_loopback_proxy` が `false` なら 127.0.0.1 にクランプされます (config.rs:L299-320, L322-341)。

**使用上の注意点**

- この関数の成功は「バインドアドレスが妥当である」ことを保証しますが、実際にソケットをバインドできるかどうか（ポートの占有状況など）はこのモジュールでは検証していません。
- ホスト名を指定しても DNS 解決は行われません。ホストとして使えるのは実質 IP リテラルのみで、ホスト名を指定するとループバックにフォールバックします (config.rs:L423-433, L785-789)。
- `dangerously_allow_non_loopback_proxy` フラグを `true` にすると本来危険な 0.0.0.0 バインドが許可されますが、UNIX ソケットプロキシが有効な場合は強制的にループバックへクランプされます (config.rs:L322-361, L808-837)。

---

#### `NetworkProxySettings::allow_unix_sockets(&self) -> Vec<String>`  

（config.rs:L187-201）

**概要**

- 設定された UNIX ソケット許可リストから、許可 (`Allow`) されたパスの一覧を `Vec<String>` として返します。
- 許可されていない、あるいは設定自体が `None` の場合は空ベクタを返します。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `&self` | `&NetworkProxySettings` | 現在のプロキシ設定。 |

**戻り値**

- `Vec<String>`  
  - `NetworkUnixSocketPermissions.entries` のうち値が `NetworkUnixSocketPermission::Allow` のキー（パス文字列）のリスト。  
  - 設定が存在しない場合は空ベクタ。

**内部処理の流れ**

1. `self.unix_sockets.as_ref()` で `Option<NetworkUnixSocketPermissions>` を取り出す (config.rs:L187-190)。
2. 存在する場合はマップ `entries` をイテレートし、`permission == Allow` のキーのみを収集 (config.rs:L191-198)。
3. ない場合、または `Allow` が 1 件もない場合は `unwrap_or_default()` により空ベクタを返す (config.rs:L199-200)。

**Examples（使用例）**

```rust
use network_proxy::config::NetworkProxySettings;

fn unix_allowlist_example() {
    let mut settings = NetworkProxySettings::default();            // デフォルトは unix_sockets=None (L144-161)
    assert!(settings.allow_unix_sockets().is_empty());             // まだ何も許可されていない (L187-201)

    settings.set_allow_unix_sockets(vec![
        "/var/run/docker.sock".to_string(),
        "/tmp/example.sock".to_string(),
    ]);                                                            // Allow で上書き (L229-231)

    let allowed = settings.allow_unix_sockets();                   // 許可されたパスの一覧を取得
    assert_eq!(allowed.len(), 2);
}
```

**Errors / Panics**

- このメソッド自体はエラーも panic も返しません。
- ただし、`resolve_runtime` 経由で使われるときには、返されたパスが `ValidatedUnixSocketPath::parse` によって検証され、不正なパスはエラーになります (config.rs:L400-405)。

**Edge cases（エッジケース）**

- `unix_sockets` が `None` の場合: 空ベクタ。
- 許可以外の値（`None`）しか存在しない場合: 空ベクタ。
- パス文字列の重複: 内部は `BTreeMap<String, NetworkUnixSocketPermission>` なのでキーの重複はありません (config.rs:L111-115, L259-264)。

**使用上の注意点**

- ここで返されるのはあくまで設定文字列であり、OS 上のパスの存在確認や形式検証は行われません。形式検証は `resolve_runtime` 経由で `ValidatedUnixSocketPath::parse` に委ねられます。
- 相対パスを設定すると `resolve_runtime` でエラーになるため、常に絶対パス（OS ネイティブまたは `/...` 形式）を指定する必要があります (config.rs:L383-397, L839-856)。

---

#### `NetworkProxySettings::set_allowed_domains(&mut self, allowed_domains: Vec<String>)`  

（config.rs:L203-205）

**概要**

- 許可ドメインの一覧を設定します。
- 同じドメインに対する既存の Allow エントリを置き換えますが、Deny エントリは保持され、優先度的に Deny が勝つようになっています。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `&mut self` | `&mut NetworkProxySettings` | 設定を書き換える対象。 |
| `allowed_domains` | `Vec<String>` | 許可したいドメインパターン一覧。 |

**戻り値**

- なし（`()`）。

**内部処理の流れ**

1. 内部ヘルパー `set_domain_entries(allowed_domains, NetworkDomainPermission::Allow)` を呼ぶだけのラッパー (config.rs:L203-205, L233-251)。
2. `set_domain_entries` 側で以下を実施:
   - 既存エントリから `permission == Allow` のものを削除 (config.rs:L233-237)。
   - 新たな `allowed_domains` の各文字列について、同じ `(pattern, Allow)` がまだ存在しない場合にだけ追加 (config.rs:L238-248)。
   - エントリが空の場合は `domains` を `None` に戻し、非空なら `Some(domains)` に (config.rs:L250-251)。

**Examples（使用例）**

```rust
use network_proxy::config::{NetworkProxySettings, NetworkDomainPermission};

fn domain_allow_deny_example() {
    let mut settings = NetworkProxySettings::default();

    // まず example.com を Deny として登録                                  // Deny エントリを追加 (L207-209)
    settings.set_denied_domains(vec!["example.com".to_string()]);

    // その後 Allow を設定しても、Deny が優先される                          // テストで確認済み (L613-625)
    settings.set_allowed_domains(vec!["example.com".to_string()]);

    // allowed_domains は None (Allow 有効パターンなし)                      // effective_entries が Deny を採用 (L72-101, L165-167)
    assert_eq!(settings.allowed_domains(), None);

    // denied_domains には example.com が含まれる
    assert_eq!(
        settings.denied_domains(),
        Some(vec!["example.com".to_string()])
    );
}
```

**Errors / Panics**

- このメソッド単体では `Result` を返さず、エラーや panic を発生させません。

**Edge cases（エッジケース）**

- `allowed_domains` が空ベクタの場合:
  - 既存の Allow エントリはすべて削除され、Deny エントリだけが残ります。
  - その結果、`domains.entries` が空なら `domains` フィールドは `None` になります (config.rs:L233-251)。
- 同じドメインを複数回含むベクタ:
  - 内部で重複チェックを行っているため、同じ `(pattern, Allow)` のエントリは一度だけ追加されます (config.rs:L238-248)。

**使用上の注意点**

- Allow と Deny の両方に同じパターンを登録すると、`NetworkDomainPermission` の順序 (`Deny` が `Allow` より大きい) により常に Deny が優先されます (config.rs:L22-30, L72-101)。
- `set_allowed_domains` は既存の Allow を「上書き」する操作であり、増分追加ではありません。増分的に操作したい場合は `upsert_domain_permission` の利用が適しています (config.rs:L211-227)。

---

#### `NetworkProxySettings::upsert_domain_permission(&mut self, host: String, permission: NetworkDomainPermission, normalize: impl Fn(&str) -> String)`  

（config.rs:L211-227）

**概要**

- ドメインパターンと許可種別を 1 件追加/更新します。
- 正規化関数 `normalize` を通じて比較し、同じ正規化結果を持つ既存エントリをすべて削除してから新しいエントリを追加します。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `&mut self` | `&mut NetworkProxySettings` | ドメイン設定を書き換える対象。 |
| `host` | `String` | 追加/更新したいドメインパターン。 |
| `permission` | `NetworkDomainPermission` | 許可/拒否種別。 |
| `normalize` | `impl Fn(&str) -> String` | パターンを比較するための正規化関数（例: 小文字化など）。 |

**戻り値**

- なし（`()`）。

**内部処理の流れ**

1. 既存の `self.domains` を取り出し（`take()`）、`None` の場合はデフォルト値（空の `NetworkDomainPermissions`）を生成 (config.rs:L217)。
2. `host` を `normalize` して `normalized_host` を得る (config.rs:L218)。
3. 既存のエントリのうち、`normalize(&entry.pattern) == normalized_host` であるものを `retain` で削除 (config.rs:L219-221)。
4. 新たな `NetworkDomainPermissionEntry { pattern: host, permission }` を `domains.entries` に push (config.rs:L222-225)。
5. エントリが非空であれば `self.domains = Some(domains)`、空なら `None` に戻す (config.rs:L226)。

**Examples（使用例）**

```rust
use network_proxy::config::{NetworkProxySettings, NetworkDomainPermission};

fn upsert_example() {
    let mut settings = NetworkProxySettings::default();

    // ケースインセンシティブに扱いたい正規化関数                           // ここでは小文字化のみ (例)
    let normalize = |s: &str| s.to_ascii_lowercase();

    // "Example.com" を Allow で登録
    settings.upsert_domain_permission(
        "Example.com".to_string(),
        NetworkDomainPermission::Allow,
        normalize,
    );

    // "example.COM" を Deny で登録すると、同一とみなされて上書きされる
    settings.upsert_domain_permission(
        "example.COM".to_string(),
        NetworkDomainPermission::Deny,
        normalize,
    );

    // effective_entries では Deny のみが残る                             // 実際の確認は allowed/denied_domains 経由
    assert_eq!(settings.allowed_domains(), None);
    assert_eq!(settings.denied_domains(), Some(vec!["example.COM".to_string()]));
}
```

**Errors / Panics**

- このメソッド自体ではエラーや panic は発生しません。
- ただし、`normalize` に副作用や panic が含まれる場合、その影響は呼び出し側責務です（このモジュールでは `normalize` の中身を制約していません）。

**Edge cases（エッジケース）**

- `self.domains` が `None` の状態で呼び出した場合:
  - 内部でデフォルト値（空エントリ）を生成し、その上に 1 件追加します (config.rs:L217-225)。
- `normalize` が異なる呼び出しごとに異なる結果を返す場合:
  - `retain` での削除基準と後続ロジックの整合性が崩れる可能性がありますが、このモジュール側ではチェックしていません。

**使用上の注意点**

- 一貫した正規化ルール（例: 小文字化＋末尾ドット削除など）を使うことが前提になっています。そうしないと、同じドメインを重複して登録してしまう可能性があります。
- `allowed_domains` / `denied_domains` は `effective_entries` を通じて計算されるため、同じパターンに対する複数のエントリが存在しても最終的な Permission は 1 つに集約されます (config.rs:L72-101, L165-171)。

---

#### `ValidatedUnixSocketPath::parse(socket_path: &str) -> Result<ValidatedUnixSocketPath>`  

（config.rs:L383-397）

**概要**

- `network.allow_unix_sockets` の各エントリ文字列を検査し、「妥当な絶対 UNIX ソケットパス」かどうかを検証します。
- OS ネイティブな絶対パス（`Path::is_absolute()` が `true`）と、`/path/to.sock` のような Unix 風絶対パスの両方を許可します。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `socket_path` | `&str` | 設定に記述された UNIX ソケットパス文字列。 |

**戻り値**

- `Ok(ValidatedUnixSocketPath::Native(path))`  
  - OS ネイティブな絶対パスと判定できた場合。正規化済み `AbsolutePathBuf` を保持 (config.rs:L387-389)。
- `Ok(ValidatedUnixSocketPath::UnixStyleAbsolute(path))`  
  - `UnixStyleAbsolutePath::parse` によって `/...` 形式の Unix 風絶対パスと判定された場合 (config.rs:L392-394)。
- `Err(anyhow::Error)`  
  - いずれにも当てはまらない場合（相対パスなど）に `bail!` でエラーを返します (config.rs:L396)。

**内部処理の流れ**

1. `Path::new(socket_path)` で OS ネイティブのパス型に変換し、`is_absolute()` をチェック (config.rs:L385-386)。
2. 絶対パスなら `AbsolutePathBuf::from_absolute_path(path)` で正規化しつつ `Native` バリアントとして返却 (config.rs:L387-389)。
3. そうでない場合、`UnixStyleAbsolutePath::parse(socket_path)` を呼び、先頭が `/` なら `UnixStyleAbsolute` として受理 (config.rs:L392-394, L371-374)。
4. どちらにも当てはまらなければ `bail!("expected an absolute path, got {socket_path:?}")` でエラー (config.rs:L396)。

**Examples（使用例）**

```rust
use network_proxy::config::ValidatedUnixSocketPath;

fn validate_unix_paths() -> anyhow::Result<()> {
    // ネイティブな絶対パス (Unix の例)
    let native = ValidatedUnixSocketPath::parse("/var/run/docker.sock")?;   // Native バリアント (L385-389)

    // Unix 風絶対パス (Windows 上でのリモート Linux パスなど)
    let unix_style = ValidatedUnixSocketPath::parse("/private/tmp/example.sock")?; // UnixStyleAbsolute (L392-394)

    // 相対パスはエラー
    assert!(ValidatedUnixSocketPath::parse("relative.sock").is_err());      // テストで確認済み (L839-856)

    Ok(())
}
```

**Errors / Panics**

- エラー条件:
  - `Path::is_absolute()` が `false` かつ `UnixStyleAbsolutePath::parse` でも `None` の場合 (config.rs:L371-374, L383-397)。
  - `AbsolutePathBuf::from_absolute_path` が内部正規化に失敗した場合（詳細は外部クレートですが、ここでは `with_context` でメッセージが付加されます）(config.rs:L387-389)。
- panic は使用していません。

**Edge cases（エッジケース）**

- Windows 上での `/tmp/...` のようなパス:
  - OS ネイティブでは絶対パスと扱われない可能性がありますが、`UnixStyleAbsolutePath::parse` により Unix 風絶対パスとして受理されます (config.rs:L371-374, L392-394)。
- 空文字列 `""`:
  - `Path::new("")` の `is_absolute()` は `false` となり、かつ `starts_with('/')` でもないためエラー (`bail!`) になります。

**使用上の注意点**

- この型は外部 API には公開されておらず、あくまで設定の妥当性検証のための内部表現です (`pub(crate)`、config.rs:L377-381)。
- 実行時コード側で、Unix 風とネイティブ絶対パスをどう扱い分けるかは別モジュールに委ねられており、このチャンクからは分かりません。

---

#### `clamp_bind_addrs(http_addr: SocketAddr, socks_addr: SocketAddr, cfg: &NetworkProxySettings) -> (SocketAddr, SocketAddr)`  

（config.rs:L322-361）

**概要**

- 設定に基づき、HTTP/SOCKS プロキシのバインドアドレスを安全な値にクランプします。
- 非ループバックバインドの禁止/許可、および UNIX ソケットプロキシ有効時の強制ループバック化を行います。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `http_addr` | `SocketAddr` | ユーザー設定から解決された HTTP バインドアドレス候補。 |
| `socks_addr` | `SocketAddr` | 同様に SOCKS バインドアドレス候補。 |
| `cfg` | `&NetworkProxySettings` | `dangerously_allow_non_loopback_proxy` や `allow_unix_sockets` などのフラグを参照。 |

**戻り値**

- `(SocketAddr, SocketAddr)`  
  - クランプ済みの HTTP/SOCKS アドレス。

**内部処理の流れ**

1. まず `clamp_non_loopback` を使って、`dangerously_allow_non_loopback_proxy` に従った初期クランプを行う (config.rs:L327-338, L299-320)。
   - フラグが `false` なら非ループバックアドレスは 127.0.0.1:port にクランプ。
   - フラグが `true` なら非ループバックアドレスを許容しつつ警告ログを出す。
2. `cfg.allow_unix_sockets()` が空で、かつ `dangerously_allow_all_unix_sockets` が `false` ならここで終了し、上記結果を返す (config.rs:L339-341)。
3. それ以外（UNIX ソケットプロキシが有効）では:
   - 非ループバックかつ `dangerously_allow_non_loopback_proxy` が `true` であれば、「無視してループバックにクランプする」という警告ログを出す (config.rs:L347-355)。
   - 実際の返り値は常に `127.0.0.1:<port>` 形式で返す (config.rs:L357-360)。

**Examples（使用例）**

```rust
use network_proxy::config::{NetworkProxySettings, clamp_bind_addrs};
use std::net::SocketAddr;

fn clamp_example() {
    let http_addr: SocketAddr = "0.0.0.0:3128".parse().unwrap();
    let socks_addr: SocketAddr = "0.0.0.0:8081".parse().unwrap();

    // 安全デフォルト: 非ループバックは禁止                                  // dangerously_allow_non_loopback_proxy=false がデフォルト (L144-161)
    let cfg = NetworkProxySettings::default();
    let (http, socks) = clamp_bind_addrs(http_addr, socks_addr, &cfg);
    assert_eq!(http.to_string(), "127.0.0.1:3128");
    assert_eq!(socks.to_string(), "127.0.0.1:8081");

    // 危険フラグをオンにした場合
    let cfg2 = NetworkProxySettings {
        dangerously_allow_non_loopback_proxy: true,
        ..Default::default()
    };
    let (http2, socks2) = clamp_bind_addrs(http_addr, socks_addr, &cfg2);     // テストで確認 (L793-805)
    assert_eq!(http2.to_string(), "0.0.0.0:3128");
    assert_eq!(socks2.to_string(), "0.0.0.0:8081");
}
```

**Errors / Panics**

- この関数は `Result` を返さず、エラーや panic は発生しません。
- 代わりに危険な設定時には `tracing::warn!` で警告ログを出力します (config.rs:L311-312, L315-319, L348-355)。

**Edge cases（エッジケース）**

- UNIX ソケットプロキシが有効な場合（`allow_unix_sockets` が非空、または `dangerously_allow_all_unix_sockets == true`）:
  - `dangerously_allow_non_loopback_proxy` が `true` でも、最終的なバインドアドレスは必ずループバックになります (config.rs:L339-361, L808-837)。
- 既にループバックアドレスを渡した場合:
  - `clamp_non_loopback` 内の早期リターンにより、そのまま返されます (config.rs:L306-307)。

**使用上の注意点**

- 実際に外部からアクセス可能なプロキシを立てたい場合、`dangerously_allow_non_loopback_proxy` を `true` にし、かつ `allow_unix_sockets` を空のままにする必要があります。
- `dangerously_allow_all_unix_sockets` を `true` にすると、UNIX ソケットプロキシが常に有効扱いとなり、バインドアドレスがループバックに強制される点に注意が必要です (config.rs:L339-361, L824-837)。

---

#### `parse_host_port(url: &str, default_port: u16) -> Result<SocketAddressParts>`  

（config.rs:L466-501）

**概要**

- 入力文字列から「ホスト名」と「ポート番号」を抽出します。
- URL 形式 / `host:port` 形式 / IPv4/IPv6 リテラルなど、さまざまなパターンに柔軟に対応します。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `url` | `&str` | 入力文字列（URL 風、`host:port` など）。 |
| `default_port` | `u16` | ポート指定がない場合や無効な場合に使うデフォルトポート。 |

**戻り値**

- `Ok(SocketAddressParts { host, port })`  
  - 抽出されたホスト文字列とポート番号。
- `Err(anyhow::Error)`  
  - ホストが欠落している場合など、パース不能な場合。

**内部処理の流れ**

1. `trim()` で前後の空白を除去し、空ならエラー (`missing host...`) (config.rs:L466-470)。
2. 「スキームと誤認されたくない IPv6 リテラル」（例: `"2001:db8::1"`）を検出し、その場合はホストとしてそのまま採用し、ポートはデフォルト (config.rs:L472-478)。
3. それ以外は:
   - `://` を含んでいなければ `http://` をプレフィックスして URL として解釈しやすくする (config.rs:L480-486)。
   - `Url::parse` が成功し、`host_str()` が取れればそれを利用（`[]` をトリムして IPv6 リテラルを抽出） (config.rs:L487-497)。
4. ここまでで成功しなければ `parse_host_port_fallback(trimmed, default_port)` にフォールバック (config.rs:L499-501)。

**Examples（使用例）**

```rust
use network_proxy::config::parse_host_port;

fn parse_examples() -> anyhow::Result<()> {
    // host:port 形式
    let parts = parse_host_port("127.0.0.1:8080", 3128)?;             // テストで確認 (L671-678)
    assert_eq!(parts.host, "127.0.0.1");
    assert_eq!(parts.port, 8080);

    // URL + パス
    let parts = parse_host_port("http://example.com:8080/some/path", 3128)?; // (L681-693)
    assert_eq!(parts.host, "example.com");
    assert_eq!(parts.port, 8080);

    // IPv6 (ブラケット付き)
    let parts = parse_host_port("http://[::1]:9999", 3128)?;          // (L711-719)
    assert_eq!(parts.host, "::1");
    assert_eq!(parts.port, 9999);

    // IPv6 リテラル (ブラケットなし)
    let parts = parse_host_port("2001:db8::1", 3128)?;                // (L723-730)
    assert_eq!(parts.host, "2001:db8::1");
    assert_eq!(parts.port, 3128);

    Ok(())
}
```

**Errors / Panics**

- エラー条件:
  - トリム後に空文字列 (`""` や `"   "`) の場合 (config.rs:L466-470, L660-668)。
  - ホスト部分が空の `":8080"` や `"http://:8080"` など。fallback 内で `missing host...` エラー (config.rs:L536-537, L545-547)。
- panic は使用していません。

**Edge cases（エッジケース）**

- `example.com:notaport` のような無効なポート:
  - `u16` としてパースできなければ `default_port` にフォールバックします (config.rs:L539-542, L733-741)。
- ユーザー情報を含む URL（`http://user:pass@host.example:5555`）:
  - `host.example` と `5555` を正しく抽出し、ユーザー情報は無視します (config.rs:L503-512, L697-708)。
- スキーム付きだが `Url::parse` に失敗する形式:
  - `parse_host_port_fallback` がスキームを削除したうえで手動解析します (config.rs:L503-508)。

**使用上の注意点**

- この関数はあくまで「文字列からホストとポートを切り出す」だけであり、ホスト名の DNS 解決は行いません。
- IPv6 リテラルでは、`"[::1]:8080"` のように角カッコ付きで書くのが推奨です。角カッコなしもサポートされていますが、`host:port` と誤認されないよう特別扱いされています (config.rs:L472-478)。

---

#### `host_and_port_from_network_addr(value: &str, default_port: u16) -> String`  

（config.rs:L436-450）

**概要**

- ネットワークアドレス設定（`network.proxy_url` など）から、「ユーザー向け表示用の `host:port` 文字列」を生成します。
- パースに成功すれば `example.com:8080` または `[::1]:8080` のような正規化された形式を返し、失敗時はベストエフォートで整形します。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `value` | `&str` | 入力文字列（URL 風、`host:port` など）。 |
| `default_port` | `u16` | ポート指定がない場合のデフォルトポート。 |

**戻り値**

- `String`  
  - 空/未設定の場合は `"<missing>"`。
  - それ以外は `[host]:port` または `host:port` 形式。

**内部処理の流れ**

1. `trim()` で前後の空白を除去し、空なら `"<missing>"` を返す (config.rs:L436-440, L744-749)。
2. `parse_host_port` を試し、成功すれば `format_host_and_port(&parts.host, parts.port)` で整形 (config.rs:L442-449, L452-457)。
3. `parse_host_port` が失敗した場合は、生の `trimmed` をホストとして `format_host_and_port(trimmed, default_port)` を返す (config.rs:L444-446)。

**Examples（使用例）**

```rust
use network_proxy::config::host_and_port_from_network_addr;

fn display_addr_example() {
    assert_eq!(
        host_and_port_from_network_addr("", 1234),
        "<missing>"                                                // 空入力 (L436-440, L744-749)
    );

    assert_eq!(
        host_and_port_from_network_addr("http://[::1]:8080", 3128),
        "[::1]:8080"                                               // IPv6 表示形式 (L752-757)
    );

    assert_eq!(
        host_and_port_from_network_addr("example.com:notaport", 3128),
        "example.com:3128"                                         // 無効なポート → デフォルトポート
    );
}
```

**Errors / Panics**

- この関数は常に `String` を返し、エラーを返しません。
- `parse_host_port` 内部でのエラーは握りつぶし、ベストエフォートの整形にフォールバックします (config.rs:L442-446)。

**Edge cases（エッジケース）**

- 空や空白のみの文字列: 常に `"<missing>"`。
- `value` に `":"` を含むがパース不能な場合:
  - それでも `format_host_and_port` によって `[value]:default_port` のような形式が返ります (config.rs:L452-457)。

**使用上の注意点**

- これは人間向けの表示用ヘルパーであり、ネットワーク接続に直接使うべき値ではありません。
- 失敗時も何らかの文字列を返す設計のため、「フォールバック表示」として扱う必要があります。

---

#### `validate_unix_socket_allowlist_paths(cfg: &NetworkProxyConfig) -> Result<()>`  

（config.rs:L400-405）

**概要**

- `cfg.network.allow_unix_sockets()` で取得できる UNIX ソケット許可リストの全エントリに対して `ValidatedUnixSocketPath::parse` を適用し、すべて妥当な絶対パスであることを検証します。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `cfg` | `&NetworkProxyConfig` | 検証対象の設定。 |

**戻り値**

- `Ok(())`  
  - すべてのエントリが妥当な絶対パスである場合、または許可リストが空の場合。
- `Err(anyhow::Error)`  
  - 1 件でも不正なパスがあればエラー。メッセージに `network.allow_unix_sockets[index]` が含まれます。

**内部処理の流れ**

1. `cfg.network.allow_unix_sockets()` で `Vec<String>` を取得 (config.rs:L400-401, L187-201)。
2. `enumerate()` でインデックスをつけてイテレート。
3. 各 `socket_path` に対して `ValidatedUnixSocketPath::parse` を呼び、エラー時に `with_context` で `"invalid network.allow_unix_sockets[{index}]"` を追加 (config.rs:L402-403)。
4. 全て成功したら `Ok(())` を返す (config.rs:L405)。

**Examples（使用例）**

```rust
use network_proxy::config::{NetworkProxyConfig, NetworkProxySettings, validate_unix_socket_allowlist_paths};

fn validate_list_example() -> anyhow::Result<()> {
    let mut settings = NetworkProxySettings::default();
    settings.set_allow_unix_sockets(vec!["/tmp/example.sock".to_string()]);

    let cfg = NetworkProxyConfig { network: settings };

    validate_unix_socket_allowlist_paths(&cfg)?;                    // 成功

    Ok(())
}
```

**Errors / Panics**

- 相対パス（例: `"relative.sock"`）が含まれているとエラーになります。テストでは、`resolve_runtime` 経由でこの関数が呼ばれ、エラーメッセージに `network.allow_unix_sockets[0]` が含まれることが確認されています (config.rs:L839-856)。
- panic はありません。

**Edge cases（エッジケース）**

- `allow_unix_sockets` が空の場合:
  - for ループは一度も実行されず、`Ok(())` となります (config.rs:L400-405)。
- 複数エラーがあっても、最初に失敗したエントリの情報だけが返されます（`Result` は早期リターン）。

**使用上の注意点**

- この関数は `resolve_runtime` 内で最初に呼ばれており、UNIX ソケット許可リストに問題があると、バインドアドレス解決まで進みません (config.rs:L408-409)。
- エラーの特定には `index` 情報（`[0]` など）が役立つようになっています。

---

### 3.3 その他の関数一覧（抜粋）

本モジュール内の他の補助的な関数/メソッドの一覧です。

| 関数名 | 可視性 | 行範囲 | 役割（1 行） |
|--------|--------|--------|--------------|
| `NetworkProxySettings::allowed_domains` | `pub` | config.rs:L165-167 | 有効な Allow ドメインの一覧を返す。 |
| `NetworkProxySettings::denied_domains` | `pub` | config.rs:L169-171 | 有効な Deny ドメインの一覧を返す。 |
| `NetworkProxySettings::domain_entries` | private | config.rs:L173-185 | 指定 Permission のパターンだけを抽出する内部ヘルパー。 |
| `NetworkProxySettings::set_denied_domains` | `pub` | config.rs:L207-209 | Deny ドメインの一覧を設定。 |
| `NetworkProxySettings::set_allow_unix_sockets` | `pub` | config.rs:L229-231 | UNIX ソケット許可リストを設定。 |
| `NetworkProxySettings::set_domain_entries` | private | config.rs:L233-251 | Allow/Deny 用エントリをまとめて置き換える内部ヘルパー。 |
| `NetworkProxySettings::set_unix_socket_entries` | private | config.rs:L253-266 | UNIX ソケット許可/不許可エントリを置き換える内部ヘルパー。 |
| `NetworkMode::allows_method` | `pub` | config.rs:L282-288 | モードに応じて HTTP メソッドが許可されるか判定。 |
| `default_proxy_url` | private | config.rs:L291-293 | `proxy_url` フィールドのデフォルト値 (`http://127.0.0.1:3128`) を返す。 |
| `default_socks_url` | private | config.rs:L295-297 | `socks_url` フィールドのデフォルト値 (`http://127.0.0.1:8081`) を返す。 |
| `clamp_non_loopback` | private | config.rs:L299-320 | 非ループバックアドレスをループバックにクランプするユーティリティ。 |
| `resolve_addr` | private | config.rs:L423-433 | `parse_host_port` の結果から `SocketAddr` を構築し、ホスト名をループバックにフォールバック。 |
| `format_host_and_port` | private | config.rs:L452-457 | IPv6 の場合に `"[host]:port"`、それ以外は `"host:port"` に整形。 |
| `parse_host_port_fallback` | private | config.rs:L503-552 | URL パーサに頼れないケースのための手動パーサ。 |
| `UnixStyleAbsolutePath::parse` | private | config.rs:L371-374 | `/` で始まる文字列を Unix 風絶対パスとして受理。 |

テスト用ヘルパーとテスト関数は `mod tests` 以下にまとまっており、API の期待挙動を広くカバーしています (config.rs:L554-869)。

---

## 4. データフロー

### 4.1 設定からランタイムへの変換フロー

`NetworkProxyConfig` から `RuntimeConfig` への代表的なデータフローを示します。

```mermaid
sequenceDiagram
    participant Loader as 設定ローダ
    participant Cfg as NetworkProxyConfig (L16-20)
    participant RT as resolve_runtime (L408-421)
    participant VUS as validate_unix_socket_allowlist_paths (L400-405)
    participant VPath as ValidatedUnixSocketPath::parse (L383-397)
    participant Addr as resolve_addr (L423-433)
    participant HP as parse_host_port (L466-501)
    participant Clamp as clamp_bind_addrs (L322-361)

    Loader->>Cfg: JSON/ファイルからデシリアライズ
    Loader->>RT: &Cfg

    RT->>VUS: validate_unix_socket_allowlist_paths(&Cfg)
    VUS->>Cfg: Cfg.network.allow_unix_sockets() (L187-201)
    loop for each path
        VUS->>VPath: parse(socket_path)
        VPath-->>VUS: Result<ValidatedUnixSocketPath>
    end
    VUS-->>RT: Ok(())

    RT->>Addr: resolve_addr(proxy_url, 3128)
    Addr->>HP: parse_host_port(url, default_port)
    HP-->>Addr: SocketAddressParts
    Addr-->>RT: SocketAddr

    RT->>Addr: resolve_addr(socks_url, 8081)
    Addr-->>RT: SocketAddr

    RT->>Clamp: clamp_bind_addrs(http_addr, socks_addr, &Cfg.network)
    Clamp-->>RT: (http_addr, socks_addr)

    RT-->>Loader: Ok(RuntimeConfig)
```

要点:

- UNIX ソケット許可リストの検証は、アドレス解決よりも先に行われます (config.rs:L408-409)。
- ホスト/ポートは `parse_host_port` → `resolve_addr` の順に解決され、ホスト名はループバックにフォールバックします (config.rs:L423-433, L466-501)。
- 最終的なバインドアドレスの安全性は `clamp_bind_addrs` によって保証されます (config.rs:L322-361)。

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

典型的なフローは「設定のロード → 必要に応じた上書き → `resolve_runtime` の呼び出し → 実サーバでの使用」です。

```rust
use network_proxy::config::{
    NetworkProxyConfig,
    NetworkProxySettings,
    NetworkMode,
    resolve_runtime,
};
use serde::Deserialize;

// 1. アプリ全体設定の例。serde でデシリアライズ可能にする。
#[derive(Deserialize)]
struct AppConfig {
    network: NetworkProxySettings,                                      // NetworkProxyConfig と同じフィールド構成 (L16-20, L119-142)
}

fn main() -> anyhow::Result<()> {
    // 2. 設定ファイルなどから JSON をロードしてデシリアライズする（例）
    let json = r#"{
        "network": {
            "enabled": true,
            "proxy_url": "0.0.0.0:3128",
            "socks_url": "127.0.0.1:8081",
            "mode": "limited"
        }
    }"#;

    let app_cfg: AppConfig = serde_json::from_str(json)?;               // 不足フィールドは Default で補われる (L117-142, L595-611)

    // 3. NetworkProxyConfig に詰め替える
    let cfg = NetworkProxyConfig {
        network: app_cfg.network,
    };

    // 4. ランタイム設定を解決する
    let runtime = resolve_runtime(&cfg)?;                               // HTTP/SOCKS の SocketAddr を取得 (L408-421)

    // 5. 実際のプロキシサーバ実装に渡してバインドする
    // http_server.bind(runtime.http_addr)?;
    // socks_server.bind(runtime.socks_addr)?;

    Ok(())
}
```

### 5.2 よくある使用パターン

#### ドメイン許可/拒否の設定

```rust
use network_proxy::config::NetworkProxySettings;

fn configure_domains() {
    let mut settings = NetworkProxySettings::default();

    // 特定ドメインを拒否
    settings.set_denied_domains(vec![
        "example.com".to_string(),
        "*.tracking.com".to_string(),
    ]);

    // 一部サブドメインだけ許可するなど、必要に応じて Allow を設定
    settings.set_allowed_domains(vec![
        "api.example.com".to_string(),
    ]);

    // 実際の適用結果は allowed_domains / denied_domains で確認
    let allowed = settings.allowed_domains(); // None or Some(Vec<...>) (L165-167)
    let denied = settings.denied_domains();   // 同様 (L169-171)
}
```

#### UNIX ソケットプロキシの有効化

```rust
use network_proxy::config::{NetworkProxySettings, NetworkProxyConfig, resolve_runtime};

fn configure_unix_sockets() -> anyhow::Result<()> {
    let mut settings = NetworkProxySettings::default();
    settings.enabled = true;

    // UNIX ソケットへのプロキシングを許可するパスを追加
    settings.set_allow_unix_sockets(vec![
        "/var/run/docker.sock".to_string(),
    ]);                                                                   // L229-231

    let cfg = NetworkProxyConfig { network: settings };

    // パス形式が妥当でない場合、ここでエラーになる
    let runtime = resolve_runtime(&cfg)?;                                 // L408-421

    // runtime.http_addr / socks_addr は自動的にループバックにクランプされる (L322-361)

    Ok(())
}
```

### 5.3 よくある間違い

#### 相対パスの UNIX ソケットを許可しようとする

```rust
use network_proxy::config::{NetworkProxyConfig, NetworkProxySettings, resolve_runtime};

fn wrong_unix_path() {
    let mut settings = NetworkProxySettings::default();
    // 間違い例: 相対パス
    settings.set_allow_unix_sockets(vec!["relative.sock".to_string()]);

    let cfg = NetworkProxyConfig { network: settings };

    // 正しくはエラーになる
    let err = resolve_runtime(&cfg).unwrap_err();                         // テストで検証済み (L839-856)
    assert!(err.to_string().contains("network.allow_unix_sockets[0]"));
}
```

**正しい例**: `/tmp/relative.sock` のように絶対パスを指定する (config.rs:L383-397)。

#### ホスト名を 0.0.0.0 の代わりに指定して外部公開を期待する

```rust
use network_proxy::config::{NetworkProxySettings, NetworkProxyConfig, resolve_runtime};

fn wrong_host() -> anyhow::Result<()> {
    let mut settings = NetworkProxySettings::default();
    settings.enabled = true;
    settings.proxy_url = "http://example.com:3128".to_string();          // ホスト名 (L781-789)

    let cfg = NetworkProxyConfig { network: settings };
    let runtime = resolve_runtime(&cfg)?;                                // resolve_addr が 127.0.0.1 にフォールバック (L423-433)

    // 実際には 127.0.0.1:3128 にバインドされ、外部公開にはなりません
    assert_eq!(runtime.http_addr.to_string(), "127.0.0.1:3128");

    Ok(())
}
```

**正しい例**: 外部公開したい場合は `0.0.0.0:3128` と書いたうえで `dangerously_allow_non_loopback_proxy = true` をセットする必要があります (config.rs:L793-805)。

### 5.4 使用上の注意点（まとめ）

- **安全デフォルト**  
  - 非ループバックアドレスへのバインドはデフォルトで拒否され、明示的なフラグが必要です (config.rs:L299-320)。
- **ホスト名はループバックにフォールバック**  
  - `resolve_addr` はホスト名を実 IP に解決せず、ループバックに置き換えます (config.rs:L423-433)。
- **UNIX ソケット許可リストは絶対パスのみ**  
  - 相対パスは設定時点では受け入れられますが、`resolve_runtime` でエラーになります (config.rs:L383-397, L400-405, L839-856)。
- **並行性**  
  - いずれの API も `Sync`/`Send` 制約を直接表明していませんが、内部にはグローバルな可変状態がなく、`&NetworkProxyConfig` / `&NetworkProxySettings` を共有する限りはスレッドセーフに扱えます（Rust の所有権/借用ルールに従います）。

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

例: 新しいドメイン Permission（例えば `Audit`）を追加したい場合。

1. **列挙体の拡張**  
   - `NetworkDomainPermission` に新しいバリアントを追加し、順序（Allow/Deny との大小関係）を明確にする (config.rs:L26-30)。
2. **`effective_entries` の確認**  
   - 列挙順序が優先度に直結しているため、新バリアントの相対的な優先度を意図通りになるよう再確認する (config.rs:L72-101)。
3. **シリアライズ形式の確認**  
   - `NetworkDomainPermissions` の Serialize/Deserialize 実装はバリアント名をそのまま使うので、新バリアントの `serde(rename_all = "lowercase")` の影響を確認する (config.rs:L24-25, L43-53, L56-69)。
4. **テストの追加**  
   - 許可/拒否/Audit の競合パターンについて新しいテストケースを `mod tests` に追加する (config.rs:L554-869)。

### 6.2 既存の機能を変更する場合

例: `parse_host_port` のパースルールを変更する場合。

- **影響範囲の確認**
  - 直接の呼び出し元: `resolve_addr` と `host_and_port_from_network_addr` (config.rs:L423-433, L436-450)。
  - 間接的に `resolve_runtime` に影響し、テスト群にも広く影響します (config.rs:L573-757, L760-790)。
- **契約の確認**
  - 現在は「空やホスト欠落はエラー」「無効なポートは `default_port` にフォールバック」という振る舞いが前提になっています (config.rs:L466-470, L533-542, L733-741)。
- **テストの更新**
  - `parse_host_port_*` および `host_and_port_from_network_addr_*` のテストを更新し、新しいルールを明示的にカバーする必要があります (config.rs:L660-757)。

---

## 7. 関連ファイル

このチャンクには他ファイルのコードは含まれていないため、厳密な依存関係は分かりませんが、少なくとも次のような関係が読み取れます。

| パス | 役割 / 関係 |
|------|------------|
| `network-proxy/src/config.rs` | 本モジュール。ネットワークプロキシの設定・UNIX ソケット許可リスト・バインドアドレス解決を提供する。 |
| （不明） | 実際に HTTP/SOCKS プロキシサーバを起動するモジュール。`RuntimeConfig` を受け取りソケットバインドを行うと推測されますが、このチャンクからは詳細不明です。 |
| `codex_utils_absolute_path` クレート | `AbsolutePathBuf` を提供し、UNIX ソケットパスの正規化に利用されています (config.rs:L4, L387-389)。 |

このファイル単体で、設定関連のコアロジックと安全性ポリシーはほぼ完結しており、上位のアプリケーションコードは主に `NetworkProxyConfig` と `resolve_runtime` を入口として利用する構造になっています。
