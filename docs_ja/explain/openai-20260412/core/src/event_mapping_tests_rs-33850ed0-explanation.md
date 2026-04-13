# core/src/event_mapping_tests.rs コード解説

## 0. ざっくり一言

このファイルは、`parse_turn_item` 関数が `codex_protocol::models::ResponseItem` を内部表現の `TurnItem` に正しく変換できているかを検証するテスト群です。ユーザー／アシスタントメッセージ、推論ログ、Web 検索呼び出し、フックプロンプト、各種メタデータの無視ルールなど、イベントマッピングの振る舞いを網羅的に確認しています。  
（本チャンクには行番号情報がないため、根拠行は便宜上すべて `core/src/event_mapping_tests.rs:L1-L462` と表記します）

---

## 1. このモジュールの役割

### 1.1 概要

- このモジュールは **外部プロトコル表現 (`ResponseItem`)** から **内部イベント表現 (`TurnItem`)** への変換関数 `parse_turn_item` の振る舞いをテストします。
- ユーザー入力・アシスタント出力・推論内容・Web 検索呼び出し・フックプロンプトなどの各種イベントについて、
  - どの情報をどの内部型に写像するか
  - どの情報を「文脈用メタデータ」として無視するか
  を確認します。
- Rust の `Option` 型（`Some` / `None`）によるエラーハンドリングや、列挙型 (`enum`) に対するパターンマッチの使い方もテストコード上で確認できます。  
  （根拠: すべてのテストで `parse_turn_item(&item)` の返り値に対して `expect` や `is_none`、`match` を使用している点）

### 1.2 アーキテクチャ内での位置づけ

このテストモジュール自体はアプリケーションロジックを持ちませんが、どのコンポーネントがどのように関わるかを示します。

```mermaid
graph TD
    subgraph core/src/event_mapping_tests.rs (L1-L462)
        T[#[test] 各種テスト関数]
    end

    subgraph super (event_mapping 実装; 行範囲不明)
        PT[parse_turn_item(&ResponseItem) -> Option<TurnItem>]
    end

    subgraph codex_protocol クレート
        R[models::ResponseItem]
        TI[items::TurnItem]
        UI[user_input::UserInput]
        AMC[items::AgentMessageContent]
        HPF[items::HookPromptFragment]
        WSI[items::WebSearchItem]
        WSA[models::WebSearchAction]
        RIC[models::ReasoningItemContent]
        RIRS[models::ReasoningItemReasoningSummary]
        BHPM[items::build_hook_prompt_message]
    end

    T -->|テスト入力生成| R
    T -->|テスト期待値生成| TI
    T -->|呼び出し| PT
    PT -->|入力型| R
    PT -->|出力型| TI
    PT -->|内部で利用| UI & AMC & HPF & WSI & WSA & RIC & RIRS
    T -->|利用| BHPM
```

- テスト関数は `ResponseItem` を構築し、`parse_turn_item` を呼び出し、`TurnItem` 系列の型との整合性を検証しています。
- `parse_turn_item` の実装はこのファイルには含まれず、`super` モジュール（同じディレクトリの本体実装）にあります。  
  （根拠: 冒頭の `use super::parse_turn_item;`）

### 1.3 設計上のポイント（テストから読み取れる範囲）

- **純粋なマッピング関数のテスト**  
  - `parse_turn_item` は外部イベント → 内部イベントへの変換のみを行い、I/O や並行処理は行わないとみなせます（テストはすべて同期的で副作用なし）。  
    （根拠: テスト中の呼び出しはすべて同期であり、async/スレッド関連の要素がない）
- **`Option` による「無視可能イベント」の表現**  
  - 特定のユーザーメッセージ（指示タグ `<INSTRUCTIONS>...` や `<environment_context>...` 等）は `None` を返して「会話用の TurnItem にはしない」設計になっています。  
    （根拠: `skips_user_instructions_and_env` で `assert!(turn_item.is_none())`）
- **列挙型とパターンマッチによる型安全**  
  - `TurnItem` の各バリアント (`UserMessage`, `AgentMessage`, `HookPrompt`, `Reasoning`, `WebSearch`) ごとにテストがあり、パターンマッチで内容を取り出して検証しています。  
    （根拠: 各テストの `match turn_item { TurnItem::X(...) => { ... } other => panic!(...) }`）

---

## 2. 主要な機能一覧（テスト対象の振る舞い）

このファイルが検証している主要な振る舞いは次の通りです（すべて `core/src/event_mapping_tests.rs:L1-L462` を根拠とします）。

- ユーザーメッセージ変換:
  - `ResponseItem::Message`（role=`"user"`）内の `InputText`・`InputImage` を `UserInput` の列に変換
  - 画像ラベル用のタグテキスト（`<image ...>` / `</image>`）をスキップ
- メタデータメッセージの無視:
  - `<INSTRUCTIONS>...</INSTRUCTIONS>` や `<environment_context>...</environment_context>` などのタグで囲まれたユーザーメッセージは `None` を返して無視
- アシスタントメッセージ変換:
  - 旧形式の `InputText` と新形式の `OutputText` の両方から `TurnItem::AgentMessage` を生成
- フックプロンプト変換:
  - `build_hook_prompt_message` で生成されたメッセージや `<hook_prompt ...>...</hook_prompt>` を含むメッセージから、`TurnItem::HookPrompt` を生成
  - フックプロンプト以外の文脈 (`<environment_context>`) はフラグメントから除外
- 推論イベント変換:
  - `ResponseItem::Reasoning` から、要約テキストと生の推論コンテンツを `TurnItem::Reasoning` に取り出す
- Web 検索呼び出し変換:
  - `ResponseItem::WebSearchCall` を `TurnItem::WebSearch(WebSearchItem)` に変換
  - `Search`/`OpenPage`/`FindInPage` 各アクションに応じて `query` 文字列を生成
  - `action: None` のケースでは `WebSearchAction::Other` と空文字列の `query` にフォールバック

---

## 3. 公開 API と詳細解説

このファイル自身はテストモジュールであり公開 API を定義しませんが、**テストからわかる範囲で `parse_turn_item` と関連型の挙動**を説明します。

### 3.1 型一覧（構造体・列挙体など）

> 定義は他モジュールですが、このテストで利用される主な型です。行範囲は利用箇所のあるファイル全体を示します。

| 名前 | 種別 | 役割 / 用途 | 根拠行 |
|------|------|-------------|--------|
| `ResponseItem` | 列挙体（推測） | 外部プロトコル上の 1 イベント（メッセージ、推論、Web検索呼び出しなど）を表現 | `core/src/event_mapping_tests.rs:L1-L462` |
| `TurnItem` | 列挙体 | コアロジック側で扱うイベント表現。`UserMessage` / `AgentMessage` / `HookPrompt` / `Reasoning` / `WebSearch` などのバリアントを持つ | 同上 |
| `UserInput` | 列挙体 | ユーザーメッセージ内の単一要素（テキスト / 画像）を表現 | 同上 |
| `AgentMessageContent` | 列挙体 | エージェントメッセージの構成要素（テキストなど）を表現 | 同上 |
| `HookPromptFragment` | 構造体（推測） | フックプロンプトの 1 片（`text` と `hook_run_id`） | 同上 |
| `WebSearchItem` | 構造体 | Web 検索呼び出しを内部表現としてまとめたもの（`id`, `query`, `action`） | 同上 |
| `WebSearchAction` | 列挙体 | Web 検索のアクション種別。`Search`, `OpenPage`, `FindInPage`, `Other` などを持つ | 同上 |
| `ReasoningItemContent` | 列挙体 | 推論イベント内の生コンテンツ（`ReasoningText`, `Text` など） | 同上 |
| `ReasoningItemReasoningSummary` | 列挙体 | 推論イベントの要約（ここでは `SummaryText { text }` のみ利用） | 同上 |
| `UserInput::Text` / `UserInput::Image` | 列挙体バリアント | テキスト入力と画像入力を区別 | 同上 |

※ いずれの型も定義本体はこのチャンクには現れず、**コンストラクタやパターンマッチから用途のみがわかります**。

### 3.2 関数詳細: `parse_turn_item`

#### `parse_turn_item(item: &ResponseItem) -> Option<TurnItem>`

**概要**

- `codex_protocol::models::ResponseItem` を受け取り、コア内部で扱う `TurnItem` に変換する関数です。
- 変換できない（もしくは変換したくない）イベント（環境コンテキストや instructions など）については `None` を返します。
- テストから、戻り値の型は `Option<TurnItem>` であると読み取れます。  
  （根拠: `skips_user_instructions_and_env` で `is_none()` を呼んでいる）

**引数**

| 引数名 | 型 | 説明 |
|--------|----|------|
| `item` | `&ResponseItem` | 外部プロトコルから渡される 1 つのイベント。借用参照で渡され、所有権は移動しません。 |

**戻り値**

- `Option<TurnItem>`  
  - `Some(turn_item)` : 会話やログに使う意味のあるイベントと判断できた場合
  - `None` : 指示用タグや環境情報など、会話ターンとして扱わないイベント

**内部処理の流れ（テストから推測できる論理）**

※ 実装はこのファイルにはありませんが、テストが検証している振る舞いから見える処理を整理します（根拠はいずれも `core/src/event_mapping_tests.rs:L1-L462` 内の対応テスト）。

1. **`ResponseItem` のバリアント判定**
   - `ResponseItem::Message { .. }`
   - `ResponseItem::Reasoning { .. }`
   - `ResponseItem::WebSearchCall { .. }`
   - 上記以外のバリアントの存在は、このチャンクからは不明です。

2. **Message (role = "user") の処理**
   - `content: Vec<ContentItem>` を走査し、次のように変換:
     - 通常のユーザーテキスト  
       → `UserInput::Text { text, text_elements: Vec::new() }` として保持  
       （根拠: `parses_user_message_with_text_and_two_images`）
     - 画像入力 (`ContentItem::InputImage { image_url }`)  
       → `UserInput::Image { image_url }`  
       （同上）
     - 画像ラベル用テキスト（例: `local_image_open_tag_text(1)`、`image_open_tag_text()`、`image_close_tag_text()` が返すもの）  
       → 完全にスキップし、`UserInput` ベクタには含めない  
       （根拠: `skips_local_image_label_text`, `skips_unnamed_image_label_text`）
   - 特定のタグに包まれたメッセージは **ターンとして無視**:
     - `# AGENTS.md instructions ... <INSTRUCTIONS> ... </INSTRUCTIONS>`
     - `<environment_context> ... </environment_context>`
     - `<skill> ... </skill>`
     - `<user_shell_command> ... </user_shell_command>`
     - これらのみが入ったメッセージについては `None` を返す  
       （根拠: `skips_user_instructions_and_env`）

3. **Message (role = "assistant") の処理**
   - 旧形式: `content: vec![ContentItem::InputText { text }]`  
     - テキストをそのまま `AgentMessageContent::Text { text }` にして `TurnItem::AgentMessage` を生成  
       （根拠: `parses_assistant_message_input_text_for_backward_compatibility`）
   - 新形式: `content: vec![ContentItem::OutputText { text }]`  
     - 同様に `AgentMessageContent::Text { text }` を含む `TurnItem::AgentMessage` を生成  
       （根拠: `parses_agent_message`）

4. **フックプロンプトの処理**
   - `build_hook_prompt_message(&[HookPromptFragment::from_single_hook(...)])` で生成されたメッセージ:
     - そのまま `TurnItem::HookPrompt` に変換し、`fragments` に引数の `HookPromptFragment` を格納  
       （根拠: `parses_hook_prompt_message_as_distinct_turn_item`）
   - 通常の `ResponseItem::Message` 内に `<hook_prompt ...>...</hook_prompt>` が含まれる場合:
     - メッセージの `id` を `hook_prompt.id` にコピー
     - `<hook_prompt>` タグ内のテキストから `HookPromptFragment { text, hook_run_id }` を抽出
     - HTML エンティティ `&amp;` を `&` に復元してテキストに格納
     - 同じ `content` に含まれる `<environment_context>...</environment_context>` のような他の文脈テキストはフラグメントから除外  
       （根拠: `parses_hook_prompt_and_hides_other_contextual_fragments`）

5. **Reasoning の処理**
   - `ResponseItem::Reasoning { summary, content, .. }` から:
     - `summary` 中の `ReasoningItemReasoningSummary::SummaryText { text }` をすべて取り出し、`summary_text: Vec<String>` に格納
     - `content`（`Option<Vec<ReasoningItemContent>>`）が `Some` の場合:
       - `ReasoningItemContent::ReasoningText { text }`
       - `ReasoningItemContent::Text { text }`  
       の両方を `raw_content: Vec<String>` に格納
     - `encrypted_content` はこのテストでは常に `None` であり、扱いは不明  
       （根拠: `parses_reasoning_summary_and_raw_content`, `parses_reasoning_including_raw_content`）

6. **WebSearchCall の処理**
   - `ResponseItem::WebSearchCall { id, status, action }` を `TurnItem::WebSearch(WebSearchItem)` にマッピング。
   - `id: Some(id)` → `WebSearchItem { id }` にコピー。
   - `action` のバリアントに応じて `query` と `action` を決定:
     - `Search { query: Some(q), .. }`  
       → `query: q`, `action: WebSearchAction::Search { query: Some(q), .. }`
     - `OpenPage { url: Some(u) }`  
       → `query: u`, `action: WebSearchAction::OpenPage { url: Some(u) }`
     - `FindInPage { url: Some(u), pattern: Some(p) }`  
       → `query: "'p' in u"`, `action: WebSearchAction::FindInPage { url: Some(u), pattern: Some(p) }`
     - `action: None` の場合  
       → `query: ""`, `action: WebSearchAction::Other`  
       （根拠: `parses_web_search_call`, `parses_web_search_open_page_call`, `parses_web_search_find_in_page_call`, `parses_partial_web_search_call_without_action_as_other`）

**Examples（使用例）**

1. ユーザーメッセージ（テキスト＋画像）から `UserMessage` を得る例:

```rust
use codex_protocol::models::ResponseItem;
use codex_protocol::models::ContentItem;
use codex_protocol::user_input::UserInput;
use codex_protocol::items::TurnItem;

// ResponseItem を組み立てる
let item = ResponseItem::Message {
    id: None,
    role: "user".to_string(),
    content: vec![
        ContentItem::InputText {
            text: "Hello world".to_string(),           // ユーザーのテキスト
        },
        ContentItem::InputImage {
            image_url: "https://example.com/img.png".to_string(), // 画像URL
        },
    ],
    end_turn: None,
    phase: None,
};

// イベントを内部表現に変換
if let Some(TurnItem::UserMessage(user)) = parse_turn_item(&item) {
    // user.content: Vec<UserInput>
    // 期待される内容:
    // - UserInput::Text { text: "Hello world", text_elements: Vec::new() }
    // - UserInput::Image { image_url: "https://example.com/img.png" }
    println!("{:?}", user.content);
} else {
    // ユーザーメッセージとして扱わない場合（メタデータ-only など）
    println!("ignored");
}
```

1. Web 検索呼び出しから `WebSearchItem` を得る例:

```rust
use codex_protocol::models::{ResponseItem, WebSearchAction};
use codex_protocol::items::{TurnItem, WebSearchItem};

let item = ResponseItem::WebSearchCall {
    id: Some("ws_1".to_string()),
    status: Some("completed".to_string()),
    action: Some(WebSearchAction::Search {
        query: Some("weather".to_string()),           // 検索クエリ
        queries: None,
    }),
};

let turn_item = parse_turn_item(&item).expect("expected web search turn item");
match turn_item {
    TurnItem::WebSearch(WebSearchItem { id, query, action }) => {
        assert_eq!(id, "ws_1");
        assert_eq!(query, "weather");                 // query フィールドに反映
        // action には同じ WebSearchAction::Search が入る
    }
    _ => panic!("unexpected turn item variant"),
}
```

**Errors / Panics**

- `parse_turn_item` 自体は `Option<TurnItem>` を返すため、変換に失敗したり「無視すべき」と判断したケースは `None` で表現されます。
- テストコードが `expect("...")` を呼ぶ場面では、「この入力では `Some` が返ってくるはず」という前提を検証しています。  
  （根拠: 多くのテストで `parse_turn_item(&item).expect("expected ...")`）
- `parse_turn_item` の内部で `panic!` が発生するかどうかは、このチャンクからは分かりません。ただしテストでは異常系入力をある程度与えており、そこでは panic せずに `None` や `WebSearchAction::Other` 等にフォールバックしていることが確認できます。

**Edge cases（エッジケース）**

テストから確認できるエッジケース:

- **メタデータ専用のユーザーメッセージ**
  - `<INSTRUCTIONS>...</INSTRUCTIONS>`, `<environment_context>...</environment_context>`, `<skill>...</skill>`, `<user_shell_command>...</user_shell_command>` のみを含むメッセージは `None`。  
    （根拠: `skips_user_instructions_and_env`）
- **画像ラベルタグ付きメッセージ**
  - `local_image_open_tag_text(1)` や `image_open_tag_text()` / `image_close_tag_text()` で生成されるテキストは完全に無視され、`UserInput` には画像本体と通常テキストだけが残る。  
    （根拠: `skips_local_image_label_text`, `skips_unnamed_image_label_text`）
- **WebSearchCall の不完全データ**
  - `action: None` で `status: Some("in_progress")` なケースでも `TurnItem::WebSearch` を返し、`action: WebSearchAction::Other`, `query: ""` にする。  
    （根拠: `parses_partial_web_search_call_without_action_as_other`）
- **推論コンテンツの多様な型**
  - `ReasoningItemContent::ReasoningText` だけでなく `ReasoningItemContent::Text` も `raw_content` に含める。  
    （根拠: `parses_reasoning_including_raw_content`）

**使用上の注意点**

- `None` が返るケースがあるため、呼び出し側では `Option` を必ずハンドリングする必要があります。
  - 例: ログとして完全に保持したい場合には、`None` だったイベントを別のストリームに保存するなどの考慮が必要になります。
- ユーザーメッセージに含まれる特定のタグ付きテキスト（instructions, environment_context, skill, user_shell_command）は **意図的にドロップ** されます。
  - これは、システム内部のメタ情報や実行コマンドが通常の会話ログとして扱われてしまうのを防ぐためと考えられますが、実装意図はコードからは断定できません。
- Web 検索の `query` フィールドは、`Search` 以外のアクションでは URL や `"'<pattern>' in <url>"` のような文字列になるため、「単純な検索語句」としてだけ扱うと意味がずれる可能性があります。

### 3.3 その他の関数（テスト関数）

このファイルで定義される関数はすべてテスト用です。

| 関数名 | 種別 | 役割（1 行） | 根拠行 |
|--------|------|--------------|--------|
| `parses_user_message_with_text_and_two_images` | `#[test] fn` | ユーザーのテキスト＋複数画像が `UserInput` 列に正しく変換されることを検証 | `core/src/event_mapping_tests.rs:L1-L462` |
| `skips_local_image_label_text` | `#[test] fn` | ローカル画像ラベル用タグテキストが `UserInput` から除外されることを検証 | 同上 |
| `parses_assistant_message_input_text_for_backward_compatibility` | `#[test] fn` | 旧形式 (`InputText`) のアシスタントメッセージが `AgentMessage` として解釈されることを検証 | 同上 |
| `skips_unnamed_image_label_text` | `#[test] fn` | 名前なし画像タグ（`image_open_tag_text` 等）がスキップされることを検証 | 同上 |
| `skips_user_instructions_and_env` | `#[test] fn` | instructions / environment_context / skill / user_shell_command メッセージが `None` になることを検証 | 同上 |
| `parses_hook_prompt_message_as_distinct_turn_item` | `#[test] fn` | `build_hook_prompt_message` で作られたメッセージが `HookPrompt` として扱われることを検証 | 同上 |
| `parses_hook_prompt_and_hides_other_contextual_fragments` | `#[test] fn` | hook_prompt タグだけを抽出し、environment_context をフラグメントから除外することを検証 | 同上 |
| `parses_agent_message` | `#[test] fn` | 新形式 (`OutputText`) のアシスタントメッセージが `AgentMessage` になることを検証 | 同上 |
| `parses_reasoning_summary_and_raw_content` | `#[test] fn` | 推論イベントの要約と生コンテンツがそれぞれ `summary_text` / `raw_content` に格納されることを検証 | 同上 |
| `parses_reasoning_including_raw_content` | `#[test] fn` | `ReasoningText` と `Text` の両方が `raw_content` に含まれることを検証 | 同上 |
| `parses_web_search_call` | `#[test] fn` | `Search` アクションの WebSearchCall が `WebSearchItem` に正しく変換されることを検証 | 同上 |
| `parses_web_search_open_page_call` | `#[test] fn` | `OpenPage` アクションが URL を `query` に反映することを検証 | 同上 |
| `parses_web_search_find_in_page_call` | `#[test] fn` | `FindInPage` アクションが `"'<pattern>' in <url>"` 形式の `query` を生成することを検証 | 同上 |
| `parses_partial_web_search_call_without_action_as_other` | `#[test] fn` | `action: None` の WebSearchCall を `WebSearchAction::Other` として扱うことを検証 | 同上 |

---

## 4. データフロー

ここでは代表的なシナリオとして、「ユーザーメッセージ（テキスト＋画像）」がどのように処理されるかを示します。

```mermaid
sequenceDiagram
    participant Test as テスト関数<br/>parses_user_message_with_text_and_two_images<br/>(L1-L462)
    participant RI as ResponseItem::Message<br/>(user)
    participant PT as parse_turn_item<br/>(super; 行範囲不明)
    participant TI as TurnItem::UserMessage
    participant UI as Vec<UserInput>

    Test->>RI: 構築 (InputText + InputImage*2)
    Test->>PT: parse_turn_item(&RI)
    PT->>PT: Message/role/content を解析
    PT->>UI: UserInput::Text / Image を生成<br/>（画像ラベル用テキストは破棄）
    PT->>TI: TurnItem::UserMessage { content: UI }
    PT-->>Test: Some(TurnItem::UserMessage)
    Test->>Test: 期待される Vec<UserInput> と比較し assert_eq
```

要点:

- テストコードが `ResponseItem::Message` を組み立て、`parse_turn_item` に渡します。
- `parse_turn_item` は `ResponseItem` のバリアントと role・content を判定し、内部表現 `TurnItem` に変換します。
- ユーザーメッセージでは、画像ラベル用のタグテキストを捨て、テキストと画像をそれぞれ `UserInput` としてベクタにまとめます。
- 変換結果は `Some(TurnItem::UserMessage)` として返され、テスト側で `assert_eq!` により期待値と比較されます。

同様の流れが、Reasoning や WebSearchCall、HookPrompt に対しても適用されます。

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

`parse_turn_item` の基本的な使い方は、テストと同様に「外部イベントストリームから 1 件ずつ取り出して変換する」形になります。

```rust
use codex_protocol::models::{ResponseItem, ContentItem};
use codex_protocol::items::TurnItem;

// 外部から受け取った ResponseItem（例としてユーザーメッセージ）
let response_item = ResponseItem::Message {
    id: Some("msg-1".to_string()),
    role: "user".to_string(),
    content: vec![
        ContentItem::InputText {
            text: "Hello".to_string(),
        },
    ],
    end_turn: None,
    phase: None,
};

// コアロジック用の TurnItem に変換
if let Some(turn_item) = parse_turn_item(&response_item) {
    match turn_item {
        TurnItem::UserMessage(user) => {
            // user.content: Vec<UserInput> を会話履歴などに追加
        }
        TurnItem::AgentMessage(agent) => {
            // agent.content を UI に表示するなど
        }
        TurnItem::HookPrompt(hook) => {
            // hook.fragments をもとにフックを実行
        }
        TurnItem::Reasoning(reasoning) => {
            // reasoning.summary_text や raw_content をログ表示
        }
        TurnItem::WebSearch(search) => {
            // search.action に応じた処理
        }
    }
} else {
    // None → instructions や environment_context など、会話ターンとしては無視
}
```

### 5.2 よくある使用パターン

1. **イベントストリーム処理**

```rust
fn process_events(events: impl IntoIterator<Item = ResponseItem>) {
    for event in events {
        if let Some(turn_item) = parse_turn_item(&event) {
            // 変換に成功したイベントだけを会話ログなどに追加
            handle_turn_item(turn_item);
        } else {
            // 無視すべきメタデータイベントなのでスキップ
        }
    }
}
```

- `parse_turn_item` が `None` を返すケースを自然にフィルタとして利用できます。

1. **WebSearch 呼び出しの復元**

```rust
fn handle_turn_item(turn: TurnItem) {
    if let TurnItem::WebSearch(search) = turn {
        match search.action {
            WebSearchAction::Search { query: Some(q), .. } => {
                // 検索クエリ q として扱う
            }
            WebSearchAction::OpenPage { url: Some(u) } => {
                // URL u をブラウザで開くなど
            }
            WebSearchAction::FindInPage { url: Some(u), pattern: Some(p) } => {
                // u のページ内で p を検索
            }
            WebSearchAction::Other => {
                // 不完全な呼び出し。ログなどに残しておく
            }
            _ => { /* このチャンクには現れないパターン */ }
        }
    }
}
```

### 5.3 よくある間違い

```rust
// NG例: None を考慮せずに unwrap してしまう
let turn_item = parse_turn_item(&item).unwrap(); // instructions-only メッセージなどで panic の可能性

// 正しい例: None を明示的に扱う
if let Some(turn_item) = parse_turn_item(&item) {
    // 変換できたケースのみ処理
    handle_turn_item(turn_item);
} else {
    // メタデータのみのメッセージなどはここに来る
}
```

```rust
// NG例: WebSearchItem.query を常に「検索語句」と想定して UI に出してしまう
if let TurnItem::WebSearch(search) = turn_item {
    show_query_to_user(&search.query); // "https://example.com" や "'needle' in https://..." が来ることもある
}

// 正しい例: action に応じて query の意味を解釈する
if let TurnItem::WebSearch(search) = turn_item {
    match search.action {
        WebSearchAction::Search { .. } => show_search_query(&search.query),
        WebSearchAction::OpenPage { .. } => show_opened_url(&search.query),
        WebSearchAction::FindInPage { .. } => show_find_in_page_desc(&search.query),
        WebSearchAction::Other => log_incomplete_call(&search),
    }
}
```

### 5.4 使用上の注意点（まとめ）

- `parse_turn_item` は **ミドルレイヤ** であり、外部イベントのうち一部を会話用の TurnItem に変換し、一部を無視します。
  - メタデータ専用メッセージが `None` になることを前提に、呼び出し側の制御フローを設計する必要があります。
- セキュリティ / 安全性の観点:
  - `<user_shell_command>...</user_shell_command>` が `None` で無視されることは、「ユーザーに見せる会話ターン」と「内部的なコマンド実行」を分離するための安全策として機能します。
  - instructions や environment_context も同様に、通常の会話メッセージとして扱われないことがテストで保証されています。
- 並行性:
  - このファイルからは並行実行の有無は読み取れませんが、`&ResponseItem` の不変参照を取る形になっており、`parse_turn_item` 自体は共有データを変更しない純粋関数的な設計であることが示唆されます（ただし実装は未確認）。

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

- **新しい `ResponseItem` バリアントを TurnItem にマッピングしたい場合**
  1. `super` モジュール側（`parse_turn_item` の実装ファイル）で、新バリアントに対応する分岐を追加します。
  2. 対応する内部型（`TurnItem` の新バリアント、または既存バリアントのフィールド）を定義・拡張します。
  3. このテストファイルに、新バリアント用のテスト関数を追加します。
     - `ResponseItem` を組み立てて `parse_turn_item` を呼び出し、期待される `TurnItem` との比較を行います。

- **新しいメタデータタグを無視したい場合**
  1. `parse_turn_item` 内の「無視すべきユーザーメッセージ」の判定ロジックを拡張します（例: 新しい `<...>` タグの検出）。
  2. `skips_user_instructions_and_env` に類似したテストを追加し、そのタグを含むメッセージで `parse_turn_item` が `None` を返すことを確認します。

### 6.2 既存の機能を変更する場合

- 影響範囲の確認:
  - `TurnItem` の形を変えると、このテストファイルだけでなく、コアロジック全体での利用箇所に影響します。
  - 特に `WebSearchItem.query` の生成ルールを変えると、UI やログの表示ロジックも変更が必要になる可能性があります。
- 契約（前提・返り値の意味）の確認:
  - `parse_turn_item` が `None` を返す条件を変えると、上位レイヤでの「無視されるイベント」の定義が変わります。
  - instructions や environment_context が `Some` で返されるように変更する場合は、セキュリティ／動作上の意味合いを慎重に検討する必要があります。
- テストの更新:
  - 仕様変更に応じて、このファイル内の該当テストを修正または追加します。
  - 変更前後で期待される振る舞いを明示することで、将来のリグレッションを防ぐことができます。

---

## 7. 関連ファイル

このモジュールと密接に関係するファイル・モジュール（パスはコード中の `use` から推測できる範囲です）。

| パス / モジュール | 役割 / 関係 |
|-------------------|------------|
| `super` モジュール（ファイル名はこのチャンクからは不明） | `parse_turn_item` の実装本体を持つモジュール。テスト対象。 |
| `codex_protocol::models` | `ResponseItem`, `ContentItem`, `ReasoningItemContent`, `ReasoningItemReasoningSummary`, `WebSearchAction`、および `local_image_open_tag_text`, `image_open_tag_text`, `image_close_tag_text` などを定義するプロトコル層。 |
| `codex_protocol::items` | `TurnItem`, `AgentMessageContent`, `HookPromptFragment`, `WebSearchItem`, `build_hook_prompt_message` など、イベント／メッセージのアイテム型を定義するモジュール。 |
| `codex_protocol::user_input::UserInput` | ユーザーからの入力（テキスト／画像）を表現する内部型。`TurnItem::UserMessage` 内部で利用。 |
| `pretty_assertions` クレート | `assert_eq!` の出力を見やすくするためのテスト支援クレート。 |

このファイル全体は、`parse_turn_item` の仕様を **テストという形で文書化している** 位置づけになっており、仕様確認や実装変更時のリファレンスとして利用することができます。
