# UsageBar

App nativo de barra de menus para macOS 14+, em SwiftUI. Monitora limites de assinaturas de Claude, Codex e, experimentalmente, Devin. Não mede gastos das APIs.

## Executar

```sh
git clone https://github.com/CarlosSouza/UsageBar.git
cd UsageBar
bash scripts/build-app.sh
open dist/UsageBar.app
```

O script gera um `.app` com assinatura ad hoc para uso local, sem instalar em Aplicativos. Para distribuir a outras pessoas, faltam assinatura Developer ID e notarização. Requer Command Line Tools / Swift 6. O app roda enquanto estiver aberto e o Mac estiver acordado e conectado; não há monitoramento em servidor.

## Claude

Requer Claude Code v2.1.251+ com assinatura que exponha `rate_limits` na statusline (documentado para Pro/Max). Após conectar, os dados aparecem depois de uma resposta do assistente.

```sh
/usr/bin/python3 scripts/connect-claude.py
```

O instalador faz backup de `~/.claude/settings.json`, preserva outras preferências e encadeia o comando de statusline anterior. Ele não é executado automaticamente pelo build. Reinicie sua sessão do Claude Code após instalar. Se houver configuração de statusline específica do projeto, ela pode sobrepor a configuração global.

Apenas percentual, renovação e horário de observação são exportados para `~/Library/Application Support/UsageBar/claude.json`; prompts e respostas não são armazenados. O UsageBar lê o arquivo a cada 30 segundos. Reexecuções com métricas idênticas preservam o horário anterior: após 15 minutos sem mudança os dados são conservadoramente considerados antigos. Dados ausentes ou antigos não viram zero nem geram novos alertas. Uso feito fora do Claude Code só será observado quando o CLI atualizar seus limites.

Para desfazer: restaure apenas `statusLine` do backup e remova os scripts de `~/Library/Application Support/UsageBar/`; preserve mudanças posteriores em outras preferências.

## Codex

Faça login no Codex CLI com sua assinatura ChatGPT e confira o caminho do executável em Ajustes. O app usa `codex app-server` e `account/rateLimits/read` a cada 5 minutos, com todas as janelas retornadas. Não abre conversas, não envia prompts e não lê tokens de autenticação diretamente. Login por API key pode não retornar cotas da assinatura.

## Devin (experimental)

A API pública de consumo exige Enterprise. Este adaptador usa o endpoint não documentado do painel web, também identificado no código do CodexBar. A compatibilidade com sua conta Core/básica precisa ser confirmada; nenhum saldo de ACUs é convertido artificialmente em percentual.

1. Entre em `https://app.devin.ai/` e abra Usage & Limits da organização.
2. No inspetor do navegador, aba Network, localize a requisição bem-sucedida que termina em `/billing/quota/usage`.
3. Copie **somente para os ajustes locais do UsageBar** o Bearer token de `Authorization` e o ID interno `x-cog-org-id` (`org_…` ou `org-…`). Não envie esses valores no chat.
4. Esta versão lê `daily_percentage`, `weekly_percentage`, `daily_reset_at` e `weekly_reset_at`. Os percentuais são usados diretamente: `100` significa 100%, `1` significa 1%. A antiga opção de fração foi removida e sua preferência salva é ignorada.
5. Salve a sessão, ative o monitor e compare com o painel antes de habilitar os alertas.

O token fica no Chaves, é enviado somente a `https://app.devin.ai`, e redirecionamentos são recusados. A sessão não é renovada automaticamente; será necessário substituí-la quando expirar. Não há varredura de cookies do navegador. Planos sem essas cotas ou mudanças no endpoint aparecem como erro, não como consumo zero. Atualização a cada 5 minutos.

## Exportação local (codex.json e devin.json)

Além do `claude.json`, o app grava `~/Library/Application Support/UsageBar/codex.json` e `devin.json` a cada leitura (a cada 5 minutos, quando o provedor está habilitado): `observed_at`, `windows[]` com `id`, `title`, `usedPercent`, `resetsAt`, `observedAt` (epoch em segundos) e `error`. Só métricas, nenhum token. Scripts locais podem ler esses arquivos em vez de guardar credenciais.

## Alertas

Cada provedor tem threshold de 1–100%, inicialmente 90%. Um alerta é enviado quando uma leitura válida atinge ou ultrapassa o threshold, inclusive se a primeira leitura já estiver acima. O controle por provedor, janela, renovação e canal persiste entre execuções. Alterar o threshold não reenvia uma janela já notificada. Falhas de entrega tentam novamente após 5 minutos enquanto a métrica permanecer recente; timeouts de rede podem causar duplicação se o servidor tiver aceitado a mensagem.

- **macOS:** em Ajustes, use “Permitir notificações”, habilite o canal e teste. O sistema pode silenciar banners conforme Foco e preferências.
- **iPhone/Apple Watch:** instale o [ntfy para iOS](https://docs.ntfy.sh/subscribe/phone/). No ntfy, adicione uma assinatura preenchendo separadamente `Servidor = https://ntfy.sh` e `Tópico = usagebar_...`; não cole a URL inteira no campo de tópico. Depois salve a configuração no UsageBar, teste e habilite o canal. Servidores próprios HTTPS também são aceitos.
- No servidor público, o nome aleatório do tópico funciona como senha. Mantenha-o privado ou configure um access token em um tópico protegido. O UsageBar guarda o token opcional no Chaves e envia ao ntfy apenas o texto do alerta.
- Habilite o espelhamento de notificações do ntfy no Watch. O sistema Apple normalmente entrega ao iPhone **ou** ao Watch conforme uso/bloqueio, sem garantir dois alertas simultâneos.

As notificações vêm desativadas até a configuração. A aceitação de um envio pelo sistema/ntfy não prova que o dispositivo exibiu o alerta. O Mac precisa estar ligado, conectado e com o UsageBar aberto.

## Verificação

```sh
CLANG_MODULE_CACHE_PATH=/private/tmp/usagebar-clang SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/usagebar-modules swift run --scratch-path /private/tmp/usagebar-build --cache-path /private/tmp/usagebar-cache --disable-sandbox UsageCoreChecks
/usr/bin/python3 -m unittest discover -s tests -p 'test_*.py'
```

Testes cobrem thresholds, renovação, deduplicação persistente por canal, dados antigos/ausentes e parsing. Validação de login real e entrega nos dispositivos depende da configuração das contas.

## Fontes

- [Claudebar, referência funcional](https://github.com/mryll/claudebar)
- [Claude Code: statusline e rate limits](https://code.claude.com/docs/en/statusline#rate-limit-usage)
- [Documentação oficial OpenAI: Codex App Server](https://developers.openai.com/pt-BR/docs/app-server)
- [Devin: API Enterprise de consumo](https://docs.devin.ai/api-reference/v3/consumption/organizations-consumption-daily)
- [CodexBar: integração web do Devin](https://github.com/steipete/CodexBar/blob/main/docs/devin.md)
- [ntfy: publicação por HTTP](https://docs.ntfy.sh/publish/)
- [ntfy para iPhone](https://docs.ntfy.sh/subscribe/phone/)
- [Apple: notificações no Watch](https://support.apple.com/en-us/108369)
