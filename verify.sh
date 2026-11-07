#!/bin/sh
set -eu

id="${1:-}"
[ -n "$id" ] || { echo "用法: ./verify.sh <编号>"; exit 2; }

entry="jokes/$id.md"
[ -s "$entry" ] || { echo "缺少 $entry"; exit 1; }

grep -q "^## $id$" "$entry" || { echo "$entry 里没有 ## $id"; exit 1; }

if [ -s "images/$id.jpg" ]; then
  img="images/$id.jpg"
elif [ -s "images/$id.png" ]; then
  img="images/$id.png"
else
  echo "缺少 images/$id.jpg"
  exit 1
fi

file "$img" | grep -qE 'JPEG|PNG' || { echo "图片格式不对: $img"; exit 1; }

grep -q '^灵感：\[@' "$entry" || { echo "缺少灵感作者"; exit 1; }

if grep -q '## 自评' "$entry"; then
  echo "$entry 里不应有自评"
  exit 1
fi

echo "verify ok: $id ($img)"
