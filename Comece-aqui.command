#!/bin/bash
# Comece-aqui.command — assistente guiado para quem nao usa Terminal.
#
# No Finder, um arquivo .command abre no Terminal com dois cliques. E' por isso que este
# arquivo existe: e' a unica porta de entrada que nao exige saber abrir o Terminal, nem
# navegar ate' a pasta, nem decorar comando nenhum.
#
# Ele nao faz nada sozinho: cada passo que toca o mouse ou o sistema pergunta antes.

cd -- "$(dirname -- "${BASH_SOURCE[0]}")" || exit 1

# Cores (desligadas se a saida nao for um terminal)
if [ -t 1 ]; then
  B=$'\033[1m'; V=$'\033[32m'; A=$'\033[33m'; R=$'\033[31m'; Z=$'\033[0m'
else
  B=''; V=''; A=''; R=''; Z=''
fi

titulo()  { printf '\n%s━━━ %s ━━━%s\n\n' "$B" "$1" "$Z"; }
ok()      { printf '  %s✓%s %s\n' "$V" "$Z" "$1"; }
aviso()   { printf '  %s!%s %s\n' "$A" "$Z" "$1"; }
erro()    { printf '  %s✗%s %s\n' "$R" "$Z" "$1"; }
info()    { if [ -z "$1" ]; then printf '\n'; else printf '    %s\n' "$1"; fi; }

# pergunta "texto"  -> 0 se a pessoa responder s/sim
pergunta() {
  local resposta
  printf '\n  %s%s%s [s/N] ' "$B" "$1" "$Z"
  read -r resposta
  case "$resposta" in [sS]|[sS][iI][mM]) return 0 ;; *) return 1 ;; esac
}

limpa_tela() { [ -t 1 ] && [ -n "${TERM:-}" ] && clear; return 0; }

fim() {
  printf '\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$B" "$Z"
  printf '  Pode fechar esta janela.\n\n'
  exit "${1:-0}"
}

limpa_tela
cat <<'CABECALHO'
  ┌──────────────────────────────────────────────┐
  │   Conserto do Magic Mouse no macOS 27        │
  └──────────────────────────────────────────────┘

  Depois da atualizacao para o macOS 27, o Magic Mouse conecta,
  mostra a bateria... e nao mexe o cursor. Isso e' um defeito do
  proprio macOS 27.

  Este assistente vai, um passo de cada vez:

    1. conferir se o seu Mac e' mesmo um caso desses
    2. preparar o programa
    3. conferir que ele e' seguro
    4. procurar o seu mouse (sem mexer nele)
    5. perguntar se voce quer aplicar o conserto
    6. perguntar se quer deixar o conserto permanente

  Nada acontece sem voce responder "s". Voce pode parar em
  qualquer ponto fechando esta janela.

CABECALHO

printf '  %sPressione ENTER para comecar%s (ou feche a janela para sair) ' "$B" "$Z"
read -r _

# ── 1. O Mac ────────────────────────────────────────────────────────────────
titulo "1 de 6 — Conferindo o seu Mac"

versao=$(sw_vers -productVersion)
principal=${versao%%.*}
info "macOS $versao"

if [ "$principal" = "27" ]; then
  ok "Esta e' a versao afetada pelo defeito."
else
  aviso "Este conserto foi feito para o macOS 27; voce esta no $versao."
  info "Nas outras versoes o defeito nao existe, entao o conserto"
  info "provavelmente nao vai mudar nada."
  pergunta "Quer continuar mesmo assim?" || fim 0
fi

achou_mouse=$(system_profiler SPBluetoothDataType 2>/dev/null | grep -ci 'magic mouse')
if [ "${achou_mouse:-0}" -gt 0 ]; then
  ok "Encontrei um Magic Mouse pareado com este Mac."
else
  aviso "Nao encontrei nenhum Magic Mouse pareado."
  info "Ligue o mouse e confira em Ajustes do Sistema > Bluetooth"
  info "que ele aparece como conectado."
  pergunta "Quer continuar mesmo assim?" || fim 0
fi

# ── 2. Preparar ─────────────────────────────────────────────────────────────
titulo "2 de 6 — Preparando o programa"

if ! xcode-select -p >/dev/null 2>&1 || ! command -v clang >/dev/null 2>&1; then
  erro "Falta no seu Mac a ferramenta que monta o programa."
  info ""
  info "Ela e' gratuita e vem da propria Apple. Da' para pedir a instalacao"
  info "daqui mesmo: a Apple abre uma janela e voce so' precisa aceitar."
  info ""

  # Nao adianta mandar a pessoa digitar um comando "aqui embaixo": assim que este
  # assistente terminar, a janela do Terminal para de aceitar entrada. Ou pedimos a
  # instalacao por ela, ou damos um caminho que funcione depois que ele sair.
  if pergunta "Pedir a instalacao agora?"; then
    xcode-select --install >/dev/null 2>&1
    info ""
    info "Pedido enviado. Se a janela da Apple apareceu, aceite e espere"
    info "a instalacao terminar (costuma levar alguns minutos)."
    info ""
    info "Quando acabar, de' dois cliques neste mesmo arquivo de novo."
  else
    info ""
    info "Sem problema. Quando quiser instalar por conta propria:"
    info ""
    info "  1. Abra o app Terminal (Launchpad > Outros > Terminal)"
    info "  2. Digite:  xcode-select --install"
    info "  3. Aceite a janela da Apple e espere terminar"
    info "  4. Volte aqui e de' dois cliques neste arquivo de novo"
  fi
  echo
  fim 1
fi
ok "Ferramentas da Apple encontradas."

info "Montando o programa..."
if saida=$(make build 2>&1); then
  ok "Programa pronto."
else
  erro "Nao consegui montar o programa."
  echo "$saida" | tail -15 | sed 's/^/      /'
  fim 1
fi

# ── 3. Seguranca ────────────────────────────────────────────────────────────
titulo "3 de 6 — Conferindo que o programa e' seguro"

info "Estas checagens sao automaticas e leem o proprio codigo:"
if saida=$(./tests/run.sh 2>&1); then
  # A suite reporta "N passed, M failed" em ingles; aqui so' o numero interessa.
  n=$(echo "$saida" | tail -1 | awk '{print $1}')
  ok "${n:-Todas as} checagens passaram."
  info ""
  info "Entre outras coisas, elas confirmam que o programa:"
  info "  • nao le o que voce digita nem clica"
  info "  • nao acessa a internet"
  info "  • nao grava arquivo nenhum"
  info "  • so' abre o Magic Mouse — nao toca no teclado"
else
  erro "Alguma checagem de seguranca falhou. Melhor parar por aqui."
  echo "$saida" | tail -20 | sed 's/^/      /'
  fim 1
fi

# ── 4. Procurar o mouse ─────────────────────────────────────────────────────
titulo "4 de 6 — Procurando o seu mouse"

cat <<'EXPLICA'
    Para falar com o mouse, o macOS exige permissao de administrador.
    O Mac vai pedir a SENHA DO SEU USUARIO agora.

    Nada e' enviado ao mouse neste passo: este e' so' o teste de
    "olhar sem tocar". Voce ainda vai poder desistir depois dele.

EXPLICA

if ! sudo -v; then
  erro "Sem a senha nao da' para continuar."
  fim 1
fi

if saida=$(sudo ./magicmousefix --dry-run 2>&1); then
  ok "Achei o seu mouse:"
  echo "$saida" | sed 's/^/      /'
else
  aviso "Nao encontrei o mouse agora."
  echo "$saida" | sed 's/^/      /'
  info ""
  info "O mouse costuma sumir quando entra em repouso. Mexa nele ou"
  info "desligue e ligue o botao embaixo, e rode este assistente de novo."
  fim 1
fi

# ── 5. Aplicar ──────────────────────────────────────────────────────────────
titulo "5 de 6 — Aplicar o conserto"

cat <<'EXPLICA'
    Agora sim: o programa vai enviar ao mouse a mensagem de 4 bytes
    que o macOS 27 deixou de enviar.

    Isso nao e' permanente e nao altera nada dentro do mouse: o efeito
    acaba quando o mouse desconecta ou o Mac dorme. Se nao gostar do
    resultado, desligue e ligue o mouse e tudo volta como estava.

EXPLICA

if pergunta "Aplicar o conserto agora?"; then
  if sudo ./magicmousefix; then
    ok "Conserto aplicado."
    info ""
    info "Mexa o mouse agora. Ele deve estar funcionando."
  else
    aviso "O mouse nao aceitou a mensagem."
    info "Desligue e ligue o mouse e tente este assistente de novo."
    fim 1
  fi
else
  info "Tudo bem, nao apliquei nada."
  fim 0
fi

# ── 6. Permanente ───────────────────────────────────────────────────────────
titulo "6 de 6 — Deixar o conserto permanente"

cat <<'EXPLICA'
    O conserto acima vale ate' o mouse desconectar ou o Mac dormir.
    Para nao precisar repetir, da' para deixar um ajudante instalado:
    ele reaplica o conserto sozinho toda vez que o mouse volta, e
    tambem depois de reiniciar o Mac.

    Ele instala tres coisas, e SO' estas tres:

      /usr/local/libexec/magicmousefix                    o programa
      /Library/LaunchDaemons/com.local.magicmousefix.plist  o ajudante
      /etc/newsyslog.d/magicmousefix.conf                 limpeza do log

    Para remover tudo depois, e' so' dar dois cliques no arquivo
    "Desinstalar.command", nesta mesma pasta.

EXPLICA

if pergunta "Deixar o conserto permanente?"; then
  if sudo ./scripts/install.sh; then
    ok "Ajudante instalado."
    info "Teste: desligue e ligue o mouse — ele deve voltar sozinho."
  else
    aviso "A instalacao nao terminou. O conserto do passo 5 continua valendo"
    info "ate' o mouse desconectar."
    fim 1
  fi
else
  info "Sem problema. O conserto do passo 5 vale ate' o mouse desconectar;"
  info "e' so' rodar este assistente de novo quando precisar."
fi

titulo "Pronto"
cat <<'FINAL'
    Vale avisar a Apple, para que consertem de verdade:
    https://www.apple.com/feedback/macos.html

    Para desfazer tudo: dois cliques em "Desinstalar.command".
FINAL
fim 0
