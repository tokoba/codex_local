#!/bin/bash
find ./codex-rs -name "*.rs" -type f -exec wc -l {} + | sort -nr | head -30
