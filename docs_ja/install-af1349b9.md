## インストールとビルド

### システム要件

| 要件                         | 詳細                                                                 |
| ---------------------------- | -------------------------------------------------------------------- |
| オペレーティングシステム     | macOS 12+、Ubuntu 20.04+/Debian 10+、または Windows 11 **（WSL2 経由）** |
| Git（任意、推奨）            | 組み込みの PR ヘルパーを利用するには 2.23 以上                        |
| RAM                          | 4GB 以上（8GB を推奨）                                               |

### DotSlash

GitHub Release には、`codex` という名前の Codex CLI 向け [DotSlash](https://dotslash-cli.com/) ファイルも含まれています。DotSlash ファイルを使用すると、ソース管理に軽量なコミットを行うことで、開発に使用するプラットフォームに関わらず、すべてのコントリビューターが同じバージョンの実行ファイルを使用するようにできます。

### ソースからビルド

```bash
# リポジトリをクローンし、Cargo ワークスペースのルートへ移動します。
git clone https://github.com/openai/codex.git
cd codex/codex-rs

# 必要に応じて Rust ツールチェーンをインストールします。
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup component add rustfmt
rustup component add clippy
# ワークスペースの justfile で使用されるヘルパーツールをインストールします:
cargo install just
# 任意: `just test` ヘルパー用に nextest をインストールします
cargo install --locked cargo-nextest

# Codex をビルドします。
cargo build

# サンプルのプロンプトで TUI を起動します。
cargo run --bin codex -- "explain this codebase to me"

# 変更を加えた後は、ルート justfile のヘルパーを使用します（デフォルトでは codex-rs を対象とします）:
just fmt
just fix -p <crate-you-touched>

# 関連するテストを実行します（プロジェクト固有のものが最も高速です）。例:
cargo test -p codex-tui
# cargo-nextest をインストール済みの場合、`just test` は nextest 経由でテストスイートを実行します:
just test
# 日常的なローカル実行では `--all-features` の使用は避けてください。
# 追加のフィーチャーの組み合わせをコンパイルすることでビルド時間と
# `target/` のディスク使用量が増加するためです。
# 機能を完全にカバーしたい場合は、次を使用します:
cargo test --all-features
```

## トレーシング / 詳細ログ出力

Codex は Rust で実装されているため、ログ動作の構成に `RUST_LOG` 環境変数を使用できます。

TUI のデフォルトは `RUST_LOG=codex_core=info,codex_tui=info,codex_rmcp_client=info` で、ログメッセージはデフォルトで `~/.codex/log/codex-tui.log` に書き込まれます。単一の実行に対しては、`-c log_dir=...`（たとえば `-c log_dir=./.codex-log`）を使ってログディレクトリを上書きできます。

```bash
tail -F ~/.codex/log/codex-tui.log
```

対照的に、非対話モード（`codex exec`）のデフォルトは `RUST_LOG=error` ですが、メッセージはインラインで出力されるため、別ファイルを監視する必要はありません。

設定オプションの詳細については、[`RUST_LOG`](https://docs.rs/env_logger/latest/env_logger/#enabling-logging) に関する Rust のドキュメントを参照してください。
