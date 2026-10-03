# Module LiveView hooks

A mounted Base, Core, Domain, or Extension module may ship a colocated hook
beside its LiveView or function component. The host compiles the selected
composition and bundles these hooks into its ordinary static JavaScript asset.
No host import list, runtime script registration, or CSP change is needed.

Use the module's descriptor namespace for the declaring Elixir module and a
local dot-prefixed hook name:

```heex
<div id="location-capture" phx-hook=".LocationCapture">...</div>
<script :type={Phoenix.LiveView.ColocatedHook} name=".LocationCapture">
  export default {
    mounted() {
      // Bind the module's browser behavior here.
    }
  }
</script>
```

Phoenix resolves `.LocationCapture` to
`Bilimbi.Domain.People.Attendance.Web.ClockLive.LocationCapture` when that is
the declaring module. Both the declaration and `phx-hook` use the local name;
when sharing a hook across components, use the fully qualified name on the
consumer. Local names may repeat in different declaring modules. A fully
qualified name must be unique, including across multiple render functions in
one component. The build fails with the name and contributing owners on a
clash. Hook declarations outside the owner's descriptor namespace also fail.
Use a stable descriptive declaring module and hook name; never manufacture
names from source paths or numeric module IDs.

The host's final `:bilimbi_hooks` compiler reads the validated graph and compiled
HEEx metadata after dependencies and the host compile. It intersects each
compiled application's module list with that application's extracted
`phoenix-colocated` directories before loading hook metadata, so unmounted files
and modules without extracted assets are not loaded. It imports the selected
hook files into `_build/<env>/bilimbi-hooks/index.js`. `app.js` consumes that
entry via the existing build-path `NODE_PATH`. The adapter is
[`module_hooks.exs`](module_hooks.exs); its comment records the pinned LiveView
metadata contract. There is no extra descriptor field or install registry.
Colocated hook extraction happens when HEEx compiles, so authors do not need
to add a hook manifest compiler to their module's Mix project.

Run `mix assets.build` or `mix assets.deploy` from `apps/web` after changing the
mounted set. Both compile first. Development's normal compilation updates the
entry when a component changes, and the existing esbuild watcher rebuilds it.
Mounting or unmounting changes Mix dependencies and the development reloadable
application list; restart your own development server after fetching the new
composition dependencies. Stale files from an unmounted module may remain in
`_build`, but the collector never selects them. An already deployed bundle
changes only with the next build and deployment.

Do not add `runtime` to a colocated hook or inject ordinary inline scripts.
Phoenix removes the compile-time hook declaration from rendered HTML; its code
ships only through the static bundle under the host's existing `script-src
'self'` policy. Hooks are trusted selected source, just like server code.

The fixtures under `test/fixtures/module_hooks/` provide a mounted browser
probe, a same-local-name Extension hook, and an intentional duplicate. The
focused test compiles their real HEEx and executes an esbuild bundle, then
rebuilds after unmount while retaining extracted files. Run it with:

```bash
cd apps/web
mix test test/bilimbi_web/module_hooks_test.exs
```
