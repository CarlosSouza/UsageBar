# Validação local

18/09/2026, Apple Silicon, Swift 6.4 / Command Line Tools.

- Build de produção concluído via `bash scripts/build-app.sh`.
- `codesign --verify --strict --verbose=2 dist/UsageBar.app`: assinatura ad hoc válida.
- 9 verificações Swift de thresholds, rearme, deduplicação, persistência, cotas Codex, unidades/timestamps Devin e configuração ntfy: passaram.
- 3 testes Python do coletor e instalador Claude, incluindo preservação da configuração existente e reexecução sem recursão: passaram.
- O ambiente só tem Command Line Tools, sem XCTest. As verificações Swift são um executável independente (`UsageCoreChecks`) com precondições, executado em debug.
- A compilação usa caches temporários e omite símbolos de debug no bundle de produção. Não depende de pacotes externos.

Pendente: inspeção visual interativa; leitura autenticada nas contas; permissão de notificações; assinatura do tópico ntfy e teste real de entrega no Mac/iPhone/Watch. Nenhuma credencial foi inserida nos arquivos do projeto.

## Multi-auth integration, 2026-10-06

- Release builds of UsageBar and UsageBarWidget passed using `TMPDIR="$PWD/.build/packaging" bash scripts/build-app.sh`. Build caches stayed inside the project.
- The 11 existing UsageCore checks and 7 multi-auth checks passed. Multi-auth checks cover versioned JSON, quota timestamps, unknown and unauthorized quotas, zero-based to one-based indices, switch and unpin commands, changed account labels, command failures, timeouts, and bounded output. Commands were tested against a local mock executable.
- `UsageCoreChecks --check-installed-multi-auth` decoded the installed CLI's cached limits response: schema 1, two accounts, two selected-account windows. It did not switch accounts or request live quota refreshes.
- App and widget ad hoc signatures passed `codesign --verify --strict --verbose=2`.
- Verification was manual against command output and the diff. Interactive visual inspection, a real account switch, and updates in an already-running desktop/router session remain unverified.
- The release build and all 18 checks passed again before installation. The app was copied from `dist/UsageBar.app` to `/Applications/UsageBar.app` and relaunched. Recursive file comparison found no differences, and the installed app and widget passed `codesign --verify --deep --strict --verbose=2`.
