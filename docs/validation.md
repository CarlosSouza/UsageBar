# Validação local

18/09/2026, Apple Silicon, Swift 6.4 / Command Line Tools.

- Build de produção concluído via `bash scripts/build-app.sh`.
- `codesign --verify --strict --verbose=2 dist/UsageBar.app`: assinatura ad hoc válida.
- 9 verificações Swift de thresholds, rearme, deduplicação, persistência, cotas Codex, unidades/timestamps Devin e configuração ntfy: passaram.
- 3 testes Python do coletor e instalador Claude, incluindo preservação da configuração existente e reexecução sem recursão: passaram.
- O ambiente só tem Command Line Tools, sem XCTest. As verificações Swift são um executável independente (`UsageCoreChecks`) com precondições, executado em debug.
- A compilação usa caches temporários e omite símbolos de debug no bundle de produção. Não depende de pacotes externos.

Pendente: inspeção visual interativa; leitura autenticada nas contas; permissão de notificações; assinatura do tópico ntfy e teste real de entrega no Mac/iPhone/Watch. Nenhuma credencial foi inserida nos arquivos do projeto.
