#!/bin/sh
# A Fastlight extension in plain POSIX sh, using only what every Mac has:
# "bc 2*(3+4)" asks bc. (Fastlight's own calculator is built in, on "=" and
# in normal search; this is an example to copy from.)
# Protocol: docs/extensions/README.md.

# Handshake: the first line says which protocol version we speak.
echo '{"type":"ready","protocol":1}'

# One request per line. Fastlight writes compact JSON with sorted keys, so
# sed can pick fields out; a real parser would be safer for free text.
while IFS= read -r line; do
  id=$(printf '%s\n' "$line" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
  [ -n "$id" ] || continue # notifications have no id and get no reply

  case "$line" in
    *'"type":"search"'*) ;;
    *) printf '{"id":%s,"error":"unsupported request"}\n' "$id"; continue ;;
  esac

  expr=$(printf '%s\n' "$line" | sed -n 's/.*"query":"\([^"]*\)".*/\1/p')
  # Only digits, operators, dots, parentheses and spaces go to bc, with at
  # least one operator between numbers: "2024" alone isn't a calculation.
  if [ -z "$expr" ] || [ -n "$(printf '%s' "$expr" | tr -d '0-9+*/%^(). -')" ] ||
    ! printf '%s' "$expr" | grep -q '[0-9)] *[-+*/%^] *[0-9(.]'; then
    printf '{"id":%s,"items":[]}\n' "$id"
    continue
  fi

  # scale=10 for decimals, then trim trailing zeros and a bare dot.
  result=$(printf 'scale=10; %s\n' "$expr" | BC_LINE_LENGTH=0 bc -l 2>/dev/null |
    sed -e 's/^\(-\{0,1\}\)\./\10./' -e '/\./s/0*$//' -e 's/\.$//')
  case "$result" in
    '' | *[!0-9.-]*) printf '{"id":%s,"items":[]}\n' "$id"; continue ;;
  esac

  printf '{"id":%s,"items":[{"id":"result","title":"%s","subtitle":"%s","icon":"terminal",' "$id" "$result" "$expr"
  printf '"actions":[{"type":"copy","text":"%s","title":"Copy Result"},' "$result"
  printf '{"type":"paste","text":"%s","title":"Paste Result"}]}]}\n' "$result"
done
