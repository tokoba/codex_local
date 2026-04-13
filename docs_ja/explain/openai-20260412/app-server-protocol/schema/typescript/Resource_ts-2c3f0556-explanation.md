# app-server-protocol/schema/typescript/Resource.ts

## 0. ざっくり一言

サーバーが読み取り可能な既知のリソースを表す **データ構造（TypeScript 型定義）** を提供する、自動生成ファイルです（`Resource.ts:L1-3`, `Resource.ts:L6-9`）。

---

## 1. このモジュールの役割

### 1.1 概要

- このモジュールは、**「サーバーが読み取り可能なリソース」** を表す `Resource` 型を提供します（`Resource.ts:L6-9`）。
- ファイル先頭のコメントから、`ts-rs` によって **自動生成** されており、手動編集は禁止されています（`Resource.ts:L1-3`）。
- 実行時ロジックや関数は一切含まず、**型情報だけ** を提供するモジュールです（`Resource.ts:L4-9`）。

### 1.2 アーキテクチャ内での位置づけ

- パス `schema/typescript` から、このファイルは **アプリケーションサーバープロトコルの TypeScript スキーマ** の一部と位置づけられます。
- `Resource` 型は、`JsonValue` 型（`./serde_json/JsonValue`）に依存しています（`Resource.ts:L4`, `Resource.ts:L9`）。
- このファイル自身は `Resource` を `export` しており、他の TypeScript コードから利用されるための **公開スキーマ定義モジュール** になっています（`Resource.ts:L9`）。

依存関係を簡略図で示します。

```mermaid
graph TD
    subgraph "schema/typescript"
        JV["JsonValue 型 (import, L4)"]
        R["Resource 型 (export, L9)"]
    end

    R --> JV
```

- `Resource` 型は、自身のプロパティの一部で `JsonValue` を使用することで、その内部に任意の JSON 互換データ（と推測されますが、このチャンクだけでは断定できません）を保持できる設計になっています（`Resource.ts:L4`, `Resource.ts:L9`）。

### 1.3 設計上のポイント

- **自動生成コード**  
  - ファイル先頭に「GENERATED CODE! DO NOT MODIFY BY HAND!」と明記されており、手動編集禁止です（`Resource.ts:L1-3`）。
- **データのみ・状態なし**  
  - 関数やクラスは存在せず、`type` エイリアスによる構造的な型のみを定義しています（`Resource.ts:L9`）。
- **部分的な情報を許容する設計**  
  - 多くのプロパティが `?` 付き（オプショナル）であり、「一部情報だけが分かっているリソース」も扱えるようになっています（`Resource.ts:L9`）。
- **型安全性**  
  - TypeScript の型システムにより、`name` や `uri` が必須であること、その他のプロパティの型（`string`, `number`, `JsonValue`, `Array<JsonValue>`）がコンパイル時にチェックされます（`Resource.ts:L9`）。
- **エラー処理・並行性**  
  - 実行時の関数・非同期処理・エラーハンドリング・並行性に関するコードは一切含まれていません（`Resource.ts:L4-9`）。

---

## 2. 主要な機能一覧

このファイルは実行機能ではなく **型定義のみ** を提供します。そのため「機能」は次の 1 点に集約されます。

- `Resource` 型定義: サーバーが読み取り可能なリソースのメタデータ構造を TypeScript 型として表現する（`Resource.ts:L6-9`）。

---

## 3. 公開 API と詳細解説

### 3.1 型一覧（構造体・列挙体など）

#### コンポーネントインベントリー

| 名前       | 種別         | 公開 / 非公開 | 役割 / 用途                                                                 | 行番号根拠              |
|------------|--------------|---------------|------------------------------------------------------------------------------|-------------------------|
| `Resource` | 型エイリアス | 公開 (`export`) | サーバーが読み取り可能なリソースのメタデータを表すオブジェクト構造を定義する | `Resource.ts:L6-9`      |
| `JsonValue`| 型（別モジュール） | インポートのみ | 一部プロパティ (`annotations`, `icons`, `_meta`) の値の型として利用される    | `Resource.ts:L4`, `L9`  |

`Resource` 型のプロパティ一覧を示します（`Resource.ts:L9`）。

| プロパティ名   | 型                    | 必須?       | 説明（型レベルの意味）                                               |
|----------------|-----------------------|------------|----------------------------------------------------------------------|
| `annotations`  | `JsonValue`           | 任意 (`?`) | 任意値を入れられる拡張情報。型としては `JsonValue` で表現される。   |
| `description`  | `string`              | 任意 (`?`) | 文字列型の説明文。                                                   |
| `mimeType`     | `string`              | 任意 (`?`) | 文字列型の MIME タイプ。                                             |
| `name`         | `string`              | 必須        | リソース名称を表す文字列（必須）。                                   |
| `size`         | `number`              | 任意 (`?`) | 数値型のサイズ情報。                                                 |
| `title`        | `string`              | 任意 (`?`) | 文字列型のタイトル。                                                 |
| `uri`          | `string`              | 必須        | リソースを一意に指す URI を表す文字列（必須）。                      |
| `icons`        | `Array<JsonValue>`    | 任意 (`?`) | アイコン情報の配列。各要素は `JsonValue` 型。                        |
| `_meta`        | `JsonValue`           | 任意 (`?`) | メタ情報格納用と見られるフィールド。型としては `JsonValue`。        |

> 備考: プロパティの意味・用途は名前から推測できるものもありますが、このチャンクにはプロパティ単位のコメントはなく、**具体的な業務上の意味はコードからは断定できません**（`Resource.ts:L9`）。

### 3.2 関数詳細（最大 7 件）

このファイルには **関数・メソッドが一切定義されていない** ため、詳細解説すべき関数は存在しません（`Resource.ts:L4-9`）。

- エラー発生条件・パニック・非同期処理・並行性に関する挙動も、このモジュール単体からは発生しません。

### 3.3 その他の関数

- 補助関数やラッパー関数も定義されていません（`Resource.ts:L4-9`）。

---

## 4. データフロー

ここでは、「`Resource` 型オブジェクトの内部でどのようにデータ型が組み合わさっているか」をデータフローとして整理します。

### 4.1 型レベルでの内部データフロー

`Resource` 型は複数のプリミティブ型 (`string`, `number`) と、`JsonValue` / `Array<JsonValue>` を組み合わせた構造になっています（`Resource.ts:L4`, `Resource.ts:L9`）。

```mermaid
sequenceDiagram
    participant R as Resource オブジェクト (L9)
    participant JV as JsonValue 型 (L4)

    R->>JV: annotations プロパティ (JsonValue)
    R->>JV: icons プロパティの各要素 (Array&lt;JsonValue&gt;)
    R->>JV: _meta プロパティ (JsonValue)
```

- `Resource` の一部プロパティは `JsonValue` に委ねられており、「構造が固定されていない追加情報」を格納できる形になっています（`Resource.ts:L4`, `Resource.ts:L9`）。
- それ以外のプロパティはプリミティブ型 (`string`, `number`) であり、型が固定されたメタデータを表します（`Resource.ts:L9`）。

> このチャンクには、`Resource` がどの関数・モジュールから生成・利用されるかといった **ランタイムの呼び出しフロー** は現れません。そのため、外部コンポーネント間のデータフローは「不明」となります。

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

`Resource` は TypeScript の型エイリアスなので、主に **オブジェクトの型注釈** や **関数の引数 / 戻り値の型** として利用します。

```typescript
// Resource 型をインポートする（この例では同一ディレクトリ想定）
import type { Resource } from "./Resource"; // Resource.ts の export を利用

// Resource 型の値を作成する例
const fileResource: Resource = {           // Resource 型のオブジェクトを宣言
    name: "example.txt",                   // 必須プロパティ: string
    uri: "file:///path/to/example.txt",    // 必須プロパティ: string
    mimeType: "text/plain",                // 任意プロパティ: string
    size: 1234,                            // 任意プロパティ: number
};                                         // annotations, icons などは省略可能
```

- `name` と `uri` が **必須** であるため、これらを省略するとコンパイルエラーになります（`Resource.ts:L9`）。
- それ以外のプロパティはすべてオプショナルなので、必要なものだけ指定できます（`Resource.ts:L9`）。

関数の型として利用する例です。

```typescript
import type { Resource } from "./Resource"; // Resource 型を利用

// Resource を受け取って何らかの処理を行う関数の例
function printResourceSummary(resource: Resource): void { // 引数 resource の型を Resource とする
    console.log(resource.name);                          // name は必須なので直接アクセス可能
    console.log(resource.uri);                           // uri も必須
    if (resource.description) {                          // description はオプショナルなので存在チェック
        console.log(resource.description);               // 存在する場合のみ利用
    }
}
```

### 5.2 よくある使用パターン

1. **必須項目だけを持つ最小構成の `Resource`**

```typescript
const minimalResource: Resource = {        // 最小限の Resource
    name: "config.json",                  // 必須
    uri: "file:///etc/app/config.json",   // 必須
};                                        // 他は省略
```

1. **拡張情報を `JsonValue` で保持するパターン**

`JsonValue` の中身はこのチャンクからは分かりませんが、「任意の JSON 互換データ」を入れる用途が想定されます（名前とモジュール名からの推測であり、断定ではありません）。

```typescript
const richResource: Resource = {
    name: "image.png",
    uri: "https://example.com/image.png",
    annotations: {                        // JsonValue と推測されるオブジェクト
        tags: ["thumbnail", "public"],    // 任意のキー/値
        createdBy: "user123",
    } as any,                             // 実際の JsonValue 型定義に合わせて注釈する必要あり
};
```

> `JsonValue` の正確な型定義はこのチャンクには現れないため、ここでは `as any` を用いた疑似コードに留めています。

### 5.3 よくある間違い

**間違い例: 必須プロパティを指定しない**

```typescript
// ❌ 間違い例: name, uri を省略しているため Resource としては不完全
const invalidResource: Resource = {
    // name: "missing",                   // 必須なのに欠けている
    // uri: "file:///missing",           // 必須なのに欠けている
    description: "This will not compile", // オプショナルだけ指定
};
```

- `Resource` 型では `name` と `uri` が必須なので（`Resource.ts:L9`）、上記はコンパイルエラーになります。

**正しい例**

```typescript
// ✅ 正しい: 必須プロパティを含んだ Resource
const validResource: Resource = {
    name: "present",
    uri: "file:///present",
    description: "Now it compiles",
};
```

### 5.4 使用上の注意点（まとめ）

- **実行時には型情報が消える**  
  TypeScript の型はコンパイル後に消えるため、`Resource` 型だけでは **実行時のバリデーション** は行われません。外部入力（JSON など）を `Resource` にマッピングする場合は、別途検証ロジックが必要です。
- **オプショナルプロパティへのアクセス**  
  `annotations`, `description`, `mimeType`, `size`, `title`, `icons`, `_meta` は `undefined` の可能性があるため、使用前に存在チェックを行う必要があります（`Resource.ts:L9`）。
- **`JsonValue` の扱い**  
  `JsonValue` の構造はこのファイルからは分かりません。強い型安全性を保つには、`JsonValue` の定義側（`./serde_json/JsonValue`）を確認する必要があります（`Resource.ts:L4`）。
- **並行性・非同期性**  
  このモジュールは型定義のみであり、スレッド共有・非同期処理に関する懸念は直接は存在しません。ただし、同一の `Resource` オブジェクトが複数箇所で書き換えられる場合は、アプリケーション側で整合性に注意が必要です（一般的な JS/TS の注意点です）。

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能（プロパティ）を追加する場合

- ファイル先頭のコメントにある通り、このファイルは **自動生成されており、手動で変更すべきではありません**（`Resource.ts:L1-3`）。
- 新しいプロパティを `Resource` に追加したい場合は、通常は **生成元（おそらく Rust 側の型定義や ts-rs の設定）を修正し、再生成する** ことになります。  
  - これは `ts-rs` が Rust の型から TypeScript の型を生成するライブラリとして知られているための推測であり、このチャンクだけからは生成元の具体的な位置は特定できません。
- 直接このファイルを編集した場合:
  - 次回の自動生成で上書きされる可能性が高く、変更が失われるリスクがあります。
  - 他言語側のスキーマとの不整合が発生する可能性があります。

### 6.2 既存の機能（プロパティ）を変更する場合

- **影響範囲**  
  - `name` や `uri` の型や必須性を変更すると、`Resource` を利用しているすべての TypeScript コードに影響します。
  - `JsonValue` 型を別の型に変更すると、`annotations`, `icons`, `_meta` を利用しているコードに影響します（`Resource.ts:L9`）。
- **契約（前提条件）の確認**  
  - `name` / `uri` が必須であることを前提にしているロジックが多いと想定されるため（名前とコメントからの推測）、変更するときは、利用箇所全体を確認する必要があります。
- **テスト**  
  - このチャンクにはテストコードは現れません。そのため、実際のリポジトリでは `Resource` 型の変更に応じて、型チェックや CI、ビルド等でエラーがないかを確認することが必要です。
- **自動生成前提**  
  - 繰り返しになりますが、変更は生成元に対して行い、この TypeScript ファイルは再生成するという運用が前提と考えられます（`Resource.ts:L1-3`）。

---

## 7. 関連ファイル

このチャンクから直接確認できる関連ファイルは次の通りです。

| パス                            | 役割 / 関係                                                                                  |
|---------------------------------|---------------------------------------------------------------------------------------------|
| `./serde_json/JsonValue`       | `JsonValue` 型を提供するモジュール。`Resource` 型の `annotations`, `icons`, `_meta` で利用される（`Resource.ts:L4`, `L9`）。 |
| （不明）                        | テストコードや他言語側のスキーマファイルは、このチャンクには現れないため特定できません。      |

---

## 付記: Bugs / Security / Contracts / Edge Cases など

- **バグの可能性**  
  - 本ファイル自体は型定義のみであり、実行時のバグを直接生むロジックは含まれていません（`Resource.ts:L4-9`）。
- **セキュリティ**  
  - `Resource` の内容（特に `annotations`, `icons`, `_meta` に格納される `JsonValue`）がどのように使われるかによっては、XSS 等の懸念が出る可能性がありますが、その利用方法はこのチャンクには現れないため **不明** です。
- **契約 / エッジケース**  
  - `name`, `uri` が欠けたオブジェクトは `Resource` として扱えない（コンパイルエラー）という契約があります（`Resource.ts:L9`）。
  - `size` などの数値プロパティの範囲や単位（バイトか、別単位か）はコードからは分かりません。
- **テスト**  
  - このファイルに対する専用テストコードはチャンク内に存在しません。
- **パフォーマンス / スケーラビリティ**  
  - 型定義のみのため、このファイル自体の実行時パフォーマンスへの影響はありません。
- **観測性（ロギング等）**  
  - ログ出力やメトリクス取得に関するコードは含まれていません。

このように、`Resource.ts` は「サーバーが読み取り可能なリソースのスキーマ」を TypeScript で表現するための、**シンプルかつ自動生成された型定義モジュール**として整理できます。
