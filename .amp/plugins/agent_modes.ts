// @amp-agent-mode key=glm label=GLM-5.2
// @amp-agent-mode key=kimi label=Kimi-K3
//
// Bilimbi custom agent modes.
// Experimental modes powered by GLM-5.2 and Kimi-K3, encoding Bilimbi's
// deep-module boundaries, schema-compatibility rules, and Elixir/Phoenix
// conventions from AGENTS.md and DESIGN.md.

import type { PluginAPI } from '@ampcode/plugin'

export const description =
  'Bilimbi experimental agent modes: GLM-5.2 (general coding via GLM) ' +
  'and Kimi-K3 (large-context coding via Kimi).'

export default function (amp: PluginAPI) {
  amp.logger.log('Bilimbi agent modes plugin initialized')

  // ── GLM-5.2 ─────────────────────────────────────────────────────
  // General coding mode powered by GLM-5.2 (Zhipu). Good for fast,
  // cost-effective Elixir/Phoenix implementation tasks.
  amp.registerAgentMode({
    key: 'glm',
    label: 'GLM-5.2',
    description:
      'General coding mode powered by GLM-5.2. Cost-effective for ' +
      'Elixir/Phoenix implementation, tests, and refactoring within ' +
      'Bilimbi conventions.',
    color: '#3b82f6',
    agent: {
      kind: 'agent-definition',
      name: 'Bilimbi GLM',
      model: 'amp/glm-5.2',
      reasoningEffort: 'high',
      tools: 'all',
      instructions: [
        'You are a coding agent for Bilimbi, the Phoenix/Elixir port of',
        'the Belimbing application platform.',
        '',
        'Follow AGENTS.md and DESIGN.md in the repository root.',
        '',
        'Key conventions:',
        '- Elixir 1.20 / OTP 28 / Phoenix 1.8 / Ecto 3.14 / Tailwind 4.',
        '- Deep modules: hide schemas, queries, and table names behind',
        '  small public APIs. Callers should not know implementation.',
        '- Base must not depend on Core. Core may depend on Base.',
        '- APIs reading/writing tenant-owned data take a',
        '  Bilimbi.Base.Tenancy.Scope, never a raw tenant ID.',
        '- Use verified routes (~p). LiveViews use a Live suffix.',
        '- Assign forms with to_form/1; templates use @form[:field].',
        '- CSS uses semantic roles from the @theme block only.',
        '- Predicates end in ?. No String.to_atom/1 on user input.',
        '- Run mix format and focused tests after changes.',
      ].join('\n'),
      display: { label: 'GLM-5.2', color: '#3b82f6' },
    },
  })

  // ── Kimi-K3 ─────────────────────────────────────────────────────
  // General coding mode powered by Kimi-K3 (Moonshot). Large 350K
  // context window and 128K output — good for cross-module work and
  // long file generation.
  amp.registerAgentMode({
    key: 'kimi',
    label: 'Kimi-K3',
    description:
      'General coding mode powered by Kimi-K3. Large 350K context and ' +
      '128K output for cross-module Bilimbi work, long migrations, and ' +
      'multi-file refactoring.',
    color: '#8b5cf6',
    agent: {
      kind: 'agent-definition',
      name: 'Bilimbi Kimi',
      model: 'fireworks-ai/accounts/fireworks/models/kimi-k3',
      reasoningEffort: 'high',
      tools: 'all',
      instructions: [
        'You are a coding agent for Bilimbi, the Phoenix/Elixir port of',
        'the Belimbing application platform.',
        '',
        'Follow AGENTS.md and DESIGN.md in the repository root.',
        '',
        'Your large context window (350K) and output budget (128K) make',
        'you well-suited for tasks that span many files or produce long',
        'output: cross-module refactoring, multi-table migrations,',
        'comprehensive test suites, and documentation passes.',
        '',
        'Key conventions:',
        '- Elixir 1.20 / OTP 28 / Phoenix 1.8 / Ecto 3.14 / Tailwind 4.',
        '- Deep modules: hide schemas, queries, and table names behind',
        '  small public APIs. Callers should not know implementation.',
        '- Base must not depend on Core. Core may depend on Base.',
        '- APIs reading/writing tenant-owned data take a',
        '  Bilimbi.Base.Tenancy.Scope, never a raw tenant ID.',
        '- Use verified routes (~p). LiveViews use a Live suffix.',
        '- Assign forms with to_form/1; templates use @form[:field].',
        '- CSS uses semantic roles from the @theme block only.',
        '- Predicates end in ?. No String.to_atom/1 on user input.',
        '- Run mix format and focused tests after changes.',
      ].join('\n'),
      display: { label: 'Kimi-K3', color: '#8b5cf6' },
    },
  })
}
