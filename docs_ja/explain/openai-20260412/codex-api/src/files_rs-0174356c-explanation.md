# codex-api/src/files.rs コード解説

## 0. ざっくり一言

ローカルファイルを OpenAI ファイル API 互換のバックエンドにアップロードし、ダウンロード用 URL や URI を取得する非同期ヘルパーを提供するモジュールです（codex-api/src/files.rs:L14-20, L93-95, L97-252）。

---

## 1. このモジュールの役割

### 1.1 概要

- このモジュールは、**ローカルファイルをリモートストレージにアップロードし、そのメタデータを取得する処理**を担当します（L97-252）。
- ファイルの存在確認・サイズチェック・アップロード・アップロード完了のポーリング・結果のラップを一つの関数 `upload_local_file` にまとめています（L97-252）。
- エラーは `OpenAiFileError` 列挙体を通じて詳細な原因とともに返されます（L33-75）。

### 1.2 アーキテクチャ内での位置づけ

このモジュールは、`AuthProvider` を用いて認証付き HTTP リクエストを送り、`reqwest` と `tokio` による非同期 I/O でファイルアップロードを行います（L5, L10-12, L132-139, L165-172, L193-201）。

```mermaid
graph LR
    subgraph "codex-api/src/files.rs"
        ULF["upload_local_file (L97-252)"]
        AReq["authorized_request (L254-270)"]
        BRC["build_reqwest_client (L272-277)"]
        Err["OpenAiFileError (L33-75)"]
        UOF["UploadedOpenAiFile (L22-31)"]
    end

    Caller["呼び出し側コード"] --> ULF
    ULF --> AReq
    ULF --> BRC
    ULF --> UOF
    ULF --> Err

    AReq --> Auth["AuthProvider トレイト（定義はこのチャンクには現れない） (L5, L254-268)"]
    BRC --> CCA["codex_client::build_reqwest_client_with_custom_ca (L6, L272-276)"]

    ULF -->|HTTP POST /files, POST /files/{id}/uploaded| Backend["OpenAI 互換バックエンド<br/>(base_url 以下)"]
    ULF -->|HTTP PUT upload_url| Storage["アップロード用エンドポイント<br/>(upload_url)"]
```

> この図は、`upload_local_file (L97-252)` を中心とした依存関係を表しています。

### 1.3 設計上のポイント

- **責務の分割**  
  - 公開 API は URI 生成 (`openai_file_uri`) とアップロード (`upload_local_file`) に限定されています（L93-95, L97-252）。
  - 認証付きリクエストの組み立ては `authorized_request` に切り出されています（L254-270）。
  - HTTP クライアントの生成とカスタム CA の扱いは `build_reqwest_client` に集約されています（L272-277）。

- **状態管理**  
  - モジュール内に永続的な状態は持たず、関数はすべて「入力 → 処理 → 戻り値」の形で動作します。
  - `UploadedOpenAiFile` はアップロード結果のスナップショットを保持する不変データ構造として設計されています（L22-31）。

- **エラーハンドリング**  
  - すべての失敗は `OpenAiFileError` にマッピングされ、パス・URL・元のエラー（`source`）を保持します（L33-75）。
  - HTTP ステータスが成功でない場合はボディ文字列を含む `UnexpectedStatus` を返します（L59-64, L146-151, L179-185, L204-209）。
  - JSON デコード失敗は `Decode` として表現されます（L65-70, L153-157, L211-215）。

- **非同期・並行性**  
  - `upload_local_file` は `async fn` であり、`tokio::fs`・`tokio::time`・`reqwest` を用いた完全非同期 I/O です（L97, L102-104, L159-172, L192-193, L240-241）。
  - アップロード完了待ち（finalize）は、タイムアウト付きのポーリングループ＋`tokio::time::sleep` によって実装されています（L192-241）。
  - 共有ミュータブル状態は本体コードにはありません。テストでのみ `Arc<AtomicUsize>` を使用しています（L284-286, L328-329, L368）。

---

## 2. 主要な機能一覧

- OpenAI ファイル URI の生成: `openai_file_uri` — `sediment://<file_id>` 形式の URI を返します（L14, L93-95）。
- ローカルファイルのアップロード: `upload_local_file` — ファイル存在・サイズの検証からアップロード・完了確認・結果オブジェクト生成までを行います（L97-252）。
- 認証付き HTTP リクエストの組み立て: `authorized_request` — `AuthProvider` からトークンとアカウント ID を取得してヘッダに設定します（L254-268）。
- カスタム CA 付き HTTP クライアント生成: `build_reqwest_client` — `codex_client::build_reqwest_client_with_custom_ca` を利用し、失敗時はログを出してデフォルトクライアントにフォールバックします（L272-277）。

---

## 3. 公開 API と詳細解説

### 3.1 型・関数インベントリー

#### 3.1.1 型一覧

| 名前 | 種別 | 公開範囲 | 定義位置 | 役割 / 用途 |
|------|------|----------|----------|-------------|
| `UploadedOpenAiFile` | 構造体 | `pub` | `codex-api/src/files.rs:L22-31` | アップロード完了した OpenAI ファイルのメタデータとローカルパスを保持します。`file_id`・`uri`・`download_url` などをまとめて返します。 |
| `OpenAiFileError` | 列挙体 | `pub` | `codex-api/src/files.rs:L33-75` | パスの問題・ファイルサイズ超過・HTTP エラー・JSON デコードエラー・アップロード未完了など、アップロード処理で起こりうるすべてのエラー分類です。 |
| `CreateFileResponse` | 構造体 | モジュール内限定 | `codex-api/src/files.rs:L77-81` | `POST {base_url}/files` のレスポンス JSON をデコードするための内部用型です。`file_id` と `upload_url` を保持します。 |
| `DownloadLinkResponse` | 構造体 | モジュール内限定 | `codex-api/src/files.rs:L83-91` | アップロード完了ポーリング (`POST {base_url}/files/{file_id}/uploaded`) のレスポンス JSON を表す内部用型です。`status` や `download_url` などを保持します。 |

#### 3.1.2 定数一覧

| 名前 | 公開範囲 | 定義位置 | 値 / 役割 |
|------|----------|----------|-----------|
| `OPENAI_FILE_URI_PREFIX` | `pub` | `codex-api/src/files.rs:L14` | `"sediment://"` — `openai_file_uri` で利用される URI プレフィックスです（L93-95）。 |
| `OPENAI_FILE_UPLOAD_LIMIT_BYTES` | `pub` | `codex-api/src/files.rs:L15` | `512 * 1024 * 1024` バイト（512 MiB）— ローカルファイルの最大アップロードサイズ上限として使用されます（L118-123）。 |
| `OPENAI_FILE_REQUEST_TIMEOUT` | モジュール内限定 | `codex-api/src/files.rs:L17` | `Duration::from_secs(60)` — HTTP リクエスト（作成・アップロード・ファイナライズ）のタイムアウトです（L167, L261）。 |
| `OPENAI_FILE_FINALIZE_TIMEOUT` | モジュール内限定 | `codex-api/src/files.rs:L18` | `Duration::from_secs(30)` — ファイナライズポーリング全体の許容時間です（L192-193, L235-238）。 |
| `OPENAI_FILE_FINALIZE_RETRY_DELAY` | モジュール内限定 | `codex-api/src/files.rs:L19` | `Duration::from_millis(250)` — ファイナライズの再試行間隔です（L240-241）。 |
| `OPENAI_FILE_USE_CASE` | モジュール内限定 | `codex-api/src/files.rs:L20` | `"codex"` — ファイル作成リクエスト JSON の `use_case` フィールドとして送信されます（L133-137）。 |

#### 3.1.3 関数一覧

| 関数名 | 公開範囲 | async | 戻り値 | 定義位置 | 役割（1 行） |
|--------|----------|-------|--------|----------|--------------|
| `openai_file_uri` | `pub` | いいえ | `String` | `codex-api/src/files.rs:L93-95` | `OPENAI_FILE_URI_PREFIX` と `file_id` を連結し、`sediment://<id>` 形式の URI を生成します。 |
| `upload_local_file` | `pub` | はい | `Result<UploadedOpenAiFile, OpenAiFileError>` | `codex-api/src/files.rs:L97-252` | ローカルファイルを検証し、リモートにアップロードし、ダウンロード URL などを含む `UploadedOpenAiFile` を返します。 |
| `authorized_request` | モジュール内限定 | いいえ | `reqwest::RequestBuilder` | `codex-api/src/files.rs:L254-270` | `AuthProvider` のトークン・アカウント ID を用いて認証ヘッダ付きの `RequestBuilder` を構築します。 |
| `build_reqwest_client` | モジュール内限定 | いいえ | `reqwest::Client` | `codex-api/src/files.rs:L272-277` | カスタム CA 設定付きの `reqwest::Client` を生成し、失敗時は警告ログを出してデフォルトクライアントを返します。 |

（テストモジュール内の `chatgpt_auth`・`base_url_for`・`upload_local_file_returns_canonical_uri` はテスト専用のため、後述のテストセクションで扱います。）

---

### 3.2 関数詳細

#### `openai_file_uri(file_id: &str) -> String` （L93-95）

**概要**

- OpenAI ファイル ID から `sediment://<file_id>` 形式の URI を生成します（L14, L93-95）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `file_id` | `&str` | OpenAI ファイルを一意に識別する ID 文字列です。 |

**戻り値**

- `String` — `OPENAI_FILE_URI_PREFIX`（`"sediment://"`）と `file_id` を連結した文字列です（L14, L93-95）。

**内部処理の流れ**

1. フォーマット文字列 `"{OPENAI_FILE_URI_PREFIX}{file_id}"` を `format!` で組み立てます（L93-94）。
2. 結果の `String` を返します（L95）。

**Examples（使用例）**

```rust
use codex_api::files::openai_file_uri;

let file_id = "file_123";                            // 何らかの方法で得られた OpenAI ファイル ID
let uri = openai_file_uri(file_id);                  // "sediment://file_123" を生成
assert_eq!(uri, "sediment://file_123".to_string());
```

**Errors / Panics**

- パニック要因はありません。`format!` は通常の文字列連結であり、入力によりパニックすることはありません（L93-95）。

**Edge cases（エッジケース）**

- `file_id` が空文字列の場合、結果は `"sediment://"` になります。この挙動はコードからそのまま読み取れます（L93-95）。
- `file_id` に非 ASCII 文字が含まれていても、そのまま連結されます。エンコードやバリデーションは行っていません（L93-95）。

**使用上の注意点**

- 返される URI のスキーム `"sediment://"` はこのモジュール独自のものです（L14）。実際にどのコンポーネントがこの URI を解釈するかは、このファイルからは分かりません。
- この関数は純粋関数であり、副作用はありません。

---

#### `upload_local_file(base_url: &str, auth: &impl AuthProvider, path: &Path) -> Result<UploadedOpenAiFile, OpenAiFileError>` （L97-252）

**概要**

- 指定されたローカルファイルを検証し、OpenAI 互換のバックエンドにアップロードします。
- アップロード完了までポーリングで待ち、`file_id`・`download_url`・`uri` などを含む `UploadedOpenAiFile` を返します（L22-31, L97-252）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `base_url` | `&str` | バックエンド API のベース URL。関数内で `"{base_url}/files"` や `"{base_url}/files/{file_id}/uploaded"` が構築されます（L131, L187-191）。 |
| `auth` | `&impl AuthProvider` | 認証情報の提供者。`bearer_token()` と `account_id()` が使われます（L254-268）。定義はこのチャンクには現れません。 |
| `path` | `&Path` | アップロード対象ローカルファイルのパスです（L97-101）。 |

**戻り値**

- `Ok(UploadedOpenAiFile)` — アップロードが成功し、バックエンドがダウンロード URL などを返した場合（L219-232）。
- `Err(OpenAiFileError)` — パスの問題、サイズ超過、HTTP エラー、JSON デコードエラー、アップロード未完了／失敗など、詳細な理由付きで失敗を表します（L33-75, L102-124, L140-143, L147-151, L153-157, L159-176, L179-185, L198-201, L205-209, L212-215, L222-227, L235-239, L243-249）。

**内部処理の流れ（アルゴリズム）**

1. **ファイルメタデータ取得とバリデーション**（L102-124）  
   - `tokio::fs::metadata(path)` で非同期にメタデータを取得します（L102-104）。  
   - エラー種別が `NotFound` なら `OpenAiFileError::MissingPath`、それ以外は `ReadFile` にマッピングします（L104-112）。  
   - `metadata.is_file()` が `false` なら `NotAFile` を返します（L113-117）。  
   - `metadata.len()` が `OPENAI_FILE_UPLOAD_LIMIT_BYTES` を超える場合、`FileTooLarge` を返します（L118-123）。

2. **ファイル名決定と作成リクエスト**（L126-157）  
   - `path.file_name().and_then(|v| v.to_str()).unwrap_or("file")` でファイル名文字列を決定します（L126-130）。非 UTF-8 名は `"file"` にフォールバックします。  
   - `create_url = format!("{}/files", base_url.trim_end_matches('/'))` を生成します（L131）。  
   - `authorized_request` により `POST create_url` のリクエストを構築し、JSON ボディ `{ file_name, file_size, use_case: "codex" }` を送信します（L132-139）。  
   - 送信エラーは `OpenAiFileError::Request` に変換されます（L140-143）。  
   - ステータスコードが成功でなければ `UnexpectedStatus`（ボディ文字列付き）を返します（L144-151）。  
   - レスポンスボディを `CreateFileResponse` として JSON デコードし、失敗時は `Decode` エラーを返します（L153-157）。

3. **ファイル本体のアップロード**（L159-185）  
   - `File::open(path)` で非同期にファイルを開き、失敗時は `ReadFile` エラーです（L159-164）。  
   - `build_reqwest_client()` で HTTP クライアントを用意し、`PUT create_payload.upload_url` を送信します（L165-172）。  
     - タイムアウトは `OPENAI_FILE_REQUEST_TIMEOUT`（60 秒）です（L167）。  
     - `x-ms-blob-type: BlockBlob` と `content-length` ヘッダを設定します（L168-169）。  
     - ボディは `ReaderStream::new(upload_file)` を `reqwest::Body::wrap_stream` で包んでストリーミング送信します（L170）。  
   - 送信エラーは `Request`、非成功ステータスは `UnexpectedStatus` にマッピングされます（L173-176, L177-185）。

4. **アップロード完了のファイナライズ（ポーリング）**（L187-251）  
   - `finalize_url = "{base_url}/files/{file_id}/uploaded"` を組み立てます（L187-191）。  
   - `Instant::now()` を記録し、ポーリング全体の経過時間を測ります（L192）。  
   - ループ内で以下を繰り返します（L193-251）：  
     1. `authorized_request` により `POST finalize_url` を送り、空の JSON `{}` をボディとして送信します（L194-201）。  
     2. ステータスが成功でなければ `UnexpectedStatus` を返します（L204-209）。  
     3. レスポンスボディを `DownloadLinkResponse` として JSON デコードし、失敗時は `Decode` を返します（L211-215）。  
     4. `status` フィールドにより分岐します（L217-250）：  
        - `"success"` の場合（L218-233）：  
          - `download_url` が `Some` でなければ `UploadFailed { message: "missing download_url" }` を返します（L222-227）。  
          - `file_name` はレスポンスの値が `Some` ならそれを、`None` なら先に決めたファイル名を用います（L228）。  
          - `mime_type` は `Option<String>` のままコピーします（L230）。  
          - これらと `file_id`・`uri`・`file_size_bytes` を `UploadedOpenAiFile` に詰めて返します（L219-232）。  
        - `"retry"` の場合（L234-241）：  
          - `finalize_started_at.elapsed()` が `OPENAI_FILE_FINALIZE_TIMEOUT`（30 秒）以上なら `UploadNotReady` エラーを返します（L235-239）。  
          - そうでなければ `tokio::time::sleep(OPENAI_FILE_FINALIZE_RETRY_DELAY)`（250 ms）で待って再試行します（L240-241）。  
        - その他の文字列の場合（L242-249）：  
          - `error_message` が `Some` ならそれを、`None` なら `"upload finalization returned an error"` をメッセージとして `UploadFailed` を返します（L243-249）。

**非同期・並行性の観点**

- `metadata` 取得・ファイルオープン・HTTP 通信・`sleep` はすべて `async`/`await` を用いた非同期処理です（L102-104, L159-161, L165-172, L193-201, L240-241）。
- 共有ミュータブル状態は使用していないため、この関数自体は他のタスクと独立して動作できます。
- `Instant` と `tokio::time::sleep` を用いることで、ポーリングループはブロッキングせずにタイムアウトを管理します（L192-193, L235-241）。

**Examples（使用例）**

以下は、典型的な利用例を示します。認証情報の具体的な実装はこのファイルには現れないため、コメントで表現しています。

```rust
use std::path::Path;
use codex_api::files::upload_local_file;
use codex_api::files::UploadedOpenAiFile;
use codex_api::AuthProvider;   // トレイト定義は別モジュール（このチャンクには現れない）

// 何らかの AuthProvider 実装を用意していると仮定する
struct MyAuth;
impl AuthProvider for MyAuth {
    // bearer_token() や account_id() の実装は crate 側の定義に従う
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let base_url = "https://example.com/backend-api";   // "/files" は付けない（関数内で付加される） (L131)
    let auth = MyAuth;
    let path = Path::new("data/hello.txt");

    match upload_local_file(base_url, &auth, path).await {
        Ok(UploadedOpenAiFile { file_id, uri, download_url, .. }) => {
            println!("file_id = {file_id}");
            println!("uri = {uri}");
            println!("download_url = {download_url}");
        }
        Err(e) => {
            eprintln!("upload failed: {e}");
        }
    }

    Ok(())
}
```

**Errors / Panics**

- 明示的な `unwrap` や `expect` は本体コードにはなく、通常の経路ではパニックしません（`unwrap_or`・`unwrap_or_default` のみ使用：L129-130, L145）。
- 発生しうる主なエラーと条件は次の通りです（`OpenAiFileError` 定義 L33-75 と照合）:

  - `MissingPath` — `metadata(path)` が `ErrorKind::NotFound` を返した場合（L104-107）。
  - `ReadFile` — `metadata`／`File::open` などで他の I/O エラーが発生した場合（L108-112, L159-164）。
  - `NotAFile` — `metadata.is_file()` が `false` の場合（L113-117）。
  - `FileTooLarge` — `metadata.len()` > `OPENAI_FILE_UPLOAD_LIMIT_BYTES` の場合（L118-123）。
  - `Request` — `create`／`upload`／`finalize` における HTTP 送信中に `reqwest::Error` が発生した場合（L140-143, L173-176, L198-201）。
  - `UnexpectedStatus` — HTTP ステータスが成功でない場合（L146-151, L179-185, L205-209）。
  - `Decode` — 作成／ファイナライズレスポンスの JSON デコードに失敗した場合（L153-157, L211-215）。
  - `UploadNotReady` — ファイナライズで `"retry"` が続き、30 秒以上経過した場合（L235-239）。
  - `UploadFailed` — `"success"` だが `download_url` が欠如している場合、または `"retry"` 以外のステータスでエラーとして扱われた場合（L222-227, L243-249）。

**Edge cases（エッジケース）**

- **存在しないパス**  
  - `metadata` が `NotFound` を返すと `MissingPath` になります（L104-107）。
- **ディレクトリパス**  
  - `is_file()` が偽で `NotAFile` になります（L113-117）。
- **サイズ上限超過**  
  - ファイルサイズが 512 MiB を超えると即時に `FileTooLarge` エラーが返され、ネットワークリクエストは行われません（L15, L118-123）。
- **非 UTF-8 ファイル名**  
  - `to_str()` が `None` を返した場合、`"file"` にフォールバックします（L126-130）。
- **アップロード PUT のタイムアウト**  
  - `OPENAI_FILE_REQUEST_TIMEOUT`（60 秒）でタイムアウトすると `reqwest::Error` となり、`Request` エラーにマッピングされます（L167, L173-176）。  
    タイムアウト自体の詳細は `reqwest::Error` 側の情報として保持されます。
- **ファイナライズの長時間遅延**  
  - `"retry"` が返り続け、30 秒以上経過した時点で `UploadNotReady` としてエラー終了します（L192-193, L235-239）。
- **ファイナライズレスポンスの不整合**  
  - `"success"` にもかかわらず `download_url` が `None` の場合は `UploadFailed`（`"missing download_url"`）で失敗扱いになります（L222-227）。
  - `status` が `"success"` / `"retry"` 以外で、`error_message` が `None` の場合は、固定メッセージ `"upload finalization returned an error"` が使われます（L243-249）。

**使用上の注意点**

- `base_url` には末尾の `/files` を含めないことが前提です。関数内で `"{base_url}/files"` や `"{base_url}/files/{file_id}/uploaded"` を生成しているため、`/files` を重ねると URL が崩れます（L131, L187-191）。
- ファイルサイズ上限（512 MiB）はハードコードされているため、より大きなファイルを扱うには定数の変更と再コンパイルが必要です（L15, L118-123）。
- エラーにはローカルパスやリモート URL、HTTP レスポンスボディが含まれるため、ログ出力時に機密情報や内部構造が露出しうる点に注意が必要です（L35-37, L53-56, L59-64）。
- この関数は I/O とネットワークを伴うため、呼び出し頻度が高い場合はバックエンド側への負荷・レート制限にも注意する必要があります。このファイル単体から具体的な制限値は分かりません。

---

#### `authorized_request(auth: &impl AuthProvider, method: reqwest::Method, url: &str) -> reqwest::RequestBuilder` （L254-270）

**概要**

- `AuthProvider` から Bearer トークンとアカウント ID を取得し、タイムアウト付きの `reqwest::RequestBuilder` を作成します（L254-268）。

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `auth` | `&impl AuthProvider` | 認証情報を提供するトレイトオブジェクト。`bearer_token()`・`account_id()` を呼び出しています（L263-267）。 |
| `method` | `reqwest::Method` | HTTP メソッド（POST など）です（L254-257）。 |
| `url` | `&str` | リクエスト先 URL です（L254-257）。 |

**戻り値**

- `reqwest::RequestBuilder` — `build_reqwest_client()` で生成した `Client` を元に、タイムアウト・認証ヘッダ・アカウント ID ヘッダが設定されたビルダーです（L259-269）。

**内部処理の流れ**

1. `build_reqwest_client()` で `reqwest::Client` を取得します（L259, L272-277）。
2. `client.request(method, url)` で `RequestBuilder` を作成し、`OPENAI_FILE_REQUEST_TIMEOUT` をタイムアウトとして設定します（L260-262）。
3. `auth.bearer_token()` が `Some(token)` の場合、`Authorization: Bearer <token>` ヘッダを設定します（L263-265）。
4. `auth.account_id()` が `Some(account_id)` の場合、`chatgpt-account-id: <account_id>` ヘッダを追加します（L266-267）。
5. 最終的な `RequestBuilder` を返します（L269）。

**Examples（使用例）**

この関数はモジュール内部からのみ呼び出されています。たとえば `upload_local_file` 内で次のように使われています。

```rust
// ファイル作成リクエストの構築 (L132-139)
let create_response = authorized_request(auth, reqwest::Method::POST, &create_url)
    .json(&serde_json::json!({
        "file_name": file_name,
        "file_size": metadata.len(),
        "use_case": OPENAI_FILE_USE_CASE,
    }))
    .send()
    .await;
```

**Errors / Panics**

- この関数自体はエラーもパニックも返しませんが、返された `RequestBuilder` の `.send().await` で `reqwest::Error` が発生しうる点は `upload_local_file` 側で考慮されています（L140-143, L173-176, L198-201）。
- `build_reqwest_client` 内部でのみ `unwrap_or_else` が使われていますが、失敗時は新しい `Client` を返すためパニックしません（L272-277）。

**Edge cases（エッジケース）**

- `bearer_token()` が `None` の場合、`Authorization` ヘッダは設定されません（L263-265）。
- `account_id()` が `None` の場合、`chatgpt-account-id` ヘッダは設定されません（L266-267）。
- タイムアウトは必ず `OPENAI_FILE_REQUEST_TIMEOUT` になります。リクエストごとにタイムアウトを変える仕組みはこの関数にはありません（L260-262）。

**使用上の注意点**

- `AuthProvider` の実装がどのようなライフタイムやスレッドセーフ性（`Send`/`Sync`）を持つかは、このチャンクには現れません。そのため、並行呼び出し時の要件は別モジュールの定義を確認する必要があります。
- `chatgpt-account-id` というヘッダ名はこのモジュールで固定で使用されています（L266-267）。

---

#### `build_reqwest_client() -> reqwest::Client` （L272-277）

**概要**

- カスタム CA 設定を行う `codex_client::build_reqwest_client_with_custom_ca` を呼び出し、失敗した場合は警告ログを出したうえで `reqwest::Client::new()` にフォールバックします（L272-277）。

**戻り値**

- `reqwest::Client` — 成功時はカスタム CA 設定済みのクライアント、失敗時はデフォルト設定のクライアントです（L272-277）。

**内部処理の流れ**

1. `reqwest::Client::builder()` を引数に `build_reqwest_client_with_custom_ca` を呼び出します（L273）。
2. 結果が `Ok(client)` の場合はそのクライアントを返します（L272-273）。
3. `Err(error)` の場合は `tracing::warn!` で警告ログを出力し（L274）、`reqwest::Client::new()` でデフォルトクライアントを返します（L275-276）。

**Examples（使用例）**

`upload_local_file` 内でアップロード PUT リクエストのために使用されています。

```rust
let upload_response = build_reqwest_client()          // カスタム CA 付きクライアントを取得 (L165-166)
    .put(&create_payload.upload_url)
    .timeout(OPENAI_FILE_REQUEST_TIMEOUT)
    // ...
    .send()
    .await;
```

**Errors / Panics**

- `build_reqwest_client_with_custom_ca` の失敗は `unwrap_or_else` 内で処理され、パニックは発生しません（L272-276）。
- `tracing::warn!` によるログ出力のみが副作用です（L274）。

**Edge cases（エッジケース）**

- カスタム CA の設定に失敗した場合でも、デフォルト CA を使ったクライアントで処理が継続されます（L273-276）。  
  そのため「証明書検証が期待どおり行われていない」状態でもアップロードが進む可能性がありますが、このファイル単体からは、想定される運用ポリシーは分かりません。

**使用上の注意点**

- セキュリティ上、カスタム CA 設定に失敗した場合にアップロード自体を止めるべきかどうかはシステム全体の要件次第です。このモジュールでは「警告ログ＋フォールバック」という方針が採られています（L272-276）。

---

### 3.3 その他の関数

| 関数名 | 役割（1 行） | 定義位置 |
|--------|--------------|----------|
| `tests::chatgpt_auth` | テスト用 `CoreAuthProvider` を生成します。`CoreAuthProvider::for_test(Some("token"), Some("account_id"))` を呼び出しています（L297-299）。 | `codex-api/src/files.rs:L297-299` |
| `tests::base_url_for` | `MockServer` の URI からテスト用 `base_url` (`"{server_uri}/backend-api"`) を作成します（L301-303）。 | `codex-api/src/files.rs:L301-303` |
| `tests::upload_local_file_returns_canonical_uri` | 一連の HTTP モックを通じて `upload_local_file` の成功パスと URI 生成を検証します（L305-369）。 | `codex-api/src/files.rs:L305-369` |

---

## 4. データフロー

ここでは、`upload_local_file (L97-252)` の代表的なデータフローをシーケンス図で示します。

```mermaid
sequenceDiagram
    autonumber

    participant Caller as 呼び出し側
    participant Files as upload_local_file (L97-252)
    participant FS as tokio::fs (metadata, File::open)
    participant Backend as backend-api (base_url)
    participant Blob as upload_url (ストレージ)

    Caller->>Files: upload_local_file(base_url, auth, path)
    activate Files

    Files->>FS: metadata(path) (L102-104)
    FS-->>Files: Metadata or Error
    alt パスが不正 / ファイルでない / サイズ超過
        Files-->>Caller: Err(OpenAiFileError::...) (L104-123)
        deactivate Files
    else 正常
        Files->>Backend: POST {base_url}/files (authorized_request) (L131-139)
        Backend-->>Files: HTTP 2xx + {"file_id","upload_url"} or Error (L144-157)
        alt 失敗
            Files-->>Caller: Err(Request/UnexpectedStatus/Decode) (L140-143, L146-151, L153-157)
            deactivate Files
        else 成功
            Files->>FS: File::open(path) (L159-161)
            FS-->>Files: File handle or Error
            alt File::open失敗
                Files-->>Caller: Err(ReadFile) (L159-164)
                deactivate Files
            else 成功
                Files->>Blob: PUT upload_url (stream body) (L165-172)
                Blob-->>Files: HTTP 2xx or Error (L177-185)
                alt 失敗
                    Files-->>Caller: Err(Request/UnexpectedStatus) (L173-176, L179-185)
                    deactivate Files
                else 成功
                    loop finalize (status = "retry" かつ timeout未満) (L193-241)
                        Files->>Backend: POST {base_url}/files/{file_id}/uploaded (L194-201)
                        Backend-->>Files: {"status", ...} or Error (L202-215)
                        alt HTTP/JSONエラー
                            Files-->>Caller: Err(Request/UnexpectedStatus/Decode) (L198-201, L205-209, L211-215)
                            deactivate Files
                        else status判定
                            alt status == "success"
                                Files-->>Caller: Ok(UploadedOpenAiFile) (L219-232)
                                deactivate Files
                            else status == "retry" かつ timeout超過
                                Files-->>Caller: Err(UploadNotReady) (L235-239)
                                deactivate Files
                            else その他status
                                Files-->>Caller: Err(UploadFailed) (L243-249)
                                deactivate Files
                            end
                        end
                    end
                end
            end
        end
    end
```

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

典型的には、以下のようなフローになります。

1. `AuthProvider` 実装を用意する（詳細はこのチャンクには現れませんが、テストでは `CoreAuthProvider::for_test` を用いています（L297-299））。
2. `base_url` をバックエンドのベース URL（`/files` を含まない）として用意する（L131, L187-191）。
3. ローカルファイルパスを `Path` で指定し、`upload_local_file` を `await` する。
4. 返ってきた `UploadedOpenAiFile` から `uri` や `download_url` を利用する（L219-232）。

```rust
use std::path::Path;
use codex_api::files::{upload_local_file, UploadedOpenAiFile};

async fn upload_example(auth: &impl codex_api::AuthProvider) -> anyhow::Result<()> {
    let base_url = "https://my-service.example.com/backend-api";  // "/files" は付けない
    let path = Path::new("docs/manual.pdf");

    let UploadedOpenAiFile {
        file_id,
        uri,
        download_url,
        file_name,
        file_size_bytes,
        mime_type,
        ..
    } = upload_local_file(base_url, auth, path).await?;           // L97-252

    println!("uploaded file_id = {file_id}");
    println!("canonical uri = {uri}");
    println!("download from = {download_url}");
    println!("name = {file_name}, size = {file_size_bytes}, mime = {:?}", mime_type);

    Ok(())
}
```

### 5.2 よくある使用パターン

- **複数ファイルの連続アップロード**

  `upload_local_file` はステートレスな関数なので、複数ファイルに対して単純なループで呼び出すことが可能です。

  ```rust
  let paths = vec!["a.txt", "b.txt", "c.txt"];
  for p in paths {
      match upload_local_file(base_url, auth, Path::new(p)).await {
          Ok(info) => println!("uploaded: {} -> {}", p, info.download_url),
          Err(err) => eprintln!("failed to upload {p}: {err}"),
      }
  }
  ```

- **ダウンロード URL ではなく URI を保存する**

  `UploadedOpenAiFile::uri` は `sediment://<file_id>` 形式で、後続コンポーネントがこの URI をキーとして使うことを想定していると解釈できます（L14, L219-222）。  
  実際にどのコンポーネントが URI を解釈するかはこのファイルからは分かりません。

### 5.3 よくある間違い

```rust
// 間違い例: base_url に "/files" を含めてしまう
let base_url = "https://example.com/backend-api/files";
// upload_local_file 内でさらに "/files" が付加され "…/files/files" になる (L131)
let result = upload_local_file(base_url, auth, path).await;

// 正しい例: base_url は "/files" を含まない
let base_url = "https://example.com/backend-api";
let result = upload_local_file(base_url, auth, path).await;
```

```rust
// 間違い例: ディレクトリパスを渡している
let path = Path::new("/tmp");            // ディレクトリ
let result = upload_local_file(base_url, auth, path).await;
// => OpenAiFileError::NotAFile が返る (L113-117)

// 正しい例: 実際のファイルパスを渡す
let path = Path::new("/tmp/file.txt");
let result = upload_local_file(base_url, auth, path).await;
```

### 5.4 使用上の注意点（まとめ）

- **Bugs/Security 観点**

  - カスタム CA 設定に失敗しても、デフォルトクライアントで通信を継続します（L272-276）。  
    厳格な TLS 検証が必要な環境では、この振る舞いが要件に合っているか確認が必要です。
  - エラーにはローカルパス（`path`）およびリモート URL とレスポンスボディが含まれます（L35-37, L53-56, L59-64）。ログやユーザ向け表示に用いる際は情報漏洩に注意します。

- **Contracts / Edge Cases**

  - パスは「存在する通常のファイル」である必要があります（L102-117）。
  - ファイルサイズは 512 MiB 以下である必要があります（L15, L118-123）。
  - `base_url` は末尾スラッシュの有無にかかわらず内部で `trim_end_matches('/')` されていますが（L131, L187-189）、`/files` を含めない前提です。
  - ファイナライズは `"success"` か `"retry"` の `status` を前提としていますが、それ以外も `UploadFailed` によって処理されます（L217-250）。

- **並行性**

  - 関数はステートレスで、共有ミュータブル状態を持たないため、異なるファイルに対して複数同時に呼び出すこと自体にコード上の制約はありません。
  - 実際の並行呼び出し可能性（`Send`/`Sync` 要件）は `AuthProvider` 実装や `reqwest` クライアントの特性に依存し、このファイル単体からは完全には分かりません。

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

例として、「アップロード済みファイルの削除 API」を追加したい場合を考えます。

1. **エラーの整理**  
   - 削除に特有のエラー（例: すでに削除済みなど）を表現したい場合は、`OpenAiFileError` に新しいバリアントを追加するのが自然です（L33-75）。
2. **新しい関数の追加場所**  
   - アップロードと同じ「ファイル API」カテゴリの処理であれば、このファイル `codex-api/src/files.rs` に `pub async fn delete_openai_file(...)` のような関数を追加するのが一貫性があります。
3. **HTTP 呼び出しの組み立て**  
   - 既存の `authorized_request` を利用して、認証付きの DELETE/POST リクエストを構築します（L254-270）。
   - レスポンスのエラー処理は `upload_local_file` のパターン（`UnexpectedStatus` / `Decode`）を踏襲すると挙動が揃います（L146-151, L153-157, L205-209, L211-215）。
4. **レスポンス用型の追加**  
   - 必要であれば `CreateFileResponse`／`DownloadLinkResponse` 同様に、モジュール内限定の `struct` を追加して `serde::Deserialize` でデコードします（L77-81, L83-91）。

### 6.2 既存の機能を変更する場合

- **影響範囲の確認**

  - `upload_local_file` は公開 API かつテストで直接利用されているため（L97-252, L356-358）、シグネチャや戻り値の構造を変更すると、呼び出し側全体に影響します。
  - `UploadedOpenAiFile` や `OpenAiFileError` は公開型なので、フィールド・バリアントの削除や意味変更は下位互換性に注意が必要です（L22-31, L33-75）。

- **契約（前提条件・返り値の意味）**

  - ファイルサイズ上限やタイムアウト値は定数として外に見えています（`OPENAI_FILE_UPLOAD_LIMIT_BYTES` は `pub`、他は `const`）。  
    アップロードの仕様として利用されている可能性があるため、変更時にはドキュメント化やマイグレーションガイドが必要になることがあります（L15, L17-19）。
  - `UploadNotReady` は「タイムアウト時に返る」契約を担っているため（L235-239）、挙動を変更する場合はこのバリアントの意味も更新する必要があります。

- **テスト・使用箇所の再確認**

  - `upload_local_file_returns_canonical_uri` テストは、`file_id`・`uri`・`download_url`・`file_name`・`mime_type`・ファイナライズのリトライ回数に依存しています（L360-368）。  
    これらの挙動を変更した場合、テストの更新が必要です。
  - 他モジュールからの呼び出しはこのチャンクには現れないため、実際の使用箇所はプロジェクト全体で検索する必要があります。

---

## 7. 関連ファイル

| パス / シンボル | 役割 / 関係 |
|-----------------|------------|
| `crate::AuthProvider` | 認証付きリクエストに必要なトレイトです。`authorized_request` と `upload_local_file` から参照され、Bearer トークンとアカウント ID を提供します（L5, L97-101, L254-268）。定義位置はこのチャンクには現れません。 |
| `crate::CoreAuthProvider` | テスト用に使用される認証プロバイダ実装です。`CoreAuthProvider::for_test` を通じてモックトークンとアカウント ID を生成しています（L282-283, L297-299）。 |
| `codex_client::build_reqwest_client_with_custom_ca` | カスタム CA 設定を行う HTTP クライアントビルダーヘルパーです。`build_reqwest_client` から呼び出されています（L6, L272-276）。内部実装はこのチャンクには現れません。 |
| `reqwest` クレート | HTTP クライアント・`RequestBuilder`・`StatusCode` などを提供し、ファイル作成・アップロード・ファイナライズの全ての HTTP 通信に使用されています（L7-8, L132-139, L165-172, L194-201, L254-270）。 |
| `tokio` / `tokio_util` | 非同期ファイル I/O (`tokio::fs::File`, `tokio::fs::metadata`) および `ReaderStream` を通じたストリーミングアップロード、時間管理 (`Instant`, `sleep`) を提供します（L10-12, L102-104, L159-161, L170, L192-193, L240-241）。 |
| `wiremock` / `tempfile` / `pretty_assertions` | テストモジュールで HTTP サーバのモック・一時ディレクトリ作成・アサーション改善のために使用されています（L287-295, L305-369）。 |

以上が、`codex-api/src/files.rs` の公開 API・コアロジック・エラー・非同期挙動・コンポーネント構造・データフローに関する解説です。
