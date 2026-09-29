# Guia rápido — meu Magic Mouse parou depois do macOS 27

Escrito para quem não usa Terminal. Se você já é de linha de comando, o
[`README.md`](../README.md) tem o caminho manual.

## O que aconteceu com o seu mouse

Depois da atualização para o macOS 27, o Magic Mouse:

- aparece como **Conectado** no Bluetooth,
- **mostra a bateria** normalmente,
- e **não mexe o cursor**, não clica, não faz gesto nenhum.

Não é o seu mouse que quebrou, nem a bateria. O macOS 27 deixou de enviar ao mouse uma
mensagenzinha de 4 bytes que o coloca em modo multi-touch. O mouse fica ligado esperando uma ordem
que nunca chega. O macOS 26 enviava.

Este programa envia essa mensagem no lugar do macOS. É só isso que ele faz.

## Como usar

**Dois cliques no arquivo `Comece-aqui.command`**, na pasta do projeto.

Abre uma janela preta (o Terminal) com um assistente que conduz tudo, um passo por vez. Você só
precisa ler e responder.

Se o macOS recusar abrir o arquivo, clique nele com o **botão direito** e escolha **Abrir** — aí
aparece o botão "Abrir mesmo assim", que o duplo clique não oferece.

## O que o assistente vai fazer

| Passo | O que acontece | Mexe no mouse? |
|---|---|---|
| 1 | Confere se o seu Mac é mesmo um caso desses | não |
| 2 | Monta o programa | não |
| 3 | Roda as checagens de segurança | não |
| 4 | Procura o seu mouse e mostra o que achou | **não** |
| 5 | Pergunta se você quer aplicar o conserto | só se você disser "s" |
| 6 | Pergunta se quer deixar permanente | só se você disser "s" |

Nada acontece sem você responder **s**. Fechar a janela para tudo.

## Duas coisas que ele vai pedir

**As ferramentas da Apple.** Se faltarem, o assistente para no passo 2 e mostra o comando para
instalá-las (`xcode-select --install`). São gratuitas, vêm da própria Apple, e você só precisa
fazer isso uma vez.

**A sua senha.** Para falar com o mouse, o macOS exige permissão de administrador — é a mesma senha
que você usa para desbloquear o Mac. Ela é pedida pelo próprio sistema, não pelo programa, e o
programa nunca a vê.

## "É seguro rodar isso?"

Pergunta justa — é código de um estranho, rodando com permissão de administrador, escrevendo num
aparelho seu. O que dá para afirmar:

- **É um arquivo só, com cerca de 450 linhas**, e ele é entregue como código, não como programa
  pronto — justamente para poder ser lido antes de ser rodado.
- **Não lê o que você digita nem clica.** Não acessa a internet. Não grava arquivo nenhum. Não
  executa outro programa. O passo 3 do assistente confere as quatro coisas lendo o próprio código —
  não é promessa de texto, é checagem automática que falha se alguém mexer.
- **Só abre o Magic Mouse.** Seus teclados não são nem abertos. (Essa foi a principal mudança em
  relação ao projeto original, que abria todos os aparelhos de entrada do Mac.)
- **O passo 4 olha sem tocar.** Ele lista o que *seria* afetado, sem enviar nada.
- **Dá para desfazer.** O efeito no mouse some quando ele desconecta. O que for instalado no Mac
  sai inteiro com dois cliques em `Desinstalar.command`.

## Se der errado

**"Não encontrei o mouse agora"** — ele entra em repouso rápido. Mexa nele, ou desligue e ligue o
botão embaixo do mouse, e rode o assistente de novo.

**"O mouse não aceitou a mensagem"** — desligue e ligue o mouse e tente outra vez. O mouse tem
várias interfaces internas e algumas recusam a mensagem; basta uma aceitar.

**Parou de funcionar de novo depois que o Mac dormiu** — é o caso em que vale o passo 6, o ajudante
permanente. Se mesmo assim voltar a falhar, veja a parte do `--heartbeat` no
[`README.md`](../README.md).

**Quero só ver o estado das coisas** — dois cliques não têm para isso, mas o arquivo
`scripts/doctor.sh` mostra tudo (Mac, mouse, o que está instalado) sem mudar nada.

## Desfazer tudo

**Dois cliques em `Desinstalar.command`.** Ele remove o programa e o ajudante. Seu mouse volta a se
comportar como o macOS 27 o deixa — ou seja, provavelmente volta a não funcionar.

## Avise a Apple

Isto é um remendo, não a correção. Quanto mais gente reportar, mais rápido a Apple conserta de
verdade: <https://www.apple.com/feedback/macos.html>

## Créditos

O truque dos 4 bytes foi publicado primeiro em
[o0mohd0o/MagicMouseFix](https://github.com/o0mohd0o/MagicMouseFix). Este projeto deriva de
[oleksandr-antonian/macos27-magic-mouse-fix](https://github.com/oleksandr-antonian/macos27-magic-mouse-fix),
que é a fonte da verdade dos bytes e do formato do ajudante. Ambos são MIT, e o aviso de copyright
original está preservado no [`LICENSE`](../LICENSE). As diferenças estão listadas em
[`upstream-diff.md`](upstream-diff.md).
