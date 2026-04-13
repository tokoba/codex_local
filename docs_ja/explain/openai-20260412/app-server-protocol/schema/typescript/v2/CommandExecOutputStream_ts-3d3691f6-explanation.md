# app-server-protocol/schema/typescript/v2/CommandExecOutputStream.ts コード解説

## 0. ざっくり一言

`CommandExecOutputStream` は、コマンド実行結果の出力ストリーム種別を `"stdout"` または `"stderr"` のいずれかに限定して表現するための TypeScript 型エイリアスです (CommandExecOutputStream.ts:L5-8)。  
このファイル自体は ts-rs により自動生成されており、手動編集は想定されていません (CommandExecOutputStream.ts:L1-3)。

---

## 1. このモジュールの役割

### 1.1 概要

- このモジュールは、`command/exec/outputDelta` という種類の通知に含まれる「どの出力ストリームか」を示すラベルを型として表現するために存在します (CommandExecOutputStream.ts:L5-6)。
- `CommandExecOutputStream` 型は `"stdout"` | `"stderr"` という **文字列リテラル型のユニオン** として定義され、許可される値をコンパイル時に制限します (CommandExecOutputStream.ts:L8-8)。

### 1.2 アーキテクチャ内での位置づけ

- ファイルパス `app-server-protocol/schema/typescript/v2` から、このモジュールは「アプリケーションとサーバー間プロトコル」の TypeScript 向けスキーマ定義群のひとつと位置づけられます（パス情報より）。
- コメントより、`CommandExecOutputStream` は `command/exec/outputDelta` 通知のストリームラベルに対応する型であることが分かります (CommandExecOutputStream.ts:L5-6)。
- どのファイルや型から実際にインポートされているかは、このチャンクには現れていません（不明）。

以下は、コメントから読み取れる情報に基づく **想定上の位置づけ** を示した依存関係図です（通知ペイロード型などの具体的な名前は推測であり、このチャンクには定義がありません）。

```mermaid
graph TD
    A["CommandExecOutputStream.ts\n(CommandExecOutputStream 型; L5-8)"]
    B["command/exec/outputDelta 通知ペイロード型\n(推測: このチャンクには定義なし)"]
    C["通知送信側コンポーネント\n(推測)"]
    D["通知受信側コンポーネント\n(推測)"]

    A -->|stream フィールドの型として利用 (推測)| B
    C -->|B 型のデータを送信 (推測)| B
    B -->|シリアライズされて送信 (推測)| D
```

### 1.3 設計上のポイント

- **自動生成コードであることの明記**  
  冒頭コメントで、「自動生成コードであり、手で編集してはならない」ことが明示されています (CommandExecOutputStream.ts:L1-3)。  
  これは、設計上「単一のソース（おそらく Rust 側の型定義）から複数言語のスキーマを生成する」方針であることを示唆します（ts-rs 利用による）。

- **文字列リテラルのユニオン型での表現**  
  `"stdout"` と `"stderr"` の 2 つの文字列リテラルのみを許可するユニオン型として宣言されています (CommandExecOutputStream.ts:L8-8)。  
  単なる `string` 型ではなくユニオン型にすることで、「取りうる値の集合」が型レベルで厳密に定義されます。

- **状態を持たない純粋な型定義**  
  関数やクラス、実行時ロジックは一切なく、1 つの型エイリアスをエクスポートするだけのモジュールです (CommandExecOutputStream.ts:L5-8)。  
  したがって、このファイル単体では状態管理やエラーハンドリング、並行性制御といった論点は存在しません。

---

## 2. 主要な機能一覧

このモジュールが提供する主要な「機能」は、公開型の定義 1 点のみです。

- `CommandExecOutputStream`: コマンド実行結果の出力ストリーム種別を `"stdout"` または `"stderr"` に限定する文字列リテラル型エイリアス (CommandExecOutputStream.ts:L5-8)

---

## 3. 公開 API と詳細解説

このファイルは 1 つの型エイリアスをエクスポートするだけのモジュールです (CommandExecOutputStream.ts:L8-8)。

### 3.1 型一覧（構造体・列挙体など）

| 名前                       | 種別                        | 役割 / 用途                                                                                             | 定義箇所                                  |
|----------------------------|-----------------------------|----------------------------------------------------------------------------------------------------------|-------------------------------------------|
| `CommandExecOutputStream`  | 文字列リテラルのユニオン型エイリアス | `command/exec/outputDelta` 通知で使用される出力ストリームラベルを `"stdout"` または `"stderr"` に限定して表現する | CommandExecOutputStream.ts:L5-8 |

#### `CommandExecOutputStream`

**概要**

- TypeScript の型エイリアスとして、2 つの文字列リテラル `"stdout"` と `"stderr"` からなるユニオン型が定義されています (CommandExecOutputStream.ts:L8-8)。
- コメントより、この型は `command/exec/outputDelta` 通知の「ストリームラベル」を表現するために使われることが分かります (CommandExecOutputStream.ts:L5-6)。

```typescript
// 抜粋 (CommandExecOutputStream.ts:L5-8)

/**
 * Stream label for `command/exec/outputDelta` notifications.
 */
export type CommandExecOutputStream = "stdout" | "stderr";
```

**型の意味（TypeScript の観点）**

- `export type CommandExecOutputStream = "stdout" | "stderr";` は、次のような意味を持ちます (CommandExecOutputStream.ts:L8-8)。
  - `type ... = ...` は **型エイリアス**（既存の型に別名を付ける仕組み）です。
  - `"stdout"` や `"stderr"` は **文字列リテラル型** で、その文字列値のみを取る型です。
  - `"stdout" | "stderr"` は **ユニオン型** で、「`"stdout"` または `"stderr"` のどちらかである」ことを表します。
- したがって `CommandExecOutputStream` 型の変数は、コンパイル時点で **この 2 つ以外の文字列リテラルを代入することはできません**。

**言語固有の安全性 / エラー挙動**

- **コンパイル時チェック**  
  `CommandExecOutputStream` 型を使うと、誤った文字列（例: `"STDOUT"` や `"out"`）を代入しようとした時点で TypeScript コンパイラがエラーとして検出します。  
  これは、「値のバリエーションの間違い」を実行前に防ぐ効果があります。
- **実行時エラー**  
  この型定義自体には実行時ロジックがないため、型に起因するエラーはすべてコンパイル時（型チェック時）に検出されます。  
  ただし、`as CommandExecOutputStream` などで強制的に型アサーションを行った場合は、誤った値が実行時に残る可能性があります（TypeScript 全般の注意点）。
- **並行性**  
  型定義のみであり、実行時オブジェクトや共有状態を持たないため、このファイル単体に関しては並行性に関する懸念はありません。

**Edge cases（エッジケース）**

- `CommandExecOutputStream` 型の変数に対し、`"stdout"` / `"stderr"` 以外の **文字列リテラル** を直接代入するとコンパイルエラーになります (CommandExecOutputStream.ts:L8-8)。
- 値が実行時に決まる通常の `string`（例: ユーザー入力）から `CommandExecOutputStream` へ代入する場合は、型アサーションやランタイムチェックが必要になります。チェックを行わない型アサーションだけの利用は、安全性を損なう可能性があります（TypeScript 一般の性質）。

**使用上の注意点**

- 自動生成コードであるため、この型にバリアント（例: `"stdin"`）を追加・変更したい場合は、**直接編集ではなく生成元（ts-rs が参照するスキーマ）を変更する必要があります** (CommandExecOutputStream.ts:L1-3)。
- 文字列は **大文字小文字が区別される** ため、`"STDOUT"` や `"Stdout"` は `CommandExecOutputStream` としては不正な値になります (CommandExecOutputStream.ts:L8-8)。
- ランタイムから渡される任意の文字列をこの型にキャストする際は、 `"stdout"` / `"stderr"` のいずれかかどうかを実行時に検証することが望ましいです。そうしないと、型アサーションでコンパイルエラーを抑制してしまい、実行時のバグやログの混乱につながる可能性があります。

### 3.2 関数詳細（最大 7 件）

- このファイルには、関数・メソッド・クラスなどの **実行時処理を持つ要素は定義されていません** (CommandExecOutputStream.ts:L1-8)。  
  そのため、このセクションに詳細解説すべき関数は存在しません。

### 3.3 その他の関数

- 補助的な関数やラッパー関数も、このファイルには一切登場しません (CommandExecOutputStream.ts:L1-8)。

---

## 4. データフロー

このファイルには具体的な処理フローは記述されていませんが、コメントより `command/exec/outputDelta` 通知のストリームラベルとして使われることが分かります (CommandExecOutputStream.ts:L5-6)。  
そのため、典型的なデータフローは概ね次のようになると考えられます（通知送信側・受信側の名称は一般化したものです）。

1. 通知送信側コンポーネントが、コマンド実行から得られた出力の一部を `command/exec/outputDelta` 通知として構築する（推測）。
2. 通知ペイロード内に `"stdout"` または `"stderr"` のいずれかを `CommandExecOutputStream` 型として設定する (CommandExecOutputStream.ts:L8-8)。
3. 通知受信側が、このストリーム種別に応じてログ出力先や表示方法を切り替える（推測）。

この流れをシーケンス図として表現すると、以下のようになります。

```mermaid
sequenceDiagram
    participant S as "通知送信側\n(推測)"
    participant R as "通知受信側\n(推測)"

    Note over S,R: CommandExecOutputStream 型定義 (L5-8) を利用

    S->>R: command/exec/outputDelta 通知\nstream: "stdout" | "stderr"\n(型: CommandExecOutputStream; L5-8)
    R-->R: stream の値に応じて処理を分岐 (推測)
```

> 注: 上記の送信側 / 受信側コンポーネントや通知ペイロード構造は、コメントに基づく一般的な想定であり、このチャンクに具体的な定義は存在しません (CommandExecOutputStream.ts:L1-8)。

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

`CommandExecOutputStream` を、通知ペイロードの `stream` フィールドの型として使う例です。  
`CommandExecOutputDelta` インターフェースは **説明用の仮例** であり、このリポジトリ内に同名の型が存在するかどうかは、このチャンクからは分かりません。

```typescript
// CommandExecOutputStream 型をインポートする                      // 自動生成された型を利用する
import type { CommandExecOutputStream } from "./CommandExecOutputStream";  // パスは同一ディレクトリ想定の例

// command/exec/outputDelta 通知ペイロードの仮の型定義               // 実際の構造はこのチャンクからは不明
interface CommandExecOutputDelta {
    stream: CommandExecOutputStream;                                    // 出力ストリームの種別
    data: string;                                                       // 出力内容（例として string）
}

// 正しい利用例                                                       // stream には "stdout" または "stderr" だけが許される
const msg: CommandExecOutputDelta = {
    stream: "stdout",                                                   // コンパイル OK ("stdout" は許可されたリテラル)
    data: "hello world",                                                // 任意の文字列
};
```

- `stream` フィールドが `CommandExecOutputStream` 型であるため、`"stdout"` / `"stderr"` 以外の文字列を指定するとコンパイルエラーになります (CommandExecOutputStream.ts:L8-8)。

### 5.2 よくある使用パターン

ストリーム種別に応じて処理を分岐する関数の例です。

```typescript
import type { CommandExecOutputStream } from "./CommandExecOutputStream";  // CommandExecOutputStream 型を利用

// 出力ストリームに応じて処理を切り替える関数                       // stream 引数の型に CommandExecOutputStream を指定
function handleOutput(stream: CommandExecOutputStream, chunk: string): void {
    if (stream === "stdout") {                                           // "stdout" の場合の処理
        console.log(chunk);                                              // 標準出力側の扱い（例）
    } else {                                                             // ここでは "stderr" のみが残る
        console.error(chunk);                                            // 標準エラー側の扱い（例）
    }
}
```

- ユニオン型を用いることで、`if (stream === "stdout")` と比較した後の `else` 節では **自動的に `"stderr"` だけが残る** ため、条件分岐が明確になります (CommandExecOutputStream.ts:L8-8)。
- 値の取りうる範囲が 2 パターンに限定されているため、`switch` 文等を使った場合でも **パターン漏れの検出** がしやすくなります（将来バリアントが追加された場合に有用）。

### 5.3 よくある間違い

#### 誤ったリテラルを指定する

```typescript
import type { CommandExecOutputStream } from "./CommandExecOutputStream";

// 間違い例: 許可されていない文字列リテラル                         // "STDOUT" は CommandExecOutputStream ではない
const badStream: CommandExecOutputStream = "STDOUT";  // コンパイルエラー
```

- `CommandExecOutputStream` は `"stdout"` と `"stderr"` のみを許可するため、大文字小文字が異なる `"STDOUT"` などはコンパイルエラーになります (CommandExecOutputStream.ts:L8-8)。

#### 型アサーションで無理に通す

```typescript
// 間違いになりうる例                                                 // ランタイム値をそのままキャストしている
function fromUserInput(input: string): CommandExecOutputStream {
    return input as CommandExecOutputStream;                           // コンパイルは通るが安全ではない
}
```

- これは **コンパイルエラーを抑制してしまう** 典型例であり、`input` が `"stdout"` / `"stderr"` 以外の値であっても実行時にはそのまま通ってしまいます。
- 正しくは、入力値を検証してから `CommandExecOutputStream` として扱う必要があります。

```typescript
// 正しい方向性の例                                                   // ランタイムで検証してから型を絞り込む
function parseStream(input: string): CommandExecOutputStream | undefined {
    if (input === "stdout" || input === "stderr") {                    // 許可された 2 値のみ許す
        return input;                                                  // 型推論により CommandExecOutputStream として返せる
    }
    return undefined;                                                  // 不正な値は undefined で表現（例）
}
```

### 5.4 使用上の注意点（まとめ）

- **許可される値は `"stdout"` / `"stderr"` のみ**  
  これ以外の文字列リテラルはコンパイル時に拒否されます (CommandExecOutputStream.ts:L8-8)。
- **大文字小文字は区別される**  
  `"STDOUT"` や `"StdOut"` 等は別の文字列として扱われ、`CommandExecOutputStream` には代入できません (CommandExecOutputStream.ts:L8-8)。
- **ランタイムからの入力には検証が必要**  
  ユーザー入力や外部システムから受け取った文字列をこの型にキャストする場合、実行時検証を行わずに `as` で型アサーションを行うと、型システムによる安全性が失われます。
- **自動生成コードである点**  
  ファイル先頭に「生成コードであり手動編集してはいけない」とあるため (CommandExecOutputStream.ts:L1-3)、直接編集すると再生成時に上書きされたり、他言語のスキーマと不整合が発生する可能性があります。
- **テスト / ログ / セキュリティの観点**  
  - この型自体には実行時ロジックがないため、このファイル単体に対する直接のテストケースは通常不要であり、利用側のコンポーネントのテストでカバーされることが多いと考えられます（このチャンクにはテストは現れません: CommandExecOutputStream.ts:L1-8）。
  - 型の利用により、「stderr を stdout に誤って扱う」といったロジック上のバグやログの混在を防ぎやすくなり、監査やデバッグ時の混乱を減らす効果が期待できます（コメントの意図より: CommandExecOutputStream.ts:L5-6）。

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

このファイルは ts-rs によって生成されているため、**直接編集することは想定されていません** (CommandExecOutputStream.ts:L1-3)。

- 新しいストリーム種別（例: `"stdin"`）を追加したい場合:
  - TypeScript ファイルを直接編集するのではなく、**ts-rs が参照している生成元のスキーマ（おそらく Rust 側の型定義）** を変更し、その後コード生成を再実行する必要があります（生成元の具体的なパスはこのチャンクからは不明です）。
  - 生成元でストリームバリアントを追加すると、それに合わせてこの TypeScript 型にも新しい文字列リテラルが追加される形になると推測されます（ts-rs 利用の一般的なパターン）。

- この型を利用する新しい関数やクラスを追加する場合:
  - 利用側のモジュールで `import type { CommandExecOutputStream } from "...";` とインポートし、`stream` 引数やフィールドの型として使用します (CommandExecOutputStream.ts:L8-8)。
  - 追加する機能の中で `"stdout"` / `"stderr"` の両方を適切に扱う必要があり、将来バリアントが増えた場合に備えて `switch` 文に `default` を設けないなどの工夫をすると、コンパイラによるパターン漏れ検出がしやすくなります。

### 6.2 既存の機能を変更する場合

- **バリアント名を変更する場合**（例: `"stderr"` を `"stdErr"` に変えるなど）:
  - 生成元のスキーマを修正し、ts-rs により再生成します (CommandExecOutputStream.ts:L1-3)。
  - TypeScript 側では、`CommandExecOutputStream` を利用しているすべての箇所でコンパイルエラーが発生するため、それらを順に修正することで影響範囲を把握できます (CommandExecOutputStream.ts:L8-8)。
- **バリアントを削除する場合**:
  - 同様に生成元を変更し再生成します。
  - `"stderr"` を削除した場合などは、エラー処理を想定していたコードがコンパイルエラーになるため、設計上の意味合い（本当に不要なストリームなのか）をよく確認する必要があります。
- **契約（前提条件・返り値の意味など）の注意点**:
  - `CommandExecOutputStream` は「許可されるストリームの集合」を表す契約そのものです (CommandExecOutputStream.ts:L8-8)。
  - この集合を変えることは、プロトコル仕様の変更に直結します。アプリケーション間通信の互換性（前方互換・後方互換）への影響が大きいため、バージョニング方針（ディレクトリ名にある `v2` など）との整合性に注意する必要があります（パスの情報より）。

---

## 7. 関連ファイル

このチャンクには他ファイル名の記述はありませんが、ファイルパスとコメントから、関係が強いと考えられる要素を整理します。

| パス / 区分                                               | 役割 / 関係 |
|----------------------------------------------------------|------------|
| `app-server-protocol/schema/typescript/v2/`（ディレクトリ） | 同一プロトコルの TypeScript スキーマ定義群が配置されるディレクトリと考えられます。`CommandExecOutputStream` と同様に、他の通知やコマンドの型が定義されている可能性があります（具体的なファイル名はこのチャンクには現れません）。 |
| ts-rs の生成元スキーマ（具体的パス不明）                 | この TypeScript ファイルの元となる Rust 側などの型定義が存在すると考えられます。`CommandExecOutputStream` に対応する列挙型や型エイリアスが定義されているはずですが、このチャンクからは場所や構造は分かりません (CommandExecOutputStream.ts:L1-3)。 |
| `command/exec/outputDelta` 関連のペイロード型（不明）     | コメントに現れる通知名から、そのペイロードを表す TypeScript 型（インターフェースなど）が別ファイルで定義されていると推測されますが、具体的なファイルパスや型名はこのチャンクには現れません (CommandExecOutputStream.ts:L5-6)。 |

> いずれも、このチャンクにコード上の定義や import 文などの形では現れていないため、実際のファイル構成や型の詳細を確認するにはリポジトリ全体の探索が必要です。
