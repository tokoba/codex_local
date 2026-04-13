# JavaScript REPL (`js_repl`)

`js_repl` は、トップレベルでの `await` が可能な、永続的な Node バックエンドのカーネル上で JavaScript を実行します。

## Feature gate

`js_repl` はデフォルトでは無効で、次の設定を行った場合にのみ有効になります。

```toml
[features]
js_repl = true
```

`js_repl_tools_only` を有効にすると、モデルからの直接のツール呼び出しを強制的に `js_repl` 経由にできます。

```toml
[features]
js_repl = true
js_repl_tools_only = true
```

有効にすると、モデルからの直接ツール呼び出しは `js_repl` と `js_repl_reset` に制限されます。その他のツールは、`js_repl` 内から `await codex.tool(...)` を通じて引き続き利用できます。

## Node runtime

`js_repl` には、`codex-rs/node-version.txt` で規定されているバージョン以上の Node が必要です。

Runtime 解決順序:

1. 環境変数 `CODEX_JS_REPL_NODE_PATH`
2. 設定 / プロファイルの `js_repl_node_path`
3. `PATH` 上で見つかった `node`

明示的なランタイムパスを設定できます:

```toml
js_repl_node_path = "/absolute/path/to/node"
```

## Module resolution

`js_repl` は、順序付けされた検索パスを用いて **ベア**な指定子（例: `await import("pkg")`）を解決します。ローカルファイルのインポートも、相対パス、絶対パス、および ESM の `.js` / `.mjs` ファイルを指す `file://` URL でサポートされます。

Module resolution は次の順序で行われます:

1. `CODEX_JS_REPL_NODE_MODULE_DIRS`（PATH 区切りのリスト）
2. 設定 / プロファイルの `js_repl_node_module_dirs`（絶対パスの配列）
3. スレッドの作業ディレクトリ（cwd。常に最後のフォールバックとして含まれます）

`CODEX_JS_REPL_NODE_MODULE_DIRS` と `js_repl_node_module_dirs` では、指定された順序でモジュール解決が試行され、前にあるエントリほど優先されます。

ベアなパッケージインポートは、インポート元がローカルファイルであっても、常にこの REPL 全体で共有される検索パスを使用します。インポートされたファイルの場所を基準に解決されることはありません。

## Usage

- `js_repl` は自由形式のツールです。生の JavaScript ソーステキストを送信してください。
- 先頭行にオプションのプラグマを指定できます:
  - `// codex-js-repl: timeout_ms=15000`
- トップレベルのバインディングは呼び出し間で保持されます。
- セルが例外を投げた場合でも、それ以前に存在していたバインディングは引き続き利用可能です。例外が発生する前に初期化が完了したレキシカルバインディングは後続の呼び出しでも利用可能なまま残り、巻き上げられた `var` / `function` のバインディングは、実行がその宣言、またはサポートされている書き込み位置に明確に到達している場合にのみ保持されます。
- 巻き上げられた `var` について、セルが失敗した場合にサポートされるケースは、宣言より前のトップレベルでの識別子への直接書き込み・更新（例: `x = 1`, `x += 1`, `x++`, `x &&= 1`）と、空でないトップレベルの `for...in` / `for...of` ループです。
- 意図的に未サポートとされている失敗セルのケースには、宣言より前の巻き上げられた関数の読み取り、エイリアスや直接 IIFE に基づく推論、ネストされたブロックやその他のネストした文構造内での書き込み、すでにインストルメントされた代入式の右辺（RHS）内でのネストした書き込み、巻き上げられた `var` に対する分割代入の復元、`var` の部分的な分割代入の復元、宣言前の `undefined` 読み取り、空のトップレベル `for...in` / `for...of` ループ変数などが含まれます。
- トップレベルの静的な import 宣言（例: `import x from "pkg"`）は現在サポートされていません。代わりに `await import("pkg")` を使った動的インポートを利用してください。
- インポートされるローカルファイルは ESM 形式の `.js` / `.mjs` ファイルである必要があり、呼び出し元のセルと同じ REPL の VM コンテキストで実行されます。
- インポートされたローカルファイル内の静的な import は、相対パス、絶対パス、または `file://` URL 経由で、他のローカルの `.js` / `.mjs` ファイルのみを対象にできます。ローカルファイルからのベアなパッケージインポートや組み込みモジュールのインポートは、`await import(...)` を使った動的インポートのままでなければなりません。
- `import.meta.resolve()` は、`file://...`、ベアなパッケージ名、`node:fs` などのインポート可能な文字列を返します。返された値は `await import(...)` にそのまま渡せます。
- ローカルファイルのモジュールは実行の間で再読み込みされるため、後から行う `await import("./file.js")` では、編集や修正済みの失敗が反映されます。すでに作成したトップレベルのバインディングは、`js_repl_reset` が実行されるまで保持されます。
- カーネルの状態をクリアするには `js_repl_reset` を使用します。

## Helper APIs inside the kernel

`js_repl` は次のグローバル変数／関数を公開します:

- `codex.cwd`: REPL の作業ディレクトリのパス。
- `codex.homeDir`: カーネル環境における有効なホームディレクトリのパス。
- `codex.tmpDir`: セッションごとの一時ディレクトリのパス。
- `codex.tool(name, args?)`: `js_repl` 内から通常の Codex ツール呼び出しを実行します（利用可能な場合は `shell` / `shell_command` のようなシェルツールも含みます）。
- `codex.emitImage(imageLike)`: 呼び出すたびに、外側の `js_repl` 関数の出力に画像を 1 枚明示的に追加します。
- `codex.tool(...)` と `codex.emitImage(...)` は、セルをまたいでも安定したヘルパーとして同一の識別性を保ちます。保存した参照や永続化されたオブジェクトは、後続のセルでもこれらを再利用できますが、セルの終了後に発火する非同期コールバックからの呼び出しは、実行中のコンテキストが存在しないため失敗します。
- インポートされたローカルファイルは同じ VM コンテキストで実行されるため、`codex.*`、捕捉された `console`、Node 風の `import.meta` ヘルパーにもアクセスできます。
- 各 `codex.tool(...)` 呼び出しは、`codex_core::tools::js_repl` ロガーから `info` レベルで制限付きのサマリーを出力します。`trace` レベルでは、同じパスから JavaScript から見える生のレスポンスオブジェクトまたはエラー文字列をそのままログに出力します。
- ネストされた `codex.tool(...)` の出力は、明示的に出力しない限り JavaScript 内部にとどまります。
- `codex.emitImage(...)` は、Data URL、単一の `input_image` アイテム、`{ bytes, mimeType }` のようなオブジェクト、あるいは 1 枚の画像のみを含みテキストを含まない生のツールレスポンスオブジェクトを受け付けます。複数の画像を出力したい場合は、複数回呼び出してください。
- `codex.emitImage(...)` は、テキストと画像が混在するコンテンツは受け付けません。
- `view_image` ツールのスキーマに `detail` 引数が含まれている場合にのみ、`detail: "original"` を指定してフル解像度での画像処理を要求してください。同じ条件は `codex.emitImage(...)` にも適用されます。`view_image.detail` が存在する場合、`codex.emitImage(...)` にも `detail: "original"` を渡すことができます。これは、高精度な画像認識や厳密な位置特定が必要なとき、特に CUA エージェントに対して推奨されます。
- メモリ上の Playwright スクリーンショットを共有する例: `await codex.emitImage({ bytes: await page.screenshot({ type: "jpeg", quality: 85 }), mimeType: "image/jpeg", detail: "original" })`。
- ローカル画像ツールの結果を共有する例: `await codex.emitImage(codex.tool("view_image", { path: "/absolute/path", detail: "original" }))`。
- `codex.emitImage(...)` や `view_image` で送信する画像をエンコードする際、非可逆圧縮で問題ない場合は品質 85 前後の JPEG を優先してください。透過やロスレスなディテールが重要な場合は PNG を使用します。アップロードするデータが小さいほど、高速で処理でき、サイズ制限に抵触しにくくなります。

`process.stdout` / `process.stderr` / `process.stdin` へ直接書き込むことは避けてください。カーネルは stdio 上で JSON 行ベースのトランスポートを使用しています。

## Debug logging

ネストされた `codex.tool(...)` の診断情報は、ロールアウト履歴ではなく通常の `tracing` 出力を通じて出力されます。

- `info` レベルでは制限付きのサマリーがログに出力されます。
- `trace` レベルでは、JavaScript から見えるシリアライズ済みのレスポンスオブジェクトやエラー文字列がそのままログに出力されます。

`codex app-server` の場合、これらのログはサーバープロセスの `stderr` に書き出されます。

例:

```sh
RUST_LOG=codex_core::tools::js_repl=info \
LOG_FORMAT=json \
codex app-server \
2> /tmp/codex-app-server.log
```

```sh
RUST_LOG=codex_core::tools::js_repl=trace \
LOG_FORMAT=json \
codex app-server \
2> /tmp/codex-app-server.log
```

In both cases, inspect `/tmp/codex-app-server.log` or whatever sink captures the process `stderr`.

## ベンダー提供のパーサーアセット (`meriyah.umd.min.js`)

カーネルは、ベンダー提供の Meriyah バンドルを次の場所に埋め込んでいます:

- `codex-rs/core/src/tools/js_repl/meriyah.umd.min.js`

現在のソースは npm の `meriyah@7.0.0`（`dist/meriyah.umd.min.js`）です。
ライセンス情報は次の場所で管理されています:

- `third_party/meriyah/LICENSE`
- `NOTICE`

### このファイルの取得方法

クリーンな一時ディレクトリから実行します:

```sh
tmp="$(mktemp -d)"
cd "$tmp"
npm pack meriyah@7.0.0
tar -xzf meriyah-7.0.0.tgz
cp package/dist/meriyah.umd.min.js /path/to/repo/codex-rs/core/src/tools/js_repl/meriyah.umd.min.js
cp package/LICENSE.md /path/to/repo/third_party/meriyah/LICENSE
```

### 新しいバージョンへの更新方法

1. 上記のコマンド内の `7.0.0` を、対象のバージョンに置き換えます。
2. 新しい `dist/meriyah.umd.min.js` を `codex-rs/core/src/tools/js_repl/meriyah.umd.min.js` にコピーします。
3. パッケージのライセンスファイルを `third_party/meriyah/LICENSE` にコピーします。
4. `meriyah.umd.min.js` 先頭のヘッダーコメント内のバージョン文字列を更新します。
5. 上流の著作権表示が変更されている場合は、`NOTICE` を更新します。
6. 該当する `js_repl` のテストを実行します。
