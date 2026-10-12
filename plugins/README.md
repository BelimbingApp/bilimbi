# Bilimbi Codex plugin marketplace

[`.agents/plugins/marketplace.json`](../.agents/plugins/marketplace.json) is
the repository's plugin catalog, named `bilimbi-local` and displayed as
**Bilimbi**. It points to `./plugins/bilimbi`, relative to the repository
root. That plugin holds `.codex-plugin/plugin.json`, `skills/`, and an ignored
`bin/` directory for the built native program. Another harness's manifest,
such as `.claude-plugin/`, could sit beside `.codex-plugin/` and share the
same skills and program.

## With a Bilimbi checkout

Build the program from `clients/bilimbi-cli` and place it in
`plugins/bilimbi/bin/` as described in the
[build guide](../clients/bilimbi-cli/README.md#build-and-verify). Open the
checkout as a trusted project in Codex desktop, then restart the app. Codex
reads the repository marketplace automatically: open **Plugins > Personal**,
find **Bilimbi**, and click **+** to install.

## Without the repository

1. Get the release package for your platform from Bilimbi CI's **Native
   client** artifact (for example, `bilimbi-windows-amd64.zip`). Extract it
   into a permanent folder, keeping `.agents/` and `plugins/bilimbi/`, which
   contains the program.
2. With the Codex CLI installed, register the extracted root folder:

   ```sh
   codex plugin marketplace add "<extracted-folder>"
   ```

3. Restart Codex desktop, open **Plugins > Personal > Bilimbi**, and click
   **+** to install. Start a new conversation to use the plugin.

The [official OpenAI plugin documentation](https://developers.openai.com/plugins/build/plugins#add-a-marketplace-from-the-cli)
documents local-folder registration through the CLI; it does not confirm a
local-folder option for the desktop Plugins **Add** button.

See the [native client README](../clients/bilimbi-cli/README.md) for the full
installation walk-through, sign-in, and command reference.
