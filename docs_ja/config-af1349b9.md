# 設定

基本的な設定手順については、[こちらのドキュメント](https://developers.openai.com/codex/config-basic) を参照してください。

高度な設定手順については、[こちらのドキュメント](https://developers.openai.com/codex/config-advanced) を参照してください。

すべての設定項目のリファレンスについては、[こちらのドキュメント](https://developers.openai.com/codex/config-reference) を参照してください。

## MCP サーバーへの接続

Codex は、`~/.codex/config.toml` で設定された MCP サーバーに接続できます。最新の MCP サーバーオプションについては、設定リファレンスを参照してください:

- <https://developers.openai.com/codex/config-reference>

## MCP ツールの承認

Codex は、カスタム MCP サーバーに対するツールごとの承認の上書き設定を
`~/.codex/config.toml` の `mcp_servers` 配下に保存します:

```toml
[mcp_servers.docs.tools.search]
approval_mode = "approve"
```

## Apps（コネクタ）

composer で `$` を使用して ChatGPT コネクタを挿入すると、ポップオーバーにアクセス可能な
アプリが一覧表示されます。`/apps` コマンドは、利用可能なアプリとインストール済みのアプリを一覧表示します。接続済みのアプリは先頭に表示され
「connected」とラベル付けされます。それ以外は「can be installed」としてマークされます。

## Notify

Codex は、エージェントがターンを終了したときに通知フックを実行できます。最新の通知設定については、設定リファレンスを参照してください:

- <https://developers.openai.com/codex/config-reference>

Codex がどのクライアントによってターンが開始されたかを把握している場合、レガシーな notify JSON ペイロードには、トップレベルの `client` フィールドも含まれます。TUI は `codex-tui` を報告し、アプリサーバーは `initialize` からの `clientInfo.name` の値を報告します。

## JSON Schema

`config.toml` 用に生成された JSON Schema は `codex-rs/core/config.schema.json` に配置されます。

## SQLite ステート DB

Codex は、SQLite バックエンドのステート DB を `sqlite_home`（設定キー）または
`CODEX_SQLITE_HOME` 環境変数で指定された場所に保存します。未設定の場合、WorkspaceWrite サンドボックス
セッションはデフォルトで一時ディレクトリを使用し、その他のモードはデフォルトで `CODEX_HOME` を使用します。

## カスタム CA 証明書

Codex は、外向きの HTTPS およびセキュア WebSocket
接続に対して、エンタープライズプロキシやゲートウェイが TLS をインターセプトする場合にカスタムのルート CA バンドルを信頼できるようにします。これは
ログインフローおよび Codex のその他の外部接続にも適用され、
そこには、共有の `codex-client` の CA ロードパスを通じて reqwest クライアントまたはセキュア WebSocket クライアントを構築する Codex コンポーネントや、
それを利用するリモート MCP 接続が含まれます。

`CODEX_CA_CERTIFICATE` に、1 つ以上の証明書ブロックを含む PEM ファイルのパスを設定すると、
Codex 固有の CA バンドルを使用できます。`CODEX_CA_CERTIFICATE` が未設定の場合、
Codex は `SSL_CERT_FILE` にフォールバックします。
どちらの変数も設定されていない場合、Codex はシステムのルート証明書を使用します。

`CODEX_CA_CERTIFICATE` は `SSL_CERT_FILE` より優先されます。空の値は
未設定として扱われます。

PEM ファイルには複数の証明書を含めることができます。Codex は OpenSSL の
`TRUSTED CERTIFICATE` ラベルも許容し、同じバンドル内に含まれる正しい形式の `X509 CRL` セクションは
無視します。ファイルが空であるか、読み取れないか、不正な形式の場合、影響を受ける Codex
の HTTP またはセキュア WebSocket 接続は、これらの環境変数を指し示すユーザー向けのエラーを
報告します。

## 通知

Codex は、一部の UI プロンプトに対する「do not show again」フラグを `[notice]` テーブル配下に保存します。

## Plan モードのデフォルト

`plan_mode_reasoning_effort` によって、Plan モード固有の既定の推論負荷を
上書き設定できます。未設定の場合、Plan モードは組み込みの Plan プリセットの既定値
（現在は `medium`）を使用します。明示的に設定された場合（`none` を含む）、これは
Plan プリセットを上書きします。文字列値 `none` は「推論なし」（Plan を明示的に上書き）を意味し、
「グローバルなデフォルトを継承する」という意味ではありません。現在、
「Plan モードでグローバルなデフォルトに従う」ための個別の設定値は存在しません。

## Realtime 開始時の指示

`experimental_realtime_start_instructions` によって、組み込みの
realtime が有効になったときに Codex が挿入する開発者向けメッセージを置き換えることができます。これは
プロンプト履歴内の realtime 開始メッセージのみに影響し、websocket
バックエンドのプロンプト設定や realtime 終了/非アクティブメッセージは変更しません。

Ctrl+C/Ctrl+D で終了する場合には、約 1 秒以内の二度押しを促すヒント（`ctrl + c again to quit`）が使用されます。
