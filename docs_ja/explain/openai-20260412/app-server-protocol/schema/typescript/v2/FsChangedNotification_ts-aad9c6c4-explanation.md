# app-server-protocol/schema/typescript/v2/FsChangedNotification.ts コード解説

## 0. ざっくり一言

`fs/watch` 購読者向けに送られる「ファイルシステム変更通知」のペイロードを表す、TypeScript のオブジェクト型定義です（`FsChangedNotification`）。（FsChangedNotification.ts:L6-9）

---

## 1. このモジュールの役割

### 1.1 概要

- このモジュールは、`fs/watch` 機能から送信されるファイルシステム監視イベント通知を表現するための型 `FsChangedNotification` を提供します。（FsChangedNotification.ts:L6-9）
- 通知には、監視を識別する `watchId`（文字列）と、そのイベントに関係するファイルまたはディレクトリの絶対パス配列 `changedPaths` が含まれます。（FsChangedNotification.ts:L10-13, L14-17）

### 1.2 アーキテクチャ内での位置づけ

このモジュールは以下のような位置づけにあります。

- `AbsolutePathBuf` 型に依存し、変更されたパスをその型で表現します。（FsChangedNotification.ts:L4, L17）
- コメントから、`fs/watch` と呼ばれるファイル監視機構から通知されるイベントのメッセージスキーマであることが読み取れます。（FsChangedNotification.ts:L6-8）

```mermaid
graph LR
    subgraph "このチャンク"
        A[FsChangedNotification 型<br/>(FsChangedNotification.ts:L9-17)]
    end

    B[AbsolutePathBuf 型<br/>(../AbsolutePathBuf)<br/>※定義はこのチャンクに存在しない] --> A

    C["fs/watch" 機構（概念）<br/>※実装はこのチャンクに存在しない] --> A
    A --> D[fs/watch 購読者（クライアント側コード）<br/>※このチャンクには存在しない]
```

> `fs/watch` やクライアントコードの具体的な実装は、このチャンクには現れていません。上記はコメントから読み取れる概念的な位置づけです。（FsChangedNotification.ts:L6-8）

### 1.3 設計上のポイント

- **自動生成コードであること**  
  ファイル先頭コメントにより、このファイルは `ts-rs` によって生成されたコードであり、手動編集してはいけないことが明記されています。（FsChangedNotification.ts:L1-3）

- **型専用インポート (`import type`)**  
  `AbsolutePathBuf` は `import type` で取り込まれており、型情報のみを参照し、実行時にはインポートが消える形になっています（バンドルサイズや実行時依存を増やさないための TypeScript 特有の機能）。（FsChangedNotification.ts:L4）

- **純粋なデータ構造**  
  関数やクラス、ロジックは一切持たず、通知ペイロードの構造だけを定義する役割に限定されています。（FsChangedNotification.ts:L9-17）

- **エラー処理・並行性は外部に委譲**  
  このファイルにはエラーハンドリングや非同期処理・並行性に関するコードは存在せず、これらは `FsChangedNotification` を利用する側の責務となります。（FsChangedNotification.ts:L1-17）

---

## 2. 主要な機能一覧

このモジュールが提供する機能は「型定義」に集約されています。

- `FsChangedNotification` 型: `fs/watch` から送られるファイルシステム変更通知のペイロードを表現するオブジェクト型（FsChangedNotification.ts:L6-9）
- `watchId` プロパティ: 通知がどの監視に対応するかを識別する ID（文字列型）を保持（FsChangedNotification.ts:L10-13）
- `changedPaths` プロパティ: このイベントに関連するファイル・ディレクトリの絶対パス一覧を `AbsolutePathBuf` 型の配列として保持（FsChangedNotification.ts:L14-17）

---

## 3. 公開 API と詳細解説

### 3.1 型一覧（構造体・列挙体など）

このファイルに定義されている公開型は 1 つです。

| 名前 | 種別 | 役割 / 用途 | 根拠 |
|------|------|-------------|------|
| `FsChangedNotification` | 型エイリアス（オブジェクト型） | `fs/watch` 購読者に対して送られる、ファイルシステム変更通知メッセージの構造を表す | FsChangedNotification.ts:L6-9 |

`FsChangedNotification` のフィールド構造は次のとおりです。

| フィールド名 | 型 | 説明 | 必須 | 根拠 |
|-------------|----|------|------|------|
| `watchId` | `string` | 以前 `fs/watch` によって払い出された監視 ID。どの監視からのイベントかを識別するために使われる。 | 必須（オプショナル指定なし） | FsChangedNotification.ts:L10-13 |
| `changedPaths` | `Array<AbsolutePathBuf>` | このイベントに関連するファイルまたはディレクトリの絶対パス一覧。要素の型は `AbsolutePathBuf`。 | 必須（オプショナル指定なし） | FsChangedNotification.ts:L14-17 |

> `AbsolutePathBuf` 型の定義はこのチャンクには含まれていません。そのため、具体的な構造や表現形式（文字列かオブジェクトかなど）は不明です。（FsChangedNotification.ts:L4）

### 3.2 関数詳細（最大 7 件）

このファイルには関数・メソッドの宣言は存在しません。（FsChangedNotification.ts:L1-17）

- したがって、エラー発生条件やパニック条件など、関数単位での挙動はここからは読み取れません。
- 型定義としての役割に専念しており、実際の送受信・バリデーション・ロギングなどはすべて別モジュール側の責務になります。

### 3.3 その他の関数

このファイルには補助関数・ラッパー関数も含まれていません。（FsChangedNotification.ts:L1-17）

---

## 4. データフロー

ここでは、`FsChangedNotification` が関わる典型的な処理の流れを、コメント情報から読み取れる範囲で概念的に整理します。

### 4.1 処理の要点

- あるコンポーネント（ここでは「fs/watch 発行元」とします）がファイルシステムを監視し、変化を検知します。
- 変化が検知されると、監視に対応する `watchId` と、影響のあったファイル/ディレクトリの絶対パスを `changedPaths` にまとめ、`FsChangedNotification` 型のオブジェクトが構築されます。（FsChangedNotification.ts:L10-17）
- そのオブジェクトが `fs/watch` の購読者へと通知され、購読者は `watchId` と `changedPaths` に基づき処理を行います。（FsChangedNotification.ts:L6-8）

※ 実際の監視ロジックや通知の送信経路はこのチャンクには存在しないため、下記は「想定される利用シナリオ」です。

### 4.2 シーケンス図

```mermaid
sequenceDiagram
    participant Watcher as fs/watch 発行元
    participant Note as FsChangedNotification<br/>(FsChangedNotification.ts:L9-17)
    participant Client as fs/watch 購読クライアント

    Watcher->>Watcher: ファイルシステムを監視
    Watcher->>Note: watchId, changedPaths を設定したオブジェクトを生成
    Note-->>Client: 通知ペイロードとして送信
    Client->>Client: watchId / changedPaths に基づき処理を実行
```

この図は、`FsChangedNotification` が「fs/watch 発行元」と「購読クライアント」の間でやり取りされるデータの容器として機能することを表しています。（FsChangedNotification.ts:L6-9）

---

## 5. 使い方（How to Use）

### 5.1 基本的な使用方法

ここでは、`FsChangedNotification` をイベントハンドラの引数として受け取り、監視 ID と変更されたパスを処理する基本的な例を示します。

```typescript
// FsChangedNotification 型をインポートする                 // 型のみ利用するので import type が推奨
import type { FsChangedNotification } from "./FsChangedNotification"; // パスは例（同ディレクトリ想定）

// ファイル変更通知を処理する関数                            // fs/watch から通知を受け取るハンドラを仮定
function onFsChanged(notification: FsChangedNotification) {   // 引数に型を付けることで型安全性を確保
    console.log("watch:", notification.watchId);              // watchId は string として扱える

    for (const path of notification.changedPaths) {           // changedPaths は AbsolutePathBuf の配列
        // path の具体的な構造はこのチャンクからは不明         // ここでは単にログに出す例を示す
        console.log("changed:", path);
    }
}
```

このように型アノテーションを付けることで、

- `watchId` を数値として扱う、といった型の取り違えをコンパイル時に検出できます。（FsChangedNotification.ts:L13）
- `changedPaths` を配列ではなく単一の値として扱おうとした場合も、コンパイル時にエラーとなります。（FsChangedNotification.ts:L17）

### 5.2 よくある使用パターン

1. **イベントハンドラの引数として利用**

   ```typescript
   import type { FsChangedNotification } from "./FsChangedNotification";

   type FsWatchListener = (notification: FsChangedNotification) => void; // リスナー型を定義

   const listeners: FsWatchListener[] = [];                     // リスナーの配列

   function addFsWatchListener(listener: FsWatchListener) {     // 追加関数（例）
       listeners.push(listener);
   }

   // 内部でファイル変更を検知したと仮定し、通知を配信する例
   function dispatchNotification(n: FsChangedNotification) {    // n の構造は型で保証される
       for (const listener of listeners) {
           listener(n);                                         // 各リスナーに通知
       }
   }
   ```

2. **通知の配列としてバッチ処理**

   ```typescript
   import type { FsChangedNotification } from "./FsChangedNotification";

   function handleBatch(notifications: FsChangedNotification[]) {   // 通知の配列をまとめて処理
       for (const n of notifications) {
           // watchId ごとに処理を分岐するなどの利用が想定される
           console.log(n.watchId, n.changedPaths.length);
       }
   }
   ```

### 5.3 よくある間違い

この型定義に照らすと、次のような誤用が起こりやすいと考えられます。

```typescript
import type { FsChangedNotification } from "./FsChangedNotification";

// 誤り例: changedPaths を単一の値として扱っている
function wrongHandler(notification: FsChangedNotification) {
    // const firstPath: string = notification.changedPaths;   // コンパイルエラー:
                                                              // 'Array<AbsolutePathBuf>' を 'string' に代入できない
}

// 正しい例: 配列として扱う
function correctHandler(notification: FsChangedNotification) {
    const [firstPath] = notification.changedPaths;           // 配列の分割代入で 1 件目を取得
    if (firstPath) {
        console.log(firstPath);
    }
}
```

- TypeScript の型チェックにより、このような誤用はコンパイル段階で検出できます。（FsChangedNotification.ts:L14-17）

### 5.4 使用上の注意点（まとめ）

- **必須フィールドであること**  
  `watchId` と `changedPaths` はどちらも必須プロパティであり、オプショナル（`?`）指定はありません。そのため、`FsChangedNotification` 型を満たすオブジェクトを生成する場合、この 2 つのプロパティを必ず設定する必要があります。（FsChangedNotification.ts:L9-17）

- **changedPaths の性質**  
  `changedPaths` は配列であり、「変更されたパスが 1 つだけ」の場合でも配列として渡されます。単一値ではない点に注意が必要です。（FsChangedNotification.ts:L14-17）

- **パスの妥当性チェックは別途必要**  
  この型定義自体は、パス文字列の正当性や存在確認などを行いません。  
  実際にファイル操作を行う場合は、利用側で適切な検証・サニタイズを行う必要があります。（FsChangedNotification.ts:L9-17）

- **実行時エラー・並行性**  
  本ファイルには実行時コードがないため、ここから直接発生するランタイムエラーや並行性の問題はありません。実際のエラーやレースコンディション等は、この型を利用する I/O や非同期処理側の実装に依存します。（FsChangedNotification.ts:L1-17）

---

## 6. 変更の仕方（How to Modify）

### 6.1 新しい機能を追加する場合

このファイルは `ts-rs` によって自動生成されており、「手で編集しないこと」が明示されています。（FsChangedNotification.ts:L1-3）

そのため、**新しいフィールドを追加したい場合でも、このファイルを直接編集すべきではありません。**

一般的な手順は次のようになります（コードから推測できる範囲の一般論です）。

1. **生成元（Rust 側など）の定義を変更**  
   - `ts-rs` の出力元となる構造体・型定義（おそらく Rust 側の構造体）に、通知に必要なフィールドを追加します。  
   - そのファイルパスや構造体名はこのチャンクからは分かりません。（FsChangedNotification.ts:L1-3）

2. **`ts-rs` を再実行して TypeScript コードを再生成**  
   - ビルドスクリプトや専用コマンドを通じて、TypeScript 側のスキーマを再生成します。
   - 再生成により、このファイルの `FsChangedNotification` 定義に新フィールドが反映されます。

3. **通知を利用している箇所を更新**  
   - 新しく追加されたフィールドを利用するクライアントコードを適宜更新します。

### 6.2 既存の機能を変更する場合

例えば `watchId` の型を `string` から `number` に変更したい、といったケースでも、同様に生成元を変更する必要があります。

変更時に注意すべき点:

- **生成元の変更が単一の真実の源泉**  
  - `FsChangedNotification` の構造は、生成元の型定義が唯一の正とみなされるべきです。TypeScript 側だけを手動で変更すると、Rust 側などとの不整合が生じる可能性があります。（FsChangedNotification.ts:L1-3）

- **影響範囲の確認**  
  - `watchId` や `changedPaths` に依存した処理（フィルタリング、ログ出力、UI 表示など）は、変更後の型に合わせてすべて洗い出して修正する必要があります。  
  - これらの使用箇所は、このチャンクには現れないため、別ファイルを検索して特定することになります。（FsChangedNotification.ts:L9-17）

- **後方互換性**  
  - プロトコルとして利用される型である可能性が高いため、既存クライアントとの互換性に注意が必要です。  
  - 例えばフィールド削除や型変更は、古いクライアントとの通信に影響する可能性があります。

---

## 7. 関連ファイル

このモジュールと密接に関係すると読み取れるファイル・概念を整理します。

| パス / 概念 | 役割 / 関係 | 根拠 |
|-------------|------------|------|
| `../AbsolutePathBuf` | `AbsolutePathBuf` 型をエクスポートしているモジュール。`changedPaths` の要素型として利用される。具体的な構造はこのチャンクからは不明。 | FsChangedNotification.ts:L4, L17 |
| `fs/watch`（概念） | コメント中に登場するファイルシステム監視機構。`FsChangedNotification` はこの監視機構の購読者向け通知ペイロードとして利用される。実装や定義はこのチャンクには存在しない。 | FsChangedNotification.ts:L6-8 |
| `ts-rs` 生成元（Rust 側など） | 本 TypeScript 型定義を自動生成するための元となる定義。Rust の構造体であるとコメントから推測できるが、具体的なファイルパスや型名は不明。変更はここに対して行う必要がある。 | FsChangedNotification.ts:L1-3 |

---

### 付記: 安全性・エラー・並行性に関するまとめ

- **型安全性（TypeScript 特有）**  
  - `FsChangedNotification` を使って関数引数や返り値に型を付けることで、`watchId` や `changedPaths` の誤用をコンパイル時に検出できます。（FsChangedNotification.ts:L9-17）
  - `import type` を利用しているため、実行時には余計な依存を増やさず、あくまで型レベルの保証に留まります。（FsChangedNotification.ts:L4）

- **エラー処理**  
  - このファイルは純粋な型定義であり、実行時のバリデーションや例外処理は含みません。  
  - 不正な JSON からのデシリアライズやスキーマとの不整合などは、別のレイヤー（パーサ・バリデータ）で扱う必要があります。（FsChangedNotification.ts:L1-17）

- **並行性・非同期性**  
  - 本ファイルには非同期処理やスレッド関連のコードは存在しないため、このファイル由来のレースコンディションやデッドロックはありません。  
  - ただし、`FsChangedNotification` を受け取る処理が非同期イベント駆動であることは想定されますが、その具体的な実装はこのチャンクには現れていません。（FsChangedNotification.ts:L6-8）
