# Pesquisa de integrações — 18/09/2026

## Claude e referência claudebar

O claudebar lê credenciais OAuth do Claude Code, renova o token e consulta `https://api.anthropic.com/api/oauth/usage`. O próprio projeto identifica esse endpoint como não documentado e recomenda intervalo mínimo de 300 segundos por causa de HTTP 429. É referência de produto, mas não contrato estável de integração. [Repositório](https://github.com/mryll/claudebar)

**Caminho recomendado:** a documentação oficial de Claude Code agora disponibiliza `rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage` e `resets_at` (epoch em segundos) no JSON enviado ao script de statusline. Requer v2.1.251+, assinatura Pro/Max e a primeira resposta da sessão. Cada janela pode estar ausente e desaparece após seu reset. O script pode exportar somente essas métricas para arquivo local consumido pelo app. Essa arquitetura é uma inferência nossa sobre a interface documentada. Ela depende de sessões ativas para receber novos dados; campo ausente ou dado antigo deve aparecer como indisponível/desatualizado, nunca 0%. [Statusline oficial](https://code.claude.com/docs/en/statusline#rate-limit-usage)

Não usar `context_window.used_percentage` como consumo da assinatura: é contexto da conversa. Também não confundir custos estimados por sessão com orçamento real. [Campos oficiais](https://code.claude.com/docs/en/statusline#available-data)

A API administrativa pública de uso/custo mede API da organização, exige credencial administrativa e não está disponível para contas individuais. Ela não substitui os limites Pro/Max. [Usage and Cost API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api)

As instruções atuais da Anthropic reservam OAuth ao uso nativo e restringem coleta/intermediação de credenciais Claude.ai em aplicativos de terceiros. Isso reforça a preferência técnica por exportação local de métricas da interface oficial. [Autenticação e credenciais](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)

## Devin

**Integração oficial viável para Enterprise:** `GET https://api.devin.ai/v3/organizations/{org_id}/consumption/daily`, Bearer de service user `cog_`, permissão `ViewOrgConsumption`. Query: `time_after`/`time_before`; resposta: `total_acus`, `consumption_by_date`, `acus_by_product`. A página declara explicitamente que relatórios de consumo por API são exclusivos para organizações Enterprise. Fronteira do dia de cobrança: 08:00 UTC. Para calcular porcentagem, configurar orçamento ACU e início/fim do ciclo; consumo absoluto sem denominador não define percentual. [API oficial](https://docs.devin.ai/api-reference/v3/consumption/organizations-consumption-daily)

Existe equivalente Enterprise agregado: `GET /v3/enterprise/consumption/daily`. [API agregada](https://docs.devin.ai/api-reference/v3/consumption/consumption-daily)

Self-serve usa cota inclusa e créditos pré-pagos; visualiza uso do mês/cota/saldo em Settings > Plans. Não encontramos endpoint público documentado equivalente para essa modalidade. Não prometer captura automática compatível com qualquer plano; implementar estado explicativo ou importação manual até confirmar a conta do usuário. [Guia de uso](https://docs.devin.ai/admin/billing/usage)

**Atualização após pesquisa no código:** o CodexBar implementa leitura do painel por `GET https://app.devin.ai/api/<internal-org-id>/billing/quota/usage`, Bearer da sessão e `x-cog-org-id`. O UsageBar inclui um adaptador experimental dessa interface, com configuração manual e armazenamento no Chaves, sem importar sessões do navegador. Os campos diários/semanais e timestamps precisam existir para o app exibir métricas. Os campos de percentual são usados diretamente, sem multiplicar por 100. A compatibilidade com a conta do usuário não foi validada. [Documentação do adaptador](https://github.com/steipete/CodexBar/blob/main/docs/devin.md), [schema observado no código](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Devin/DevinUsageSnapshot.swift)

## Codex

O app usa o protocolo documentado de `codex app-server`, inicializa a conexão e consulta somente `account/rateLimits/read`. `rateLimitsByLimitId` permite várias cotas; cada janela informa `usedPercent`, `windowDurationMins` e `resetsAt`. O fallback `rateLimits` serve para versões anteriores. Não inicia conversas nem solicita inferência. [Documentação oficial OpenAI](https://developers.openai.com/pt-BR/docs/app-server)

## Notificações macOS, iPhone, Apple Watch

**Implementação atual:** notificação local no Mac + ntfy para iPhone/Watch. O app publica JSON por HTTPS com `topic`, `title`, `message` e prioridade padrão. O servidor é configurável, o access token opcional fica no Chaves e redirecionamentos são recusados para não encaminhar a credencial a outro host. [API de publicação ntfy](https://docs.ntfy.sh/publish/)

O ntfy possui cliente iOS aberto. No servidor público sem ACL, o tópico é a senha; por isso o UsageBar gera um nome aleatório longo e permite substituí-lo. No app iOS, informe separadamente o servidor (`https://ntfy.sh`) e o tópico. Como alternativa, a assinatura pode ser feita pelo app web em `https://ntfy.sh/app`. [Cliente para telefone](https://docs.ntfy.sh/subscribe/phone/), [app web](https://docs.ntfy.sh/subscribe/web/), [escolha do tópico](https://docs.ntfy.sh/publish/#picking-a-topic)

**Limite importante do requisito:** notificações espelhadas normalmente aparecem no iPhone OU no Watch. iPhone desbloqueado recebe o alerta; Watch recebe quando está desbloqueado/no pulso e iPhone está bloqueado, conforme configuração. Portanto podemos suportar ambos os dispositivos, mas não prometer vibração simultânea. [Apple](https://support.apple.com/en-us/108369)

Alternativa totalmente própria: app iOS complementar com registro de token APNs e serviço emissor autenticado, mais espelhamento/cliente Watch. Exige provisionamento, capability de push e gestão de tokens. O processo emissor poderia rodar no Mac pessoal; serviço sempre disponível seria necessário para coleta e alertas quando o Mac estiver desligado. Esta última escolha é inferência arquitetural. [Registro APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns), [Servidor APNs](https://developer.apple.com/documentation/UserNotifications/setting-up-a-remote-notification-server)

## Regras propostas para o app

Threshold global com override por provedor/janela; alertar ao atingir ou cruzar 90%; persistir deduplicação por janela de reset; rearme no próximo ciclo; jamais alertar com dado vencido; botão explícito de teste; mostrar última coleta e origem. Essas são decisões propostas de implementação, não limitações das APIs.
