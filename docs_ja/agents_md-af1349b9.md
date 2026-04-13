# AGENTS.md

AGENTS.md についての情報は、[このドキュメント](https://developers.openai.com/codex/guides/agents-md)を参照してください。

## 階層型エージェントメッセージ

`config.toml` の `[features]` で `child_agents_md` フィーチャーフラグが有効になっている場合、Codex は AGENTS.md のスコープと優先順位に関する追加のガイダンスをユーザー指示メッセージに付加し、AGENTS.md が存在しない場合でもそのメッセージを出力します。
