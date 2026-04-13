# TUI Stream Chunking 調整ガイド

本書は、基盤となるポリシーの形を変更することなく、adaptive stream chunking の定数をどのように調整するかを説明します。

## Scope

このガイドは、`codex-rs/tui/src/streaming/chunking.rs` 内のキュープレッシャーのしきい値およびヒステリシスウィンドウと、`codex-rs/tui/src/app.rs` 内のベースラインのコミットケイデンスを調整する際に使用します。

このガイドの対象は挙動のチューニングであり、ポリシーの再設計ではありません。

## Before tuning

- ベースラインの挙動を維持すること:
  - `Smooth` モードは、ベースラインのティックごとに 1 行を処理します。
  - `CatchUp` モードは、キューにたまったバックログを即座に処理します。
- 次を使ってトレースログを取得すること:
  - `codex_tui::streaming::commit_tick`
- 持続的出力、バースト的出力、および混在出力のプロンプトで評価すること。

計測手順については `docs/tui-stream-chunking-validation.md` を参照してください。

## Tuning goals

以下 3 つの目標を同時に満たすように調整します:

- バースト出力時の目に見える遅延を小さくする
- モードのフラッピング（`Smooth <-> CatchUp` のチャタリング）を抑える
- 混在したワークロード下での catch-up のエントリー/エグジット挙動を安定させる

## Constants and what they control

### Baseline commit cadence

- `COMMIT_ANIMATION_TICK` (`tui/src/app.rs`)
  - 値を小さくすると Smooth モードの更新ケイデンスが上がり、定常状態の遅延が減ります。
  - 値を大きくするとスムージングが強まり、体感の遅延が増える可能性があります。
  - これは通常、チャンク分割のしきい値やホールドが良い範囲に収まった後で変更するべきです。

### Enter/exit thresholds

- `ENTER_QUEUE_DEPTH_LINES`, `ENTER_OLDEST_AGE`
  - 値を小さくすると、より早く catch-up に入ります（遅延は減るが、モード切り替えのリスクは増える）。
  - 値を大きくすると、より遅く catch-up に入ります（遅延許容量は増えるが、モード切り替えは減る）。
- `EXIT_QUEUE_DEPTH_LINES`, `EXIT_OLDEST_AGE`
  - 値を小さくすると、catch-up をより長く維持します。
  - 値を大きくすると、より早く exit できる一方で、再度のエントリーが増える可能性があります。

### Hysteresis holds

- `EXIT_HOLD`
  - ホールド時間を長くすると、プレッシャーがノイジーな場合のフリップフロップ的な exit を軽減できます。
  - 長すぎると、プレッシャーが解消された後でも catch-up が有効なままになり得ます。
- `REENTER_CATCH_UP_HOLD`
  - ホールド時間を長くすると、exit 直後の急速な再エントリーを抑制できます。
  - 長すぎると、近い将来のバーストに対する必要な catch-up が遅れる可能性があります。
  - 深刻なバックログは、設計上このホールドをバイパスします。

### Severe-backlog gates

- `SEVERE_QUEUE_DEPTH_LINES`, `SEVERE_OLDEST_AGE`
  - 値を小さくすると、再エントリーホールドをより早くバイパスします。
  - 値を大きくすると、極端なプレッシャーの場合にのみホールドのバイパスを許可します。

## Recommended tuning order

因果関係を明確に保つため、次の順序で調整します:

1. エントリー/エグジットのしきい値 (`ENTER_*`, `EXIT_*`)
2. ホールドウィンドウ (`EXIT_HOLD`, `REENTER_CATCH_UP_HOLD`)
3. Severe gate (`SEVERE_*`)
4. ベースラインケイデンス (`COMMIT_ANIMATION_TICK`)

一度に 1 つの論理グループだけ変更し、次のグループに進む前に必ず再計測してください。

## Symptom-driven adjustments

- catch-up が開始されるまでのラグが大きすぎる場合:
  - `ENTER_QUEUE_DEPTH_LINES` および/または `ENTER_OLDEST_AGE` を下げる
- `Smooth -> CatchUp -> Smooth` のチャタリングが頻発する場合:
  - `EXIT_HOLD` を増やす
  - `REENTER_CATCH_UP_HOLD` を増やす
  - エグジットしきい値を厳しくする（`EXIT_*` を下げる）
- 短いバーストに対して catch-up が頻繁に有効化される場合:
  - `ENTER_QUEUE_DEPTH_LINES` および/または `ENTER_OLDEST_AGE` を上げる
  - `REENTER_CATCH_UP_HOLD` を増やす
- catch-up の有効化が遅すぎる場合:
  - `ENTER_QUEUE_DEPTH_LINES` および/または `ENTER_OLDEST_AGE` を下げる
  - Severe gate (`SEVERE_*`) を下げて、再エントリーホールドのバイパスを早める

## Validation checklist after each tuning pass

- `cargo test -p codex-tui` が通ること。
- トレースウィンドウで、キューの age が有界である挙動になっていること。
- モード遷移が、短い間隔のサイクルに繰り返し集中していないこと。
- モードが `CatchUp` に入ったら、catch-up がバックログを素早く解消すること。
