#!/bin/sh
set -eu

id="${1:-}"
[ -n "$id" ] || { echo "用法: ./verify.sh <编号>"; exit 2; }

grep -q "^## $id$" joke.md || { echo "joke.md 里没有 ## $id"; exit 1; }

if [ -s "images/$id.jpg" ]; then
  img="images/$id.jpg"
elif [ -s "images/$id.png" ]; then
  img="images/$id.png"
else
  echo "缺少 images/$id.jpg"
  exit 1
fi

file "$img" | grep -qE 'JPEG|PNG' || { echo "图片格式不对: $img"; exit 1; }

awk "/^## $id$/{f=1;next} /^## /{f=0} f" joke.md | grep -q '^> ' \
  || { echo "缺少英文引用行"; exit 1; }

awk "/^## $id$/{f=1;next} /^## /{f=0} f" joke.md | grep -q '^灵感：\[@' \
  || { echo "缺少灵感作者"; exit 1; }

if grep -q '## 自评' joke.md; then
  echo "joke.md 里不应有自评"
  exit 1
fi

echo "verify ok: $id ($img)"
