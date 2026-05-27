#!/usr/bin/env bash
# prescan.sh — предварительный скан C#-кода для skill doc-db.
#
# Извлекает СЫРЬЁ (SQL-литералы, OracleDbType-биндинги, DataRow-маппинги) в
# _tmp/sql-facts.txt, чтобы на крупных проектах (> 200 .cs) Claude не сканировал
# весь код в контекст. Claude затем агрегирует сырьё в модель таблиц
# (концептуальный формат — см. references/extraction-algorithm.md).
#
# Использование:  ./prescan.sh <путь-к-проекту>
# Windows: запускать через Git Bash или WSL.

set -euo pipefail

ROOT="${1:-.}"
OUT_DIR="$ROOT/_tmp"
OUT="$OUT_DIR/sql-facts.txt"

mkdir -p "$OUT_DIR"

{
  echo "# sql-facts — сырые факты prescan ($(date +%F))"
  echo "# Корень: $ROOT"
  echo

  echo "## SQL-литералы (INSERT / UPDATE / SELECT / DELETE)"
  grep -rEn --include='*.cs' \
    -e 'INSERT[[:space:]]+INTO[[:space:]]+[A-Z0-9_.]+' \
    -e 'UPDATE[[:space:]]+[A-Z0-9_.]+[[:space:]]+SET' \
    -e 'SELECT[[:space:]].+[[:space:]]FROM[[:space:]]+[A-Z0-9_.]+' \
    -e 'DELETE[[:space:]]+FROM[[:space:]]+[A-Z0-9_.]+' \
    "$ROOT" || true
  echo

  echo "## Bind-параметры (OracleDbType)"
  grep -rEn --include='*.cs' \
    -e '\.Parameters\.Add\([[:space:]]*"[:]?p_[A-Z0-9_]+"[[:space:]]*,[[:space:]]*OracleDbType\.[A-Za-z0-9]+' \
    "$ROOT" || true
  echo

  echo '## DataRow-маппинг (dr["COL"].ToXxx())'
  grep -rEn --include='*.cs' \
    -e 'dr\[[[:space:]]*"[A-Z0-9_]+"[[:space:]]*\][[:space:]]*\.[[:space:]]*To[A-Za-z]+\(\)' \
    "$ROOT" || true
} > "$OUT"

echo "Готово: $OUT"
echo "Строк: $(wc -l < "$OUT")"
