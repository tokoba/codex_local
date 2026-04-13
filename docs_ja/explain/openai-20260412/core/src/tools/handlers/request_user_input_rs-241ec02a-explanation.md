# core/src/tools/handlers/request_user_input.rs

## 0. ざっくり一言

`RequestUserInputHandler` は、「request_user_input」ツール呼び出しを処理し、  
セッションにユーザー入力を要求して、その結果を JSON テキストとして呼び出し元に返すハンドラです。  
（根拠: `RequestUserInputHandler` 定義と `handle` 実装全体  
core/src/tools/handlers/request_user_input.rs:L14-16, L25-75）

---

## 1. このモジュールの役割

### 1.1 概要

- このモジュールは **「ツール呼び出し」から「セッションを通じたユーザー入力要求」への橋渡し** を行います。
- `ToolInvocation` に含まれるペイロードやセッション情報を検証し、ユーザーに入力を求めるべきかどうかを判定します。（L25-32, L34-55）
- 実際に `session.request_user_input(...)` を呼び出し、そのレスポンスを JSON 文字列にして `FunctionToolOutput` として返します。（L59-75）

### 1.2 アーキテクチャ内での位置づけ

このファイル内のコンポーネントと、直接依存している型／関数との関係は概ね次のようになっています。

```mermaid
graph TD
  subgraph "request_user_input.rs (handle L25-75)"
    R[RequestUserInputHandler<br/>ToolHandler実装]
  end

  TI[ToolInvocation<br/>(session, turn, call_id, payload)] --> R
  R -->|実装| ToolHandler
  R -->|種別を返す| TK[ToolKind::Function]

  R -->|match| TP[ToolPayload::Function { arguments }]
  R -->|使用| SA[SessionSource::SubAgent]    
  R -->|使用| RA[RequestUserInputArgs]

  R -->|呼び出し| PA[parse_arguments(&arguments)]
  R -->|呼び出し| NU[normalize_request_user_input_args]
  R -->|呼び出し| UM[request_user_input_unavailable_message]

  R -->|await| SC[session.collaboration_mode()]
  R -->|await| SR[session.request_user_input(turn, call_id, args)]

  R -->|シリアライズ| SJ[serde_json::to_string(response)]
  R -->|ラップ| FO[FunctionToolOutput::from_text]

  R -->|エラー型| FE[FunctionCallError]
```

- すべての矢印は、このファイルに現れる実際の呼び出し／依存関係に基づきます。（L1-12, L18-75）
- `session` や `turn` の具体的な型定義・実装は、このチャンクには現れないため不明です。

### 1.3 設計上のポイント

コードから読み取れる設計上の特徴は次の通りです。

- **ToolHandler 実装としての分離**  
  - `RequestUserInputHandler` は `ToolHandler` トレイトを実装しており、このハンドラ単体で「request_user_input」ツールの処理を完結します。（L18-23）
- **ステートレスに近い構造**  
  - 構造体フィールドは `default_mode_request_user_input: bool` のみで、処理時に更新されません。ハンドラは実質的に不変の設定を参照するだけです。（L14-16）
- **非同期処理**  
  - `handle` は `async fn` であり、`session.collaboration_mode().await` と `session.request_user_input(...).await` を用いて非同期的に外部コンポーネントとやり取りします。（L25, L49-49, L59-61）
- **エラーハンドリングの方針**  
  - 利用者／モデルに返すべきエラーは `FunctionCallError::RespondToModel` として扱い、  
    内部エラー（JSON シリアライズ失敗など）は `FunctionCallError::Fatal` として区別しています。（L37-39, L43-47, L53, L58, L63-65, L68-71）

---

## 2. 主要な機能一覧（コンポーネントインベントリー）

このファイル内で定義されている構造体・関数・モジュールの一覧です。

| 名前 | 種別 | 公開範囲 | 役割 / 用途 | 行範囲 |
|------|------|----------|-------------|--------|
| `RequestUserInputHandler` | 構造体 | `pub` | request_user_input ツールを処理するハンドラ本体。設定として `default_mode_request_user_input` を保持。 | L14-16 |
| `impl ToolHandler for RequestUserInputHandler` | トレイト実装 | crate 内から利用 | ツール種別を返す `kind` と、実際のツール処理を行う `handle` を提供。 | L18-75 |
| `kind(&self)` | メソッド | `ToolHandler` 経由 | このハンドラが処理するツールの種別として `ToolKind::Function` を返す。 | L21-23 |
| `handle(&self, invocation: ToolInvocation)` | `async fn` メソッド | `ToolHandler` 経由 | ツール呼び出しを検証し、ユーザー入力を要求し、その結果を `FunctionToolOutput` にして返すコアロジック。 | L25-75 |
| `tests` | モジュール | テスト時のみ | 同名ファイル `request_user_input_tests.rs` を参照するテストモジュール。内容はこのチャンクには現れない。 | L78-80 |

このファイル固有の公開 API は `RequestUserInputHandler` 構造体ですが、実際には `ToolHandler` トレイトを介して `kind` / `handle` が外部から呼び出される設計と解釈できます。（L18-23）

主要な機能（振る舞い）を箇条書きにすると次の通りです。

- ツールペイロードの型チェックとエラー応答（L34-41）
- SubAgent からの呼び出し禁止の強制（L43-47）
- コラボレーションモードに応じた request_user_input 利用可否の判定（L49-55）
- ツール引数の JSON パースおよび正規化（L56-58）
- セッションを通じたユーザー入力要求と、キャンセル検知（L59-66）
- ユーザー入力レスポンスの JSON シリアライズと出力形式への変換（L68-75）

---

## 3. 公開 API と詳細解説

### 3.1 型一覧（構造体・列挙体など）

| 名前 | 種別 | フィールド / 概要 | 行範囲 |
|------|------|-------------------|--------|
| `RequestUserInputHandler` | 構造体 | `default_mode_request_user_input: bool` — デフォルトの協調モードにおいて `request_user_input` を許可するかどうかの設定値と解釈できるが、具体的意味はこのチャンクからは断定できません。 | L14-16 |

※ フィールドの意味は `request_user_input_unavailable_message(mode, self.default_mode_request_user_input)` に渡していることから、  
  「モードと設定に基づき利用可否メッセージを決めるフラグ」であると想定できますが、詳細な意味や値域はこのファイルからは分かりません。（L50-52）

---

### 3.2 関数詳細

このファイルで重要度が高いのは `handle` メソッドです。これをテンプレートに沿って詳しく説明します。

#### `handle(&self, invocation: ToolInvocation) -> Result<FunctionToolOutput, FunctionCallError>`

**概要**

- request_user_input ツール呼び出しのメイン処理です。（L25）
- 受け取った `ToolInvocation` を分解し、ペイロードの形式・セッションの状態（コラボレーションモード、SubAgent かどうか）をチェックします。（L25-55）
- ユーザー入力の要求をセッションに投げ、そのレスポンスを JSON 文字列にして `FunctionToolOutput` として返します。（L59-75）

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `self` | `&RequestUserInputHandler` | ハンドラ自身。設定フィールド `default_mode_request_user_input` を参照します。（L50-52） |
| `invocation` | `ToolInvocation` | ツール呼び出しコンテキスト。`session`, `turn`, `call_id`, `payload` などを含みます。（L26-32） |

`ToolInvocation` の具体的なフィールド型（`session` や `turn` の型）はこのチャンクには現れませんが、`session` は `collaboration_mode` と `request_user_input` メソッドを持つ非同期コンポーネントであることが分かります。（L49, L59-61）

**戻り値**

- `Result<FunctionToolOutput, FunctionCallError>`  
  - `Ok(FunctionToolOutput)`  
    - ユーザー入力のレスポンスをシリアライズした JSON テキストを保持しています。（L68-75）
  - `Err(FunctionCallError)`  
    - 入力ペイロード不正、利用不可モード、SubAgent からの呼び出し、引数パース失敗、正規化失敗、ユーザーキャンセル、シリアライズ失敗など、さまざまなエラー状態を表します。（L34-41, L43-47, L50-54, L56-58, L62-66, L68-71）

**内部処理の流れ（アルゴリズム）**

1. `ToolInvocation` を分解  
   - 構造体パターンで `session`, `turn`, `call_id`, `payload` を取り出します。（L26-32）

2. ペイロード型のチェック  
   - `match payload` で `ToolPayload::Function { arguments }` の場合のみ受理し、それ以外は `FunctionCallError::RespondToModel` を返して終了します。（L34-41）

3. SubAgent 呼び出しの禁止  
   - `matches!(turn.session_source, SessionSource::SubAgent(_))` で、SubAgent からの呼び出しであれば、  
     `"request_user_input can only be used by the root thread"` というメッセージ付きエラーを返します。（L43-47）

4. コラボレーションモードに応じた利用可否判定  
   - `session.collaboration_mode().await.mode` でモードを取得し、`request_user_input_unavailable_message(mode, self.default_mode_request_user_input)` を呼び出します。（L49-52）  
   - `Some(message)` が返ってきた場合は、`FunctionCallError::RespondToModel(message)` としてエラー終了します。（L50-54）

5. 引数のパースと正規化  
   - `parse_arguments(&arguments)?` で、`arguments` から `RequestUserInputArgs` に変換します。（L56）  
   - `normalize_request_user_input_args(args)` で正規化を行い、ここでのエラーは `map_err(FunctionCallError::RespondToModel)` によってユーザー向けエラーとして扱われます。（L58）

6. ユーザー入力要求の送信  
   - `session.request_user_input(turn.as_ref(), call_id, args).await` で実際にユーザー入力を要求します。（L59-61）  
   - 戻り値は `Option<_>` であり、`None` の場合は  
     `"{REQUEST_USER_INPUT_TOOL_NAME} was cancelled before receiving a response"`  
     というメッセージ付き `FunctionCallError::RespondToModel` を返します。（L62-66）

7. レスポンスのシリアライズと出力生成  
   - `serde_json::to_string(&response)` でレスポンスを JSON 文字列に変換します。ここでのエラーは `FunctionCallError::Fatal` として扱われます。（L68-71）  
   - 問題なければ `FunctionToolOutput::from_text(content, Some(true))` を `Ok` で返します。（L74-75）

**Flowchart（非同期ハンドラの処理フロー）**

```mermaid
flowchart TD
  A[handle 呼び出し<br/>(L25)] --> B[ToolInvocation 分解<br/>(L26-32)]
  B --> C{payload は<br/>Function? (L34-41)}
  C -- いいえ --> E1[Err RespondToModel<br/>unsupported payload<br/>(L37-39)]
  C -- はい --> D[SubAgent 呼び出し? (L43-47)]
  D -- はい --> E2[Err RespondToModel<br/>root thread のみ使用可<br/>(L43-47)]
  D -- いいえ --> F[collaboration_mode 取得<br/>(L49)]
  F --> G{unavailable_message? (L50-52)}
  G -- Some --> E3[Err RespondToModel<br/>message (L50-54)]
  G -- None --> H[parse_arguments (L56)]
  H --> I[normalize_request_user_input_args (L58)]
  I --> J[session.request_user_input<br/>await (L59-61)]
  J --> K{response あり? (L62-66)}
  K -- なし(None) --> E4[Err RespondToModel<br/>cancelled message (L62-66)]
  K -- あり(Some) --> L[serde_json::to_string (L68-71)]
  L --> M[Ok(FunctionToolOutput::from_text)<br/>(L74-75)]
```

**Examples（使用例）**

> 注: `ToolInvocation`, `session`, `turn` などの具体的な型定義はこのチャンクには現れません。  
> 以下は典型的な呼び出しイメージを示す擬似コードです。

```rust
use crate::tools::handlers::request_user_input::RequestUserInputHandler;
use crate::tools::context::{ToolInvocation, ToolPayload};
use crate::tools::registry::ToolHandler;
use codex_tools::REQUEST_USER_INPUT_TOOL_NAME;

// ハンドラの生成（設定値は適宜）                           // ハンドラを構造体リテラルで生成
let handler = RequestUserInputHandler {                   // 公開フィールドなので直接初期化可能
    default_mode_request_user_input: true,                // デフォルトモードで request_user_input を許可すると仮定
};

// ToolInvocation の生成（実際のフィールドはこのチャンクでは不明）
let invocation = ToolInvocation {
    // session, turn, call_id などを上位レイヤで構築
    payload: ToolPayload::Function {
        arguments: r#"{"prompt": "コメントを入力してください"}"#.to_string(),
    },
    // .. 他のフィールド
};

// 非同期コンテキスト内で handle を呼び出す
let result = handler.handle(invocation).await;            // async fn なので await が必要

match result {
    Ok(output) => {
        // output からユーザー入力結果（JSON テキスト）を取り出して利用
        let text = output.text();                         // 実際のメソッドはこのチャンクには現れない
        println!("ユーザー入力レスポンス: {text}");
    }
    Err(err) => {
        // FunctionCallError を上位で処理
        eprintln!("request_user_input ツールエラー: {err:?}");
    }
}
```

**Errors / Panics**

この関数は明示的な `panic!` は含んでおらず、エラーはすべて `Result` 経由で返しています。

発生し得る `Err(FunctionCallError)` のケース:

1. **ペイロード種別が Function でない**  
   - 条件: `payload` が `ToolPayload::Function { .. }` 以外。（L34-41）  
   - エラー: `FunctionCallError::RespondToModel`  
     - メッセージ: `"{REQUEST_USER_INPUT_TOOL_NAME} handler received unsupported payload"`（L37-39）

2. **SubAgent からの呼び出し**  
   - 条件: `matches!(turn.session_source, SessionSource::SubAgent(_))` が真。（L43-47）  
   - エラー: `FunctionCallError::RespondToModel`  
     - メッセージ: `"request_user_input can only be used by the root thread"`（L43-47）

3. **コラボレーションモードにより利用不可**  
   - 条件: `request_user_input_unavailable_message(mode, self.default_mode_request_user_input)` が `Some(message)` を返す。（L50-52）  
   - エラー: `FunctionCallError::RespondToModel(message)`（L53）

4. **引数パース失敗**  
   - 条件: `parse_arguments(&arguments)` が `Err` を返す。（L56）  
   - エラー: 型は `parse_arguments` の実装に依存しますが、`?` によって `FunctionCallError` にマップされて `Err` になります。（L56）  
     - 具体的なエラーメッセージはこのチャンクには現れません。

5. **引数正規化の失敗**  
   - 条件: `normalize_request_user_input_args(args)` が `Err(err)` を返す。（L58）  
   - エラー: `FunctionCallError::RespondToModel(err)`（L58）

6. **ユーザー入力要求がキャンセルされた**  
   - 条件: `session.request_user_input(...).await` が `None` を返す。（L59-66）  
   - エラー: `FunctionCallError::RespondToModel`  
     - メッセージ: `"{REQUEST_USER_INPUT_TOOL_NAME} was cancelled before receiving a response"`（L63-65）

7. **レスポンスの JSON シリアライズ失敗**  
   - 条件: `serde_json::to_string(&response)` が `Err(err)` を返す。（L68-71）  
   - エラー: `FunctionCallError::Fatal`  
     - メッセージ: `"failed to serialize {REQUEST_USER_INPUT_TOOL_NAME} response: {err}"`（L69-71）

**Edge cases（エッジケース）**

- **ペイロードが Function 以外**  
  - すべての非対応ペイロード種別で、同じメッセージの `RespondToModel` エラーになります。（L34-41）
- **SubAgent からの呼び出し**  
  - SubAgent 用セッションソースであれば、早期にエラーとなり、後続の処理（モードチェックやセッションへのリクエスト）は実行されません。（L43-47）
- **コラボレーションモードによる制限**  
  - 具体的なモード値や条件はこのチャンクには現れませんが、どのようなモードでも一度 `unavailable_message` を通過するため、  
    「デフォルトモードでは許可するが他のモードでは拒否する」といったロジックを実装しやすい構造になっています。（L49-52）
- **ユーザーが入力を行わずにキャンセルした場合**  
  - `session.request_user_input` の戻り値が `None` のとき、その状態を「キャンセル」とみなし、明示的メッセージを返しています。（L62-66）
- **レスポンスが JSON 化できない場合**  
  - ここは `Fatal` エラーとして扱われ、モデル向けではなくシステムレベルの障害として扱われます。（L68-71）

**使用上の注意点**

- `handle` は `async fn` のため、必ず非同期コンテキスト（`tokio` などのランタイム上）から `.await` 付きで呼び出す必要があります。（L25, L49, L59-61）
- `ToolInvocation` の `payload` は必ず `ToolPayload::Function { arguments }` になるように構築する必要があります。（L34-41）
- SubAgent から `request_user_input` を呼び出すと必ずエラーになるため、コールチェーン設計時に「root thread のみがユーザー入力ツールを使う」ことを前提とした設計が必要です。（L43-47）
- `normalize_request_user_input_args` で弾かれないよう、引数スキーマに従った JSON を `arguments` に渡す必要があります。（L56-58）
- レスポンスは JSON 文字列として `FunctionToolOutput` に格納されるため、呼び出し元側で適切にデシリアライズする設計が必要です。（L68-75）

---

### 3.3 その他の関数

`kind` メソッドは単純な識別用メソッドです。

| 関数名 | 役割（1 行） | 行範囲 |
|--------|--------------|--------|
| `kind(&self) -> ToolKind` | このハンドラが扱うツール種別として `ToolKind::Function` を返す。 | L21-23 |

---

## 4. データフロー

ここでは、`handle` メソッドが呼び出されてから `FunctionToolOutput` を返すまでの代表的なデータフローを示します。

### 4.1 処理の要点

- 上位レイヤー（ツール実行エンジン）が `ToolInvocation` を生成し、`RequestUserInputHandler::handle` を呼び出します。
- ハンドラはペイロード（JSON 文字列）から `RequestUserInputArgs` を組み立て、セッションにユーザー入力をリクエストします。（L34-36, L56-59）
- セッションから受け取ったレスポンスを JSON テキストとしてシリアライズし、`FunctionToolOutput` として返却します。（L68-75）

### 4.2 シーケンス図

```mermaid
sequenceDiagram
    participant Caller as 呼び出し元エンジン
    participant Handler as RequestUserInputHandler<br/>handle (L25-75)
    participant Session as session<br/>(型は不明)
    participant Tools as codex_tools<br/>& helpers

    Caller->>Handler: handle(invocation)
    activate Handler

    Handler->>Handler: ToolInvocation 分解 (L26-32)
    Handler->>Handler: payload種別チェック (L34-41)
    Handler->>Handler: SessionSourceチェック (L43-47)

    Handler->>Session: collaboration_mode().await (L49)
    Session-->>Handler: mode

    Handler->>Tools: request_user_input_unavailable_message(mode, default_flag) (L50-52)
    Tools-->>Handler: Option<message>

    alt 利用不可 (Some(message))
        Handler-->>Caller: Err RespondToModel(message) (L53)
        deactivate Handler
    else 利用可 (None)
        Handler->>Tools: parse_arguments(&arguments) (L56)
        Tools-->>Handler: RequestUserInputArgs

        Handler->>Tools: normalize_request_user_input_args(args) (L58)
        Tools-->>Handler: normalized_args

        Handler->>Session: request_user_input(turn, call_id, normalized_args).await (L59-61)
        Session-->>Handler: Option<response>

        alt responseがNone
            Handler-->>Caller: Err RespondToModel("...cancelled...") (L62-66)
            deactivate Handler
        else responseがSome
            Handler->>Tools: serde_json::to_string(&response) (L68-71)
            Tools-->>Handler: content(JSON文字列)

            Handler-->>Caller: Ok(FunctionToolOutput::from_text(content, Some(true))) (L74-75)
            deactivate Handler
        end
    end
```

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

このモジュールを利用する典型的なフローは次のようになります。

1. `RequestUserInputHandler` を設定付きで生成する。（L14-16）
2. 上位レイヤーで `ToolInvocation` を組み立て、`payload` に `ToolPayload::Function { arguments }` を設定する。（L34-36）
3. 非同期コンテキストで `handler.handle(invocation).await` を呼び出す。（L25）
4. 戻り値の `FunctionToolOutput` から JSON 文字列を取得し、必要に応じてパースして利用する。（L68-75）

擬似コード例（実際の型の詳細はこのチャンクには現れません）:

```rust
async fn handle_request_user_input_tool(invocation: ToolInvocation)
    -> Result<FunctionToolOutput, FunctionCallError>
{
    let handler = RequestUserInputHandler {
        default_mode_request_user_input: true, // 設定値
    };

    handler.handle(invocation).await
}
```

### 5.2 よくある使用パターン

- **デフォルトモードのみでユーザー入力を許可したい場合**  
  - `default_mode_request_user_input` を `true` にし、`request_user_input_unavailable_message` の実装側で「その他のモードではメッセージを返す」ようにする構成が想定できます。（L14-16, L50-52）
- **ツール引数を柔軟に指定したい場合**  
  - `arguments` に JSON 文字列を渡し、`RequestUserInputArgs` と `normalize_request_user_input_args` の実装でオプション項目やデフォルト値を扱う設計がとれます。（L9, L56-58）

（これらの詳細な挙動は `RequestUserInputArgs` や `normalize_request_user_input_args` の実装に依存し、このチャンクには現れないため不明です。）

### 5.3 よくある間違い

このコードから推測できる誤用例と正しい使用例です。

```rust
// 誤り例: Functionペイロード以外で呼び出す
let invocation = ToolInvocation {
    payload: ToolPayload::SomeOtherVariant,  // Function ではない
    // ...
};
// -> handle は "unsupported payload" の RespondToModel エラーを返す（L34-41）

// 正しい例: FunctionペイロードでJSON文字列を渡す
let invocation = ToolInvocation {
    payload: ToolPayload::Function {
        arguments: r#"{"prompt": "入力してください"}"#.to_string(),
    },
    // ...
};
```

```rust
// 誤り例: SubAgent から呼び出す
// turn.session_source が SessionSource::SubAgent(_) になっているケース
// -> handle は "request_user_input can only be used by the root thread" を返す（L43-47）

// 正しい例: root thread の turn から呼び出す
// turn.session_source が SubAgent 以外になるように設計する必要がある
```

### 5.4 使用上の注意点（まとめ）

- `handle` は `async` であるため、同期コンテキストから直接呼び出すことはできません。（L25）
- `payload` のバリアント、`turn.session_source` の値、コラボレーションモードなど、複数の前提条件を満たさないとエラーが返るため、呼び出し側の設計時にこれらの条件を満たすようにする必要があります。（L34-55）
- `session.request_user_input` が `None` を返すケースを「キャンセル」とみなし、ユーザー／モデルに分かる文言で返しているため、上位レイヤーではこのエラーを単なる失敗ではなく「ユーザーキャンセル」という意味として扱う設計が望ましいです。（L62-66）
- レスポンスは JSON 文字列として返るため、その形式に合わせて後段の処理を設計することが重要です。（L68-75）

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

このファイルに新しい機能を追加する典型的なパターンは次のようになります。

1. **エラー条件やメッセージを拡張したい場合**
   - 例えば、特定の `RequestUserInputArgs` の値に応じて別の制約をかけたい場合、  
     `normalize_request_user_input_args` の前後に追加の検証ロジックを挿入することが自然です。（L56-58）
   - 新たな検証でエラーとなる場合は、既存と同様に `FunctionCallError::RespondToModel` を返すことで、  
     モデル向けの分かりやすいエラーとして扱えます。

2. **レスポンスの出力形式を変更したい場合**
   - 現在は `serde_json::to_string(&response)` と `FunctionToolOutput::from_text(content, Some(true))` 固定です。（L68-75）  
   - 例えば、構造化形式の `FunctionToolOutput` を導入したい場合は、この部分を差し替えるのが入口となります。

### 6.2 既存の機能を変更する場合

変更時に注意すべき点:

- **契約（前提条件・返り値）の維持**
  - `handle` は「ペイロード種別の検証」「SubAgent の拒否」「モードに応じた利用可否」「キャンセルを None で判定」といった契約を暗黙に持っています。（L34-55, L62-66）  
  - これらの条件を変更する場合、他のツールハンドラや上位レイヤーがこれらの前提に依存していないか確認する必要があります。

- **エラー種別の意味**
  - JSON シリアライズ失敗だけが `FunctionCallError::Fatal` になっており、他は `RespondToModel` か（おそらく） `parse_arguments` 由来の `FunctionCallError` です。（L56, L68-71）  
  - `Fatal` を増やす／減らす場合は、「どのエラーがモデルに返されるべきか」というシステム全体の設計ポリシーに注意する必要があります。

- **テストの更新**
  - `#[cfg(test)]` `mod tests;` で別ファイルのテストが参照されているため、振る舞いを変更した際には `request_user_input_tests.rs` 側も更新する必要があります。（L78-80）  
  - テストファイルの内容はこのチャンクには現れないため、具体的な修正箇所は不明です。

---

## 7. 関連ファイル

このモジュールと密接に関係する可能性が高いファイル・外部コンポーネントを一覧にします。  
（パスや役割は、このチャンクの `use` 文から読み取れる範囲のみを記載します。L1-12）

| パス / シンボル | 役割 / 関係 |
|----------------|------------|
| `crate::function_tool::FunctionCallError` | ツール実行時のエラー型。`RespondToModel` と `Fatal` などのバリアントを持ち、`handle` の戻り値として利用されます。（L1, L37-39, L43-47, L53, L58, L63-65, L68-71） |
| `crate::tools::context::FunctionToolOutput` | ツール実行の出力型。JSON テキストをラップして返す際に使用されます。（L2, L74-75） |
| `crate::tools::context::{ToolInvocation, ToolPayload}` | ツール呼び出しのコンテキストとペイロード種別。`handle` の入力およびペイロード検証に使用されます。（L3-4, L26-32, L34-36） |
| `crate::tools::handlers::parse_arguments` | `arguments` 文字列から `RequestUserInputArgs` への変換を行うヘルパー関数。（L5, L56） |
| `crate::tools::registry::{ToolHandler, ToolKind}` | ツールハンドラのトレイトとツール種別。`RequestUserInputHandler` はこれを実装して `ToolKind::Function` を返します。（L6-7, L18-23） |
| `codex_protocol::protocol::SessionSource` | セッションの発生源を表す列挙体。SubAgent かどうかを判定するために使用されます。（L8, L43-47） |
| `codex_protocol::request_user_input::RequestUserInputArgs` | `request_user_input` ツールの引数構造体。（L9, L56） |
| `codex_tools::REQUEST_USER_INPUT_TOOL_NAME` | ツール名を表す定数。エラーメッセージ中で使用されます。（L10, L37-39, L63-65, L69-71） |
| `codex_tools::normalize_request_user_input_args` | 引数の正規化ロジック。`RequestUserInputArgs` を整形し、エラー時にはメッセージを返す関数。（L11, L58） |
| `codex_tools::request_user_input_unavailable_message` | コラボレーションモードと設定値に基づき、ツールが利用不可な場合のメッセージを返す関数。（L12, L50-52） |
| `request_user_input_tests.rs` | `#[cfg(test)]` 時に読み込まれるテストファイル。このチャンクでは内容は不明です。（L78-80） |

---

## Bugs / Security（このファイルから読み取れる範囲）

- **明確なバグは見当たりません**  
  - ペイロード種別チェック、SubAgent チェック、モードチェック、キャンセル検知といった基本的な検証が揃っており、  
    明らかに誤った条件分岐などは見られません。（L34-55, L62-66）

- **セキュリティ上の観点**
  - SubAgent からの呼び出しを禁止することで、「下位エージェントが勝手にユーザー入力を要求する」ことを防ぐ設計になっています。（L43-47）  
    これは権限分離の観点で重要なガードです。
  - ユーザーに表示される可能性の高いメッセージ（`RespondToModel`）は、すべて固定文字列または外部関数からの文字列であり、  
    ここではユーザー入力がそのままエラーメッセージとして反映されるような箇所はありません。（L37-39, L43-47, L53, L63-65, L69-71）

- **残る不明点**
  - `parse_arguments` や `normalize_request_user_input_args` がユーザー入力をどのように検証／サニタイズしているかは、このチャンクには現れないため不明です。（L5, L11, L56-58）  
  - `session.request_user_input` が内部でどのような認可／検証を行っているかも、このファイルからは判断できません。（L59-61）

---

## Contracts / Edge Cases（まとめ）

このハンドラの外部的な契約（Contract）とエッジケースをまとめます。

- **契約**
  - 入力 `ToolInvocation` の `payload` が `ToolPayload::Function { arguments }` でなければならない。（L34-41）
  - `turn.session_source` は `SessionSource::SubAgent(_)` であってはならない。（L43-47）
  - コラボレーションモードと `default_mode_request_user_input` の組み合わせによっては、  
    ユーザー入力要求が禁止され、その理由がメッセージとして返る。（L49-55）
  - ユーザー入力要求がキャンセルされた場合は、`None` ではなく「キャンセル」と分かるエラーメッセージでモデルに返る。（L62-66）
  - 成功時には、ユーザー入力レスポンスが JSON 文字列として `FunctionToolOutput` に格納される。（L68-75）

- **代表的なエッジケース**
  - 誤ったペイロード種別 → 「unsupported payload」エラー。（L34-41）
  - SubAgent からの呼び出し → 「root thread のみ使用可」エラー。（L43-47）
  - 利用不可モード → `request_user_input_unavailable_message` の返すメッセージでエラー。（L50-54）
  - キャンセル → 「...was cancelled before receiving a response」エラー。（L62-66）
  - レスポンスがシリアライズ不可能 → Fatal エラー。（L68-71）

---

## Tests

- このファイルには `#[cfg(test)]` 付きで `mod tests;` が定義され、`request_user_input_tests.rs` がテストコードとして存在します。（L78-80）
- テストの具体的な内容やカバレッジはこのチャンクには現れないため、「どのパスがテストされているか」「モックがどう構成されているか」は不明です。

---

## Performance / Scalability（このファイルに基づく範囲）

- このハンドラ自身は、非同期 I/O（`session.collaboration_mode`, `session.request_user_input`）のラッパであり、  
  内部で重い計算やループは行っていません。（L49, L59-61）
- シリアライズも 1 回の `serde_json::to_string` のみであり、大きなレスポンスでない限りボトルネックにはなりにくいと考えられます。（L68-71）
- `&self` でステートレスに近く、内部にミューテーブルな共有状態を持たないため、多数の並行リクエストに対しても `RequestUserInputHandler` 自体はスケールしやすい構造です。（L14-16, L18-25）

（ただし、最終的なスケーラビリティは `session` 実装と、ユーザー入力 UI 側の設計に依存し、このチャンクからは判断できません。）

---

以上が、`core/src/tools/handlers/request_user_input.rs` の機能とデータフロー、安全性・エラー処理・並行性の観点を含む解説レポートです。
