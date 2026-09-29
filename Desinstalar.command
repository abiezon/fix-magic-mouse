#!/bin/bash
# Desinstalar.command — remove tudo o que o assistente instalou.
# Dois cliques no Finder.

cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1

if [ -t 1 ]; then B=$'\033[1m'; Z=$'\033[0m'; else B=''; Z=''; fi

[ -t 1 ] && [ -n "${TERM:-}" ] && clear
cat <<'CABECALHO'
  ┌──────────────────────────────────────────────┐
  │   Remover o conserto do Magic Mouse          │
  └──────────────────────────────────────────────┘

  Isto remove o ajudante e o programa do seu Mac.

  O seu mouse volta a se comportar como o macOS 27 o deixa —
  ou seja, provavelmente volta a nao funcionar.

  O registro de atividade (/var/log/magicmousefix.log) e'
  mantido; o desinstalador diz como apaga-lo, se voce quiser.

CABECALHO

printf '  %sRemover tudo?%s [s/N] ' "$B" "$Z"
read -r r
case "$r" in
  [sS]|[sS][iI][mM]) ;;
  *) printf '\n  Nada foi removido. Pode fechar esta janela.\n\n'; exit 0 ;;
esac

printf '\n  O Mac vai pedir a senha do seu usuario.\n\n'
sudo ./scripts/uninstall.sh
printf '\n  Pode fechar esta janela.\n\n'
